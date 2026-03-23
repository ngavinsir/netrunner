const std = @import("std");
const game = @import("game.zig");
const matchups = @import("catalog.zig");
const fixture = @import("../parity/oracle.zig");
const setup = fixture;
const state = @import("state.zig");
const flow = game;
const generator = game;

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

fn expectTitleSuffix(expected: []const state.CardInstance, actual: []const state.CardInstance) !void {
    try std.testing.expect(actual.len >= expected.len);
    const offset = actual.len - expected.len;
    for (expected, actual[offset..]) |lhs, rhs| {
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

fn expectTransitionMatches(expected: fixture.TransitionExpectation, actual: state.GameSnapshot) !void {
    try std.testing.expectEqual(expected.decision_side, actual.decision_side);
    try std.testing.expectEqual(expected.active_player, actual.state.active_player);
    try std.testing.expectEqual(expected.turn, actual.state.turn);
    try std.testing.expectEqual(expected.end_turn, actual.state.end_turn);
    try expectOptionalRun(expected.run, actual.state.run);
    try std.testing.expectEqual(expected.corp_credit, actual.state.corp.credit);
    try std.testing.expectEqual(expected.runner_credit, actual.state.runner.credit);
    try std.testing.expectEqual(expected.runner_run_credit, actual.state.runner.run_credit);
    try std.testing.expectEqual(expected.corp_click, actual.state.corp.click);
    try std.testing.expectEqual(expected.runner_click, actual.state.runner.click);
    try std.testing.expectEqual(expected.corp_agenda_point, actual.state.corp.agenda_point);
    try std.testing.expectEqual(expected.runner_agenda_point, actual.state.runner.agenda_point);
    try std.testing.expectEqual(expected.corp_keep, actual.state.corp.keep);
    try std.testing.expectEqual(expected.runner_keep, actual.state.runner.keep);
    try std.testing.expectEqual(expected.rng_seed, actual.state.rng_seed.?);

    try expectOptionalString(expected.corp_prompt_type, if (actual.state.corp.prompt_state) |prompt| prompt.prompt_type else null);
    try expectOptionalString(expected.runner_prompt_type, if (actual.state.runner.prompt_state) |prompt| prompt.prompt_type else null);
    try expectActions(expected.legal_actions, actual.legal_actions);
    try expectServers(expected.corp_servers, actual.state.corp.servers);

    try expectSameTitles(expected.corp_hand, actual.state.corp.hand);
    try expectSameTitles(expected.corp_deck, actual.state.corp.deck);
    try expectSameTitles(expected.runner_hand, actual.state.runner.hand);
    try expectSameTitles(expected.runner_deck, actual.state.runner.deck);
}

fn expectOptionalRun(expected: ?state.RunState, actual: ?state.RunState) !void {
    if (expected) |lhs| {
        const rhs = actual orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(lhs.position, rhs.position);
        try std.testing.expectEqual(lhs.corp_auto_no_action, rhs.corp_auto_no_action);
        try std.testing.expectEqual(lhs.no_action, rhs.no_action);
        try std.testing.expectEqualStrings(lhs.phase, rhs.phase);
        try std.testing.expectEqual(lhs.server.len, rhs.server.len);
        for (lhs.server, rhs.server) |left, right| {
            try std.testing.expectEqualStrings(left, right);
        }
    } else {
        try std.testing.expect(actual == null);
    }
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
    try expectTransitionMatches(oracle.runner_after_corp_keep.keep_start_turn.transition, corp_keep_runner_keep.snapshot);

    var corp_keep_runner_mulligan = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_keep_runner_mulligan.deinit();
    try flow.applyMulliganChoice(&corp_keep_runner_mulligan, .corp, .keep);
    try flow.applyMulliganChoice(&corp_keep_runner_mulligan, .runner, .mulligan);
    try flow.applyStartTurn(&corp_keep_runner_mulligan, .corp);
    try expectTransitionMatches(oracle.runner_after_corp_keep.mulligan_start_turn.transition, corp_keep_runner_mulligan.snapshot);

    var corp_mulligan_runner_keep = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_mulligan_runner_keep.deinit();
    try flow.applyMulliganChoice(&corp_mulligan_runner_keep, .corp, .mulligan);
    try flow.applyMulliganChoice(&corp_mulligan_runner_keep, .runner, .keep);
    try flow.applyStartTurn(&corp_mulligan_runner_keep, .corp);
    try expectTransitionMatches(oracle.runner_after_corp_mulligan.keep_start_turn.transition, corp_mulligan_runner_keep.snapshot);

    var corp_mulligan_runner_mulligan = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_mulligan_runner_mulligan.deinit();
    try flow.applyMulliganChoice(&corp_mulligan_runner_mulligan, .corp, .mulligan);
    try flow.applyMulliganChoice(&corp_mulligan_runner_mulligan, .runner, .mulligan);
    try flow.applyStartTurn(&corp_mulligan_runner_mulligan, .corp);
    try expectTransitionMatches(oracle.runner_after_corp_mulligan.mulligan_start_turn.transition, corp_mulligan_runner_mulligan.snapshot);
}

test "corp basic action transitions match oracle fixture" {
    const allocator = std.testing.allocator;
    var oracle = try fixture.loadTransitionOracle(
        allocator,
        "test/resources/parity/system-gateway-beginner-init.json",
    );
    defer fixture.freeTransitionOracle(allocator, &oracle);

    var start_state = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer start_state.deinit();

    try flow.applyAction(&start_state, start_state.snapshot.legal_actions[0]);
    try flow.applyAction(&start_state, start_state.snapshot.legal_actions[0]);
    try flow.applyAction(&start_state, start_state.snapshot.legal_actions[0]);

    const start_turn_oracle = oracle.runner_after_corp_keep.keep_start_turn;

    var gain_credit = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer gain_credit.deinit();
    try flow.applyAction(&gain_credit, gain_credit.snapshot.legal_actions[0]);
    try flow.applyAction(&gain_credit, gain_credit.snapshot.legal_actions[0]);
    try flow.applyAction(&gain_credit, gain_credit.snapshot.legal_actions[0]);
    try flow.applyAction(&gain_credit, gain_credit.snapshot.legal_actions[try findBasicActionIndex(gain_credit.snapshot.legal_actions, .gain_credit)]);
    try expectTransitionMatches(start_turn_oracle.basic_actions.gain_credit, gain_credit.snapshot);

    var draw_card = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer draw_card.deinit();
    try flow.applyAction(&draw_card, draw_card.snapshot.legal_actions[0]);
    try flow.applyAction(&draw_card, draw_card.snapshot.legal_actions[0]);
    try flow.applyAction(&draw_card, draw_card.snapshot.legal_actions[0]);
    try flow.applyAction(&draw_card, draw_card.snapshot.legal_actions[try findBasicActionIndex(draw_card.snapshot.legal_actions, .draw_card)]);
    try expectTransitionMatches(start_turn_oracle.basic_actions.draw_card, draw_card.snapshot);

    var advance_card = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer advance_card.deinit();
    try flow.applyAction(&advance_card, advance_card.snapshot.legal_actions[0]);
    try flow.applyAction(&advance_card, advance_card.snapshot.legal_actions[0]);
    try flow.applyAction(&advance_card, advance_card.snapshot.legal_actions[0]);
    try flow.applyAction(&advance_card, advance_card.snapshot.legal_actions[try findBasicActionIndex(advance_card.snapshot.legal_actions, .advance_installed)]);
    try expectTransitionMatches(start_turn_oracle.basic_actions.advance_card, advance_card.snapshot);

    var purge_viruses = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer purge_viruses.deinit();
    try flow.applyAction(&purge_viruses, purge_viruses.snapshot.legal_actions[0]);
    try flow.applyAction(&purge_viruses, purge_viruses.snapshot.legal_actions[0]);
    try flow.applyAction(&purge_viruses, purge_viruses.snapshot.legal_actions[0]);
    try flow.applyAction(&purge_viruses, purge_viruses.snapshot.legal_actions[try findBasicActionIndex(purge_viruses.snapshot.legal_actions, .purge_viruses)]);
    try expectTransitionMatches(start_turn_oracle.basic_actions.purge_viruses, purge_viruses.snapshot);
}

test "corp play-from-hand transitions match oracle fixture" {
    const allocator = std.testing.allocator;
    var oracle = try fixture.loadTransitionOracle(
        allocator,
        "test/resources/parity/system-gateway-beginner-init.json",
    );
    defer fixture.freeTransitionOracle(allocator, &oracle);

    const keep_keep = oracle.runner_after_corp_keep.keep_start_turn;

    var hedge_fund = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer hedge_fund.deinit();
    try flow.applyAction(&hedge_fund, hedge_fund.snapshot.legal_actions[0]);
    try flow.applyAction(&hedge_fund, hedge_fund.snapshot.legal_actions[0]);
    try flow.applyAction(&hedge_fund, hedge_fund.snapshot.legal_actions[0]);
    try flow.applyAction(&hedge_fund, hedge_fund.snapshot.legal_actions[try findCardPlayActionIndex(hedge_fund.snapshot.legal_actions, "Hedge Fund")]);
    try expectTransitionMatches((try findCardPlayExpectation(keep_keep.play_from_hand, "Hedge Fund")).result, hedge_fund.snapshot);

    var bran = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer bran.deinit();
    try flow.applyAction(&bran, bran.snapshot.legal_actions[0]);
    try flow.applyAction(&bran, bran.snapshot.legal_actions[0]);
    try flow.applyAction(&bran, bran.snapshot.legal_actions[0]);
    try flow.applyAction(&bran, bran.snapshot.legal_actions[try findCardPlayActionIndex(bran.snapshot.legal_actions, "Brân 1.0")]);
    try expectTransitionMatches((try findCardPlayExpectation(keep_keep.play_from_hand, "Brân 1.0")).result, bran.snapshot);

    var regolith = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer regolith.deinit();
    try flow.applyAction(&regolith, regolith.snapshot.legal_actions[0]);
    try flow.applyAction(&regolith, regolith.snapshot.legal_actions[0]);
    try flow.applyAction(&regolith, regolith.snapshot.legal_actions[0]);
    try flow.applyAction(&regolith, regolith.snapshot.legal_actions[try findCardPlayActionIndex(regolith.snapshot.legal_actions, "Regolith Mining License")]);
    try expectTransitionMatches((try findCardPlayExpectation(keep_keep.play_from_hand, "Regolith Mining License")).result, regolith.snapshot);

    const mull_keep = oracle.runner_after_corp_mulligan.keep_start_turn;
    var seamless_launch = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer seamless_launch.deinit();
    try flow.applyMulliganChoice(&seamless_launch, .corp, .mulligan);
    try flow.applyMulliganChoice(&seamless_launch, .runner, .keep);
    try flow.applyStartTurn(&seamless_launch, .corp);
    try flow.applyAction(&seamless_launch, seamless_launch.snapshot.legal_actions[try findCardPlayActionIndex(seamless_launch.snapshot.legal_actions, "Seamless Launch")]);
    try expectTransitionMatches((try findCardPlayExpectation(mull_keep.play_from_hand, "Seamless Launch")).result, seamless_launch.snapshot);
}

test "corp install prompt resolutions match oracle fixture" {
    const allocator = std.testing.allocator;
    var oracle = try fixture.loadTransitionOracle(
        allocator,
        "test/resources/parity/system-gateway-beginner-init.json",
    );
    defer fixture.freeTransitionOracle(allocator, &oracle);

    const keep_keep = oracle.runner_after_corp_keep.keep_start_turn;

    var bran_archives = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer bran_archives.deinit();
    try flow.applyAction(&bran_archives, bran_archives.snapshot.legal_actions[0]);
    try flow.applyAction(&bran_archives, bran_archives.snapshot.legal_actions[0]);
    try flow.applyAction(&bran_archives, bran_archives.snapshot.legal_actions[0]);
    try flow.applyAction(&bran_archives, bran_archives.snapshot.legal_actions[try findCardPlayActionIndex(bran_archives.snapshot.legal_actions, "Brân 1.0")]);
    const bran_expectation = try findCardPlayExpectation(keep_keep.play_from_hand, "Brân 1.0");
    try flow.applyAction(&bran_archives, bran_archives.snapshot.legal_actions[try findPromptChoiceActionIndex(bran_archives.snapshot.legal_actions, "Archives")]);
    try expectTransitionMatches((try findPromptChoiceExpectation(bran_expectation.prompt_choices, "Archives")).result, bran_archives.snapshot);

    var regolith_remote = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer regolith_remote.deinit();
    try flow.applyAction(&regolith_remote, regolith_remote.snapshot.legal_actions[0]);
    try flow.applyAction(&regolith_remote, regolith_remote.snapshot.legal_actions[0]);
    try flow.applyAction(&regolith_remote, regolith_remote.snapshot.legal_actions[0]);
    try flow.applyAction(&regolith_remote, regolith_remote.snapshot.legal_actions[try findCardPlayActionIndex(regolith_remote.snapshot.legal_actions, "Regolith Mining License")]);
    const regolith_expectation = try findCardPlayExpectation(keep_keep.play_from_hand, "Regolith Mining License");
    try flow.applyAction(&regolith_remote, regolith_remote.snapshot.legal_actions[try findPromptChoiceActionIndex(regolith_remote.snapshot.legal_actions, "New remote")]);
    try expectTransitionMatches((try findPromptChoiceExpectation(regolith_expectation.prompt_choices, "New remote")).result, regolith_remote.snapshot);

    var palisade_hq = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer palisade_hq.deinit();
    try flow.applyAction(&palisade_hq, palisade_hq.snapshot.legal_actions[0]);
    try flow.applyAction(&palisade_hq, palisade_hq.snapshot.legal_actions[0]);
    try flow.applyAction(&palisade_hq, palisade_hq.snapshot.legal_actions[0]);
    try flow.applyAction(&palisade_hq, palisade_hq.snapshot.legal_actions[try findCardPlayActionIndex(palisade_hq.snapshot.legal_actions, "Palisade")]);
    const palisade_expectation = try findCardPlayExpectation(keep_keep.play_from_hand, "Palisade");
    try flow.applyAction(&palisade_hq, palisade_hq.snapshot.legal_actions[try findPromptChoiceActionIndex(palisade_hq.snapshot.legal_actions, "HQ")]);
    try expectTransitionMatches((try findPromptChoiceExpectation(palisade_expectation.prompt_choices, "HQ")).result, palisade_hq.snapshot);
}

fn expectActions(expected: []const fixture.ActionExpectation, actual: []const state.LegalAction) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |lhs, rhs| {
        try std.testing.expectEqual(lhs.kind, rhs.kind);
        try std.testing.expectEqual(lhs.side, rhs.side);
        try expectOptionalString(lhs.choice_text, if (rhs.choice) |choice| choice.text else null);
        try expectOptionalString(lhs.server, rhs.server);
        try std.testing.expectEqual(lhs.card_index, rhs.card_index);
        try expectOptionalString(lhs.card_title, rhs.card_title);
        try std.testing.expect(expectedBasicActionMatches(rhs, lhs));
        try expectOptionalString(lhs.label, rhs.label);
    }
}

fn findCardPlayExpectation(
    expectations: []const fixture.CardPlayExpectation,
    title: []const u8,
) !fixture.CardPlayExpectation {
    for (expectations) |expectation| {
        if (std.mem.eql(u8, expectation.card_title, title)) return expectation;
    }
    return error.MissingTransition;
}

fn findPromptChoiceExpectation(
    expectations: []const fixture.PromptChoiceExpectation,
    choice_text: []const u8,
) !fixture.PromptChoiceExpectation {
    for (expectations) |expectation| {
        if (std.mem.eql(u8, expectation.choice_text, choice_text)) return expectation;
    }
    return error.MissingTransition;
}

fn findBasicActionIndex(
    actions: []const state.LegalAction,
    basic_action: state.BasicAction,
) !usize {
    for (actions, 0..) |action, idx| {
        if (action.kind == .use_ability and action.basic_action == basic_action) return idx;
    }
    return error.MissingAction;
}

fn findCardPlayActionIndex(
    actions: []const state.LegalAction,
    title: []const u8,
) !usize {
    for (actions, 0..) |action, idx| {
        if (action.kind == .play_from_hand and action.card_title != null and std.mem.eql(u8, action.card_title.?, title)) {
            return idx;
        }
    }
    return error.MissingAction;
}

fn findPromptChoiceActionIndex(
    actions: []const state.LegalAction,
    choice_text: []const u8,
) !usize {
    for (actions, 0..) |action, idx| {
        if (action.kind != .prompt_choice or action.choice == null or action.choice.?.text == null) continue;
        if (std.mem.eql(u8, action.choice.?.text.?, choice_text)) return idx;
    }
    return error.MissingAction;
}

fn expectServers(expected: []const state.ServerSlot, actual: []const state.ServerSlot) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |lhs, rhs| {
        if (lhs.state.ices.len == 0 and lhs.state.content.len == 0) continue;
        try expectTitleSuffix(lhs.state.ices, rhs.state.ices);
        try expectTitleSuffix(lhs.state.content, rhs.state.content);
    }
}

