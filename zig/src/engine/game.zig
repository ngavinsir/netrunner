const std = @import("std");
const catalog = @import("catalog.zig");
const state = @import("state.zig");

const MutableServer = struct {
    name: []const u8,
    ices: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    content: std.ArrayListUnmanaged(state.CardInstance) = .empty,
};

pub const Game = struct {
    arena: std.heap.ArenaAllocator,
    backing_allocator: std.mem.Allocator,
    corp_hand: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    corp_deck: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    corp_discard: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    runner_hand: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    runner_deck: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    runner_discard: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    corp_servers: std.ArrayListUnmanaged(MutableServer) = .empty,
    snapshot: state.GameSnapshot,

    pub fn deinit(self: *Game) void {
        for (self.corp_servers.items) |*server| {
            server.ices.deinit(self.backing_allocator);
            server.content.deinit(self.backing_allocator);
        }
        self.corp_servers.deinit(self.backing_allocator);
        self.corp_hand.deinit(self.backing_allocator);
        self.corp_deck.deinit(self.backing_allocator);
        self.corp_discard.deinit(self.backing_allocator);
        self.runner_hand.deinit(self.backing_allocator);
        self.runner_deck.deinit(self.backing_allocator);
        self.runner_discard.deinit(self.backing_allocator);
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const RngState = u64;

const splitmix_gamma: u64 = 0x9E3779B97F4A7C15;
const splitmix_mul_1: u64 = 0xBF58476D1CE4E5B9;
const splitmix_mul_2: u64 = 0x94D049BB133111EB;

const corp_basic_action = catalog.CardSpec{
    .title = "Corp Basic Action Card",
    .side = .corp,
    .code = 0,
    .card_type = "Basic Action",
};

const runner_basic_action = catalog.CardSpec{
    .title = "Runner Basic Action Card",
    .side = .runner,
    .code = 1,
    .card_type = "Basic Action",
};

const prompt_install_destination = "install-destination";
const prompt_access_choice = "access-choice";
const prompt_access_cleanup = "access-cleanup";
const prompt_run_target = "run-target";
const prompt_hq_access = "hq-access";

const corp_mulligan_actions = [_]state.LegalAction{
    .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") },
    .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Mulligan") },
};
const runner_mulligan_actions = [_]state.LegalAction{
    .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") },
    .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Mulligan") },
};
const corp_continue_actions = [_]state.LegalAction{
    .{ .kind = .@"continue", .side = .corp, .prompt_type = "run" },
};
const runner_continue_actions = [_]state.LegalAction{
    .{ .kind = .@"continue", .side = .runner, .prompt_type = "run" },
};
const corp_start_turn_actions = [_]state.LegalAction{
    .{ .kind = .start_turn, .side = .corp },
};
const runner_start_turn_actions = [_]state.LegalAction{
    .{ .kind = .start_turn, .side = .runner },
};
const corp_end_turn_actions = [_]state.LegalAction{
    .{ .kind = .end_turn, .side = .corp },
};
const runner_end_turn_actions = [_]state.LegalAction{
    .{ .kind = .end_turn, .side = .runner },
};

pub fn createInitialSnapshot(
    backing_allocator: std.mem.Allocator,
    matchup: catalog.MatchupSpec,
    seed: state.Seed,
) !Game {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();

    var game = Game{
        .arena = arena,
        .backing_allocator = backing_allocator,
        .snapshot = undefined,
    };
    errdefer game.deinit();

    const allocator = game.arena.allocator();
    var rng_state = init(seed);

    const corp_full_deck = try buildDeck(allocator, &rng_state, matchup.corp);
    const runner_full_deck = try buildDeck(allocator, &rng_state, matchup.runner);
    const corp_identity = try makeCardInstance(allocator, try lookupRequiredCardSpec(matchup.corp.identity_code));
    const runner_identity = try makeCardInstance(allocator, try lookupRequiredCardSpec(matchup.runner.identity_code));

    const corp_hand = try cloneCards(allocator, corp_full_deck[0..5]);
    const corp_deck = try cloneCards(allocator, corp_full_deck[5..]);
    const runner_hand = try cloneCards(allocator, runner_full_deck[0..5]);
    const runner_deck = try cloneCards(allocator, runner_full_deck[5..]);

    const mulligan_prompt = try dupPromptChoices(allocator);

    game.corp_hand = try initCardList(backing_allocator, corp_hand);
    game.corp_deck = try initCardList(backing_allocator, corp_deck);
    game.runner_hand = try initCardList(backing_allocator, runner_hand);
    game.runner_deck = try initCardList(backing_allocator, runner_deck);
    game.corp_servers = try initEmptyCorpServers(backing_allocator, allocator);
    game.snapshot = .{
        .state = .{
            .format = try allocator.dupe(u8, matchup.format),
            .seed = seed,
            .rng_seed = oracleSeed(rng_state),
            .active_player = .runner,
            .turn = 0,
            .end_turn = true,
            .pending_install = null,
            .corp = .{
                .identity = corp_identity,
                .basic_action_card = try makeCardInstance(allocator, corp_basic_action),
                .click = 0,
                .click_per_turn = 3,
                .credit = 5,
                .agenda_point = 0,
                .agenda_point_req = matchup.agenda_point_req,
                .hand_size = .{ .base = 5, .total = 5 },
                .bad_publicity = .{ .base = 0, .additional = 0 },
                .run_credit = 0,
                .link = 0,
                .tag = null,
                .memory = null,
                .brain_damage = 0,
                .keep = .undecided,
                .prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "mulligan"),
                    .choices = mulligan_prompt,
                    .source_card = null,
                },
                .deck = &.{},
                .hand = &.{},
                .discard = &.{},
                .servers = &.{},
            },
            .runner = .{
                .identity = runner_identity,
                .basic_action_card = try makeCardInstance(allocator, runner_basic_action),
                .click = 0,
                .click_per_turn = 4,
                .credit = 5,
                .agenda_point = 0,
                .agenda_point_req = matchup.agenda_point_req,
                .hand_size = .{ .base = 5, .total = 5 },
                .bad_publicity = null,
                .run_credit = 0,
                .link = 0,
                .tag = .{ .base = 0, .total = 0, .is_tagged = false },
                .memory = .{
                    .base = 4,
                    .available = 4,
                    .used = 0,
                },
                .brain_damage = 0,
                .keep = .undecided,
                .prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                },
                .deck = &.{},
                .hand = &.{},
                .discard = &.{},
                .servers = &.{},
            },
        },
        .decision_side = .corp,
        .legal_actions = &corp_mulligan_actions,
    };
    try syncOwnedViews(&game);
    return game;
}

pub fn currentPlayer(snapshot: *const Game) state.Side {
    return snapshot.snapshot.decision_side;
}

pub fn legalActionCount(snapshot: *const Game) usize {
    return snapshot.snapshot.legal_actions.len;
}

pub fn legalActionAt(
    snapshot: *const Game,
    index: usize,
) !state.LegalAction {
    if (index >= snapshot.snapshot.legal_actions.len) return error.InvalidActionIndex;
    return snapshot.snapshot.legal_actions[index];
}

pub fn applyActionByIndex(
    snapshot: *Game,
    index: usize,
) !void {
    try applyAction(snapshot, try legalActionAt(snapshot, index));
}

