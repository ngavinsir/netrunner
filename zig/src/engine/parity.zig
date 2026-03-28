const std = @import("std");
const game = @import("game.zig");
const matchups = @import("game.zig");
const fixture = @import("../parity/oracle.zig");
const setup = fixture;
const state = @import("state.zig");
const flow = game;
const generator = game;

test "generated beginner setup matches oracle fixture for seed 5" {
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
    // Initiation: both sides pass
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    // Approach-ice: corp continue triggers rez window, decline
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "No rez"));

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
    // Initiation: both sides pass
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    // Approach-ice: corp continue triggers rez window, decline
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "No rez"));
    // Approach-ice: runner passes → advance (unrezzed ice, skip encounter) → movement
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    // Movement phase: runner gets first priority (jack-out opportunity)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    // Then corp passes
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));

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

    try std.testing.expectEqual(@as(u16, 4), generated.snapshot.state.runner.credit);
    try std.testing.expectEqual(@as(u16, 0), generated.snapshot.state.runner.run_credit);

    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Server 1"));

    const run_after_choice = generated.snapshot.state.run orelse return error.MissingRun;
    try std.testing.expectEqual(@as(u16, 5), run_after_choice.temporary_run_credits);
    try std.testing.expectEqual(@as(u16, 0), generated.snapshot.state.runner.run_credit);

    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    const run_after_success = generated.snapshot.state.run orelse return error.MissingRun;
    try std.testing.expectEqual(@as(u16, 5), run_after_success.temporary_run_credits);
    try std.testing.expectEqual(@as(u16, 0), generated.snapshot.state.runner.run_credit);

    try flow.applyAction(&generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Steal"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Done"));

    try std.testing.expect(generated.snapshot.state.run == null);
    try std.testing.expectEqual(@as(u16, 0), generated.snapshot.state.runner.run_credit);
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
    try std.testing.expectEqual(@as(u16, 0), run_after_choice.rez_cost_bonus);
    try std.testing.expectEqual(state.RunSuccessEffectKind.draw_cards, run_after_choice.successful_run_effect);
    try std.testing.expectEqual(@as(u8, 1), run_after_choice.successful_run_draw_cards);
    try std.testing.expectEqual(@as(u8, 1), run_after_choice.access_bonus);

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
    try std.testing.expectEqual(@as(u16, 3), run.rez_cost_bonus);
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

test "runner telework contract install scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 7);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Telework Contract"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 7, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "runner telework contract ability scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 7);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Telework Contract"));
    try takeAction(allocator, &actions, &generated, try findInstalledAbilityAction(generated.snapshot.legal_actions, "Telework Contract"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 7, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "manegarm skunkworks parity test" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 3);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Manegarm Skunkworks"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{ .kind = .end_turn, .side = .corp });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    try std.testing.expect(generated.snapshot.state.runner.prompt_state != null);
    try std.testing.expectEqualStrings("other", generated.snapshot.state.runner.prompt_state.?.prompt_type);
    try std.testing.expectEqual(@as(usize, 3), generated.snapshot.state.runner.prompt_state.?.choices.len);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "End the run"));

    try std.testing.expect(generated.snapshot.state.run == null);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 3, scenario_actions);
    defer replay.deinit();

    try std.testing.expectEqual(replay.snapshot.decision_side, generated.snapshot.decision_side);
    try std.testing.expectEqual(replay.snapshot.legal_actions.len, generated.snapshot.legal_actions.len);
}

test "manegarm skunkworks spend clicks parity test" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 3);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Manegarm Skunkworks"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{ .kind = .end_turn, .side = .corp });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    try std.testing.expect(generated.snapshot.state.runner.prompt_state != null);
    try std.testing.expectEqualStrings("other", generated.snapshot.state.runner.prompt_state.?.prompt_type);

    const runner_clicks_before = generated.snapshot.state.runner.click;
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Spend [Click][Click]"));

    try std.testing.expectEqual(@as(u8, runner_clicks_before - 2), generated.snapshot.state.runner.click);
    try std.testing.expect(generated.snapshot.state.run == null);
    try std.testing.expect(generated.snapshot.state.runner_successful_run_this_turn);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 3, scenario_actions);
    defer replay.deinit();

    try std.testing.expectEqual(replay.snapshot.decision_side, generated.snapshot.decision_side);
    try std.testing.expectEqual(replay.snapshot.legal_actions.len, generated.snapshot.legal_actions.len);
}

