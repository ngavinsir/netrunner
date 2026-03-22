const std = @import("std");
const state = @import("../engine/state.zig");

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
    ability_index: ?state.TinyCount = null,
    label: ?[]const u8 = null,
};

pub const TransitionExpectation = struct {
    decision_side: state.Side,
    active_player: state.Side,
    turn: state.TurnNumber,
    end_turn: bool,
    corp_click: state.TinyCount,
    runner_click: state.TinyCount,
    corp_keep: state.KeepState,
    runner_keep: state.KeepState,
    rng_seed: state.RngSeed,
    corp_prompt_type: ?[]const u8,
    runner_prompt_type: ?[]const u8,
    legal_actions: []const ActionExpectation,
    corp_hand: []const state.CardInstance,
    corp_deck: []const state.CardInstance,
    runner_hand: []const state.CardInstance,
    runner_deck: []const state.CardInstance,
};

pub const RunnerTransitionOracle = struct {
    keep: TransitionExpectation,
    keep_start_turn: TransitionExpectation,
    mulligan: TransitionExpectation,
    mulligan_start_turn: TransitionExpectation,
};

pub const TransitionOracle = struct {
    keep: TransitionExpectation,
    mulligan: TransitionExpectation,
    runner_after_corp_keep: RunnerTransitionOracle,
    runner_after_corp_mulligan: RunnerTransitionOracle,
};

pub fn loadSummary(
    allocator: std.mem.Allocator,
    fixture_path: []const u8,
) !FixtureSummary {
    const source = try std.fs.cwd().readFileAlloc(allocator, fixture_path, 1 << 20);
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

pub fn freeSummary(allocator: std.mem.Allocator, summary: *FixtureSummary) void {
    allocator.free(summary.fixture_kind);
    allocator.free(summary.matchup);
    allocator.free(summary.decision_side);
    summary.* = undefined;
}

pub fn loadTransitionOracle(
    allocator: std.mem.Allocator,
    fixture_path: []const u8,
) !TransitionOracle {
    const source = try std.fs.cwd().readFileAlloc(allocator, fixture_path, 1 << 20);
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
    };
}

pub fn freeTransitionOracle(allocator: std.mem.Allocator, oracle: *TransitionOracle) void {
    freeTransitionExpectation(allocator, &oracle.keep);
    freeTransitionExpectation(allocator, &oracle.mulligan);
    freeRunnerTransitionOracle(allocator, &oracle.runner_after_corp_keep);
    freeRunnerTransitionOracle(allocator, &oracle.runner_after_corp_mulligan);
    oracle.* = undefined;
}

fn freeRunnerTransitionOracle(allocator: std.mem.Allocator, oracle: *RunnerTransitionOracle) void {
    freeTransitionExpectation(allocator, &oracle.keep);
    freeTransitionExpectation(allocator, &oracle.keep_start_turn);
    freeTransitionExpectation(allocator, &oracle.mulligan);
    freeTransitionExpectation(allocator, &oracle.mulligan_start_turn);
    oracle.* = undefined;
}

fn freeTransitionExpectation(allocator: std.mem.Allocator, transition: *TransitionExpectation) void {
    if (transition.corp_prompt_type) |text| allocator.free(text);
    if (transition.runner_prompt_type) |text| allocator.free(text);
    freeActionExpectations(allocator, transition.legal_actions);
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
        .keep_start_turn = try parseNestedStartTurnExpectation(allocator, keep_transition orelse return error.MissingTransition),
        .mulligan = mulligan orelse return error.MissingTransition,
        .mulligan_start_turn = try parseNestedStartTurnExpectation(allocator, mulligan_transition orelse return error.MissingTransition),
    };
}

