const std = @import("std");
const flow = @import("flow.zig");
const generator = @import("generator.zig");
const matchups = @import("matchups.zig");
const fixture = @import("../parity/fixture.zig");
const setup = @import("setup.zig");
const state = @import("state.zig");

test "generated beginner setup matches oracle fixture for seed 1" {
    var oracle = try setup.loadBeginnerInitialSnapshot(
        std.testing.allocator,
        "test/resources/parity/system-gateway-beginner-init.json",
    );
    defer oracle.deinit();

    var generated = try generator.createInitialSnapshot(
        std.testing.allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer generated.deinit();

    try std.testing.expectEqual(oracle.snapshot.state.seed, generated.snapshot.state.seed);
    try std.testing.expectEqual(oracle.snapshot.state.rng_seed.?, generated.snapshot.state.rng_seed.?);
    try std.testing.expectEqual(oracle.snapshot.state.active_player, generated.snapshot.state.active_player);
    try std.testing.expectEqual(oracle.snapshot.state.turn, generated.snapshot.state.turn);
    try std.testing.expectEqual(oracle.snapshot.state.end_turn, generated.snapshot.state.end_turn);

    try std.testing.expectEqualStrings(oracle.snapshot.state.corp.identity.title, generated.snapshot.state.corp.identity.title);
    try std.testing.expectEqualStrings(oracle.snapshot.state.runner.identity.title, generated.snapshot.state.runner.identity.title);
    try std.testing.expectEqualStrings(oracle.snapshot.state.corp.basic_action_card.title, generated.snapshot.state.corp.basic_action_card.title);
    try std.testing.expectEqualStrings(oracle.snapshot.state.runner.basic_action_card.title, generated.snapshot.state.runner.basic_action_card.title);

    try std.testing.expectEqual(oracle.snapshot.state.corp.click_per_turn, generated.snapshot.state.corp.click_per_turn);
    try std.testing.expectEqual(oracle.snapshot.state.runner.click_per_turn, generated.snapshot.state.runner.click_per_turn);
    try std.testing.expectEqual(oracle.snapshot.state.corp.credit, generated.snapshot.state.corp.credit);
    try std.testing.expectEqual(oracle.snapshot.state.runner.credit, generated.snapshot.state.runner.credit);
    try std.testing.expectEqual(oracle.snapshot.state.corp.hand_size.total, generated.snapshot.state.corp.hand_size.total);
    try std.testing.expectEqual(oracle.snapshot.state.runner.hand_size.total, generated.snapshot.state.runner.hand_size.total);

    try std.testing.expectEqual(oracle.snapshot.decision_side, generated.snapshot.decision_side);
    try std.testing.expectEqual(oracle.snapshot.legal_actions.len, generated.snapshot.legal_actions.len);
    try std.testing.expectEqualStrings(oracle.snapshot.legal_actions[0].choice.?.text.?, generated.snapshot.legal_actions[0].choice.?.text.?);
    try std.testing.expectEqualStrings(oracle.snapshot.legal_actions[1].choice.?.text.?, generated.snapshot.legal_actions[1].choice.?.text.?);

    try expectSameTitles(oracle.snapshot.state.corp.hand, generated.snapshot.state.corp.hand);
    try expectSameTitles(oracle.snapshot.state.corp.deck, generated.snapshot.state.corp.deck);
    try expectSameTitles(oracle.snapshot.state.runner.hand, generated.snapshot.state.runner.hand);
    try expectSameTitles(oracle.snapshot.state.runner.deck, generated.snapshot.state.runner.deck);
}

fn expectSameTitles(expected: []const state.CardInstance, actual: []const state.CardInstance) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |lhs, rhs| {
        try std.testing.expectEqualStrings(lhs.title, rhs.title);
    }
}

test "corp mulligan transitions match oracle fixture" {
    const allocator = std.testing.allocator;
    var oracle = try fixture.loadTransitionOracle(
        allocator,
        "test/resources/parity/system-gateway-beginner-init.json",
    );
    defer fixture.freeTransitionOracle(allocator, &oracle);

    var keep_state = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer keep_state.deinit();
    try flow.applyMulliganChoice(&keep_state, .corp, .keep);
    try expectTransitionMatches(oracle.keep, keep_state.snapshot);

    var mulligan_state = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer mulligan_state.deinit();
    try flow.applyMulliganChoice(&mulligan_state, .corp, .mulligan);
    try expectTransitionMatches(oracle.mulligan, mulligan_state.snapshot);
}

fn expectTransitionMatches(expected: fixture.TransitionExpectation, actual: state.SetupSnapshot) !void {
    try std.testing.expectEqual(expected.decision_side, actual.decision_side);
    try std.testing.expectEqual(expected.active_player, actual.state.active_player);
    try std.testing.expectEqual(expected.turn, actual.state.turn);
    try std.testing.expectEqual(expected.end_turn, actual.state.end_turn);
    try std.testing.expectEqual(expected.corp_click, actual.state.corp.click);
    try std.testing.expectEqual(expected.runner_click, actual.state.runner.click);
    try std.testing.expectEqual(expected.corp_keep, actual.state.corp.keep);
    try std.testing.expectEqual(expected.runner_keep, actual.state.runner.keep);
    try std.testing.expectEqual(expected.rng_seed, actual.state.rng_seed.?);

    try expectOptionalString(expected.corp_prompt_type, if (actual.state.corp.prompt_state) |prompt| prompt.prompt_type else null);
    try expectOptionalString(expected.runner_prompt_type, if (actual.state.runner.prompt_state) |prompt| prompt.prompt_type else null);
    try expectActions(expected.legal_actions, actual.legal_actions);

    try expectSameTitles(expected.corp_hand, actual.state.corp.hand);
    try expectSameTitles(expected.corp_deck, actual.state.corp.deck);
    try expectSameTitles(expected.runner_hand, actual.state.runner.hand);
    try expectSameTitles(expected.runner_deck, actual.state.runner.deck);
}