pub fn applyAction(
    generated: *Game,
    action: state.LegalAction,
) !void {
    if (generated.snapshot.decision_side != action.side) return error.NotCurrentDecision;

    switch (action.kind) {
        .prompt_choice => {
            const choice = action.choice orelse return error.MissingChoice;
            if (choice.kind != .string or choice.text == null) return error.UnsupportedChoice;
            try applyPromptChoice(generated, action.side, choice.text.?);
        },
        .@"continue" => try applyContinue(generated, action.side),
        .start_turn => try applyStartTurn(generated, action.side),
        .end_turn => try applyEndTurn(generated, action.side),
        .run => {
            const server = action.server orelse return error.MissingServer;
            try applyRun(generated, action.side, server);
        },
        .use_ability => {
            const basic_action = action.basic_action orelse return error.MissingAbilityKind;
            try applyBasicActionAbility(generated, action.side, basic_action);
        },
        .play_from_hand => {
            const card_index = action.card_index orelse return error.MissingCardIndex;
            try applyPlayFromHand(generated, action.side, card_index);
        },
        else => return error.UnsupportedAction,
    }
}

pub fn applyMulliganChoice(
    generated: *Game,
    side: state.Side,
    choice: state.KeepState,
) !void {
    if (choice == .undecided) return error.InvalidChoice;
    if (generated.snapshot.decision_side != side) return error.NotCurrentDecision;

    const allocator = generated.arena.allocator();
    var player = switch (side) {
        .corp => &generated.snapshot.state.corp,
        .runner => &generated.snapshot.state.runner,
    };
    player.keep = choice;

    if (choice == .mulligan) {
        var rng_state = fromOracleSeed(generated.snapshot.state.rng_seed orelse return error.MissingRngSeed);
        const combined = try combineCards(allocator, player.hand, player.deck);
        shuffleInPlace(state.CardInstance, &rng_state, combined);
        try replaceCardList(generated.backing_allocator, handList(generated, side), combined[0..5]);
        try replaceCardList(generated.backing_allocator, deckList(generated, side), combined[5..]);
        generated.snapshot.state.rng_seed = oracleSeed(rng_state);
        try syncOwnedViews(generated);
    }

    switch (side) {
        .corp => {
            player.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, "waiting"),
                .choices = &.{},
                .source_card = null,
            };

            generated.snapshot.state.runner.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, "mulligan"),
                .choices = try dupPromptChoices(allocator),
                .source_card = null,
            };
            generated.snapshot.decision_side = .runner;
            generated.snapshot.legal_actions = try mulliganActionsForSide(allocator, .runner);
        },
        .runner => {
            generated.snapshot.state.corp.prompt_state = null;
            generated.snapshot.state.runner.prompt_state = null;
            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try startTurnActions(allocator, .corp);
        },
    }
}

pub fn applyStartTurn(
    generated: *Game,
    side: state.Side,
) !void {
    if (generated.snapshot.decision_side != side) return error.NotCurrentDecision;

    const allocator = generated.arena.allocator();
    if (!generated.snapshot.state.end_turn) return error.TurnAlreadyStarted;

    switch (side) {
        .corp => {
            var corp = &generated.snapshot.state.corp;
            if (generated.corp_deck.items.len == 0) return error.EmptyDeck;
            try drawCard(generated, .corp);
            corp.click = corp.click_per_turn;

            generated.snapshot.state.active_player = .corp;
            generated.snapshot.state.turn += 1;
            generated.snapshot.state.end_turn = false;
            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try corpOpeningActionsForState(allocator, corp);
        },
        .runner => {
            var runner = &generated.snapshot.state.runner;
            runner.click = runner.click_per_turn;

            generated.snapshot.state.active_player = .runner;
            generated.snapshot.state.end_turn = false;
            generated.snapshot.decision_side = .runner;
            generated.snapshot.legal_actions = try runnerOpeningActionsForState(
                allocator,
                runner.*,
                generated.snapshot.state.corp.servers,
            );
        },
    }
}

pub fn applyEndTurn(
    generated: *Game,
    side: state.Side,
) !void {
    if (generated.snapshot.state.end_turn) return error.TurnAlreadyEnded;
    if (generated.snapshot.state.active_player != side) return error.NotActivePlayer;

    const next_side = otherSide(side);
    generated.snapshot.state.end_turn = true;
    generated.snapshot.decision_side = next_side;
    generated.snapshot.legal_actions = try startTurnActions(generated.arena.allocator(), next_side);
}

pub fn init(seed: state.Seed) RngState {
    return seed;
}

pub fn oracleSeed(rng_state: RngState) state.RngSeed {
    return @bitCast(rng_state);
}

pub fn fromOracleSeed(seed: state.RngSeed) RngState {
    return @bitCast(seed);
}

pub fn randBelow(rng_state: *RngState, upper_bound: usize) usize {
    std.debug.assert(upper_bound > 0);
    const next = nextWord(rng_state.*);
    rng_state.* = next.seed;
    return @intCast(next.word % upper_bound);
}

pub fn shuffleInPlace(comptime T: type, rng_state: *RngState, items: []T) void {
    if (items.len <= 1) return;
    var i = items.len - 1;
    while (i > 0) : (i -= 1) {
        const j = randBelow(rng_state, i + 1);
        std.mem.swap(T, &items[i], &items[j]);
    }
}

fn applyPromptChoice(
    generated: *Game,
    side: state.Side,
    choice_text: []const u8,
) !void {
    const player = switch (side) {
        .corp => generated.snapshot.state.corp,
        .runner => generated.snapshot.state.runner,
    };
    const prompt = player.prompt_state orelse return error.MissingPrompt;

    if (std.mem.eql(u8, prompt.prompt_type, "mulligan")) {
        const keep_state = parseKeepState(choice_text);
        try applyMulliganChoice(generated, side, keep_state);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_install_destination) and generated.snapshot.state.pending_install != null and prompt.source_card != null) {
        try applyPendingInstallChoice(generated, prompt.source_card.?, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_access_cleanup) and prompt.source_card != null) {
        try applyAccessCleanupChoice(generated, prompt.source_card.?, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_access_choice) and prompt.source_card != null) {
        try applyAccessPromptChoice(generated, side, prompt.source_card.?, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_hq_access)) {
        try applyHqAccessChoice(generated, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_run_target) and prompt.source_card != null) {
        try applyRunnerRunTargetChoice(generated, prompt.source_card.?, choice_text);
        return;
    }

    return error.UnsupportedPrompt;
}

fn applyBasicActionAbility(
    generated: *Game,
    side: state.Side,
    basic_action: state.BasicAction,
) !void {
    if (generated.snapshot.state.end_turn) return error.TurnNotStarted;
    if (generated.snapshot.state.active_player != side) return error.NotActivePlayer;

    switch (side) {
        .corp => try applyCorpBasicActionAbility(generated, basic_action),
        .runner => try applyRunnerBasicActionAbility(generated, basic_action),
    }
}

fn applyCorpBasicActionAbility(
    generated: *Game,
    basic_action: state.BasicAction,
) !void {
    var corp = &generated.snapshot.state.corp;

    switch (basic_action) {
        .gain_credit => {
            try spendClicks(corp, 1);
            corp.credit += 1;
        },
        .draw_card => {
            try spendClicks(corp, 1);
            try drawCard(generated, .corp);
        },
        .advance_installed => {
            try spendClicks(corp, 1);
            try spendCredits(corp, 1);
        },
        .purge_viruses => {
            try spendClicks(corp, 3);
        },
        else => return error.UnsupportedAbility,
    }

    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), corp);
}

fn applyRunnerBasicActionAbility(
    generated: *Game,
    basic_action: state.BasicAction,
) !void {
    const runner = &generated.snapshot.state.runner;

    switch (basic_action) {
        .gain_credit => {
            try spendClicks(runner, 1);
            runner.credit += 1;
        },
        .draw_card => {
            try spendClicks(runner, 1);
            try drawCard(generated, .runner);
        },
        .run_any_server => return error.UnsupportedAbility,
        else => return error.UnsupportedAbility,
    }

    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try runnerOpeningActionsForState(
        generated.arena.allocator(),
        runner.*,
        generated.snapshot.state.corp.servers,
    );
}

