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
    // Internal mutable state for gameplay logic
    // These ArrayLists contain the source of truth for game state
    corp_hand: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    corp_deck: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    corp_discard: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    corp_scored: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    runner_hand: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    runner_deck: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    runner_discard: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    runner_scored: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    runner_rig_hardware: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    runner_rig_program: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    runner_rig_resources: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    corp_servers: std.ArrayListUnmanaged(MutableServer) = .empty,
    // Snapshot state for parity testing only
    // NOTE: snapshot should only be used for:
    // - Comparing against the Clojure oracle (parity testing)
    // - Generating legal actions
    // - Serializing game state for fixtures
    // Do NOT use snapshot for core gameplay logic as it may contain stale data.
    // Always use the internal ArrayLists above for gameplay state lookups.
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
        self.corp_scored.deinit(self.backing_allocator);
        self.runner_hand.deinit(self.backing_allocator);
        self.runner_deck.deinit(self.backing_allocator);
        self.runner_discard.deinit(self.backing_allocator);
        self.runner_scored.deinit(self.backing_allocator);
        self.runner_rig_hardware.deinit(self.backing_allocator);
        self.runner_rig_program.deinit(self.backing_allocator);
        self.runner_rig_resources.deinit(self.backing_allocator);
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
const prompt_advance_installed = "advance-installed";
const prompt_score_agenda = "score-agenda";
const prompt_access_choice = "access-choice";
const prompt_access_cleanup = "access-cleanup";
const prompt_send_message_rez = "send-message-rez";
const prompt_send_message_rez_score = "send-message-rez-score";
const prompt_predictive_planogram = "predictive-planogram-choice";
const prompt_public_trail = "public-trail-choice";
const prompt_retribution = "retribution-choice";
const prompt_wildcat_strike = "wildcat-strike-choice";
const prompt_run_target = "run-target";
const prompt_run_any_server_basic = "run-any-server-basic";
const prompt_run_central = "run-central";
const prompt_hq_access = "hq-access";
const prompt_rez_window = "rez-window";
const prompt_bran_install_ice = "bran-install-ice";

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

fn runnerContinueActions(allocator: std.mem.Allocator, jack_out_available: bool) ![]const state.LegalAction {
    if (jack_out_available) {
        const actions = try allocator.alloc(state.LegalAction, 2);
        actions[0] = .{ .kind = .@"continue", .side = .runner, .prompt_type = "run" };
        actions[1] = .{ .kind = .jack_out, .side = .runner, .prompt_type = "run", .label = "Jack out" };
        return actions;
    }
    const actions = try allocator.alloc(state.LegalAction, 1);
    actions[0] = .{ .kind = .@"continue", .side = .runner, .prompt_type = "run" };
    return actions;
}
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
    seed: u64,
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
        .jack_out => try applyJackOut(generated, action.side),
        .use_ability => {
            const basic_action = action.basic_action orelse return error.MissingAbilityKind;
            try applyBasicActionAbility(generated, action.side, basic_action);
        },
        .use_installed_ability => {
            const installed_ability = action.installed_ability orelse return error.MissingAbilityKind;
            try applyInstalledAbility(generated, action.side, action.server, action.card_index, installed_ability);
        },
        .install_from_hand => {
            const card_index = action.card_index orelse return error.MissingCardIndex;
            try applyInstallFromHand(generated, action.side, card_index);
        },
        .play_from_hand => {
            const card_index = action.card_index orelse return error.MissingCardIndex;
            try applyPlayFromHand(generated, action.side, card_index);
        },
        .use_subroutine => {
            const subroutine_index = action.choice orelse return error.MissingChoice;
            try applyUseSubroutine(generated, action.side, action.card_index orelse 0, subroutine_index, action);
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
            generated.snapshot.state.runner_successful_run_last_turn = generated.snapshot.state.runner_successful_run_this_turn;
            generated.snapshot.state.runner_successful_run_this_turn = false;

            generated.snapshot.state.active_player = .corp;
            generated.snapshot.state.turn += 1;
            generated.snapshot.state.end_turn = false;
            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try corpOpeningActionsForState(allocator, corp);
        },
        .runner => {
            var runner = &generated.snapshot.state.runner;
            runner.click = runner.click_per_turn;
            resetInstalledAbilityUsage(generated);

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

pub fn init(seed: u64) RngState {
    return seed;
}

pub fn oracleSeed(rng_state: RngState) i64 {
    return @bitCast(rng_state);
}

pub fn fromOracleSeed(seed: i64) RngState {
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

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_advance_installed)) {
        try applyAdvanceInstalledChoice(generated, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_score_agenda)) {
        try applyScoreAgendaChoice(generated, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_access_cleanup) and prompt.source_card != null) {
        try applyAccessCleanupChoice(generated, prompt.source_card.?, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_send_message_rez) and prompt.source_card != null) {
        try applySendMessageRezChoice(generated, prompt.source_card.?, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_send_message_rez_score) and prompt.source_card != null) {
        try applySendMessageScoreRezChoice(generated, prompt.source_card.?, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_rez_window)) {
        try applyRezWindowChoice(generated, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_predictive_planogram)) {
        try applyPredictivePlanogramChoice(generated, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_retribution)) {
        try applyRetributionChoice(generated, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_access_choice) and prompt.source_card != null) {
        try applyAccessPromptChoice(generated, side, prompt.source_card.?, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_public_trail)) {
        try applyPublicTrailChoice(generated, choice_text);
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

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_run_any_server_basic)) {
        try applyRun(generated, .runner, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_run_central)) {
        try applyRun(generated, .runner, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_wildcat_strike)) {
        try applyWildcatStrikeChoice(generated, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, "manegarm-skunkworks-choice")) {
        try applyManegarmSkunkworksChoice(generated, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_bran_install_ice)) {
        try applyBranInstallIceChoice(generated, choice_text);
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
            if (countInstalledCards(corp.servers) == 0) {
                try spendClicks(corp, 1);
                try spendCredits(corp, 1);
            } else {
                try beginAdvanceInstalledPrompt(generated);
                return;
            }
        },
        .score_agenda => {
            try beginScoreAgendaPrompt(generated);
            return;
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
        .run_any_server => {
            try beginRunAnyServerPrompt(generated);
            return;
        },
        else => return error.UnsupportedAbility,
    }

    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try runnerOpeningActionsForState(
        generated.arena.allocator(),
        runner.*,
        generated.snapshot.state.corp.servers,
    );
}

const InstalledTarget = struct {
    server_index: usize,
    is_ice: bool,
    card_index: usize,
};

fn beginAdvanceInstalledPrompt(generated: *Game) !void {
    var corp = &generated.snapshot.state.corp;
    const allocator = generated.arena.allocator();
    const choices = try installedCardChoices(allocator, generated.snapshot.state.corp.servers);
    if (choices.len == 0) return error.UnsupportedAbility;

    corp.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_advance_installed),
        .choices = choices,
        .source_card = null,
    };
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try promptChoiceActions(allocator, .corp, corp.prompt_state.?);
}

fn applyAdvanceInstalledChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    var corp = &generated.snapshot.state.corp;
    const source_card = if (corp.prompt_state) |prompt_state| prompt_state.source_card else null;
    const advancement_amount = if (source_card) |card| card.corp_play.advancement_amount else 1;
    if (advancement_amount == 1) {
        try spendClicks(corp, 1);
        try spendCredits(corp, 1);
    }
    _ = try addAdvancementCounter(generated, choice_text, advancement_amount);
    corp.prompt_state = null;
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), corp);
}

fn beginScoreAgendaPrompt(generated: *Game) !void {
    var corp = &generated.snapshot.state.corp;
    const allocator = generated.arena.allocator();
    const choices = try scoreableAgendaChoices(allocator, generated.snapshot.state.corp.servers);
    if (choices.len == 0) return error.UnsupportedAbility;

    corp.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_score_agenda),
        .choices = choices,
        .source_card = null,
    };
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try promptChoiceActions(allocator, .corp, corp.prompt_state.?);
}

fn applyScoreAgendaChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    var corp = &generated.snapshot.state.corp;
    try spendClicks(corp, 1);

    const target = try parseInstalledTargetChoice(choice_text);
    if (target.is_ice) return error.UnsupportedChoice;
    if (target.server_index < 3) return error.UnsupportedChoice;
    if (target.server_index >= generated.corp_servers.items.len) return error.UnsupportedChoice;

    const server = generated.corp_servers.items[target.server_index];
    if (target.card_index >= server.content.items.len) return error.UnsupportedChoice;
    const agenda = server.content.items[target.card_index];
    const agenda_points = agenda.agenda_points orelse return error.UnsupportedChoice;
    const requirement = agenda.advancement_requirement orelse return error.UnsupportedChoice;
    if (agenda.advancement_counter < requirement) return error.UnsupportedChoice;

    const scored_agenda = removeServerContentCard(generated, target.server_index, @intCast(target.card_index));
    try generated.corp_scored.append(generated.backing_allocator, scored_agenda);
    try removeServerIfEmpty(generated, target.server_index);
    try syncOwnedViews(generated);

    corp.agenda_point += agenda_points;
    // On-score agenda effects
    if (std.mem.eql(u8, scored_agenda.title, "Offworld Office")) {
        generated.snapshot.state.corp.credit += 7;
    } else if (std.mem.eql(u8, scored_agenda.title, "Superconducting Hub")) {
        try drawCards(generated, .corp, 2);
    }

    updateTerminalState(generated);
    if (generated.snapshot.state.game_over) {
        generated.snapshot.state.corp.prompt_state = null;
        return;
    }

    if (std.mem.eql(u8, scored_agenda.title, "Send a Message")) {
        if (try beginSendMessageRezPromptForScore(generated, scored_agenda)) return;
    }

    corp.prompt_state = null;
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), corp);
}

fn beginRunAnyServerPrompt(generated: *Game) !void {
    const runner = &generated.snapshot.state.runner;
    const allocator = generated.arena.allocator();
    const choices = try runTargetChoicesFor(allocator, .any_runnable, generated.snapshot.state.corp.servers);
    if (choices.len == 0) return error.UnsupportedAbility;
    runner.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_run_any_server_basic),
        .choices = choices,
        .source_card = null,
    };
    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try promptChoiceActions(allocator, .runner, runner.prompt_state.?);
}

fn scoreableAgendaChoices(
    allocator: std.mem.Allocator,
    servers: []const state.ServerSlot,
) ![]const state.PromptChoice {
    var count: usize = 0;
    for (servers, 0..) |server, server_index| {
        if (server_index < 3) continue;
        for (server.state.content) |card| {
            if (card.agenda_points == null) continue;
            if (card.advancement_requirement == null) continue;
            if (card.advancement_counter < card.advancement_requirement.?) continue;
            count += 1;
        }
    }
    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    for (servers, 0..) |server, server_index| {
        if (server_index < 3) continue;
        for (server.state.content, 0..) |card, card_index| {
            if (card.agenda_points == null) continue;
            if (card.advancement_requirement == null) continue;
            if (card.advancement_counter < card.advancement_requirement.?) continue;
            const text = try std.fmt.allocPrint(allocator, "{s}|c|{d}", .{ server.name, card_index });
            choices[next] = stringChoice(text);
            next += 1;
        }
    }
    return choices;
}

fn installedCardChoices(
    allocator: std.mem.Allocator,
    servers: []const state.ServerSlot,
) ![]const state.PromptChoice {
    var count: usize = 0;
    for (servers) |server| {
        count += server.state.ices.len + server.state.content.len;
    }
    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    for (servers) |server| {
        for (server.state.ices, 0..) |_, card_index| {
            const text = try std.fmt.allocPrint(allocator, "{s}|i|{d}", .{ server.name, card_index });
            choices[next] = stringChoice(text);
            next += 1;
        }
        for (server.state.content, 0..) |_, card_index| {
            const text = try std.fmt.allocPrint(allocator, "{s}|c|{d}", .{ server.name, card_index });
            choices[next] = stringChoice(text);
            next += 1;
        }
    }
    return choices;
}

fn parseInstalledTargetChoice(choice_text: []const u8) !InstalledTarget {
    var iter = std.mem.splitScalar(u8, choice_text, '|');
    const server_name = iter.next() orelse return error.UnsupportedChoice;
    const zone = iter.next() orelse return error.UnsupportedChoice;
    const index_text = iter.next() orelse return error.UnsupportedChoice;
    const card_index = try std.fmt.parseInt(usize, index_text, 10);
    return .{
        .server_index = findCorpServerIndexByName(server_name) orelse return error.UnsupportedChoice,
        .is_ice = std.mem.eql(u8, zone, "i"),
        .card_index = card_index,
    };
}

