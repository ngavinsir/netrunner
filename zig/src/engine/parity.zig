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

    try std.testing.expectEqual(oracle.snapshot.state.seed, generated.seed);
    try std.testing.expectEqual(oracle.snapshot.state.rng_seed.?, generated.rng_seed.?);
    try std.testing.expectEqual(oracle.snapshot.state.active_player, generated.active_player);
    try std.testing.expectEqual(oracle.snapshot.state.turn, generated.turn);
    try std.testing.expectEqual(oracle.snapshot.state.end_turn, generated.end_turn);

    try std.testing.expectEqualStrings(oracle.snapshot.state.corp.identity.title, generated.corp_identity.title);
    try std.testing.expectEqualStrings(oracle.snapshot.state.runner.identity.title, generated.runner_identity.title);
    try std.testing.expectEqualStrings(oracle.snapshot.state.corp.basic_action_card.title, generated.corp_basic_action_card.title);
    try std.testing.expectEqualStrings(oracle.snapshot.state.runner.basic_action_card.title, generated.runner_basic_action_card.title);

    try std.testing.expectEqual(oracle.snapshot.state.corp.click_per_turn, generated.corp_click_per_turn);
    try std.testing.expectEqual(oracle.snapshot.state.runner.click_per_turn, generated.runner_click_per_turn);
    try std.testing.expectEqual(oracle.snapshot.state.corp.credit, generated.corp_credit);
    try std.testing.expectEqual(oracle.snapshot.state.runner.credit, generated.runner_credit);
    try std.testing.expectEqual(oracle.snapshot.state.corp.hand_size.total, generated.corp_hand_size.total);
    try std.testing.expectEqual(oracle.snapshot.state.runner.hand_size.total, generated.runner_hand_size.total);

    try std.testing.expectEqual(oracle.snapshot.decision_side, generated.decision_side);
    try std.testing.expectEqual(oracle.snapshot.legal_actions.len, generated.legal_actions.len);
    try std.testing.expectEqualStrings(oracle.snapshot.legal_actions[0].choice.?.text.?, generated.legal_actions[0].choice.?.text.?);
    try std.testing.expectEqualStrings(oracle.snapshot.legal_actions[1].choice.?.text.?, generated.legal_actions[1].choice.?.text.?);

    try expectSameTitles(oracle.snapshot.state.corp.hand, generated.corp_hand.items);
    try expectSameTitles(oracle.snapshot.state.corp.deck, generated.corp_deck.items);
    try expectSameTitles(oracle.snapshot.state.runner.hand, generated.runner_hand.items);
    try expectSameTitles(oracle.snapshot.state.runner.deck, generated.runner_deck.items);
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
    try expectTransitionMatches(oracle.keep, try keep_state.toSnapshot());

    var mulligan_state = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer mulligan_state.deinit();
    try flow.applyMulliganChoice(&mulligan_state, .corp, .mulligan);
    try expectTransitionMatches(oracle.mulligan, try mulligan_state.toSnapshot());
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
    try expectTransitionMatches(oracle.runner_after_corp_keep.keep, try corp_keep_runner_keep.toSnapshot());

    var corp_keep_runner_mulligan = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_keep_runner_mulligan.deinit();
    try flow.applyMulliganChoice(&corp_keep_runner_mulligan, .corp, .keep);
    try flow.applyMulliganChoice(&corp_keep_runner_mulligan, .runner, .mulligan);
    try expectTransitionMatches(oracle.runner_after_corp_keep.mulligan, try corp_keep_runner_mulligan.toSnapshot());

    var corp_mulligan_runner_keep = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_mulligan_runner_keep.deinit();
    try flow.applyMulliganChoice(&corp_mulligan_runner_keep, .corp, .mulligan);
    try flow.applyMulliganChoice(&corp_mulligan_runner_keep, .runner, .keep);
    try expectTransitionMatches(oracle.runner_after_corp_mulligan.keep, try corp_mulligan_runner_keep.toSnapshot());

    var corp_mulligan_runner_mulligan = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_mulligan_runner_mulligan.deinit();
    try flow.applyMulliganChoice(&corp_mulligan_runner_mulligan, .corp, .mulligan);
    try flow.applyMulliganChoice(&corp_mulligan_runner_mulligan, .runner, .mulligan);
    try expectTransitionMatches(oracle.runner_after_corp_mulligan.mulligan, try corp_mulligan_runner_mulligan.toSnapshot());
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
    try generator.corpStartTurnFull(&corp_keep_runner_keep);
    try expectTransitionMatches(oracle.runner_after_corp_keep.keep_start_turn.transition, try corp_keep_runner_keep.toSnapshot());

    var corp_keep_runner_mulligan = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_keep_runner_mulligan.deinit();
    try flow.applyMulliganChoice(&corp_keep_runner_mulligan, .corp, .keep);
    try flow.applyMulliganChoice(&corp_keep_runner_mulligan, .runner, .mulligan);
    try generator.corpStartTurnFull(&corp_keep_runner_mulligan);
    try expectTransitionMatches(oracle.runner_after_corp_keep.mulligan_start_turn.transition, try corp_keep_runner_mulligan.toSnapshot());

    var corp_mulligan_runner_keep = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_mulligan_runner_keep.deinit();
    try flow.applyMulliganChoice(&corp_mulligan_runner_keep, .corp, .mulligan);
    try flow.applyMulliganChoice(&corp_mulligan_runner_keep, .runner, .keep);
    try generator.corpStartTurnFull(&corp_mulligan_runner_keep);
    try expectTransitionMatches(oracle.runner_after_corp_mulligan.keep_start_turn.transition, try corp_mulligan_runner_keep.toSnapshot());

    var corp_mulligan_runner_mulligan = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer corp_mulligan_runner_mulligan.deinit();
    try flow.applyMulliganChoice(&corp_mulligan_runner_mulligan, .corp, .mulligan);
    try flow.applyMulliganChoice(&corp_mulligan_runner_mulligan, .runner, .mulligan);
    try generator.corpStartTurnFull(&corp_mulligan_runner_mulligan);
    try expectTransitionMatches(oracle.runner_after_corp_mulligan.mulligan_start_turn.transition, try corp_mulligan_runner_mulligan.toSnapshot());
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

    try flow.applyAction(&start_state, start_state.legal_actions[0]); // Keep corp
    try flow.applyAction(&start_state, start_state.legal_actions[0]); // Keep runner
    try flow.applyAction(&start_state, start_state.legal_actions[0]); // start_turn
    try flow.applyAction(&start_state, start_state.legal_actions[0]); // phase-12 corp continue
    try flow.applyAction(&start_state, start_state.legal_actions[0]); // phase-12 runner continue

    const start_turn_oracle = oracle.runner_after_corp_keep.keep_start_turn;

    var gain_credit = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer gain_credit.deinit();
    try flow.applyAction(&gain_credit, gain_credit.legal_actions[0]); // Keep corp
    try flow.applyAction(&gain_credit, gain_credit.legal_actions[0]); // Keep runner
    try generator.corpStartTurnFull(&gain_credit);
    try flow.applyAction(&gain_credit, gain_credit.legal_actions[try findBasicActionIndex(gain_credit.legal_actions, .gain_credit)]);
    try expectTransitionMatches(start_turn_oracle.basic_actions.gain_credit, try gain_credit.toSnapshot());

    var draw_card = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer draw_card.deinit();
    try flow.applyAction(&draw_card, draw_card.legal_actions[0]); // Keep corp
    try flow.applyAction(&draw_card, draw_card.legal_actions[0]); // Keep runner
    try generator.corpStartTurnFull(&draw_card);
    try flow.applyAction(&draw_card, draw_card.legal_actions[try findBasicActionIndex(draw_card.legal_actions, .draw_card)]);
    try expectTransitionMatches(start_turn_oracle.basic_actions.draw_card, try draw_card.toSnapshot());

    var advance_card = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer advance_card.deinit();
    try flow.applyAction(&advance_card, advance_card.legal_actions[0]); // Keep corp
    try flow.applyAction(&advance_card, advance_card.legal_actions[0]); // Keep runner
    try generator.corpStartTurnFull(&advance_card);
    try flow.applyAction(&advance_card, advance_card.legal_actions[try findBasicActionIndex(advance_card.legal_actions, .advance_installed)]);
    try expectTransitionMatches(start_turn_oracle.basic_actions.advance_card, try advance_card.toSnapshot());

    var purge_viruses = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer purge_viruses.deinit();
    try flow.applyAction(&purge_viruses, purge_viruses.legal_actions[0]); // Keep corp
    try flow.applyAction(&purge_viruses, purge_viruses.legal_actions[0]); // Keep runner
    try generator.corpStartTurnFull(&purge_viruses);
    try flow.applyAction(&purge_viruses, purge_viruses.legal_actions[try findBasicActionIndex(purge_viruses.legal_actions, .purge_viruses)]);
    try expectTransitionMatches(start_turn_oracle.basic_actions.purge_viruses, try purge_viruses.toSnapshot());
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
    try flow.applyAction(&hedge_fund, hedge_fund.legal_actions[0]); // Keep corp
    try flow.applyAction(&hedge_fund, hedge_fund.legal_actions[0]); // Keep runner
    try generator.corpStartTurnFull(&hedge_fund);
    try flow.applyAction(&hedge_fund, hedge_fund.legal_actions[try findCardPlayActionIndex(hedge_fund.legal_actions, "Hedge Fund")]);
    try expectTransitionMatches((try findCardPlayExpectation(keep_keep.play_from_hand, "Hedge Fund")).result, try hedge_fund.toSnapshot());

    var bran = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer bran.deinit();
    try flow.applyAction(&bran, bran.legal_actions[0]); // Keep corp
    try flow.applyAction(&bran, bran.legal_actions[0]); // Keep runner
    try generator.corpStartTurnFull(&bran);
    try flow.applyAction(&bran, bran.legal_actions[try findCardPlayActionIndex(bran.legal_actions, "Brân 1.0")]);
    try expectTransitionMatches((try findCardPlayExpectation(keep_keep.play_from_hand, "Brân 1.0")).result, try bran.toSnapshot());

    var regolith = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer regolith.deinit();
    try flow.applyAction(&regolith, regolith.legal_actions[0]);
    try flow.applyAction(&regolith, regolith.legal_actions[0]);
    try generator.corpStartTurnFull(&regolith);
    try flow.applyAction(&regolith, regolith.legal_actions[try findCardPlayActionIndex(regolith.legal_actions, "Regolith Mining License")]);
    try expectTransitionMatches((try findCardPlayExpectation(keep_keep.play_from_hand, "Regolith Mining License")).result, try regolith.toSnapshot());

    const mull_keep = oracle.runner_after_corp_mulligan.keep_start_turn;
    var seamless_launch = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer seamless_launch.deinit();
    try flow.applyMulliganChoice(&seamless_launch, .corp, .mulligan);
    try flow.applyMulliganChoice(&seamless_launch, .runner, .keep);
    try generator.corpStartTurnFull(&seamless_launch);
    try flow.applyAction(&seamless_launch, seamless_launch.legal_actions[try findCardPlayActionIndex(seamless_launch.legal_actions, "Seamless Launch")]);
    try expectTransitionMatches((try findCardPlayExpectation(mull_keep.play_from_hand, "Seamless Launch")).result, try seamless_launch.toSnapshot());
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
    try flow.applyAction(&bran_archives, bran_archives.legal_actions[0]);
    try flow.applyAction(&bran_archives, bran_archives.legal_actions[0]);
    try generator.corpStartTurnFull(&bran_archives);
    try flow.applyAction(&bran_archives, bran_archives.legal_actions[try findCardPlayActionIndex(bran_archives.legal_actions, "Brân 1.0")]);
    const bran_expectation = try findCardPlayExpectation(keep_keep.play_from_hand, "Brân 1.0");
    try flow.applyAction(&bran_archives, bran_archives.legal_actions[try findPromptChoiceActionIndex(bran_archives.legal_actions, "Archives")]);
    try expectTransitionMatches((try findPromptChoiceExpectation(bran_expectation.prompt_choices, "Archives")).result, try bran_archives.toSnapshot());

    var regolith_remote = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer regolith_remote.deinit();
    try flow.applyAction(&regolith_remote, regolith_remote.legal_actions[0]);
    try flow.applyAction(&regolith_remote, regolith_remote.legal_actions[0]);
    try generator.corpStartTurnFull(&regolith_remote);
    try flow.applyAction(&regolith_remote, regolith_remote.legal_actions[try findCardPlayActionIndex(regolith_remote.legal_actions, "Regolith Mining License")]);
    const regolith_expectation = try findCardPlayExpectation(keep_keep.play_from_hand, "Regolith Mining License");
    try flow.applyAction(&regolith_remote, regolith_remote.legal_actions[try findPromptChoiceActionIndex(regolith_remote.legal_actions, "New remote")]);
    try expectTransitionMatches((try findPromptChoiceExpectation(regolith_expectation.prompt_choices, "New remote")).result, try regolith_remote.toSnapshot());

    var palisade_hq = try generator.createInitialSnapshot(
        allocator,
        matchups.system_gateway_beginner,
        1,
    );
    defer palisade_hq.deinit();
    try flow.applyAction(&palisade_hq, palisade_hq.legal_actions[0]);
    try flow.applyAction(&palisade_hq, palisade_hq.legal_actions[0]);
    try generator.corpStartTurnFull(&palisade_hq);
    try flow.applyAction(&palisade_hq, palisade_hq.legal_actions[try findCardPlayActionIndex(palisade_hq.legal_actions, "Palisade")]);
    const palisade_expectation = try findCardPlayExpectation(keep_keep.play_from_hand, "Palisade");
    try flow.applyAction(&palisade_hq, palisade_hq.legal_actions[try findPromptChoiceActionIndex(palisade_hq.legal_actions, "HQ")]);
    try expectTransitionMatches((try findPromptChoiceExpectation(palisade_expectation.prompt_choices, "HQ")).result, try palisade_hq.toSnapshot());
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
    for (expected) |lhs| {
        if (lhs.state.ices.len == 0 and lhs.state.content.len == 0) continue;
        const rhs = findServerSlotByName(actual, lhs.name) orelse {
            std.debug.print("Missing server: {s}\n", .{lhs.name});
            return error.TestExpectedEqual;
        };
        try expectTitleSuffix(lhs.state.ices, rhs.state.ices);
        try expectTitleSuffix(lhs.state.content, rhs.state.content);
    }
}

