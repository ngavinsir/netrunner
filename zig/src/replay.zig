const std = @import("std");
const api = @import("api.zig");

fn defaultIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

/// Action replay save/load.
/// Format: line-based text — matchup_id, seed, then one action index per line.
/// Deterministic: same matchup + seed + actions = same game state.
pub const Replay = struct {
    matchup_id: c_int,
    seed: u64,
    actions: std.ArrayListUnmanaged(c_int) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, matchup_id: c_int, seed: u64) Replay {
        return .{
            .matchup_id = matchup_id,
            .seed = seed,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Replay) void {
        self.actions.deinit(self.allocator);
    }

    pub fn record(self: *Replay, action_index: c_int) !void {
        try self.actions.append(self.allocator, action_index);
    }

    pub fn save(self: *const Replay, path: []const u8) !void {
        const io = defaultIo();
        const file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        // Write matchup_id and seed
        var hdr_buf: [64]u8 = undefined;
        const hdr = std.fmt.bufPrint(&hdr_buf, "{d}\n{d}\n", .{ self.matchup_id, self.seed }) catch return error.InvalidFormat;
        try file.writeStreamingAll(io, hdr);
        // Write each action index
        for (self.actions.items) |idx| {
            var line_buf: [32]u8 = undefined;
            const line = std.fmt.bufPrint(&line_buf, "{d}\n", .{idx}) catch continue;
            try file.writeStreamingAll(io, line);
        }
    }

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Replay {
        const io = defaultIo();
        const file = try std.Io.Dir.cwd().openFile(io, path, .{});
        defer file.close(io);
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(io, &buffer);
        const content = try reader.interface.allocRemaining(allocator, .limited(10 * 1024 * 1024));
        defer allocator.free(content);
        return parse(allocator, content);
    }

    pub fn parse(allocator: std.mem.Allocator, content: []const u8) !Replay {
        var lines = std.mem.splitScalar(u8, content, '\n');
        const matchup_str = lines.next() orelse return error.InvalidFormat;
        const seed_str = lines.next() orelse return error.InvalidFormat;
        const matchup_id = try std.fmt.parseInt(c_int, std.mem.trim(u8, matchup_str, &std.ascii.whitespace), 10);
        const seed = try std.fmt.parseInt(u64, std.mem.trim(u8, seed_str, &std.ascii.whitespace), 10);

        var actions: std.ArrayListUnmanaged(c_int) = .empty;
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;
            try actions.append(allocator, try std.fmt.parseInt(c_int, trimmed, 10));
        }
        return .{ .matchup_id = matchup_id, .seed = seed, .actions = actions, .allocator = allocator };
    }

    /// Replay all recorded actions into a fresh game. Returns the game handle.
    pub fn restore(self: *const Replay) ?*anyopaque {
        const h = api.netrunner_create(self.matchup_id, self.seed) orelse return null;
        for (self.actions.items) |idx| {
            if (api.netrunner_apply_action(h, idx) != 0) {
                api.netrunner_destroy(h);
                return null;
            }
        }
        return h;
    }
};

test "save and load round-trips" {
    const allocator = std.testing.allocator;
    var r = Replay.init(allocator, 2, 42);
    defer r.deinit();
    try r.record(0);
    try r.record(1);
    try r.record(3);

    const path = "/tmp/netrunner-test-replay.txt";
    try r.save(path);

    var loaded = try Replay.load(allocator, path);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(c_int, 2), loaded.matchup_id);
    try std.testing.expectEqual(@as(u64, 42), loaded.seed);
    try std.testing.expectEqual(@as(usize, 3), loaded.actions.items.len);
    try std.testing.expectEqual(@as(c_int, 0), loaded.actions.items[0]);
    try std.testing.expectEqual(@as(c_int, 1), loaded.actions.items[1]);
    try std.testing.expectEqual(@as(c_int, 3), loaded.actions.items[2]);
}

test "restore replays game to correct state" {
    const allocator = std.testing.allocator;
    const matchup_id: c_int = 0;
    const seed: u64 = 123;

    var r = Replay.init(allocator, matchup_id, seed);
    defer r.deinit();

    // Create reference game and apply keep/keep
    const h1 = api.netrunner_create(matchup_id, seed) orelse return error.CreateFailed;
    defer api.netrunner_destroy(h1);
    try std.testing.expectEqual(@as(c_int, 0), api.netrunner_apply_action(h1, 0));
    try r.record(0);
    try std.testing.expectEqual(@as(c_int, 0), api.netrunner_apply_action(h1, 0));
    try r.record(0);

    // Restore and compare
    const h2 = r.restore() orelse return error.RestoreFailed;
    defer api.netrunner_destroy(h2);
    try std.testing.expectEqual(api.netrunner_current_player(h1), api.netrunner_current_player(h2));
    try std.testing.expectEqual(api.netrunner_turn(h1), api.netrunner_turn(h2));
    try std.testing.expectEqual(api.netrunner_num_actions(h1), api.netrunner_num_actions(h2));
}
