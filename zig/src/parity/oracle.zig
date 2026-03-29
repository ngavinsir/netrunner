const std = @import("std");
const state = @import("../engine/state.zig");

const oracle_dir_name = ".netrunner-oracle";
const oracle_socket_name = "o.sock";

const OracleServer = struct {
    child: std.process.Child,
    socket_path: []const u8,
    pid_path: []const u8,

    fn init(allocator: std.mem.Allocator, repo_root: []const u8) !OracleServer {
        const socket_path = try defaultOracleSocketPath(allocator);
        const pid_path = try defaultOraclePidPath(allocator);

        // Clean up any stale socket/process from a previous crashed run
        cleanupStaleOracle(socket_path, pid_path);

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
        child.stderr_behavior = .Ignore;
        try child.spawn();
        try child.waitForSpawn();

        // Write PID file so we can clean up dangling processes
        writePidFile(pid_path, child.id) catch {};

        try waitForUnixSocket(socket_path);
        return .{
            .child = child,
            .socket_path = socket_path,
            .pid_path = pid_path,
        };
    }

    fn deinit(self: *OracleServer) void {
        _ = self.child.kill() catch {};
        std.fs.deleteFileAbsolute(self.socket_path) catch {};
        std.fs.deleteFileAbsolute(self.pid_path) catch {};
    }
};

var oracle_server_mutex: std.Thread.Mutex = .{};
var persistent_oracle_server: ?OracleServer = null;
// Limits concurrent fallback (one-shot) oracle processes to 1
var fallback_semaphore: std.Thread.Mutex = .{};

pub const BeginnerInitialSnapshot = struct {
    arena: std.heap.ArenaAllocator,
    snapshot: state.GameSnapshot,

    pub fn deinit(self: *BeginnerInitialSnapshot) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const ReplaySnapshot = struct {
    arena: std.heap.ArenaAllocator,
    snapshot: state.GameSnapshot,

    pub fn deinit(self: *ReplaySnapshot) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const FixtureSummary = struct {
    fixture_version: u16,
    fixture_kind: []const u8,
    matchup: []const u8,
    seed: u64,
    decision_side: []const u8,
    legal_action_count: usize,
    transition_count: usize,
};

pub const ActionExpectation = struct {
    kind: state.ActionKind,
    side: state.Side,
    choice_text: ?[]const u8 = null,
    server: ?[]const u8 = null,
    card_index: ?u8 = null,
    card_title: ?[]const u8 = null,
    ability_index: ?u8 = null,
    label: ?[]const u8 = null,
};

pub const TransitionExpectation = struct {
    decision_side: state.Side,
    active_player: state.Side,
    turn: u16,
    end_turn: bool,
    run: ?state.RunState,
    corp_credit: u16,
    runner_credit: u16,
    runner_run_credit: u16,
    corp_click: u8,
    runner_click: u8,
    corp_agenda_point: u8,
    runner_agenda_point: u8,
    corp_keep: state.KeepState,
    runner_keep: state.KeepState,
    rng_seed: i64,
    corp_prompt_type: ?[]const u8,
    runner_prompt_type: ?[]const u8,
    legal_actions: []const ActionExpectation,
    corp_servers: []const state.ServerSlot,
    corp_hand: []const state.CardInstance,
    corp_deck: []const state.CardInstance,
    runner_hand: []const state.CardInstance,
    runner_deck: []const state.CardInstance,
};

pub const BasicActionOracle = struct {
    gain_credit: TransitionExpectation,
    draw_card: TransitionExpectation,
    advance_card: TransitionExpectation,
    purge_viruses: TransitionExpectation,
};

pub const StartTurnOracle = struct {
    transition: TransitionExpectation,
    basic_actions: BasicActionOracle,
    play_from_hand: []const CardPlayExpectation,
};

pub const PromptChoiceExpectation = struct {
    choice_text: []const u8,
    result: TransitionExpectation,
};

pub const CardPlayExpectation = struct {
    card_title: []const u8,
    result: TransitionExpectation,
    prompt_choices: []const PromptChoiceExpectation = &.{},
};

pub const RunnerTransitionOracle = struct {
    keep: TransitionExpectation,
    keep_start_turn: StartTurnOracle,
    mulligan: TransitionExpectation,
    mulligan_start_turn: StartTurnOracle,
};

pub const TransitionOracle = struct {
    keep: TransitionExpectation,
    mulligan: TransitionExpectation,
    runner_after_corp_keep: RunnerTransitionOracle,
    runner_after_corp_mulligan: RunnerTransitionOracle,
    scenarios: []const ScenarioExpectation,
};

pub const ScenarioExpectation = struct {
    name: []const u8,
    actions: []const ActionExpectation,
    result: TransitionExpectation,
};

pub fn loadBeginnerInitialSnapshot(
    backing_allocator: std.mem.Allocator,
    fixture_path: []const u8,
) !BeginnerInitialSnapshot {
    var result: BeginnerInitialSnapshot = .{
        .arena = std.heap.ArenaAllocator.init(backing_allocator),
        .snapshot = undefined,
    };
    errdefer result.arena.deinit();

    const allocator = result.arena.allocator();
    const source = try std.fs.cwd().readFileAlloc(allocator, fixture_path, 64 << 20);
    const root_value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, source, .{});

    const root = root_value.object;
    const initial = try getRequired(.object, root, "initial");
    const oracle_state = try getRequired(.object, initial, "oracle-state");
    const legal_actions_value = try getRequired(.array, initial, "legal-actions");

    result.snapshot = .{
        .state = try parseGameState(allocator, oracle_state),
        .decision_side = try parseSide(try getRequired(.string, initial, "decision-side")),
        .legal_actions = try parseLegalActions(allocator, legal_actions_value),
    };
    return result;
}

pub fn loadSummary(
    allocator: std.mem.Allocator,
    fixture_path: []const u8,
) !FixtureSummary {
    const source = try std.fs.cwd().readFileAlloc(allocator, fixture_path, 64 << 20);
    defer allocator.free(source);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, source, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const initial = try getRequired(.object, root, "initial");
    const legal_actions = try getRequired(.array, initial, "legal-actions");
    const transitions = try getRequired(.array, root, "transitions");

    return .{
        .fixture_version = try getIntegerAs(u16, root, "fixture-version"),
        .fixture_kind = try allocator.dupe(u8, try getRequired(.string, root, "fixture-kind")),
        .matchup = try allocator.dupe(u8, try getRequired(.string, root, "matchup")),
        .seed = try getIntegerAs(u64, root, "seed"),
        .decision_side = try allocator.dupe(u8, try getRequired(.string, initial, "decision-side")),
        .legal_action_count = legal_actions.items.len,
        .transition_count = transitions.items.len,
    };
}

pub fn replayActions(
    backing_allocator: std.mem.Allocator,
    seed: u64,
    actions: []const state.LegalAction,
) !ReplaySnapshot {
    return replayActionsWithMatchup(backing_allocator, seed, actions, null);
}

pub fn replayActionsWithMatchup(
    backing_allocator: std.mem.Allocator,
    seed: u64,
    actions: []const state.LegalAction,
    matchup: ?[]const u8,
) !ReplaySnapshot {
    var result: ReplaySnapshot = .{
        .arena = std.heap.ArenaAllocator.init(backing_allocator),
        .snapshot = undefined,
    };
    errdefer result.arena.deinit();

    const allocator = result.arena.allocator();
    const repo_root = try repoRootPath(allocator);
    const root_value = blk: {
        const socket_path = try ensurePersistentOracleServer(repo_root);
        const first_response = runReplayOracleSocket(allocator, socket_path, seed, actions, matchup) catch {
            oracle_server_mutex.lock();
            defer oracle_server_mutex.unlock();
            resetPersistentOracleServerLocked();
            // Serialize fallback spawns to avoid multiple concurrent lein processes
            fallback_semaphore.lock();
            defer fallback_semaphore.unlock();
            const fallback_response = try runReplayOracleOnce(allocator, repo_root, seed, actions, matchup);
            break :blk try parseReplayResponse(allocator, fallback_response);
        };

        break :blk parseReplayResponse(allocator, first_response) catch {
            oracle_server_mutex.lock();
            defer oracle_server_mutex.unlock();
            resetPersistentOracleServerLocked();
            // Serialize fallback spawns to avoid multiple concurrent lein processes
            fallback_semaphore.lock();
            defer fallback_semaphore.unlock();
            const fallback_response = try runReplayOracleOnce(allocator, repo_root, seed, actions, matchup);
            break :blk try parseReplayResponse(allocator, fallback_response);
        };
    };

    const root = root_value.object;
    const oracle_state = try getRequired(.object, root, "oracle-state");
    const legal_actions_value = try getRequired(.array, root, "legal-actions");

    result.snapshot = .{
        .state = try parseGameState(allocator, oracle_state),
        .decision_side = try parseSide(try getRequired(.string, root, "decision-side")),
        .legal_actions = try parseLegalActions(allocator, legal_actions_value),
    };
    return result;
}

pub fn freeSummary(allocator: std.mem.Allocator, summary: *FixtureSummary) void {
    allocator.free(summary.fixture_kind);
    allocator.free(summary.matchup);
    allocator.free(summary.decision_side);
    summary.* = undefined;
}

/// Shut down the persistent oracle server if running. Call this on test suite exit.
pub fn shutdownPersistentOracle() void {
    oracle_server_mutex.lock();
    defer oracle_server_mutex.unlock();
    resetPersistentOracleServerLocked();
}

fn ensurePersistentOracleServer(repo_root: []const u8) ![]const u8 {
    oracle_server_mutex.lock();
    defer oracle_server_mutex.unlock();

    if (persistent_oracle_server == null) {
        persistent_oracle_server = try OracleServer.init(std.heap.page_allocator, repo_root);
    }
    return persistent_oracle_server.?.socket_path;
}

fn resetPersistentOracleServerLocked() void {
    if (persistent_oracle_server) |*server| {
        server.deinit();
        persistent_oracle_server = null;
    }
}

fn runReplayOracleSocket(
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    seed: u64,
    actions: []const state.LegalAction,
    matchup: ?[]const u8,
) ![]const u8 {
    var stream = try std.net.connectUnixSocket(socket_path);
    defer stream.close();
    var write_buffer: [4096]u8 = undefined;
    var read_buffer: [4096]u8 = undefined;

    const request_payload = try buildReplayRequestJson(allocator, seed, actions, matchup);
    defer allocator.free(request_payload);
    var writer = stream.writer(&write_buffer);
    try writer.interface.writeAll(request_payload);
    try writer.interface.writeByte('\n');
    try writer.interface.flush();

    var response: std.ArrayList(u8) = .empty;
    defer response.deinit(allocator);
    while (true) {
        const amount = try stream.read(&read_buffer);
        if (amount == 0) break;
        try response.appendSlice(allocator, read_buffer[0..amount]);
    }
    return response.toOwnedSlice(allocator);
}

// Timeout for one-shot fallback oracle processes (2 minutes)
const fallback_timeout_ns: u64 = 120 * std.time.ns_per_s;

fn runReplayOracleOnce(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    seed: u64,
    actions: []const state.LegalAction,
    matchup: ?[]const u8,
) ![]const u8 {
    const request_path = try std.fmt.allocPrint(allocator, "/tmp/netrunner-oracle-{d}.json", .{std.time.microTimestamp()});
    defer allocator.free(request_path);

    const request_payload = try buildReplayRequestJson(allocator, seed, actions, matchup);
    defer allocator.free(request_payload);
    try std.fs.cwd().writeFile(.{ .sub_path = request_path, .data = request_payload });
    defer std.fs.cwd().deleteFile(request_path) catch {};

    const argv = [_][]const u8{
        "mise",
        "exec",
        "--",
        "lein",
        "run",
        "-m",
        "game.parity.oracle",
        request_path,
    };
    var child = std.process.Child.init(&argv, allocator);
    child.cwd = repo_root;
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    try child.waitForSpawn();

    const stdout_file = child.stdout orelse return error.ReplayOracleFailed;

    // Spawn a watchdog thread that kills the process after the timeout
    const pid = child.id;
    const watchdog = std.Thread.spawn(.{}, watchdogKill, .{ pid, fallback_timeout_ns }) catch null;
    defer if (watchdog) |w| w.detach();

    const response = try stdout_file.readToEndAlloc(allocator, 64 << 20);
    const term = try child.wait();

    // If killed by signal, the watchdog likely fired
    switch (term) {
        .Signal => {
            allocator.free(response);
            return error.ReplayOracleTimedOut;
        },
        else => {},
    }
    return response;
}

fn buildReplayRequestJson(
    allocator: std.mem.Allocator,
    seed: u64,
    actions: []const state.LegalAction,
    matchup: ?[]const u8,
) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    var writer = output.writer(allocator);
    try writer.writeAll("{\"seed\":");
    try writer.print("{d}", .{seed});
    if (matchup) |m| {
        try writer.writeAll(",\"matchup\":\"");
        try writer.writeAll(m);
        try writer.writeByte('"');
    }
    try writer.writeAll(",\"actions\":[");
    var wrote_action = false;
    for (actions) |action| {
        if (shouldSkipAction(action)) continue;
        if (wrote_action) try writer.writeByte(',');
        try writeActionJson(&writer, action);
        wrote_action = true;
    }
    try writer.writeAll("]}");
    return try output.toOwnedSlice(allocator);
}