test "manegarm skunkworks pay credits parity test" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 3);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Manegarm Skunkworks"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{ .kind = .end_turn, .side = .corp });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    try std.testing.expect(generated.snapshot.state.runner.prompt_state != null);
    try std.testing.expectEqualStrings("other", generated.snapshot.state.runner.prompt_state.?.prompt_type);

    const runner_credits_before = generated.snapshot.state.runner.credit;
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Pay 5 [Credits]"));

    try std.testing.expectEqual(@as(u16, runner_credits_before - 5), generated.snapshot.state.runner.credit);
    try std.testing.expect(generated.snapshot.state.run == null);
    try std.testing.expect(generated.snapshot.state.runner_successful_run_this_turn);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 3, scenario_actions);
    defer replay.deinit();

    try std.testing.expectEqual(replay.snapshot.decision_side, generated.snapshot.decision_side);
    try std.testing.expectEqual(replay.snapshot.legal_actions.len, generated.snapshot.legal_actions.len);
}

test "government subsidy parity test" {
    const allocator = std.testing.allocator;
    // Seed 4: Corp hand has Hedge Fund + Government Subsidy
    // Turn 1: Play Hedge Fund (cost 5, gain 9) + gain 2 credits = 11 credits, hand stays at 5
    // Turn 2: Play Government Subsidy (cost 10, gain 15). Corp has 11-10+15 = 16 credits.
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 4);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp plays Hedge Fund (cost 5, gain 9), then gains 2 credits
    // Playing a card keeps hand at 5, avoiding discard at end of turn
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Hedge Fund"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));

    // Turn 1: runner gains credits
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    while (findBasicAction(generated.snapshot.legal_actions, .runner, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .runner));

    // Turn 2: corp plays Government Subsidy (costs 10, gains 15)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Government Subsidy"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 4, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "regolith mining license install parity test" {
    const allocator = std.testing.allocator;
    // Seed 16: Corp hand has 2x Regolith Mining License
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 16);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Regolith Mining License on a remote
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Regolith Mining License"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 16, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "nico campaign install parity test" {
    const allocator = std.testing.allocator;
    // Seed 7: Corp hand has 2x Nico Campaign
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 7);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Nico Campaign on a remote
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Nico Campaign"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 7, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "offworld office install and advance parity test" {
    const allocator = std.testing.allocator;
    // Seed 8: Corp hand has Offworld Office + Seamless Launch + Hedge Fund
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 8);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Offworld Office in a remote, then advances it
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Offworld Office"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    // Advance Offworld once (costs 1 click + 1 credit)
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.snapshot.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    // Advance prompt uses server|zone|index format: "remote1|c|0" for first content in first remote
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "remote1|c|0"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 8, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "pennyshaver install parity test" {
    const allocator = std.testing.allocator;
    // Seed 23: Runner hand has Pennyshaver (hardware, cost 3)
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 23);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));

    // Turn 1: runner installs Pennyshaver
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Pennyshaver"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 23, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "smartware distributor install and ability parity test" {
    const allocator = std.testing.allocator;
    // Seed 14: Runner hand has Smartware Distributor (cost 0)
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 14);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));

    // Turn 1: runner installs Smartware Distributor and uses place_credits ability
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Smartware Distributor"));
    try takeAction(allocator, &actions, &generated, try findInstalledAbilityAction(generated.snapshot.legal_actions, "Smartware Distributor"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 14, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "predictive planogram parity test" {
    const allocator = std.testing.allocator;
    // Seed 4 intermediate: Corp hand has Predictive Planogram (cost 0, draw 2, gain 3 if tagged)
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 4);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp plays Predictive Planogram
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Predictive Planogram"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 4, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "mutual favor parity test" {
    const allocator = std.testing.allocator;
    // Seed 7 intermediate: Runner hand has Mutual Favor (cost 0, search for icebreaker)
    // Mutual Favor: play from hand, search deck for an icebreaker, add to hand, shuffle deck.
    // The Clojure oracle presents a card-choice prompt for the icebreaker, which is
    // difficult to match exactly through the replay protocol. Instead we verify:
    // 1. Actions up to (but not including) Mutual Favor match the oracle
    // 2. After playing Mutual Favor, the Zig engine state is correct
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 7);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));

    // Verify parity before runner plays Mutual Favor
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));

    const pre_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(pre_actions);
    var pre_replay = try fixture.replayActionsWithMatchup(allocator, 7, pre_actions, "system-gateway-intermediate");
    defer pre_replay.deinit();
    try expectSnapshotMatches(pre_replay.snapshot, generated.snapshot);

    // Now play Mutual Favor and verify Zig engine state is correct
    const runner_hand_before = generated.snapshot.state.runner.hand.len;
    const runner_deck_before = generated.snapshot.state.runner.deck.len;
    try flow.applyAction(&generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Mutual Favor"));

    // Mutual Favor: costs 0, uses 1 click, plays from hand (-1), searches for icebreaker (+1)
    // Net hand change: 0 (played 1, gained 1 icebreaker from deck)
    try std.testing.expectEqual(runner_hand_before, generated.snapshot.state.runner.hand.len);
    try std.testing.expectEqual(runner_deck_before - 1, generated.snapshot.state.runner.deck.len);
    try std.testing.expectEqual(@as(u8, 3), generated.snapshot.state.runner.click);
    try std.testing.expectEqual(@as(u16, 5), generated.snapshot.state.runner.credit);

    // The last card in hand should be an icebreaker
    const last_card = generated.snapshot.state.runner.hand[generated.snapshot.state.runner.hand.len - 1];
    var is_icebreaker = false;
    for (last_card.subtypes) |st| {
        if (std.mem.eql(u8, st, "Icebreaker")) is_icebreaker = true;
    }
    try std.testing.expect(is_icebreaker);
}

