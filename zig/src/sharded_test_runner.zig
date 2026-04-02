const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

pub const std_options: std.Options = .{
    .logFn = log,
};

var log_err_count: usize = 0;
const queue_file_name = "next-index";
const queue_lock_name = "next-index.lock";

pub fn main() void {
    @disableInstrumentation();

    const args = std.process.argsAlloc(std.heap.page_allocator) catch
        @panic("unable to parse command line args");
    defer std.process.argsFree(std.heap.page_allocator, args);

    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--seed=")) {
            testing.random_seed = std.fmt.parseUnsigned(u32, arg["--seed=".len..], 0) catch
                @panic("unable to parse --seed command line argument");
        } else if (std.mem.startsWith(u8, arg, "--cache-dir=")) {
            // Accepted for compatibility with Zig's default test runner.
        } else {
            @panic("unrecognized command line argument");
        }
    }

    mainTerminal();
}

fn mainTerminal() void {
    @disableInstrumentation();

    const shard_total = readShardEnv("NETRUNNER_TEST_TOTAL") orelse 1;
    const shard_index = readShardEnv("NETRUNNER_TEST_INDEX") orelse 0;
    const queue_dir = readShardPathEnv("NETRUNNER_TEST_QUEUE_DIR");
    if (shard_total == 0) @panic("NETRUNNER_TEST_TOTAL must be greater than zero");
    if (shard_index >= shard_total) @panic("NETRUNNER_TEST_INDEX must be less than NETRUNNER_TEST_TOTAL");

    const test_fn_list = builtin.test_functions;
    const ordered_indices = buildExecutionOrder(std.heap.page_allocator, test_fn_list) catch
        @panic("unable to build test execution order");
    defer std.heap.page_allocator.free(ordered_indices);
    const striped_count = initialStripedCount(ordered_indices.len, shard_total);
    var striped_cursor = shard_index;
    const shard_start_ns = std.time.nanoTimestamp();

    var ok_count: usize = 0;
    var skip_count: usize = 0;
    var fail_count: usize = 0;
    var fuzz_count: usize = 0;
    var leaks: usize = 0;
    var total_log_err_count: usize = 0;
    var processed_count: usize = 0;
    const have_tty = std.fs.File.stderr().isTty();

    while (claimScheduledIndex(queue_dir, shard_total, &striped_cursor, striped_count, ordered_indices.len)) |ordered_index| {
        const global_index = ordered_indices[ordered_index];
        const test_fn = test_fn_list[global_index];
        processed_count += 1;

        testing.allocator_instance = .{};
        testing.log_level = .warn;
        log_err_count = 0;
        is_fuzz_test = false;

        if (!have_tty) {
            std.debug.print(
                "[shard {d}/{d}] {d} {s}...",
                .{ shard_index + 1, shard_total, processed_count, test_fn.name },
            );
        }

        if (test_fn.func()) |_| {
            ok_count += 1;
            if (!have_tty) std.debug.print("OK\n", .{});
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip_count += 1;
                if (have_tty) {
                    std.debug.print(
                        "[shard {d}/{d}] {d} {s}...SKIP\n",
                        .{ shard_index + 1, shard_total, processed_count, test_fn.name },
                    );
                } else {
                    std.debug.print("SKIP\n", .{});
                }
            },
            else => {
                fail_count += 1;
                if (have_tty) {
                    std.debug.print(
                        "[shard {d}/{d}] {d} {s}...FAIL ({s})\n",
                        .{ shard_index + 1, shard_total, processed_count, test_fn.name, @errorName(err) },
                    );
                } else {
                    std.debug.print("FAIL ({s})\n", .{@errorName(err)});
                }
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            },
        }

        if (testing.allocator_instance.deinit() == .leak) {
            leaks += 1;
        }
        total_log_err_count += log_err_count;
        fuzz_count += @intFromBool(is_fuzz_test);
    }

    const elapsed_ms = @divFloor(std.time.nanoTimestamp() - shard_start_ns, std.time.ns_per_ms);
    if (ok_count == processed_count) {
        std.debug.print(
            "[shard {d}/{d}] All {d} claimed tests passed in {d}ms.\n",
            .{ shard_index + 1, shard_total, ok_count, elapsed_ms },
        );
    } else {
        std.debug.print(
            "[shard {d}/{d}] {d} passed; {d} skipped; {d} failed in {d}ms.\n",
            .{
                shard_index + 1,
                shard_total,
                ok_count,
                skip_count,
                fail_count,
                elapsed_ms,
            },
        );
    }
    if (total_log_err_count != 0) {
        std.debug.print("[shard {d}/{d}] {d} errors were logged.\n", .{ shard_index + 1, shard_total, total_log_err_count });
    }
    if (leaks != 0) {
        std.debug.print("[shard {d}/{d}] {d} tests leaked memory.\n", .{ shard_index + 1, shard_total, leaks });
    }
    if (fuzz_count != 0) {
        std.debug.print("[shard {d}/{d}] {d} fuzz tests found.\n", .{ shard_index + 1, shard_total, fuzz_count });
    }
    if (leaks != 0 or total_log_err_count != 0 or fail_count != 0) {
        std.process.exit(1);
    }
}