fn findCorpServerIndexByName(name: []const u8) ?usize {
    if (std.mem.eql(u8, name, "hq")) return 0;
    if (std.mem.eql(u8, name, "rnd")) return 1;
    if (std.mem.eql(u8, name, "archives")) return 2;
    if (std.mem.startsWith(u8, name, "remote")) {
        const index_text = name["remote".len..];
        const parsed = std.fmt.parseInt(usize, index_text, 10) catch return null;
        return parsed + 2;
    }
    return null;
}

fn displayNameForServer(
    allocator: std.mem.Allocator,
    name: []const u8,
    server_index: usize,
) ![]const u8 {
    _ = server_index;
    if (std.mem.eql(u8, name, "hq")) return allocator.dupe(u8, "HQ");
    if (std.mem.eql(u8, name, "rnd")) return allocator.dupe(u8, "R&D");
    if (std.mem.eql(u8, name, "archives")) return allocator.dupe(u8, "Archives");
    if (std.mem.startsWith(u8, name, "remote")) {
        const index_text = name["remote".len..];
        return std.fmt.allocPrint(allocator, "Server {s}", .{index_text});
    }
    return allocator.dupe(u8, name);
}

fn addAdvancementCounter(
    generated: *Game,
    choice_text: []const u8,
    amount: u8,
) !state.CardInstance {
    const target = try parseInstalledTargetChoice(choice_text);
    if (target.server_index >= generated.corp_servers.items.len) return error.UnsupportedChoice;
    var server = &generated.corp_servers.items[target.server_index];
    if (target.is_ice) {
        if (target.card_index >= server.ices.items.len) return error.UnsupportedChoice;
        var card = &server.ices.items[target.card_index];
        card.advancement_counter += amount;
        try syncOwnedViews(generated);
        return card.*;
    }
    if (target.card_index >= server.content.items.len) return error.UnsupportedChoice;
    var card = &server.content.items[target.card_index];
    card.advancement_counter += amount;
    try syncOwnedViews(generated);
    return card.*;
}

fn removeServerIfEmpty(
    generated: *Game,
    server_index: usize,
) !void {
    if (server_index < 3) return;
    const server = generated.corp_servers.items[server_index];
    if (server.ices.items.len != 0 or server.content.items.len != 0) return;
    var removed_server = generated.corp_servers.orderedRemove(server_index);
    removed_server.ices.deinit(generated.backing_allocator);
    removed_server.content.deinit(generated.backing_allocator);
}

fn updateTerminalState(generated: *Game) void {
    // Check flatline: runner has damage >= hand size
    const runner = &generated.snapshot.state.runner;
    const hand_size = runner.hand_size.total;
    const brain_damage = runner.brain_damage;
    if (brain_damage >= hand_size) {
        generated.snapshot.state.game_over = true;
        generated.snapshot.state.winner = .corp;
        generated.snapshot.state.run = null;
        generated.snapshot.state.corp.prompt_state = null;
        generated.snapshot.state.runner.prompt_state = null;
        generated.snapshot.legal_actions = &.{};
        generated.snapshot.decision_side = .corp;
        return;
    }

    // Check deck-out: corp must draw from empty deck
    if (generated.corp_deck.items.len == 0 and generated.snapshot.state.active_player == .corp and generated.snapshot.state.corp.click > 0) {
        // Corp can't draw - this is checked at draw time, but we flag terminal state if needed
    }

    // Check agenda point victories
    if (generated.snapshot.state.corp.agenda_point >= generated.snapshot.state.corp.agenda_point_req) {
        generated.snapshot.state.game_over = true;
        generated.snapshot.state.winner = .corp;
        generated.snapshot.state.run = null;
        generated.snapshot.state.corp.prompt_state = null;
        generated.snapshot.state.runner.prompt_state = null;
        generated.snapshot.legal_actions = &.{};
        generated.snapshot.decision_side = .corp;
        return;
    }
    if (generated.snapshot.state.runner.agenda_point >= generated.snapshot.state.runner.agenda_point_req) {
        generated.snapshot.state.game_over = true;
        generated.snapshot.state.winner = .runner;
        generated.snapshot.state.run = null;
        generated.snapshot.state.corp.prompt_state = null;
        generated.snapshot.state.runner.prompt_state = null;
        generated.snapshot.legal_actions = &.{};
        generated.snapshot.decision_side = .runner;
    }
}

fn isRunnerTagged(runner: state.PlayerState) bool {
    if (runner.tag) |tag_state| return tag_state.is_tagged or tag_state.total > 0;
    return false;
}

fn runnerHadSuccessfulRunLastTurn(generated: *const Game) bool {
    return generated.snapshot.state.runner_successful_run_last_turn;
}

fn predictivePlanogramChoices(
    allocator: std.mem.Allocator,
    runner: state.PlayerState,
) ![]const state.PromptChoice {
    const tagged = isRunnerTagged(runner);
    const count: usize = if (tagged) 3 else 2;
    const choices = try allocator.alloc(state.PromptChoice, count);
    choices[0] = stringChoice("Gain 3 [Credits]");
    choices[1] = stringChoice("Draw 3 cards");
    if (tagged) choices[2] = stringChoice("Gain 3 [Credits] and draw 3 cards");
    return choices;
}

fn applyPredictivePlanogramChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    var corp = &generated.snapshot.state.corp;
    if (std.mem.eql(u8, choice_text, "Gain 3 [Credits]")) {
        corp.credit += 3;
    } else if (std.mem.eql(u8, choice_text, "Draw 3 cards")) {
        try drawCards(generated, .corp, 3);
    } else if (std.mem.eql(u8, choice_text, "Gain 3 [Credits] and draw 3 cards")) {
        corp.credit += 3;
        try drawCards(generated, .corp, 3);
    } else return error.UnsupportedChoice;

    corp.prompt_state = null;
    generated.snapshot.state.runner.prompt_state = null;
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), corp);
}

fn publicTrailChoices(
    allocator: std.mem.Allocator,
    runner_credit: u16,
) ![]const state.PromptChoice {
    const count: usize = if (runner_credit >= 8) 2 else 1;
    const choices = try allocator.alloc(state.PromptChoice, count);
    choices[0] = stringChoice("Take 1 tag");
    if (runner_credit >= 8) choices[1] = stringChoice("Pay 8 [Credits]");
    return choices;
}

fn applyPublicTrailChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    const runner = &generated.snapshot.state.runner;
    if (std.mem.eql(u8, choice_text, "Take 1 tag")) {
        if (runner.tag == null) {
            runner.tag = .{ .base = 0, .total = 1, .is_tagged = true };
        } else {
            runner.tag.?.total += 1;
            runner.tag.?.is_tagged = runner.tag.?.total > 0;
        }
    } else if (std.mem.eql(u8, choice_text, "Pay 8 [Credits]")) {
        try spendCredits(runner, 8);
    } else return error.UnsupportedChoice;

    generated.snapshot.state.runner.prompt_state = null;
    generated.snapshot.state.corp.prompt_state = null;
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated.snapshot.state.corp);
}

fn retributionChoices(
    allocator: std.mem.Allocator,
    runner: state.PlayerState,
) ![]const state.PromptChoice {
    const count = runner.rig_hardware.len + runner.rig_program.len;
    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    for (runner.rig_hardware, 0..) |_, idx| {
        const text = try std.fmt.allocPrint(allocator, "h|{d}", .{idx});
        choices[next] = stringChoice(text);
        next += 1;
    }
    for (runner.rig_program, 0..) |_, idx| {
        const text = try std.fmt.allocPrint(allocator, "p|{d}", .{idx});
        choices[next] = stringChoice(text);
        next += 1;
    }
    return choices;
}

fn applyRetributionChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    var pieces = std.mem.splitScalar(u8, choice_text, '|');
    const zone = pieces.next() orelse return error.UnsupportedChoice;
    const index_text = pieces.next() orelse return error.UnsupportedChoice;
    const index = try std.fmt.parseInt(usize, index_text, 10);

    if (std.mem.eql(u8, zone, "h")) {
        if (index >= generated.runner_rig_hardware.items.len) return error.UnsupportedChoice;
        const trashed = generated.runner_rig_hardware.orderedRemove(index);
        try generated.runner_discard.append(generated.backing_allocator, trashed);
    } else if (std.mem.eql(u8, zone, "p")) {
        if (index >= generated.runner_rig_program.items.len) return error.UnsupportedChoice;
        const trashed = generated.runner_rig_program.orderedRemove(index);
        try generated.runner_discard.append(generated.backing_allocator, trashed);
    } else return error.UnsupportedChoice;

    generated.snapshot.state.corp.prompt_state = null;
    generated.snapshot.decision_side = .corp;
    try syncOwnedViews(generated);
    generated.snapshot.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated.snapshot.state.corp);
}

fn playRunnerMutualFavor(
    generated: *Game,
    card_index: u8,
    card: state.CardInstance,
) !void {
    const runner = &generated.snapshot.state.runner;
    try spendClicks(runner, 1);
    try spendCredits(runner, card.cost orelse 0);
    _ = try removeCardFromHand(generated, .runner, card_index);
    try appendDiscardCard(generated, .runner, card);

    const deck = &generated.runner_deck;
    var target_index: ?usize = null;
    for (deck.items, 0..) |candidate, idx| {
        if (isIcebreaker(candidate)) {
            target_index = idx;
            break;
        }
    }
    if (target_index) |idx| {
        const chosen = deck.orderedRemove(idx);
        try generated.runner_hand.append(generated.backing_allocator, chosen);
        try shuffleDeck(generated, .runner);
    }

    try syncOwnedViews(generated);
    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try runnerOpeningActionsForState(
        generated.arena.allocator(),
        runner.*,
        generated.snapshot.state.corp.servers,
    );
}

fn hasSubtype(card: state.CardInstance, subtype: []const u8) bool {
    for (card.subtypes) |s| {
        if (std.mem.eql(u8, s, subtype)) return true;
    }
    return false;
}

fn isIcebreaker(card: state.CardInstance) bool {
    return hasSubtype(card, "Icebreaker");
}

fn playRunnerWildcatStrike(
    generated: *Game,
    card_index: u8,
    card: state.CardInstance,
) !void {
    const runner = &generated.snapshot.state.runner;
    try spendClicks(runner, 1);
    try spendCredits(runner, card.cost orelse 0);
    _ = try removeCardFromHand(generated, .runner, card_index);
    try appendDiscardCard(generated, .runner, card);

    generated.snapshot.state.runner.prompt_state = .{
        .prompt_type = try generated.arena.allocator().dupe(u8, "waiting"),
        .choices = &.{},
        .source_card = null,
    };
    generated.snapshot.state.corp.prompt_state = .{
        .prompt_type = try generated.arena.allocator().dupe(u8, prompt_wildcat_strike),
        .choices = try wildcatStrikeChoices(generated.arena.allocator()),
        .source_card = card,
    };
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try promptChoiceActions(
        generated.arena.allocator(),
        .corp,
        generated.snapshot.state.corp.prompt_state.?,
    );
}

fn wildcatStrikeChoices(allocator: std.mem.Allocator) ![]const state.PromptChoice {
    const choices = try allocator.alloc(state.PromptChoice, 2);
    choices[0] = stringChoice("Runner gains 6 [Credits]");
    choices[1] = stringChoice("Runner draws 4 cards");
    return choices;
}

fn applyWildcatStrikeChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    var runner = &generated.snapshot.state.runner;
    if (std.mem.eql(u8, choice_text, "Runner gains 6 [Credits]")) {
        runner.credit += 6;
    } else if (std.mem.eql(u8, choice_text, "Runner draws 4 cards")) {
        try drawCards(generated, .runner, 4);
    } else return error.UnsupportedChoice;

    generated.snapshot.state.corp.prompt_state = null;
    generated.snapshot.state.runner.prompt_state = null;
    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try runnerOpeningActionsForState(
        generated.arena.allocator(),
        runner.*,
        generated.snapshot.state.corp.servers,
    );
}

fn applyManegarmSkunkworksChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    const allocator = generated.arena.allocator();
    var runner = &generated.snapshot.state.runner;
    var run = &generated.snapshot.state.run.?;

    if (std.mem.eql(u8, choice_text, "Spend [Click][Click]")) {
        runner.click -= 2;
    } else if (std.mem.eql(u8, choice_text, "Pay 5 [Credits]")) {
        runner.credit -= 5;
    } else if (std.mem.eql(u8, choice_text, "End the run")) {
        try completeUnsuccessfulRun(generated);
        return;
    } else return error.UnsupportedChoice;

    runner.prompt_state = null;
    try applySuccessfulRunEffects(generated);
    if (try prepareNextAccess(generated)) {
        run.phase = try allocator.dupe(u8, "success");
        generated.snapshot.decision_side = .corp;
        generated.snapshot.legal_actions = try continueActionsForRun(allocator, .corp, run.*);
        return;
    }
    try completeSuccessfulRunWithCorpPriority(generated);
}