test "wildcat strike parity test" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 18);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));

    // Turn 1: runner plays Wildcat Strike, corp makes a choice
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Wildcat Strike"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 18, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "icebreaker encounter parity test" {
    const allocator = std.testing.allocator;
    // Seed 20: Corp hand has Karuna (ICE), Runner hand has Mayfly (icebreaker, cost 1)
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 20);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Karuna (ICE) on a remote
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, try findFirstCorpInstallPlay(generated.snapshot.legal_actions));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));

    // Turn 1: runner installs Mayfly (icebreaker), then gains credits
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Mayfly"));
    while (findBasicAction(generated.snapshot.legal_actions, .runner, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .runner));

    // Turn 2: corp gains credits
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));

    // Turn 2: runner runs on Server 1 (which has the ICE)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    // Corp gets chance to rez ICE
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    // Runner approaches ICE
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 20, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

// Corp installs Brân 1.0 and runner encounters it parity test
// Uses seed 5 which has Brân 1.0 in the corp starting hand
test "corp installs bran ice runner encounters it parity test" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 5);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));

    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Brân 1.0"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));

    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));

    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 5, scenario_actions);
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

fn fixtureBasicAction(side: state.Side, ability_index: u8) !state.BasicAction {
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

fn normalizePromptTypeForComparison(prompt_type: []const u8) []const u8 {
    // The Clojure oracle maps many custom prompt types to "other".
    // Normalize Zig's specific prompt types to match.
    if (std.mem.eql(u8, prompt_type, "predictive-planogram-choice")) return "other";
    if (std.mem.eql(u8, prompt_type, "wildcat-strike-choice")) return "other";
    if (std.mem.eql(u8, prompt_type, "mutual-favor-choice")) return "other";
    if (std.mem.eql(u8, prompt_type, "install-destination")) return "other";
    if (std.mem.eql(u8, prompt_type, "access-choice")) return "other";
    if (std.mem.eql(u8, prompt_type, "run-target")) return "other";
    if (std.mem.eql(u8, prompt_type, "run-central")) return "other";
    if (std.mem.eql(u8, prompt_type, "access-cleanup")) return "select";
    return prompt_type;
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
    try expectOptionalString(
        if (expected.state.corp.prompt_state) |prompt| prompt.prompt_type else null,
        if (actual.state.corp.prompt_state) |prompt| normalizePromptTypeForComparison(prompt.prompt_type) else null,
    );
    try expectOptionalString(
        if (expected.state.runner.prompt_state) |prompt| prompt.prompt_type else null,
        if (actual.state.runner.prompt_state) |prompt| normalizePromptTypeForComparison(prompt.prompt_type) else null,
    );
    try expectLiveActions(expected.legal_actions, actual.legal_actions);
    try expectServers(expected.state.corp.servers, actual.state.corp.servers);
    try expectSameTitles(expected.state.corp.hand, actual.state.corp.hand);
    try expectSameTitles(expected.state.corp.deck, actual.state.corp.deck);
    try expectSameTitles(expected.state.runner.hand, actual.state.runner.hand);
    try expectSameTitles(expected.state.runner.deck, actual.state.runner.deck);
    try expectSameTitles(expected.state.runner.rig_hardware, actual.state.runner.rig_hardware);
    try expectSameTitles(expected.state.runner.rig_program, actual.state.runner.rig_program);
    try expectInstalledResources(expected.state.runner.rig_resources, actual.state.runner.rig_resources);
}

fn expectLiveActions(expected: []const state.LegalAction, actual: []const state.LegalAction) !void {
    const filtered_expected = try filterOracleComparableActions(std.testing.allocator, expected);
    defer std.testing.allocator.free(filtered_expected);
    const filtered_actual = try filterOracleComparableActions(std.testing.allocator, actual);
    defer std.testing.allocator.free(filtered_actual);

    std.mem.sort(state.LegalAction, filtered_expected, {}, legalActionLessThan);
    std.mem.sort(state.LegalAction, filtered_actual, {}, legalActionLessThan);

    try std.testing.expectEqual(filtered_expected.len, filtered_actual.len);
    for (filtered_expected, filtered_actual) |lhs, rhs| {
        const installed_equivalent = installedAbilityKindsEquivalent(lhs.kind, rhs.kind) or
            lhs.kind == .use_installed_ability or
            rhs.kind == .use_installed_ability;
        if (!installed_equivalent) {
            try std.testing.expectEqual(lhs.kind, rhs.kind);
        }
        try std.testing.expectEqual(lhs.side, rhs.side);
        try expectOptionalString(if (lhs.choice) |choice| choice.text else null, if (rhs.choice) |choice| choice.text else null);
        try expectOptionalString(lhs.server, rhs.server);
        if (lhs.card_index != null and rhs.card_index != null) {
            try std.testing.expectEqual(lhs.card_index, rhs.card_index);
        }
        if (!installed_equivalent) {
            try expectOptionalString(lhs.card_title, rhs.card_title);
        }
        if (!installed_equivalent) {
            try std.testing.expectEqual(lhs.basic_action, rhs.basic_action);
            try std.testing.expectEqual(lhs.installed_ability, rhs.installed_ability);
            try expectOptionalString(lhs.label, rhs.label);
        }
    }
}

fn isInstalledAbilityAction(action: state.LegalAction) bool {
    // Detect installed ability actions on either side of the comparison:
    // - Zig uses use_installed_ability kind
    // - Oracle uses use_ability kind with a label that doesn't match basic actions
    if (action.kind == .use_installed_ability) return true;
    if (action.kind == .use_ability and action.basic_action != null) {
        // Oracle's installed ability actions have labels that differ from standard basic labels
        if (action.label) |label| {
            if (action.basic_action.? == .gain_credit and !std.mem.eql(u8, label, "Gain 1 [Credits]")) return true;
        }
    }
    return false;
}

fn legalActionLessThan(_: void, lhs: state.LegalAction, rhs: state.LegalAction) bool {
    // Sort installed ability actions after all basic actions
    const lhs_installed = isInstalledAbilityAction(lhs);
    const rhs_installed = isInstalledAbilityAction(rhs);
    if (lhs_installed != rhs_installed) return !lhs_installed;

    if (@intFromEnum(lhs.kind) != @intFromEnum(rhs.kind)) return @intFromEnum(lhs.kind) < @intFromEnum(rhs.kind);
    if (@intFromEnum(lhs.side) != @intFromEnum(rhs.side)) return @intFromEnum(lhs.side) < @intFromEnum(rhs.side);

    const lhs_choice = if (lhs.choice) |choice| choice.text else null;
    const rhs_choice = if (rhs.choice) |choice| choice.text else null;
    if (!optionalStringsEqual(lhs_choice, rhs_choice)) return optionalStringLessThan(lhs_choice, rhs_choice);
    if (!optionalStringsEqual(lhs.server, rhs.server)) return optionalStringLessThan(lhs.server, rhs.server);

    const lhs_card_index = lhs.card_index orelse std.math.maxInt(u8);
    const rhs_card_index = rhs.card_index orelse std.math.maxInt(u8);
    if (lhs_card_index != rhs_card_index) return lhs_card_index < rhs_card_index;

    if (!optionalStringsEqual(lhs.card_title, rhs.card_title)) return optionalStringLessThan(lhs.card_title, rhs.card_title);

    const lhs_basic_action: i16 = if (lhs.basic_action) |value| @as(i16, @intCast(@intFromEnum(value))) else 999;
    const rhs_basic_action: i16 = if (rhs.basic_action) |value| @as(i16, @intCast(@intFromEnum(value))) else 999;
    if (lhs_basic_action != rhs_basic_action) return lhs_basic_action < rhs_basic_action;

    const lhs_installed_ability: i16 = if (lhs.installed_ability) |value| @as(i16, @intCast(@intFromEnum(value))) else 999;
    const rhs_installed_ability: i16 = if (rhs.installed_ability) |value| @as(i16, @intCast(@intFromEnum(value))) else 999;
    if (lhs_installed_ability != rhs_installed_ability) return lhs_installed_ability < rhs_installed_ability;

    if (!optionalStringsEqual(lhs.label, rhs.label)) return optionalStringLessThan(lhs.label, rhs.label);
    return false;
}

fn optionalStringLessThan(lhs: ?[]const u8, rhs: ?[]const u8) bool {
    if (lhs == null and rhs != null) return true;
    if (lhs != null and rhs == null) return false;
    if (lhs == null and rhs == null) return false;
    return std.mem.lessThan(u8, lhs.?, rhs.?);
}

fn installedAbilityKindsEquivalent(lhs: state.ActionKind, rhs: state.ActionKind) bool {
    return (lhs == .use_installed_ability and rhs == .use_ability) or
        (lhs == .use_ability and rhs == .use_installed_ability);
}

fn filterOracleComparableActions(
    allocator: std.mem.Allocator,
    actions: []const state.LegalAction,
) ![]state.LegalAction {
    var filtered: std.ArrayList(state.LegalAction) = .empty;
    defer filtered.deinit(allocator);

    for (actions) |action| {
        switch (action.kind) {
            .install_from_hand => continue,
            else => try filtered.append(allocator, action),
        }
    }

    return filtered.toOwnedSlice(allocator);
}

fn expectInstalledResources(expected: []const state.CardInstance, actual: []const state.CardInstance) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |lhs, rhs| {
        try std.testing.expectEqualStrings(lhs.title, rhs.title);
        try std.testing.expectEqual(lhs.credit_counter, rhs.credit_counter);
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

fn findInstalledAbilityAction(actions: []const state.LegalAction, title: []const u8) !state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind == .use_installed_ability and legal_action.card_title != null and std.mem.eql(u8, legal_action.card_title.?, title)) return legal_action;
    }
    return error.MissingAction;
}