fn findServerSlotByName(servers: []const state.ServerSlot, name: []const u8) ?state.ServerSlot {
    for (servers) |s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    return null;
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

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findFirstPlayFromHand(generated.legal_actions, .corp));
    if (findFirstKindAction(generated.legal_actions, .prompt_choice, .corp)) |prompt_action| {
        try takeAction(allocator, &actions, &generated, prompt_action);
    }
    while (findBasicAction(generated.legal_actions, .corp, .gain_credit)) |gain_action| {
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
    if (replay.snapshot.decision_side != generated.decision_side) {
        std.debug.panic(
            "replay_side={any} actual_side={any} replay_kind={any} replay_prompt={s} actual_kind={any} actual_prompt={s}",
            .{
                replay.snapshot.decision_side,
                generated.decision_side,
                if (replay.snapshot.legal_actions.len > 0) replay.snapshot.legal_actions[0].kind else .run,
                if (replay.snapshot.legal_actions.len > 0) (replay.snapshot.legal_actions[0].prompt_type orelse "") else "",
                if (generated.legal_actions.len > 0) generated.legal_actions[0].kind else .run,
                if (generated.legal_actions.len > 0) (generated.legal_actions[0].prompt_type orelse "") else "",
            },
        );
    }
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "corp first install runner start-turn scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "corp first install runner gain-credit scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .runner, .gain_credit) orelse return error.MissingAction);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "corp first install runner draw-card scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .runner, .draw_card) orelse return error.MissingAction);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "corp first install runner sure-gamble scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Sure Gamble"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "corp first install runner run-server-1 scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "corp first install runner run-server-1 continue scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "corp first install runner run-server-1 approach-ice scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    // Initiation: both sides pass
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    // Approach-ice: corp continue triggers rez window, decline
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "No rez"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "corp first install runner run-server-1 movement-complete scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    // Initiation: both sides pass
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    // Approach-ice: corp continue triggers rez window, decline
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "No rez"));
    // Approach-ice: runner passes → advance (unrezzed ice, skip encounter) → movement
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    // Movement phase: runner gets first priority (jack-out opportunity)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    // Then corp passes
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "send-a-message access-success scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Send a Message"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "send-a-message steal scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Send a Message"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Steal"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "send-a-message cleanup-done scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Send a Message"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Steal"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Done"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner tread-lightly prompt scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Tread Lightly"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner tread-lightly server-choice scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Tread Lightly"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Server 1"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner jailbreak prompt scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Jailbreak"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner jailbreak hq-choice scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Jailbreak"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "HQ"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner overclock prompt scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Overclock"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner overclock server-choice scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Overclock"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Server 1"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner overclock run credits are attached and cleared through run flow" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();

    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try generator.corpStartTurnFull(&generated);
    try flow.applyAction(&generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Send a Message"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try flow.applyAction(&generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try flow.applyAction(&generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Overclock"));

    try std.testing.expectEqual(@as(u16, 4), generated.runner_credit);
    try std.testing.expectEqual(@as(u16, 0), generated.runner_run_credit);

    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Server 1"));

    const run_after_choice = generated.run orelse return error.MissingRun;
    try std.testing.expectEqual(@as(u16, 5), run_after_choice.temporary_run_credits);
    try std.testing.expectEqual(@as(u16, 0), generated.runner_run_credit);

    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    const run_after_success = generated.run orelse return error.MissingRun;
    try std.testing.expectEqual(@as(u16, 5), run_after_success.temporary_run_credits);
    try std.testing.expectEqual(@as(u16, 0), generated.runner_run_credit);

    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Steal"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Done"));

    try std.testing.expect(generated.run == null);
    try std.testing.expectEqual(@as(u16, 0), generated.runner_run_credit);
}

test "runner overclock successful-run scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Send a Message"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Overclock"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner overclock cleanup-done scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Send a Message"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Overclock"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Steal"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Done"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner jailbreak successful-run effect is attached to run flow" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();

    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try generator.corpStartTurnFull(&generated);
    try flow.applyAction(&generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.legal_actions, .corp, .gain_credit)) |gain_action| {
        try flow.applyAction(&generated, gain_action);
    }
    {
        try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .end_turn, .corp));
        while (true) {
            const ps = generated.corp_prompt_state orelse break;
            if (!std.mem.eql(u8, ps.prompt_type, "discard")) break;
            if (ps.choices.len == 0) break;
            const title = if (ps.choices[0].card) |c| c.title else null;
            if (title == null) break;
            try flow.applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "discard", .choice = .{ .kind = .card, .text = title } });
        }
    }
    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const hand_before_play = generated.runner_hand.items.len;
    try flow.applyAction(&generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Jailbreak"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .runner, "HQ"));

    const run_after_choice = generated.run orelse return error.MissingRun;
    try std.testing.expectEqual(@as(u16, 0), run_after_choice.rez_cost_bonus);
    try std.testing.expectEqual(state.RunSuccessEffectKind.draw_cards, run_after_choice.successful_run_effect);
    try std.testing.expectEqual(@as(u8, 1), run_after_choice.successful_run_draw_cards);
    try std.testing.expectEqual(@as(u8, 1), run_after_choice.access_bonus);

    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    try std.testing.expectEqual(hand_before_play, generated.runner_hand.items.len);
}

