const std = @import("std");
const state = @import("state.zig");

pub const BeginnerInitialSnapshot = struct {
    arena: std.heap.ArenaAllocator,
    snapshot: state.SetupSnapshot,

    pub fn deinit(self: *BeginnerInitialSnapshot) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn loadBeginnerInitialSnapshot(
    backing_allocator: std.mem.Allocator,
    fixture_path: []const u8,
) !BeginnerInitialSnapshot {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();

    const allocator = arena.allocator();
    const source = try std.fs.cwd().readFileAlloc(allocator, fixture_path, 1 << 20);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, source, .{});

    const root = parsed.value.object;
    const initial = try getRequired(.object, root, "initial");
    const oracle_state = try getRequired(.object, initial, "oracle-state");
    const legal_actions_value = try getRequired(.array, initial, "legal-actions");

    return .{
        .arena = arena,
        .snapshot = .{
            .state = try parseGameState(allocator, oracle_state),
            .decision_side = try parseSide(try getRequired(.string, initial, "decision-side")),
            .legal_actions = try parseLegalActions(allocator, legal_actions_value),
        },
    };
}

fn parseGameState(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) !state.GameState {
    return .{
        .format = try dupeString(allocator, try getRequired(.string, object, "format")),
        .seed = try getIntegerAs(state.Seed, object, "seed"),
        .rng_seed = try getOptionalInteger(object, "rng-seed"),
        .active_player = try parseSide(try getRequired(.string, object, "active-player")),
        .turn = try getIntegerAs(state.TurnNumber, object, "turn"),
        .end_turn = try getBool(object, "end-turn"),
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
        .click = try getIntegerAs(state.TinyCount, object, "click"),
        .click_per_turn = try getIntegerAs(state.TinyCount, object, "click-per-turn"),
        .credit = try getIntegerAs(state.Count, object, "credit"),
        .agenda_point = try getIntegerAs(state.TinyCount, object, "agenda-point"),
        .agenda_point_req = try getIntegerAs(state.TinyCount, object, "agenda-point-req"),
        .hand_size = try parseHandSize(try getRequired(.object, object, "hand-size")),
        .bad_publicity = try parseOptionalBadPublicity(object, "bad-publicity"),
        .run_credit = try getIntegerAsOrDefault(state.Count, object, "run-credit", 0),
        .link = try getIntegerAsOrDefault(state.TinyCount, object, "link", 0),
        .tag = try parseOptionalTagState(object, "tag"),
        .memory = try parseOptionalMemoryState(object, "memory"),
        .brain_damage = try getIntegerAsOrDefault(state.TinyCount, object, "brain-damage", 0),
        .keep = try parseKeepState(object, "keep"),
        .prompt_state = try parseOptionalPromptState(allocator, object, "prompt-state"),
        .deck = try parseCards(allocator, object, "deck"),
        .hand = try parseCards(allocator, object, "hand"),
        .discard = try parseCards(allocator, object, "discard"),
    };
}

fn parseCards(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    key: []const u8,
) ![]const state.CardInstance {
    const array = try getOptional(.array, object, key) orelse return &.{};
    const cards = try allocator.alloc(state.CardInstance, array.items.len);
    for (array.items, 0..) |item, idx| {
        cards[idx] = try parseCard(allocator, try expectObject(item));
    }
    return cards;
}

fn parseCard(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) !state.CardInstance {
    return .{
        .title = try dupeString(allocator, try getRequired(.string, object, "title")),
        .printed_title = try dupeOptionalString(allocator, try getOptional(.string, object, "printed-title")),
        .code = try getOptionalIntegerAs(state.CardCode, object, "code"),
        .side = try parseSide(try getRequired(.string, object, "side")),
        .card_type = try dupeOptionalString(allocator, try getOptional(.string, object, "type")),
    };
}

fn parseOptionalPromptState(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    key: []const u8,
) !?state.PromptState {
    const prompt_object = try getOptional(.object, object, key) orelse return null;
    const choices = try parsePromptChoices(allocator, prompt_object);
    return .{
        .prompt_type = try dupeString(allocator, try getRequired(.string, prompt_object, "prompt-type")),
        .choices = choices,
    };
}

fn parsePromptChoices(
    allocator: std.mem.Allocator,
    prompt_object: std.json.ObjectMap,
) ![]const state.PromptChoice {
    const array = try getOptional(.array, prompt_object, "choices") orelse return &.{};
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
            .number = try getOptionalIntegerAs(state.Count, object, "value"),
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
        .code = try getOptionalIntegerAs(state.CardCode, object, "code"),
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

    return .{
        .kind = try parseActionKind(try getRequired(.string, object, "kind")),
        .side = try parseSide(try getRequired(.string, object, "side")),
        .prompt_type = try dupeOptionalString(allocator, try getOptional(.string, object, "prompt-type")),
        .choice = choice,
        .server = try dupeOptionalString(allocator, try getOptional(.string, object, "server")),
        .ability_index = try getOptionalIntegerAs(state.TinyCount, object, "ability-index"),
        .label = try dupeOptionalString(allocator, try getOptional(.string, object, "label")),
    };
}

fn parseHandSize(object: std.json.ObjectMap) !state.HandSize {
    return .{
        .base = try getIntegerAs(state.TinyCount, object, "base"),
        .total = try getIntegerAs(state.TinyCount, object, "total"),
    };
}

fn parseOptionalBadPublicity(
    object: std.json.ObjectMap,
    key: []const u8,
) !?state.BadPublicity {
    const bp = try getOptional(.object, object, key) orelse return null;
    return .{
        .base = try getIntegerAs(state.TinyCount, bp, "base"),
        .additional = try getIntegerAs(state.TinyCount, bp, "additional"),
    };
}

fn parseOptionalTagState(
    object: std.json.ObjectMap,
    key: []const u8,
) !?state.TagState {
    const tag = try getOptional(.object, object, key) orelse return null;
    return .{
        .base = try getIntegerAs(state.TinyCount, tag, "base"),
        .total = try getIntegerAs(state.TinyCount, tag, "total"),
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
        .base = try getIntegerAs(state.TinyCount, memory, "base"),
        .available = try getIntegerAs(state.TinyCount, memory, "available"),
        .used = try getIntegerAs(state.TinyCount, memory, "used"),
        .caissa_available = if (caissa) |value| try getIntegerAs(state.TinyCount, value, "available") else 0,
        .caissa_used = if (caissa) |value| try getIntegerAs(state.TinyCount, value, "used") else 0,
        .virus_available = if (virus) |value| try getIntegerAs(state.TinyCount, value, "available") else 0,
        .virus_used = if (virus) |value| try getIntegerAs(state.TinyCount, value, "used") else 0,
    };
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
