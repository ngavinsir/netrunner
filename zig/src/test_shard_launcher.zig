const std = @import("std");

const oracle_dir_name = ".netrunner-oracle";
const oracle_socket_name = "o.sock";
const oracle_pid_name = "oracle.pid";
const shared_oracle_socket_env = "NETRUNNER_SHARED_ORACLE_SOCKET";

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
    // Find repo root by looking for project.clj (Clojure project marker)
    const repo_root = try findRepoRoot(allocator, cwd_path);
    const queue_name = try std.fmt.allocPrint(allocator, "test-sharded-{d}", .{std.time.microTimestamp()});
    const queue_dir = try std.fs.path.join(allocator, &.{ cwd_path, "zig-cache", queue_name });
    std.fs.makeDirAbsolute(queue_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Start a single shared oracle process for all shards
    const socket_path = try resolveSocketPath(allocator);
    const pid_path = try siblingPath(allocator, socket_path, oracle_pid_name);
    var oracle_process = try spawnOracle(allocator, repo_root, socket_path, pid_path);
    defer {
        _ = oracle_process.kill() catch {};
        _ = oracle_process.wait() catch {};
        // Clean up stale socket file
        std.fs.deleteFileAbsolute(socket_path) catch {};
        std.fs.deleteFileAbsolute(pid_path) catch {};
    }

    // Wait for oracle to accept connections
    try waitForSocket(socket_path);

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
        try env_map.put(shared_oracle_socket_env, socket_path);
        children[shard_index].env_map = env_map;

        try children[shard_index].spawn();
        started_count += 1;
    }

    var exit_code: u8 = 0;
    for (children[0..started_count]) |*child| {
        const term = child.wait() catch {
            exit_code = 1;
            continue;
        };
        switch (term) {
            .Exited => |code| {
                if (code != 0) exit_code = 1;
            },
            else => exit_code = 1,
        }
    }

    if (exit_code != 0) std.process.exit(exit_code);
}

fn resolveSocketPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    const dir = try std.fs.path.join(allocator, &.{ home, oracle_dir_name });
    defer allocator.free(dir);
    std.fs.makeDirAbsolute(dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    return try std.fs.path.join(allocator, &.{ dir, oracle_socket_name });
}

fn siblingPath(allocator: std.mem.Allocator, socket_path: []const u8, name: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(socket_path) orelse ".";
    return try std.fs.path.join(allocator, &.{ dir, name });
}

fn killPreviousOracle(allocator: std.mem.Allocator, pid_path: []const u8) void {
    // Read PID from file and kill the process
    var dir = std.fs.openDirAbsolute(std.fs.path.dirname(pid_path) orelse ".", .{}) catch return;
    defer dir.close();
    const pid_str = dir.readFileAlloc(allocator, std.fs.path.basename(pid_path), 20) catch return;
    defer allocator.free(pid_str);
    const pid = std.fmt.parseInt(std.process.Child.Id, std.mem.trim(u8, pid_str, &std.ascii.whitespace), 10) catch return;
    const c = @cImport(@cInclude("signal.h"));
    _ = c.kill(pid, c.SIGTERM);
    // Poll until the process is gone
    var attempts: usize = 0;
    while (attempts < 100) : (attempts += 1) {
        if (c.kill(pid, 0) != 0) return; // process no longer exists
        std.Thread.sleep(50 * std.time.ns_per_ms);
    }
}

fn waitForSocketGone(socket_path: []const u8) void {
    var attempts: usize = 0;
    while (attempts < 100) : (attempts += 1) {
        if (std.net.connectUnixSocket(socket_path)) |stream| {
            stream.close();
        } else |_| {
            return; // can't connect = gone
        }
        std.Thread.sleep(50 * std.time.ns_per_ms);
    }
}

fn spawnOracle(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    socket_path: []const u8,
    pid_path: []const u8,
) !std.process.Child {
    // Kill any existing oracle process from a previous run
    killPreviousOracle(allocator, pid_path);
    // Clean up stale files
    std.fs.deleteFileAbsolute(socket_path) catch {};
    std.fs.deleteFileAbsolute(pid_path) catch {};
    // Wait for old socket to stop accepting connections
    waitForSocketGone(socket_path);

    const argv = [_][]const u8{
        "mise",
        "exec",
        "--",
        "lein",
        "run",
        "-m",
        "game.parity.oracle",
        "--unix-server",
        socket_path,
    };
    var child = std.process.Child.init(&argv, allocator);
    child.cwd = repo_root;
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    return child;
}

fn waitForSocket(socket_path: []const u8) !void {
    var attempts: usize = 0;
    while (attempts < 2400) : (attempts += 1) {
        if (std.net.connectUnixSocket(socket_path)) |stream| {
            stream.close();
            return;
        } else |_| {
            std.Thread.sleep(50 * std.time.ns_per_ms);
        }
    }
    std.debug.print("error: oracle failed to start at {s} after 120s\n", .{socket_path});
    return error.OracleStartupFailed;
}

fn cloneEnvMap(allocator: std.mem.Allocator, src: *const std.process.EnvMap) !std.process.EnvMap {
    var cloned = std.process.EnvMap.init(allocator);
    var it = src.hash_map.iterator();
    while (it.next()) |entry| {
        try cloned.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    return cloned;
}

fn findRepoRoot(allocator: std.mem.Allocator, start_path: []const u8) ![]const u8 {
    var current = try allocator.dupe(u8, start_path);
    while (true) {
        // Check if project.clj exists in current directory
        var dir = std.fs.openDirAbsolute(current, .{}) catch {
            allocator.free(current);
            return error.RepoRootNotFound;
        };
        dir.access("project.clj", .{}) catch {
            dir.close();
            // Try parent directory
            const parent = std.fs.path.dirname(current) orelse {
                allocator.free(current);
                return error.RepoRootNotFound;
            };
            if (std.mem.eql(u8, parent, current)) {
                allocator.free(current);
                return error.RepoRootNotFound;
            }
            const parent_dup = try allocator.dupe(u8, parent);
            allocator.free(current);
            current = parent_dup;
            continue;
        };
        dir.close();
        return current;
    }
}