fn applyPlayFromHand(
    generated: *Game,
    side: state.Side,
    card_index: state.TinyCount,
) !void {
    if (generated.snapshot.state.end_turn) return error.TurnNotStarted;
    if (generated.snapshot.state.active_player != side) return error.NotActivePlayer;

    switch (side) {
        .corp => try applyCorpPlayFromHand(generated, card_index),
        .runner => try applyRunnerPlayFromHand(generated, card_index),
    }
}

fn applyCorpPlayFromHand(
    generated: *Game,
    card_index: state.TinyCount,
) !void {
    var corp = &generated.snapshot.state.corp;
    if (card_index >= corp.hand.len) return error.InvalidCardIndex;

    const card = corp.hand[card_index];
    const card_type = card.card_type orelse return error.MissingCardType;

    if (std.mem.eql(u8, card_type, "Operation")) {
        try playCorpOperation(generated, card_index, card);
        return;
    }

    if (card.install.kind != .none) {
        corp.prompt_state = .{
            .prompt_type = try generated.arena.allocator().dupe(u8, prompt_install_destination),
            .choices = try installChoicesForCard(generated.arena.allocator(), card.install.kind),
            .source_card = card,
        };
        generated.snapshot.state.pending_install = .{
            .card = card,
            .card_index = card_index,
        };
        generated.snapshot.decision_side = .corp;
        generated.snapshot.legal_actions = try promptChoiceActions(generated.arena.allocator(), .corp, corp.prompt_state.?);
        return;
    }

    return error.UnsupportedCardType;
}

fn applyPendingInstallChoice(
    generated: *Game,
    source_card: state.CardInstance,
    choice_text: []const u8,
) !void {
    var corp = &generated.snapshot.state.corp;
    const pending_install = generated.snapshot.state.pending_install orelse return error.MissingPendingInstall;
    if (pending_install.card.install.kind != source_card.install.kind) return error.UnsupportedPrompt;

    try spendClicks(corp, 1);
    _ = try removeCardFromHand(generated, .corp, pending_install.card_index);
    try installCard(generated, pending_install.card, choice_text);

    corp.prompt_state = null;
    generated.snapshot.state.pending_install = null;
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), corp);
}

fn applyAccessPromptChoice(
    generated: *Game,
    side: state.Side,
    accessed: state.CardInstance,
    choice_text: []const u8,
) !void {
    if (side != .runner) return error.UnsupportedSide;
    switch (accessed.access.kind) {
        .steal_agenda => try applyStealAgendaChoice(generated, accessed, choice_text),
        .none => return error.UnsupportedAccessTarget,
    }
}

fn applyStealAgendaChoice(
    generated: *Game,
    accessed: state.CardInstance,
    choice_text: []const u8,
) !void {
    if (!std.mem.eql(u8, choice_text, "Steal")) return error.UnsupportedChoice;

    const allocator = generated.arena.allocator();
    const run = generated.snapshot.state.run orelse return error.NoRunInProgress;
    const is_central = isCentralRunServer(run.server);

    var runner = &generated.snapshot.state.runner;
    runner.agenda_point += accessed.agenda_points orelse return error.MissingAgendaPoints;
    try removeAccessedCard(generated, run);

    if (is_central) {
        generated.snapshot.state.runner.prompt_state = null;
        generated.snapshot.state.corp.prompt_state = null;
        generated.snapshot.state.run.?.no_action = null;
        if (generated.snapshot.state.run.?.accesses_remaining > 0) {
            generated.snapshot.state.run.?.phase = try allocator.dupe(u8, "success");
            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try continueActions(allocator, .corp);
            return;
        }
        try completeRunWithoutAccess(generated);
        return;
    }

    generated.snapshot.state.runner.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "waiting"),
        .choices = &.{},
        .source_card = null,
    };
    generated.snapshot.state.corp.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_access_cleanup),
        .choices = try singleStringChoice(allocator, "Done"),
        .source_card = accessed,
    };
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try promptChoiceActions(
        allocator,
        .corp,
        generated.snapshot.state.corp.prompt_state.?,
    );
}

fn removeAccessedCard(
    generated: *Game,
    run: state.RunState,
) !void {
    const access_index = run.access_card_index orelse return error.MissingAccessTarget;
    const target_server = try findServerByRunPath(generated.snapshot.state.corp.servers, run.server);
    if (std.mem.eql(u8, run.server[0], "hq")) {
        if (access_index >= generated.corp_hand.items.len) return error.MissingAccessTarget;
        _ = generated.corp_hand.orderedRemove(access_index);
        try syncOwnedViews(generated);
        return;
    }
    if (std.mem.eql(u8, run.server[0], "rnd")) {
        if (access_index >= generated.corp_deck.items.len) return error.MissingAccessTarget;
        _ = generated.corp_deck.orderedRemove(access_index);
        try syncOwnedViews(generated);
        return;
    }
    if (std.mem.eql(u8, run.server[0], "archives")) {
        if (access_index >= generated.corp_discard.items.len) return error.MissingAccessTarget;
        _ = generated.corp_discard.orderedRemove(access_index);
        try syncOwnedViews(generated);
        return;
    }

    _ = removeServerContentCard(generated, target_server.index, 0);
    const updated_server = generated.corp_servers.items[target_server.index];
    if (target_server.index >= 3 and updated_server.ices.items.len == 0 and updated_server.content.items.len == 0) {
        var removed_server = generated.corp_servers.orderedRemove(target_server.index);
        removed_server.ices.deinit(generated.backing_allocator);
        removed_server.content.deinit(generated.backing_allocator);
    }
    try syncOwnedViews(generated);
}

fn applyAccessCleanupChoice(
    generated: *Game,
    accessed: state.CardInstance,
    choice_text: []const u8,
) !void {
    switch (accessed.access.kind) {
        .steal_agenda => {
            if (!std.mem.eql(u8, choice_text, "Done")) return error.UnsupportedChoice;
            try completeRunWithoutAccess(generated);
        },
        .none => return error.UnsupportedChoice,
    }
}

fn playCorpOperation(
    generated: *Game,
    card_index: state.TinyCount,
    card: state.CardInstance,
) !void {
    const allocator = generated.arena.allocator();
    var corp = &generated.snapshot.state.corp;
    try spendClicks(corp, 1);
    try spendCredits(corp, card.cost orelse 0);
    _ = try removeCardFromHand(generated, .corp, card_index);

    switch (card.corp_play.kind) {
        .gain_credits => {
            corp.credit += card.corp_play.gain_credits;
            try drawCards(generated, .corp, card.corp_play.draw_cards);
        },
        .no_op => {},
        .none => return error.UnsupportedOperation,
    }

    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(allocator, corp);
}

fn applyRunnerPlayFromHand(
    generated: *Game,
    card_index: state.TinyCount,
) !void {
    const runner = &generated.snapshot.state.runner;
    if (card_index >= runner.hand.len) return error.InvalidCardIndex;

    const card = runner.hand[card_index];
    const card_type = card.card_type orelse return error.MissingCardType;
    if (!std.mem.eql(u8, card_type, "Event")) return error.UnsupportedCardType;

    switch (card.runner_play.kind) {
        .gain_credits => try playRunnerGainCredits(generated, card_index, card),
        .choose_run_target => try playRunnerChooseRunTarget(generated, card_index, card),
        .none => return error.UnsupportedCardType,
    }
}

fn playRunnerGainCredits(
    generated: *Game,
    card_index: state.TinyCount,
    card: state.CardInstance,
) !void {
    const allocator = generated.arena.allocator();
    var runner = &generated.snapshot.state.runner;
    try spendClicks(runner, 1);
    try spendCredits(runner, card.cost orelse 0);
    _ = try removeCardFromHand(generated, .runner, card_index);
    try appendDiscardCard(generated, .runner, card);
    try spendClicks(runner, card.runner_play.lose_clicks);
    runner.credit += card.runner_play.gain_credits;
    try drawCards(generated, .runner, card.runner_play.draw_cards);

    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try runnerOpeningActionsForState(
        allocator,
        runner.*,
        generated.snapshot.state.corp.servers,
    );
}