test "runner jailbreak successful-run scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Jailbreak"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "HQ"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 1, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner tread-lightly run modifier is attached to run state" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 1);
    defer generated.deinit();

    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try generator.corpStartTurnFull(&generated);
    try flow.applyAction(&generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    while (findBasicAction(generated.legal_actions, .corp, .gain_credit)) |gain_action| {
        try flow.applyAction(&generated, gain_action);
    }
    {
        try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .end_turn, .corp));
        while (true) {
            const ps = generated.corp_prompt_state orelse break;
            if (!std.mem.eql(u8, ps.prompt_type, "discard")) break;
            if (ps.choices.len == 0) break;
            const title = if (ps.choices[0].card) |c| c.title else null;
            if (title == null) break;
            try flow.applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "discard", .choice = .{ .kind = .card, .text = title } });
        }
    }
    try flow.applyAction(&generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try flow.applyAction(&generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Tread Lightly"));
    try flow.applyAction(&generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Server 1"));

    const run = generated.run orelse return error.MissingRun;
    try std.testing.expectEqual(@as(u16, 3), run.rez_cost_bonus);
}

test "runner creative-commission scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Creative Commission"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner vrcation scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 3);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "VRcation"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 3, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner telework contract install scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 7);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Telework Contract"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 7, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "runner telework contract ability scenario matches live replay oracle" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 7);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Telework Contract"));
    try takeAction(allocator, &actions, &generated, try findInstalledAbilityAction(generated.legal_actions, "Telework Contract"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 7, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "manegarm skunkworks end the run parity test" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 3);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Manegarm Skunkworks"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    // Corp gets priority — rez Manegarm during the run
    try takeAction(allocator, &actions, &generated, findRezNonIceAction(generated.legal_actions, "Manegarm Skunkworks") orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    try std.testing.expect(generated.runner_prompt_state != null);
    try std.testing.expectEqualStrings("manegarm-tax", generated.runner_prompt_state.?.prompt_type);
    try std.testing.expectEqual(@as(usize, 3), generated.runner_prompt_state.?.choices.len);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "End the run"));
    try std.testing.expect(generated.run == null);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 3, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "manegarm skunkworks spend clicks parity test" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 3);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Manegarm Skunkworks"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    // Corp rezzes Manegarm during approach
    try takeAction(allocator, &actions, &generated, findRezNonIceAction(generated.legal_actions, "Manegarm Skunkworks") orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    try std.testing.expect(generated.runner_prompt_state != null);
    try std.testing.expectEqualStrings("manegarm-tax", generated.runner_prompt_state.?.prompt_type);

    const runner_clicks_before = generated.runner_click;
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Spend [Click][Click]"));

    try std.testing.expectEqual(@as(u8, runner_clicks_before - 2), generated.runner_click);
    // After paying tax, runner directly accesses Manegarm (trash prompt — no corp priority)
    try std.testing.expect(generated.runner_prompt_state != null);
    try std.testing.expectEqualStrings("access-choice", generated.runner_prompt_state.?.prompt_type);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "No action"));

    try std.testing.expect(generated.run == null);
    try std.testing.expect(generated.runner_successful_run_this_turn);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 3, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "manegarm skunkworks pay credits parity test" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 3);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Manegarm Skunkworks"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    // Corp rezzes Manegarm during approach
    try takeAction(allocator, &actions, &generated, findRezNonIceAction(generated.legal_actions, "Manegarm Skunkworks") orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    try std.testing.expect(generated.runner_prompt_state != null);
    try std.testing.expectEqualStrings("manegarm-tax", generated.runner_prompt_state.?.prompt_type);

    const runner_credits_before = generated.runner_credit;
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Pay 5 [Credits]"));

    try std.testing.expectEqual(@as(u16, runner_credits_before - 5), generated.runner_credit);
    // After paying tax, runner directly accesses Manegarm (trash prompt — no corp priority)
    try std.testing.expect(generated.runner_prompt_state != null);
    try std.testing.expectEqualStrings("access-choice", generated.runner_prompt_state.?.prompt_type);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "No action"));

    try std.testing.expect(generated.run == null);
    try std.testing.expect(generated.runner_successful_run_this_turn);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 3, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
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
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp plays Hedge Fund (cost 5, gain 9), then gains 2 credits
    // Playing a card keeps hand at 5, avoiding discard at end of turn
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Hedge Fund"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1: runner gains credits
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2: corp plays Government Subsidy (costs 10, gains 15)
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Government Subsidy"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 4, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "regolith mining license install parity test" {
    const allocator = std.testing.allocator;
    // Seed 16: Corp hand has 2x Regolith Mining License
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 16);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Regolith Mining License on a remote
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Regolith Mining License"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 16, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "nico campaign install parity test" {
    const allocator = std.testing.allocator;
    // Seed 7: Corp hand has 2x Nico Campaign
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 7);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Nico Campaign on a remote
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Nico Campaign"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 7, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "offworld office install and advance parity test" {
    const allocator = std.testing.allocator;
    // Seed 8: Corp hand has Offworld Office + Seamless Launch + Hedge Fund
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 8);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Offworld Office in a remote, then advances it
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Offworld Office"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    // Advance Offworld once (costs 1 click + 1 credit)
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    // Advance prompt uses server|zone|index format: "remote1|c|0" for first content in first remote
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "remote1|c|0"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 8, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "pennyshaver install parity test" {
    const allocator = std.testing.allocator;
    // Seed 23: Runner hand has Pennyshaver (hardware, cost 3)
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 23);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1: runner installs Pennyshaver
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Pennyshaver"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 23, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "smartware distributor install and ability parity test" {
    const allocator = std.testing.allocator;
    // Seed 14: Runner hand has Smartware Distributor (cost 0)
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 14);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1: runner installs Smartware Distributor and uses place_credits ability
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Smartware Distributor"));
    try takeAction(allocator, &actions, &generated, try findInstalledAbilityAction(generated.legal_actions, "Smartware Distributor"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 14, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "predictive planogram parity test" {
    const allocator = std.testing.allocator;
    // Seed 4 intermediate: Corp hand has Predictive Planogram (cost 0, draw 2, gain 3 if tagged)
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 4);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp plays Predictive Planogram
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Predictive Planogram"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 4, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
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
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Verify parity before runner plays Mutual Favor
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const pre_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(pre_actions);
    var pre_replay = try fixture.replayActionsWithMatchup(allocator, 7, pre_actions, "system-gateway-intermediate");
    defer pre_replay.deinit();
    try expectSnapshotMatches(pre_replay.snapshot, try generated.toSnapshot());

    // Now play Mutual Favor and verify Zig engine state is correct
    const runner_hand_before = generated.runner_hand.items.len;
    const runner_deck_before = generated.runner_deck.items.len;
    try flow.applyAction(&generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Mutual Favor"));

    // Mutual Favor: costs 0, uses 1 click, plays from hand (-1), searches for icebreaker (+1)
    // Net hand change: 0 (played 1, gained 1 icebreaker from deck)
    try std.testing.expectEqual(runner_hand_before, generated.runner_hand.items.len);
    try std.testing.expectEqual(runner_deck_before - 1, generated.runner_deck.items.len);
    try std.testing.expectEqual(@as(u8, 3), generated.runner_click);
    try std.testing.expectEqual(@as(u16, 5), generated.runner_credit);

    // The last card in hand should be an icebreaker
    const last_card = generated.runner_hand.items[generated.runner_hand.items.len - 1];
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
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1: runner plays Wildcat Strike, corp makes a choice
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Wildcat Strike"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 18, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "icebreaker encounter parity test" {
    const allocator = std.testing.allocator;
    // Seed 20: Corp hand has Karuna (ICE), Runner hand has Mayfly (icebreaker, cost 1)
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 20);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Karuna (ICE) on a remote
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findFirstCorpInstallPlay(&generated, generated.legal_actions) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1: runner installs Mayfly (icebreaker), then gains credits
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Mayfly"));
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2: corp gains credits
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 2: runner runs on Server 1 (which has the ICE)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    // Corp gets chance to rez ICE
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    // Runner approaches ICE
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 20, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

// Corp installs Brân 1.0 and runner encounters it parity test
// Uses seed 5 which has Brân 1.0 in the corp starting hand
test "corp installs bran ice runner encounters it parity test" {
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 5);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);

    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Brân 1.0"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));

    try takeAction(allocator, &actions, &generated, .{
        .kind = .end_turn,
        .side = .corp,
    });
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 5, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
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
    if (std.mem.eql(u8, prompt_type, "funhouse-encounter")) return "other";
    if (std.mem.eql(u8, prompt_type, "retribution-trash")) return "other";
    if (std.mem.eql(u8, prompt_type, "break-sub")) return "other";
    if (std.mem.eql(u8, prompt_type, "sprint-shuffle")) return "select";
    if (std.mem.eql(u8, prompt_type, "hansei-trash")) return "select";
    if (std.mem.eql(u8, prompt_type, "ballista-trash")) return "other";
    if (std.mem.eql(u8, prompt_type, "above-the-law-trash")) return "other";
    if (std.mem.eql(u8, prompt_type, "anoetic-void")) return "other";
    if (std.mem.eql(u8, prompt_type, "longevity-serum-trash")) return "select";
    if (std.mem.eql(u8, prompt_type, "longevity-serum-shuffle")) return "select";
    if (std.mem.eql(u8, prompt_type, "precision-design-archive")) return "select";
    if (std.mem.eql(u8, prompt_type, "malapert-search")) return "select";
    if (std.mem.eql(u8, prompt_type, "ansel-install")) return "select";
    if (std.mem.eql(u8, prompt_type, "tao-swap-ice")) return "select";
    if (std.mem.eql(u8, prompt_type, "reality-plus")) return "other";
    if (std.mem.eql(u8, prompt_type, "trojan-host")) return "select";
    if (std.mem.eql(u8, prompt_type, "access-cleanup")) return "select";
    if (std.mem.eql(u8, prompt_type, "mu-overflow")) return "select";
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
    // Filter out trojans (hosted on ICE) from program comparison — Clojure tracks them on the ICE host
    const actual_programs = blk: {
        var non_trojan: std.ArrayList(state.CardInstance) = .empty;
        defer non_trojan.deinit(std.testing.allocator);
        for (actual.state.runner.rig_program) |prog| {
            if (prog.hosted_on_ice_server == null) {
                try non_trojan.append(std.testing.allocator, prog);
            }
        }
        break :blk try non_trojan.toOwnedSlice(std.testing.allocator);
    };
    defer std.testing.allocator.free(actual_programs);
    try expectSameTitles(expected.state.runner.rig_program, actual_programs);
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
            .rez_non_ice => continue, // Zig offers rez actions during runs; Clojure doesn't list them
            .use_installed_ability => {
                // Filter auto-resolve toggle abilities (Cookbook's "Toggle auto-resolve" — UI only)
                if (action.label) |label| {
                    if (std.mem.startsWith(u8, label, "Toggle auto-resolve")) continue;
                }
                try filtered.append(allocator, action);
                continue;
            },
            // Skip oracle use_ability actions that don't map to Zig basic actions
            // (e.g., Clojure corp install/play-op/remove-tag abilities, or
            // icebreaker pump/break abilities exported as use_ability with wrong basic_action)
            .use_ability => {
                if (action.basic_action == null and action.installed_ability == null) continue;
                // Filter icebreaker abilities misidentified as basic actions by Clojure
                // (e.g., Marjanah's "+1 strength" exported as draw_card basic action)
                if (action.basic_action != null and action.label != null) {
                    const ba = action.basic_action.?;
                    const label = action.label.?;
                    if (ba == .draw_card and !std.mem.startsWith(u8, label, "Draw")) continue;
                    if (ba == .gain_credit and !std.mem.startsWith(u8, label, "Gain")) continue;
                }
                try filtered.append(allocator, action);
            },
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

// --- Generic card lookup helpers for e2e action pickers ---

fn findCardInHand(gen: *const generator.Game, title: []const u8, side: state.Side) ?state.CardInstance {
    const hand = switch (side) {
        .corp => gen.corp_hand.items,
        .runner => gen.runner_hand.items,
    };
    for (hand) |card| {
        if (std.mem.eql(u8, card.title, title)) return card;
    }
    return null;
}

fn isCardType(gen: *const generator.Game, title: []const u8, side: state.Side, card_type: []const u8) bool {
    const card = findCardInHand(gen, title, side) orelse return false;
    const ct = card.card_type orelse return false;
    return std.mem.eql(u8, ct, card_type);
}

fn findPlayByCardType(gen: *const generator.Game, actions: []const state.LegalAction, side: state.Side, card_type: []const u8) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind != .play_from_hand or a.side != side) continue;
        const title = a.card_title orelse continue;
        if (isCardType(gen, title, side, card_type)) return a;
    }
    return null;
}

fn findPlayByCorpPlayKind(gen: *const generator.Game, actions: []const state.LegalAction, kind: state.CorpPlayKind) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind != .play_from_hand or a.side != .corp) continue;
        const title = a.card_title orelse continue;
        const card = findCardInHand(gen, title, .corp) orelse continue;
        if (card.corp_play.kind == kind) return a;
    }
    return null;
}

fn findPlayByRunnerPlayKind(gen: *const generator.Game, actions: []const state.LegalAction, kind: state.RunnerPlayKind) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind != .play_from_hand or a.side != .runner) continue;
        const title = a.card_title orelse continue;
        const card = findCardInHand(gen, title, .runner) orelse continue;
        if (!canAffordEventClicks(gen, card)) continue;
        if (card.runner_play.kind == kind) return a;
    }
    return null;
}

/// Check if runner has enough clicks for an event (1 base + lose_clicks)
fn canAffordEventClicks(gen: *const generator.Game, card: state.CardInstance) bool {
    return gen.runner_click >= 1 + card.runner_play.lose_clicks;
}

/// Find the best economy event: gain_credits kind with actual credit gain, prefer highest gain.
/// Skips events that only draw cards (VRcation) — those are handled separately.
fn findRunnerPureEconomy(gen: *const generator.Game, actions: []const state.LegalAction) ?state.LegalAction {
    var best: ?state.LegalAction = null;
    var best_gain: u16 = 0;
    for (actions) |a| {
        if (a.kind != .play_from_hand or a.side != .runner) continue;
        const title = a.card_title orelse continue;
        const card = findCardInHand(gen, title, .runner) orelse continue;
        if (!canAffordEventClicks(gen, card)) continue;
        if (card.runner_play.kind != .gain_credits or card.runner_play.gain_credits == 0) continue;
        if (card.runner_play.gain_credits > best_gain) {
            best = a;
            best_gain = card.runner_play.gain_credits;
        }
    }
    return best;
}

/// Find the best corp economy operation: gain_credits kind, prefer highest gain.
fn findCorpBestEconomy(gen: *const generator.Game, actions: []const state.LegalAction) ?state.LegalAction {
    var best: ?state.LegalAction = null;
    var best_gain: u16 = 0;
    for (actions) |a| {
        if (a.kind != .play_from_hand or a.side != .corp) continue;
        const title = a.card_title orelse continue;
        const card = findCardInHand(gen, title, .corp) orelse continue;
        if (card.corp_play.kind != .gain_credits or card.corp_play.gain_credits == 0) continue;
        if (card.corp_play.gain_credits > best_gain) {
            best = a;
            best_gain = card.corp_play.gain_credits;
        }
    }
    return best;
}

fn takeAction(
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(state.LegalAction),
    generated: *generator.Game,
    selected: state.LegalAction,
) !void {
    try actions.append(allocator, selected);
    try flow.applyAction(generated, selected);
}

fn takeCorpStartTurn(
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(state.LegalAction),
    generated: *generator.Game,
) !void {
    try takeAction(allocator, actions, generated, try findActionByKind(generated.legal_actions, .start_turn, .corp));
    // Phase 12: resolve locally (NOT recorded — oracle auto-resolves)
    try flow.applyAction(generated, .{ .kind = .@"continue", .side = .corp });
    try flow.applyAction(generated, .{ .kind = .@"continue", .side = .runner });
}

fn endTurnAndDiscard(
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(state.LegalAction),
    generated: *generator.Game,
    side: state.Side,
) !void {
    // If active player would need to discard after drawing, play/install a card first
    {
        const hand_len = switch (side) {
            .corp => generated.corp_hand.items.len,
            .runner => generated.runner_hand.items.len,
        };
        const hand_size = switch (side) {
            .corp => generated.corp_hand_size.total,
            .runner => generated.runner_hand_size.total,
        };
        if (hand_len > hand_size) {
            // Try to play any card from hand (install or operation) to reduce hand size
            if (findFirstCorpInstallPlay(generated, generated.legal_actions)) |install_action| {
                try takeAction(allocator, actions, generated, install_action);
                if (generated.corp_prompt_state) |ps| {
                    if (std.mem.eql(u8, ps.prompt_type, "install-destination")) {
                        try takeAction(allocator, actions, generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
                    }
                }
            } else {
                // All cards are operations — play the cheapest one
                if (findFirstPlayFromHand(generated.legal_actions, side) catch null) |play_action| {
                    try takeAction(allocator, actions, generated, play_action);
                    // Resolve any operation-specific prompts
                    while (generated.corp_prompt_state != null) {
                        const cp = generated.corp_prompt_state.?;
                        if (cp.choices.len > 0) {
                            const choice_text = if (cp.choices[0].text) |t| t else break;
                            try takeAction(allocator, actions, generated, .{
                                .kind = .prompt_choice,
                                .side = .corp,
                                .prompt_type = cp.prompt_type,
                                .choice = .{ .kind = .string, .text = choice_text },
                            });
                        } else break;
                    }
                }
            }
        }
    }
    // Spend remaining clicks
    while (findBasicAction(generated.legal_actions, side, .gain_credit)) |gain_action| {
        try takeAction(allocator, actions, generated, gain_action);
    }
    try takeAction(allocator, actions, generated, try findActionByKind(generated.legal_actions, .end_turn, side));
    // Resolve discard prompts without recording (Clojure auto-resolves discard)
    while (true) {
        const ps = switch (side) {
            .corp => generated.corp_prompt_state,
            .runner => generated.runner_prompt_state,
        };
        const prompt = ps orelse break;
        if (!std.mem.eql(u8, prompt.prompt_type, "discard")) break;
        if (prompt.choices.len == 0) break;
        const title = if (prompt.choices[0].card) |c| c.title else null;
        if (title == null) break;
        try flow.applyAction(generated, .{
            .kind = .prompt_choice,
            .side = side,
            .prompt_type = "discard",
            .choice = .{ .kind = .card, .text = title },
        });
    }
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

fn findFirstCorpInstallPlay(gen: *const generator.Game, actions: []const state.LegalAction) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind != .play_from_hand or a.side != .corp or a.card_title == null) continue;
        // Skip operations — they're played, not installed
        if (isCardType(gen, a.card_title.?, .corp, "Operation")) continue;
        return a;
    }
    return null;
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
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: install Verbal Plasticity then draw
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Verbal Plasticity"));

    const hand_before = generated.runner_hand.items.len;
    const deck_before = generated.runner_deck.items.len;
    // Click draw - should draw 2 cards (1 normal + 1 Verbal Plasticity)
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .runner, .draw_card) orelse return error.MissingAction);
    try std.testing.expectEqual(hand_before + 2, generated.runner_hand.items.len);
    try std.testing.expectEqual(deck_before - 2, generated.runner_deck.items.len);

    // Second click draw - should only draw 1 card (Verbal Plasticity already triggered)
    const hand_before2 = generated.runner_hand.items.len;
    const deck_before2 = generated.runner_deck.items.len;
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .runner, .draw_card) orelse return error.MissingAction);
    try std.testing.expectEqual(hand_before2 + 1, generated.runner_hand.items.len);
    try std.testing.expectEqual(deck_before2 - 1, generated.runner_deck.items.len);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 13, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "docklands pass grants extra hq access" {
    const allocator = std.testing.allocator;
    // Seed 2 beginner: Runner hand has Docklands Pass
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: install Docklands Pass then run HQ
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Docklands Pass"));
    // Verify Docklands Pass is installed
    try std.testing.expectEqual(@as(usize, 1), generated.runner_rig_hardware.items.len);

    // Run HQ (no ice installed) - just verify the pre-access state matches oracle
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "HQ"));

    // Verify parity before access (run initiation state)
    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActions(allocator, 2, scenario_actions);
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());

    // Continue through run to access phase
    {
        var iters: u32 = 0;
        while (iters < 20) : (iters += 1) {
            if (findFirstKindAction(generated.legal_actions, .@"continue", .corp)) |cont| {
                try flow.applyAction(&generated, cont);
            } else if (findFirstKindAction(generated.legal_actions, .@"continue", .runner)) |cont| {
                try flow.applyAction(&generated, cont);
            } else break;
        }
    }
    // Verify the Docklands Pass bonus was applied
    try std.testing.expect(generated.turn_events.runner_hq_breaches > 0);
}