fn extractJsonObject(response: []const u8) ![]const u8 {
    const start = std.mem.indexOfScalar(u8, response, '{') orelse return error.SyntaxError;
    const finish = std.mem.lastIndexOfScalar(u8, response, '}') orelse return error.SyntaxError;
    if (finish < start) return error.SyntaxError;
    return response[start .. finish + 1];
}

fn parseReplayResponse(
    allocator: std.mem.Allocator,
    response: []const u8,
) !std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, allocator, try extractJsonObject(response), .{});
}

fn repoRootPath(allocator: std.mem.Allocator) ![]const u8 {
    return std.process.getEnvVarOwned(allocator, "PWD") catch try std.fs.cwd().realpathAlloc(allocator, ".");
}

fn defaultOracleSocketPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    const dir = try std.fs.path.join(allocator, &.{ home, oracle_dir_name });
    std.fs.makeDirAbsolute(dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    return try std.fs.path.join(allocator, &.{ dir, oracle_socket_name });
}

fn defaultOraclePidPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    const dir = try std.fs.path.join(allocator, &.{ home, oracle_dir_name });
    return try std.fs.path.join(allocator, &.{ dir, "oracle.pid" });
}

fn writePidFile(pid_path: []const u8, pid: std.process.Child.Id) !void {
    var buf: [20]u8 = undefined;
    const pid_str = std.fmt.bufPrint(&buf, "{d}", .{pid}) catch return;
    std.fs.cwd().writeFile(.{ .sub_path = pid_path, .data = pid_str }) catch {};
}