fn applyPlayFromHand(
    generated: *Game,
    side: state.Side,
    card_index: u8,
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
    card_index: u8,
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
    var installed = pending_install.card;
    installed.credit_counter = installed.installed_ability.initial_credit_counters;
    installed.ability_used_this_turn = false;
    try installCard(generated, installed, choice_text);

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
        .urtica_cipher => return error.UnsupportedAccessTarget,
        .manegarm_skunkworks => return error.UnsupportedAccessTarget,
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

    const runner = &generated.snapshot.state.runner;
    runner.agenda_point += accessed.agenda_points orelse return error.MissingAgendaPoints;
    try removeAccessedCard(generated, run);

    // TODO: Generalize stolen agenda effects
    if (std.mem.eql(u8, accessed.title, "Send a Message")) {
        if (try beginSendMessageRezPrompt(generated, accessed)) return;
    }

    const is_central = isCentralRunServer(run.server);
    if (is_central) {
        try continueOrCompleteAfterSteal(generated, true);
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

fn beginSendMessageRezPrompt(
    generated: *Game,
    accessed: state.CardInstance,
) !bool {
    const allocator = generated.arena.allocator();
    const choices = try sendMessageRezChoices(allocator, generated.snapshot.state.corp.servers);
    if (choices.len == 0) return false;

    generated.snapshot.state.runner.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "waiting"),
        .choices = &.{},
        .source_card = null,
    };
    generated.snapshot.state.corp.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_send_message_rez),
        .choices = choices,
        .source_card = accessed,
    };
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try promptChoiceActions(
        allocator,
        .corp,
        generated.snapshot.state.corp.prompt_state.?,
    );
    return true;
}

fn beginSendMessageRezPromptForScore(
    generated: *Game,
    scored_agenda: state.CardInstance,
) !bool {
    const allocator = generated.arena.allocator();
    const choices = try sendMessageRezChoices(allocator, generated.snapshot.state.corp.servers);
    if (choices.len == 0) return false;

    generated.snapshot.state.corp.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_send_message_rez_score),
        .choices = choices,
        .source_card = scored_agenda,
    };
    generated.snapshot.state.runner.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "waiting"),
        .choices = &.{},
        .source_card = null,
    };
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try promptChoiceActions(
        allocator,
        .corp,
        generated.snapshot.state.corp.prompt_state.?,
    );
    return true;
}

fn applySendMessageRezChoice(
    generated: *Game,
    accessed: state.CardInstance,
    choice_text: []const u8,
) !void {
    // TODO: This is specific to "Send a Message" - need general on-score/stolen effect framework
    if (!std.mem.eql(u8, accessed.title, "Send a Message")) return error.UnsupportedPrompt;
    if (!try rezInstalledIceByTitle(generated, choice_text)) return error.UnsupportedChoice;
    try continueOrCompleteAfterSteal(generated, false);
}

fn applySendMessageScoreRezChoice(
    generated: *Game,
    scored_agenda: state.CardInstance,
    choice_text: []const u8,
) !void {
    // TODO: This is specific to "Send a Message" - need general on-score effect framework
    if (!std.mem.eql(u8, scored_agenda.title, "Send a Message")) return error.UnsupportedPrompt;
    if (!try rezInstalledIceByTitle(generated, choice_text)) return error.UnsupportedChoice;
    generated.snapshot.state.corp.prompt_state = null;
    generated.snapshot.state.runner.prompt_state = null;
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated.snapshot.state.corp);
}

fn continueOrCompleteAfterSteal(
    generated: *Game,
    is_central: bool,
) !void {
    updateTerminalState(generated);
    if (generated.snapshot.state.game_over) return;

    const allocator = generated.arena.allocator();
    if (is_central) {
        generated.snapshot.state.runner.prompt_state = null;
        generated.snapshot.state.corp.prompt_state = null;
        generated.snapshot.state.run.?.no_action = null;
        if (generated.snapshot.state.run.?.accesses_remaining > 0) {
            generated.snapshot.state.run.?.phase = try allocator.dupe(u8, "success");
            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try continueActionsForRun(allocator, .corp, generated.snapshot.state.run);
            return;
        }
        try completeRunWithoutAccess(generated);
        return;
    }
    try completeRunWithoutAccess(generated);
}

fn sendMessageRezChoices(
    allocator: std.mem.Allocator,
    servers: []const state.ServerSlot,
) ![]const state.PromptChoice {
    var count: usize = 0;
    for (servers) |server| {
        for (server.state.ices) |ice| {
            if (!ice.rezzed) count += 1;
        }
    }
    if (count == 0) return try allocator.alloc(state.PromptChoice, 0);

    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    for (servers) |server| {
        for (server.state.ices) |ice| {
            if (ice.rezzed) continue;
            choices[next] = stringChoice(ice.title);
            next += 1;
        }
    }
    return choices;
}

fn rezInstalledIceByTitle(
    generated: *Game,
    title: []const u8,
) !bool {
    for (generated.corp_servers.items) |*server| {
        for (server.ices.items) |*ice| {
            if (ice.rezzed) continue;
            if (!std.mem.eql(u8, ice.title, title)) continue;
            ice.rezzed = true;
            try syncOwnedViews(generated);
            return true;
        }
    }
    return false;
}

fn applyJackOut(
    generated: *Game,
    side: state.Side,
) !void {
    if (side != .runner) return error.UnsupportedSide;
    const run = generated.snapshot.state.run orelse return error.NoRunInProgress;
    if (!run.jack_out_available) return error.JackOutNotAvailable;

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

fn applyUseSubroutine(
    generated: *Game,
    side: state.Side,
    card_index: u8,
    subroutine_index: state.PromptChoice,
    action: state.LegalAction,
) !void {
    _ = side;
    _ = card_index;

    // Get the current run and ICE
    const run = generated.snapshot.state.run orelse return error.NoRunInProgress;
    const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;

    // Find the current ICE in the server using internal corp_servers
    const target_server = try findMutableServerByRunPath(generated.corp_servers.items, run.server);
    const server_index = target_server.index;
    if (server_index >= generated.corp_servers.items.len) return error.InvalidServer;
    const server = &generated.corp_servers.items[server_index];

    // Calculate actual ice index (position from the end)
    const ice_count = server.ices.items.len;
    if (current_ice_idx >= ice_count) return error.InvalidIceIndex;
    const actual_ice_idx = ice_count - 1 - current_ice_idx;

    var ice = &server.ices.items[actual_ice_idx];

    // Check if this is a bioroid ability (action.card_title matches ICE title)
    const is_bioroid_ability = action.card_title != null and
        std.mem.eql(u8, action.card_title.?, ice.title);

    if (is_bioroid_ability) {
        // Find the bioroid ability on the ICE
        var found_ability: ?state.RunnerAbilitySpec = null;
        for (ice.runner_abilities) |ability| {
            if (ability.kind == .bioroid_break) {
                found_ability = ability;
                break;
            }
        }
        const ability = found_ability orelse return error.NoBioroidAbility;

        // Check if runner has enough clicks
        const runner = &generated.snapshot.state.runner;
        if (runner.click < ability.click_cost) return error.InsufficientClicks;

        // Spend clicks
        runner.click -= ability.click_cost;

        // Break subroutines (up to break_quantity, or fewer if not enough unbroken subs)
        const break_qty = ability.break_quantity;
        var broken_count: u8 = 0;
        for (ice.subroutines, 0..) |_, sub_idx| {
            if (broken_count >= break_qty) break;
            const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(sub_idx))) != 0;
            if (!is_broken) {
                ice.broken_subroutines |= (@as(u16, 1) << @as(u4, @intCast(sub_idx)));
                broken_count += 1;
            }
        }
    } else {
        // Icebreaker break logic
        // Find the icebreaker in the runner's rig_program
        if (action.card_title) |title| {
            var found_icebreaker: ?usize = null;
            for (generated.runner_rig_program.items, 0..) |card, idx| {
                if (std.mem.eql(u8, card.title, title)) {
                    found_icebreaker = idx;
                    break;
                }
            }
            const icebreaker_idx = found_icebreaker orelse return error.NotAnIcebreaker;
            const icebreaker = generated.runner_rig_program.items[icebreaker_idx];

            // Check if it's actually an icebreaker with break ability
            if (!isIcebreaker(icebreaker)) return error.NotAnIcebreaker;
            if (icebreaker.installed_ability.kind != .break_subroutine) return error.UnsupportedAbility;

            // Check which subroutine to break based on subroutine_index
            const sub_idx: u8 = switch (subroutine_index.kind) {
                .number => @intCast(subroutine_index.number orelse return error.InvalidSubroutine),
                else => return error.InvalidSubroutine,
            };

            if (sub_idx >= ice.subroutines.len) return error.InvalidSubroutine;

            // Check if we have enough credits
            const runner = &generated.snapshot.state.runner;
            if (runner.credit < icebreaker.installed_ability.credit_cost) return error.InsufficientCredits;

            // Spend credits
            runner.credit -= icebreaker.installed_ability.credit_cost;

            // Mark subroutine as broken
            ice.broken_subroutines |= (@as(u16, 1) << @as(u4, @intCast(sub_idx)));
        } else {
            return error.NotAnIcebreaker;
        }
    }

    try syncOwnedViews(generated);

    // Generate new legal actions - still in encounter, can break more or continue
    const allocator = generated.arena.allocator();
    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try encounterActionsForState(allocator, generated, ice.*);
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
            try completeRunAfterAccess(generated);
        },
        .urtica_cipher => return error.UnsupportedChoice,
        .manegarm_skunkworks => return error.UnsupportedChoice,
        .none => return error.UnsupportedChoice,
    }
}

fn playCorpOperation(
    generated: *Game,
    card_index: u8,
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
        .advance_installed => {
            if (countInstalledCards(generated.snapshot.state.corp.servers) == 0) {
                generated.snapshot.decision_side = .corp;
                generated.snapshot.legal_actions = try corpOpeningActionsForState(allocator, corp);
                return;
            }
            corp.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, prompt_advance_installed),
                .choices = try installedCardChoices(allocator, generated.snapshot.state.corp.servers),
                .source_card = card,
            };
            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try promptChoiceActions(allocator, .corp, corp.prompt_state.?);
            return;
        },
        .predictive_planogram => {
            corp.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, prompt_predictive_planogram),
                .choices = try predictivePlanogramChoices(allocator, generated.snapshot.state.runner),
                .source_card = card,
            };
            generated.snapshot.state.runner.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, "waiting"),
                .choices = &.{},
                .source_card = null,
            };
            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try promptChoiceActions(allocator, .corp, corp.prompt_state.?);
            return;
        },
        .public_trail => {
            if (!runnerHadSuccessfulRunLastTurn(generated)) {
                generated.snapshot.decision_side = .corp;
                generated.snapshot.legal_actions = try corpOpeningActionsForState(allocator, corp);
                return;
            }
            generated.snapshot.state.corp.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, "waiting"),
                .choices = &.{},
                .source_card = null,
            };
            generated.snapshot.state.runner.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, prompt_public_trail),
                .choices = try publicTrailChoices(allocator, generated.snapshot.state.runner.credit),
                .source_card = card,
            };
            generated.snapshot.decision_side = .runner;
            generated.snapshot.legal_actions = try promptChoiceActions(allocator, .runner, generated.snapshot.state.runner.prompt_state.?);
            return;
        },
        .retribution => {
            if (!isRunnerTagged(generated.snapshot.state.runner)) {
                generated.snapshot.decision_side = .corp;
                generated.snapshot.legal_actions = try corpOpeningActionsForState(allocator, corp);
                return;
            }
            const choices = try retributionChoices(allocator, generated.snapshot.state.runner);
            if (choices.len == 0) {
                generated.snapshot.decision_side = .corp;
                generated.snapshot.legal_actions = try corpOpeningActionsForState(allocator, corp);
                return;
            }
            corp.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, prompt_retribution),
                .choices = choices,
                .source_card = card,
            };
            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try promptChoiceActions(allocator, .corp, corp.prompt_state.?);
            return;
        },
        .no_op => {},
        .none => return error.UnsupportedOperation,
    }

    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(allocator, corp);
}

fn applyRunnerPlayFromHand(
    generated: *Game,
    card_index: u8,
) !void {
    const runner = &generated.snapshot.state.runner;
    if (card_index >= runner.hand.len) return error.InvalidCardIndex;

    const card = runner.hand[card_index];
    if (card.runner_install.kind != .none) return applyInstallFromHand(generated, .runner, card_index);

    const card_type = card.card_type orelse return error.MissingCardType;
    if (!std.mem.eql(u8, card_type, "Event")) return error.UnsupportedCardType;

    switch (card.runner_play.kind) {
        .gain_credits => try playRunnerGainCredits(generated, card_index, card),
        .choose_run_target => try playRunnerChooseRunTarget(generated, card_index, card),
        .mutual_favor => try playRunnerMutualFavor(generated, card_index, card),
        .wildcat_strike => try playRunnerWildcatStrike(generated, card_index, card),
        .none => return error.UnsupportedCardType,
    }
}