fn playRunnerChooseRunTarget(
    generated: *Game,
    card_index: state.TinyCount,
    card: state.CardInstance,
) !void {
    const allocator = generated.arena.allocator();
    var runner = &generated.snapshot.state.runner;
    try spendClicks(runner, 1);
    try spendCredits(runner, card.cost orelse 0);
    _ = try removeCardFromHand(generated, .runner, card_index);
    try appendDiscardCard(generated, .runner, card);
    runner.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_run_target),
        .choices = try runTargetChoicesFor(allocator, card.runner_play.run_target_kind, generated.snapshot.state.corp.servers),
        .source_card = card,
    };

    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try promptChoiceActions(allocator, .runner, runner.prompt_state.?);
}

fn applyRunnerRunTargetChoice(
    generated: *Game,
    source_card: state.CardInstance,
    server: []const u8,
) !void {
    if (source_card.runner_play.kind != .choose_run_target) return error.UnsupportedPrompt;
    const allocator = generated.arena.allocator();
    var runner = &generated.snapshot.state.runner;
    var corp = &generated.snapshot.state.corp;

    const run_server = try canonicalRunServer(allocator, server);
    const target_server = try findServerByRunPath(corp.servers, run_server);
    const initial_position: state.TinyCount = if (isCentralRunServer(run_server))
        0
    else
        @intCast(target_server.slot.state.ices.len);

    runner.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    corp.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    generated.snapshot.state.run = .{
        .server = run_server,
        .position = initial_position,
        .phase = try allocator.dupe(u8, "initiation"),
        .corp_auto_no_action = false,
        .no_action = null,
        .temporary_run_credits = source_card.runner_play.run_credits,
        .accesses_remaining = 0,
        .accessed_count = 0,
        .accessed_card_indexes = .{ null, null, null, null },
        .access_card_index = null,
        .rez_cost_bonus = source_card.runner_play.run_rez_cost_bonus,
        .successful_run_effect = source_card.runner_play.successful_run_effect,
        .successful_run_draw_cards = source_card.runner_play.successful_run_draw_cards,
        .access_bonus = source_card.runner_play.successful_run_access_bonus,
    };
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try continueActions(allocator, .corp);
}

fn applyRun(
    generated: *Game,
    side: state.Side,
    server: []const u8,
) !void {
    if (generated.snapshot.state.end_turn) return error.TurnNotStarted;
    if (generated.snapshot.state.active_player != side) return error.NotActivePlayer;
    if (side != .runner) return error.UnsupportedSide;

    const allocator = generated.arena.allocator();
    var runner = &generated.snapshot.state.runner;
    var corp = &generated.snapshot.state.corp;
    try spendClicks(runner, 1);

    const run_server = try canonicalRunServer(allocator, server);
    const target_server = try findServerByRunPath(corp.servers, run_server);
    const initial_position: state.TinyCount = if (isCentralRunServer(run_server))
        0
    else
        @intCast(target_server.slot.state.ices.len);
    runner.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    corp.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    generated.snapshot.state.run = .{
        .server = run_server,
        .position = initial_position,
        .phase = try allocator.dupe(u8, "initiation"),
        .corp_auto_no_action = false,
        .no_action = null,
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
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try continueActions(allocator, .corp);
}

fn applyContinue(
    generated: *Game,
    side: state.Side,
) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.snapshot.state.run;
    if (run.* == null) return error.NoRunInProgress;
    if (generated.snapshot.decision_side != side) return error.NotCurrentDecision;

    if (std.mem.eql(u8, run.*.?.phase, "success")) return try advanceSuccessPhase(generated, side);

    if (run.*.?.no_action == null) {
        run.*.?.no_action = side;
        generated.snapshot.decision_side = otherSide(side);
        generated.snapshot.legal_actions = try continueActions(allocator, otherSide(side));
        return;
    }

    if (run.*.?.no_action.? == side) return error.InvalidAction;

    run.*.?.no_action = null;
    if (std.mem.eql(u8, run.*.?.phase, "initiation")) return try advanceInitiationPhase(generated);
    if (std.mem.eql(u8, run.*.?.phase, "approach-ice")) return try advanceApproachIcePhase(generated);
    if (std.mem.eql(u8, run.*.?.phase, "movement")) return try advanceMovementPhase(generated);

    return error.UnsupportedRunPhase;
}

fn advanceSuccessPhase(generated: *Game, side: state.Side) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.snapshot.state.run.?;
    if (generated.snapshot.state.runner.prompt_state) |runner_prompt| {
        if (side != .corp) return error.InvalidAction;
        generated.snapshot.state.corp.prompt_state = null;
        generated.snapshot.decision_side = .runner;
        generated.snapshot.legal_actions = try promptChoiceActions(allocator, .runner, runner_prompt);
        return;
    }

    if (run.no_action == null) {
        run.no_action = side;
        generated.snapshot.decision_side = otherSide(side);
        generated.snapshot.legal_actions = try continueActions(allocator, otherSide(side));
        return;
    }

    if (run.no_action.? == side) return error.InvalidAction;
    run.no_action = null;
    if (try prepareNextAccess(generated)) {
        run.phase = try allocator.dupe(u8, "success");
        generated.snapshot.decision_side = .corp;
        generated.snapshot.legal_actions = try continueActions(allocator, .corp);
        return;
    }
    try completeRunWithoutAccess(generated);
}

fn advanceInitiationPhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.snapshot.state.run.?;
    run.phase = try allocator.dupe(u8, if (run.position == 0) "movement" else "approach-ice");
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try continueActions(allocator, .corp);
}

fn advanceApproachIcePhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.snapshot.state.run.?;
    if (run.position > 0) run.position -= 1;
    run.phase = try allocator.dupe(u8, "movement");
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try continueActions(allocator, .corp);
}

fn advanceMovementPhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.snapshot.state.run.?;
    if (run.position > 0) {
        run.phase = try allocator.dupe(u8, "approach-ice");
        generated.snapshot.decision_side = .corp;
        generated.snapshot.legal_actions = try continueActions(allocator, .corp);
        return;
    }

    try applySuccessfulRunEffects(generated);
    if (try prepareNextAccess(generated)) {
        run.phase = try allocator.dupe(u8, "success");
        generated.snapshot.decision_side = .corp;
        generated.snapshot.legal_actions = try continueActions(allocator, .corp);
        return;
    }

    try completeRunWithoutAccess(generated);
}

fn prepareNextAccess(generated: *Game) !bool {
    const run = &generated.snapshot.state.run.?;
    if (run.accesses_remaining == 0) {
        run.accesses_remaining = 1 + run.access_bonus;
    }

    if (run.accesses_remaining == 0) return false;
    if (std.mem.eql(u8, run.server[0], "hq")) {
        const maybe_access = try nextHqAccessTarget(generated, run);
        if (maybe_access == null) {
            run.accesses_remaining = 0;
            return false;
        }
        run.access_card_index = maybe_access.?.index;
        return beginHqAccessChoicePrompt(generated);
    }
    const maybe_access = try nextAccessTarget(generated);
    if (maybe_access == null) {
        run.accesses_remaining = 0;
        return false;
    }

    run.access_card_index = maybe_access.?.index;
    rememberAccessedIndex(run, maybe_access.?.index);
    run.accesses_remaining -= 1;
    if (try beginAccessFlow(generated, maybe_access.?.card)) return true;
    return run.accesses_remaining > 0;
}

fn applySuccessfulRunEffects(generated: *Game) !void {
    const run = generated.snapshot.state.run orelse return error.NoRunInProgress;
    switch (run.successful_run_effect) {
        .none => {},
        .draw_cards => try drawCards(generated, .runner, run.successful_run_draw_cards),
    }
}