fn cleanupStaleOracle(socket_path: []const u8, pid_path: []const u8) void {
    // Try to kill any leftover process from a previous run
    if (std.fs.cwd().readFileAlloc(std.heap.page_allocator, pid_path, 20) catch null) |pid_str| {
        defer std.heap.page_allocator.free(pid_str);
        const pid = std.fmt.parseInt(std.process.Child.Id, pid_str, 10) catch {
            // Invalid PID file, just clean up files
            std.fs.deleteFileAbsolute(pid_path) catch {};
            std.fs.deleteFileAbsolute(socket_path) catch {};
            return;
        };
        // Send SIGKILL to the stale process
        std.posix.kill(pid, std.posix.SIG.KILL) catch {};
        // Give it a moment to die
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
    // Remove stale socket and PID files
    std.fs.deleteFileAbsolute(socket_path) catch {};
    std.fs.deleteFileAbsolute(pid_path) catch {};
}

fn watchdogKill(pid: std.process.Child.Id, timeout_ns: u64) void {
    std.Thread.sleep(timeout_ns);
    std.posix.kill(pid, std.posix.SIG.KILL) catch {};
}

fn waitForUnixSocket(socket_path: []const u8) !void {
    var attempts: usize = 0;
    while (attempts < 2400) : (attempts += 1) {
        if (std.net.connectUnixSocket(socket_path)) |stream| {
            stream.close();
            return;
        } else |_| {
            std.Thread.sleep(50 * std.time.ns_per_ms);
        }
    }
    return error.ReplayOracleFailed;
}

fn shouldSkipAction(action: state.LegalAction) bool {
    // Skip score_agenda and advance_installed basic actions — in Clojure these are
    // single commands with card context, not two-step prompt flows.
    // The subsequent prompt_choice is translated to the proper action.
    if (action.basic_action) |ba| {
        if (ba == .score_agenda or ba == .advance_installed) return true;
    }
    // Skip discard-to-hand-size selects — Clojure handles these as part of the
    // end-turn async chain. Sending them as separate actions breaks the chain.
    if (action.kind == .prompt_choice and action.prompt_type != null) {
        if (std.mem.eql(u8, action.prompt_type.?, "discard")) return true;
        // Skip "No rez" from rez-window — Clojure's auto-no-action handles approach passing.
        if (std.mem.eql(u8, action.prompt_type.?, "rez-window")) {
            if (action.choice) |choice| {
                if (choice.text) |text| {
                    if (std.mem.eql(u8, text, "No rez")) return true;
                }
            }
        }
    }
    return false;
}

fn isPhase12Continue(action: state.LegalAction) bool {
    // Phase-12 continues are internal to the Zig engine; the Clojure oracle
    // auto-resolves phase-12 so these must not be sent.
    return action.kind == .@"continue" and action.prompt_type == null and
        (action.side == .corp or action.side == .runner);
}

fn writeActionJson(writer: anytype, action: state.LegalAction) !void {
    // Translate score-agenda prompt_choice into a "score" action for Clojure
    if (action.kind == .prompt_choice and action.prompt_type != null) {
        if (std.mem.eql(u8, action.prompt_type.?, "score-agenda")) {
            try writer.writeByte('{');
            try writeJsonFieldString(writer, "kind", "score", false);
            try writeJsonFieldString(writer, "side", sideName(action.side), true);
            if (action.choice) |choice| {
                if (choice.text) |text| {
                    try writeCorpServerCardLocator(writer, text, true);
                }
            }
            try writer.writeByte('}');
            return;
        }
        // Translate discard prompt_choice into a "select" action for Clojure
        if (std.mem.eql(u8, action.prompt_type.?, "discard")) {
            try writer.writeByte('{');
            try writeJsonFieldString(writer, "kind", "select", false);
            try writeJsonFieldString(writer, "side", sideName(action.side), true);
            if (action.choice) |choice| {
                if (choice.text) |text| {
                    try writeHandCardLocator(writer, action.side, text, true);
                }
            }
            try writer.writeByte('}');
            return;
        }
        // Translate mu-overflow prompt_choice into a "select" action for Clojure
        if (std.mem.eql(u8, action.prompt_type.?, "mu-overflow")) {
            try writer.writeByte('{');
            try writeJsonFieldString(writer, "kind", "select", false);
            try writeJsonFieldString(writer, "side", sideName(action.side), true);
            if (action.choice) |choice| {
                if (choice.text) |text| {
                    try writeRunnerProgramLocator(writer, text, true);
                }
                // Also send card-title for fallback resolution
                if (choice.card) |card| {
                    if (card.title) |title| {
                        try writeJsonFieldString(writer, "card-title", title, true);
                    }
                }
            }
            try writer.writeByte('}');
            return;
        }
        // Translate rez-window "Rez approached ice" into a "rez-ice" action for Clojure
        if (std.mem.eql(u8, action.prompt_type.?, "rez-window")) {
            try writer.writeByte('{');
            try writeJsonFieldString(writer, "kind", "rez-ice", false);
            try writeJsonFieldString(writer, "side", sideName(action.side), true);
            try writer.writeByte('}');
            return;
        }
        // Translate manegarm-tax prompt_choice into a "manegarm-tax" action for Clojure
        if (std.mem.eql(u8, action.prompt_type.?, "manegarm-tax")) {
            try writer.writeByte('{');
            try writeJsonFieldString(writer, "kind", "manegarm-tax", false);
            try writeJsonFieldString(writer, "side", sideName(action.side), true);
            if (action.choice) |choice| {
                if (choice.text) |text| {
                    try writeJsonFieldString(writer, "choice", text, true);
                }
            }
            try writer.writeByte('}');
            return;
        }
        // Translate advance-installed prompt_choice into an "advance" action for Clojure
        if (std.mem.eql(u8, action.prompt_type.?, "advance-installed")) {
            try writer.writeByte('{');
            try writeJsonFieldString(writer, "kind", "advance", false);
            try writeJsonFieldString(writer, "side", sideName(action.side), true);
            if (action.choice) |choice| {
                if (choice.text) |text| {
                    try writeCorpServerCardLocator(writer, text, true);
                }
            }
            try writer.writeByte('}');
            return;
        }
    }

    try writer.writeByte('{');
    try writeJsonFieldString(writer, "kind", actionKindName(action.kind), false);
    try writeJsonFieldString(writer, "side", sideName(action.side), true);
    if (action.prompt_type) |prompt_type| try writeJsonFieldString(writer, "prompt-type", oraclePromptType(prompt_type), true);
    if (action.choice) |choice| try writeChoiceJsonField(writer, "choice", choice, true);
    if (action.server) |server| try writeJsonFieldString(writer, "server", server, true);
    if (action.card_title) |card_title| try writeJsonFieldString(writer, "card-title", card_title, true);
    if (action.card_index) |card_index| try writeJsonFieldInteger(writer, "card-index", card_index, true);
    if (oracleAbilityIndex(action)) |ability_index| try writeJsonFieldInteger(writer, "ability-index", ability_index, true);
    if (action.label) |label| try writeJsonFieldString(writer, "label", label, true);
    // For use_subroutine, emit subroutine-index from the choice's number
    if (action.kind == .use_subroutine) {
        if (action.choice) |choice| {
            if (choice.number) |num| {
                try writeJsonFieldInteger(writer, "subroutine-index", num, true);
            }
        }
    }
    try writer.writeByte('}');
}

fn writeCorpServerCardLocator(writer: anytype, choice_text: []const u8, leading_comma: bool) !void {
    // Parse "remote1|c|0" into ["corp", "servers", "remote1", "content", 0]
    var iter = std.mem.splitScalar(u8, choice_text, '|');
    const server_name = iter.next() orelse return;
    const zone = iter.next() orelse return;
    const index_text = iter.next() orelse return;
    const zone_name = if (std.mem.eql(u8, zone, "c")) "content" else "ices";

    if (leading_comma) try writer.writeByte(',');
    try writeJsonString(writer, "card-locator");
    try writer.writeByte(':');
    try writer.writeAll("[\"corp\",\"servers\",");
    try writeJsonString(writer, server_name);
    try writer.writeByte(',');
    try writeJsonString(writer, zone_name);
    try writer.writeByte(',');
    try writer.writeAll(index_text);
    try writer.writeByte(']');
}

fn writeHandCardLocator(writer: anytype, side: state.Side, card_title: []const u8, leading_comma: bool) !void {
    // Send card-title for the select action — Clojure resolves by title
    if (leading_comma) try writer.writeByte(',');
    try writeJsonString(writer, "card-title");
    try writer.writeByte(':');
    try writeJsonString(writer, card_title);
    _ = side;
}

fn writeRunnerProgramLocator(writer: anytype, choice_text: []const u8, leading_comma: bool) !void {
    // Parse "p|2" into ["runner", "rig", "program", 2]
    var iter = std.mem.splitScalar(u8, choice_text, '|');
    _ = iter.next(); // skip "p"
    const index_text = iter.next() orelse return;
    if (leading_comma) try writer.writeByte(',');
    try writeJsonString(writer, "card-locator");
    try writer.writeAll(":[\"runner\",\"rig\",\"program\",");
    try writer.writeAll(index_text);
    try writer.writeByte(']');
}

fn oracleAbilityIndex(action: state.LegalAction) ?u8 {
    if (action.kind == .use_installed_ability) {
        // Icebreaker pump_strength is the 2nd ability (index 1) in Clojure card defs
        if (action.installed_ability) |ia| {
            if (ia == .pump_strength) return 1;
        }
        return 0;
    }
    if (action.kind == .use_runner_ability) {
        return 0;
    }
    if (action.basic_action) |basic_action| {
        return switch (action.side) {
            .corp => switch (basic_action) {
                .gain_credit => 0,
                .draw_card => 1,
                .advance_installed => 4,
                .purge_viruses => 6,
                else => null,
            },
            .runner => switch (basic_action) {
                .gain_credit => 0,
                .draw_card => 1,
                .install_from_grip => 2,
                .run_any_server => 4,
                else => null,
            },
        };
    }
    return null;
}

fn oraclePromptType(prompt_type: []const u8) []const u8 {
    if (std.mem.eql(u8, prompt_type, "install-destination")) return "other";
    if (std.mem.eql(u8, prompt_type, "access-choice")) return "other";
    if (std.mem.eql(u8, prompt_type, "run-target")) return "other";
    if (std.mem.eql(u8, prompt_type, "run-central")) return "other";
    if (std.mem.eql(u8, prompt_type, "access-cleanup")) return "select";
    if (std.mem.eql(u8, prompt_type, "discard")) return "select";
    if (std.mem.eql(u8, prompt_type, "mu-overflow")) return "select";
    return prompt_type;
}

fn writeChoiceJsonField(writer: anytype, key: []const u8, choice: state.PromptChoice, leading_comma: bool) !void {
    if (leading_comma) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeByte('{');
    try writeJsonFieldString(writer, "choice-type", choiceKindName(choice.kind), false);
    switch (choice.kind) {
        .string, .keyword, .value => if (choice.text) |text| try writeJsonFieldString(writer, "value", text, true),
        .number => if (choice.number) |number| try writeJsonFieldInteger(writer, "value", number, true),
        .card => if (choice.card) |card| try writeCardReferenceJsonField(writer, "card", card, true),
    }
    try writer.writeByte('}');
}

fn writeCardReferenceJsonField(writer: anytype, key: []const u8, card: state.CardReference, leading_comma: bool) !void {
    if (leading_comma) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeByte('{');
    var wrote_field = false;
    if (card.title) |title| {
        try writeJsonFieldString(writer, "title", title, wrote_field);
        wrote_field = true;
    }
    if (card.printed_title) |printed_title| {
        try writeJsonFieldString(writer, "printed-title", printed_title, wrote_field);
        wrote_field = true;
    }
    if (card.code) |code| {
        try writeJsonFieldInteger(writer, "code", code, wrote_field);
        wrote_field = true;
    }
    if (card.side) |side| {
        try writeJsonFieldString(writer, "side", sideName(side), wrote_field);
    }
    try writer.writeByte('}');
}

fn writeJsonFieldString(writer: anytype, key: []const u8, value: []const u8, leading_comma: bool) !void {
    if (leading_comma) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writeJsonString(writer, value);
}

fn writeJsonFieldInteger(writer: anytype, key: []const u8, value: anytype, leading_comma: bool) !void {
    if (leading_comma) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

fn actionKindName(kind: state.ActionKind) []const u8 {
    return switch (kind) {
        .prompt_choice => "prompt-choice",
        .@"continue" => "continue",
        .start_turn => "start-turn",
        .end_turn => "end-turn",
        .play_from_hand => "play-from-hand",
        .flashback => "flashback",
        .install_from_hand => "install-from-hand",
        .use_ability => "use-ability",
        .use_installed_ability => "use-installed-ability",
        .use_corp_ability => "use-corp-ability",
        .use_runner_ability => "use-runner-ability",
        .use_subroutine => "use-subroutine",
        .jack_out => "jack-out",
        .run => "run",
    };
}

fn sideName(side: state.Side) []const u8 {
    return switch (side) {
        .corp => "corp",
        .runner => "runner",
    };
}

fn choiceKindName(kind: state.ChoiceKind) []const u8 {
    return switch (kind) {
        .string => "string",
        .number => "number",
        .keyword => "keyword",
        .card => "card",
        .value => "value",
    };
}

pub fn loadTransitionOracle(
    allocator: std.mem.Allocator,
    fixture_path: []const u8,
) !TransitionOracle {
    const source = try std.fs.cwd().readFileAlloc(allocator, fixture_path, 64 << 20);
    defer allocator.free(source);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, source, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const transitions = try getRequired(.array, root, "transitions");
    var keep: ?TransitionExpectation = null;
    var mulligan: ?TransitionExpectation = null;
    var keep_transition: ?std.json.ObjectMap = null;
    var mulligan_transition: ?std.json.ObjectMap = null;

    for (transitions.items) |item| {
        const transition = try expectObject(item);
        const action = try getRequired(.object, transition, "action");
        const result = try getRequired(.object, transition, "result");
        const choice = try getRequired(.object, action, "choice");
        const choice_value = try getRequired(.string, choice, "value");
        const parsed_transition = try parseTransitionExpectation(allocator, result);
        if (std.mem.eql(u8, choice_value, "Keep")) {
            keep = parsed_transition;
            keep_transition = transition;
        } else if (std.mem.eql(u8, choice_value, "Mulligan")) {
            mulligan = parsed_transition;
            mulligan_transition = transition;
        }
    }

    return .{
        .keep = keep orelse return error.MissingTransition,
        .mulligan = mulligan orelse return error.MissingTransition,
        .runner_after_corp_keep = try parseRunnerTransitionOracle(allocator, keep_transition orelse return error.MissingTransition),
        .runner_after_corp_mulligan = try parseRunnerTransitionOracle(allocator, mulligan_transition orelse return error.MissingTransition),
        .scenarios = try parseScenarioExpectations(allocator, root),
    };
}

pub fn freeTransitionOracle(allocator: std.mem.Allocator, oracle: *TransitionOracle) void {
    freeTransitionExpectation(allocator, &oracle.keep);
    freeTransitionExpectation(allocator, &oracle.mulligan);
    freeRunnerTransitionOracle(allocator, &oracle.runner_after_corp_keep);
    freeRunnerTransitionOracle(allocator, &oracle.runner_after_corp_mulligan);
    freeScenarioExpectations(allocator, oracle.scenarios);
    oracle.* = undefined;
}

fn freeScenarioExpectations(allocator: std.mem.Allocator, scenarios: []const ScenarioExpectation) void {
    for (scenarios) |scenario| {
        allocator.free(scenario.name);
        freeActionExpectations(allocator, scenario.actions);
        var result = scenario.result;
        freeTransitionExpectation(allocator, &result);
    }
    allocator.free(scenarios);
}

fn parseGameState(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) !state.GameState {
    return .{
        .format = try dupeString(allocator, try getRequired(.string, object, "format")),
        .seed = try getIntegerAs(u64, object, "seed"),
        .rng_seed = try getOptionalInteger(object, "rng-seed"),
        .active_player = try parseSide(try getRequired(.string, object, "active-player")),
        .turn = try getIntegerAs(u16, object, "turn"),
        .end_turn = try getBool(object, "end-turn"),
        .run = try parseOptionalRunState(allocator, object, "run"),
        .pending_install = null,
        .corp = try parsePlayerState(allocator, try getRequired(.object, object, "corp")),
        .runner = try parsePlayerState(allocator, try getRequired(.object, object, "runner")),
    };
}

fn parsePlayerState(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) !state.PlayerState {
    return .{
        .identity = try parseCard(allocator, try getRequired(.object, object, "identity")),
        .basic_action_card = try parseCard(allocator, try getRequired(.object, object, "basic-action-card")),
        .click = try getIntegerAs(u8, object, "click"),
        .click_per_turn = try getIntegerAs(u8, object, "click-per-turn"),
        .credit = try getIntegerAs(u16, object, "credit"),
        .agenda_point = try getIntegerAs(u8, object, "agenda-point"),
        .agenda_point_req = try getIntegerAs(u8, object, "agenda-point-req"),
        .hand_size = try parseHandSize(try getRequired(.object, object, "hand-size")),
        .bad_publicity = try parseOptionalBadPublicity(object, "bad-publicity"),
        .run_credit = try getIntegerAsOrDefault(u16, object, "run-credit", 0),
        .link = try getIntegerAsOrDefault(u8, object, "link", 0),
        .tag = try parseOptionalTagState(object, "tag"),
        .memory = try parseOptionalMemoryState(object, "memory"),
        .brain_damage = try getIntegerAsOrDefault(u8, object, "brain-damage", 0),
        .keep = try parseKeepState(object, "keep"),
        .prompt_state = try parseOptionalPromptState(allocator, object, "prompt-state"),
        .deck = try parseCards(allocator, object, "deck"),
        .hand = try parseCards(allocator, object, "hand"),
        .discard = try parseCards(allocator, object, "discard"),
        .scored = try parseOptionalCards(allocator, object, "scored"),
        .rig_hardware = try parseRigHardware(allocator, object),
        .rig_program = try parseRigPrograms(allocator, object),
        .rig_resources = try parseRigResources(allocator, object),
        .servers = try parseServers(allocator, object),
    };
}

fn parseRigHardware(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) ![]const state.CardInstance {
    const rig = try getOptional(.object, object, "rig") orelse return try allocator.alloc(state.CardInstance, 0);
    return try parseOptionalCards(allocator, rig, "hardware");
}

fn parseRigPrograms(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) ![]const state.CardInstance {
    const rig = try getOptional(.object, object, "rig") orelse return try allocator.alloc(state.CardInstance, 0);
    return try parseOptionalCards(allocator, rig, "program");
}

fn parseRigResources(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) ![]const state.CardInstance {
    const rig = try getOptional(.object, object, "rig") orelse return try allocator.alloc(state.CardInstance, 0);
    return try parseCards(allocator, rig, "resource");
}

fn parseOptionalRunState(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    key: []const u8,
) !?state.RunState {
    const run_object = try getOptional(.object, object, key) orelse return null;
    const server_items = try getRequired(.array, run_object, "server");
    const server = try allocator.alloc([]const u8, server_items.items.len);
    for (server_items.items, 0..) |item, idx| {
        server[idx] = try normalizeInternalServerName(allocator, try extractField(.string, item));
    }
    return .{
        .server = server,
        .position = try getIntegerAs(u8, run_object, "position"),
        .phase = try dupeString(allocator, try getRequired(.string, run_object, "phase")),
        .corp_auto_no_action = if (try getOptional(.boolean, run_object, "corp-auto-no-action")) |value| value else false,
        .no_action = try parseOptionalRunSide(run_object, "no-action"),
        .temporary_run_credits = 0,
        .accesses_remaining = 0,
        .accessed_count = 0,
        .accessed_card_indexes = .{ null, null, null, null },
        .access_card_index = null,
        .rez_cost_bonus = 0,
        .successful_run_effect = .none,
        .successful_run_draw_cards = 0,
        .access_bonus = 0,
    };
}

fn parseOptionalRunSide(
    object: std.json.ObjectMap,
    key: []const u8,
) !?state.Side {
    const value = getOptionalValue(object, key) orelse return null;
    return switch (value) {
        .null => null,
        .bool => |boolean| if (boolean) error.UnexpectedType else null,
        .string => |text| try parseSide(text),
        else => error.UnexpectedType,
    };
}

fn parseCard(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) !state.CardInstance {
    const counter = try getOptional(.object, object, "counter");
    return .{
        .title = try dupeString(allocator, try getRequired(.string, object, "title")),
        .printed_title = try dupeOptionalString(allocator, try getOptional(.string, object, "printed-title")),
        .code = try getOptionalCardCode(object, "code"),
        .side = try parseSide(try getRequired(.string, object, "side")),
        .card_type = try dupeOptionalString(allocator, try getOptional(.string, object, "type")),
        .cost = try getOptionalIntegerAs(u16, object, "cost"),
        .agenda_points = try getOptionalIntegerAs(u8, object, "agenda-points"),
        .advancement_requirement = try getOptionalIntegerAs(u8, object, "advancement-requirement"),
        .rezzed = (try getOptional(.boolean, object, "rezzed")) orelse false,
        .advancement_counter = if (counter) |counter_map| try getIntegerAsOrDefault(u8, counter_map, "advancement", 0) else 0,
        .credit_counter = if (counter) |counter_map| try getIntegerAsOrDefault(u16, counter_map, "credit", 0) else 0,
    };
}

fn parseOptionalPromptState(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    key: []const u8,
) !?state.PromptState {
    const prompt_object = try getOptional(.object, object, key) orelse return null;
    return .{
        .prompt_type = try dupeString(allocator, try getRequired(.string, prompt_object, "prompt-type")),
        .choices = try parsePromptChoices(allocator, prompt_object),
        .source_card = if (try getOptional(.object, prompt_object, "source-card")) |source_card|
            try parseCard(allocator, source_card)
        else
            null,
    };
}

fn parsePromptChoices(
    allocator: std.mem.Allocator,
    prompt_object: std.json.ObjectMap,
) ![]const state.PromptChoice {
    const array = try getOptional(.array, prompt_object, "choices") orelse return try allocator.alloc(state.PromptChoice, 0);
    const choices = try allocator.alloc(state.PromptChoice, array.items.len);
    for (array.items, 0..) |item, idx| {
        choices[idx] = try parsePromptChoice(allocator, try expectObject(item));
    }
    return choices;
}

fn parsePromptChoice(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) !state.PromptChoice {
    const kind = try parseChoiceKind(try getRequired(.string, object, "choice-type"));
    return switch (kind) {
        .string, .keyword, .value => .{
            .kind = kind,
            .text = try dupeOptionalString(allocator, try getOptional(.string, object, "value")),
        },
        .number => .{
            .kind = kind,
            .number = try getOptionalIntegerAs(u16, object, "value"),
        },
        .card => .{
            .kind = kind,
            .card = try parseCardReference(allocator, try getRequired(.object, object, "card")),
        },
    };
}

fn parseCardReference(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) !state.CardReference {
    const maybe_side = try getOptional(.string, object, "side");
    return .{
        .title = try dupeOptionalString(allocator, try getOptional(.string, object, "title")),
        .printed_title = try dupeOptionalString(allocator, try getOptional(.string, object, "printed-title")),
        .code = try getOptionalCardCode(object, "code"),
        .side = if (maybe_side) |side_name| try parseSide(side_name) else null,
    };
}

fn parseLegalActions(
    allocator: std.mem.Allocator,
    array: std.json.Array,
) ![]const state.LegalAction {
    const actions = try allocator.alloc(state.LegalAction, array.items.len);
    for (array.items, 0..) |item, idx| {
        actions[idx] = try parseLegalAction(allocator, try expectObject(item));
    }
    return actions;
}

fn parseLegalAction(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) !state.LegalAction {
    const choice = if (try getOptional(.object, object, "choice")) |choice_object|
        try parsePromptChoice(allocator, choice_object)
    else
        null;

    const ability_index = try getOptionalIntegerAs(u8, object, "ability-index");
    const side = try parseSide(try getRequired(.string, object, "side"));
    const installed_resource_index = try parseRunnerRigResourceCardIndex(object);
    const kind = try parseActionKind(try getRequired(.string, object, "kind"));
    return .{
        .kind = if (kind == .use_ability and side == .runner and installed_resource_index != null and ability_index != null and ability_index.? == 0) .use_installed_ability else kind,
        .side = side,
        .prompt_type = try dupeOptionalString(allocator, try getOptional(.string, object, "prompt-type")),
        .choice = choice,
        .server = try dupeOptionalString(allocator, try getOptional(.string, object, "server")),
        .card_index = installed_resource_index orelse try parseOptionalCardIndex(object),
        .card_title = try dupeOptionalString(allocator, try getOptional(.string, object, "card-title")),
        .basic_action = if (kind == .use_ability and installed_resource_index == null)
            if (ability_index) |idx| try parseBasicAction(side, idx) else null
        else
            null,
        .installed_ability = if (kind == .use_ability and side == .runner and installed_resource_index != null and ability_index != null and ability_index.? == 0) .take_credits else null,
        .label = try dupeOptionalString(allocator, try getOptional(.string, object, "label")),
    };
}

fn parseRunnerRigResourceCardIndex(
    object: std.json.ObjectMap,
) !?u8 {
    const locator = try getOptional(.array, object, "card-locator") orelse return null;
    if (locator.items.len != 4) return null;
    const a = try extractField(.string, locator.items[0]);
    const b = try extractField(.string, locator.items[1]);
    const c = try extractField(.string, locator.items[2]);
    if (!std.mem.eql(u8, a, "runner")) return null;
    if (!std.mem.eql(u8, b, "rig")) return null;
    if (!std.mem.eql(u8, c, "resource")) return null;
    return try castInteger(u8, try extractField(.integer, locator.items[3]));
}

fn parseBasicAction(side: state.Side, ability_index: u8) !state.BasicAction {
    return switch (side) {
        .corp => switch (ability_index) {
            0 => .gain_credit,
            1 => .draw_card,
            4 => .advance_installed,
            6 => .purge_viruses,
            else => error.UnsupportedAbility,
        },
        .runner => switch (ability_index) {
            0 => .gain_credit,
            1 => .draw_card,
            2 => .install_from_grip,
            4 => .run_any_server,
            else => error.UnsupportedAbility,
        },
    };
}

fn parseRunnerTransitionOracle(
    allocator: std.mem.Allocator,
    transition: std.json.ObjectMap,
) !RunnerTransitionOracle {
    const transitions = try getRequired(.array, transition, "transitions");
    var keep: ?TransitionExpectation = null;
    var keep_transition: ?std.json.ObjectMap = null;
    var mulligan: ?TransitionExpectation = null;
    var mulligan_transition: ?std.json.ObjectMap = null;

    for (transitions.items) |item| {
        const nested = try expectObject(item);
        const action = try getRequired(.object, nested, "action");
        const result = try getRequired(.object, nested, "result");
        const choice = try getRequired(.object, action, "choice");
        const choice_value = try getRequired(.string, choice, "value");
        const parsed_transition = try parseTransitionExpectation(allocator, result);
        if (std.mem.eql(u8, choice_value, "Keep")) {
            keep = parsed_transition;
            keep_transition = nested;
        } else if (std.mem.eql(u8, choice_value, "Mulligan")) {
            mulligan = parsed_transition;
            mulligan_transition = nested;
        }
    }

    return .{
        .keep = keep orelse return error.MissingTransition,
        .keep_start_turn = try parseStartTurnOracle(allocator, keep_transition orelse return error.MissingTransition),
        .mulligan = mulligan orelse return error.MissingTransition,
        .mulligan_start_turn = try parseStartTurnOracle(allocator, mulligan_transition orelse return error.MissingTransition),
    };
}

fn parseScenarioExpectations(
    allocator: std.mem.Allocator,
    root: std.json.ObjectMap,
) ![]const ScenarioExpectation {
    const scenarios = try getOptional(.array, root, "scenarios") orelse return try allocator.alloc(ScenarioExpectation, 0);
    const parsed = try allocator.alloc(ScenarioExpectation, scenarios.items.len);
    for (scenarios.items, 0..) |item, idx| {
        const scenario = try expectObject(item);
        parsed[idx] = .{
            .name = try allocator.dupe(u8, try getRequired(.string, scenario, "name")),
            .actions = try parseActionExpectations(allocator, try getRequired(.array, scenario, "actions")),
            .result = try parseTransitionExpectation(allocator, try getRequired(.object, scenario, "result")),
        };
    }
    return parsed;
}

fn parseStartTurnOracle(
    allocator: std.mem.Allocator,
    transition: std.json.ObjectMap,
) !StartTurnOracle {
    const transitions = try getRequired(.array, transition, "transitions");
    if (transitions.items.len != 1) return error.MissingTransition;

    const nested = try expectObject(transitions.items[0]);
    const action = try getRequired(.object, nested, "action");
    const result = try getRequired(.object, nested, "result");

    if (try parseActionKind(try getRequired(.string, action, "kind")) != .start_turn) {
        return error.InvalidActionKind;
    }

    return .{
        .transition = try parseTransitionExpectation(allocator, result),
        .basic_actions = try parseBasicActionOracle(allocator, nested),
        .play_from_hand = try parseCardPlayExpectations(allocator, nested),
    };
}

fn parseBasicActionOracle(
    allocator: std.mem.Allocator,
    transition: std.json.ObjectMap,
) !BasicActionOracle {
    const transitions = try getRequired(.array, transition, "transitions");
    var gain_credit: ?TransitionExpectation = null;
    var draw_card: ?TransitionExpectation = null;
    var advance_card: ?TransitionExpectation = null;
    var purge_viruses: ?TransitionExpectation = null;

    for (transitions.items) |item| {
        const nested = try expectObject(item);
        const action = try getRequired(.object, nested, "action");
        const ability_index = try getOptionalIntegerAs(u8, action, "ability-index") orelse continue;
        const result = try getRequired(.object, nested, "result");
        const parsed_transition = try parseTransitionExpectation(allocator, result);

        switch (ability_index) {
            0 => gain_credit = parsed_transition,
            1 => draw_card = parsed_transition,
            4 => advance_card = parsed_transition,
            6 => purge_viruses = parsed_transition,
            else => {},
        }
    }

    return .{
        .gain_credit = gain_credit orelse return error.MissingTransition,
        .draw_card = draw_card orelse return error.MissingTransition,
        .advance_card = advance_card orelse return error.MissingTransition,
        .purge_viruses = purge_viruses orelse return error.MissingTransition,
    };
}

fn parseCardPlayExpectations(
    allocator: std.mem.Allocator,
    transition: std.json.ObjectMap,
) ![]const CardPlayExpectation {
    const transitions = try getRequired(.array, transition, "transitions");
    var count: usize = 0;
    for (transitions.items) |item| {
        const nested = try expectObject(item);
        const action = try getRequired(.object, nested, "action");
        if (try parseActionKind(try getRequired(.string, action, "kind")) == .play_from_hand) {
            count += 1;
        }
    }

    const expectations = try allocator.alloc(CardPlayExpectation, count);
    var idx: usize = 0;
    for (transitions.items) |item| {
        const nested = try expectObject(item);
        const action = try getRequired(.object, nested, "action");
        if (try parseActionKind(try getRequired(.string, action, "kind")) != .play_from_hand) continue;

        expectations[idx] = .{
            .card_title = try allocator.dupe(u8, try getRequired(.string, action, "card-title")),
            .result = try parseTransitionExpectation(allocator, try getRequired(.object, nested, "result")),
            .prompt_choices = try parsePromptChoiceExpectations(allocator, nested),
        };
        idx += 1;
    }

    return expectations;
}

fn parsePromptChoiceExpectations(
    allocator: std.mem.Allocator,
    transition: std.json.ObjectMap,
) ![]const PromptChoiceExpectation {
    const transitions = try getOptional(.array, transition, "transitions") orelse return try allocator.alloc(PromptChoiceExpectation, 0);
    var count: usize = 0;
    for (transitions.items) |item| {
        const nested = try expectObject(item);
        const action = try getRequired(.object, nested, "action");
        if (try parseActionKind(try getRequired(.string, action, "kind")) == .prompt_choice) {
            count += 1;
        }
    }

    const expectations = try allocator.alloc(PromptChoiceExpectation, count);
    var idx: usize = 0;
    for (transitions.items) |item| {
        const nested = try expectObject(item);
        const action = try getRequired(.object, nested, "action");
        if (try parseActionKind(try getRequired(.string, action, "kind")) != .prompt_choice) continue;

        const choice = try getRequired(.object, action, "choice");
        expectations[idx] = .{
            .choice_text = try allocator.dupe(u8, try getRequired(.string, choice, "value")),
            .result = try parseTransitionExpectation(allocator, try getRequired(.object, nested, "result")),
        };
        idx += 1;
    }

    return expectations;
}

fn parseTransitionExpectation(
    allocator: std.mem.Allocator,
    result: std.json.ObjectMap,
) !TransitionExpectation {
    const oracle_state = try getRequired(.object, result, "oracle-state");
    const corp = try getRequired(.object, oracle_state, "corp");
    const runner = try getRequired(.object, oracle_state, "runner");
    const legal_actions = try getRequired(.array, result, "legal-actions");

    return .{
        .decision_side = try parseSide(try getRequired(.string, result, "decision-side")),
        .active_player = try parseSide(try getRequired(.string, oracle_state, "active-player")),
        .turn = try getIntegerAs(u16, oracle_state, "turn"),
        .end_turn = try getBool(oracle_state, "end-turn"),
        .run = try parseOptionalRunState(allocator, oracle_state, "run"),
        .corp_credit = try getIntegerAs(u16, corp, "credit"),
        .runner_credit = try getIntegerAs(u16, runner, "credit"),
        .runner_run_credit = try getIntegerAsOrDefault(u16, runner, "run-credit", 0),
        .corp_click = try getIntegerAs(u8, corp, "click"),
        .runner_click = try getIntegerAs(u8, runner, "click"),
        .corp_agenda_point = try getIntegerAs(u8, corp, "agenda-point"),
        .runner_agenda_point = try getIntegerAs(u8, runner, "agenda-point"),
        .corp_keep = try parseKeepState(corp, "keep"),
        .runner_keep = try parseKeepState(runner, "keep"),
        .rng_seed = try getInteger(oracle_state, "rng-seed"),
        .corp_prompt_type = try dupeOptionalString(allocator, try getPromptType(corp)),
        .runner_prompt_type = try dupeOptionalString(allocator, try getPromptType(runner)),
        .legal_actions = try parseActionExpectations(allocator, legal_actions),
        .corp_servers = try parseServers(allocator, corp),
        .corp_hand = try parseCards(allocator, corp, "hand"),
        .corp_deck = try parseCards(allocator, corp, "deck"),
        .runner_hand = try parseCards(allocator, runner, "hand"),
        .runner_deck = try parseCards(allocator, runner, "deck"),
    };
}

fn parseActionExpectations(
    allocator: std.mem.Allocator,
    actions: std.json.Array,
) ![]const ActionExpectation {
    const parsed = try allocator.alloc(ActionExpectation, actions.items.len);
    for (actions.items, 0..) |item, idx| {
        const action = try expectObject(item);
        const side = try parseSide(try getRequired(.string, action, "side"));
        const ability_index = try getOptionalIntegerAs(u8, action, "ability-index");
        const installed_resource_index = try parseRunnerRigResourceCardIndex(action);
        const choice_text = if (try getOptional(.object, action, "choice")) |choice|
            try dupeOptionalString(allocator, try getOptional(.string, choice, "value"))
        else
            null;
        const raw_kind = try parseActionKind(try getRequired(.string, action, "kind"));

        parsed[idx] = .{
            .kind = if (raw_kind == .use_ability and side == .runner and installed_resource_index != null and ability_index != null and ability_index.? == 0) .use_installed_ability else raw_kind,
            .side = side,
            .choice_text = choice_text,
            .server = try dupeOptionalString(allocator, try getOptional(.string, action, "server")),
            .card_index = installed_resource_index orelse try parseOptionalCardIndex(action),
            .card_title = try dupeOptionalString(allocator, try getOptional(.string, action, "card-title")),
            .ability_index = ability_index,
            .label = try dupeOptionalString(allocator, try getOptional(.string, action, "label")),
        };
    }
    return parsed;
}

fn parseCards(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    key: []const u8,
) ![]const state.CardInstance {
    const array = try getOptional(.array, object, key) orelse return try allocator.alloc(state.CardInstance, 0);
    const cards = try allocator.alloc(state.CardInstance, array.items.len);
    for (array.items, 0..) |item, idx| {
        cards[idx] = try parseCard(allocator, try expectObject(item));
    }
    return cards;
}

fn parseOptionalCards(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    key: []const u8,
) ![]const state.CardInstance {
    if (try getOptional(.array, object, key) == null) return try allocator.alloc(state.CardInstance, 0);
    return parseCards(allocator, object, key);
}

fn parseServers(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) ![]const state.ServerSlot {
    const servers = try getOptional(.object, object, "servers") orelse return try allocator.alloc(state.ServerSlot, 0);

    var count: usize = 0;
    if (servers.contains("hq")) count += 1;
    if (servers.contains("rd")) count += 1;
    if (servers.contains("archives")) count += 1;
    var remote_count: usize = 0;
    var iter = servers.iterator();
    while (iter.next()) |entry| {
        if (std.mem.startsWith(u8, entry.key_ptr.*, "remote")) {
            count += 1;
            remote_count += 1;
        }
    }
    const remote_names = try allocator.alloc([]const u8, remote_count);
    defer allocator.free(remote_names);
    var remote_idx: usize = 0;
    iter = servers.iterator();
    while (iter.next()) |entry| {
        if (std.mem.startsWith(u8, entry.key_ptr.*, "remote")) {
            remote_names[remote_idx] = entry.key_ptr.*;
            remote_idx += 1;
        }
    }
    std.mem.sort([]const u8, remote_names, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);

    const parsed = try allocator.alloc(state.ServerSlot, count);
    var idx: usize = 0;
    for ([_][]const u8{ "hq", "rd", "archives" }) |name| {
        if (try getOptional(.object, servers, name)) |server_object| {
            parsed[idx] = .{
                .name = try normalizeInternalServerName(allocator, name),
                .state = .{
                    .ices = try parseCards(allocator, server_object, "ices"),
                    .content = try parseCards(allocator, server_object, "content"),
                },
            };
            idx += 1;
        }
    }
    for (remote_names) |name| {
        const server_object = try getRequired(.object, servers, name);
        parsed[idx] = .{
            .name = try normalizeInternalServerName(allocator, name),
            .state = .{
                .ices = try parseCards(allocator, server_object, "ices"),
                .content = try parseCards(allocator, server_object, "content"),
            },
        };
        idx += 1;
    }
    return parsed;
}

fn normalizeInternalServerName(
    allocator: std.mem.Allocator,
    name: []const u8,
) ![]const u8 {
    if (std.mem.eql(u8, name, "rd")) return allocator.dupe(u8, "rnd");
    return allocator.dupe(u8, name);
}

fn parseOptionalCardIndex(object: std.json.ObjectMap) !?u8 {
    const locator = try getOptional(.array, object, "card-locator") orelse return null;
    if (locator.items.len < 3) return null;
    const zone = switch (locator.items[1]) {
        .string => |text| text,
        else => return null,
    };
    if (!std.mem.eql(u8, zone, "hand") and
        !std.mem.eql(u8, zone, "discard") and
        !std.mem.eql(u8, zone, "play-area") and
        !std.mem.eql(u8, zone, "current") and
        !std.mem.eql(u8, zone, "set-aside") and
        !std.mem.eql(u8, zone, "scored"))
    {
        return null;
    }
    return switch (locator.items[locator.items.len - 1]) {
        .integer => |value| try castInteger(u8, value),
        else => null,
    };
}

fn parseHandSize(object: std.json.ObjectMap) !state.HandSize {
    return .{
        .base = try getIntegerAs(u8, object, "base"),
        .total = try getIntegerAs(u8, object, "total"),
    };
}

fn parseOptionalBadPublicity(
    object: std.json.ObjectMap,
    key: []const u8,
) !?state.BadPublicity {
    const bp = try getOptional(.object, object, key) orelse return null;
    return .{
        .base = try getIntegerAs(u8, bp, "base"),
        .additional = try getIntegerAs(u8, bp, "additional"),
    };
}

fn parseOptionalTagState(
    object: std.json.ObjectMap,
    key: []const u8,
) !?state.TagState {
    const tag = try getOptional(.object, object, key) orelse return null;
    return .{
        .base = try getIntegerAs(u8, tag, "base"),
        .total = try getIntegerAs(u8, tag, "total"),
        .is_tagged = try getBool(tag, "is-tagged"),
    };
}

fn parseOptionalMemoryState(
    object: std.json.ObjectMap,
    key: []const u8,
) !?state.MemoryState {
    const memory = try getOptional(.object, object, key) orelse return null;
    const only_for = try getOptional(.object, memory, "only-for");
    const caissa = if (only_for) |value| try getOptional(.object, value, "caissa") else null;
    const virus = if (only_for) |value| try getOptional(.object, value, "virus") else null;

    return .{
        .base = try getIntegerAs(u8, memory, "base"),
        .available = try getIntegerAs(u8, memory, "available"),
        .used = try getIntegerAs(u8, memory, "used"),
        .caissa_available = if (caissa) |value| try getIntegerAs(u8, value, "available") else 0,
        .caissa_used = if (caissa) |value| try getIntegerAs(u8, value, "used") else 0,
        .virus_available = if (virus) |value| try getIntegerAs(u8, value, "available") else 0,
        .virus_used = if (virus) |value| try getIntegerAs(u8, value, "used") else 0,
    };
}

fn freeRunnerTransitionOracle(allocator: std.mem.Allocator, oracle: *RunnerTransitionOracle) void {
    freeTransitionExpectation(allocator, &oracle.keep);
    freeStartTurnOracle(allocator, &oracle.keep_start_turn);
    freeTransitionExpectation(allocator, &oracle.mulligan);
    freeStartTurnOracle(allocator, &oracle.mulligan_start_turn);
    oracle.* = undefined;
}

fn freeStartTurnOracle(allocator: std.mem.Allocator, oracle: *StartTurnOracle) void {
    freeTransitionExpectation(allocator, &oracle.transition);
    freeBasicActionOracle(allocator, &oracle.basic_actions);
    freeCardPlayExpectations(allocator, oracle.play_from_hand);
    oracle.* = undefined;
}

fn freeBasicActionOracle(allocator: std.mem.Allocator, oracle: *BasicActionOracle) void {
    freeTransitionExpectation(allocator, &oracle.gain_credit);
    freeTransitionExpectation(allocator, &oracle.draw_card);
    freeTransitionExpectation(allocator, &oracle.advance_card);
    freeTransitionExpectation(allocator, &oracle.purge_viruses);
    oracle.* = undefined;
}

fn freeCardPlayExpectations(allocator: std.mem.Allocator, expectations: []const CardPlayExpectation) void {
    for (expectations) |expectation| {
        allocator.free(expectation.card_title);
        var result = expectation.result;
        freeTransitionExpectation(allocator, &result);
        freePromptChoiceExpectations(allocator, expectation.prompt_choices);
    }
    allocator.free(expectations);
}

fn freePromptChoiceExpectations(allocator: std.mem.Allocator, expectations: []const PromptChoiceExpectation) void {
    for (expectations) |expectation| {
        allocator.free(expectation.choice_text);
        var result = expectation.result;
        freeTransitionExpectation(allocator, &result);
    }
    allocator.free(expectations);
}

fn freeTransitionExpectation(allocator: std.mem.Allocator, transition: *TransitionExpectation) void {
    if (transition.run) |run| {
        for (run.server) |segment| allocator.free(segment);
        allocator.free(run.server);
        allocator.free(run.phase);
    }
    if (transition.corp_prompt_type) |text| allocator.free(text);
    if (transition.runner_prompt_type) |text| allocator.free(text);
    freeActionExpectations(allocator, transition.legal_actions);
    freeServers(allocator, transition.corp_servers);
    freeCards(allocator, transition.corp_hand);
    freeCards(allocator, transition.corp_deck);
    freeCards(allocator, transition.runner_hand);
    freeCards(allocator, transition.runner_deck);
    transition.* = undefined;
}

fn freeActionExpectations(allocator: std.mem.Allocator, actions: []const ActionExpectation) void {
    for (actions) |action| {
        if (action.choice_text) |text| allocator.free(text);
        if (action.server) |text| allocator.free(text);
        if (action.card_title) |text| allocator.free(text);
        if (action.label) |text| allocator.free(text);
    }
    allocator.free(actions);
}

fn freeCards(allocator: std.mem.Allocator, cards: []const state.CardInstance) void {
    for (cards) |card| {
        allocator.free(card.title);
        if (card.printed_title) |title| allocator.free(title);
        if (card.card_type) |card_type| allocator.free(card_type);
    }
    allocator.free(cards);
}

fn freeServers(allocator: std.mem.Allocator, servers: []const state.ServerSlot) void {
    for (servers) |server| {
        allocator.free(server.name);
        freeCards(allocator, server.state.ices);
        freeCards(allocator, server.state.content);
    }
    allocator.free(servers);
}

fn getPromptType(object: std.json.ObjectMap) !?[]const u8 {
    const prompt = try getOptional(.object, object, "prompt-state") orelse return null;
    return try getRequired(.string, prompt, "prompt-type");
}

fn parseSide(raw: []const u8) !state.Side {
    if (std.ascii.eqlIgnoreCase(raw, "corp")) return .corp;
    if (std.ascii.eqlIgnoreCase(raw, "runner")) return .runner;
    return error.InvalidSide;
}

fn parseChoiceKind(raw: []const u8) !state.ChoiceKind {
    return std.meta.stringToEnum(state.ChoiceKind, raw) orelse error.InvalidChoiceKind;
}

fn parseActionKind(raw: []const u8) !state.ActionKind {
    if (std.mem.eql(u8, raw, "prompt-choice")) return .prompt_choice;
    if (std.mem.eql(u8, raw, "continue")) return .@"continue";
    if (std.mem.eql(u8, raw, "start-turn")) return .start_turn;
    if (std.mem.eql(u8, raw, "end-turn")) return .end_turn;
    if (std.mem.eql(u8, raw, "install-from-hand")) return .install_from_hand;
    if (std.mem.eql(u8, raw, "play-from-hand")) return .play_from_hand;
    if (std.mem.eql(u8, raw, "flashback")) return .flashback;
    if (std.mem.eql(u8, raw, "use-ability")) return .use_ability;
    if (std.mem.eql(u8, raw, "use-installed-ability")) return .use_installed_ability;
    if (std.mem.eql(u8, raw, "use-corp-ability")) return .use_corp_ability;
    if (std.mem.eql(u8, raw, "use-runner-ability")) return .use_runner_ability;
    if (std.mem.eql(u8, raw, "use-subroutine")) return .use_subroutine;
    if (std.mem.eql(u8, raw, "run")) return .run;
    return error.InvalidActionKind;
}

fn parseKeepState(object: std.json.ObjectMap, key: []const u8) !state.KeepState {
    const value = try getValue(object, key);
    return switch (value) {
        .bool => |boolean| if (boolean) error.UnexpectedType else .undecided,
        .string => |text| blk: {
            if (std.mem.eql(u8, text, "keep")) break :blk .keep;
            if (std.mem.eql(u8, text, "mulligan")) break :blk .mulligan;
            break :blk error.UnexpectedType;
        },
        else => error.UnexpectedType,
    };
}

fn dupeString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return try allocator.dupe(u8, value);
}

fn dupeOptionalString(
    allocator: std.mem.Allocator,
    value: ?[]const u8,
) !?[]const u8 {
    return if (value) |text| try allocator.dupe(u8, text) else null;
}

fn getValue(object: std.json.ObjectMap, key: []const u8) !std.json.Value {
    return object.get(key) orelse error.MissingField;
}

fn getOptionalValue(object: std.json.ObjectMap, key: []const u8) ?std.json.Value {
    return object.get(key);
}

fn expectObject(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |object| object,
        else => error.UnexpectedType,
    };
}