fn expectOptionalString(expected: ?[]const u8, actual: ?[]const u8) !void {
    const normalized_actual = normalizePromptType(actual);
    if (expected) |lhs| {
        if (normalized_actual) |rhs| {
            try std.testing.expectEqualStrings(lhs, rhs);
        } else {
            return error.TestExpectedEqual;
        }
    } else {
        try std.testing.expect(normalized_actual == null);
    }
}

fn normalizePromptType(prompt_type: ?[]const u8) ?[]const u8 {
    const text = prompt_type orelse return null;
    if (std.mem.eql(u8, text, "install-destination")) return "other";
    if (std.mem.eql(u8, text, "access-choice")) return "other";
    if (std.mem.eql(u8, text, "hq-access")) return "other";
    if (std.mem.eql(u8, text, "run-target")) return "other";
    if (std.mem.eql(u8, text, "access-cleanup")) return "select";
    return text;
}

test "corp first-play end-turn scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstPlayFromHand(generated.snapshot.legal_actions, .corp));
    if (findFirstKindAction(generated.snapshot.legal_actions, .prompt_choice, .corp)) |prompt_action| {
        try takeAction(allocator, &actions, &generated, prompt_action);
    }
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    if (replay.snapshot.decision_side != generated.snapshot.decision_side) {
        std.debug.panic(
            "replay_side={any} actual_side={any} replay_kind={any} replay_prompt={s} actual_kind={any} actual_prompt={s}",
            .{
                replay.snapshot.decision_side,
                generated.snapshot.decision_side,
                if (replay.snapshot.legal_actions.len > 0) replay.snapshot.legal_actions[0].kind else .run,
                if (replay.snapshot.legal_actions.len > 0) (replay.snapshot.legal_actions[0].prompt_type orelse "") else "",
                if (generated.snapshot.legal_actions.len > 0) generated.snapshot.legal_actions[0].kind else .run,
                if (generated.snapshot.legal_actions.len > 0) (generated.snapshot.legal_actions[0].prompt_type orelse "") else "",
            },
        );
    }
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "corp first install runner start-turn scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "corp first install runner gain-credit scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.snapshot.legal_actions, .runner, .gain_credit) orelse return error.MissingAction);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "corp first install runner draw-card scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.snapshot.legal_actions, .runner, .draw_card) orelse return error.MissingAction);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "corp first install runner sure-gamble scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Sure Gamble"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "corp first install runner run-server-1 scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "corp first install runner run-server-1 continue scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "corp first install runner run-server-1 approach-ice scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "corp first install runner run-server-1 movement-complete scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "send-a-message access-success scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Send a Message"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "send-a-message steal scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Send a Message"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Steal"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "send-a-message cleanup-done scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Send a Message"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Steal"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Done"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner tread-lightly prompt scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Tread Lightly"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner tread-lightly server-choice scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Tread Lightly"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Server 1"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner jailbreak prompt scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Jailbreak"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner jailbreak hq-choice scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Jailbreak"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "HQ"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner overclock prompt scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Overclock"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner overclock server-choice scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Overclock"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Server 1"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner overclock run credits are attached and cleared through run flow" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();

    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try flow.applyAction(&generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Send a Message"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    try flow.applyAction(&generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try flow.applyAction(&generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Overclock"));

    try std.testing.expectEqual(@as(state.Count, 4), generated.snapshot.state.runner.credit);
    try std.testing.expectEqual(@as(state.Count, 0), generated.snapshot.state.runner.run_credit);

    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Server 1"));

    const run_after_choice = generated.snapshot.state.run orelse return error.MissingRun;
    try std.testing.expectEqual(@as(state.Count, 5), run_after_choice.temporary_run_credits);
    try std.testing.expectEqual(@as(state.Count, 0), generated.snapshot.state.runner.run_credit);

    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    const run_after_success = generated.snapshot.state.run orelse return error.MissingRun;
    try std.testing.expectEqual(@as(state.Count, 5), run_after_success.temporary_run_credits);
    try std.testing.expectEqual(@as(state.Count, 0), generated.snapshot.state.runner.run_credit);

    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Steal"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Done"));

    try std.testing.expect(generated.snapshot.state.run == null);
    try std.testing.expectEqual(@as(state.Count, 0), generated.snapshot.state.runner.run_credit);
}