fn applyInstallFromHand(
    generated: *Game,
    side: state.Side,
    card_index: u8,
) !void {
    if (generated.snapshot.state.end_turn) return error.TurnNotStarted;
    if (generated.snapshot.state.active_player != side) return error.NotActivePlayer;
    if (side != .runner) return error.UnsupportedSide;

    const allocator = generated.arena.allocator();
    const runner = &generated.snapshot.state.runner;
    if (card_index >= runner.hand.len) return error.InvalidCardIndex;

    const card = runner.hand[card_index];
    if (card.runner_install.kind == .none) return error.UnsupportedRunnerInstall;

    try spendClicks(runner, 1);
    try spendCredits(runner, card.cost orelse 0);

    var installed_card = try removeCardFromHand(generated, .runner, card_index);
    installed_card.credit_counter = installed_card.installed_ability.initial_credit_counters;
    installed_card.ability_used_this_turn = false;
    try appendRunnerInstalledCard(generated, installed_card);

    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try runnerOpeningActionsForState(
        allocator,
        runner.*,
        generated.snapshot.state.corp.servers,
    );
}

fn playRunnerGainCredits(
    generated: *Game,
    card_index: u8,
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
    card_index: u8,
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
    const initial_position: u8 = if (isCentralRunServer(run_server))
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
        .encounter_phase = .none,
        .current_ice_index = null,
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
        .jack_out_available = false,
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
    const initial_position: u8 = if (isCentralRunServer(run_server))
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
        .encounter_phase = .none,
        .current_ice_index = null,
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
        .jack_out_available = false,
    };
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try continueActions(allocator, .corp);
}

fn applyInstalledAbility(
    generated: *Game,
    side: state.Side,
    server_name: ?[]const u8,
    card_index_opt: ?u8,
    installed_ability: state.InstalledAbilityKind,
) !void {
    if (generated.snapshot.state.end_turn) return error.TurnNotStarted;
    if (generated.snapshot.state.active_player != side) return error.NotActivePlayer;
    const allocator = generated.arena.allocator();
    const card_index = card_index_opt orelse return error.MissingCardIndex;

    switch (side) {
        .runner => {
            var runner = &generated.snapshot.state.runner;

            // Determine which rig zone to look in based on card type
            var card: *state.CardInstance = undefined;
            var rig_zone: enum { resources, programs, hardware } = undefined;

            if (card_index < generated.runner_rig_resources.items.len) {
                card = &generated.runner_rig_resources.items[card_index];
                rig_zone = .resources;
            } else if (card_index < generated.runner_rig_resources.items.len + generated.runner_rig_program.items.len) {
                const program_index = card_index - @as(u8, @intCast(generated.runner_rig_resources.items.len));
                card = &generated.runner_rig_program.items[program_index];
                rig_zone = .programs;
            } else if (card_index < generated.runner_rig_resources.items.len + generated.runner_rig_program.items.len + generated.runner_rig_hardware.items.len) {
                const hardware_index = card_index - @as(u8, @intCast(generated.runner_rig_resources.items.len + generated.runner_rig_program.items.len));
                card = &generated.runner_rig_hardware.items[hardware_index];
                rig_zone = .hardware;
            } else {
                return error.InvalidCardIndex;
            }

            if (card.installed_ability.kind != installed_ability) return error.UnsupportedAbility;
            if (card.installed_ability.once_per_turn and card.ability_used_this_turn) return error.AbilityAlreadyUsed;

            switch (installed_ability) {
                .take_credits => {
                    try spendClicks(runner, card.installed_ability.click_cost);
                    const amount = @min(card.credit_counter, card.installed_ability.take_credits_amount);
                    runner.credit += amount;
                    card.credit_counter -= amount;
                    card.ability_used_this_turn = true;

                    if (card.installed_ability.trash_on_empty and card.credit_counter == 0) {
                        switch (rig_zone) {
                            .resources => {
                                const trashed = generated.runner_rig_resources.orderedRemove(card_index);
                                try appendDiscardCard(generated, .runner, trashed);
                            },
                            .programs => {
                                const program_index = card_index - @as(u8, @intCast(generated.runner_rig_resources.items.len));
                                const trashed = generated.runner_rig_program.orderedRemove(program_index);
                                try appendDiscardCard(generated, .runner, trashed);
                            },
                            .hardware => {
                                const hardware_index = card_index - @as(u8, @intCast(generated.runner_rig_resources.items.len + generated.runner_rig_program.items.len));
                                const trashed = generated.runner_rig_hardware.orderedRemove(hardware_index);
                                try appendDiscardCard(generated, .runner, trashed);
                            },
                        }
                    } else {
                        try syncOwnedViews(generated);
                    }
                },
                .place_credits => {
                    try spendClicks(runner, card.installed_ability.click_cost);
                    card.credit_counter += card.installed_ability.place_credits_amount;
                    card.ability_used_this_turn = true;
                    try syncOwnedViews(generated);
                },
                .break_subroutine, .pump_strength => {
                    return error.UnsupportedAbility;
                },
                .run_central => {
                    try spendClicks(runner, card.installed_ability.click_cost);
                    card.ability_used_this_turn = true;
                    try syncOwnedViews(generated);
                    // Open central server choice prompt
                    const choices = try runTargetChoicesFor(allocator, .central_only, generated.snapshot.state.corp.servers);
                    runner.prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, prompt_run_central),
                        .choices = choices,
                        .source_card = card.*,
                    };
                    generated.snapshot.decision_side = .runner;
                    generated.snapshot.legal_actions = try promptChoiceActions(allocator, .runner, runner.prompt_state.?);
                    return;
                },
                .none => return error.UnsupportedAbility,
            }

            generated.snapshot.decision_side = .runner;
            generated.snapshot.legal_actions = try runnerOpeningActionsForState(
                allocator,
                runner.*,
                generated.snapshot.state.corp.servers,
            );
        },
        .corp => {
            const server_display = server_name orelse return error.MissingServer;
            const server_index = try findServerIndexByDisplayName(generated.snapshot.state.corp.servers, server_display);
            if (server_index >= generated.corp_servers.items.len) return error.UnknownServer;
            if (card_index >= generated.corp_servers.items[server_index].content.items.len) return error.InvalidCardIndex;
            var corp = &generated.snapshot.state.corp;
            var card = &generated.corp_servers.items[server_index].content.items[card_index];
            if (card.installed_ability.kind != installed_ability) return error.UnsupportedAbility;
            if (card.installed_ability.once_per_turn and card.ability_used_this_turn) return error.AbilityAlreadyUsed;

            switch (installed_ability) {
                .take_credits => {
                    try spendClicks(corp, card.installed_ability.click_cost);
                    const amount = @min(card.credit_counter, card.installed_ability.take_credits_amount);
                    corp.credit += amount;
                    card.credit_counter -= amount;
                    card.ability_used_this_turn = true;

                    if (card.installed_ability.trash_on_empty and card.credit_counter == 0) {
                        const trashed = generated.corp_servers.items[server_index].content.orderedRemove(card_index);
                        try appendDiscardCard(generated, .corp, trashed);
                    } else {
                        try syncOwnedViews(generated);
                    }
                },
                .place_credits, .break_subroutine, .pump_strength, .run_central => return error.UnsupportedAbility,
                .none => return error.UnsupportedAbility,
            }

            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try corpOpeningActionsForState(allocator, corp);
        },
    }
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

    // Handle movement phase jack-out window
    if (std.mem.eql(u8, run.*.?.phase, "movement") and run.*.?.jack_out_available) {
        if (run.*.?.no_action == null) {
            // First pass - if runner, they had chance to jack out
            // Now corp gets to pass
            run.*.?.no_action = side;
            generated.snapshot.decision_side = otherSide(side);
            generated.snapshot.legal_actions = try continueActionsForRun(allocator, otherSide(side), run.*);
            return;
        }
        // Both players passed on jack-out - clear flag and continue
        run.*.?.no_action = null;
        return try advanceMovementPhase(generated);
    }

    if (run.*.?.no_action == null) {
        if (side == .corp and std.mem.eql(u8, run.*.?.phase, "approach-ice")) {
            if (try maybeOpenRezWindowPrompt(generated)) return;
        }
        run.*.?.no_action = side;
        generated.snapshot.decision_side = otherSide(side);
        generated.snapshot.legal_actions = try continueActionsForRun(allocator, otherSide(side), run.*);
        return;
    }

    if (run.*.?.no_action.? == side) return error.InvalidAction;

    run.*.?.no_action = null;
    if (std.mem.eql(u8, run.*.?.phase, "initiation")) return try advanceInitiationPhase(generated);
    if (std.mem.eql(u8, run.*.?.phase, "approach-ice")) return try advanceApproachIcePhase(generated);
    if (std.mem.eql(u8, run.*.?.phase, "movement")) return try advanceMovementPhase(generated);

    return error.UnsupportedRunPhase;
}

fn maybeOpenRezWindowPrompt(generated: *Game) !bool {
    if (generated.snapshot.state.corp.prompt_state) |prompt_state| {
        if (!std.mem.eql(u8, prompt_state.prompt_type, "run")) {
            return false;
        }
    } else {
        return false;
    }
    if (generated.snapshot.state.run == null) {
        return false;
    }
    const target = try currentApproachedIce(generated) orelse {
        return false;
    };
    if (target.ice.rezzed) {
        return false;
    }
    if (generated.snapshot.state.corp.credit < (target.ice.cost orelse 0)) {
        return false;
    }

    generated.snapshot.state.corp.prompt_state = .{
        .prompt_type = try generated.arena.allocator().dupe(u8, prompt_rez_window),
        .choices = try rezWindowChoices(generated.arena.allocator()),
        .source_card = target.ice,
    };
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try promptChoiceActions(
        generated.arena.allocator(),
        .corp,
        generated.snapshot.state.corp.prompt_state.?,
    );
    return true;
}

fn rezWindowChoices(allocator: std.mem.Allocator) ![]const state.PromptChoice {
    const choices = try allocator.alloc(state.PromptChoice, 2);
    choices[0] = stringChoice("Rez approached ice");
    choices[1] = stringChoice("No rez");
    return choices;
}

fn applyRezWindowChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    if (std.mem.eql(u8, choice_text, "Rez approached ice")) {
        const target = (try currentApproachedIce(generated)) orelse return error.UnsupportedChoice;
        if (target.ice.rezzed) return error.UnsupportedChoice;
        const rez_cost = target.ice.cost orelse 0;
        const run = generated.snapshot.state.run orelse return error.NoRunInProgress;
        const adjusted_cost = rez_cost + run.rez_cost_bonus;
        try spendCredits(&generated.snapshot.state.corp, adjusted_cost);
        generated.corp_servers.items[target.server_index].ices.items[target.ice_index].rezzed = true;
        try syncOwnedViews(generated);
    } else if (!std.mem.eql(u8, choice_text, "No rez")) {
        return error.UnsupportedChoice;
    }

    // Restore "run" prompt state (run is still in progress)
    const allocator = generated.arena.allocator();
    generated.snapshot.state.corp.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    const run = &generated.snapshot.state.run;
    if (run.* == null) return error.NoRunInProgress;
    run.*.?.no_action = .corp;
    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
}

const ApproachedIceTarget = struct {
    server_index: usize,
    ice_index: usize,
    ice: state.CardInstance,
};

// Find approached ice using internal mutable state, not snapshot
// This avoids stale data issues from syncOwnedViews
fn currentApproachedIceInternal(generated: *const Game) !?ApproachedIceTarget {
    const run = generated.snapshot.state.run orelse return null;
    if (!std.mem.eql(u8, run.phase, "approach-ice")) return null;
    if (run.position == 0) return null;

    const target_server = try findMutableServerByRunPath(generated.corp_servers.items, run.server);
    const ice_index = @as(usize, run.position) - 1;
    if (ice_index >= target_server.server.ices.items.len) return null;
    const ice = target_server.server.ices.items[ice_index];
    return .{
        .server_index = target_server.index,
        .ice_index = ice_index,
        .ice = ice,
    };
}

const MutableServerLookup = struct {
    index: usize,
    server: MutableServer,
};

// Find server by run path using internal MutableServer state
// NOTE: This uses the internal corp_servers ArrayList, not the snapshot.
// The snapshot's server data may be stale due to arena allocation patterns.
// Use this for all gameplay logic; use snapshot only for parity testing.
fn findMutableServerByRunPath(
    servers: []const MutableServer,
    run_server: []const []const u8,
) !MutableServerLookup {
    if (run_server.len == 0) return error.UnsupportedServer;
    if (std.mem.eql(u8, run_server[0], "hq") and servers.len > 0) {
        return .{ .index = 0, .server = servers[0] };
    }
    if (std.mem.eql(u8, run_server[0], "rnd") and servers.len > 1) {
        return .{ .index = 1, .server = servers[1] };
    }
    if (std.mem.eql(u8, run_server[0], "archives") and servers.len > 2) {
        return .{ .index = 2, .server = servers[2] };
    }
    for (servers, 0..) |server, idx| {
        if (std.mem.eql(u8, server.name, run_server[0])) {
            return .{ .index = idx, .server = server };
        }
    }
    return error.UnknownServer;
}