const JsonField = enum {
    object,
    array,
    string,
    integer,
    boolean,
};

fn JsonFieldType(comptime field: JsonField) type {
    return switch (field) {
        .object => std.json.ObjectMap,
        .array => std.json.Array,
        .string => []const u8,
        .integer => i64,
        .boolean => bool,
    };
}

fn extractField(comptime field: JsonField, value: std.json.Value) !JsonFieldType(field) {
    return switch (field) {
        .object => switch (value) {
            .object => |object| object,
            else => error.UnexpectedType,
        },
        .array => switch (value) {
            .array => |array| array,
            else => error.UnexpectedType,
        },
        .string => switch (value) {
            .string => |string| string,
            else => error.UnexpectedType,
        },
        .integer => switch (value) {
            .integer => |integer| integer,
            else => error.UnexpectedType,
        },
        .boolean => switch (value) {
            .bool => |boolean| boolean,
            else => error.UnexpectedType,
        },
    };
}

fn getRequired(comptime field: JsonField, object: std.json.ObjectMap, key: []const u8) !JsonFieldType(field) {
    return try extractField(field, try getValue(object, key));
}

fn getOptional(comptime field: JsonField, object: std.json.ObjectMap, key: []const u8) !?JsonFieldType(field) {
    const value = getOptionalValue(object, key) orelse return null;
    return switch (value) {
        .null => null,
        else => try extractField(field, value),
    };
}