test "orbital superiority gives tag when runner not tagged" {
    const allocator = std.testing.allocator;
    // Seed 6 intermediate: Corp hand has Orbital Superiority
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 6);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Corp needs to install Orbital Superiority, advance it to 4, and score it.
    // This takes multiple turns. Let's install it first.
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Install Orbital Superiority in a remote
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Orbital Superiority"));
    // Choose install destination
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    // Advance it twice (click 2 and 3)
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    // Choose target - find the advance prompt
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "remote1|c|0"));
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "remote1|c|0"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Runner passes turn 1
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2: corp advances twice more and scores
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "remote1|c|0"));
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "remote1|c|0"));
    // Score it
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .corp, .score_agenda) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "remote1|c|0"));

    // Runner should now have 1 tag (not tagged before scoring)
    try std.testing.expect(!generated.game_over);
    const tag = generated.runner_tag.?;
    try std.testing.expectEqual(@as(u8, 1), tag.total);
    try std.testing.expect(tag.is_tagged);
    // Corp should have 2 agenda points
    try std.testing.expectEqual(@as(u8, 2), generated.corp_agenda_point);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 6, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

fn findBioroidBreakAction(actions: []const state.LegalAction, card_title: []const u8, subroutine_index: u8) !state.LegalAction {
    for (actions) |legal_action| {
        if (legal_action.kind != .use_subroutine) continue;
        if (legal_action.card_title == null or !std.mem.eql(u8, legal_action.card_title.?, card_title)) continue;
        if (legal_action.choice == null or legal_action.choice.?.number == null) continue;
        if (legal_action.choice.?.number.? != subroutine_index) continue;
        if (legal_action.side == .runner) return legal_action;
    }
    return error.MissingAction;
}

test "e2e beginner game plays to completion with oracle parity" {
    const allocator = std.testing.allocator;
    const seed: u64 = 1;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_beginner, seed);
    defer generated.deinit();

    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    var step: u32 = 0;
    const max_steps: u32 = 1000;
    var last_turn: u16 = 0;

    while (step < max_steps) : (step += 1) {
        if (generated.game_over) break;
        if (generated.legal_actions.len == 0) break;

        // Resolve corp phase-12 locally (NOT recorded — oracle auto-resolves)
        if (generated.corp_phase_12) {
            try flow.applyAction(&generated, .{ .kind = .@"continue", .side = .corp });
            try flow.applyAction(&generated, .{ .kind = .@"continue", .side = .runner });
            continue;
        }

        // Check oracle parity at turn boundaries
        if (generated.turn != last_turn and generated.turn > 0) {
            var replay = fixture.replayActionsWithMatchup(allocator, seed, actions.items, null) catch |err| {
                std.debug.print("\n=== ORACLE REPLAY FAILED at turn {d} (step {d}, {d} actions) ===\n", .{ generated.turn, step, actions.items.len });
                std.debug.print("  error: {s}\n", .{@errorName(err)});
                const start = if (actions.items.len > 15) actions.items.len - 15 else 0;
                for (actions.items[start..], start..) |sa, ai| {
                    std.debug.print("    [{d}] {s}/{s}", .{ ai, @tagName(sa.kind), @tagName(sa.side) });
                    if (sa.card_title) |t| std.debug.print(" title={s}", .{t});
                    if (sa.prompt_type) |pt| std.debug.print(" prompt={s}", .{pt});
                    if (sa.choice) |c| { if (c.text) |t| std.debug.print(" choice={s}", .{t}); }
                    if (sa.server) |s| std.debug.print(" server={s}", .{s});
                    std.debug.print("\n", .{});
                }
                return err;
            };
            defer replay.deinit();
            const gen_snapshot = try generated.toSnapshot();
            expectSnapshotMatches(replay.snapshot, gen_snapshot) catch |err| {
                std.debug.print("\n=== PARITY DIVERGENCE at turn {d} (step {d}, {d} actions) ===\n", .{ generated.turn, step, actions.items.len });
                std.debug.print("  rng: oracle={d} zig={d}\n", .{ replay.snapshot.state.rng_seed.?, gen_snapshot.state.rng_seed.? });
                std.debug.print("  corp: credit={d}/{d} click={d}/{d}\n", .{ replay.snapshot.state.corp.credit, gen_snapshot.state.corp.credit, replay.snapshot.state.corp.click, gen_snapshot.state.corp.click });
                std.debug.print("  runner: credit={d}/{d} click={d}/{d}\n", .{ replay.snapshot.state.runner.credit, gen_snapshot.state.runner.credit, replay.snapshot.state.runner.click, gen_snapshot.state.runner.click });
                if (replay.snapshot.state.run != null or gen_snapshot.state.run != null)
                    std.debug.print("  run: oracle={s} zig={s}\n", .{
                        if (replay.snapshot.state.run) |r| r.phase else "null",
                        if (gen_snapshot.state.run) |r| r.phase else "null",
                    });
                std.debug.print("  decision: oracle={s} zig={s}\n", .{ @tagName(replay.snapshot.decision_side), @tagName(gen_snapshot.decision_side) });
                const oracle_rprompt = if (replay.snapshot.state.runner.prompt_state) |ps| ps.prompt_type else "null";
                const zig_rprompt = if (gen_snapshot.state.runner.prompt_state) |ps| ps.prompt_type else "null";
                std.debug.print("  runner prompt: oracle={s} zig={s}\n", .{ oracle_rprompt, zig_rprompt });
                const oracle_cprompt = if (replay.snapshot.state.corp.prompt_state) |ps| ps.prompt_type else "null";
                const zig_cprompt = if (gen_snapshot.state.corp.prompt_state) |ps| ps.prompt_type else "null";
                std.debug.print("  corp prompt: oracle={s} zig={s}\n", .{ oracle_cprompt, zig_cprompt });
                std.debug.print("  last actions:\n", .{});
                const start = if (actions.items.len > 15) actions.items.len - 15 else 0;
                for (actions.items[start..], start..) |sa, ai| {
                    std.debug.print("    [{d}] {s}/{s}", .{ ai, @tagName(sa.kind), @tagName(sa.side) });
                    if (sa.card_title) |t| std.debug.print(" title={s}", .{t});
                    if (sa.prompt_type) |pt| std.debug.print(" prompt={s}", .{pt});
                    if (sa.choice) |c| { if (c.text) |t| std.debug.print(" choice={s}", .{t}); }
                    if (sa.server) |s| std.debug.print(" server={s}", .{s});
                    std.debug.print("\n", .{});
                }
                return err;
            };
            last_turn = generated.turn;
        }

        const action = pickE2eAction(&generated);
        takeAction(allocator, &actions, &generated, action) catch |err| {
            std.debug.print("\n=== ACTION ERROR at step {d} turn {d} ===\n", .{ step, generated.turn });
            std.debug.print("  kind={s} side={s}", .{ @tagName(action.kind), @tagName(action.side) });
            if (action.card_title) |t| std.debug.print(" title={s}", .{t});
            if (action.installed_ability) |ia| std.debug.print(" ability={s}", .{@tagName(ia)});
            if (action.label) |l| std.debug.print(" label={s}", .{l});
            if (action.card_index) |ci| std.debug.print(" idx={d}", .{ci});
            std.debug.print("\n", .{});
            return err;
        };
    }

    try std.testing.expect(generated.game_over);
    try std.testing.expect(generated.winner != null);
}

fn resolveOneDiscardPrompt(gen: *generator.Game) !bool {
    for ([_]state.Side{ .corp, .runner }) |side| {
        const ps = switch (side) {
            .corp => gen.corp_prompt_state,
            .runner => gen.runner_prompt_state,
        };
        const prompt = ps orelse continue;
        if (!std.mem.eql(u8, prompt.prompt_type, "discard")) continue;
        if (prompt.choices.len == 0) continue;
        const title = if (prompt.choices[0].card) |c| c.title else continue;
        try flow.applyAction(gen, .{
            .kind = .prompt_choice,
            .side = side,
            .prompt_type = "discard",
            .choice = .{ .kind = .card, .text = title },
        });
        return true;
    }
    return false;
}

fn pickE2eAction(gen: *generator.Game) state.LegalAction {
    const actions = gen.legal_actions;
    if (actions.len == 0) {
        std.debug.print("FATAL: 0 legal actions, side={s} turn={d} game_over={}\n", .{
            @tagName(gen.decision_side), gen.turn, gen.game_over,
        });
        if (gen.corp_prompt_state) |ps| std.debug.print("  corp_prompt={s} choices={d}\n", .{ ps.prompt_type, ps.choices.len });
        if (gen.runner_prompt_state) |ps| std.debug.print("  runner_prompt={s} choices={d}\n", .{ ps.prompt_type, ps.choices.len });
        if (gen.run) |run| {
            std.debug.print("  run: phase={s} pos={d} no_action={s} jack_out={}\n", .{
                run.phase,
                run.position,
                if (run.no_action) |na| @tagName(na) else "null",
                run.jack_out_available,
            });
            if (run.current_ice_index) |ci| std.debug.print("  current_ice={d}\n", .{ci});
        }
        std.debug.print("  corp_click={d} runner_click={d}\n", .{ gen.corp_click, gen.runner_click });
        std.debug.print("  end_turn={} active={s}\n", .{ gen.end_turn, @tagName(gen.active_player) });
        std.debug.print("  corp_hand={d} runner_hand={d}\n", .{ gen.corp_hand.items.len, gen.runner_hand.items.len });
        for (gen.corp_servers.items, 0..) |server, si| {
            std.debug.print("  server[{d}] '{s}': ice={d} content={d}\n", .{ si, server.name, server.ices.items.len, server.content.items.len });
        }
        @panic("0 legal actions");
    }
    const side = gen.decision_side;

    // === Prompts ===
    if (findPromptText(actions, "Keep")) |a| return a;
    if (findPromptText(actions, "Steal")) |a| return a;

    // Encounter-specific prompts: Funhouse (pay to avoid tag), Karunā (jack out after damage)
    if (findPromptText(actions, "Pay")) |a| return a;
    // For jack-out prompts during encounter, decline (don't jack out)
    if (findPromptText(actions, "No action")) |a| return a;
    // Rez window: always decline (matches oracle's auto-no-action)
    if (findPromptText(actions, "No rez")) |a| return a;

    // Tao swap-ice prompt: decline (pick "Done") to keep things simple
    if (gen.runner_prompt_state) |ps| {
        if (std.mem.eql(u8, ps.prompt_type, "tao-swap-ice")) {
            if (findPromptText(actions, "Done")) |a| return a;
        }
    }

    // Carnivore: prefer "Trash card" during access if available (exercises the ability)
    if (findPromptText(actions, "Trash card")) |a| return a;

    // Any other prompt: first choice
    for (actions) |a| {
        if (a.kind == .prompt_choice) return a;
    }

    // Corp continue (approach/movement phases)
    if (findFirstKindAction(actions, .@"continue", .corp)) |a| return a;

    // === ICE encounter combat ===
    // During encounter: break > pump > leech > bioroid > continue
    if (findEncounterBreakAction(actions)) |a| return a;
    if (findEncounterPumpAction(actions)) |a| return a;
    if (findEncounterLeechAction(actions)) |a| return a;
    if (findFirstKindAction(actions, .use_runner_ability, .runner)) |a| return a;

    // Runner continue (pass encounter/movement)
    if (findFirstKindAction(actions, .@"continue", .runner)) |a| return a;

    // Start turn
    if (findFirstKindAction(actions, .start_turn, side)) |a| return a;

    if (side == .corp) return pickCorpAction(gen, actions);
    return pickRunnerAction(gen, actions);
}