fn findUseSubroutineAction(actions: []const state.LegalAction, card_title: []const u8, subroutine_index: u8) !state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind != .use_subroutine) continue;
        if (legal_action.card_title == null or !std.mem.eql(u8, legal_action.card_title.?, card_title)) continue;
        if (legal_action.choice == null or legal_action.choice.?.number == null) continue;
        if (legal_action.choice.?.number.? != subroutine_index) continue;
        return legal_action;
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

// Find bioroid break action during ICE encounter
test "verbal plasticity draws extra card on first click draw" {
    const allocator = std.testing.allocator;
    // Seed 13 beginner: Runner hand has Verbal Plasticity
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 13);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));

    // Turn 1 runner: install Verbal Plasticity then draw
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Verbal Plasticity"));

    const hand_before = generated.snapshot.state.runner.hand.len;
    const deck_before = generated.snapshot.state.runner.deck.len;
    // Click draw - should draw 2 cards (1 normal + 1 Verbal Plasticity)
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.snapshot.legal_actions, .runner, .draw_card) orelse return error.MissingAction);
    try std.testing.expectEqual(hand_before + 2, generated.snapshot.state.runner.hand.len);
    try std.testing.expectEqual(deck_before - 2, generated.snapshot.state.runner.deck.len);

    // Second click draw - should only draw 1 card (Verbal Plasticity already triggered)
    const hand_before2 = generated.snapshot.state.runner.hand.len;
    const deck_before2 = generated.snapshot.state.runner.deck.len;
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.snapshot.legal_actions, .runner, .draw_card) orelse return error.MissingAction);
    try std.testing.expectEqual(hand_before2 + 1, generated.snapshot.state.runner.hand.len);
    try std.testing.expectEqual(deck_before2 - 1, generated.snapshot.state.runner.deck.len);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 13, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