fn completeRunWithoutAccess(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.snapshot.state.run = null;
    generated.snapshot.state.corp.prompt_state = null;
    generated.snapshot.state.runner.prompt_state = null;
    generated.snapshot.state.runner.run_credit = 0;
    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try runnerOpeningActionsForState(
        allocator,
        generated.snapshot.state.runner,
        generated.snapshot.state.corp.servers,
    );
}

fn beginAccessFlow(
    generated: *Game,
    accessed: state.CardInstance,
) !bool {
    const allocator = generated.arena.allocator();
    switch (accessed.access.kind) {
        .steal_agenda => {
            generated.snapshot.state.runner.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, prompt_access_choice),
                .choices = try singleStringChoice(allocator, "Steal"),
                .source_card = accessed,
            };
            return true;
        },
        .none => return false,
    }
}

fn beginHqAccessChoicePrompt(generated: *Game) !bool {
    const allocator = generated.arena.allocator();
    generated.snapshot.state.runner.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_hq_access),
        .choices = try singleStringChoice(allocator, "Card from hand"),
        .source_card = null,
    };
    return true;
}

fn applyHqAccessChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    if (!std.mem.eql(u8, choice_text, "Card from hand")) return error.UnsupportedChoice;
    const run = &generated.snapshot.state.run.?;
    if (run.accesses_remaining == 0) return error.MissingAccessTarget;
    const access_index = run.access_card_index orelse return error.MissingAccessTarget;
    if (access_index >= generated.snapshot.state.corp.hand.len) return error.MissingAccessTarget;
    const accessed = generated.snapshot.state.corp.hand[access_index];
    rememberAccessedIndex(run, access_index);
    run.accesses_remaining -= 1;
    if (try beginAccessFlow(generated, accessed)) {
        generated.snapshot.decision_side = .runner;
        generated.snapshot.legal_actions = try promptChoiceActions(
            generated.arena.allocator(),
            .runner,
            generated.snapshot.state.runner.prompt_state.?,
        );
        return;
    }

    generated.snapshot.state.runner.prompt_state = .{
        .prompt_type = try generated.arena.allocator().dupe(u8, "waiting"),
        .choices = &.{},
        .source_card = null,
    };
    if (run.accesses_remaining > 0) {
        run.phase = try generated.arena.allocator().dupe(u8, "success");
        run.no_action = null;
        generated.snapshot.decision_side = .corp;
        generated.snapshot.legal_actions = try continueActions(generated.arena.allocator(), .corp);
        return;
    }
    try completeRunWithoutAccess(generated);
}

const AccessTarget = struct {
    index: state.TinyCount,
    card: state.CardInstance,
};

fn nextAccessTarget(generated: *Game) !?AccessTarget {
    const run = &generated.snapshot.state.run.?;
    if (std.mem.eql(u8, run.server[0], "rnd")) {
        return nextIndexedAccessTarget(generated.snapshot.state.corp.deck, run.accessed_count);
    }
    if (std.mem.eql(u8, run.server[0], "archives")) {
        return nextIndexedAccessTarget(generated.snapshot.state.corp.discard, run.accessed_count);
    }
    const target_server = try findServerByRunPath(generated.snapshot.state.corp.servers, run.server);
    return nextIndexedAccessTarget(target_server.slot.state.content, run.accessed_count);
}

fn nextIndexedAccessTarget(cards: []const state.CardInstance, accessed_count: state.TinyCount) ?AccessTarget {
    if (accessed_count >= cards.len) return null;
    return .{
        .index = accessed_count,
        .card = cards[accessed_count],
    };
}

fn nextHqAccessTarget(generated: *Game, run: *state.RunState) !?AccessTarget {
    if (generated.snapshot.state.corp.hand.len == 0) return null;
    var shuffled_indexes: [64]state.TinyCount = undefined;
    for (generated.snapshot.state.corp.hand, 0..) |_, idx| {
        shuffled_indexes[idx] = @intCast(idx);
    }
    var rng_state = fromOracleSeed(generated.snapshot.state.rng_seed orelse return error.MissingRngSeed);
    shuffleInPlace(state.TinyCount, &rng_state, shuffled_indexes[0..generated.snapshot.state.corp.hand.len]);
    generated.snapshot.state.rng_seed = oracleSeed(rng_state);
    for (shuffled_indexes[0..generated.snapshot.state.corp.hand.len]) |chosen_index| {
        if (wasIndexAccessed(run.*, chosen_index)) continue;
        return .{
            .index = chosen_index,
            .card = generated.snapshot.state.corp.hand[chosen_index],
        };
    }
    return null;
}

fn rememberAccessedIndex(run: *state.RunState, card_index: state.TinyCount) void {
    if (run.accessed_count < run.accessed_card_indexes.len) {
        run.accessed_card_indexes[run.accessed_count] = card_index;
    }
    run.accessed_count += 1;
}

fn wasIndexAccessed(run: state.RunState, card_index: state.TinyCount) bool {
    var idx: usize = 0;
    while (idx < run.accessed_count and idx < run.accessed_card_indexes.len) : (idx += 1) {
        if (run.accessed_card_indexes[idx] == card_index) return true;
    }
    return false;
}

fn mulliganActionsForSide(
    allocator: std.mem.Allocator,
    side: state.Side,
) ![]const state.LegalAction {
    _ = allocator;
    return switch (side) {
        .corp => &corp_mulligan_actions,
        .runner => &runner_mulligan_actions,
    };
}

fn continueActions(
    allocator: std.mem.Allocator,
    side: state.Side,
) ![]const state.LegalAction {
    _ = allocator;
    return switch (side) {
        .corp => &corp_continue_actions,
        .runner => &runner_continue_actions,
    };
}

fn startTurnActions(
    allocator: std.mem.Allocator,
    side: state.Side,
) ![]const state.LegalAction {
    _ = allocator;
    return switch (side) {
        .corp => &corp_start_turn_actions,
        .runner => &runner_start_turn_actions,
    };
}

fn endTurnActions(
    allocator: std.mem.Allocator,
    side: state.Side,
) ![]const state.LegalAction {
    _ = allocator;
    return switch (side) {
        .corp => &corp_end_turn_actions,
        .runner => &runner_end_turn_actions,
    };
}

fn corpOpeningActionsForState(
    allocator: std.mem.Allocator,
    corp: *const state.PlayerState,
) ![]const state.LegalAction {
    if (corp.click == 0) return endTurnActions(allocator, .corp);
    var playable_hand_count: usize = 0;
    for (corp.hand) |card| {
        if (isCorpCardPlayableFromHand(corp, card)) playable_hand_count += 1;
    }

    var count: usize = playable_hand_count;
    if (corp.click >= 1) count += 1;
    if (corp.click >= 1 and corp.deck.len > 0) count += 1;
    if (corp.click >= 1 and corp.credit >= 1) count += 1;
    if (corp.click >= 3) count += 1;

    const actions = try allocator.alloc(state.LegalAction, count);
    var next: usize = 0;
    for (corp.hand, 0..) |card, idx| {
        if (!isCorpCardPlayableFromHand(corp, card)) continue;
        actions[next] = .{
            .kind = .play_from_hand,
            .side = .corp,
            .card_index = @intCast(idx),
            .card_title = try allocator.dupe(u8, card.title),
        };
        next += 1;
    }

    if (corp.click >= 1) {
        actions[next] = try basicAbilityAction(allocator, .corp, .gain_credit, "Gain 1 [Credits]");
        next += 1;
    }
    if (corp.click >= 1 and corp.deck.len > 0) {
        actions[next] = try basicAbilityAction(allocator, .corp, .draw_card, "Draw 1 card");
        next += 1;
    }
    if (corp.click >= 1 and corp.credit >= 1) {
        actions[next] = try basicAbilityAction(allocator, .corp, .advance_installed, "Advance 1 installed card");
        next += 1;
    }
    if (corp.click >= 3) {
        actions[next] = try basicAbilityAction(allocator, .corp, .purge_viruses, "Purge virus counters");
    }

    return actions;
}