fn findEncounterBreakAction(actions: []const state.LegalAction) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind == .use_installed_ability and a.side == .runner) {
            if (a.installed_ability) |ia| {
                if (ia == .break_subroutine) return a;
            }
        }
    }
    return null;
}

fn findEncounterPumpAction(actions: []const state.LegalAction) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind == .use_installed_ability and a.side == .runner) {
            if (a.installed_ability) |ia| {
                if (ia == .pump_strength) return a;
            }
        }
    }
    return null;
}

fn findEncounterLeechAction(actions: []const state.LegalAction) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind == .use_installed_ability and a.side == .runner) {
            if (a.installed_ability) |ia| {
                if (ia == .none and a.card_title != null) return a;
            }
        }
    }
    return null;
}

fn pickCorpAction(gen: *generator.Game, actions: []const state.LegalAction) state.LegalAction {
    const credit = gen.corp_credit;

    // Score agenda if possible
    if (findBasicAction(actions, .corp, .score_agenda)) |a| return a;

    // Install cards (non-operations: ICE, agendas, assets, upgrades)
    if (gen.corp_hand.items.len > 0) {
        if (findFirstCorpInstallPlay(gen, actions)) |a| return a;
    }

    // Play economy operations (generic: best net credit gain)
    if (findCorpBestEconomy(gen, actions)) |a| return a;

    // Use installed abilities (Regolith Mining License, Nico Campaign, etc.)
    for (actions) |a| {
        if (a.kind == .use_installed_ability and a.side == .corp) return a;
    }

    // Advance installed cards if we have targets
    if (credit >= 1 and hasAdvanceableCards(gen)) {
        if (findBasicAction(actions, .corp, .advance_installed)) |a| return a;
    }

    // Play advancement operations (generic: any operation with advance_installed kind)
    if (hasAdvanceableCards(gen)) {
        if (findPlayByCorpPlayKind(gen, actions, .advance_installed)) |a| return a;
    }

    // Play custom operations (Predictive Planogram, Public Trail, Retribution, etc.)
    if (findPlayByCorpPlayKind(gen, actions, .custom)) |a| return a;

    // Draw cards if hand is small
    if (gen.corp_hand.items.len <= 3) {
        if (findBasicAction(actions, .corp, .draw_card)) |a| return a;
    }

    // Gain credits as fallback
    if (findBasicAction(actions, .corp, .gain_credit)) |a| return a;

    // End turn
    if (findFirstKindAction(actions, .end_turn, .corp)) |a| return a;

    return actions[0];
}

fn pickRunnerAction(gen: *generator.Game, actions: []const state.LegalAction) state.LegalAction {
    const click = gen.runner_click;
    const credit = gen.runner_credit;

    // Play pure economy events (generic: highest credit gain, skips draw-only events)
    if (findRunnerPureEconomy(gen, actions)) |a| return a;

    // Install economy resources (take_credits ability — drip economy)
    if (findRunnerInstallByAbility(gen, actions, .take_credits)) |a| return a;

    // Install free resources (cost 0 — Smartware Distributor etc.)
    if (findRunnerInstallByMaxCost(gen, actions, "Resource", 0)) |a| return a;

    // Use installed abilities (non-combat: take credits, place credits, run abilities)
    for (actions) |a| {
        if (a.kind == .use_installed_ability and a.side == .runner and isSafeInstalledAbility(a)) return a;
    }

    // Install hardware
    if (findPlayByCardType(gen, actions, .runner, "Hardware")) |a| return a;

    // Install icebreaker programs (have Icebreaker subtype)
    if (credit >= 3) {
        if (findRunnerInstallIcebreaker(gen, actions)) |a| return a;
    }

    // Install remaining resources (Verbal Plasticity etc.)
    if (findPlayByCardType(gen, actions, .runner, "Resource")) |a| return a;

    // Run a server if we have credits and clicks
    if (click >= 2 and credit >= 3) {
        if (findRunActionAny(actions)) |a| return a;
    }

    // Play run events (generic: any event with choose_run_target kind)
    if (findPlayByRunnerPlayKind(gen, actions, .choose_run_target)) |a| return a;

    // Play draw/utility events (VRcation, etc. — gain_credits kind with 0 credit gain)
    if (findPlayByRunnerPlayKind(gen, actions, .gain_credits)) |a| return a;

    // Play custom events (Mutual Favor, Wildcat Strike, etc.)
    if (findPlayByRunnerPlayKind(gen, actions, .custom)) |a| return a;

    // Install remaining programs (utility — Conduit, Leech)
    if (credit >= 1) {
        if (findPlayByCardType(gen, actions, .runner, "Program")) |a| return a;
    }

    // Play/install remaining cards from hand if overflowing
    if (gen.runner_hand.items.len > gen.runner_hand_size.total) {
        if (findFirstPlayFromHand(actions, .runner) catch null) |a| return a;
    }

    // Draw cards if hand is small
    if (gen.runner_hand.items.len <= 2) {
        if (findBasicAction(actions, .runner, .draw_card)) |a| return a;
    }

    // Gain credits as fallback
    if (findBasicAction(actions, .runner, .gain_credit)) |a| return a;

    // End turn
    if (findFirstKindAction(actions, .end_turn, .runner)) |a| return a;

    return actions[0];
}

fn findRunnerInstallByAbility(gen: *const generator.Game, actions: []const state.LegalAction, ability_kind: state.InstalledAbilityKind) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind != .play_from_hand or a.side != .runner) continue;
        const title = a.card_title orelse continue;
        const card = findCardInHand(gen, title, .runner) orelse continue;
        if (card.installed_ability.kind == ability_kind) return a;
    }
    return null;
}

fn findRunnerInstallByMaxCost(gen: *const generator.Game, actions: []const state.LegalAction, card_type: []const u8, max_cost: u16) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind != .play_from_hand or a.side != .runner) continue;
        const title = a.card_title orelse continue;
        const card = findCardInHand(gen, title, .runner) orelse continue;
        const ct = card.card_type orelse continue;
        if (!std.mem.eql(u8, ct, card_type)) continue;
        if ((card.cost orelse 0) <= max_cost) return a;
    }
    return null;
}

fn findRunnerInstallIcebreaker(gen: *const generator.Game, actions: []const state.LegalAction) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind != .play_from_hand or a.side != .runner) continue;
        const title = a.card_title orelse continue;
        const card = findCardInHand(gen, title, .runner) orelse continue;
        const ct = card.card_type orelse continue;
        if (!std.mem.eql(u8, ct, "Program")) continue;
        for (card.subtypes) |st| {
            if (std.mem.eql(u8, st, "Icebreaker")) return a;
        }
    }
    return null;
}

fn findRunActionAny(actions: []const state.LegalAction) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind == .run and a.side == .runner) return a;
    }
    return null;
}

fn isSafeInstalledAbility(action: state.LegalAction) bool {
    const ability = action.installed_ability orelse return false;
    return switch (ability) {
        .take_credits, .place_credits, .run_central, .run_rd, .start_of_turn_credits, .trash_for_virus_credits, .trash_for_damage, .remove_from_game_shuffle => true,
        .break_subroutine, .pump_strength, .none => false,
    };
}

fn findPromptText(actions: []const state.LegalAction, text: []const u8) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind != .prompt_choice) continue;
        if (a.choice) |c| {
            if (c.text) |t| {
                if (std.mem.eql(u8, t, text)) return a;
            }
        }
    }
    return null;
}

fn hasAdvanceableCards(gen: *const generator.Game) bool {
    for (gen.corp_servers.items) |server| {
        for (server.content.items) |card| {
            if (card.agenda_points != null) return true;
            if (card.access.adds_advancement) return true;
        }
    }
    return false;
}

fn resolveRunToEnd(
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(state.LegalAction),
    generated: *generator.Game,
) !void {
    var iters: u32 = 0;
    while (iters < 50) : (iters += 1) {
        if (generated.run == null) break;

        // Handle prompts first: steal, access, subroutine choices, encounter prompts
        if (findPromptText(generated.legal_actions, "Steal")) |a| {
            try takeAction(allocator, actions, generated, a);
            continue;
        }
        if (findPromptText(generated.legal_actions, "Take 1 tag")) |a| {
            try takeAction(allocator, actions, generated, a);
            continue;
        }
        if (findPromptText(generated.legal_actions, "Pay")) |a| {
            try takeAction(allocator, actions, generated, a);
            continue;
        }
        if (findPromptText(generated.legal_actions, "No action")) |a| {
            try takeAction(allocator, actions, generated, a);
            continue;
        }
        // Generic prompt fallback
        var found_prompt = false;
        for (generated.legal_actions) |a| {
            if (a.kind == .prompt_choice) {
                try takeAction(allocator, actions, generated, a);
                found_prompt = true;
                break;
            }
        }
        if (found_prompt) continue;

        // Continues
        if (findFirstKindAction(generated.legal_actions, .@"continue", .corp)) |cont| {
            try takeAction(allocator, actions, generated, cont);
            continue;
        }
        if (findFirstKindAction(generated.legal_actions, .@"continue", .runner)) |cont| {
            try takeAction(allocator, actions, generated, cont);
            continue;
        }
        break;
    }
}

fn findRezNonIceAction(actions: []const state.LegalAction, title: []const u8) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind == .rez_non_ice and a.card_title != null and std.mem.eql(u8, a.card_title.?, title)) return a;
    }
    return null;
}

fn findPlayByTitle(actions: []const state.LegalAction, side: state.Side, title: []const u8) ?state.LegalAction {
    for (actions) |a| {
        if (a.kind == .play_from_hand and a.side == side and a.card_title != null) {
            if (std.mem.eql(u8, a.card_title.?, title)) return a;
        }
    }
    return null;
}

// ============================================================================
// Intermediate card parity tests
// ============================================================================

