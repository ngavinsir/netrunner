const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len < 3) {
        std.debug.print("usage: {s} <test-binary> <shard-count> [test-runner-args...]\n", .{args[0]});
        std.process.exit(1);
    }

    const test_binary = args[1];
    const shard_count = std.fmt.parseUnsigned(usize, args[2], 10) catch {
        std.debug.print("invalid shard count: {s}\n", .{args[2]});
        std.process.exit(1);
    };
    if (shard_count == 0) {
        std.debug.print("shard count must be greater than zero\n", .{});
        std.process.exit(1);
    }

    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    const queue_name = try std.fmt.allocPrint(allocator, "test-sharded-{d}", .{std.time.microTimestamp()});
    const queue_dir = try std.fs.path.join(allocator, &.{ cwd_path, "zig-cache", queue_name });
    std.fs.makeDirAbsolute(queue_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const process_env = try std.process.getEnvMap(allocator);
    const shard_total_text = try std.fmt.allocPrint(allocator, "{d}", .{shard_count});
    const forwarded_args = args[3..];

    const children = try allocator.alloc(std.process.Child, shard_count);
    var started_count: usize = 0;
    errdefer {
        for (children[0..started_count]) |*child| {
            _ = child.kill() catch {};
        }
    }

    for (0..shard_count) |shard_index| {
        const shard_index_text = try std.fmt.allocPrint(allocator, "{d}", .{shard_index});
        const child_argv = try allocator.alloc([]const u8, 1 + forwarded_args.len);
        child_argv[0] = test_binary;
        @memcpy(child_argv[1..], forwarded_args);

        children[shard_index] = std.process.Child.init(child_argv, allocator);
        children[shard_index].cwd = cwd_path;
        children[shard_index].stdin_behavior = .Ignore;
        children[shard_index].stdout_behavior = .Inherit;
        children[shard_index].stderr_behavior = .Inherit;

        const env_map = try allocator.create(std.process.EnvMap);
        env_map.* = try cloneEnvMap(allocator, &process_env);
        try env_map.put("NETRUNNER_TEST_TOTAL", shard_total_text);
        try env_map.put("NETRUNNER_TEST_INDEX", shard_index_text);
        try env_map.put("NETRUNNER_TEST_QUEUE_DIR", queue_dir);
        children[shard_index].env_map = env_map;

        try children[shard_index].spawn();
        started_count += 1;
    }

    var exit_code: u8 = 0;
    for (children[0..started_count]) |*child| {
        const term = try child.wait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) exit_code = 1;
            },
            else => exit_code = 1,
        }
    }

    if (exit_code != 0) std.process.exit(exit_code);
}

fn cloneEnvMap(allocator: std.mem.Allocator, src: *const std.process.EnvMap) !std.process.EnvMap {
    var cloned = std.process.EnvMap.init(allocator);
    var it = src.hash_map.iterator();
    while (it.next()) |entry| {
        try cloned.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    return cloned;
}