fn parseNestedStartTurnExpectation(
    allocator: std.mem.Allocator,
    transition: std.json.ObjectMap,
) !TransitionExpectation {
    const transitions = try getRequired(.array, transition, "transitions");
    if (transitions.items.len != 1) return error.MissingTransition;

    const nested = try expectObject(transitions.items[0]);
    const action = try getRequired(.object, nested, "action");
    const result = try getRequired(.object, nested, "result");

    if (try parseActionKind(try getRequired(.string, action, "kind")) != .start_turn) {
        return error.InvalidActionKind;
    }

    return try parseTransitionExpectation(allocator, result);
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
        .turn = try getIntegerAs(state.TurnNumber, oracle_state, "turn"),
        .end_turn = switch (try getValue(oracle_state, "end-turn")) {
            .bool => |value| value,
            else => return error.UnexpectedType,
        },
        .corp_click = try getIntegerAs(state.TinyCount, corp, "click"),
        .runner_click = try getIntegerAs(state.TinyCount, runner, "click"),
        .corp_keep = try parseKeepState(corp, "keep"),
        .runner_keep = try parseKeepState(runner, "keep"),
        .rng_seed = try getInteger(oracle_state, "rng-seed"),
        .corp_prompt_type = try dupeOptionalString(allocator, try getPromptType(corp)),
        .runner_prompt_type = try dupeOptionalString(allocator, try getPromptType(runner)),
        .legal_actions = try parseActionExpectations(allocator, legal_actions),
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
        const choice_text = if (try getOptional(.object, action, "choice")) |choice|
            try dupeOptionalString(allocator, try getOptional(.string, choice, "value"))
        else
            null;

        parsed[idx] = .{
            .kind = try parseActionKind(try getRequired(.string, action, "kind")),
            .side = try parseSide(try getRequired(.string, action, "side")),
            .choice_text = choice_text,
            .server = try dupeOptionalString(allocator, try getOptional(.string, action, "server")),
            .ability_index = try getOptionalIntegerAs(state.TinyCount, action, "ability-index"),
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
    const array = try getRequired(.array, object, key);
    const cards = try allocator.alloc(state.CardInstance, array.items.len);
    for (array.items, 0..) |item, idx| {
        const card = try expectObject(item);
        cards[idx] = .{
            .title = try allocator.dupe(u8, try getRequired(.string, card, "title")),
            .printed_title = try dupeOptionalString(allocator, try getOptional(.string, card, "printed-title")),
            .code = try getOptionalIntegerAs(state.CardCode, card, "code"),
            .side = try parseSide(try getRequired(.string, card, "side")),
            .card_type = try dupeOptionalString(allocator, try getOptional(.string, card, "type")),
        };
    }
    return cards;
}

fn getPromptType(object: std.json.ObjectMap) !?[]const u8 {
    const prompt = try getOptional(.object, object, "prompt-state") orelse return null;
    return try getRequired(.string, prompt, "prompt-type");
}

fn getValue(object: std.json.ObjectMap, key: []const u8) !std.json.Value {
    return object.get(key) orelse return error.MissingField;
}

fn getOptionalValue(object: std.json.ObjectMap, key: []const u8) ?std.json.Value {
    return object.get(key);
}

fn expectObject(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |inner| inner,
        else => error.UnexpectedType,
    };
}

const JsonField = enum {
    object,
    array,
    string,
    integer,
};

fn JsonFieldType(comptime field: JsonField) type {
    return switch (field) {
        .object => std.json.ObjectMap,
        .array => std.json.Array,
        .string => []const u8,
        .integer => i64,
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

fn castInteger(comptime T: type, value: i64) !T {
    return std.math.cast(T, value) orelse error.IntegerOutOfRange;
}

fn dupeOptionalString(
    allocator: std.mem.Allocator,
    value: ?[]const u8,
) !?[]const u8 {
    return if (value) |text| try allocator.dupe(u8, text) else null;
}

fn parseSide(raw: []const u8) !state.Side {
    if (std.ascii.eqlIgnoreCase(raw, "corp")) return .corp;
    if (std.ascii.eqlIgnoreCase(raw, "runner")) return .runner;
    return error.InvalidSide;
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

fn parseActionKind(raw: []const u8) !state.ActionKind {
    if (std.mem.eql(u8, raw, "prompt-choice")) return .prompt_choice;
    if (std.mem.eql(u8, raw, "start-turn")) return .start_turn;
    if (std.mem.eql(u8, raw, "play-from-hand")) return .play_from_hand;
    if (std.mem.eql(u8, raw, "flashback")) return .flashback;
    if (std.mem.eql(u8, raw, "use-ability")) return .use_ability;
    if (std.mem.eql(u8, raw, "use-corp-ability")) return .use_corp_ability;
    if (std.mem.eql(u8, raw, "use-runner-ability")) return .use_runner_ability;
    if (std.mem.eql(u8, raw, "use-subroutine")) return .use_subroutine;
    if (std.mem.eql(u8, raw, "run")) return .run;
    return error.InvalidActionKind;
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