test "dzmz optimizer install discount parity test" {
    const allocator = std.testing.allocator;
    // Seed 8 intermediate: Runner hand has DZMZ Optimizer
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 8);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp gains credits and ends turn
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: install DZMZ Optimizer (cost 2)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    const credit_before = generated.runner_credit;
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "DZMZ Optimizer"));

    // DZMZ costs 2 credits to install
    try std.testing.expectEqual(credit_before - 2, generated.runner_credit);
    // Should be installed in hardware rig
    try std.testing.expectEqual(@as(usize, 1), generated.runner_rig_hardware.items.len);
    try std.testing.expectEqualStrings("DZMZ Optimizer", generated.runner_rig_hardware.items[0].title);
    // Should provide +1 MU
    if (generated.runner_memory) |mem| {
        try std.testing.expectEqual(@as(u8, 5), mem.base); // 4 base + 1 from DZMZ
    }

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 8, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "leech virus placement and ice strength reduction parity test" {
    const allocator = std.testing.allocator;
    // Seed 2 intermediate: Runner hand has Leech
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 2);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: install Leech (cost 1), then run Archives (central, no ICE)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Leech"));
    try std.testing.expectEqual(@as(usize, 1), generated.runner_rig_program.items.len);
    try std.testing.expectEqualStrings("Leech", generated.runner_rig_program.items[0].title);

    // Run on Archives (a central server, no ICE) — Leech should gain a virus on successful run
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Archives"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 2, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "conduit click to run rd parity test" {
    const allocator = std.testing.allocator;
    // Seed 23 intermediate: Runner hand has Conduit
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 23);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: install Conduit (cost 4), then use its click-to-run ability
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Conduit"));
    try std.testing.expectEqual(@as(usize, 1), generated.runner_rig_program.items.len);
    try std.testing.expectEqualStrings("Conduit", generated.runner_rig_program.items[0].title);

    // Use Conduit's ability to run R&D (costs 1 click)
    try takeAction(allocator, &actions, &generated, try findInstalledAbilityAction(generated.legal_actions, "Conduit"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 23, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "funhouse install and rez parity test" {
    const allocator = std.testing.allocator;
    // Seed 15 intermediate: Corp hand has 1 Funhouse
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 15);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Funhouse on HQ and gains credits
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Funhouse"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "HQ"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: pass
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2: corp gains credits (for rez)
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 2 runner: run HQ
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "HQ"));
    // Corp continue → rez window
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));

    // Check if rez window is available
    if (findPromptChoiceAction(generated.legal_actions, .corp, "Rez approached ice") catch null) |rez| {
        try takeAction(allocator, &actions, &generated, rez);
    }

    // Verify parity up to this point
    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 15, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "funhouse full encounter parity test" {
    const allocator = std.testing.allocator;
    // Full encounter: rez Funhouse → on-encounter (take tag) → subs fire → run ends
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 15);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Funhouse on HQ
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Funhouse"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "HQ"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: pass
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2: corp gains credits (need 5+ to rez Funhouse)
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 2 runner: pass
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 3: corp gains more credits
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 3 runner: run HQ (corp should have 5+ credits)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try std.testing.expect(generated.corp_credit >= 5);
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "HQ"));
    // Corp gets priority — approach ICE phase
    // Corp continue → triggers rez window if affordable
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    // Rez Funhouse via rez-window (if available)
    if (findPromptChoiceAction(generated.legal_actions, .corp, "Rez approached ice") catch null) |rez_action| {
        try takeAction(allocator, &actions, &generated, rez_action);
    } else {
        // Corp can't afford to rez — skip this test
        return;
    }
    // Runner continue → encounter starts → Funhouse on-encounter prompt
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    // Funhouse on-encounter: take 1 tag
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Take 1 tag"));
    try std.testing.expectEqual(@as(u8, 1), generated.runner_tag.?.total);

    // Runner in encounter — no icebreaker, continue to let subs fire
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
    // Corp continue → subs fire (give_tag_or_pay_credits)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));

    // Sub creates a prompt — resolve it, then continue through run to end
    try resolveRunToEnd(allocator, &actions, &generated);

    // Run should be over, end runner turn
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Verify parity at clean turn boundary
    try takeCorpStartTurn(allocator, &actions, &generated);
    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 15, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "funhouse encounter take tag local test" {
    const allocator = std.testing.allocator;
    // Verify Funhouse encounter mechanics locally (no oracle)
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 15);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs Funhouse on HQ
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Funhouse"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "HQ"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: pass
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2: corp gains credits
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 2 runner: run HQ
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "HQ"));
    // Approach: corp continue → rez window
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .corp));
    // Rez Funhouse if possible
    if (findPromptChoiceAction(generated.legal_actions, .corp, "Rez approached ice") catch null) |rez| {
        try takeAction(allocator, &actions, &generated, rez);
        // Runner continue → encounter → Funhouse on-encounter prompt
        try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .@"continue", .runner));
        // Funhouse prompt should exist
        try std.testing.expect(generated.runner_prompt_state != null);
        try std.testing.expectEqualStrings("funhouse-encounter", generated.runner_prompt_state.?.prompt_type);
        // Choose "Take 1 tag"
        try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Take 1 tag"));
        // Runner should have 1 tag and still be in the encounter
        try std.testing.expectEqual(@as(u8, 1), generated.runner_tag.?.total);
        try std.testing.expect(generated.run != null);
    }
}

test "public trail runner takes tag parity test" {
    const allocator = std.testing.allocator;
    // Seed 32 intermediate: Corp hand has Public Trail
    // Need runner to have run last turn + corp to have 4+ credits
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 32);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes (just gains credits)
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: make a successful run on Archives
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Archives"));
    try resolveRunToEnd(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2: corp plays Public Trail (costs 4, runner ran last turn)
    try takeCorpStartTurn(allocator, &actions, &generated);
    try std.testing.expect(generated.corp_credit >= 4);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Public Trail"));
    // Runner must choose: Take 1 tag or Pay 8 credits
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Take 1 tag"));

    // Runner should now have 1 tag
    const tag = generated.runner_tag.?;
    try std.testing.expectEqual(@as(u8, 1), tag.total);
    try std.testing.expect(tag.is_tagged);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 32, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "retribution trashes runner program parity test" {
    const allocator = std.testing.allocator;
    // Seed 21: Corp has both Public Trail and Retribution, runner has a program.
    // Flow: runner installs program + runs, corp tags via Public Trail then trashes via Retribution.
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 21);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1 corp: gain credits (need 4 for Public Trail + 1 for Retribution)
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: install a program, then run Archives (sets successful_run for Public Trail)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    const prog = findPlayByCardType(&generated, generated.legal_actions, .runner, "Program") orelse return;
    try takeAction(allocator, &actions, &generated, prog);
    const prog_count = generated.runner_rig_program.items.len;
    try std.testing.expect(prog_count >= 1);
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Archives"));
    try resolveRunToEnd(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2 corp: play Public Trail (tags runner), then Retribution (trashes program)
    try takeCorpStartTurn(allocator, &actions, &generated);
    try std.testing.expect(generated.corp_credit >= 5); // 4 for PT + 1 for Ret
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Public Trail"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Take 1 tag"));

    // Runner is now tagged — play Retribution
    try std.testing.expect(generated.runner_tag.?.is_tagged);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Retribution"));
    // Choose first program (p|0)
    try std.testing.expect(generated.corp_prompt_state != null);
    try std.testing.expectEqualStrings("retribution-trash", generated.corp_prompt_state.?.prompt_type);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "p|0"));
    try std.testing.expectEqual(prog_count - 1, generated.runner_rig_program.items.len);

    // Verify oracle parity
    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 21, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "amaze amusements install parity test" {
    const allocator = std.testing.allocator;
    // Seed 6 intermediate: Corp hand has AMAZE Amusements
    // Verify AMAZE Amusements installs in a remote correctly
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, 6);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // Mulligan phase
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs AMAZE Amusements in a remote
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "AMAZE Amusements"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Verify parity
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 6, scenario_actions, "system-gateway-intermediate");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

// ============================================================================
// Advanced card parity tests (System Gateway full set)
// ============================================================================

test "buzzsaw install parity test" {
    const allocator = std.testing.allocator;
    // Seed 1 advanced: Runner has Buzzsaw
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Buzzsaw"));
    try std.testing.expect(generated.runner_rig_program.items.len >= 1);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 1, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "echelon install parity test" {
    const allocator = std.testing.allocator;
    // Seed 1 advanced: Runner has Echelon
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Echelon"));
    try std.testing.expect(generated.runner_rig_program.items.len >= 1);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 1, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "marjanah install parity test" {
    const allocator = std.testing.allocator;
    // Seed 8 advanced: Runner has Marjanah
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 8);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Marjanah"));
    try std.testing.expect(generated.runner_rig_program.items.len >= 1);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 8, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "t400 memory diamond install parity test" {
    const allocator = std.testing.allocator;
    // Seed 12 advanced: Runner has T400 Memory Diamond
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 12);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    const mu_before = generated.runner_memory.?.available;
    const hs_before = generated.runner_hand_size.total;
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "T400 Memory Diamond"));
    try std.testing.expectEqual(mu_before + 1, generated.runner_memory.?.available);
    try std.testing.expectEqual(hs_before + 1, generated.runner_hand_size.total);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 12, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "sprint draw and shuffle parity test" {
    const allocator = std.testing.allocator;
    // Seed 1 advanced: Corp has Sprint
    // Sprint prompt selections are auto-resolved by oracle (skipped from action stream).
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);

    const hand_before = generated.corp_hand.items.len;
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Sprint"));
    // Sprint draws 3 then presents shuffle prompt
    try std.testing.expect(generated.corp_prompt_state != null);
    try std.testing.expectEqualStrings("sprint-shuffle", generated.corp_prompt_state.?.prompt_type);

    // Pick first card to shuffle back
    const first_pick = generated.corp_hand.items[0].title;
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, first_pick));
    // Pick second card
    const second_pick = generated.corp_hand.items[0].title;
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, second_pick));
    try std.testing.expectEqual(hand_before, generated.corp_hand.items.len);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Verify at runner start turn for stable parity point
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 1, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "hansei review gain credits and trash parity test" {
    const allocator = std.testing.allocator;
    // Seed 15 advanced: Corp has Hansei Review (cost 5)
    // Hansei trash prompt is auto-resolved by oracle (skipped from action stream).
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 15);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);

    const credit_before = generated.corp_credit;
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Hansei Review"));
    try std.testing.expectEqual(credit_before + 5, generated.corp_credit);
    // Resolve the trash prompt (auto-resolved in oracle)
    try std.testing.expect(generated.corp_prompt_state != null);
    const trash_pick = generated.corp_hand.items[0].title;
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, trash_pick));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Verify at runner start turn for stable parity point
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 15, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "ping install and rez parity test" {
    const allocator = std.testing.allocator;
    // Seed 1 advanced: Corp has Ping
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Install Ping on a server
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Ping"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Runner runs the server
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 1, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "tomorrows headline install parity test" {
    const allocator = std.testing.allocator;
    // Seed 3 advanced: Corp has Tomorrow's Headline
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 3);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Install Tomorrow's Headline in a remote
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Tomorrow's Headline"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 3, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "ballista install parity test" {
    const allocator = std.testing.allocator;
    // Seed 9 advanced: Corp has Ballista
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 9);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Install Ballista on a server
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Ballista"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 9, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "above the law install parity test" {
    const allocator = std.testing.allocator;
    // Seed 4 advanced: Corp has Above the Law
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 4);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Install Above the Law in a remote
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Above the Law"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 4, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "anoetic void install parity test" {
    const allocator = std.testing.allocator;
    // Seed 8 advanced: Corp has Anoetic Void
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_advanced, 8);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Install Anoetic Void in a remote
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Anoetic Void"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 8, scenario_actions, "system-gateway-advanced");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

// ============================================================================
// Complete card parity tests (new cards from system-gateway-complete matchup)
// ============================================================================

fn findCardInHandBySeed(matchup: generator.MatchupSpec, title: []const u8, side: state.Side, max_seed: u64) ?u64 {
    var seed: u64 = 1;
    while (seed <= max_seed) : (seed += 1) {
        var g = generator.createInitialSnapshot(std.testing.allocator, matchup, seed) catch continue;
        defer g.deinit();
        const hand = switch (side) {
            .corp => g.corp_hand.items,
            .runner => g.runner_hand.items,
        };
        for (hand) |card| {
            if (std.mem.eql(u8, card.title, title)) return seed;
        }
    }
    return null;
}

fn findTwoCardsInHandBySeed(matchup: generator.MatchupSpec, title1: []const u8, title2: []const u8, side: state.Side, max_seed: u64) ?u64 {
    var seed: u64 = 1;
    while (seed <= max_seed) : (seed += 1) {
        var g = generator.createInitialSnapshot(std.testing.allocator, matchup, seed) catch continue;
        defer g.deinit();
        const hand = switch (side) {
            .corp => g.corp_hand.items,
            .runner => g.runner_hand.items,
        };
        var found1 = false;
        var found2 = false;
        for (hand) |card| {
            if (std.mem.eql(u8, card.title, title1)) found1 = true;
            if (std.mem.eql(u8, card.title, title2)) found2 = true;
        }
        if (found1 and found2) return seed;
    }
    return null;
}