fn runnerOpeningActionsForState(
    allocator: std.mem.Allocator,
    runner: state.PlayerState,
    corp_servers: []const state.ServerSlot,
) ![]const state.LegalAction {
    if (runner.click == 0) return endTurnActions(allocator, .runner);

    const runnable_servers = try runnableServers(allocator, corp_servers);

    var playable_hand_count: usize = 0;
    for (runner.hand) |card| {
        if (isRunnerCardPlayableFromHand(runner, card)) playable_hand_count += 1;
    }

    var count: usize = playable_hand_count + runnable_servers.len;
    if (runner.click >= 1) count += 1;
    if (runner.click >= 1 and runner.deck.len > 0) count += 1;
    if (runner.click >= 1 and runnable_servers.len > 0) count += 1;

    const actions = try allocator.alloc(state.LegalAction, count);
    var next: usize = 0;
    for (runner.hand, 0..) |card, idx| {
        if (!isRunnerCardPlayableFromHand(runner, card)) continue;
        actions[next] = .{
            .kind = .play_from_hand,
            .side = .runner,
            .card_index = @intCast(idx),
            .card_title = try allocator.dupe(u8, card.title),
        };
        next += 1;
    }
    for (runnable_servers) |server_name| {
        actions[next] = .{
            .kind = .run,
            .side = .runner,
            .server = server_name,
        };
        next += 1;
    }

    if (runner.click >= 1) {
        actions[next] = try basicAbilityAction(allocator, .runner, .gain_credit, "Gain 1 [Credits]");
        next += 1;
    }
    if (runner.click >= 1 and runner.deck.len > 0) {
        actions[next] = try basicAbilityAction(allocator, .runner, .draw_card, "Draw 1 card");
        next += 1;
    }
    if (runner.click >= 1 and runnable_servers.len > 0) {
        actions[next] = try basicAbilityAction(allocator, .runner, .run_any_server, "Run any server");
    }

    return actions;
}

fn basicAbilityAction(
    allocator: std.mem.Allocator,
    side: state.Side,
    basic_action: state.BasicAction,
    label: []const u8,
) !state.LegalAction {
    return .{
        .kind = .use_ability,
        .side = side,
        .basic_action = basic_action,
        .label = try allocator.dupe(u8, label),
    };
}

fn buildDeck(
    allocator: std.mem.Allocator,
    rng_state: *RngState,
    side_spec: catalog.SideSpec,
) ![]state.CardInstance {
    const shuffled_lines = try allocator.dupe(catalog.DeckLine, side_spec.deck_lines);
    shuffleInPlace(catalog.DeckLine, rng_state, shuffled_lines);

    const total_cards = countCards(shuffled_lines);
    const cards = try allocator.alloc(state.CardInstance, total_cards);

    var idx: usize = 0;
    for (shuffled_lines) |line| {
        var copy_idx: state.TinyCount = 0;
        while (copy_idx < line.qty) : (copy_idx += 1) {
            cards[idx] = try makeCardInstance(allocator, try lookupRequiredCardSpec(line.card_code));
            idx += 1;
        }
    }

    shuffleInPlace(state.CardInstance, rng_state, cards);
    return cards;
}

fn emptyCorpServers(allocator: std.mem.Allocator) ![]const state.ServerSlot {
    const servers = try allocator.alloc(state.ServerSlot, 3);
    servers[0] = .{
        .name = try allocator.dupe(u8, "hq"),
        .state = .{ .ices = &.{}, .content = &.{} },
    };
    servers[1] = .{
        .name = try allocator.dupe(u8, "rnd"),
        .state = .{ .ices = &.{}, .content = &.{} },
    };
    servers[2] = .{
        .name = try allocator.dupe(u8, "archives"),
        .state = .{ .ices = &.{}, .content = &.{} },
    };
    return servers;
}

fn initCardList(
    allocator: std.mem.Allocator,
    cards: []const state.CardInstance,
) !std.ArrayListUnmanaged(state.CardInstance) {
    var list: std.ArrayListUnmanaged(state.CardInstance) = .empty;
    try list.appendSlice(allocator, cards);
    return list;
}

fn initEmptyCorpServers(
    list_allocator: std.mem.Allocator,
    string_allocator: std.mem.Allocator,
) !std.ArrayListUnmanaged(MutableServer) {
    var servers: std.ArrayListUnmanaged(MutableServer) = .empty;
    try servers.append(list_allocator, .{ .name = try string_allocator.dupe(u8, "hq") });
    try servers.append(list_allocator, .{ .name = try string_allocator.dupe(u8, "rnd") });
    try servers.append(list_allocator, .{ .name = try string_allocator.dupe(u8, "archives") });
    return servers;
}

fn syncOwnedViews(game: *Game) !void {
    const allocator = game.arena.allocator();

    game.snapshot.state.corp.hand = game.corp_hand.items;
    game.snapshot.state.corp.deck = game.corp_deck.items;
    game.snapshot.state.corp.discard = game.corp_discard.items;
    game.snapshot.state.runner.hand = game.runner_hand.items;
    game.snapshot.state.runner.deck = game.runner_deck.items;
    game.snapshot.state.runner.discard = game.runner_discard.items;

    const servers = try allocator.alloc(state.ServerSlot, game.corp_servers.items.len);
    for (game.corp_servers.items, 0..) |server, idx| {
        servers[idx] = .{
            .name = server.name,
            .state = .{
                .ices = server.ices.items,
                .content = server.content.items,
            },
        };
    }
    game.snapshot.state.corp.servers = servers;
}

fn cloneCards(
    allocator: std.mem.Allocator,
    cards: []const state.CardInstance,
) ![]const state.CardInstance {
    const copy = try allocator.alloc(state.CardInstance, cards.len);
    for (cards, 0..) |card, idx| copy[idx] = card;
    return copy;
}

fn countCards(lines: []const catalog.DeckLine) usize {
    var total: usize = 0;
    for (lines) |line| total += line.qty;
    return total;
}

fn dupPromptChoices(allocator: std.mem.Allocator) ![]const state.PromptChoice {
    const choices = try allocator.alloc(state.PromptChoice, 2);
    choices[0] = stringChoice("Keep");
    choices[1] = stringChoice("Mulligan");
    return choices;
}

fn singleStringChoice(
    allocator: std.mem.Allocator,
    text: []const u8,
) ![]const state.PromptChoice {
    const choices = try allocator.alloc(state.PromptChoice, 1);
    choices[0] = stringChoice(text);
    return choices;
}

fn stringChoice(text: []const u8) state.PromptChoice {
    return .{
        .kind = .string,
        .text = text,
    };
}

fn cardReferenceFor(card: state.CardInstance) state.CardReference {
    return .{
        .title = card.title,
        .printed_title = card.printed_title,
        .code = card.code,
        .side = card.side,
    };
}

fn makeCardInstance(
    allocator: std.mem.Allocator,
    spec: catalog.CardSpec,
) !state.CardInstance {
    return .{
        .title = try allocator.dupe(u8, spec.title),
        .printed_title = try allocator.dupe(u8, spec.title),
        .code = spec.code,
        .side = spec.side,
        .card_type = if (spec.card_type) |kind| try allocator.dupe(u8, kind) else null,
        .cost = spec.cost,
        .agenda_points = spec.agenda_points,
        .corp_play = spec.corp_play,
        .runner_play = spec.runner_play,
        .access = spec.access,
        .install = spec.install,
    };
}

fn lookupRequiredCardSpec(card_code: state.CardCode) !catalog.CardSpec {
    return catalog.lookupCardSpecByCode(card_code) orelse error.UnknownCardCode;
}