test "runner overclock successful-run scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Send a Message"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Overclock"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner overclock cleanup-done scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Send a Message"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Overclock"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Steal"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Done"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner jailbreak successful-run effect is attached to run flow" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();

    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try flow.applyAction(&generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try flow.applyAction(&generated, gain_action);
    }
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));

    const hand_before_play = generated.snapshot.state.runner.hand.len;
    try flow.applyAction(&generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Jailbreak"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "HQ"));

    const run_after_choice = generated.snapshot.state.run orelse return error.MissingRun;
    try std.testing.expectEqual(@as(state.Count, 0), run_after_choice.rez_cost_bonus);
    try std.testing.expectEqual(state.RunSuccessEffectKind.draw_cards, run_after_choice.successful_run_effect);
    try std.testing.expectEqual(@as(state.TinyCount, 1), run_after_choice.successful_run_draw_cards);
    try std.testing.expectEqual(@as(state.TinyCount, 1), run_after_choice.access_bonus);

    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    try std.testing.expectEqual(hand_before_play, generated.snapshot.state.runner.hand.len);
}

test "runner jailbreak successful-run scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Jailbreak"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "HQ"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner tread-lightly run modifier is attached to run state" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();

    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try flow.applyAction(&generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try flow.applyAction(&generated, gain_action);
    }
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try flow.applyAction(&generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Tread Lightly"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Server 1"));

    const run = generated.snapshot.state.run orelse return error.MissingRun;
    try std.testing.expectEqual(@as(state.Count, 3), run.rez_cost_bonus);
}