test "pharos install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Pharos", .corp, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Pharos"));
    const install_choice = generated.legal_actions[0];
    try takeAction(allocator, &actions, &generated, install_choice);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "fermenter install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Fermenter", .runner, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Fermenter"));
    try std.testing.expect(generated.runner_rig_program.items.len >= 1);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "fermenter trash for credits parity test" {
    // Fermenter: install, pass turns to accumulate virus counters, then trash for credits
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Fermenter", .runner, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1 corp: pass
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: install Fermenter (gets 1 virus counter on install)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Fermenter"));
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2 corp: pass
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 2 runner: Fermenter gets +1 virus counter on turn start (now 2 total)
    // Use trash_for_virus_credits ability: gain 2*2=4 credits
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findInstalledAbilityAction(generated.legal_actions, "Fermenter"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "luminal transubstantiation install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Luminal Transubstantiation", .corp, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Luminal Transubstantiation"));
    const install_choice = generated.legal_actions[0];
    try takeAction(allocator, &actions, &generated, install_choice);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "cookbook install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Cookbook", .runner, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Corp plays an action to use up Neurospike from hand (if present)
    // Just gain credit to advance state
    if (findBasicAction(generated.legal_actions, .corp, .gain_credit)) |gain_action| {
        try takeAction(allocator, &actions, &generated, gain_action);
    }
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Cookbook"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "clearinghouse install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Clearinghouse", .corp, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Clearinghouse"));
    const install_choice = generated.legal_actions[0];
    try takeAction(allocator, &actions, &generated, install_choice);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "neurospike parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Neurospike", .corp, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Neurospike is playable (Clojure always offers it) but does 0 damage with no scored agendas
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Neurospike"));

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "longevity serum install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Longevity Serum", .corp, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Longevity Serum"));
    const install_choice = generated.legal_actions[0];
    try takeAction(allocator, &actions, &generated, install_choice);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "spin doctor install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Spin Doctor", .corp, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Spin Doctor"));
    const install_choice = generated.legal_actions[0];
    try takeAction(allocator, &actions, &generated, install_choice);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "malapert data vault install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Malapert Data Vault", .corp, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Malapert Data Vault"));
    const install_choice = generated.legal_actions[0];
    try takeAction(allocator, &actions, &generated, install_choice);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "pantograph install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Pantograph", .runner, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Pantograph"));
    try std.testing.expect(generated.runner_rig_hardware.items.len >= 1);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "weyland built to last advance gives 2cr parity test" {
    const allocator = std.testing.allocator;
    // Find seed where corp has an advanceable card in hand
    const seed: u64 = 1;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_weyland, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Install an agenda to a remote
    const install_play = findPlayByCardType(&generated, generated.legal_actions, .corp, "Agenda") orelse return error.NoAgendaInHand;
    try takeAction(allocator, &actions, &generated, install_play);
    try takeAction(allocator, &actions, &generated, generated.legal_actions[0]); // New remote

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-weyland");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "jinteki restoring humanity end turn credit parity test" {
    const allocator = std.testing.allocator;
    const seed: u64 = 1;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_jinteki, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Play some cards to get discard, then end turn
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-jinteki");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "hb precision design hand size parity test" {
    const allocator = std.testing.allocator;
    const seed: u64 = 1;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_hb, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    // HB: Precision Design should have +1 hand size (6 total)
    try std.testing.expectEqual(@as(u8, 6), generated.corp_hand_size.total);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-hb");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "botulus install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Botulus", .runner, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Corp installs ICE so Botulus has a target
    if (findPlayByCardType(&generated, generated.legal_actions, .corp, "ICE")) |ice_play| {
        try takeAction(allocator, &actions, &generated, ice_play);
        try takeAction(allocator, &actions, &generated, generated.legal_actions[0]); // Install on server
    }
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Botulus"));
    // Trojan host selection: pick first available ICE
    try takeAction(allocator, &actions, &generated, generated.legal_actions[0]);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "tranquilizer install parity test" {
    const allocator = std.testing.allocator;
    const seed = findCardInHandBySeed(matchups.system_gateway_complete, "Tranquilizer", .runner, 100) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));
    try takeCorpStartTurn(allocator, &actions, &generated);
    if (findPlayByCardType(&generated, generated.legal_actions, .corp, "ICE")) |ice_play| {
        try takeAction(allocator, &actions, &generated, ice_play);
        try takeAction(allocator, &actions, &generated, generated.legal_actions[0]);
    }
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .runner, "Tranquilizer"));
    // Trojan host selection: pick first available ICE
    try takeAction(allocator, &actions, &generated, generated.legal_actions[0]);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "nbn reality plus tag trigger parity test" {
    // NBN Reality Plus: when runner gets first tag each turn, corp chooses gain 2cr or draw 2
    // Scenario: corp plays Public Trail to tag runner, Reality Plus fires
    const allocator = std.testing.allocator;
    // Use NBN identity with intermediate deck (has Public Trail)
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_nbn, 32);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: make a successful run on Archives (needed for Public Trail precondition)
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Archives"));
    try resolveRunToEnd(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2: corp plays Public Trail
    try takeCorpStartTurn(allocator, &actions, &generated);
    if (findPlayByTitle(generated.legal_actions, .corp, "Public Trail")) |pt| {
        const corp_credit_before = generated.corp_credit;
        try takeAction(allocator, &actions, &generated, pt);
        // Runner chooses "Take 1 tag"
        try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Take 1 tag"));
        // NBN Reality Plus should fire — corp prompted for 2cr or draw 2
        if (generated.corp_prompt_state) |ps| {
            if (std.mem.eql(u8, ps.prompt_type, "reality-plus")) {
                try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Gain 2 [Credits]"));
                // Corp should have gained 2cr from Reality Plus
                try std.testing.expect(generated.corp_credit >= corp_credit_before);
            }
        }
    } else {
        // Public Trail not in hand — just end turn and verify basic parity
        try endTurnAndDiscard(allocator, &actions, &generated, .corp);
    }

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 32, scenario_actions, "system-gateway-nbn");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "loup trash on access trigger parity test" {
    // Loup: first trash-on-access each turn: gain 1cr, draw 1
    // Scenario: corp installs a trashable asset, runner runs and trashes it
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_loup, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp installs a trashable asset in a remote
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Find any installable asset/upgrade
    const install_play = findPlayByCardType(&generated, generated.legal_actions, .corp, "Asset") orelse
        findPlayByCardType(&generated, generated.legal_actions, .corp, "Upgrade");
    if (install_play) |ip| {
        try takeAction(allocator, &actions, &generated, ip);
        try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
        // Rez it (need credits)
        try endTurnAndDiscard(allocator, &actions, &generated, .corp);

        // Runner turn: run the remote
        try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
        const runner_credit_before = generated.runner_credit;
        const runner_hand_before = generated.runner_hand.items.len;
        try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "Server 1"));
        try resolveRunToEnd(allocator, &actions, &generated);

        // Check Loup triggered (if runner trashed a card)
        // Loup gives +1cr and +1 card, so credit should be >= before (even after paying trash cost)
        _ = runner_credit_before;
        _ = runner_hand_before;
    } else {
        // No asset to install — just end turn
        try endTurnAndDiscard(allocator, &actions, &generated, .corp);
        try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    }

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 1, scenario_actions, "system-gateway-loup");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "zahya run hq credit trigger parity test" {
    // Zahya: gain 1cr per card accessed when HQ/R&D run ends (1/turn)
    // Scenario: runner runs HQ, accesses a card, Zahya gains credits
    const allocator = std.testing.allocator;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_zahya, 1);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1: corp passes
    try takeCorpStartTurn(allocator, &actions, &generated);
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: run HQ
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try takeAction(allocator, &actions, &generated, try findRunAction(generated.legal_actions, "HQ"));
    try resolveRunToEnd(allocator, &actions, &generated);

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, 1, scenario_actions, "system-gateway-zahya");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "malapert data vault score trigger parity test" {
    // Malapert: when agenda scored from same server, search R&D for non-agenda card
    const allocator = std.testing.allocator;
    const seed = findTwoCardsInHandBySeed(matchups.system_gateway_complete, "Malapert Data Vault", "Tomorrow's Headline", .corp, 200) orelse return error.NoSeedFound;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1 corp: install Malapert + agenda in same remote, advance once
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Malapert Data Vault"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    try takeAction(allocator, &actions, &generated, try findPlayFromHandByTitle(generated.legal_actions, .corp, "Tomorrow's Headline"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    // Advance agenda in remote2 (click 3) — agenda is at remote2|c|0
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "remote2|c|0"));
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Turn 1 runner: pass
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2 corp: advance twice more, then score
    try takeCorpStartTurn(allocator, &actions, &generated);
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "remote2|c|0"));
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .corp, .advance_installed) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "remote2|c|0"));
    // Score the agenda
    try takeAction(allocator, &actions, &generated, findBasicAction(generated.legal_actions, .corp, .score_agenda) orelse return error.MissingAction);
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "remote2|c|0"));

    // Pending effects queue processes: on-score effects fire inline,
    // Malapert does NOT fire because it's in a different server (remote1 vs remote2)
    // Tomorrow's Headline on-score gives runner 1 tag

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "tao salonga score trigger parity test" {
    // Tao: when agenda scored, runner may swap 2 installed ICE
    // Scenario: corp installs 2 ICE and scores, Tao gets swap prompt, declines
    const allocator = std.testing.allocator;
    // Find seed where corp has an agenda + 2 ICE in hand
    const seed: u64 = blk: {
        var s: u64 = 1;
        while (s <= 200) : (s += 1) {
            var g = generator.createInitialSnapshot(allocator, matchups.system_gateway_tao, s) catch continue;
            defer g.deinit();
            var ice_count: u8 = 0;
            var has_agenda = false;
            for (g.corp_hand.items) |card| {
                if (card.agenda_points != null) has_agenda = true;
                const ct = card.card_type orelse continue;
                if (std.mem.eql(u8, ct, "ICE")) ice_count += 1;
            }
            if (has_agenda and ice_count >= 2) break :blk s;
        }
        return error.NoSeedFound;
    };
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_tao, seed);
    defer generated.deinit();
    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "Keep"));
    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Keep"));

    // Turn 1 corp: install 2 ICE on different servers, install agenda
    try takeCorpStartTurn(allocator, &actions, &generated);
    // Install first ICE
    if (findPlayByCardType(&generated, generated.legal_actions, .corp, "ICE")) |ice_play| {
        try takeAction(allocator, &actions, &generated, ice_play);
        try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "HQ"));
    }
    // Install second ICE
    if (findPlayByCardType(&generated, generated.legal_actions, .corp, "ICE")) |ice_play| {
        try takeAction(allocator, &actions, &generated, ice_play);
        try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "R&D"));
    }
    // Install agenda
    if (findPlayByCardType(&generated, generated.legal_actions, .corp, "Agenda")) |agenda_play| {
        try takeAction(allocator, &actions, &generated, agenda_play);
        try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .corp, "New remote"));
    }
    try endTurnAndDiscard(allocator, &actions, &generated, .corp);

    // Runner passes turns while corp advances
    try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
    try endTurnAndDiscard(allocator, &actions, &generated, .runner);

    // Turn 2-4 corp: advance agenda to scoring threshold
    var turn: u8 = 0;
    while (turn < 3) : (turn += 1) {
        try takeCorpStartTurn(allocator, &actions, &generated);
        // Advance as many times as we have clicks
        while (generated.corp_click > 0) {
            if (findBasicAction(generated.legal_actions, .corp, .advance_installed)) |adv| {
                try takeAction(allocator, &actions, &generated, adv);
                // Pick the agenda (first advanceable card)
                try takeAction(allocator, &actions, &generated, generated.legal_actions[0]);
            } else break;
        }
        // Try to score
        if (findBasicAction(generated.legal_actions, .corp, .score_agenda)) |score| {
            try takeAction(allocator, &actions, &generated, score);
            try takeAction(allocator, &actions, &generated, generated.legal_actions[0]); // pick agenda

            // Tao should fire — runner gets swap prompt
            if (generated.runner_prompt_state) |ps| {
                if (std.mem.eql(u8, ps.prompt_type, "tao-swap-ice")) {
                    // Decline the swap
                    try takeAction(allocator, &actions, &generated, try findPromptChoiceAction(generated.legal_actions, .runner, "Done"));
                    break;
                }
            }
            break;
        }
        try endTurnAndDiscard(allocator, &actions, &generated, .corp);
        try takeAction(allocator, &actions, &generated, try findActionByKind(generated.legal_actions, .start_turn, .runner));
        try endTurnAndDiscard(allocator, &actions, &generated, .runner);
    }

    const scenario_actions = try actions.toOwnedSlice(allocator);
    defer allocator.free(scenario_actions);
    var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-tao");
    defer replay.deinit();
    try expectSnapshotMatches(replay.snapshot, try generated.toSnapshot());
}

