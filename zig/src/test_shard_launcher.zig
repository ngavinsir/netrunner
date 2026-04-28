const std = @import("std");

const oracle_dir_name = ".netrunner-oracle";
const oracle_socket_name = "o.sock";
const oracle_pid_name = "oracle.pid";
const shared_oracle_socket_env = "NETRUNNER_SHARED_ORACLE_SOCKET";

fn defaultIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = init.io;

    const args = try collectArgs(allocator, init.minimal.args);
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

    const cwd_path = try std.process.currentPathAlloc(io, allocator);
    // Find repo root by looking for project.clj (Clojure project marker)
    const repo_root = try findRepoRoot(allocator, io, cwd_path);
    const queue_name = try std.fmt.allocPrint(allocator, "test-sharded-{d}", .{std.Io.Clock.real.now(io).toMicroseconds()});
    const queue_dir = try std.fs.path.join(allocator, &.{ cwd_path, "zig-cache", queue_name });
    std.Io.Dir.createDirAbsolute(io, queue_dir, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Start a single shared oracle process for all shards
    const socket_path = try resolveSocketPath(allocator, io, init.minimal.environ);
    const pid_path = try siblingPath(allocator, socket_path, oracle_pid_name);
    var oracle_process = try spawnOracle(allocator, io, repo_root, socket_path, pid_path);
    defer {
        oracle_process.kill(io);
        // Clean up stale socket file
        std.Io.Dir.deleteFileAbsolute(io, socket_path) catch {};
        std.Io.Dir.deleteFileAbsolute(io, pid_path) catch {};
    }

    // Wait for oracle to accept connections
    try waitForSocket(io, socket_path);

    const process_env = try std.process.Environ.createMap(init.minimal.environ, allocator);
    const shard_total_text = try std.fmt.allocPrint(allocator, "{d}", .{shard_count});
    const forwarded_args = args[3..];

    const children = try allocator.alloc(std.process.Child, shard_count);
    var started_count: usize = 0;
    errdefer {
        for (children[0..started_count]) |*child| {
            child.kill(io);
        }
    }

    for (0..shard_count) |shard_index| {
        const shard_index_text = try std.fmt.allocPrint(allocator, "{d}", .{shard_index});
        const child_argv = try allocator.alloc([]const u8, 1 + forwarded_args.len);
        child_argv[0] = test_binary;
        @memcpy(child_argv[1..], forwarded_args);

        const env_map = try allocator.create(std.process.Environ.Map);
        env_map.* = try cloneEnvMap(allocator, &process_env);
        try env_map.put("NETRUNNER_TEST_TOTAL", shard_total_text);
        try env_map.put("NETRUNNER_TEST_INDEX", shard_index_text);
        try env_map.put("NETRUNNER_TEST_QUEUE_DIR", queue_dir);
        try env_map.put(shared_oracle_socket_env, socket_path);

        children[shard_index] = try std.process.spawn(io, .{
            .argv = child_argv,
            .cwd = .{ .path = cwd_path },
            .stdin = .ignore,
            .stdout = .inherit,
            .stderr = .inherit,
            .environ_map = env_map,
        });
        started_count += 1;
    }

    var exit_code: u8 = 0;
    for (children[0..started_count]) |*child| {
        const term = child.wait(io) catch {
            exit_code = 1;
            continue;
        };
        switch (term) {
            .exited => |code| {
                if (code != 0) exit_code = 1;
            },
            else => exit_code = 1,
        }
    }

    if (exit_code != 0) std.process.exit(exit_code);
}