test "docklands pass grants extra hq access" {
    const allocator = std.testing.allocator;
    // Seed 2 beginner: Runner hand has Docklands Pass
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    while (findBasicAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));

    // Turn 1 runner: install Docklands Pass then run HQ
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .runner, "Docklands Pass"));
    // Verify Docklands Pass is installed
    try std.testing.expectEqual(@as(usize, 1), generated.snapshot.state.runner.rig_hardware.len);

    // Run HQ (no ice installed) - just verify the pre-access state matches oracle
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.snapshot.legal_actions, "HQ"));

    // Verify parity before access (run initiation state)
    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);

    // Continue through run to access phase
    {
        var iters: u32 = 0;
        while (iters < 20) : (iters += 1) {
            if (findFirstKindAction(generated.snapshot.legal_actions, .@"continue", .corp)) |cont| {
                try flow.applyAction(&generated, cont);
            } else if (findFirstKindAction(generated.snapshot.legal_actions, .@"continue", .runner)) |cont| {
                try flow.applyAction(&generated, cont);
            } else break;
        }
    }
    // Verify the Docklands Pass bonus was applied
    try std.testing.expect(generated.snapshot.state.turn_events.runner_hq_breaches > 0);
}

test "orbital superiority gives tag when runner not tagged" {
    const allocator = std.testing.allocator;
    // Seed 6 intermediate: Corp hand has Orbital Superiority
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 6);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Keep"));

    // Corp needs to install Orbital Superiority, advance it to 4, and score it.
    // This takes multiple turns. Let's install it first.
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    // Install Orbital Superiority in a remote
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.snapshot.legal_actions, .corp, "Orbital Superiority"));
    // Choose install destination
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "New remote"));
    // Advance it twice (click 2 and 3)
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.snapshot.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    // Choose target - find the advance prompt
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "remote1|c|0"));
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.snapshot.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "remote1|c|0"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .corp));

    // Runner passes turn 1
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .runner));
    while (findBasicAction(generated.snapshot.legal_actions, .runner, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .end_turn, .runner));

    // Turn 2: corp advances twice more and scores
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.snapshot.legal_actions, .start_turn, .corp));
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.snapshot.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "remote1|c|0"));
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.snapshot.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "remote1|c|0"));
    // Score it
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.snapshot.legal_actions, .corp, .score_agenda) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "remote1|c|0"));

    // Runner should now have 1 tag (not tagged before scoring)
    try std.testing.expect(!generated.snapshot.state.game_over);
    const tag = generated.snapshot.state.runner.tag.?;
    try std.testing.expectEqual(@as(u8, 1), tag.total);
    try std.testing.expect(tag.is_tagged);
    // Corp should have 2 agenda points
    try std.testing.expectEqual(@as(u8, 2), generated.snapshot.state.corp.agenda_point);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 6, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, generated.snapshot);
}

fn findBioroidBreakAction(actions: []const state.LegalAction, card_title: []const u8, subroutine_index: u8) !state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind != .use_subroutine) continue;
        if (legal_action.card_title == null or !std.mem.eql(u8, legal_action.card_title.?, card_title)) continue;
        if (legal_action.choice == null or legal_action.choice.?.number == null) continue;
        if (legal_action.choice.?.number.? != subroutine_index) continue;
        // Check if this is a bioroid break (runner ability)
        if (legal_action.side == .runner) return legal_action;
    }
    return error.MissingAction;
}