fn readShardEnv(name: []const u8) ?usize {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => @panic("unable to read shard environment variable"),
    };
    defer std.heap.page_allocator.free(value);

    return std.fmt.parseUnsigned(usize, value, 10) catch
        @panic("unable to parse shard environment variable");
}

fn readShardPathEnv(name: []const u8) ?[]u8 {
    return std.process.getEnvVarOwned(std.heap.page_allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => @panic("unable to read shard path environment variable"),
    };
}

fn claimScheduledIndex(
    queue_dir: ?[]const u8,
    shard_total: usize,
    striped_cursor: *usize,
    striped_count: usize,
    total_tests: usize,
) ?usize {
    if (claimStripedIndex(striped_cursor, striped_count, shard_total)) |ordered_index| {
        return ordered_index;
    }
    return claimQueuedIndex(queue_dir, striped_count, total_tests);
}

fn claimStripedIndex(striped_cursor: *usize, striped_count: usize, shard_total: usize) ?usize {
    const ordered_index = striped_cursor.*;
    if (ordered_index >= striped_count) return null;
    striped_cursor.* += shard_total;
    return ordered_index;
}

fn claimQueuedIndex(queue_dir: ?[]const u8, start_index: usize, total_tests: usize) ?usize {
    const dir_path = queue_dir orelse return claimLocalTestIndex(start_index, total_tests);
    ensureQueueDir(dir_path) catch @panic("unable to create test queue directory");

    const lock_file = openQueueLockFile(dir_path) catch @panic("unable to open test queue lock");
    defer lock_file.close();
    lock_file.lock(.exclusive) catch @panic("unable to lock test queue");
    defer lock_file.unlock();

    const next_index = readNextIndex(dir_path, start_index) catch @panic("unable to read test queue");
    if (next_index >= total_tests) return null;

    writeNextIndex(dir_path, next_index + 1) catch @panic("unable to update test queue");
    return next_index;
}

fn claimLocalTestIndex(start_index: usize, total_tests: usize) ?usize {
    if (local_next_index == 0) local_next_index = start_index;
    if (local_next_index >= total_tests) return null;
    local_next_index += 1;
    return local_next_index - 1;
}

fn buildExecutionOrder(allocator: std.mem.Allocator, test_fn_list: []const std.builtin.TestFn) ![]usize {
    const order = try allocator.alloc(usize, test_fn_list.len);
    for (order, 0..) |*slot, index| slot.* = index;
    std.mem.sortUnstable(usize, order, test_fn_list, orderLessThan);
    return order;
}