fn getInteger(object: std.json.ObjectMap, key: []const u8) !i64 {
    return try getRequired(.integer, object, key);
}

fn getOptionalInteger(object: std.json.ObjectMap, key: []const u8) !?i64 {
    return try getOptional(.integer, object, key);
}

fn getIntegerAs(comptime T: type, object: std.json.ObjectMap, key: []const u8) !T {
    return try castInteger(T, try getInteger(object, key));
}

fn getOptionalIntegerAs(comptime T: type, object: std.json.ObjectMap, key: []const u8) !?T {
    return if (try getOptionalInteger(object, key)) |value|
        try castInteger(T, value)
    else
        null;
}

fn getOptionalCardCode(object: std.json.ObjectMap, key: []const u8) !?u32 {
    const value = getOptionalValue(object, key) orelse return null;
    return switch (value) {
        .null => null,
        .integer => |integer| try castInteger(u32, integer),
        .string => |text| try std.fmt.parseInt(u32, text, 10),
        else => error.UnexpectedType,
    };
}

fn getIntegerAsOrDefault(
    comptime T: type,
    object: std.json.ObjectMap,
    key: []const u8,
    default: T,
) !T {
    return if (try getOptionalInteger(object, key)) |value|
        try castInteger(T, value)
    else
        default;
}