test "runner creative-commission scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Creative Commission"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner vrcation scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 3);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "VRcation"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 3, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

fn findMatchingAction(
    actions: []const state.LegalAction,
    expected: fixture.ActionExpectation,
) !state.LegalAction {
    for (actions) |action| {
        if (action.kind != expected.kind or action.side != expected.side) continue;
        if (!optionalStringsEqual(expected.choice_text, if (action.choice) |choice| choice.text else null)) continue;
        if (!optionalStringsEqual(expected.server, action.server)) continue;
        if (action.card_index != expected.card_index) continue;
        if (!optionalStringsEqual(expected.card_title, action.card_title)) continue;
        if (!expectedBasicActionMatches(action, expected)) continue;
        if (!optionalStringsEqual(expected.label, action.label)) continue;
        return action;
    }
    return error.MissingAction;
}

fn expectedBasicActionMatches(action: state.LegalAction, expected: fixture.ActionExpectation) bool {
    if (expected.ability_index) |ability_index| {
        const expected_basic_action = fixtureBasicAction(expected.side, ability_index) catch return false;
        return action.basic_action == expected_basic_action;
    }
    return action.basic_action == null;
}

fn fixtureBasicAction(side: state.Side, ability_index: state.TinyCount) !state.BasicAction {
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
            4 => .run_any_server,
            else => error.UnsupportedAbility,
        },
    };
}


