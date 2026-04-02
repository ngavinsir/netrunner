const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

pub const std_options: std.Options = .{
    .logFn = log,
};

var log_err_count: usize = 0;

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
    if (shard_total == 0) @panic("NETRUNNER_TEST_TOTAL must be greater than zero");
    if (shard_index >= shard_total) @panic("NETRUNNER_TEST_INDEX must be less than NETRUNNER_TEST_TOTAL");

    const test_fn_list = builtin.test_functions;
    const selected_total = countSelectedTests(test_fn_list, shard_total, shard_index);

    var ok_count: usize = 0;
    var skip_count: usize = 0;
    var fail_count: usize = 0;
    var fuzz_count: usize = 0;
    var leaks: usize = 0;
    var total_log_err_count: usize = 0;
    var selected_index: usize = 0;
    const have_tty = std.fs.File.stderr().isTty();

    for (test_fn_list, 0..) |test_fn, global_index| {
        if (!belongsToShard(global_index, shard_total, shard_index)) continue;
        selected_index += 1;

        testing.allocator_instance = .{};
        testing.log_level = .warn;
        log_err_count = 0;
        is_fuzz_test = false;

        if (!have_tty) {
            std.debug.print(
                "[shard {d}/{d}] {d}/{d} {s}...",
                .{ shard_index + 1, shard_total, selected_index, selected_total, test_fn.name },
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
                        "[shard {d}/{d}] {d}/{d} {s}...SKIP\n",
                        .{ shard_index + 1, shard_total, selected_index, selected_total, test_fn.name },
                    );
                } else {
                    std.debug.print("SKIP\n", .{});
                }
            },
            else => {
                fail_count += 1;
                if (have_tty) {
                    std.debug.print(
                        "[shard {d}/{d}] {d}/{d} {s}...FAIL ({s})\n",
                        .{ shard_index + 1, shard_total, selected_index, selected_total, test_fn.name, @errorName(err) },
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

    if (ok_count == selected_total) {
        std.debug.print(
            "[shard {d}/{d}] All {d} tests passed.\n",
            .{ shard_index + 1, shard_total, ok_count },
        );
    } else {
        std.debug.print(
            "[shard {d}/{d}] {d} passed; {d} skipped; {d} failed.\n",
            .{ shard_index + 1, shard_total, ok_count, skip_count, fail_count },
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

fn belongsToShard(global_index: usize, shard_total: usize, shard_index: usize) bool {
    return global_index % shard_total == shard_index;
}

fn countSelectedTests(test_fn_list: anytype, shard_total: usize, shard_index: usize) usize {
    var count: usize = 0;
    for (test_fn_list, 0..) |_, global_index| {
        if (belongsToShard(global_index, shard_total, shard_index)) count += 1;
    }
    return count;
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