// Find approached ice using internal mutable state
// IMPORTANT: Uses generated.corp_servers (internal state) instead of snapshot.state.corp.servers
// to avoid stale data issues from syncOwnedViews. The snapshot may contain outdated pointers
// after arena reallocations. Always use internal state for gameplay logic.
fn currentApproachedIce(generated: *const Game) !?ApproachedIceTarget {
    return currentApproachedIceInternal(generated);
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
        generated.snapshot.legal_actions = try continueActionsForRun(allocator, otherSide(side), run.*);
        return;
    }

    if (run.no_action.? == side) return error.InvalidAction;
    run.no_action = null;
    if (try prepareNextAccess(generated)) {
        run.phase = try allocator.dupe(u8, "success");
        generated.snapshot.decision_side = .corp;
        generated.snapshot.legal_actions = try continueActionsForRun(allocator, .corp, run.*);
        return;
    }
    try completeRunWithoutAccess(generated);
}

fn advanceInitiationPhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.snapshot.state.run.?;
    if (run.position == 0) {
        run.phase = try allocator.dupe(u8, "movement");
        run.jack_out_available = false;
    } else {
        run.phase = try allocator.dupe(u8, "approach-ice");
        run.jack_out_available = false;
    }
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try continueActionsForRun(allocator, .corp, run.*);
}

fn advanceApproachIcePhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.snapshot.state.run.?;

    // Check if there's approached ice to encounter
    if (try currentApproachedIce(generated)) |target| {
        if (target.ice.rezzed) {
            // Encounter the ice - resolve unbroken subroutines
            try resolveEncounteredIceSubroutines(generated, target.ice, target.server_index, target.ice_index, 0);
            // ETR fired
            if (generated.snapshot.state.run == null) return;
            // Subroutine opened a new prompt (e.g., Brân 1.0 install ice) - wait for resolution
            if (generated.snapshot.state.corp.prompt_state) |ps| {
                if (!std.mem.eql(u8, ps.prompt_type, "run")) return;
            }
        }
    }

    if (run.position > 0) run.position -= 1;
    run.phase = try allocator.dupe(u8, "movement");
    run.jack_out_available = true; // Runner can jack out after passing ICE
    run.no_action = null;
    // Runner gets first opportunity to jack out
    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
}

fn resolveEncounteredIceSubroutines(
    generated: *Game,
    ice: state.CardInstance,
    server_index: usize,
    ice_index: usize,
    start_subroutine: u8,
) !void {
    const allocator = generated.arena.allocator();
    const subroutines = ice.subroutines;

    for (subroutines, 0..) |sub, idx| {
        if (idx < start_subroutine) continue;
        const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(idx))) != 0;
        if (is_broken) continue;

        switch (sub.kind) {
            .end_the_run => {
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
                return;
            },
            .do_net_damage => {
                const damage = sub.amount;
                try trashRandomRunnerHandCards(generated, damage);
                updateTerminalState(generated);
                if (generated.snapshot.state.game_over) return;
            },
            .do_brain_damage => {
                const damage = sub.amount;
                generated.snapshot.state.runner.brain_damage += damage;
                try trashRandomRunnerHandCards(generated, damage);
                updateTerminalState(generated);
                if (generated.snapshot.state.game_over) return;
            },
            .tag_runner => {
                const runner = &generated.snapshot.state.runner;
                if (runner.tag == null) {
                    runner.tag = .{ .base = 0, .total = 1, .is_tagged = true };
                } else {
                    runner.tag.?.total += 1;
                    runner.tag.?.is_tagged = runner.tag.?.total > 0;
                }
            },
            .trace_tag => {
                // For now, auto-resolve trace: runner takes the tag
                // TODO: implement trace prompt system
                const runner = &generated.snapshot.state.runner;
                if (runner.tag == null) {
                    runner.tag = .{ .base = 0, .total = 1, .is_tagged = true };
                } else {
                    runner.tag.?.total += 1;
                    runner.tag.?.is_tagged = runner.tag.?.total > 0;
                }
            },
            .give_runner_tags => {
                const tags = sub.amount;
                const runner = &generated.snapshot.state.runner;
                if (runner.tag == null) {
                    runner.tag = .{ .base = 0, .total = tags, .is_tagged = tags > 0 };
                } else {
                    runner.tag.?.total += tags;
                    runner.tag.?.is_tagged = runner.tag.?.total > 0;
                }
            },
            .runner_loses_credits => {
                const loss = @min(sub.amount, @as(u8, @intCast(generated.snapshot.state.runner.credit)));
                generated.snapshot.state.runner.credit -= loss;
            },
            .install_ice_from_hq_archives => {
                try beginBranInstallIcePrompt(generated, server_index, ice_index, @intCast(idx));
                return;
            },
            .none => {},
        }
    }
}

fn checkManegarmSkunkworks(generated: *Game) !bool {
    const run = generated.snapshot.state.run orelse return false;
    if (run.position != 0) return false;

    const target_server = try findServerByRunPath(generated.snapshot.state.corp.servers, run.server);
    const server = target_server.slot;

    for (server.state.content) |card| {
        if (card.access.kind == .manegarm_skunkworks) {
            const allocator = generated.arena.allocator();
            var choices: std.ArrayList(state.PromptChoice) = .empty;
            const runner = &generated.snapshot.state.runner;

            if (runner.click >= 2) {
                try choices.append(allocator, .{
                    .kind = .string,
                    .text = try allocator.dupe(u8, "Spend [Click][Click]"),
                });
            }

            if (runner.credit >= 5) {
                try choices.append(allocator, .{
                    .kind = .string,
                    .text = try allocator.dupe(u8, "Pay 5 [Credits]"),
                });
            }

            try choices.append(allocator, .{
                .kind = .string,
                .text = try allocator.dupe(u8, "End the run"),
            });

            generated.snapshot.state.runner.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, "manegarm-skunkworks-choice"),
                .choices = try choices.toOwnedSlice(allocator),
                .source_card = card,
            };

            generated.snapshot.decision_side = .runner;
            generated.snapshot.legal_actions = try promptChoiceActions(allocator, .runner, generated.snapshot.state.runner.prompt_state.?);
            return true;
        }
    }

    return false;
}

fn beginBranInstallIcePrompt(
    generated: *Game,
    server_index: usize,
    ice_index: usize,
    subroutine_index: u8,
) !void {
    const allocator = generated.arena.allocator();
    const corp = &generated.snapshot.state.corp;
    const run = &generated.snapshot.state.run.?;

    // Build list of ice cards in HQ and Archives
    var choices: std.ArrayList(state.PromptChoice) = .empty;

    // Add ice from HQ
    for (corp.hand, 0..) |card, idx| {
        if (std.mem.eql(u8, card.card_type orelse "", "ICE")) {
            try choices.append(allocator, .{
                .kind = .string,
                .text = try std.fmt.allocPrint(allocator, "HQ|{d}|{s}", .{ idx, card.title }),
            });
        }
    }

    // Add ice from Archives (face-up ice)
    for (corp.discard, 0..) |card, idx| {
        if (std.mem.eql(u8, card.card_type orelse "", "ICE") and card.rezzed) {
            try choices.append(allocator, .{
                .kind = .string,
                .text = try std.fmt.allocPrint(allocator, "Archives|{d}|{s}", .{ idx, card.title }),
            });
        }
    }

    if (choices.items.len == 0) {
        return;
    }

    // Store continuation state
    run.pending_subroutine = .{
        .server_index = @intCast(server_index),
        .ice_index = @intCast(ice_index),
        .subroutine_index = subroutine_index,
    };

    // Set corp prompt
    corp.prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_bran_install_ice),
        .choices = try choices.toOwnedSlice(allocator),
    };

    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try promptChoiceActions(allocator, .corp, corp.prompt_state.?);
}

fn applyBranInstallIceChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    const allocator = generated.arena.allocator();
    const run = generated.snapshot.state.run orelse return error.NoRunInProgress;
    const pending = run.pending_subroutine orelse return error.MissingPendingSubroutine;

    // Parse choice: "HQ|index|title" or "Archives|index|title"
    var pieces = std.mem.splitScalar(u8, choice_text, '|');
    const zone = pieces.next() orelse return error.UnsupportedChoice;
    const index_text = pieces.next() orelse return error.UnsupportedChoice;
    const card_index = try std.fmt.parseInt(usize, index_text, 10);

    // Get the ice card
    var ice_to_install: state.CardInstance = undefined;
    if (std.mem.eql(u8, zone, "HQ")) {
        if (card_index >= generated.corp_hand.items.len) return error.InvalidCardIndex;
        ice_to_install = generated.corp_hand.orderedRemove(card_index);
        generated.snapshot.state.corp.hand = try sliceFromArrayList(allocator, generated.corp_hand);
    } else if (std.mem.eql(u8, zone, "Archives")) {
        if (card_index >= generated.corp_discard.items.len) return error.InvalidCardIndex;
        ice_to_install = generated.corp_discard.orderedRemove(card_index);
        generated.snapshot.state.corp.discard = try sliceFromArrayList(allocator, generated.corp_discard);
    } else return error.UnsupportedChoice;

    // Install ice at position 0 (outermost position)
    // This pushes all existing ice outward by 1 position
    const target_server = &generated.corp_servers.items[pending.server_index];
    try target_server.ices.insert(generated.backing_allocator, 0, ice_to_install);

    // Sync views
    try syncOwnedViews(generated);

    // Clear prompt
    generated.snapshot.state.corp.prompt_state = null;

    // After installation, Bran 1.0 is now at position (ice_index + 1)
    // because we inserted a new ice at position 0
    const new_bran_position = pending.ice_index + 1;
    const bran_ice = target_server.ices.items[new_bran_position];

    // Resume subroutine resolution from next subroutine
    try resolveEncounteredIceSubroutines(generated, bran_ice, pending.server_index, new_bran_position, pending.subroutine_index + 1);

    // Clear pending state
    generated.snapshot.state.run.?.pending_subroutine = null;

    // If ETR fired, we're done
    if (generated.snapshot.state.run == null) return;

    // If another prompt opened, return
    if (generated.snapshot.state.corp.prompt_state != null) return;

    // Continue with movement phase
    const current_run = &generated.snapshot.state.run.?;
    if (current_run.position > 0) current_run.position -= 1;
    current_run.phase = try allocator.dupe(u8, "movement");
    current_run.jack_out_available = true;
    current_run.no_action = null;
    generated.snapshot.decision_side = .runner;
    generated.snapshot.legal_actions = try continueActionsForRun(allocator, .runner, current_run.*);
}

fn sliceFromArrayList(allocator: std.mem.Allocator, list: std.ArrayList(state.CardInstance)) ![]const state.CardInstance {
    return try allocator.dupe(state.CardInstance, list.items);
}

fn advanceMovementPhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.snapshot.state.run.?;

    // Clear jack-out flag since both players passed
    run.jack_out_available = false;
    run.no_action = null;

    // Check for more ice or success
    if (run.position > 0) {
        run.phase = try allocator.dupe(u8, "approach-ice");
        generated.snapshot.decision_side = .corp;
        generated.snapshot.legal_actions = try continueActionsForRun(allocator, .corp, run.*);
        return;
    }

    // Check for Manegarm Skunkworks when approaching server (position == 0)
    if (try checkManegarmSkunkworks(generated)) {
        return;
    }

    try applySuccessfulRunEffects(generated);
    if (try prepareNextAccess(generated)) {
        run.phase = try allocator.dupe(u8, "success");
        generated.snapshot.decision_side = .corp;
        generated.snapshot.legal_actions = try continueActionsForRun(allocator, .corp, run.*);
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
    generated.snapshot.state.runner_successful_run_this_turn = true;
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

fn completeRunAfterAccess(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.snapshot.state.runner_successful_run_this_turn = true;
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

fn completeSuccessfulRunWithCorpPriority(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.snapshot.state.runner_successful_run_this_turn = true;
    generated.snapshot.state.run = null;
    generated.snapshot.state.corp.prompt_state = null;
    generated.snapshot.state.runner.prompt_state = null;
    generated.snapshot.state.runner.run_credit = 0;
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try continueActions(allocator, .corp);
}

fn completeUnsuccessfulRun(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.snapshot.state.run = null;
    generated.snapshot.state.corp.prompt_state = null;
    generated.snapshot.state.runner.prompt_state = null;
    generated.snapshot.state.runner.run_credit = 0;
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try continueActions(allocator, .corp);
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
        .urtica_cipher => {
            try applyUrticaCipherOnAccess(generated, accessed);
            return false;
        },
        .manegarm_skunkworks => return false,
        .none => return false,
    }
}

fn applyUrticaCipherOnAccess(
    generated: *Game,
    accessed: state.CardInstance,
) !void {
    if (accessed.access.kind != .urtica_cipher) return error.UnsupportedAccessTarget;
    if (generated.snapshot.state.corp.credit < 2) return;
    try spendCredits(&generated.snapshot.state.corp, 2);
    const damage: u8 = 2 + accessed.advancement_counter;
    try trashRandomRunnerHandCards(generated, damage);
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
        generated.snapshot.legal_actions = try continueActionsForRun(generated.arena.allocator(), .corp, run.*);
        return;
    }
    try completeRunWithoutAccess(generated);
}