fn combineCards(
    allocator: std.mem.Allocator,
    hand: []const state.CardInstance,
    deck: []const state.CardInstance,
) ![]state.CardInstance {
    const combined = try allocator.alloc(state.CardInstance, hand.len + deck.len);
    @memcpy(combined[0..deck.len], deck);
    @memcpy(combined[deck.len..], hand);
    return combined;
}

fn handList(game: *Game, side: state.Side) *std.ArrayListUnmanaged(state.CardInstance) {
    return switch (side) {
        .corp => &game.corp_hand,
        .runner => &game.runner_hand,
    };
}

fn deckList(game: *Game, side: state.Side) *std.ArrayListUnmanaged(state.CardInstance) {
    return switch (side) {
        .corp => &game.corp_deck,
        .runner => &game.runner_deck,
    };
}

fn discardList(game: *Game, side: state.Side) *std.ArrayListUnmanaged(state.CardInstance) {
    return switch (side) {
        .corp => &game.corp_discard,
        .runner => &game.runner_discard,
    };
}

fn drawCard(game: *Game, side: state.Side) !void {
    const deck = deckList(game, side);
    if (deck.items.len == 0) return error.EmptyDeck;
    const drawn = deck.orderedRemove(0);
    try handList(game, side).append(game.backing_allocator, drawn);
    try syncOwnedViews(game);
}

fn drawCards(game: *Game, side: state.Side, amount: state.TinyCount) !void {
    var remaining = amount;
    while (remaining > 0) : (remaining -= 1) {
        try drawCard(game, side);
    }
}

fn replaceCardList(
    allocator: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(state.CardInstance),
    cards: []const state.CardInstance,
) !void {
    list.clearRetainingCapacity();
    try list.appendSlice(allocator, cards);
}

fn removeCardFromHand(
    game: *Game,
    side: state.Side,
    index: state.TinyCount,
) !state.CardInstance {
    const hand = handList(game, side);
    if (index >= hand.items.len) return error.InvalidCardIndex;
    const removed = hand.orderedRemove(index);
    try syncOwnedViews(game);
    return removed;
}

fn appendDiscardCard(
    game: *Game,
    side: state.Side,
    card: state.CardInstance,
) !void {
    try discardList(game, side).append(game.backing_allocator, card);
    try syncOwnedViews(game);
}

fn spendClicks(
    player: *state.PlayerState,
    amount: state.TinyCount,
) !void {
    if (player.click < amount) return error.InsufficientClicks;
    player.click -= amount;
}

fn spendCredits(
    player: *state.PlayerState,
    amount: state.Count,
) !void {
    if (player.credit < amount) return error.InsufficientCredits;
    player.credit -= amount;
}

fn parseKeepState(text: []const u8) state.KeepState {
    if (std.mem.eql(u8, text, "Keep")) return .keep;
    if (std.mem.eql(u8, text, "Mulligan")) return .mulligan;
    return .undecided;
}

fn isCorpCardPlayableFromHand(
    corp: *const state.PlayerState,
    card: state.CardInstance,
) bool {
    if (corp.click < 1) return false;
    const card_type = card.card_type orelse return false;
    if (std.mem.eql(u8, card_type, "Operation")) {
        return corp.credit >= (card.cost orelse 0);
    }

    return card.install.kind != .none;
}

fn isRunnerCardPlayableFromHand(
    runner: state.PlayerState,
    card: state.CardInstance,
) bool {
    if (runner.click < 1) return false;
    const card_type = card.card_type orelse return false;
    if (!std.mem.eql(u8, card_type, "Event") and
        !std.mem.eql(u8, card_type, "Program") and
        !std.mem.eql(u8, card_type, "Hardware") and
        !std.mem.eql(u8, card_type, "Resource"))
    {
        return false;
    }
    return runner.credit >= (card.cost orelse 0);
}

fn installChoicesForCard(
    allocator: std.mem.Allocator,
    install_kind: state.InstallKind,
) ![]const state.PromptChoice {
    return switch (install_kind) {
        .corp_server_choice => blk: {
            const choices = try allocator.alloc(state.PromptChoice, 4);
            choices[0] = stringChoice("Archives");
            choices[1] = stringChoice("HQ");
            choices[2] = stringChoice("New remote");
            choices[3] = stringChoice("R&D");
            break :blk choices;
        },
        .corp_remote_only => blk: {
            const choices = try allocator.alloc(state.PromptChoice, 1);
            choices[0] = stringChoice("New remote");
            break :blk choices;
        },
        .none => error.UnsupportedCardType,
    };
}

fn promptChoiceActions(
    allocator: std.mem.Allocator,
    side: state.Side,
    prompt: state.PromptState,
) ![]const state.LegalAction {
    const actions = try allocator.alloc(state.LegalAction, prompt.choices.len);
    for (prompt.choices, 0..) |choice, idx| {
        actions[idx] = .{
            .kind = .prompt_choice,
            .side = side,
            .prompt_type = try allocator.dupe(u8, prompt.prompt_type),
            .choice = choice,
        };
    }
    return actions;
}

fn runTargetChoicesFor(
    allocator: std.mem.Allocator,
    kind: state.RunTargetKind,
    servers: []const state.ServerSlot,
) ![]const state.PromptChoice {
    const names: []const []const u8 = switch (kind) {
        .any_runnable => try runnableServers(allocator, servers),
        .hq_and_rnd_only => try allocator.dupe([]const u8, &.{ "HQ", "R&D" }),
    };
    const choices = try allocator.alloc(state.PromptChoice, names.len);
    for (names, 0..) |name, idx| {
        choices[idx] = stringChoice(name);
    }
    return choices;
}

fn removeCardAt(
    allocator: std.mem.Allocator,
    cards: []const state.CardInstance,
    index: state.TinyCount,
) ![]const state.CardInstance {
    const idx: usize = index;
    if (idx >= cards.len) return error.InvalidCardIndex;
    const copy = try allocator.alloc(state.CardInstance, cards.len - 1);
    @memcpy(copy[0..idx], cards[0..idx]);
    @memcpy(copy[idx..], cards[idx + 1 ..]);
    return copy;
}

fn replaceCardAt(
    allocator: std.mem.Allocator,
    cards: []const state.CardInstance,
    index: state.TinyCount,
    next_card: state.CardInstance,
) ![]const state.CardInstance {
    const idx: usize = index;
    if (idx >= cards.len) return error.InvalidCardIndex;
    const copy = try allocator.alloc(state.CardInstance, cards.len);
    @memcpy(copy, cards);
    copy[idx] = next_card;
    return copy;
}

fn installCard(
    game: *Game,
    card: state.CardInstance,
    choice_text: []const u8,
) !void {
    const card_type = card.card_type orelse return error.MissingCardType;
    const installs_in_ice = std.mem.eql(u8, card_type, "ICE");
    const target_index: ?usize = if (std.mem.eql(u8, choice_text, "HQ"))
        0
    else if (std.mem.eql(u8, choice_text, "R&D"))
        1
    else if (std.mem.eql(u8, choice_text, "Archives"))
        2
    else if (std.mem.eql(u8, choice_text, "New remote"))
        null
    else
        return error.UnsupportedChoice;

    const allocator = game.backing_allocator;
    if (target_index) |server_index| {
        if (server_index >= game.corp_servers.items.len) return error.UnknownServer;
        var server = &game.corp_servers.items[server_index];
        if (installs_in_ice) {
            try server.ices.append(allocator, card);
        } else {
            try server.content.append(allocator, card);
        }
        try syncOwnedViews(game);
        return;
    }

    var server = MutableServer{
        .name = try std.fmt.allocPrint(game.arena.allocator(), "remote{}", .{nextRemoteIndex(game.corp_servers.items.len)}),
    };
    if (installs_in_ice) {
        try server.ices.append(allocator, card);
    } else {
        try server.content.append(allocator, card);
    }
    try game.corp_servers.append(allocator, server);
    try syncOwnedViews(game);
}