fn resolveSocketPath(allocator: std.mem.Allocator, io: std.Io, environ: std.process.Environ) ![]const u8 {
    const home = try environ.getAlloc(allocator, "HOME");
    defer allocator.free(home);
    const dir = try std.fs.path.join(allocator, &.{ home, oracle_dir_name });
    defer allocator.free(dir);
    std.Io.Dir.createDirAbsolute(io, dir, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    return try std.fs.path.join(allocator, &.{ dir, oracle_socket_name });
}

fn siblingPath(allocator: std.mem.Allocator, socket_path: []const u8, name: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(socket_path) orelse ".";
    return try std.fs.path.join(allocator, &.{ dir, name });
}

fn killPreviousOracle(allocator: std.mem.Allocator, io: std.Io, pid_path: []const u8) void {
    // Read PID from file and kill the process
    var dir = std.Io.Dir.openDirAbsolute(io, std.fs.path.dirname(pid_path) orelse ".", .{}) catch return;
    defer dir.close(io);
    const pid_str = dir.readFileAlloc(io, std.fs.path.basename(pid_path), allocator, .limited(20)) catch return;
    defer allocator.free(pid_str);
    const pid = std.fmt.parseInt(std.process.Child.Id, std.mem.trim(u8, pid_str, &std.ascii.whitespace), 10) catch return;
    const c = @cImport(@cInclude("signal.h"));
    _ = c.kill(pid, c.SIGTERM);
    // Poll until the process is gone
    var attempts: usize = 0;
    while (attempts < 100) : (attempts += 1) {
        if (c.kill(pid, 0) != 0) return; // process no longer exists
        io.sleep(.fromMilliseconds(50), .awake) catch {};
    }
}

fn collectArgs(allocator: std.mem.Allocator, args: std.process.Args) ![]const []const u8 {
    var iter = try std.process.Args.Iterator.initAllocator(args, allocator);
    defer iter.deinit();

    var result: std.ArrayListUnmanaged([]const u8) = .empty;
    while (iter.next()) |arg| {
        try result.append(allocator, try allocator.dupe(u8, arg));
    }
    return try result.toOwnedSlice(allocator);
}

fn waitForSocketGone(io: std.Io, socket_path: []const u8) void {
    var attempts: usize = 0;
    while (attempts < 100) : (attempts += 1) {
        const address = std.Io.net.UnixAddress.init(socket_path) catch return;
        if (address.connect(io)) |stream| {
            stream.close(io);
        } else |_| {
            return; // can't connect = gone
        }
        io.sleep(.fromMilliseconds(50), .awake) catch {};
    }
}

fn spawnOracle(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_root: []const u8,
    socket_path: []const u8,
    pid_path: []const u8,
) !std.process.Child {
    // Kill any existing oracle process from a previous run
    killPreviousOracle(allocator, io, pid_path);
    // Clean up stale files
    std.Io.Dir.deleteFileAbsolute(io, socket_path) catch {};
    std.Io.Dir.deleteFileAbsolute(io, pid_path) catch {};
    // Wait for old socket to stop accepting connections
    waitForSocketGone(io, socket_path);

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
    return try std.process.spawn(io, .{
        .argv = &argv,
        .cwd = .{ .path = repo_root },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .inherit,
    });
}

fn waitForSocket(io: std.Io, socket_path: []const u8) !void {
    var attempts: usize = 0;
    while (attempts < 2400) : (attempts += 1) {
        const address = try std.Io.net.UnixAddress.init(socket_path);
        if (address.connect(io)) |stream| {
            stream.close(io);
            return;
        } else |_| {
            io.sleep(.fromMilliseconds(50), .awake) catch {};
        }
    }
    std.debug.print("error: oracle failed to start at {s} after 120s\n", .{socket_path});
    return error.OracleStartupFailed;
}

fn cloneEnvMap(allocator: std.mem.Allocator, src: *const std.process.Environ.Map) !std.process.Environ.Map {
    var cloned = std.process.Environ.Map.init(allocator);
    var it = src.array_hash_map.iterator();
    while (it.next()) |entry| {
        try cloned.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    return cloned;
}

fn findRepoRoot(allocator: std.mem.Allocator, io: std.Io, start_path: []const u8) ![]const u8 {
    var current = try allocator.dupe(u8, start_path);
    while (true) {
        // Check if project.clj exists in current directory
        var dir = std.Io.Dir.openDirAbsolute(io, current, .{}) catch {
            allocator.free(current);
            return error.RepoRootNotFound;
        };
        dir.access(io, "project.clj", .{}) catch {
            dir.close(io);
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
        dir.close(io);
        return current;
    }
}