fn optionalStringsEqual(lhs: ?[]const u8, rhs: ?[]const u8) bool {
    if (lhs) |lhs_text| {
        return if (rhs) |rhs_text| std.mem.eql(u8, lhs_text, rhs_text) else false;
    }
    return rhs == null;
}

fn expectSnapshotMatches(expected: state.GameSnapshot, actual: state.GameSnapshot) !void {
    try std.testing.expectEqual(expected.decision_side, actual.decision_side);
    try std.testing.expectEqual(expected.state.active_player, actual.state.active_player);
    try std.testing.expectEqual(expected.state.turn, actual.state.turn);
    try std.testing.expectEqual(expected.state.end_turn, actual.state.end_turn);
    try expectOptionalRun(expected.state.run, actual.state.run);
    try std.testing.expectEqual(expected.state.corp.credit, actual.state.corp.credit);
    try std.testing.expectEqual(expected.state.runner.credit, actual.state.runner.credit);
    try std.testing.expectEqual(expected.state.runner.run_credit, actual.state.runner.run_credit);
    try std.testing.expectEqual(expected.state.corp.click, actual.state.corp.click);
    try std.testing.expectEqual(expected.state.runner.click, actual.state.runner.click);
    try std.testing.expectEqual(expected.state.corp.agenda_point, actual.state.corp.agenda_point);
    try std.testing.expectEqual(expected.state.runner.agenda_point, actual.state.runner.agenda_point);
    try std.testing.expectEqual(expected.state.corp.keep, actual.state.corp.keep);
    try std.testing.expectEqual(expected.state.runner.keep, actual.state.runner.keep);
    try std.testing.expectEqual(expected.state.rng_seed.?, actual.state.rng_seed.?);
    try expectOptionalString(if (expected.state.corp.prompt_state) |prompt| prompt.prompt_type else null, if (actual.state.corp.prompt_state) |prompt| prompt.prompt_type else null);
    try expectOptionalString(if (expected.state.runner.prompt_state) |prompt| prompt.prompt_type else null, if (actual.state.runner.prompt_state) |prompt| prompt.prompt_type else null);
    try expectLiveActions(expected.legal_actions, actual.legal_actions);
    try expectServers(expected.state.corp.servers, actual.state.corp.servers);
    try expectSameTitles(expected.state.corp.hand, actual.state.corp.hand);
    try expectSameTitles(expected.state.corp.deck, actual.state.corp.deck);
    try expectSameTitles(expected.state.runner.hand, actual.state.runner.hand);
    try expectSameTitles(expected.state.runner.deck, actual.state.runner.deck);
}