test "runner mulligan transitions match oracle fixture" {
    const allocator = std.testing.allocator;
    var oracle = try fixture.loadTransitionOracle(
        allocator,
        "test/resources/parity/system-gateway-beginner-init.json",
    );
    defer fixture.freeTransitionOracle(allocator, &oracle);

    var corp_keep_runner_keep = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_keep_runner_keep.deinit();
    try flow.applyMulliganChoice(&corp_keep_runner_keep, .corp, .keep);
    try flow.applyMulliganChoice(&corp_keep_runner_keep, .runner, .keep);
    try expectTransitionMatches(oracle.runner_after_corp_keep.keep, corp_keep_runner_keep.snapshot);

    var corp_keep_runner_mulligan = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_keep_runner_mulligan.deinit();
    try flow.applyMulliganChoice(&corp_keep_runner_mulligan, .corp, .keep);
    try flow.applyMulliganChoice(&corp_keep_runner_mulligan, .runner, .mulligan);
    try expectTransitionMatches(oracle.runner_after_corp_keep.mulligan, corp_keep_runner_mulligan.snapshot);

    var corp_mulligan_runner_keep = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_mulligan_runner_keep.deinit();
    try flow.applyMulliganChoice(&corp_mulligan_runner_keep, .corp, .mulligan);
    try flow.applyMulliganChoice(&corp_mulligan_runner_keep, .runner, .keep);
    try expectTransitionMatches(oracle.runner_after_corp_mulligan.keep, corp_mulligan_runner_keep.snapshot);

    var corp_mulligan_runner_mulligan = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_mulligan_runner_mulligan.deinit();
    try flow.applyMulliganChoice(&corp_mulligan_runner_mulligan, .corp, .mulligan);
    try flow.applyMulliganChoice(&corp_mulligan_runner_mulligan, .runner, .mulligan);
    try expectTransitionMatches(oracle.runner_after_corp_mulligan.mulligan, corp_mulligan_runner_mulligan.snapshot);
}

test "corp start-turn transitions match oracle fixture" {
    const allocator = std.testing.allocator;
    var oracle = try fixture.loadTransitionOracle(
        allocator,
        "test/resources/parity/system-gateway-beginner-init.json",
    );
    defer fixture.freeTransitionOracle(allocator, &oracle);

    var corp_keep_runner_keep = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_keep_runner_keep.deinit();
    try flow.applyMulliganChoice(&corp_keep_runner_keep, .corp, .keep);
    try flow.applyMulliganChoice(&corp_keep_runner_keep, .runner, .keep);
    try flow.applyStartTurn(&corp_keep_runner_keep, .corp);
    try expectTransitionMatches(oracle.runner_after_corp_keep.keep_start_turn, corp_keep_runner_keep.snapshot);

    var corp_keep_runner_mulligan = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_keep_runner_mulligan.deinit();
    try flow.applyMulliganChoice(&corp_keep_runner_mulligan, .corp, .keep);
    try flow.applyMulliganChoice(&corp_keep_runner_mulligan, .runner, .mulligan);
    try flow.applyStartTurn(&corp_keep_runner_mulligan, .corp);
    try expectTransitionMatches(oracle.runner_after_corp_keep.mulligan_start_turn, corp_keep_runner_mulligan.snapshot);

    var corp_mulligan_runner_keep = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_mulligan_runner_keep.deinit();
    try flow.applyMulliganChoice(&corp_mulligan_runner_keep, .corp, .mulligan);
    try flow.applyMulliganChoice(&corp_mulligan_runner_keep, .runner, .keep);
    try flow.applyStartTurn(&corp_mulligan_runner_keep, .corp);
    try expectTransitionMatches(oracle.runner_after_corp_mulligan.keep_start_turn, corp_mulligan_runner_keep.snapshot);

    var corp_mulligan_runner_mulligan = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_mulligan_runner_mulligan.deinit();
    try flow.applyMulliganChoice(&corp_mulligan_runner_mulligan, .corp, .mulligan);
    try flow.applyMulliganChoice(&corp_mulligan_runner_mulligan, .runner, .mulligan);
    try flow.applyStartTurn(&corp_mulligan_runner_mulligan, .corp);
    try expectTransitionMatches(oracle.runner_after_corp_mulligan.mulligan_start_turn, corp_mulligan_runner_mulligan.snapshot);
}

fn expectActions(expected: []const fixture.ActionExpectation, actual: []const state.LegalAction) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |lhs, rhs| {
        try std.testing.expectEqual(lhs.kind, rhs.kind);
        try std.testing.expectEqual(lhs.side, rhs.side);
        try expectOptionalString(lhs.choice_text, if (rhs.choice) |choice| choice.text else null);
        try expectOptionalString(lhs.server, rhs.server);
        try std.testing.expectEqual(lhs.ability_index, rhs.ability_index);
        try expectOptionalString(lhs.label, rhs.label);
    }
}

fn expectOptionalString(expected: ?[]const u8, actual: ?[]const u8) !void {
    if (expected) |lhs| {
        if (actual) |rhs| {
            try std.testing.expectEqualStrings(lhs, rhs);
        } else {
            return error.TestExpectedEqual;
        }
    } else {
        try std.testing.expect(actual == null);
    }
}