fn orderLessThan(test_fn_list: []const std.builtin.TestFn, lhs_index: usize, rhs_index: usize) bool {
    const lhs_name = test_fn_list[lhs_index].name;
    const rhs_name = test_fn_list[rhs_index].name;
    const lhs_priority = testPriority(lhs_name);
    const rhs_priority = testPriority(rhs_name);
    if (lhs_priority != rhs_priority) return lhs_priority < rhs_priority;
    return lhs_index < rhs_index;
}

fn testPriority(name: []const u8) u8 {
    if (std.mem.indexOf(u8, name, "engine.parity.test.e2e ")) |_| return 0;
    if (std.mem.indexOf(u8, name, "engine.parity.test.")) |_| return 1;
    if (std.mem.indexOf(u8, name, "engine.game.test.")) |_| return 2;
    return 3;
}

fn initialStripedCount(total_tests: usize, shard_total: usize) usize {
    const warmup_per_shard: usize = 8;
    return @min(total_tests, shard_total * warmup_per_shard);
}

fn ensureQueueDir(dir_path: []const u8) !void {
    if (std.fs.path.isAbsolute(dir_path)) {
        std.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        return;
    }
    try std.fs.cwd().makePath(dir_path);
}

fn openQueueLockFile(dir_path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(dir_path)) {
        const lock_path = try std.fs.path.join(std.heap.page_allocator, &.{ dir_path, queue_lock_name });
        defer std.heap.page_allocator.free(lock_path);
        return try std.fs.createFileAbsolute(lock_path, .{
            .read = true,
            .exclusive = false,
            .truncate = false,
        });
    }

    var dir = try std.fs.cwd().openDir(dir_path, .{});
    defer dir.close();
    return try dir.createFile(queue_lock_name, .{
        .read = true,
        .exclusive = false,
        .truncate = false,
    });
}

fn readNextIndex(dir_path: []const u8, default_index: usize) !usize {
    if (std.fs.path.isAbsolute(dir_path)) {
        const file_path = try std.fs.path.join(std.heap.page_allocator, &.{ dir_path, queue_file_name });
        defer std.heap.page_allocator.free(file_path);

        const file = std.fs.openFileAbsolute(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return default_index,
            else => return err,
        };
        defer file.close();

        const bytes = try file.readToEndAlloc(std.heap.page_allocator, 64);
        defer std.heap.page_allocator.free(bytes);
        return std.fmt.parseUnsigned(usize, std.mem.trim(u8, bytes, " \t\r\n"), 10) catch default_index;
    }

    var dir = try std.fs.cwd().openDir(dir_path, .{});
    defer dir.close();

    const bytes = dir.readFileAlloc(std.heap.page_allocator, queue_file_name, 64) catch |err| switch (err) {
        error.FileNotFound => return default_index,
        else => return err,
    };
    defer std.heap.page_allocator.free(bytes);

    return std.fmt.parseUnsigned(usize, std.mem.trim(u8, bytes, " \t\r\n"), 10) catch default_index;
}

fn writeNextIndex(dir_path: []const u8, next_index: usize) !void {
    var buf: [32]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, "{d}\n", .{next_index});

    if (std.fs.path.isAbsolute(dir_path)) {
        const file_path = try std.fs.path.join(std.heap.page_allocator, &.{ dir_path, queue_file_name });
        defer std.heap.page_allocator.free(file_path);

        const file = try std.fs.createFileAbsolute(file_path, .{
            .truncate = true,
        });
        defer file.close();
        try file.writeAll(text);
        return;
    }

    var dir = try std.fs.cwd().openDir(dir_path, .{});
    defer dir.close();
    try dir.writeFile(.{
        .sub_path = queue_file_name,
        .data = text,
    });
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    @disableInstrumentation();
    if (@intFromEnum(message_level) <= @intFromEnum(std.log.Level.err)) {
        log_err_count +|= 1;
    }
    if (@intFromEnum(message_level) <= @intFromEnum(testing.log_level)) {
        std.debug.print(
            "[" ++ @tagName(scope) ++ "] (" ++ @tagName(message_level) ++ "): " ++ format ++ "\n",
            args,
        );
    }
}

var is_fuzz_test = false;
var local_next_index: usize = 0;