fn expectLiveActions(expected: []const state.LegalAction, actual: []const state.LegalAction) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |lhs, rhs| {
        try std.testing.expectEqual(lhs.kind, rhs.kind);
        try std.testing.expectEqual(lhs.side, rhs.side);
        try expectOptionalString(if (lhs.choice) |choice| choice.text else null, if (rhs.choice) |choice| choice.text else null);
        try expectOptionalString(lhs.server, rhs.server);
        try std.testing.expectEqual(lhs.card_index, rhs.card_index);
        try expectOptionalString(lhs.card_title, rhs.card_title);
        try std.testing.expectEqual(lhs.basic_action, rhs.basic_action);
        try expectOptionalString(lhs.label, rhs.label);
    }
}

const corp_operation_titles = [_][]const u8{ "Government Subsidy", "Hedge Fund", "Seamless Launch" };

fn takeAction(
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(state.LegalAction),
    generated: *generator.Game,
    selected: state.LegalAction,
) !void {
    try actions.append(allocator, selected);
    try flow.applyAction(generated, selected);
}

fn findActionByKind(actions: []const state.LegalAction, kind: state.ActionKind, side: state.Side) !state.LegalAction {
    return findFirstKindAction(actions, kind, side) orelse error.MissingAction;
}

fn findFirstKindAction(actions: []const state.LegalAction, kind: state.ActionKind, side: state.Side) ?state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind == kind and legal_action.side == side) return legal_action;
    }
    return null;
}