fn castInteger(comptime T: type, value: i64) !T {
    return std.math.cast(T, value) orelse error.IntegerOutOfRange;
}

fn getBool(object: std.json.ObjectMap, key: []const u8) !bool {
    return try getRequired(.boolean, object, key);
}

test "load beginner initial setup snapshot" {
    var beginner = try loadBeginnerInitialSnapshot(
        std.testing.allocator,
        "test/resources/parity/system-gateway-beginner-init.json",
    );
    defer beginner.deinit();

    const snapshot = beginner.snapshot;
    try std.testing.expectEqualStrings("system-gateway", snapshot.state.format);
    try std.testing.expectEqual(@as(u64, 1), snapshot.state.seed);
    try std.testing.expectEqual(state.Side.runner, snapshot.state.active_player);
    try std.testing.expectEqual(@as(u16, 0), snapshot.state.turn);
    try std.testing.expect(snapshot.state.end_turn);

    try std.testing.expectEqual(@as(u8, 5), snapshot.state.corp.hand_size.total);
    try std.testing.expectEqual(@as(usize, 5), snapshot.state.corp.hand.len);
    try std.testing.expectEqual(@as(usize, 29), snapshot.state.corp.deck.len);
    try std.testing.expectEqual(@as(u8, 5), snapshot.state.runner.hand_size.total);
    try std.testing.expectEqual(@as(usize, 5), snapshot.state.runner.hand.len);
    try std.testing.expectEqual(@as(usize, 25), snapshot.state.runner.deck.len);
    try std.testing.expectEqual(state.KeepState.undecided, snapshot.state.corp.keep);
    try std.testing.expectEqual(state.KeepState.undecided, snapshot.state.runner.keep);

    try std.testing.expectEqualStrings("Hedge Fund", snapshot.state.corp.hand[0].title);
    try std.testing.expectEqualStrings("Palisade", snapshot.state.corp.deck[0].title);
    try std.testing.expectEqualStrings("Sure Gamble", snapshot.state.runner.hand[0].title);
    try std.testing.expectEqualStrings("Sure Gamble", snapshot.state.runner.deck[0].title);

    try std.testing.expect(snapshot.state.corp.prompt_state != null);
    try std.testing.expect(snapshot.state.runner.prompt_state != null);
    try std.testing.expectEqualStrings("mulligan", snapshot.state.corp.prompt_state.?.prompt_type);
    try std.testing.expectEqualStrings("waiting", snapshot.state.runner.prompt_state.?.prompt_type);
    try std.testing.expectEqual(@as(usize, 2), snapshot.state.corp.prompt_state.?.choices.len);

    try std.testing.expectEqual(state.Side.corp, snapshot.decision_side);
    try std.testing.expectEqual(@as(usize, 2), snapshot.legal_actions.len);
    try std.testing.expectEqual(state.ActionKind.prompt_choice, snapshot.legal_actions[0].kind);
    try std.testing.expectEqualStrings("Keep", snapshot.legal_actions[0].choice.?.text.?);
    try std.testing.expectEqualStrings("Mulligan", snapshot.legal_actions[1].choice.?.text.?);
}

test "load beginner initial parity fixture summary" {
    const allocator = std.testing.allocator;
    var summary = try loadSummary(
        allocator,
        "test/resources/parity/system-gateway-beginner-init.json",
    );
    defer freeSummary(allocator, &summary);

    try std.testing.expectEqual(@as(u16, 1), summary.fixture_version);
    try std.testing.expectEqualStrings("initial-state", summary.fixture_kind);
    try std.testing.expectEqualStrings("system-gateway-beginner", summary.matchup);
    try std.testing.expectEqual(@as(u64, 1), summary.seed);
    try std.testing.expectEqualStrings("corp", summary.decision_side);
    try std.testing.expectEqual(@as(usize, 2), summary.legal_action_count);
    try std.testing.expectEqual(@as(usize, 2), summary.transition_count);
}