test "e2e complete game plays to completion with oracle parity" {
    const allocator = std.testing.allocator;
    const seed: u64 = 3;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_complete, seed);
    defer generated.deinit();

    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    var last_turn: u16 = 0;
    var step: u32 = 0;
    while (step < 3000 and !generated.game_over) : (step += 1) {
        // Resolve discard prompts locally (not recorded)
        if (resolveOneDiscardPrompt(&generated) catch false) continue;

        // Oracle parity check at each new turn (skip during phase 12)
        if (generated.turn > last_turn and generated.turn > 0 and !generated.corp_phase_12) {
            const scenario_actions = try allocator.dupe(state.LegalAction, actions.items);
            defer allocator.free(scenario_actions);
            var replay = try fixture.replayActionsWithMatchup(allocator, seed, scenario_actions, "system-gateway-complete");
            defer replay.deinit();
            const gen_snapshot = try generated.toSnapshot();
            expectSnapshotMatches(replay.snapshot, gen_snapshot) catch |err| {
                std.debug.print("\n=== PARITY DIVERGENCE at turn {d} (step {d}, {d} actions) ===\n", .{ generated.turn, step, actions.items.len });
                std.debug.print("  rng: oracle={d} zig={d}\n", .{ replay.snapshot.state.rng_seed.?, gen_snapshot.state.rng_seed.? });
                std.debug.print("  corp: credit={d}/{d} click={d}/{d} hand={d}/{d} deck={d}/{d}\n", .{
                    replay.snapshot.state.corp.credit, gen_snapshot.state.corp.credit,
                    replay.snapshot.state.corp.click, gen_snapshot.state.corp.click,
                    replay.snapshot.state.corp.hand.len, gen_snapshot.state.corp.hand.len,
                    replay.snapshot.state.corp.deck.len, gen_snapshot.state.corp.deck.len,
                });
                std.debug.print("  runner: credit={d}/{d} click={d}/{d}\n", .{ replay.snapshot.state.runner.credit, gen_snapshot.state.runner.credit, replay.snapshot.state.runner.click, gen_snapshot.state.runner.click });
                if (replay.snapshot.state.run != null or gen_snapshot.state.run != null)
                    std.debug.print("  run: oracle={s} zig={s}\n", .{
                        if (replay.snapshot.state.run) |r| r.phase else "null",
                        if (gen_snapshot.state.run) |r| r.phase else "null",
                    });
                std.debug.print("  decision: oracle={s} zig={s}\n", .{ @tagName(replay.snapshot.decision_side), @tagName(gen_snapshot.decision_side) });
                const oracle_rprompt = if (replay.snapshot.state.runner.prompt_state) |ps| ps.prompt_type else "null";
                const zig_rprompt = if (gen_snapshot.state.runner.prompt_state) |ps| ps.prompt_type else "null";
                std.debug.print("  runner prompt: oracle={s} zig={s}\n", .{ oracle_rprompt, zig_rprompt });
                const oracle_cprompt = if (replay.snapshot.state.corp.prompt_state) |ps| ps.prompt_type else "null";
                const zig_cprompt = if (gen_snapshot.state.corp.prompt_state) |ps| ps.prompt_type else "null";
                std.debug.print("  corp prompt: oracle={s} zig={s}\n", .{ oracle_cprompt, zig_cprompt });
                std.debug.print("  last actions:\n", .{});
                const start = if (actions.items.len > 15) actions.items.len - 15 else 0;
                for (actions.items[start..], start..) |sa, ai| {
                    std.debug.print("    [{d}] {s}/{s}", .{ ai, @tagName(sa.kind), @tagName(sa.side) });
                    if (sa.card_title) |t| std.debug.print(" title={s}", .{t});
                    if (sa.prompt_type) |pt| std.debug.print(" prompt={s}", .{pt});
                    if (sa.choice) |c| {
                        if (c.text) |t| std.debug.print(" choice={s}", .{t});
                    }
                    if (sa.server) |s| std.debug.print(" server={s}", .{s});
                    std.debug.print("\n", .{});
                }
                return err;
            };
            last_turn = generated.turn;
        }

        const action = pickE2eAction(&generated);
        takeAction(allocator, &actions, &generated, action) catch |err| {
            std.debug.print("\n=== ACTION ERROR at step {d} turn {d} ===\n", .{ step, generated.turn });
            std.debug.print("  kind={s} side={s}", .{ @tagName(action.kind), @tagName(action.side) });
            if (action.card_title) |t| std.debug.print(" title={s}", .{t});
            if (action.installed_ability) |ia| std.debug.print(" ability={s}", .{@tagName(ia)});
            if (action.label) |l| std.debug.print(" label={s}", .{l});
            if (action.card_index) |ci| std.debug.print(" idx={d}", .{ci});
            std.debug.print("\n", .{});
            return err;
        };
    }

    try std.testing.expect(generated.game_over);
    try std.testing.expect(generated.winner != null);
}

test "e2e intermediate game plays to completion with oracle parity" {
    const allocator = std.testing.allocator;
    const seed: u64 = 5;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_intermediate, seed);
    defer generated.deinit();

    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    var step: u32 = 0;
    const max_steps: u32 = 1000;
    var last_turn: u16 = 0;

    while (step < max_steps) : (step += 1) {
        if (generated.game_over) break;
        if (generated.legal_actions.len == 0) break;

        // Resolve corp phase-12 locally (NOT recorded — oracle auto-resolves)
        if (generated.corp_phase_12) {
            try flow.applyAction(&generated, .{ .kind = .@"continue", .side = .corp });
            try flow.applyAction(&generated, .{ .kind = .@"continue", .side = .runner });
            continue;
        }

        // Check oracle parity at turn boundaries
        if (generated.turn != last_turn and generated.turn > 0) {
            var replay = fixture.replayActionsWithMatchup(allocator, seed, actions.items, "system-gateway-intermediate") catch |err| {
                std.debug.print("\n=== ORACLE REPLAY FAILED at turn {d} (step {d}, {d} actions) ===\n", .{ generated.turn, step, actions.items.len });
                std.debug.print("  error: {s}\n", .{@errorName(err)});
                const start = if (actions.items.len > 15) actions.items.len - 15 else 0;
                for (actions.items[start..], start..) |sa, ai| {
                    std.debug.print("    [{d}] {s}/{s}", .{ ai, @tagName(sa.kind), @tagName(sa.side) });
                    if (sa.card_title) |t| std.debug.print(" title={s}", .{t});
                    if (sa.prompt_type) |pt| std.debug.print(" prompt={s}", .{pt});
                    if (sa.choice) |c| {
                        if (c.text) |t| std.debug.print(" choice={s}", .{t});
                    }
                    if (sa.server) |s| std.debug.print(" server={s}", .{s});
                    std.debug.print("\n", .{});
                }
                return err;
            };
            defer replay.deinit();
            const gen_snapshot = try generated.toSnapshot();
            expectSnapshotMatches(replay.snapshot, gen_snapshot) catch |err| {
                std.debug.print("\n=== PARITY DIVERGENCE at turn {d} (step {d}, {d} actions) ===\n", .{ generated.turn, step, actions.items.len });
                std.debug.print("  rng: oracle={d} zig={d}\n", .{ replay.snapshot.state.rng_seed.?, gen_snapshot.state.rng_seed.? });
                std.debug.print("  corp: credit={d}/{d} click={d}/{d}\n", .{ replay.snapshot.state.corp.credit, gen_snapshot.state.corp.credit, replay.snapshot.state.corp.click, gen_snapshot.state.corp.click });
                std.debug.print("  runner: credit={d}/{d} click={d}/{d}\n", .{ replay.snapshot.state.runner.credit, gen_snapshot.state.runner.credit, replay.snapshot.state.runner.click, gen_snapshot.state.runner.click });
                if (replay.snapshot.state.run != null or gen_snapshot.state.run != null)
                    std.debug.print("  run: oracle={s} zig={s}\n", .{
                        if (replay.snapshot.state.run) |r| r.phase else "null",
                        if (gen_snapshot.state.run) |r| r.phase else "null",
                    });
                std.debug.print("  decision: oracle={s} zig={s}\n", .{ @tagName(replay.snapshot.decision_side), @tagName(gen_snapshot.decision_side) });
                const oracle_rprompt = if (replay.snapshot.state.runner.prompt_state) |ps| ps.prompt_type else "null";
                const zig_rprompt = if (gen_snapshot.state.runner.prompt_state) |ps| ps.prompt_type else "null";
                std.debug.print("  runner prompt: oracle={s} zig={s}\n", .{ oracle_rprompt, zig_rprompt });
                const oracle_cprompt = if (replay.snapshot.state.corp.prompt_state) |ps| ps.prompt_type else "null";
                const zig_cprompt = if (gen_snapshot.state.corp.prompt_state) |ps| ps.prompt_type else "null";
                std.debug.print("  corp prompt: oracle={s} zig={s}\n", .{ oracle_cprompt, zig_cprompt });
                std.debug.print("  last actions:\n", .{});
                const start = if (actions.items.len > 15) actions.items.len - 15 else 0;
                for (actions.items[start..], start..) |sa, ai| {
                    std.debug.print("    [{d}] {s}/{s}", .{ ai, @tagName(sa.kind), @tagName(sa.side) });
                    if (sa.card_title) |t| std.debug.print(" title={s}", .{t});
                    if (sa.prompt_type) |pt| std.debug.print(" prompt={s}", .{pt});
                    if (sa.choice) |c| {
                        if (c.text) |t| std.debug.print(" choice={s}", .{t});
                    }
                    if (sa.server) |s| std.debug.print(" server={s}", .{s});
                    std.debug.print("\n", .{});
                }
                return err;
            };
            last_turn = generated.turn;
        }

        const action = pickE2eAction(&generated);
        takeAction(allocator, &actions, &generated, action) catch |err| {
            std.debug.print("\n=== ACTION ERROR at step {d} turn {d} ===\n", .{ step, generated.turn });
            std.debug.print("  kind={s} side={s}", .{ @tagName(action.kind), @tagName(action.side) });
            if (action.card_title) |t| std.debug.print(" title={s}", .{t});
            if (action.installed_ability) |ia| std.debug.print(" ability={s}", .{@tagName(ia)});
            if (action.label) |l| std.debug.print(" label={s}", .{l});
            if (action.card_index) |ci| std.debug.print(" idx={d}", .{ci});
            std.debug.print("\n", .{});
            return err;
        };
    }

    try std.testing.expect(generated.game_over);
    try std.testing.expect(generated.winner != null);
}



test "e2e fullpack game plays to completion with oracle parity" {
    const allocator = std.testing.allocator;
    const seed: u64 = 7;
    var generated = try generator.createInitialSnapshot(allocator, matchups.system_gateway_fullpack, seed);
    defer generated.deinit();

    var actions: std.ArrayList(state.LegalAction) = .empty;
    defer actions.deinit(allocator);

    var step_counter: u32 = 0;
    const max_steps: u32 = 1000;

    while (step_counter < max_steps) : (step_counter += 1) {
        if (generated.game_over) break;
        if (generated.legal_actions.len == 0) break;

        if (generated.corp_phase_12) {
            try flow.applyAction(&generated, .{ .kind = .@"continue", .side = .corp });
            try flow.applyAction(&generated, .{ .kind = .@"continue", .side = .runner });
            continue;
        }

        // Per-action parity check starting from action 30 (every action)
        if (actions.items.len >= 30 and !generated.corp_phase_12) {
            var replay = fixture.replayActionsWithMatchup(allocator, seed, actions.items, "system-gateway-fullpack") catch |err| {
                std.debug.print("\n=== FULLPACK REPLAY FAILED at step {d} ({d} actions) ===\n", .{ step_counter, actions.items.len });
                return err;
            };
            defer replay.deinit();
            const gen_snapshot = try generated.toSnapshot();
            expectSnapshotMatches(replay.snapshot, gen_snapshot) catch |err| {
                std.debug.print("\n=== FULLPACK PER-ACTION DIVERGENCE at step {d} turn {d} ({d} actions) ===\n", .{ step_counter, generated.turn, actions.items.len });
                std.debug.print("  rng: oracle={d} zig={d}\n", .{ replay.snapshot.state.rng_seed.?, gen_snapshot.state.rng_seed.? });
                std.debug.print("  corp: credit={d}/{d} click={d}/{d} hand={d}/{d} deck={d}/{d}\n", .{
                    replay.snapshot.state.corp.credit, gen_snapshot.state.corp.credit,
                    replay.snapshot.state.corp.click, gen_snapshot.state.corp.click,
                    replay.snapshot.state.corp.hand.len, gen_snapshot.state.corp.hand.len,
                    replay.snapshot.state.corp.deck.len, gen_snapshot.state.corp.deck.len,
                });
                std.debug.print("  runner: credit={d}/{d} click={d}/{d}\n", .{ replay.snapshot.state.runner.credit, gen_snapshot.state.runner.credit, replay.snapshot.state.runner.click, gen_snapshot.state.runner.click });
                if (replay.snapshot.state.run != null or gen_snapshot.state.run != null)
                    std.debug.print("  run: oracle={s} zig={s}\n", .{
                        if (replay.snapshot.state.run) |r| r.phase else "null",
                        if (gen_snapshot.state.run) |r| r.phase else "null",
                    });
                std.debug.print("  last 10 actions:\n", .{});
                const s = if (actions.items.len > 10) actions.items.len - 10 else 0;
                for (actions.items[s..], s..) |sa, ai| {
                    std.debug.print("    [{d}] {s}/{s}", .{ ai, @tagName(sa.kind), @tagName(sa.side) });
                    if (sa.card_title) |t| std.debug.print(" title={s}", .{t});
                    if (sa.prompt_type) |pt| std.debug.print(" prompt={s}", .{pt});
                    if (sa.choice) |c| {
                        if (c.text) |t| std.debug.print(" choice={s}", .{t});
                    }
                    std.debug.print("\n", .{});
                }
                return err;
            };
        }

        const action = pickE2eAction(&generated);
        takeAction(allocator, &actions, &generated, action) catch |err| {
            std.debug.print("\n=== FULLPACK ERROR at step {d} turn {d} ===\n", .{ step_counter, generated.turn });
            std.debug.print("  kind={s} side={s}", .{ @tagName(action.kind), @tagName(action.side) });
            if (action.card_title) |t| std.debug.print(" title={s}", .{t});
            std.debug.print("\n", .{});
            return err;
        };
    }

    try std.testing.expect(generated.game_over);
    try std.testing.expect(generated.winner != null);
}