const AccessTarget = struct {
    index: u8,
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

fn nextIndexedAccessTarget(cards: []const state.CardInstance, accessed_count: u8) ?AccessTarget {
    if (accessed_count >= cards.len) return null;
    return .{
        .index = accessed_count,
        .card = cards[accessed_count],
    };
}

fn nextHqAccessTarget(generated: *Game, run: *state.RunState) !?AccessTarget {
    if (generated.snapshot.state.corp.hand.len == 0) return null;
    var shuffled_indexes: [64]u8 = undefined;
    for (generated.snapshot.state.corp.hand, 0..) |_, idx| {
        shuffled_indexes[idx] = @intCast(idx);
    }
    var rng_state = fromOracleSeed(generated.snapshot.state.rng_seed orelse return error.MissingRngSeed);
    shuffleInPlace(u8, &rng_state, shuffled_indexes[0..generated.snapshot.state.corp.hand.len]);
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

fn rememberAccessedIndex(run: *state.RunState, card_index: u8) void {
    if (run.accessed_count < run.accessed_card_indexes.len) {
        run.accessed_card_indexes[run.accessed_count] = card_index;
    }
    run.accessed_count += 1;
}

fn wasIndexAccessed(run: state.RunState, card_index: u8) bool {
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
    return switch (side) {
        .corp => &corp_continue_actions,
        .runner => runnerContinueActions(allocator, false), // Will be updated by caller if needed
    };
}

fn continueActionsForRun(
    allocator: std.mem.Allocator,
    side: state.Side,
    run: ?state.RunState,
) ![]const state.LegalAction {
    return switch (side) {
        .corp => &corp_continue_actions,
        .runner => runnerContinueActions(allocator, run != null and run.?.jack_out_available),
    };
}

fn encounterActionsForState(
    allocator: std.mem.Allocator,
    generated: *Game,
    ice: state.CardInstance,
) ![]const state.LegalAction {
    // Count available icebreakers and unbroken subroutines
    var breaker_count: usize = 0;
    for (generated.runner_rig_program.items) |card| {
        if (isIcebreaker(card) and card.installed_ability.kind == .break_subroutine) {
            breaker_count += 1;
        }
    }

    // Count unbroken subroutines
    var unbroken_count: usize = 0;
    for (ice.subroutines, 0..) |_, idx| {
        const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(idx))) != 0;
        if (!is_broken) unbroken_count += 1;
    }

    // Count ICE-printed runner abilities (e.g., bioroid break)
    var bioroid_ability_count: usize = 0;
    for (ice.runner_abilities) |ability| {
        if (ability.kind == .bioroid_break) {
            bioroid_ability_count += 1;
        }
    }

    // Actions: continue + icebreaker break actions + bioroid break actions
    const total_actions = 1 + (breaker_count * unbroken_count) + bioroid_ability_count;
    const actions = try allocator.alloc(state.LegalAction, total_actions);

    // Add continue action (let the ice fire)
    actions[0] = .{
        .kind = .@"continue",
        .side = .runner,
        .prompt_type = "run",
        .label = "Continue",
    };

    var next: usize = 1;

    // Add break actions for each icebreaker and each unbroken subroutine
    for (generated.runner_rig_program.items, 0..) |card, card_idx| {
        if (!isIcebreaker(card)) continue;
        if (card.installed_ability.kind != .break_subroutine) continue;

        for (ice.subroutines, 0..) |_, sub_idx| {
            const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(sub_idx))) != 0;
            if (is_broken) continue;

            const label = try std.fmt.allocPrint(allocator, "Break subroutine {d} with {s}", .{ sub_idx, card.title });
            actions[next] = .{
                .kind = .use_subroutine,
                .side = .runner,
                .card_index = @intCast(card_idx),
                .card_title = try allocator.dupe(u8, card.title),
                .choice = .{
                    .kind = .number,
                    .number = @intCast(sub_idx),
                },
                .label = label,
            };
            next += 1;
        }
    }

    // Add bioroid break actions (lose clicks to break subroutines)
    for (ice.runner_abilities) |ability| {
        if (ability.kind == .bioroid_break) {
            const label = try std.fmt.allocPrint(allocator, "Lose {d} click(s) to break {d} subroutine(s)", .{ ability.click_cost, ability.break_quantity });
            actions[next] = .{
                .kind = .use_subroutine,
                .side = .runner,
                .card_title = try allocator.dupe(u8, ice.title),
                .choice = .{
                    .kind = .number,
                    .number = ability.break_quantity,
                },
                .label = label,
            };
            next += 1;
        }
    }

    return actions;
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
    const scoreable_count = countScoreableAgendas(corp.servers);
    var playable_hand_count: usize = 0;
    for (corp.hand) |card| {
        if (isCorpCardPlayableFromHand(corp, card)) playable_hand_count += 1;
    }

    const installed_ability_count = countCorpInstalledAbilityActions(corp.servers);
    var count: usize = playable_hand_count + installed_ability_count;
    if (corp.click >= 1) count += 1;
    if (corp.click >= 1 and corp.deck.len > 0) count += 1;
    if (corp.click >= 1 and corp.credit >= 1) count += 1;
    if (corp.click >= 1 and scoreable_count > 0) count += 1;
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
    for (corp.servers, 0..) |server, server_index| {
        const display_name = try displayNameForServer(allocator, server.name, server_index);
        for (server.state.content, 0..) |card, content_index| {
            if (!hasCorpInstalledAbilityAction(card)) continue;
            actions[next] = .{
                .kind = .use_installed_ability,
                .side = .corp,
                .server = display_name,
                .card_index = @intCast(content_index),
                .card_title = try allocator.dupe(u8, card.title),
                .installed_ability = card.installed_ability.kind,
                .label = try installedAbilityLabel(allocator, card),
            };
            next += 1;
        }
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
    if (corp.click >= 1 and scoreable_count > 0) {
        actions[next] = try basicAbilityAction(allocator, .corp, .score_agenda, "Score an agenda");
        next += 1;
    }
    if (corp.click >= 3) {
        actions[next] = try basicAbilityAction(allocator, .corp, .purge_viruses, "Purge virus counters");
    }

    return actions;
}

fn countScoreableAgendas(servers: []const state.ServerSlot) usize {
    var count: usize = 0;
    for (servers, 0..) |server, server_index| {
        if (server_index < 3) continue;
        for (server.state.content) |card| {
            if (card.agenda_points == null) continue;
            if (card.advancement_requirement == null) continue;
            if (card.advancement_counter < card.advancement_requirement.?) continue;
            count += 1;
        }
    }
    return count;
}