fn installedServerState(
    allocator: std.mem.Allocator,
    server: state.ServerState,
    card: state.CardInstance,
    installs_in_ice: bool,
) !state.ServerState {
    return if (installs_in_ice)
        .{
            .ices = try appendCard(allocator, server.ices, card),
            .content = server.content,
        }
    else
        .{
            .ices = server.ices,
            .content = try appendCard(allocator, server.content, card),
        };
}

fn removeServerContentCard(
    game: *Game,
    server_index: usize,
    content_index: usize,
) state.CardInstance {
    return game.corp_servers.items[server_index].content.orderedRemove(content_index);
}

fn runnableServers(
    allocator: std.mem.Allocator,
    servers: []const state.ServerSlot,
) ![]const []const u8 {
    const remote_count = if (servers.len <= 3) 0 else servers.len - 3;
    const names = try allocator.alloc([]const u8, 3 + remote_count);
    names[0] = try allocator.dupe(u8, "Archives");
    names[1] = try allocator.dupe(u8, "HQ");
    names[2] = try allocator.dupe(u8, "R&D");

    var remote_index: usize = 0;
    while (remote_index < remote_count) : (remote_index += 1) {
        names[3 + remote_index] = try std.fmt.allocPrint(allocator, "Server {}", .{remote_index + 1});
    }
    return names;
}

const ServerLookup = struct {
    index: usize,
    slot: state.ServerSlot,
};

fn findServerByRunPath(
    servers: []const state.ServerSlot,
    run_server: []const []const u8,
) !ServerLookup {
    if (run_server.len == 0) return error.UnsupportedServer;
    if (std.mem.eql(u8, run_server[0], "hq") and servers.len > 0) {
        return .{ .index = 0, .slot = servers[0] };
    }
    if (std.mem.eql(u8, run_server[0], "rnd") and servers.len > 1) {
        return .{ .index = 1, .slot = servers[1] };
    }
    if (std.mem.eql(u8, run_server[0], "archives") and servers.len > 2) {
        return .{ .index = 2, .slot = servers[2] };
    }
    for (servers, 0..) |server, idx| {
        if (std.mem.eql(u8, server.name, run_server[0])) {
            return .{ .index = idx, .slot = server };
        }
    }
    return error.UnknownServer;
}

fn findServerIndexByName(
    servers: []const state.ServerSlot,
    name: []const u8,
) !usize {
    for (servers, 0..) |server, idx| {
        if (std.mem.eql(u8, server.name, name)) return idx;
    }
    return error.UnknownServer;
}

fn canonicalRunServer(
    allocator: std.mem.Allocator,
    server: []const u8,
) ![]const []const u8 {
    const result = try allocator.alloc([]const u8, 1);
    if (std.mem.eql(u8, server, "Archives")) {
        result[0] = try allocator.dupe(u8, "archives");
    } else if (std.mem.eql(u8, server, "HQ")) {
        result[0] = try allocator.dupe(u8, "hq");
    } else if (std.mem.eql(u8, server, "R&D")) {
        result[0] = try allocator.dupe(u8, "rnd");
    } else if (std.mem.startsWith(u8, server, "Server ")) {
        result[0] = try std.fmt.allocPrint(allocator, "remote{s}", .{server["Server ".len..]});
    } else {
        return error.UnsupportedServer;
    }
    return result;
}

fn isCentralRunServer(run_server: []const []const u8) bool {
    if (run_server.len == 0) return false;
    return std.mem.eql(u8, run_server[0], "hq") or
        std.mem.eql(u8, run_server[0], "rnd") or
        std.mem.eql(u8, run_server[0], "archives");
}

fn replaceServerAt(
    allocator: std.mem.Allocator,
    servers: []const state.ServerSlot,
    index: usize,
    next_state: state.ServerState,
) ![]const state.ServerSlot {
    const next_servers = try allocator.alloc(state.ServerSlot, servers.len);
    @memcpy(next_servers, servers);
    next_servers[index] = .{
        .name = servers[index].name,
        .state = next_state,
    };
    return next_servers;
}

fn removeServerAt(
    allocator: std.mem.Allocator,
    servers: []const state.ServerSlot,
    index: usize,
) ![]const state.ServerSlot {
    if (index >= servers.len) return error.UnknownServer;
    const next_servers = try allocator.alloc(state.ServerSlot, servers.len - 1);
    @memcpy(next_servers[0..index], servers[0..index]);
    @memcpy(next_servers[index..], servers[index + 1 ..]);
    return next_servers;
}

fn appendCard(
    allocator: std.mem.Allocator,
    cards: []const state.CardInstance,
    card: state.CardInstance,
) ![]const state.CardInstance {
    const next_cards = try allocator.alloc(state.CardInstance, cards.len + 1);
    @memcpy(next_cards[0..cards.len], cards);
    next_cards[cards.len] = card;
    return next_cards;
}

fn nextRemoteIndex(server_count: usize) usize {
    return if (server_count <= 3) 1 else (server_count - 2);
}

fn otherSide(side: state.Side) state.Side {
    return switch (side) {
        .corp => .runner,
        .runner => .corp,
    };
}

fn nextWord(seed: RngState) struct { seed: RngState, word: u64 } {
    const next_seed = seed +% splitmix_gamma;
    const z1 = (next_seed ^ (next_seed >> 30)) *% splitmix_mul_1;
    const z2 = (z1 ^ (z1 >> 27)) *% splitmix_mul_2;
    return .{
        .seed = next_seed,
        .word = z2 ^ (z2 >> 31),
    };
}

test "action index stepping matches corp opening flow" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        1,
    );
    defer generated.deinit();

    try std.testing.expectEqual(state.Side.corp, currentPlayer(&generated));
    try std.testing.expectEqual(@as(usize, 2), legalActionCount(&generated));

    try applyActionByIndex(&generated, 0);
    try std.testing.expectEqual(state.Side.runner, currentPlayer(&generated));

    try applyActionByIndex(&generated, 0);
    try std.testing.expectEqual(state.Side.corp, currentPlayer(&generated));
    try std.testing.expectEqual(@as(usize, 1), legalActionCount(&generated));

    try applyActionByIndex(&generated, 0);
    try std.testing.expectEqual(state.Side.corp, currentPlayer(&generated));
    try std.testing.expectEqual(@as(usize, 10), legalActionCount(&generated));

    try applyActionByIndex(&generated, 0);
    try std.testing.expectEqual(@as(state.Count, 9), generated.snapshot.state.corp.credit);
    try std.testing.expectEqual(@as(state.TinyCount, 2), generated.snapshot.state.corp.click);
    try std.testing.expectEqual(@as(usize, 8), legalActionCount(&generated));

    var install_generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        1,
    );
    defer install_generated.deinit();

    try applyActionByIndex(&install_generated, 0);
    try applyActionByIndex(&install_generated, 0);
    try applyActionByIndex(&install_generated, 0);
    try applyActionByIndex(&install_generated, 1);
    try std.testing.expectEqual(@as(usize, 4), legalActionCount(&install_generated));

    try applyActionByIndex(&install_generated, 0);
    try std.testing.expectEqual(@as(state.TinyCount, 2), install_generated.snapshot.state.corp.click);
    try std.testing.expectEqual(@as(usize, 8), legalActionCount(&install_generated));
    try expectInstalledIceTitle(install_generated.snapshot.state.corp.servers, "Brân 1.0");
}

fn expectInstalledIceTitle(servers: []const state.ServerSlot, title: []const u8) !void {
    var match_count: usize = 0;
    for (servers) |server| {
        for (server.state.ices) |ice| {
            if (std.mem.eql(u8, ice.title, title)) match_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), match_count);
}