fn findPromptChoiceAction(actions: []const state.LegalAction, side: state.Side, text: []const u8) !state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind != .prompt_choice or legal_action.side != side or legal_action.choice == null or legal_action.choice.?.text == null) continue;
        if (std.mem.eql(u8, legal_action.choice.?.text.?, text)) return legal_action;
    }
    return error.MissingAction;
}

fn findBasicAction(actions: []const state.LegalAction, side: state.Side, basic_action: state.BasicAction) ?state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind == .use_ability and legal_action.side == side and legal_action.basic_action == basic_action) return legal_action;
    }
    return null;
}

fn findRunAction(actions: []const state.LegalAction, server: []const u8) !state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind == .run and legal_action.server != null and std.mem.eql(u8, legal_action.server.?, server)) return legal_action;
    }
    return error.MissingAction;
}

fn findPlayFromHandByTitle(actions: []const state.LegalAction, side: state.Side, title: []const u8) !state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind == .play_from_hand and legal_action.side == side and legal_action.card_title != null and std.mem.eql(u8, legal_action.card_title.?, title)) return legal_action;
    }
    return error.MissingAction;
}

fn findFirstPlayFromHand(actions: []const state.LegalAction, side: state.Side) !state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind == .play_from_hand and legal_action.side == side) return legal_action;
    }
    return error.MissingAction;
}

fn findFirstCorpInstallPlay(actions: []const state.LegalAction) !state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind != .play_from_hand or legal_action.side != .corp or legal_action.card_title == null) continue;
        if (!containsTitle(&corp_operation_titles, legal_action.card_title.?)) return legal_action;
    }
    return error.MissingAction;
}

fn containsTitle(titles: []const []const u8, title: []const u8) bool {
    for (titles) |candidate| {
        if (std.mem.eql(u8, candidate, title)) return true;
    }
    return false;
}