fn countInstalledCards(servers: []const state.ServerSlot) usize {
    var count: usize = 0;
    for (servers) |server| {
        count += server.state.ices.len;
        count += server.state.content.len;
    }
    return count;
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
    const resource_ability_count = countRunnerInstalledAbilityActions(runner.rig_resources);
    const hardware_ability_count = countRunnerInstalledAbilityActions(runner.rig_hardware);
    const installed_ability_count = resource_ability_count + hardware_ability_count;

    var count: usize = playable_hand_count + runnable_servers.len + installed_ability_count;
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
    for (runner.rig_resources, 0..) |card, idx| {
        if (!hasRunnerInstalledAbilityAction(card)) continue;
        actions[next] = .{
            .kind = .use_installed_ability,
            .side = .runner,
            .card_index = @intCast(idx),
            .card_title = try allocator.dupe(u8, card.title),
            .installed_ability = card.installed_ability.kind,
            .label = try installedAbilityLabel(allocator, card),
        };
        next += 1;
    }
    for (runner.rig_hardware, 0..) |card, idx| {
        if (!hasRunnerInstalledAbilityAction(card)) continue;
        actions[next] = .{
            .kind = .use_installed_ability,
            .side = .runner,
            .card_index = @intCast(idx),
            .card_title = try allocator.dupe(u8, card.title),
            .installed_ability = card.installed_ability.kind,
            .label = try installedAbilityLabel(allocator, card),
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

fn installedAbilityLabel(
    allocator: std.mem.Allocator,
    card: state.CardInstance,
) ![]const u8 {
    return switch (card.installed_ability.kind) {
        .take_credits => std.fmt.allocPrint(allocator, "Take {d} [Credits] from this card", .{card.installed_ability.take_credits_amount}),
        .place_credits => std.fmt.allocPrint(allocator, "Place {d} [Credits] on this card", .{card.installed_ability.place_credits_amount}),
        .break_subroutine => std.fmt.allocPrint(allocator, "Break {d} subroutine(s)", .{card.installed_ability.break_subroutine_count}),
        .pump_strength => std.fmt.allocPrint(allocator, "Add {d} strength", .{card.installed_ability.pump_strength_amount}),
        .run_central => allocator.dupe(u8, "Make a run on a central server"),
        .none => allocator.dupe(u8, "Use ability"),
    };
}

fn hasRunnerInstalledAbilityAction(card: state.CardInstance) bool {
    if (card.installed_ability.kind == .none) return false;
    if (card.ability_used_this_turn and card.installed_ability.once_per_turn) return false;

    // For abilities that require clicks, check click cost
    if (card.installed_ability.click_cost > 0) {
        return true;
    }

    // For icebreaker abilities during encounter, they don't need click cost
    if (card.installed_ability.kind == .break_subroutine or card.installed_ability.kind == .pump_strength) {
        return true;
    }

    return false;
}

fn hasCorpInstalledAbilityAction(card: state.CardInstance) bool {
    if (card.installed_ability.kind == .none) return false;
    if (!card.rezzed) return false;
    if (card.installed_ability.click_cost == 0) return false;
    if (card.ability_used_this_turn and card.installed_ability.once_per_turn) return false;
    return card.credit_counter > 0;
}

fn countRunnerInstalledAbilityActions(cards: []const state.CardInstance) usize {
    var count: usize = 0;
    for (cards) |card| {
        if (hasRunnerInstalledAbilityAction(card)) count += 1;
    }
    return count;
}

fn countCorpInstalledAbilityActions(servers: []const state.ServerSlot) usize {
    var count: usize = 0;
    for (servers) |server| {
        for (server.state.content) |card| {
            if (hasCorpInstalledAbilityAction(card)) count += 1;
        }
    }
    return count;
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
        var copy_idx: u8 = 0;
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

fn deepCloneCard(allocator: std.mem.Allocator, card: state.CardInstance) !state.CardInstance {
    var cloned = card;
    cloned.title = try allocator.dupe(u8, card.title);
    if (card.printed_title) |pt| {
        cloned.printed_title = try allocator.dupe(u8, pt);
    }
    if (card.card_type) |ct| {
        cloned.card_type = try allocator.dupe(u8, ct);
    }
    if (card.subtypes.len > 0) {
        const subtypes_copy = try allocator.alloc([]const u8, card.subtypes.len);
        for (card.subtypes, 0..) |st, i| {
            subtypes_copy[i] = try allocator.dupe(u8, st);
        }
        cloned.subtypes = subtypes_copy;
    }
    cloned.subroutines = try allocator.dupe(state.SubroutineSpec, card.subroutines);
    return cloned;
}

fn syncOwnedViews(game: *Game) !void {
    const allocator = game.arena.allocator();

    game.snapshot.state.corp.hand = game.corp_hand.items;
    game.snapshot.state.corp.deck = game.corp_deck.items;
    game.snapshot.state.corp.discard = game.corp_discard.items;
    game.snapshot.state.corp.scored = game.corp_scored.items;
    game.snapshot.state.runner.hand = game.runner_hand.items;
    game.snapshot.state.runner.deck = game.runner_deck.items;
    game.snapshot.state.runner.discard = game.runner_discard.items;
    game.snapshot.state.runner.scored = game.runner_scored.items;
    game.snapshot.state.runner.rig_hardware = game.runner_rig_hardware.items;
    game.snapshot.state.runner.rig_program = game.runner_rig_program.items;
    game.snapshot.state.runner.rig_resources = game.runner_rig_resources.items;

    const servers = try allocator.alloc(state.ServerSlot, game.corp_servers.items.len);
    for (game.corp_servers.items, 0..) |server, idx| {
        const ice_slice = server.ices.items;
        const content_slice = server.content.items;
        const ice_copy = try allocator.alloc(state.CardInstance, ice_slice.len);
        const content_copy = try allocator.alloc(state.CardInstance, content_slice.len);
        for (ice_slice, 0..) |card, i| ice_copy[i] = try deepCloneCard(allocator, card);
        for (content_slice, 0..) |card, i| content_copy[i] = try deepCloneCard(allocator, card);
        servers[idx] = .{
            .name = server.name,
            .state = .{
                .ices = ice_copy,
                .content = content_copy,
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
    const subtypes = try allocator.alloc([]const u8, spec.subtypes.len);
    for (spec.subtypes, 0..) |subtype, i| {
        subtypes[i] = try allocator.dupe(u8, subtype);
    }

    return .{
        .title = try allocator.dupe(u8, spec.title),
        .printed_title = try allocator.dupe(u8, spec.title),
        .code = spec.code,
        .side = spec.side,
        .card_type = if (spec.card_type) |kind| try allocator.dupe(u8, kind) else null,
        .subtypes = subtypes,
        .cost = spec.cost,
        .strength = spec.strength,
        .agenda_points = spec.agenda_points,
        .advancement_requirement = spec.advancement_requirement,
        .corp_play = spec.corp_play,
        .runner_play = spec.runner_play,
        .access = spec.access,
        .install = spec.install,
        .runner_install = spec.runner_install,
        .installed_ability = spec.installed_ability,
        .subroutines = spec.subroutines,
        .advancement_counter = 0,
        .credit_counter = 0,
        .ability_used_this_turn = false,
        .broken_subroutines = 0,
    };
}

fn lookupRequiredCardSpec(card_code: u32) !catalog.CardSpec {
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

fn appendRunnerInstalledCard(
    game: *Game,
    card: state.CardInstance,
) !void {
    switch (card.runner_install.kind) {
        .hardware => try game.runner_rig_hardware.append(game.backing_allocator, card),
        .program => try game.runner_rig_program.append(game.backing_allocator, card),
        .resource => try game.runner_rig_resources.append(game.backing_allocator, card),
        else => return error.UnsupportedRunnerInstall,
    }
    try syncOwnedViews(game);
}

fn resetInstalledAbilityUsage(game: *Game) void {
    for (game.corp_servers.items) |*server| {
        for (server.content.items) |*card| {
            card.ability_used_this_turn = false;
        }
    }
    for (game.runner_rig_hardware.items) |*card| {
        card.ability_used_this_turn = false;
    }
    for (game.runner_rig_program.items) |*card| {
        card.ability_used_this_turn = false;
    }
    for (game.runner_rig_resources.items) |*card| {
        card.ability_used_this_turn = false;
    }
}

fn drawCard(game: *Game, side: state.Side) !void {
    const deck = deckList(game, side);
    if (deck.items.len == 0) {
        // Deck-out: if corp can't draw at start of turn, they lose
        if (side == .corp) {
            game.snapshot.state.game_over = true;
            game.snapshot.state.winner = .runner;
            game.snapshot.state.run = null;
            game.snapshot.state.corp.prompt_state = null;
            game.snapshot.state.runner.prompt_state = null;
            game.snapshot.legal_actions = &.{};
            game.snapshot.decision_side = .runner;
            return error.EmptyDeck;
        }
        return error.EmptyDeck;
    }
    const drawn = deck.orderedRemove(0);
    try handList(game, side).append(game.backing_allocator, drawn);
    try syncOwnedViews(game);
}

fn drawCards(game: *Game, side: state.Side, amount: u8) !void {
    var remaining = amount;
    while (remaining > 0) : (remaining -= 1) {
        try drawCard(game, side);
    }
}

fn trashRandomRunnerHandCards(
    game: *Game,
    amount: u8,
) !void {
    var remaining = amount;
    var rng_state = fromOracleSeed(game.snapshot.state.rng_seed orelse return error.MissingRngSeed);
    while (remaining > 0 and game.runner_hand.items.len > 0) : (remaining -= 1) {
        const idx = randBelow(&rng_state, game.runner_hand.items.len);
        const trashed = game.runner_hand.orderedRemove(idx);
        try game.runner_discard.append(game.backing_allocator, trashed);
    }
    game.snapshot.state.rng_seed = oracleSeed(rng_state);
    try syncOwnedViews(game);
}

fn shuffleDeck(game: *Game, side: state.Side) !void {
    const deck = deckList(game, side);
    var rng_state = fromOracleSeed(game.snapshot.state.rng_seed orelse return error.MissingRngSeed);
    shuffleInPlace(state.CardInstance, &rng_state, deck.items);
    game.snapshot.state.rng_seed = oracleSeed(rng_state);
    try syncOwnedViews(game);
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
    index: u8,
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
    amount: u8,
) !void {
    if (player.click < amount) return error.InsufficientClicks;
    player.click -= amount;
}

fn spendCredits(
    player: *state.PlayerState,
    amount: u16,
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
    if (card.runner_install.kind != .none) return runner.credit >= (card.cost orelse 0);
    const card_type = card.card_type orelse return false;
    if (!std.mem.eql(u8, card_type, "Event")) return false;
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
        .central_only => try allocator.dupe([]const u8, &.{ "HQ", "R&D", "Archives" }),
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
    index: u8,
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
    index: u8,
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

fn findServerIndexByDisplayName(
    servers: []const state.ServerSlot,
    display_name: []const u8,
) !usize {
    if (std.mem.eql(u8, display_name, "HQ")) return findServerIndexByName(servers, "hq");
    if (std.mem.eql(u8, display_name, "R&D")) return findServerIndexByName(servers, "rnd");
    if (std.mem.eql(u8, display_name, "Archives")) return findServerIndexByName(servers, "archives");
    if (std.mem.startsWith(u8, display_name, "Server ")) {
        const index_text = display_name["Server ".len..];
        const parsed = try std.fmt.parseInt(usize, index_text, 10);
        return parsed + 2;
    }
    return error.UnsupportedServer;
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
    try std.testing.expectEqual(@as(u16, 9), generated.snapshot.state.corp.credit);
    try std.testing.expectEqual(@as(u8, 2), generated.snapshot.state.corp.click);
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
    try std.testing.expectEqual(@as(u8, 2), install_generated.snapshot.state.corp.click);
    try std.testing.expectEqual(@as(usize, 8), legalActionCount(&install_generated));
    try expectInstalledIceTitle(install_generated.snapshot.state.corp.servers, "Brân 1.0");
}

test "intermediate matchup snapshot initializes" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_intermediate,
        1,
    );
    defer generated.deinit();

    try std.testing.expectEqualStrings("system-gateway", generated.snapshot.state.format);
    try std.testing.expectEqual(@as(u8, 7), generated.snapshot.state.corp.agenda_point_req);
    try std.testing.expectEqual(@as(u8, 7), generated.snapshot.state.runner.agenda_point_req);
    try std.testing.expectEqual(@as(usize, 39), generated.snapshot.state.corp.deck.len);
    try std.testing.expectEqual(@as(usize, 35), generated.snapshot.state.runner.deck.len);
    try std.testing.expectEqual(state.Side.corp, currentPlayer(&generated));
}

test "runner telework contract install and hosted-credit ability" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        7,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });
    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    const install_action = findActionByTitle(generated.snapshot.legal_actions, .play_from_hand, "Telework Contract") orelse return error.MissingAction;
    try applyAction(&generated, install_action);

    try std.testing.expectEqual(@as(usize, 1), generated.snapshot.state.runner.rig_resources.len);
    try std.testing.expectEqualStrings("Telework Contract", generated.snapshot.state.runner.rig_resources[0].title);
    try std.testing.expectEqual(@as(u16, 9), generated.snapshot.state.runner.rig_resources[0].credit_counter);
    try std.testing.expectEqual(@as(u16, 4), generated.snapshot.state.runner.credit);
    try std.testing.expectEqual(@as(u8, 3), generated.snapshot.state.runner.click);

    const use_action = findInstalledAbilityAction(generated.snapshot.legal_actions, "Telework Contract") orelse return error.MissingAction;
    try applyAction(&generated, use_action);

    try std.testing.expectEqual(@as(u16, 7), generated.snapshot.state.runner.credit);
    try std.testing.expectEqual(@as(u8, 2), generated.snapshot.state.runner.click);
    try std.testing.expectEqual(@as(u16, 6), generated.snapshot.state.runner.rig_resources[0].credit_counter);
    try std.testing.expect(findInstalledAbilityAction(generated.snapshot.legal_actions, "Telework Contract") == null);
}

test "send a message steal triggers corp rez choice when unrezzed ice exists" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        2,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });

    const ice_install = findFirstCorpIceInstallPlay(generated.snapshot.legal_actions, generated.snapshot.state.corp.hand) orelse return error.MissingAction;
    const ice_title = ice_install.card_title orelse return error.MissingAction;
    try applyAction(&generated, ice_install);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_install_destination,
        .choice = stringChoice("New remote"),
    });

    try applyAction(&generated, findActionByTitle(generated.snapshot.legal_actions, .play_from_hand, "Send a Message") orelse return error.MissingAction);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_install_destination,
        .choice = stringChoice("New remote"),
    });
    generated.snapshot.state.corp.credit = 20;
    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    try applyAction(&generated, findRunAction(generated.snapshot.legal_actions, "Server 2") orelse return error.MissingAction);
    try applyAction(&generated, .{ .kind = .@"continue", .side = .corp, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .runner, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .corp, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .runner, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .corp, .prompt_type = "run" });
    try applyAction(&generated, findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Steal") orelse return error.MissingAction);

    const rez_choice = findPromptChoiceAction(generated.snapshot.legal_actions, .corp, ice_title) orelse return error.MissingAction;
    try applyAction(&generated, rez_choice);

    try std.testing.expect(iceIsRezzed(generated.snapshot.state.corp.servers, ice_title));
}

test "run ice windows can prompt corp rez on approached ice when enabled" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        2,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });

    const ice_install = findFirstCorpIceInstallPlay(generated.snapshot.legal_actions, generated.snapshot.state.corp.hand) orelse return error.MissingAction;
    const ice_title = ice_install.card_title orelse return error.MissingAction;
    try applyAction(&generated, ice_install);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_install_destination,
        .choice = stringChoice("New remote"),
    });
    generated.snapshot.state.corp.credit = 20;
    while (findBasicAbilityAction(generated.snapshot.legal_actions, .corp, .gain_credit)) |gain_action| {
        try applyAction(&generated, gain_action);
    }
    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const run_action = findRunAction(generated.snapshot.legal_actions, "Server 1") orelse return error.MissingAction;
    try applyAction(&generated, run_action);

    var found_rez_prompt = false;
    var guard: usize = 0;
    while (guard < 12 and generated.snapshot.state.run != null) : (guard += 1) {
        if (generated.snapshot.decision_side == .corp) {
            if (findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Rez approached ice")) |rez_action| {
                try applyAction(&generated, rez_action);
                found_rez_prompt = true;
                break;
            }
        }
        const continue_action = findActionByKind(generated.snapshot.legal_actions, .@"continue", generated.snapshot.decision_side) orelse return error.MissingAction;
        try applyAction(&generated, continue_action);
    }
    try std.testing.expect(found_rez_prompt);

    try std.testing.expect(iceIsRezzed(generated.snapshot.state.corp.servers, ice_title));
}

test "corp installed credit ability on regolith pays out and trashes when empty" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        11,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });

    var regolith = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30071));
    regolith.credit_counter = regolith.installed_ability.initial_credit_counters;
    regolith.rezzed = true;
    try installCard(&generated, regolith, "New remote");

    generated.snapshot.state.corp.click = 6;
    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated.snapshot.state.corp);
    const credit_before = generated.snapshot.state.corp.credit;

    var use_count: usize = 0;
    while (use_count < 5) : (use_count += 1) {
        const action = findInstalledAbilityAction(generated.snapshot.legal_actions, "Regolith Mining License") orelse return error.MissingAction;
        try applyAction(&generated, action);
    }

    try std.testing.expectEqual(@as(u16, credit_before + 15), generated.snapshot.state.corp.credit);
    try std.testing.expect(findInstalledAbilityAction(generated.snapshot.legal_actions, "Regolith Mining License") == null);

    var found_discard = false;
    for (generated.snapshot.state.corp.discard) |card| {
        if (std.mem.eql(u8, card.title, "Regolith Mining License")) {
            found_discard = true;
            break;
        }
    }
    try std.testing.expect(found_discard);
}

test "offworld office on-score grants credits" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        12,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });

    var offworld = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30067));
    offworld.advancement_counter = 3;
    try installCard(&generated, offworld, "New remote");

    generated.snapshot.decision_side = .corp;
    generated.snapshot.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated.snapshot.state.corp);

    const credit_before = generated.snapshot.state.corp.credit;
    const score_action = findBasicAbilityAction(generated.snapshot.legal_actions, .corp, .score_agenda) orelse return error.MissingAction;
    try applyAction(&generated, score_action);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_score_agenda,
        .choice = stringChoice("remote1|c|0"),
    });

    try std.testing.expectEqual(@as(u8, 2), generated.snapshot.state.corp.agenda_point);
    try std.testing.expectEqual(@as(u16, credit_before + 7), generated.snapshot.state.corp.credit);
}

test "urtica cipher access applies net damage when corp can pay" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        13,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });

    var urtica = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30045));
    urtica.advancement_counter = 2;
    try installCard(&generated, urtica, "New remote");
    generated.snapshot.state.corp.credit = 20;

    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const hand_before = generated.snapshot.state.runner.hand.len;
    const discard_before = generated.snapshot.state.runner.discard.len;
    const corp_credit_before = generated.snapshot.state.corp.credit;

    try applyAction(&generated, findRunAction(generated.snapshot.legal_actions, "Server 1") orelse return error.MissingAction);
    var guard: usize = 0;
    while (guard < 16 and generated.snapshot.state.run != null) : (guard += 1) {
        const continue_action = findActionByKind(generated.snapshot.legal_actions, .@"continue", generated.snapshot.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    const expected_damage: usize = @min(hand_before, @as(usize, 4));
    try std.testing.expectEqual(hand_before - expected_damage, generated.snapshot.state.runner.hand.len);
    try std.testing.expectEqual(discard_before + expected_damage, generated.snapshot.state.runner.discard.len);
    try std.testing.expectEqual(corp_credit_before - 2, generated.snapshot.state.corp.credit);
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

fn findActionByTitle(actions: []const state.LegalAction, kind: state.ActionKind, title: []const u8) ?state.LegalAction {
    for (actions) |action| {
        if (action.kind == kind and action.card_title != null and std.mem.eql(u8, action.card_title.?, title)) return action;
    }
    return null;
}

fn findInstalledAbilityAction(actions: []const state.LegalAction, title: []const u8) ?state.LegalAction {
    for (actions) |action| {
        if (action.kind == .use_installed_ability and action.card_title != null and std.mem.eql(u8, action.card_title.?, title)) return action;
    }
    return null;
}

fn findActionByKind(actions: []const state.LegalAction, kind: state.ActionKind, side: state.Side) ?state.LegalAction {
    for (actions) |action| {
        if (action.kind == kind and action.side == side) return action;
    }
    return null;
}

fn findBasicAbilityAction(actions: []const state.LegalAction, side: state.Side, basic_action: state.BasicAction) ?state.LegalAction {
    for (actions) |action| {
        if (action.kind == .use_ability and action.side == side and action.basic_action != null and action.basic_action.? == basic_action) return action;
    }
    return null;
}

fn findFirstCorpIceInstallPlay(actions: []const state.LegalAction, hand: []const state.CardInstance) ?state.LegalAction {
    for (actions) |action| {
        if (action.kind != .play_from_hand or action.side != .corp or action.card_index == null) continue;
        const index: usize = action.card_index.?;
        if (index >= hand.len) continue;
        const card = hand[index];
        if (card.card_type != null and std.mem.eql(u8, card.card_type.?, "ICE")) return action;
    }
    return null;
}

fn findPromptChoiceAction(actions: []const state.LegalAction, side: state.Side, choice_text: []const u8) ?state.LegalAction {
    for (actions) |action| {
        if (action.kind != .prompt_choice or action.side != side or action.choice == null) continue;
        const choice = action.choice.?;
        if (choice.kind != .string or choice.text == null) continue;
        if (std.mem.eql(u8, choice.text.?, choice_text)) return action;
    }
    return null;
}

fn findRunAction(actions: []const state.LegalAction, server: []const u8) ?state.LegalAction {
    for (actions) |action| {
        if (action.kind == .run and action.server != null and std.mem.eql(u8, action.server.?, server)) return action;
    }
    return null;
}

fn findFirstRunAction(actions: []const state.LegalAction, side: state.Side) ?state.LegalAction {
    for (actions) |action| {
        if (action.kind == .run and action.side == side) return action;
    }
    return null;
}

fn findRemoteWithIce(servers: []const state.ServerSlot) ?[]const u8 {
    for (servers) |server| {
        if (!std.mem.startsWith(u8, server.name, "remote")) continue;
        if (server.state.ices.len == 0) continue;
        return server.name;
    }
    return null;
}

fn iceIsRezzed(servers: []const state.ServerSlot, title: []const u8) bool {
    for (servers) |server| {
        for (server.state.ices) |ice| {
            if (std.mem.eql(u8, ice.title, title) and ice.rezzed) return true;
        }
    }
    return false;
}

test "flatline terminal condition when brain damage equals hand size" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        100,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });
    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    // Set up flatline condition: brain damage >= hand size
    generated.snapshot.state.runner.brain_damage = 5;
    const hand_size = generated.snapshot.state.runner.hand.len;
    generated.snapshot.state.runner.brain_damage = @intCast(hand_size);

    updateTerminalState(&generated);
    try std.testing.expect(generated.snapshot.state.game_over);
    try std.testing.expectEqual(state.Side.corp, generated.snapshot.state.winner);
}

test "jack out is available after passing ice" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        101,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });

    // Install unrezzed ICE on a remote
    const ice_install = findFirstCorpIceInstallPlay(generated.snapshot.legal_actions, generated.snapshot.state.corp.hand) orelse return error.MissingAction;
    try applyAction(&generated, ice_install);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_install_destination,
        .choice = stringChoice("New remote"),
    });

    // End turn (ice remains unrezzed)
    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });

    // Runner starts turn and runs the remote
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    try applyAction(&generated, findRunAction(generated.snapshot.legal_actions, "Server 1") orelse return error.MissingAction);

    // Progress: initiation -> approach-ice -> movement (no rez, no encounter since ice is unrezzed)
    var guard: usize = 0;
    var found_jack_out = false;
    while (guard < 30 and generated.snapshot.state.run != null) : (guard += 1) {
        // Debug: print current phase
        // std.debug.print("Phase: {s}, Side: {any}, Actions: {d}\n", .{
        //     generated.snapshot.state.run.?.phase,
        //     generated.snapshot.decision_side,
        //     generated.snapshot.legal_actions.len
        // });

        // Check for jack_out action when it's runner's turn
        if (generated.snapshot.decision_side == .runner) {
            for (generated.snapshot.legal_actions) |action| {
                if (action.kind == .jack_out) {
                    found_jack_out = true;
                    break;
                }
            }
            if (found_jack_out) break;
        }

        // Handle rez window - corp should decline
        if (findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "No rez")) |no_rez| {
            try applyAction(&generated, no_rez);
            continue;
        }

        // Continue through the run
        const continue_action = findActionByKind(generated.snapshot.legal_actions, .@"continue", generated.snapshot.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    try std.testing.expect(found_jack_out);
}

test "ICE subroutine end the run fires" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        102,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });

    // Install Tithe (1 net damage, ETR) on a remote
    var tithe = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30073));
    tithe.rezzed = true;
    try installCard(&generated, tithe, "New remote");

    generated.snapshot.state.corp.credit = 20;
    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const hand_before = generated.snapshot.state.runner.hand.len;

    try applyAction(&generated, findRunAction(generated.snapshot.legal_actions, "Server 1") orelse return error.MissingAction);

    // Progress through the run - ICE should fire and ETR
    var guard: usize = 0;
    while (guard < 20 and generated.snapshot.state.run != null) : (guard += 1) {
        const continue_action = findActionByKind(generated.snapshot.legal_actions, .@"continue", generated.snapshot.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    // Run should have ended (ETR fired)
    try std.testing.expect(generated.snapshot.state.run == null);
    // Net damage should have been dealt (1 card from Tithe's first subroutine)
    try std.testing.expectEqual(hand_before - 1, generated.snapshot.state.runner.hand.len);
}

test "ICE net damage subroutine applies damage" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        103,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });

    // Install Karunā (2 net damage, 2 net damage) on a remote
    var karuna = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30047));
    karuna.rezzed = true;
    try installCard(&generated, karuna, "New remote");

    generated.snapshot.state.corp.credit = 20;
    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const hand_before = generated.snapshot.state.runner.hand.len;

    try applyAction(&generated, findRunAction(generated.snapshot.legal_actions, "Server 1") orelse return error.MissingAction);

    // Progress through the run
    var guard: usize = 0;
    while (guard < 20 and generated.snapshot.state.run != null) : (guard += 1) {
        const continue_action = findActionByKind(generated.snapshot.legal_actions, .@"continue", generated.snapshot.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    // Karunā should have dealt 4 net damage (2 + 2)
    try std.testing.expectEqual(@as(usize, @max(0, hand_before - 4)), generated.snapshot.state.runner.hand.len);
}

test "runner loses credits subroutine" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        104,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });

    // Install Whitespace (runner loses 2 credits, runner loses 2 credits) on a remote
    var whitespace = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30074));
    whitespace.rezzed = true;
    try installCard(&generated, whitespace, "New remote");

    generated.snapshot.state.corp.credit = 20;
    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const credit_before = generated.snapshot.state.runner.credit;

    try applyAction(&generated, findRunAction(generated.snapshot.legal_actions, "Server 1") orelse return error.MissingAction);

    // Progress through the run
    var guard: usize = 0;
    while (guard < 20 and generated.snapshot.state.run != null) : (guard += 1) {
        const continue_action = findActionByKind(generated.snapshot.legal_actions, .@"continue", generated.snapshot.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    // Whitespace should have reduced runner credits by 4 (2 + 2)
    try std.testing.expectEqual(@as(u16, @max(0, credit_before - 4)), generated.snapshot.state.runner.credit);
}

test "tread lightly run rez cost bonus is applied during corp rez window" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        1,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });

    // Install unrezzed ICE on a remote
    const ice_install = findFirstCorpIceInstallPlay(generated.snapshot.legal_actions, generated.snapshot.state.corp.hand) orelse return error.MissingAction;
    const ice_title = ice_install.card_title orelse return error.MissingAction;
    try applyAction(&generated, ice_install);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_install_destination,
        .choice = stringChoice("New remote"),
    });

    generated.snapshot.state.corp.credit = 20;
    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });

    // Runner plays Tread Lightly which sets rez cost bonus to 3
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    try applyAction(&generated, findActionByTitle(generated.snapshot.legal_actions, .play_from_hand, "Tread Lightly") orelse return error.MissingAction);

    // Tread Lightly prompts for run target
    try applyAction(&generated, findPromptChoiceAction(generated.snapshot.legal_actions, .runner, "Server 1") orelse return error.MissingAction);

    // Verify rez cost bonus is set
    try std.testing.expectEqual(@as(u16, 3), generated.snapshot.state.run.?.rez_cost_bonus);

    // Run through to approach-ice phase
    var guard: usize = 0;
    var found_rez_prompt = false;
    while (guard < 20 and generated.snapshot.state.run != null) : (guard += 1) {
        // Look for rez window prompt
        if (findPromptChoiceAction(generated.snapshot.legal_actions, .corp, "Rez approached ice")) |rez_action| {
            found_rez_prompt = true;
            // Corp has 20 credits, should be able to rez regardless of ice cost
            try std.testing.expect(generated.snapshot.state.corp.credit >= 4);
            try applyAction(&generated, rez_action);
            break;
        }
        const continue_action = findActionByKind(generated.snapshot.legal_actions, .@"continue", generated.snapshot.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    try std.testing.expect(found_rez_prompt);
    // ICE should be rezzed
    try std.testing.expect(iceIsRezzed(generated.snapshot.state.corp.servers, ice_title));
}

test "sure gamble gains credits without losing extra clicks" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        catalog.system_gateway_beginner,
        1,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .corp });
    try applyAction(&generated, .{ .kind = .end_turn, .side = .corp });
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    // Runner starts turn with 4 clicks and 5 credits
    try std.testing.expectEqual(@as(u8, 4), generated.snapshot.state.runner.click);
    try std.testing.expectEqual(@as(u16, 5), generated.snapshot.state.runner.credit);

    // Play Sure Gamble: costs 5 credits, 1 click, no lose_clicks
    const sg_action = findActionByTitle(generated.snapshot.legal_actions, .play_from_hand, "Sure Gamble") orelse return error.MissingAction;
    try applyAction(&generated, sg_action);

    // Should have spent only 1 click (not 2 like Creative Commission)
    try std.testing.expectEqual(@as(u8, 3), generated.snapshot.state.runner.click);
    // Should have gained 9 credits (spent 5, gained 9, net 4 from starting 5 = 9)
    try std.testing.expectEqual(@as(u16, 9), generated.snapshot.state.runner.credit);
}
