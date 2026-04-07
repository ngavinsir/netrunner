const std = @import("std");
const state = @import("state.zig");
const runtime = @import("runtime.zig");
const game_engine = @import("game.zig");

const Game = runtime.Game;

const gameFromEffectContext = runtime.gameFromEffectContext;
const gameFromConstEffectContext = runtime.gameFromConstEffectContext;
const addAdvancementCounter = runtime.addAdvancementCounter;
const addFloatingEffect = runtime.addFloatingEffect;
const addRunnerTag = runtime.addRunnerTag;
const appendDiscardCard = runtime.appendDiscardCard;
const appendHostedCard = runtime.appendHostedCard;
const appendRunnerInstalledCard = runtime.appendRunnerInstalledCard;
const applyBranInstallIceChoice = runtime.applyBranInstallIceChoice;
const applyInstallFromHand = runtime.applyInstallFromHand;
const applyRunFromAbility = runtime.applyRunFromAbility;
const applyRunnerPlayFromHand = runtime.applyRunnerPlayFromHand;
const applySuccessfulRunEffects = runtime.applySuccessfulRunEffects;
const beginPeerReviewInstallPrompt = runtime.beginPeerReviewInstallPrompt;
const beginRandomHqAccess = runtime.beginRandomHqAccess;
const beginRunnerHostedCardPrompt = runtime.beginRunnerHostedCardPrompt;
const beginRunnerInstallFromHand = runtime.beginRunnerInstallFromHand;
const beginRunnerOptionalInstallConfirmPrompt = runtime.beginRunnerOptionalInstallConfirmPrompt;
const beginRunnerOptionalInstallPrompt = runtime.beginRunnerOptionalInstallPrompt;
const beginYesNoPrompt = runtime.beginYesNoPrompt;
const checkManegarmSkunkworks = runtime.checkManegarmSkunkworks;
const completeRunnerInstall = runtime.completeRunnerInstall;
const completeSuccessfulRunWithCorpPriority = runtime.completeSuccessfulRunWithCorpPriority;
const completeUnsuccessfulRun = runtime.completeUnsuccessfulRun;
const continueActionsForRun = runtime.continueActionsForRun;
const continueActionsForRunWithRez = runtime.continueActionsForRunWithRez;
const corpOpeningActionsForState = runtime.corpOpeningActionsForState;
const countFractersInHeap = runtime.countFractersInHeap;
const countInstalledIcebreakers = runtime.countInstalledIcebreakers;
const countPlayableHostedRunnerCards = runtime.countPlayableHostedRunnerCards;
const currentPendingAccessedServerCard = runtime.currentPendingAccessedServerCard;
const centralNotRunThisTurnChoices = runtime.centralNotRunThisTurnChoices;
const drawCards = runtime.drawCards;
const encounterActionsForState = runtime.encounterActionsForState;
const findCardPtrByInstanceId = runtime.findCardPtrByInstanceId;
const findRunnerResourceIndex = runtime.findRunnerResourceIndex;
const findServerByRunPath = runtime.findServerByRunPath;
const hasActivePrompt = runtime.hasActivePrompt;
const hasFloatingEffectFromSource = runtime.hasFloatingEffectFromSource;
const hostedChoiceIndex = runtime.hostedChoiceIndex;
const hostRandomHqCard = runtime.hostRandomHqCard;
const hostTopRunnerDeckCard = runtime.hostTopRunnerDeckCard;
const installCard = runtime.installCard;
const corpInstallIce = game_engine.corpInstallIce;
const iceInstallChoices = game_engine.iceInstallChoices;
const installChoicesForCard = runtime.installChoicesForCard;
const installCorpCardFromHand = runtime.installCorpCardFromHand;
const installedCardChoices = runtime.installedCardChoices;
const installedNotThisTurnChoices = runtime.installedNotThisTurnChoices;
const is_runner_tagged = runtime.is_runner_tagged;
const isCentralRunServer = runtime.isCentralRunServer;
const moveCorpHandCardToDeckAndShuffle = runtime.moveCorpHandCardToDeckAndShuffle;
const prepareNextAccess = runtime.prepareNextAccess;
const promptChoiceActions = runtime.promptChoiceActions;
const purgeVirusCounters = runtime.purgeVirusCounters;
const removeCardFromHand = runtime.removeCardFromHand;
const removeCardFromHandByInstanceId = runtime.removeCardFromHandByInstanceId;
const logCorpOperationPlay = runtime.logCorpOperationPlay;
const resolveCorpOperation = runtime.resolveCorpOperation;
const removeCorpInstalledFromGame = runtime.removeCorpInstalledFromGame;
const removeHostedCard = runtime.removeHostedCard;
const removeRunnerTags = runtime.removeRunnerTags;
const restorePriorityAfterPrompt = runtime.restorePriorityAfterPrompt;
const resumePendingEffects = runtime.resumePendingEffects;
const returnHostedCardsToHq = runtime.returnHostedCardsToHq;
const runnerHandInstallableByEffect = runtime.runnerHandInstallableByEffect;
const runnerHasActiveRunEvent = runtime.runnerHasActiveRunEvent;
const runnerOpeningActionsForState = runtime.runnerOpeningActionsForState;
const showKpiChoices = runtime.showKpiChoices;
const showTopDownInstallChoices = runtime.showTopDownInstallChoices;
const shuffleDeck = runtime.shuffleDeck;
const spendClicks = runtime.spendClicks;
const sumFloatingEffects = runtime.sumFloatingEffects;
const spendCredits = runtime.spendCredits;
const stringChoice = runtime.stringChoice;
const threatLevel = runtime.threatLevel;
const trashCorpInstalledSelf = runtime.trashCorpInstalledSelf;
const trashHostedRunnerCards = runtime.trashHostedRunnerCards;
const trashRandomRunnerHandCards = runtime.trashRandomRunnerHandCards;
const updateTerminalState = runtime.updateTerminalState;
const predictive_planogram_choices = runtime.predictive_planogram_choices;
const runner_had_successful_run_last_turn = runtime.runner_had_successful_run_last_turn;
const retribution_choices = runtime.retribution_choices;
const isIcebreaker = runtime.isIcebreaker;
const wildcat_strike_choices = runtime.wildcat_strike_choices;
const hasSubtype = runtime.hasSubtype;
const runTargetChoicesFor = runtime.runTargetChoicesFor;
const canonicalRunServer = runtime.canonicalRunServer;
const trackMadeRun = runtime.trackMadeRun;
const continueActions = runtime.continueActions;
const public_trail_choices = runtime.public_trail_choices;
const fireEvent = runtime.fireEvent;
const fireEventWith = runtime.fireEventWith;
const isAbilityUsedThisTurn = runtime.isAbilityUsedThisTurn;
const markAbilityUsedThisTurn = runtime.markAbilityUsedThisTurn;
const trashCorpServerCardByInstanceId = game_engine.trashCorpServerCardByInstanceId;
const removeServerIfEmpty = game_engine.removeServerIfEmpty;
const trashRunnerRigCardByInstanceId = game_engine.trashRunnerRigCardByInstanceId;
const beginNetDamageOnAccessPrompt = game_engine.beginNetDamageOnAccessPrompt;
const beginByteAmbushPrompt = game_engine.beginByteAmbushPrompt;
const beginPhatGioanDamagePrompt = game_engine.beginPhatGioanDamagePrompt;
const beginSabotagePrompt = runtime.beginSabotagePrompt;
const bypassCurrentIce = runtime.bypassCurrentIce;
const beginStartTurnSequence = runtime.beginStartTurnSequence;
const beginPeekRdTopPrompt = runtime.beginPeekRdTopPrompt;
const completeRunnerEndTurn = runtime.completeRunnerEndTurn;
const serverHasBioroidIce = runtime.serverHasBioroidIce;
const continueServerApproach = runtime.continueServerApproach;
const removeCurrentAccessedCard = game_engine.removeCurrentAccessedCard;
const finishAccessCard = game_engine.finishAccessCard;
const checkServerApproachAbilities = game_engine.checkServerApproachAbilities;
const sideName = game_engine.sideName;
const prompt_run_central = game_engine.prompt_run_central;
const encounterBreakHandler = game_engine.encounterBreakHandler;
const encounterPumpHandler = game_engine.encounterPumpHandler;
const encounterBioroidHandler = game_engine.encounterBioroidHandler;
const encounterLeechHandler = game_engine.encounterLeechHandler;
const collectEventHandlers = game_engine.collectEventHandlers;
const beginRezIceFreePromptForScore = game_engine.beginRezIceFreePromptForScore;
const beginRezIceFreePrompt = game_engine.beginRezIceFreePrompt;
const encounterBotulusHandler = game_engine.encounterBotulusHandler;
const isInEncounter = game_engine.isInEncounter;
const openRunnerDiscardToDeckPrompt = game_engine.openRunnerDiscardToDeckPrompt;
const resolveEndTheRun = game_engine.resolveEndTheRun;
const resolveNetDamage = game_engine.resolveNetDamage;
const resolveBrainDamage = game_engine.resolveBrainDamage;
const resolveTagRunner = game_engine.resolveTagRunner;
const resolveGiveRunnerTags = game_engine.resolveGiveRunnerTags;
const resolveRunnerLosesCredits = game_engine.resolveRunnerLosesCredits;
const resolveCorpGainsCredits = game_engine.resolveCorpGainsCredits;
const resolveNetDamageConditionalEtr = game_engine.resolveNetDamageConditionalEtr;
const resolveRunnerLosesCreditsOrEtr = game_engine.resolveRunnerLosesCreditsOrEtr;
const resolveNetDamageThenJackOut = game_engine.resolveNetDamageThenJackOut;
const resolveGiveTagOrPayCredits = game_engine.resolveGiveTagOrPayCredits;
const resolveInstallIceFromHqArchives = game_engine.resolveInstallIceFromHqArchives;
const resolveTrashProgramOrEtr = game_engine.resolveTrashProgramOrEtr;
const resolveCorpInstallFromHqArchives = game_engine.resolveCorpInstallFromHqArchives;
const resolvePreventStealTrash = game_engine.resolvePreventStealTrash;
const resolveConditionalNetDamageIfTagged = game_engine.resolveConditionalNetDamageIfTagged;
const resolveConditionalEtrThreat = game_engine.resolveConditionalEtrThreat;
const resolveNetDamageUnlessEtr = game_engine.resolveNetDamageUnlessEtr;
const resolveTrashProgramOrResourceOrEtr = game_engine.resolveTrashProgramOrResourceOrEtr;
const resolveTagOrPayCreditsEtr = game_engine.resolveTagOrPayCreditsEtr;
const resolvePlaceAdvancementCounter = game_engine.resolvePlaceAdvancementCounter;
const resolveEtrIfTagged = game_engine.resolveEtrIfTagged;
const resolveRezIceWithDiscount = game_engine.resolveRezIceWithDiscount;
const resolveOtherIceSubroutine = game_engine.resolveOtherIceSubroutine;

pub const CardSpec = struct {
    title: []const u8,
    side: state.Side,
    code: u32,
    card_type: ?[]const u8 = null,
    subtypes: []const []const u8 = &.{},
    cost: ?u16 = null,
    strength: ?u8 = null,
    agenda_points: ?u8 = null,
    advancement_requirement: ?u8 = null,
    install: state.InstallSpec = .{},
    runner_install: state.RunnerInstallSpec = .{},
    abilities: []const state.AbilitySpec = &.{},
    static_abilities: []const state.StaticAbility = &.{},
    event_abilities: []const state.EventAbility = &.{},
    pay_credits: ?state.PayCreditsSpec = null,
    // Installed ability data (flattened)
    initial_credit_counters: u16 = 0,
    take_credits_amount: u16 = 0,
    trash_on_empty: bool = false,
    initial_virus_counters: u16 = 0,
    initial_power_counters: u16 = 0,
    draw_on_take: u8 = 0,
    draw_on_empty: u8 = 0,
    clicks_on_empty: u8 = 0,
    click_draw_bonus: u8 = 0,
    auto_trash_at_credits: u8 = 0,
    draw_on_auto_trash: u8 = 0,
    place_credits_per_turn: bool = false,
    auto_take_credits: bool = false,
    subroutines: []const state.SubroutineSpec = &.{},
    trash_cost: ?u16 = null,
};

fn corpGainCreditsPlayAbility(comptime credits: u16, comptime draw: u8) state.AbilitySpec {
    return .{ .is_play = true, .on_use = &struct {
        fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
            const g = gameFromEffectContext(ctx);
            g.corp_credit += credits;
            if (draw > 0) try drawCards(g, .corp, draw);
        }
    }.play };
}

fn runnerGainCreditsPlayAbility(comptime credits: u16, comptime draw: u8, comptime lose_clicks: u8) state.AbilitySpec {
    return .{ .is_play = true, .on_use = &struct {
        fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
            const g = gameFromEffectContext(ctx);
            if (lose_clicks > 0) try spendClicks(g, .runner, lose_clicks);
            g.runner_credit += credits;
            if (draw > 0) try drawCards(g, .runner, draw);
            g.decision_side = .runner;
            g.legal_actions = try runnerOpeningActionsForState(g.ephemeralAllocator(), g);
        }
    }.play };
}

const GE = @import("game.zig");

fn beginPlutusTrashPrompt(g: *GE.Game, trashed_so_far: u8) !void {
    if (trashed_so_far >= 3 or g.corp_hand.items.len == 0) {
        g.systemMsg(.corp, 35073, "Plutus: Corp trashes {d} card(s) from HQ as additional rez cost.", .{trashed_so_far});
        return;
    }
    const allocator = g.ephemeralAllocator();
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    for (g.corp_hand.items) |c| {
        try choices.append(allocator, stringChoice(try allocator.dupe(u8, c.title)));
    }
    g.corp_prompt_state = .{
        .prompt_type = "plutus-trash-hq",
        .choices = try choices.toOwnedSlice(allocator),
        .ability_ref = .{ .source_instance_id = 0, .ability_index = trashed_so_far },
        .on_choice = &struct {
            fn choice(cctx: *state.EffectContext, ct: []const u8) anyerror!void {
                const cg = gameFromEffectContext(cctx);
                const ref = (cg.corp_prompt_state orelse return).ability_ref orelse return;
                const done = ref.ability_index;
                cg.corp_prompt_state = null;
                for (cg.corp_hand.items, 0..) |c, idx| {
                    if (std.mem.eql(u8, c.title, ct)) {
                        const trashed = cg.corp_hand.orderedRemove(idx);
                        try appendDiscardCard(cg, .corp, trashed);
                        break;
                    }
                }
                try beginPlutusTrashPrompt(cg, done + 1);
            }
        }.choice,
    };
    g.decision_side = .corp;
    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
}

fn showGamedragonHostPrompt(g: *GE.Game, gd_iid: u32, is_rehost: bool) !void {
    const allocator = g.ephemeralAllocator();
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    for (g.runner_rig_program.items, 0..) |prog, idx| {
        if (!isIcebreaker(prog)) continue;
        if (hasSubtype(prog, "AI")) continue;
        // When re-hosting, skip the current host
        if (is_rehost) {
            var is_current_host = false;
            for (prog.hosted.items) |h| {
                if (h.instance_id == gd_iid) { is_current_host = true; break; }
            }
            if (is_current_host) continue;
        }
        try choices.append(allocator, .{
            .kind = .card,
            .text = try std.fmt.allocPrint(allocator, "{d}|{s}", .{ idx, prog.title }),
            .card = .{ .title = prog.title, .code = prog.code, .side = .runner, .index = @intCast(idx) },
        });
    }
    if (choices.items.len == 0) return;
    try choices.append(allocator, stringChoice("No action"));
    g.runner_prompt_state = .{
        .prompt_type = "gamedragon-host",
        .choices = try choices.toOwnedSlice(allocator),
        .ability_ref = .{ .source_instance_id = gd_iid },
        .on_choice = &struct {
            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const cg = gameFromEffectContext(cctx);
                const ref = (cg.runner_prompt_state orelse return).ability_ref orelse return;
                const iid = ref.source_instance_id;
                cg.runner_prompt_state = null;
                if (std.mem.eql(u8, choice_text, "No action")) return;
                var parts = std.mem.splitScalar(u8, choice_text, '|');
                const idx_text = parts.next() orelse return;
                const prog_idx = std.fmt.parseInt(usize, idx_text, 10) catch return;
                if (prog_idx >= cg.runner_rig_program.items.len) return;
                // Find GAMEDRAGON: first in hardware, then in hosted on programs
                for (cg.runner_rig_hardware.items, 0..) |hw, hi| {
                    if (hw.instance_id == iid) {
                        const gd = cg.runner_rig_hardware.orderedRemove(hi);
                        try appendHostedCard(cg.arena.allocator(), &cg.runner_rig_program.items[prog_idx], gd);
                        cg.systemMsg(.runner, 35027, "GAMEDRAGON Pro hosts on {s}.", .{cg.runner_rig_program.items[prog_idx].title});
                        return;
                    }
                }
                // Check if hosted on a program (re-host case)
                for (cg.runner_rig_program.items) |*prog| {
                    for (prog.hosted.items, 0..) |h, hi| {
                        if (h.instance_id == iid) {
                            const gd = removeHostedCard(cg.arena.allocator(), prog, @intCast(hi)) catch return;
                            try appendHostedCard(cg.arena.allocator(), &cg.runner_rig_program.items[prog_idx], gd);
                            cg.systemMsg(.runner, 35027, "GAMEDRAGON Pro re-hosts on {s}.", .{cg.runner_rig_program.items[prog_idx].title});
                            return;
                        }
                    }
                }
            }
        }.choice,
    };
}

fn runnerRunEventPlayAbility(
    comptime target_kind: state.RunTargetKind,
    comptime lose_clicks: u8,
    comptime run_credits: u16,
    comptime run_rez_cost_bonus: u16,
    comptime successful_run_access_bonus: u8,
    comptime successful_run_draw_cards: u8,
) state.AbilitySpec {
    return .{
        .is_play = true,
        .on_use = &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.ephemeralAllocator();
                if (lose_clicks > 0) try spendClicks(g, .runner, lose_clicks);
                g.runner_prompt_state = .{
                    .prompt_type = "run-target",
                    .choices = try runTargetChoicesFor(allocator, target_kind, g.corp_servers.items),
                    .source_card = card.*,
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            // Capture source card's event abilities before clearing prompt
                            const source_event_abilities = if (cg.runner_prompt_state) |ps|
                                if (ps.source_card) |sc|
                                    if (lookupCardSpecByCode(sc.code orelse 0)) |spec| spec.event_abilities else &.{}
                                else
                                    &.{}
                            else
                                &.{};
                            cg.runner_prompt_state = null;
                            // Add floating effects for this run event
                            if (run_credits > 0) {
                                try addFloatingEffect(cg, .{ .kind = .run_credits, .duration = .end_of_run, .value = run_credits });
                            }
                            if (run_rez_cost_bonus > 0) {
                                try addFloatingEffect(cg, .{ .kind = .rez_cost_bonus, .duration = .end_of_run, .value = run_rez_cost_bonus });
                            }
                            if (successful_run_access_bonus > 0) {
                                try addFloatingEffect(cg, .{ .kind = .access_bonus, .duration = .end_of_run, .value = successful_run_access_bonus });
                            }
                            if (successful_run_draw_cards > 0) {
                                try addFloatingEffect(cg, .{ .kind = .successful_run_draw, .duration = .end_of_run, .value = successful_run_draw_cards });
                            }
                            try applyRunFromAbility(cg, choice_text, null);
                            // Attach run event card's event abilities to the run
                            if (cg.run) |*run| {
                                run.source_event_abilities = source_event_abilities;
                            }
                        }
                    }.choice,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.play,
    };
}

// Peer Review on_choice handler — handles peer-review-private, peer-review-install, peer-review-server
const peer_review_on_choice: *const fn (*state.EffectContext, []const u8) anyerror!void = &struct {
    fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
        const cg = gameFromEffectContext(cctx);
        const c_allocator = cg.ephemeralAllocator();
        const prompt = cg.corp_prompt_state orelse return error.NoPromptState;
        if (std.mem.eql(u8, prompt.prompt_type, "peer-review-private")) {
            const ref = prompt.ability_ref orelse return error.MissingAbilityRef;
            try beginPeerReviewInstallPrompt(cg, ref.source_instance_id, peer_review_on_choice);
            return;
        } else if (std.mem.eql(u8, prompt.prompt_type, "peer-review-install")) {
            for (prompt.choices) |ch| {
                if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                    if (ch.card) |card_ref| {
                        var server_choices: std.ArrayList(state.PromptChoice) = .empty;
                        defer server_choices.deinit(c_allocator);
                        for (cg.corp_servers.items, 0..) |_, si| {
                            if (si < 4) continue;
                            const name = try std.fmt.allocPrint(c_allocator, "Server {d}", .{si - 3});
                            try server_choices.append(c_allocator, stringChoice(name));
                        }
                        try server_choices.append(c_allocator, stringChoice("New remote"));
                        cg.corp_prompt_state = .{
                            .prompt_type = "peer-review-server",
                            .choices = try server_choices.toOwnedSlice(c_allocator),
                            .ability_ref = prompt.ability_ref,
                            .min_choices = card_ref.index orelse 0,
                            .on_choice = peer_review_on_choice,
                        };
                        cg.decision_side = .corp;
                        cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                        return;
                    }
                }
            }
            return error.UnsupportedChoice;
        } else if (std.mem.eql(u8, prompt.prompt_type, "peer-review-server")) {
            const card_index = prompt.min_choices;
            if (card_index >= cg.corp_hand.items.len) return error.InvalidCardIndex;
            const card_to_install = cg.corp_hand.items[card_index];
            try installCorpCardFromHand(cg, card_index, choice_text);
            cg.systemMsg(.corp, 35055, "Corp uses Peer Review to install {s}.", .{card_to_install.title});
            cg.corp_prompt_state = null;
            cg.decision_side = .corp;
            cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
        } else return error.UnsupportedChoice;
    }
}.choice;

// Scrounge on_choice handler — shared between the scrounge-install prompt and the
// runner-discard-to-deck pending effect prompt (both handled by the same function)
const scrounge_on_choice: *const fn (*state.EffectContext, []const u8) anyerror!void = &struct {
    fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
        const cg = gameFromEffectContext(cctx);
        const prompt = cg.runner_prompt_state orelse return error.NoPromptState;
        if (std.mem.eql(u8, prompt.prompt_type, "scrounge-install")) {
            const ref = prompt.ability_ref orelse return error.MissingAbilityRef;
            const source_card_ptr = findCardPtrByInstanceId(cg, ref.source_instance_id) orelse return error.MissingSourceCard;
            cg.runner_prompt_state = null;
            try cg.pending_effects.append(cg.backing_allocator, .{ .deferred_prompt = .{
                .card = source_card_ptr.*,
                .on_choice = scrounge_on_choice,
                .open_fn = &openRunnerDiscardToDeckPrompt,
            } });
            if (std.mem.eql(u8, choice_text, "No action")) {
                if (try resumePendingEffects(cg)) return;
                try restorePriorityAfterPrompt(cg);
                return;
            }
            for (cg.runner_discard.items, 0..) |c, idx| {
                if (!std.mem.eql(u8, c.title, choice_text)) continue;
                const c_card = cg.runner_discard.orderedRemove(idx);
                try cg.runner_hand.append(cg.backing_allocator, c_card);
                const hand_index: u8 = @intCast(cg.runner_hand.items.len - 1);
                try beginRunnerInstallFromHand(cg, hand_index, false);
                cg.systemMsg(.runner, 35004, "Runner uses Scrounge to install {s} from the heap.", .{c_card.title});
                if (hasActivePrompt(cg) or cg.pending_install != null) return;
                if (try resumePendingEffects(cg)) return;
                try restorePriorityAfterPrompt(cg);
                return;
            }
            return error.UnsupportedChoice;
        }
        if (std.mem.eql(u8, prompt.prompt_type, "runner-discard-to-deck")) {
            cg.runner_prompt_state = null;
            if (!std.mem.eql(u8, choice_text, "No action")) {
                for (cg.runner_discard.items, 0..) |c_card, idx| {
                    if (!std.mem.eql(u8, c_card.title, choice_text)) continue;
                    const bottomed = cg.runner_discard.orderedRemove(idx);
                    try cg.runner_deck.append(cg.backing_allocator, bottomed);
                    cg.systemMsg(.runner, 35004, "Runner uses Scrounge to put {s} on the bottom of the stack.", .{c_card.title});
                    break;
                }
            }
            try restorePriorityAfterPrompt(cg);
            return;
        }
        return error.UnsupportedChoice;
    }
}.choice;

pub const all_cards = [_]CardSpec{
    .{ .title = "The Syndicate: Profit over Principle", .side = .corp, .code = 30077, .card_type = "Identity" },
    .{ .title = "The Catalyst: Convention Breaker", .side = .runner, .code = 30076, .card_type = "Identity" },
    .{
        .title = "Haas-Bioroid: Precision Design",
        .side = .corp,
        .code = 30035,
        .card_type = "Identity",
        .static_abilities = &.{.{ .kind = .hand_size, .value = 1 }},
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.corp_discard.items.len == 0) return;
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_discard.items, 0..) |card, idx| {
                        try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                    }
                    try choices.append(allocator, stringChoice("Done"));
                    g.corp_prompt_state = .{
                        .prompt_type = "precision-design-archive",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = null,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Jinteki: Restoring Humanity",
        .side = .corp,
        .code = 30043,
        .card_type = "Identity",
        .event_abilities = &.{.{
            .event = .corp_end_turn,
            .automatic_priority = state.Priority.gain_credits,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.corp_discard.items.len > 0) {
                        g.corp_credit += 1;
                        g.systemMsg(.corp, 30043, "Corp uses Jinteki: Restoring Humanity to gain 1 [credit].", .{});
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "NBN: Reality Plus",
        .side = .corp,
        .code = 30051,
        .card_type = "Identity",
        .event_abilities = &.{.{
            .event = .runner_gain_tag,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.turn_events.runner_gain_tag_count != 1) return; // first-event? check
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    try choices.append(allocator, stringChoice("Gain 2 [Credits]"));
                    try choices.append(allocator, stringChoice("Draw 2 cards"));
                    g.corp_prompt_state = .{
                        .prompt_type = "reality-plus",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = g.corp_identity,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                cg.systemMsg(.corp, 30051, "Corp uses NBN: Reality Plus to {s}.", .{choice_text});
                                if (std.mem.eql(u8, choice_text, "Gain 2 [Credits]")) {
                                    cg.corp_credit += 2;
                                } else if (std.mem.eql(u8, choice_text, "Draw 2 cards")) {
                                    try drawCards(cg, .corp, 2);
                                } else return error.UnsupportedChoice;
                                cg.corp_prompt_state = null;
                                cg.runner_prompt_state = null;
                                if (cg.run != null) {
                                    cg.decision_side = .runner;
                                    cg.legal_actions = try runnerOpeningActionsForState(cg.ephemeralAllocator(), cg);
                                } else {
                                    cg.decision_side = .corp;
                                    cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                                }
                            }
                        }.choice,
                    };
                    g.runner_prompt_state = .{
                        .prompt_type = "waiting",
                        .choices = &.{},
                        .source_card = null,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Weyland Consortium: Built to Last",
        .side = .corp,
        .code = 30059,
        .card_type = "Identity",
        .event_abilities = &.{.{
            .event = .advance,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    g.corp_credit += 2;
                    g.systemMsg(.corp, 30059, "Corp uses Weyland Consortium: Built to Last to gain 2 [credits].", .{});
                }
            }.handle,
        }},
    },
    .{
        .title = "Ren\xc3\xa9 \"Loup\" Arcemont: Party Animal",
        .side = .runner,
        .code = 30001,
        .card_type = "Identity",
        .event_abilities = &.{.{
            .event = .runner_trash_corp_card,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.turn_events.runner_trash_corp_card_count == 1) { // first-event?
                        g.runner_credit += 1;
                        try drawCards(g, .runner, 1);
                        g.systemMsg(.runner, 30001, "Runner uses Ren\xe9 \"Loup\" Arcemont to gain 1 [credit] and draw 1 card.", .{});
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "T\xc4\x81o Salonga: Telepresence Magician",
        .side = .runner,
        .code = 30019,
        .card_type = "Identity",
        .event_abilities = blk: {
            const H = struct {
                fn trigger(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    var ice_count: usize = 0;
                    for (g.corp_servers.items) |server| {
                        ice_count += server.ices.items.len;
                    }
                    if (ice_count < 2) return;
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_servers.items, 0..) |server, si| {
                        for (server.ices.items, 0..) |ice, ii| {
                            const text = try std.fmt.allocPrint(allocator, "{d}|{d}|{s}", .{ si, ii, ice.title });
                            try choices.append(allocator, .{ .kind = .card, .text = text, .card = .{ .title = ice.title, .side = .corp, .index = @intCast(ii) } });
                        }
                    }
                    try choices.append(allocator, stringChoice("Done"));
                    g.runner_prompt_state = .{
                        .prompt_type = "tao-swap-ice",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = null,
                        .min_choices = 0,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            };
            break :blk &.{
                .{ .event = .agenda_scored, .handler = &H.trigger },
                .{ .event = .agenda_stolen, .handler = &H.trigger },
            };
        },
    },
    .{
        .title = "Zahya Sadeghi: Versatile Smuggler",
        .side = .runner,
        .code = 30010,
        .card_type = "Identity",
        .event_abilities = &.{.{
            .event = .successful_run_ends,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.turn_events.successful_run_ends_count != 1) return; // once per turn
                    const run = g.run orelse return;
                    if (run.server != .hq and run.server != .rnd) return;
                    const accessed = run.accessed_count;
                    if (accessed == 0) return;
                    // Optional prompt: can decline to save once-per-turn ability for later run
                    const allocator = g.ephemeralAllocator();
                    const choices = try allocator.alloc(state.PromptChoice, 2);
                    choices[0] = stringChoice("Yes");
                    choices[1] = stringChoice("No");
                    g.runner_prompt_state = .{
                        .prompt_type = "zahya-gain",
                        .choices = choices,
                        .source_card = g.runner_identity,
                        .min_choices = @intCast(accessed), // stash accessed count for resolution
                        .on_choice = &struct {
                            fn handle(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                if (std.mem.eql(u8, choice_text, "Yes")) {
                                    const c_accessed = cg.runner_prompt_state.?.min_choices;
                                    cg.runner_credit += c_accessed;
                                    cg.systemMsg(.runner, 30010, "Runner uses Zahya to gain {d} [credit{s}].", .{ c_accessed, if (c_accessed != 1) "s" else "" });
                                }
                                cg.runner_prompt_state = null;
                                cg.decision_side = .runner;
                                cg.legal_actions = try runnerOpeningActionsForState(cg.ephemeralAllocator(), cg);
                            }
                        }.handle,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{ .title = "Offworld Office", .side = .corp, .code = 30067, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 4, .install = .{ .kind = .corp_remote_only }, .event_abilities = &.{.{
        .event = .agenda_scored,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                g.corp_credit += 7;
                g.systemMsg(.corp, 0, "Corp gains 7 [credits].", .{});
            }
        }.handle,
    }} },
    .{ .title = "Send a Message", .side = .corp, .code = 30069, .card_type = "Agenda", .agenda_points = 3, .advancement_requirement = 5, .install = .{ .kind = .corp_remote_only }, .event_abilities = &.{
        .{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    _ = try beginRezIceFreePromptForScore(g, card.*);
                }
            }.handle,
        },
        .{
            .event = .agenda_stolen,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    _ = try beginRezIceFreePrompt(g, card.*);
                }
            }.handle,
        },
    } },
    .{ .title = "Superconducting Hub", .side = .corp, .code = 30070, .card_type = "Agenda", .agenda_points = 1, .advancement_requirement = 3, .install = .{ .kind = .corp_remote_only }, .static_abilities = &.{.{ .kind = .hand_size, .value = 2 }}, .event_abilities = &.{.{
        .event = .agenda_scored,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                try drawCards(g, .corp, 2);
                g.systemMsg(.corp, 30070, "Corp draws 2 cards.", .{});
            }
        }.handle,
    }} },
    .{
        .title = "Orbital Superiority",
        .side = .corp,
        .code = 30068,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 4,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{ .event = .agenda_scored, .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                if (is_runner_tagged(g.runner_tag)) {
                    try trashRandomRunnerHandCards(g, 4);
                    g.systemMsg(.corp, 30068, "Corp uses Orbital Superiority to do 4 meat damage.", .{});
                    updateTerminalState(g);
                } else {
                    _ = try addRunnerTag(g, 1);
                    g.systemMsg(.corp, 30068, "Corp uses Orbital Superiority to give Runner 1 tag.", .{});
                }
            }
        }.handle }},
    },
    .{
        .title = "Nico Campaign",
        .side = .corp,
        .code = 30037,
        .card_type = "Asset",
        .cost = 2,
        .trash_cost = 2,
        .install = .{ .kind = .corp_remote_only },
        .initial_credit_counters = 9,
        .take_credits_amount = 3,
        .trash_on_empty = true,
        .draw_on_empty = 1,
        .event_abilities = &.{.{
            .event = .corp_turn_begins,
            .automatic_priority = state.Priority.draw_cards,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (card.credit_counter == 0) return;
                    const g = gameFromEffectContext(ctx);
                    const take = @min(card.credit_counter, card.take_credits_amount);
                    card.credit_counter -= take;
                    g.corp_credit += take;
                    g.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to take {d} [credit{s}].", .{
                        card.title, take, if (take != 1) "s" else "",
                    });
                    if (card.trash_on_empty and card.credit_counter == 0) {
                        if (card.draw_on_empty > 0) try drawCards(g, .corp, card.draw_on_empty);
                        try trashCorpServerCardByInstanceId(g, card.instance_id);
                    }
                }
            }.handle,
        }},
    },
    .{ .title = "Regolith Mining License", .side = .corp, .code = 30071, .card_type = "Asset", .cost = 2, .trash_cost = 3, .install = .{ .kind = .corp_remote_only }, .initial_credit_counters = 15, .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .label = "Take 3 [Credits] from this card",
        .on_use = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const amount: u16 = @min(card.credit_counter, 3);
                g.corp_credit += amount;
                card.credit_counter -= amount;
                g.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to gain {d} [credit{s}].", .{
                    card.title, amount, if (amount != 1) "s" else "",
                });
                if (card.credit_counter == 0) {
                    try trashCorpServerCardByInstanceId(g, card.instance_id);
                }
            }
        }.handle,
    }} },
    .{ .title = "Urtica Cipher", .side = .corp, .code = 30045, .card_type = "Asset", .cost = 0, .trash_cost = 2, .static_abilities = &.{.{ .kind = .can_advance }}, .install = .{ .kind = .corp_remote_only }, .event_abilities = &.{.{
        .event = .access,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                _ = try beginNetDamageOnAccessPrompt(gameFromEffectContext(ctx), card.*);
            }
        }.handle,
    }} },
    .{ .title = "Government Subsidy", .side = .corp, .code = 30064, .card_type = "Operation", .cost = 10, .abilities = &.{corpGainCreditsPlayAbility(15, 0)} },
    .{ .title = "Hedge Fund", .side = .corp, .code = 30075, .card_type = "Operation", .cost = 5, .abilities = &.{corpGainCreditsPlayAbility(9, 0)} },
    .{
        .title = "Seamless Launch",
        .side = .corp,
        .code = 30040,
        .card_type = "Operation",
        .cost = 1,
        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.ephemeralAllocator();
                const choices = try installedNotThisTurnChoices(allocator, g.corp_servers.items);
                if (choices.len == 0) {
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                    return;
                }
                g.corp_prompt_state = .{
                    .prompt_type = "seamless-advance",
                    .choices = choices,
                    .source_card = card.*,
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            const advanced_card = try addAdvancementCounter(cg, choice_text, 2);
                            cg.systemMsg(.corp, 30040, "Corp uses Seamless Launch to advance {s} 2 times.", .{advanced_card.title});
                            cg.corp_prompt_state = null;
                            cg.decision_side = .corp;
                            cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                        }
                    }.choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play }},
    },
    .{
        .title = "Predictive Planogram",
        .side = .corp,
        .code = 30056,
        .card_type = "Operation",
        .cost = 0,
        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.ephemeralAllocator();
                g.corp_prompt_state = .{
                    .prompt_type = "other",
                    .choices = try predictive_planogram_choices(allocator, g.runner_tag),
                    .source_card = card.*,
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            cg.systemMsg(.corp, 30056, "Corp uses Predictive Planogram to {s}.", .{choice_text});
                            if (std.mem.eql(u8, choice_text, "Gain 3 [Credits]")) {
                                cg.corp_credit += 3;
                            } else if (std.mem.eql(u8, choice_text, "Draw 3 cards")) {
                                try drawCards(cg, .corp, 3);
                            } else if (std.mem.eql(u8, choice_text, "Gain 3 [Credits] and draw 3 cards")) {
                                cg.corp_credit += 3;
                                try drawCards(cg, .corp, 3);
                            } else return error.UnsupportedChoice;
                            cg.corp_prompt_state = null;
                            cg.runner_prompt_state = null;
                            cg.decision_side = .corp;
                            cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                        }
                    }.choice,
                };
                g.runner_prompt_state = .{
                    .prompt_type = "waiting",
                    .choices = &.{},
                    .source_card = null,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play }},
    },
    .{
        .title = "Public Trail",
        .side = .corp,
        .code = 30057,
        .card_type = "Operation",
        .cost = 4,
        .abilities = &.{.{
            .is_play = true,
            .req = &struct {
                fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    return runner_had_successful_run_last_turn(g);
                }
            }.req,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    if (!runner_had_successful_run_last_turn(g)) {
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                        return;
                    }
                    g.corp_prompt_state = .{
                        .prompt_type = "waiting",
                        .choices = &.{},
                        .source_card = null,
                    };
                    g.runner_prompt_state = .{
                        .prompt_type = "other",
                        .choices = try public_trail_choices(allocator, g.runner_credit),
                        .source_card = card.*,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                cg.systemMsg(.runner, 30057, "Runner uses Public Trail to {s}.", .{choice_text});
                                if (std.mem.eql(u8, choice_text, "Take 1 tag")) {
                                    if (try addRunnerTag(cg, 1)) return; // Event handler opened prompt
                                } else if (std.mem.eql(u8, choice_text, "Pay 8 [Credits]")) {
                                    try spendCredits(cg, .runner, 8);
                                } else return error.UnsupportedChoice;
                                cg.runner_prompt_state = null;
                                cg.corp_prompt_state = null;
                                cg.decision_side = .corp;
                                cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                            }
                        }.choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.play,
        }},
    },
    .{
        .title = "Retribution",
        .side = .corp,
        .code = 30065,
        .card_type = "Operation",
        .cost = 1,
        .abilities = &.{.{ .is_play = true, .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                return is_runner_tagged(g.runner_tag) and
                    (g.runner_rig_hardware.items.len > 0 or g.runner_rig_program.items.len > 0);
            }
        }.req, .on_use = &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.ephemeralAllocator();
                if (!is_runner_tagged(g.runner_tag)) {
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                    return;
                }
                const choices = try retribution_choices(allocator, g.runner_rig_hardware.items, g.runner_rig_program.items);
                if (choices.len == 0) {
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                    return;
                }
                g.corp_prompt_state = .{
                    .prompt_type = "retribution-trash",
                    .choices = choices,
                    .source_card = card.*,
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            var pieces = std.mem.splitScalar(u8, choice_text, '|');
                            const zone = pieces.next() orelse return error.UnsupportedChoice;
                            const index_text = pieces.next() orelse return error.UnsupportedChoice;
                            const index = try std.fmt.parseInt(usize, index_text, 10);
                            if (std.mem.eql(u8, zone, "h")) {
                                if (index >= cg.runner_rig_hardware.items.len) return error.UnsupportedChoice;
                                const trashed = cg.runner_rig_hardware.orderedRemove(index);
                                cg.systemMsg(.corp, 30065, "Corp uses Retribution to trash {s}.", .{trashed.title});
                                try cg.runner_discard.append(cg.backing_allocator, trashed);
                            } else if (std.mem.eql(u8, zone, "p")) {
                                if (index >= cg.runner_rig_program.items.len) return error.UnsupportedChoice;
                                const trashed = cg.runner_rig_program.orderedRemove(index);
                                cg.systemMsg(.corp, 30065, "Corp uses Retribution to trash {s}.", .{trashed.title});
                                try cg.runner_discard.append(cg.backing_allocator, trashed);
                                if (cg.runner_memory) |*mem| {
                                    const mu = trashed.runner_install.mu_cost;
                                    if (mem.used >= mu) mem.used -= mu else mem.used = 0;
                                    mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
                                }
                            } else return error.UnsupportedChoice;
                            cg.corp_prompt_state = null;
                            cg.decision_side = .corp;
                            cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                        }
                    }.choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play }},
    },
    .{
        .title = "Manegarm Skunkworks",
        .side = .corp,
        .code = 30042,
        .card_type = "Upgrade",
        .cost = 2,
        .trash_cost = 3,
        .install = .{ .kind = .corp_server_choice },
        .event_abilities = &.{.{
            .event = .server_approached,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (!card.rezzed) return;
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    if (g.runner_click >= 2) {
                        try choices.append(allocator, stringChoice(try allocator.dupe(u8, "Spend [Click][Click]")));
                    }
                    if (g.runner_credit >= 5) {
                        try choices.append(allocator, stringChoice(try allocator.dupe(u8, "Pay 5 [Credits]")));
                    }
                    try choices.append(allocator, stringChoice(try allocator.dupe(u8, "End the run")));
                    g.runner_prompt_state = .{
                        .prompt_type = "manegarm-tax",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = card.*,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                cg.systemMsg(.runner, 30042, "Runner uses Manegarm Skunkworks to {s}.", .{choice_text});
                                const c_allocator = cg.ephemeralAllocator();
                                var run = &cg.run.?;
                                if (std.mem.eql(u8, choice_text, "Spend [Click][Click]")) {
                                    cg.runner_click -= 2;
                                } else if (std.mem.eql(u8, choice_text, "Pay 5 [Credits]")) {
                                    cg.runner_credit -= 5;
                                } else if (std.mem.eql(u8, choice_text, "End the run")) {
                                    try completeUnsuccessfulRun(cg);
                                    return;
                                } else return error.UnsupportedChoice;
                                cg.runner_prompt_state = null;
                                try applySuccessfulRunEffects(cg);
                                if (try prepareNextAccess(cg)) {
                                    run.phase = .success;
                                    if (cg.runner_prompt_state) |ps| {
                                        cg.decision_side = .runner;
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .runner, ps);
                                    } else {
                                        cg.decision_side = .runner;
                                        cg.legal_actions = try continueActionsForRun(c_allocator, .runner, run.*);
                                    }
                                    return;
                                }
                                try completeSuccessfulRunWithCorpPriority(cg);
                            }
                        }.choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{ .title = "AMAZE Amusements", .side = .corp, .code = 30058, .card_type = "Upgrade", .cost = 1, .trash_cost = 3, .install = .{ .kind = .corp_server_choice }, .event_abilities = &.{.{
        .event = .access,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                try addFloatingEffect(gameFromEffectContext(ctx), .{
                    .kind = .tags_on_steal,
                    .duration = .end_of_run,
                    .value = 2,
                });
            }
        }.handle,
    }} },
    .{
        .title = "Brân 1.0",
        .side = .corp,
        .code = 30039,
        .card_type = "ICE",
        .subtypes = &.{ "Bioroid", "Barrier" },
        .cost = 6,
        .strength = 6,
        .install = .{ .kind = .corp_server_choice },
        .subroutines = &.{
            .{ .resolve = &resolveInstallIceFromHqArchives, .label = "Install a card from HQ or Archives" },
            .{ .resolve = &resolveEndTheRun, .label = "End the run" },
            .{ .resolve = &resolveEndTheRun, .label = "End the run" },
        },
        .abilities = &.{.{ .on_use = &encounterBioroidHandler, .allow_opponent_use = true, .req = &isInEncounter, .cost = .{ .clicks = 1 }, .break_count = 1 }},
    },
    .{ .title = "Palisade", .side = .corp, .code = 30072, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 3, .strength = 2, .install = .{ .kind = .corp_server_choice }, .static_abilities = &.{.{ .kind = .self_strength, .value = 2, .req = &struct {
        fn check(ctx: *const state.EffectContext, card: *const state.CardInstance, _: ?*const state.CardInstance) i16 {
            const g = gameFromConstEffectContext(ctx);
            for (g.corp_servers.items) |server| {
                if (!std.mem.startsWith(u8, server.name, "remote")) continue;
                for (server.ices.items) |ice| {
                    if (ice.instance_id == card.instance_id) return 1;
                }
            }
            return 0;
        }
    }.check }}, .subroutines = &.{
        .{ .resolve = &resolveEndTheRun, .label = "End the run" },
    } },
    .{ .title = "Diviner", .side = .corp, .code = 30046, .card_type = "ICE", .subtypes = &.{ "Code Gate", "AP" }, .cost = 2, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolveNetDamageConditionalEtr, .amount = 1, .label = "Sub 0" },
    } },
    .{ .title = "Whitespace", .side = .corp, .code = 30074, .card_type = "ICE", .subtypes = &.{"Code Gate"}, .cost = 2, .strength = 0, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolveRunnerLosesCredits, .amount = 3, .label = "Runner loses 3 [Credits]" },
        .{ .resolve = &resolveRunnerLosesCreditsOrEtr, .amount = 6, .label = "Sub 1" },
    } },
    .{ .title = "Karunā", .side = .corp, .code = 30047, .card_type = "ICE", .subtypes = &.{ "Sentry", "AP" }, .cost = 4, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolveNetDamageThenJackOut, .amount = 2, .label = "Sub 0" },
        .{ .resolve = &resolveNetDamage, .amount = 2, .label = "Do 2 net damage" },
    } },
    .{ .title = "Tithe", .side = .corp, .code = 30073, .card_type = "ICE", .subtypes = &.{ "Sentry", "AP" }, .cost = 1, .strength = 1, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolveNetDamage, .amount = 1, .label = "Do 1 net damage" },
        .{ .resolve = &resolveCorpGainsCredits, .amount = 1, .label = "Corp gains 1 [Credits]" },
    } },
    .{
        .title = "Funhouse",
        .side = .corp,
        .code = 30054,
        .card_type = "ICE",
        .subtypes = &.{"Code Gate"},
        .cost = 5,
        .strength = 4,
        .install = .{ .kind = .corp_server_choice },
        .subroutines = &.{
            .{ .resolve = &resolveGiveTagOrPayCredits, .amount = 4, .label = "Sub 0" },
        },
        .event_abilities = &.{.{
            .event = .ice_encountered,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    try choices.append(allocator, stringChoice("Take 1 tag"));
                    try choices.append(allocator, stringChoice("End the run"));
                    g.runner_prompt_state = .{
                        .prompt_type = "funhouse-encounter",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = null,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                cg.systemMsg(.runner, 30054, "Runner uses Funhouse to {s}.", .{choice_text});
                                if (std.mem.eql(u8, choice_text, "Take 1 tag")) {
                                    if (try addRunnerTag(cg, 1)) return; // Event handler opened prompt
                                    cg.runner_prompt_state = null;
                                    // Continue encounter normally
                                    const run = cg.run orelse return error.NoRunInProgress;
                                    const ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                                    const target_server = try findServerByRunPath(cg.corp_servers.items, run.server);
                                    const server = target_server.slot;
                                    const ice_count = server.ices.items.len;
                                    const actual_ice_idx = ice_count - 1 - ice_idx;
                                    const c_ice = server.ices.items[actual_ice_idx];
                                    cg.decision_side = .runner;
                                    cg.legal_actions = try encounterActionsForState(cg.ephemeralAllocator(), cg, c_ice);
                                } else if (std.mem.eql(u8, choice_text, "End the run")) {
                                    cg.runner_prompt_state = null;
                                    try completeUnsuccessfulRun(cg);
                                } else return error.UnsupportedChoice;
                            }
                        }.choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{ .title = "Creative Commission", .side = .runner, .code = 30020, .card_type = "Event", .cost = 1, .abilities = &.{runnerGainCreditsPlayAbility(5, 0, 1)} },
    .{ .title = "Jailbreak", .side = .runner, .code = 30028, .card_type = "Event", .cost = 0, .abilities = &.{runnerRunEventPlayAbility(.hq_and_rnd_only, 0, 0, 0, 1, 0)}, .event_abilities = &.{.{
        .event = .successful_run,
        .automatic_priority = state.Priority.draw_cards,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                try drawCards(g, .runner, 1);
                g.systemMsg(.runner, 30028, "Runner uses Jailbreak to draw 1 card.", .{});
            }
        }.handle,
    }} },
    .{ .title = "Overclock", .side = .runner, .code = 30029, .card_type = "Event", .cost = 1, .abilities = &.{runnerRunEventPlayAbility(.any_runnable, 0, 5, 0, 0, 0)} },
    .{ .title = "Sure Gamble", .side = .runner, .code = 30030, .card_type = "Event", .cost = 5, .abilities = &.{runnerGainCreditsPlayAbility(9, 0, 0)} },
    .{ .title = "Tread Lightly", .side = .runner, .code = 30012, .card_type = "Event", .cost = 1, .abilities = &.{runnerRunEventPlayAbility(.any_runnable, 0, 0, 3, 0, 0)} },
    .{
        .title = "Mutual Favor",
        .side = .runner,
        .code = 30011,
        .card_type = "Event",
        .cost = 0,
        .abilities = &.{.{
            .is_play = true,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Search deck for first icebreaker, add to hand, shuffle deck
                    const deck = &g.runner_deck;
                    var target_index: ?usize = null;
                    for (deck.items, 0..) |candidate, idx| {
                        if (isIcebreaker(candidate)) {
                            target_index = idx;
                            break;
                        }
                    }
                    if (target_index) |idx| {
                        const chosen = deck.orderedRemove(idx);
                        try g.runner_hand.append(g.backing_allocator, chosen);
                        try shuffleDeck(g, .runner);
                    }
                    g.decision_side = .runner;
                    g.legal_actions = try runnerOpeningActionsForState(
                        g.ephemeralAllocator(),
                        g,
                    );
                }
            }.play,
        }},
    },
    .{
        .title = "Wildcat Strike",
        .side = .runner,
        .code = 30002,
        .card_type = "Event",
        .cost = 2,
        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.ephemeralAllocator();
                g.runner_prompt_state = .{
                    .prompt_type = "waiting",
                    .choices = &.{},
                    .source_card = null,
                };
                g.corp_prompt_state = .{
                    .prompt_type = "other",
                    .choices = try wildcat_strike_choices(allocator),
                    .source_card = card.*,
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            cg.systemMsg(.corp, 30002, "Corp uses Wildcat Strike to {s}.", .{choice_text});
                            if (std.mem.eql(u8, choice_text, "Runner gains 6 [Credits]")) {
                                cg.runner_credit += 6;
                            } else if (std.mem.eql(u8, choice_text, "Runner draws 4 cards")) {
                                try drawCards(cg, .runner, 4);
                            } else return error.UnsupportedChoice;
                            cg.corp_prompt_state = null;
                            cg.runner_prompt_state = null;
                            cg.decision_side = .runner;
                            cg.legal_actions = try runnerOpeningActionsForState(
                                cg.ephemeralAllocator(),
                                cg,
                            );
                        }
                    }.choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play }},
    },
    .{ .title = "VRcation", .side = .runner, .code = 30021, .card_type = "Event", .cost = 1, .abilities = &.{runnerGainCreditsPlayAbility(0, 4, 1)} },
    .{ .title = "Docklands Pass", .side = .runner, .code = 30013, .card_type = "Hardware", .cost = 2, .runner_install = .{ .kind = .hardware }, .static_abilities = &.{.{ .kind = .hq_access, .value = 1 }} },
    .{ .title = "Pennyshaver", .side = .runner, .code = 30014, .card_type = "Hardware", .cost = 3, .runner_install = .{ .kind = .hardware }, .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .label = "Gain [Credits]",
        .on_use = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const total = @as(u16, card.credit_counter) + 1;
                g.runner_credit += total;
                card.credit_counter = 0;
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                    card.title, total, if (total != 1) "s" else "",
                });
            }
        }.handle,
    }}, .event_abilities = &.{.{
        .event = .successful_run_ends,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                card.credit_counter += 1;
                g.systemMsg(.runner, card.code orelse 0, "Runner places 1 [credit] on {s}.", .{card.title});
            }
        }.handle,
    }} },
    .{ .title = "DZMZ Optimizer", .side = .runner, .code = 30022, .card_type = "Hardware", .cost = 2, .runner_install = .{ .kind = .hardware }, .static_abilities = &.{
        .{ .kind = .mu, .value = 1 },
        .{ .kind = .install_cost, .value = -1, .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance, target: ?*const state.CardInstance) i16 {
                const g = gameFromConstEffectContext(ctx);
                const card = target orelse return 0;
                return if (card.runner_install.kind == .program and g.turn_events.programs_installed_this_turn == 0) 1 else 0;
            }
        }.req },
    } },
    .{
        .title = "Red Team",
        .side = .runner,
        .code = 30018,
        .card_type = "Resource",
        .cost = 5,
        .runner_install = .{ .kind = .resource },
        .initial_credit_counters = 12,
        .take_credits_amount = 3,
        .trash_on_empty = true,
        .abilities = &.{.{
            .cost = .{ .clicks = 1 },
            .label = "Make a run on a central server",
            .req = &struct {
                fn check(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    return !g.turn_events.made_run_on_hq or !g.turn_events.made_run_on_rnd or !g.turn_events.made_run_on_archives;
                }
            }.check,
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    const choices = try centralNotRunThisTurnChoices(allocator, g.turn_events);
                    if (choices.len == 0) return;
                    g.runner_prompt_state = .{
                        .prompt_type = prompt_run_central,
                        .choices = choices,
                        .source_card = card.*,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.handle,
        }}, .event_abilities = &.{.{
            .event = .successful_run_ends,
            .automatic_priority = state.Priority.gain_credits,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (card.credit_counter == 0) return;
                    const g = gameFromEffectContext(ctx);
                    const run = g.run orelse return;
                    if (run.source_instance_id == null or run.source_instance_id.? != card.instance_id) return;
                    const take = @min(card.credit_counter, card.take_credits_amount);
                    card.credit_counter -= take;
                    g.runner_credit += take;
                    g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                        card.title, take, if (take != 1) "s" else "",
                    });
                    if (card.trash_on_empty and card.credit_counter == 0) {
                        try trashRunnerRigCardByInstanceId(g, card.instance_id);
                    }
                }
            }.handle,
        }},
    },
    .{ .title = "Smartware Distributor", .side = .runner, .code = 30033, .card_type = "Resource", .cost = 0, .runner_install = .{ .kind = .resource }, .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .label = "Place 3 [Credits] on this card",
        .on_use = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.credit_counter += 3;
            }
        }.handle,
    }}, .event_abilities = &.{.{
        .event = .runner_turn_begins,
        .automatic_priority = state.Priority.gain_credits,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                if (card.credit_counter == 0) return;
                const g = gameFromEffectContext(ctx);
                card.credit_counter -= 1;
                g.runner_credit += 1;
                g.systemMsg(.runner, card.code orelse 0, "Runner gains 1 [credit] from {s}.", .{card.title});
            }
        }.handle,
    }} },
    .{ .title = "Telework Contract", .side = .runner, .code = 30027, .card_type = "Resource", .cost = 1, .runner_install = .{ .kind = .resource }, .initial_credit_counters = 9, .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .once_per_turn = true,
        .label = "Take 3 [Credits] from this card",
        .on_use = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const amount: u16 = @min(card.credit_counter, 3);
                g.runner_credit += amount;
                card.credit_counter -= amount;
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                    card.title, amount, if (amount != 1) "s" else "",
                });
                if (card.credit_counter == 0) {
                    try trashRunnerRigCardByInstanceId(g, card.instance_id);
                }
            }
        }.handle,
    }} },
    .{ .title = "Verbal Plasticity", .side = .runner, .code = 30034, .card_type = "Resource", .cost = 3, .runner_install = .{ .kind = .resource }, .click_draw_bonus = 1 },
    .{ .title = "Carmen", .side = .runner, .code = 30015, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer" }, .cost = 5, .strength = 2, .runner_install = .{ .kind = .program, .install_cost_reduction_if_successful_run = 2 }, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 1 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 2, .pump_amount = 3 },
    } },
    .{ .title = "Cleaver", .side = .runner, .code = 30006, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Fracter" }, .cost = 3, .strength = 3, .runner_install = .{ .kind = .program }, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 2 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 2, .pump_amount = 1 },
    } },
    .{ .title = "Mayfly", .side = .runner, .code = 30032, .card_type = "Program", .subtypes = &.{ "Icebreaker", "AI" }, .cost = 1, .strength = 1, .runner_install = .{ .kind = .program, .mu_cost = 2 }, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 1 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 1, .pump_amount = 1 },
    }, .event_abilities = &.{.{
        .event = .run_ends,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, self_card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                if (!hasFloatingEffectFromSource(g, .icebreaker_broke, self_card.instance_id)) return;
                var i: usize = 0;
                while (i < g.runner_rig_program.items.len) : (i += 1) {
                    const card = g.runner_rig_program.items[i];
                    if (card.code == null or self_card.code == null) continue;
                    if (card.code.? != self_card.code.?) continue;
                    if (!hasFloatingEffectFromSource(g, .icebreaker_broke, card.instance_id)) continue;
                    const trashed = g.runner_rig_program.orderedRemove(i);
                    try appendDiscardCard(g, .runner, trashed);
                    return;
                }
            }
        }.handle,
    }} },
    .{ .title = "Unity", .side = .runner, .code = 30026, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Decoder" }, .cost = 3, .strength = 1, .runner_install = .{ .kind = .program }, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 1 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 1, .pump_amount_fn = &struct {
            fn amount(ctx: *const state.EffectContext, _: *const state.CardInstance) u8 {
                return @intCast(countInstalledIcebreakers(gameFromConstEffectContext(ctx)));
            }
        }.amount },
    } },
    .{
        .title = "Conduit",
        .side = .runner,
        .code = 30024,
        .card_type = "Program",
        .cost = 4,
        .runner_install = .{ .kind = .program },
        .static_abilities = &.{.{
            .kind = .rd_access,
            .value = 1,
            .req = &struct {
                fn req(_: *const state.EffectContext, source: *const state.CardInstance, _: ?*const state.CardInstance) i16 {
                    return @intCast(source.virus_counter);
                }
            }.req,
        }},
        .abilities = &.{.{
            .cost = .{ .clicks = 1 },
            .label = "Run on R&D",
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    try applyRunFromAbility(gameFromEffectContext(ctx), "R&D", card.instance_id);
                }
            }.handle,
        }},
        .event_abilities = &.{.{
            .event = .successful_run_ends,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const run = g.run orelse return;
                    if (run.server != .rnd) return;
                    // Auto-place virus counter (oracle auto-resolves to yes)
                    card.virus_counter += 1;
                }
            }.handle,
        }},
    },
    .{ .title = "Leech", .side = .runner, .code = 30008, .card_type = "Program", .cost = 1, .runner_install = .{ .kind = .program }, .event_abilities = &.{.{
        .event = .successful_run_ends,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const run = g.run orelse return;
                if (!run.server.isCentral()) return;
                card.virus_counter += 1;
            }
        }.handle,
    }}, .abilities = &.{.{
        .on_use = &encounterLeechHandler,
        .label = "Give -1 strength to encountered ICE",
        .req = &struct {
            fn check(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                if (card.virus_counter == 0) return false;
                return isInEncounter(ctx, card);
            }
        }.check,
    }} },
    // --- System Gateway cards beyond beginner/intermediate ---
    .{ .title = "Buzzsaw", .side = .runner, .code = 30005, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Decoder" }, .cost = 4, .strength = 3, .runner_install = .{ .kind = .program }, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 2 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 3, .pump_amount = 1 },
    } },
    .{ .title = "Echelon", .side = .runner, .code = 30025, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer" }, .cost = 3, .strength = 0, .runner_install = .{ .kind = .program }, .static_abilities = &.{.{
        .kind = .self_strength,
        .value = 1,
        .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance, _: ?*const state.CardInstance) i16 {
                return @intCast(countInstalledIcebreakers(gameFromConstEffectContext(ctx)));
            }
        }.req,
    }}, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 1 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 3, .pump_amount = 2 },
    } },
    .{ .title = "Marjanah", .side = .runner, .code = 30016, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Fracter" }, .cost = 0, .strength = 1, .runner_install = .{ .kind = .program }, .static_abilities = &.{.{
        .kind = .break_cost,
        .value = -1,
        .req = &struct {
            fn req(ctx: *const state.EffectContext, source: *const state.CardInstance, target: ?*const state.CardInstance) i16 {
                const g = gameFromConstEffectContext(ctx);
                const modified = target orelse return 0;
                if (modified.code == null or source.code == null) return 0;
                return if (modified.code.? == source.code.? and g.runner_successful_run_this_turn) 1 else 0;
            }
        }.req,
    }}, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 2, .break_count = 1 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 1, .pump_amount = 1 },
    } },
    .{ .title = "T400 Memory Diamond", .side = .runner, .code = 30031, .card_type = "Hardware", .cost = 2, .runner_install = .{ .kind = .hardware }, .static_abilities = &.{
        .{ .kind = .mu, .value = 1 },
        .{ .kind = .hand_size, .value = 1 },
    } },
    .{
        .title = "Tomorrow's Headline",
        .side = .corp,
        .code = 30052,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 3,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{
            .{
                .event = .agenda_scored,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        _ = try addRunnerTag(g, 1);
                        g.systemMsg(.corp, 0, "Runner gains 1 tag.", .{});
                        try collectEventHandlers(g, .{ .kind = .runner_gain_tag });
                    }
                }.handle,
            },
            .{
                .event = .agenda_stolen,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        _ = try addRunnerTag(g, 1);
                        g.systemMsg(.corp, 0, "Runner gains 1 tag.", .{});
                        try collectEventHandlers(g, .{ .kind = .runner_gain_tag });
                    }
                }.handle,
            },
        },
    },
    .{ .title = "Ping", .side = .corp, .code = 30055, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 2, .strength = 1, .install = .{ .kind = .corp_server_choice }, .event_abilities = &.{.{
        .event = .corp_rez_ice,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                _ = try addRunnerTag(gameFromEffectContext(ctx), 1);
            }
        }.handle,
    }}, .subroutines = &.{
        .{ .resolve = &resolveEndTheRun, .label = "End the run" },
    } },
    .{ .title = "Ballista", .side = .corp, .code = 30062, .card_type = "ICE", .subtypes = &.{"Sentry"}, .cost = 5, .strength = 4, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolveTrashProgramOrEtr, .label = "Trash 1 program or end the run" },
        .{ .resolve = &resolveTrashProgramOrEtr, .label = "Trash 1 program or end the run" },
    } },
    .{
        .title = "Sprint",
        .side = .corp,
        .code = 30041,
        .card_type = "Operation",
        .cost = 0,
        .abilities = &.{.{
            .is_play = true,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, src_card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    try drawCards(g, .corp, 3);
                    // Present prompt to choose 2 cards to shuffle back
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_hand.items, 0..) |card, idx| {
                        try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                    }
                    g.corp_prompt_state = .{
                        .prompt_type = "sprint-shuffle",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = src_card.*,
                        .min_choices = 2,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                // Mark the card as selected (don't move yet — batch like Clojure)
                                // Track selected card titles in pending_sprint_selections
                                try cg.pending_sprint_selections.append(cg.backing_allocator, choice_text);
                                // Check if we need to pick one more
                                if (cg.corp_prompt_state) |*ps| {
                                    if (ps.min_choices > 1) {
                                        ps.min_choices -= 1;
                                        // Rebuild choices excluding already-selected cards
                                        const c_allocator = cg.ephemeralAllocator();
                                        var c_choices: std.ArrayList(state.PromptChoice) = .empty;
                                        defer c_choices.deinit(c_allocator);
                                        for (cg.corp_hand.items, 0..) |card, idx| {
                                            var already_selected = false;
                                            for (cg.pending_sprint_selections.items) |sel| {
                                                if (std.mem.eql(u8, card.title, sel)) {
                                                    already_selected = true;
                                                    break;
                                                }
                                            }
                                            if (!already_selected) {
                                                try c_choices.append(c_allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                                            }
                                        }
                                        ps.choices = try c_choices.toOwnedSlice(c_allocator);
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                                        return;
                                    }
                                }
                                // All selected — now move all selected cards from hand to deck
                                for (cg.pending_sprint_selections.items) |sel_title| {
                                    for (cg.corp_hand.items, 0..) |card, idx| {
                                        if (std.mem.eql(u8, card.title, sel_title)) {
                                            const removed = cg.corp_hand.orderedRemove(idx);
                                            try cg.corp_deck.append(cg.backing_allocator, removed);
                                            break;
                                        }
                                    }
                                }
                                cg.pending_sprint_selections.clearRetainingCapacity();
                                // Done — shuffle R&D and return to corp actions
                                try shuffleDeck(cg, .corp);
                                cg.corp_prompt_state = null;
                                cg.decision_side = .corp;
                                cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.play,
        }},
    },
    .{
        .title = "Hansei Review",
        .side = .corp,
        .code = 30048,
        .card_type = "Operation",
        .cost = 5,
        .abilities = &.{.{
            .is_play = true,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    g.corp_credit += 10;
                    if (g.corp_hand.items.len == 0) {
                        // No cards to trash — just return
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                        return;
                    }
                    // Present prompt to choose 1 card from HQ to trash
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_hand.items, 0..) |hcard, idx| {
                        try choices.append(allocator, .{ .kind = .card, .text = hcard.title, .card = .{ .title = hcard.title, .side = .corp, .index = @intCast(idx) } });
                    }
                    g.corp_prompt_state = .{
                        .prompt_type = "hansei-trash",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = card.*,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                for (cg.corp_hand.items, 0..) |c_card, idx| {
                                    if (std.mem.eql(u8, c_card.title, choice_text)) {
                                        const removed = cg.corp_hand.orderedRemove(idx);
                                        try cg.corp_discard.append(cg.backing_allocator, removed);
                                        break;
                                    }
                                }
                                cg.corp_prompt_state = null;
                                cg.decision_side = .corp;
                                cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.play,
        }},
    },
    .{
        .title = "Above the Law",
        .side = .corp,
        .code = 30060,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 3,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{ .event = .agenda_scored, .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                if (g.runner_rig_resources.items.len == 0) return;
                const allocator = g.ephemeralAllocator();
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                for (g.runner_rig_resources.items, 0..) |res, idx| {
                    const label = try std.fmt.allocPrint(allocator, "r|{d}", .{idx});
                    try choices.append(allocator, .{ .kind = .string, .text = label, .card = .{ .title = res.title, .side = .runner, .index = @intCast(idx) } });
                }
                g.corp_prompt_state = .{
                    .prompt_type = "above-the-law-trash",
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = null,
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            var pieces = std.mem.splitScalar(u8, choice_text, '|');
                            const zone = pieces.next() orelse return error.UnsupportedChoice;
                            if (!std.mem.eql(u8, zone, "r")) return error.UnsupportedChoice;
                            const index_text = pieces.next() orelse return error.UnsupportedChoice;
                            const index = try std.fmt.parseInt(usize, index_text, 10);
                            if (index >= cg.runner_rig_resources.items.len) return error.UnsupportedChoice;
                            const trashed = cg.runner_rig_resources.orderedRemove(index);
                            try cg.runner_discard.append(cg.backing_allocator, trashed);
                            cg.corp_prompt_state = null;
                            cg.decision_side = .corp;
                            cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                        }
                    }.choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.handle }},
    },
    // --- Phase 1: Pharos, Fermenter, Neurospike, Luminal Transubstantiation, Cookbook ---
    .{ .title = "Pharos", .side = .corp, .code = 30063, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 7, .strength = 5, .install = .{ .kind = .corp_server_choice }, .static_abilities = &.{ .{ .kind = .can_advance }, .{ .kind = .self_strength, .value = 5, .req = &struct {
        fn check(_: *const state.EffectContext, card: *const state.CardInstance, _: ?*const state.CardInstance) i16 {
            return if (card.advancement_counter >= 3) 1 else 0;
        }
    }.check } }, .subroutines = &.{
        .{ .resolve = &resolveGiveRunnerTags, .amount = 1, .label = "Give the Runner 1 tags" },
        .{ .resolve = &resolveEndTheRun, .label = "End the run" },
        .{ .resolve = &resolveEndTheRun, .label = "End the run" },
    } },
    .{ .title = "Fermenter", .side = .runner, .code = 30007, .card_type = "Program", .subtypes = &.{"Virus"}, .cost = 1, .runner_install = .{ .kind = .program }, .initial_virus_counters = 1, .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .label = "Gain [Credits]",
        .req = &struct {
            fn check(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                return card.virus_counter > 0;
            }
        }.check,
        .on_use = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const gain = @as(u16, card.virus_counter) * 2;
                g.runner_credit += gain;
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                    card.title, gain, if (gain != 1) "s" else "",
                });
                try trashRunnerRigCardByInstanceId(g, card.instance_id);
            }
        }.handle,
    }}, .event_abilities = &.{.{
        .event = .runner_turn_begins,
        .handler = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 1;
            }
        }.handle,
    }} },
    .{
        .title = "Neurospike",
        .side = .corp,
        .code = 30049,
        .card_type = "Operation",
        .cost = 3,
        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const damage: u8 = @intCast(@max(0, sumFloatingEffects(g, .agenda_points_scored)));
                if (damage > 0) {
                    try trashRandomRunnerHandCards(g, damage);
                    g.systemMsg(.corp, 30049, "Corp uses Neurospike to do {d} net damage.", .{damage});
                    updateTerminalState(g);
                    if (g.game_over) return;
                }
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.ephemeralAllocator(), g);
            }
        }.play }},
    },
    .{
        .title = "Luminal Transubstantiation",
        .side = .corp,
        .code = 30036,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 3,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    g.corp_click += 3;
                    try addFloatingEffect(g, .{
                        .kind = .prevent_score,
                        .duration = .end_of_turn,
                        .value = 1,
                    });
                    g.systemMsg(.corp, 0, "Corp gains 3 [clicks].", .{});
                }
            }.handle,
        }},
    },
    .{ .title = "Cookbook", .side = .runner, .code = 30009, .card_type = "Resource", .subtypes = &.{"Virtual"}, .cost = 1, .runner_install = .{ .kind = .resource }, .static_abilities = &.{.{
        .kind = .virus_install_bonus,
        .value = 1,
        .req = &struct {
            fn req(_: *const state.EffectContext, _: *const state.CardInstance, target: ?*const state.CardInstance) i16 {
                const modified = target orelse return 0;
                return if (modified.runner_install.kind == .program and hasSubtype(modified.*, "Virus")) 1 else 0;
            }
        }.req,
    }} },
    // --- Phase 2: Clearinghouse, Longevity Serum, Malapert Data Vault, Spin Doctor ---
    .{
        .title = "Clearinghouse",
        .side = .corp,
        .code = 30061,
        .card_type = "Asset",
        .subtypes = &.{"Hostile"},
        .cost = 0,
        .trash_cost = 3,
        .static_abilities = &.{.{ .kind = .can_advance }},
        .install = .{ .kind = .corp_remote_only },
        // Start of turn: optional trash to do meat damage equal to advancement counters
        .event_abilities = &.{.{
            .event = .corp_turn_begins,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (!card.rezzed or card.advancement_counter == 0) return;
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    const dmg = card.advancement_counter;
                    g.corp_prompt_state = .{
                        .prompt_type = "clearinghouse-trash",
                        .choices = try allocator.dupe(state.PromptChoice, &.{
                            stringChoice(try std.fmt.allocPrint(allocator, "Trash to do {d} meat damage", .{dmg})),
                            stringChoice("No action"),
                        }),
                        .ability_ref = .{ .source_instance_id = card.instance_id, .ability_index = dmg },
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const ref = (cg.corp_prompt_state orelse return).ability_ref orelse return;
                                const damage: u8 = ref.ability_index;
                                cg.corp_prompt_state = null;
                                if (std.mem.eql(u8, choice_text, "No action")) return;
                                try trashCorpServerCardByInstanceId(cg, ref.source_instance_id);
                                cg.systemMsg(.corp, 30061, "Corp trashes Clearinghouse to do {d} meat damage.", .{damage});
                                if (damage > 0) {
                                    try trashRandomRunnerHandCards(cg, damage);
                                    updateTerminalState(cg);
                                }
                            }
                        }.choice,
                    };
                }
            }.handle,
        }},
        // Click ability: same effect but costs a click (legacy/manual trigger)
        .abilities = &.{.{
            .cost = .{ .clicks = 1 },
            .label = "Trash to do meat damage",
            .req = &struct {
                fn check(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                    return card.rezzed and card.advancement_counter > 0;
                }
            }.check,
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const damage = card.advancement_counter;
                    try trashCorpServerCardByInstanceId(g, card.instance_id);
                    g.systemMsg(.corp, 30061, "Corp trashes Clearinghouse to do {d} meat damage.", .{damage});
                    if (damage > 0) {
                        try trashRandomRunnerHandCards(g, damage);
                        updateTerminalState(g);
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Longevity Serum",
        .side = .corp,
        .code = 30044,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 3,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Present prompt to trash cards from HQ, then shuffle up to 3 from Archives into R&D
                    const allocator = g.ephemeralAllocator();
                    if (g.corp_hand.items.len == 0 and g.corp_discard.items.len == 0) return;
                    // Phase 1: Choose cards from HQ to trash (0 or more, up to hand size)
                    // For simplicity, present as "Done" + each card in hand
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_hand.items, 0..) |card, idx| {
                        try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                    }
                    try choices.append(allocator, stringChoice("Done"));
                    g.corp_prompt_state = .{
                        .prompt_type = "longevity-serum-trash",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = null,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.ephemeralAllocator();
                                const prompt = cg.corp_prompt_state orelse return error.MissingPrompt;
                                if (std.mem.eql(u8, prompt.prompt_type, "longevity-serum-trash")) {
                                    if (std.mem.eql(u8, choice_text, "Done")) {
                                        // Move to shuffle phase: choose up to 3 cards from Archives
                                        if (cg.corp_discard.items.len == 0) {
                                            cg.corp_prompt_state = null;
                                            cg.decision_side = .corp;
                                            cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                            return;
                                        }
                                        var c_choices: std.ArrayList(state.PromptChoice) = .empty;
                                        defer c_choices.deinit(c_allocator);
                                        for (cg.corp_discard.items, 0..) |card, idx| {
                                            try c_choices.append(c_allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                                        }
                                        try c_choices.append(c_allocator, stringChoice("Done"));
                                        cg.corp_prompt_state = .{
                                            .prompt_type = "longevity-serum-shuffle",
                                            .choices = try c_choices.toOwnedSlice(c_allocator),
                                            .source_card = null,
                                            .min_choices = 0,
                                            .on_choice = &@This().choice,
                                        };
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                                        return;
                                    }
                                    // Trash chosen card from hand
                                    for (cg.corp_hand.items, 0..) |card, idx| {
                                        if (std.mem.eql(u8, card.title, choice_text)) {
                                            const removed = cg.corp_hand.orderedRemove(idx);
                                            try cg.corp_discard.append(cg.backing_allocator, removed);
                                            break;
                                        }
                                    }
                                    // Rebuild trash c_choices
                                    var c_choices: std.ArrayList(state.PromptChoice) = .empty;
                                    defer c_choices.deinit(c_allocator);
                                    for (cg.corp_hand.items, 0..) |card, idx| {
                                        try c_choices.append(c_allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                                    }
                                    try c_choices.append(c_allocator, stringChoice("Done"));
                                    cg.corp_prompt_state = .{
                                        .prompt_type = "longevity-serum-trash",
                                        .choices = try c_choices.toOwnedSlice(c_allocator),
                                        .source_card = null,
                                        .on_choice = &@This().choice,
                                    };
                                    cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                                    return;
                                }
                                if (std.mem.eql(u8, prompt.prompt_type, "longevity-serum-shuffle")) {
                                    if (std.mem.eql(u8, choice_text, "Done")) {
                                        try shuffleDeck(cg, .corp);
                                        cg.corp_prompt_state = null;
                                        cg.decision_side = .corp;
                                        cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                        return;
                                    }
                                    // Move chosen card from Archives to R&D
                                    for (cg.corp_discard.items, 0..) |card, idx| {
                                        if (std.mem.eql(u8, card.title, choice_text)) {
                                            const removed = cg.corp_discard.orderedRemove(idx);
                                            try cg.corp_deck.append(cg.backing_allocator, removed);
                                            break;
                                        }
                                    }
                                    // Check if we've hit 3 shuffles
                                    if (prompt.min_choices >= 2) {
                                        // Already shuffled 3, done
                                        try shuffleDeck(cg, .corp);
                                        cg.corp_prompt_state = null;
                                        cg.decision_side = .corp;
                                        cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                        return;
                                    }
                                    if (cg.corp_discard.items.len == 0) {
                                        try shuffleDeck(cg, .corp);
                                        cg.corp_prompt_state = null;
                                        cg.decision_side = .corp;
                                        cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                        return;
                                    }
                                    // Rebuild shuffle c_choices
                                    var c_choices: std.ArrayList(state.PromptChoice) = .empty;
                                    defer c_choices.deinit(c_allocator);
                                    for (cg.corp_discard.items, 0..) |card, idx| {
                                        try c_choices.append(c_allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                                    }
                                    try c_choices.append(c_allocator, stringChoice("Done"));
                                    cg.corp_prompt_state = .{
                                        .prompt_type = "longevity-serum-shuffle",
                                        .choices = try c_choices.toOwnedSlice(c_allocator),
                                        .source_card = null,
                                        .min_choices = prompt.min_choices + 1,
                                        .on_choice = &@This().choice,
                                    };
                                    cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                                    return;
                                }
                                return error.UnsupportedPrompt;
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Malapert Data Vault",
        .side = .corp,
        .code = 30066,
        .card_type = "Upgrade",
        .cost = 1,
        .trash_cost = 4,
        .install = .{ .kind = .corp_server_choice },
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, self_card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const scored_server_index: usize = if (ctx.event) |ev| if (ev.server_index) |si| @intCast(si) else return else return;
                    if (scored_server_index >= g.corp_servers.items.len) return;
                    var same_server = false;
                    const server = g.corp_servers.items[scored_server_index];
                    for (server.content.items) |card| {
                        if (card.code != null and self_card.code != null and card.code.? == self_card.code.?) {
                            same_server = true;
                            break;
                        }
                    }
                    if (!same_server) return;
                    // Search R&D for a non-agenda card
                    if (g.corp_deck.items.len == 0) return;
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_deck.items, 0..) |card, idx| {
                        if (card.agenda_points != null) continue; // skip agendas
                        try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                    }
                    if (choices.items.len == 0) return; // no non-agenda cards in R&D
                    try choices.append(allocator, stringChoice("Done"));
                    g.corp_prompt_state = .{
                        .prompt_type = "malapert-search",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = null,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                if (std.mem.eql(u8, choice_text, "Done")) {
                                    // Declined or cancelled — shuffle R&D
                                    try shuffleDeck(cg, .corp);
                                    return;
                                }
                                // Clojure: reveal → shuffle R&D → move card to HQ
                                // Shuffle first (before removing), then find and move
                                try shuffleDeck(cg, .corp);
                                const c_allocator = cg.ephemeralAllocator();
                                for (cg.corp_deck.items, 0..) |card, idx| {
                                    if (std.mem.eql(u8, card.title, choice_text)) {
                                        const removed = cg.corp_deck.orderedRemove(idx);
                                        try cg.corp_hand.append(c_allocator, removed);
                                        break;
                                    }
                                }
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Spin Doctor",
        .side = .corp,
        .code = 30053,
        .card_type = "Asset",
        .subtypes = &.{"Character"},
        .cost = 0,
        .trash_cost = 2,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{ .event = .corp_rez_ice, .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                try drawCards(g, .corp, 2);
                g.systemMsg(.corp, 30053, "Corp uses Spin Doctor to draw 2 cards.", .{});
            }
        }.handle }},
        // "Remove from game: Shuffle up to 2 cards from Archives into R&D."
        .abilities = &.{.{
            .label = "Shuffle up to 2 cards from Archives into R&D",
            .side = .corp,
            .req = &struct {
                fn check(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                    return card.rezzed;
                }
            }.check,
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.corp_discard.items.len == 0) return;
                    const allocator = g.ephemeralAllocator();
                    const iid = card.instance_id;
                    // Remove Spin Doctor from game (cost)
                    try removeCorpInstalledFromGame(g, iid);
                    g.systemMsg(.corp, 30053, "Corp removes Spin Doctor from game.", .{});
                    // Build choices from Archives
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_discard.items) |c| {
                        try choices.append(allocator, stringChoice(try allocator.dupe(u8, c.title)));
                    }
                    try choices.append(allocator, stringChoice("Done"));
                    g.corp_prompt_state = .{
                        .prompt_type = "spin-doctor-shuffle",
                        .choices = try choices.toOwnedSlice(allocator),
                        .ability_ref = .{ .source_instance_id = 0, .ability_index = 0 }, // ability_index tracks count picked
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.ephemeralAllocator();
                                const ref = (cg.corp_prompt_state orelse return).ability_ref orelse return;
                                const picked = ref.ability_index;
                                if (std.mem.eql(u8, choice_text, "Done") or picked >= 2) {
                                    cg.corp_prompt_state = null;
                                    try shuffleDeck(cg, .corp);
                                    cg.systemMsg(.corp, 30053, "Corp shuffles R&D.", .{});
                                    return;
                                }
                                // Find and move the chosen card from Archives to R&D
                                for (cg.corp_discard.items, 0..) |c, idx| {
                                    if (std.mem.eql(u8, c.title, choice_text)) {
                                        const moved = cg.corp_discard.orderedRemove(idx);
                                        try cg.corp_deck.append(cg.backing_allocator, moved);
                                        cg.systemMsg(.corp, 30053, "Corp shuffles {s} from Archives into R&D.", .{moved.title});
                                        break;
                                    }
                                }
                                if (picked + 1 >= 2 or cg.corp_discard.items.len == 0) {
                                    cg.corp_prompt_state = null;
                                    try shuffleDeck(cg, .corp);
                                    cg.systemMsg(.corp, 30053, "Corp shuffles R&D.", .{});
                                    return;
                                }
                                // Re-present for second pick
                                var new_choices: std.ArrayList(state.PromptChoice) = .empty;
                                defer new_choices.deinit(c_allocator);
                                for (cg.corp_discard.items) |c| {
                                    try new_choices.append(c_allocator, stringChoice(try c_allocator.dupe(u8, c.title)));
                                }
                                try new_choices.append(c_allocator, stringChoice("Done"));
                                cg.corp_prompt_state = .{
                                    .prompt_type = "spin-doctor-shuffle",
                                    .choices = try new_choices.toOwnedSlice(c_allocator),
                                    .ability_ref = .{ .source_instance_id = 0, .ability_index = picked + 1 },
                                    .on_choice = &@This().choice,
                                };
                                cg.decision_side = .corp;
                                cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    // --- Phase 3: Consoles ---
    .{
        .title = "Carnivore",
        .side = .runner,
        .code = 30003,
        .card_type = "Hardware",
        .subtypes = &.{"Console"},
        .cost = 4,
        .runner_install = .{ .kind = .hardware },
        .static_abilities = &.{.{ .kind = .mu, .value = 1 }},
        .abilities = &.{.{
            .is_access_ability = true,
            .label = "Trash card",
            .side = .runner,
            .once_per_turn = true,
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const accessed = (if (g.runner_prompt_state) |ps| ps.source_card else null) orelse return error.MissingSourceCard;
                    markAbilityUsedThisTurn(card, 0);
                    // Trash 2 cards from runner hand
                    var trashed: u8 = 0;
                    while (trashed < 2 and g.runner_hand.items.len > 0) : (trashed += 1) {
                        const c = g.runner_hand.orderedRemove(0);
                        try g.runner_discard.append(g.backing_allocator, c);
                    }
                    g.runner_prompt_state = null;
                    g.turn_events.runner_trash_corp_card_count += 1;
                    if (try fireEvent(g, .runner_trash_corp_card)) return;
                    try removeCurrentAccessedCard(g);
                    try appendDiscardCard(g, .corp, accessed);
                    try finishAccessCard(g);
                }
            }.handle,
            .req = &struct {
                fn check(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    if (isAbilityUsedThisTurn(card, 0)) return false;
                    return g.runner_hand.items.len >= 2;
                }
            }.check,
        }},
    },
    .{
        .title = "Pantograph",
        .side = .runner,
        .code = 30023,
        .card_type = "Hardware",
        .subtypes = &.{"Console"},
        .cost = 2,
        .runner_install = .{ .kind = .hardware },
        .static_abilities = &.{.{ .kind = .mu, .value = 1 }},
        .event_abilities = blk: {
            const H = struct {
                const pantograph_on_choice = &struct {
                    fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                        const g = gameFromEffectContext(cctx);
                        const prompt = g.runner_prompt_state orelse return error.NoPromptState;
                        if (std.mem.eql(u8, prompt.prompt_type, "runner-bonus-install-confirm")) {
                            g.runner_prompt_state = null;
                            if (std.mem.eql(u8, choice_text, "Yes")) {
                                g.runner_credit += 1;
                                g.systemMsg(.runner, 30023, "Runner uses Pantograph to gain 1 [credit].", .{});
                                const ref = prompt.ability_ref orelse return error.MissingAbilityRef;
                                try beginRunnerOptionalInstallPrompt(g, ref.source_instance_id, &@This().choice);
                                if (!hasActivePrompt(g)) {
                                    if (try resumePendingEffects(g)) return;
                                }
                                return;
                            }
                            if (std.mem.eql(u8, choice_text, "No")) {
                                if (try resumePendingEffects(g)) return;
                                return;
                            }
                            return error.UnsupportedChoice;
                        }
                        if (std.mem.eql(u8, choice_text, "No action")) {
                            g.runner_prompt_state = null;
                            if (try resumePendingEffects(g)) return;
                            return;
                        }
                        for (prompt.choices) |prompt_choice| {
                            if (prompt_choice.text == null or !std.mem.eql(u8, prompt_choice.text.?, choice_text)) continue;
                            const card_ref = prompt_choice.card orelse continue;
                            const card_index = card_ref.index orelse continue;
                            g.runner_prompt_state = null;
                            try beginRunnerInstallFromHand(g, card_index, false);
                            if (!hasActivePrompt(g)) {
                                if (try resumePendingEffects(g)) return;
                            }
                            return;
                        }
                        return error.UnsupportedChoice;
                    }
                }.choice;
                fn trigger(ctx: *state.EffectContext, self_card: *state.CardInstance) anyerror!void {
                    try beginRunnerOptionalInstallConfirmPrompt(gameFromEffectContext(ctx), self_card.instance_id, pantograph_on_choice);
                }
            };
            break :blk &.{
                .{ .event = .agenda_scored, .handler = &H.trigger },
                .{ .event = .agenda_stolen, .handler = &H.trigger },
            };
        },
    },
    // --- Phase 4: Trojans ---
    .{ .title = "Botulus", .side = .runner, .code = 30004, .card_type = "Program", .subtypes = &.{ "Virus", "Trojan" }, .cost = 2, .runner_install = .{ .kind = .program }, .initial_virus_counters = 1, .abilities = &.{.{
        .on_use = &encounterBotulusHandler,
        .req = &struct {
            fn check(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                if (card.virus_counter == 0) return false;
                return isInEncounter(ctx, card);
            }
        }.check,
    }}, .event_abilities = &.{.{
        .event = .runner_turn_begins,
        .handler = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 1;
            }
        }.handle,
    }} },
    .{ .title = "Tranquilizer", .side = .runner, .code = 30017, .card_type = "Program", .subtypes = &.{ "Virus", "Trojan" }, .cost = 2, .runner_install = .{ .kind = .program }, .initial_virus_counters = 1, .event_abilities = &.{.{
        .event = .runner_turn_begins,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 1;
                const g = gameFromEffectContext(ctx);
                if (card.virus_counter < 3) return;
                for (g.corp_servers.items) |*server| {
                    for (server.ices.items) |*ice| {
                        for (ice.hosted.items) |hosted| {
                            if (hosted.instance_id == card.instance_id) {
                                ice.rezzed = false;
                                return;
                            }
                        }
                    }
                }
            }
        }.handle,
    }} },
    // --- Phase 5: Ansel 1.0 ---
    .{
        .title = "Ansel 1.0",
        .side = .corp,
        .code = 30038,
        .card_type = "ICE",
        .subtypes = &.{ "Bioroid", "Sentry", "Destroyer" },
        .cost = 6,
        .strength = 4,
        .install = .{ .kind = .corp_server_choice },
        .subroutines = &.{
            .{ .resolve = &resolveTrashProgramOrEtr, .label = "Trash 1 program or end the run" }, // trash 1 installed Runner card
            .{ .resolve = &resolveCorpInstallFromHqArchives, .label = "Install a card from HQ or Archives" }, // install a card from HQ or Archives
            .{ .resolve = &resolvePreventStealTrash, .label = "The Runner cannot steal or trash Corp cards for the remainder of this run" }, // prevent stealing/trashing for rest of run
        },
        .abilities = &.{.{ .on_use = &encounterBioroidHandler, .allow_opponent_use = true, .req = &isInEncounter, .cost = .{ .clicks = 1 }, .break_count = 1 }},
    },
    .{
        .title = "Anoetic Void",
        .side = .corp,
        .code = 30050,
        .card_type = "Upgrade",
        .cost = 0,
        .trash_cost = 1,
        .install = .{ .kind = .corp_server_choice },
        .event_abilities = &.{.{
            .event = .server_approached,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (!card.rezzed) return;
                    const g = gameFromEffectContext(ctx);
                    if (g.corp_credit >= 2 and g.corp_hand.items.len >= 2) {
                        const allocator = g.ephemeralAllocator();
                        g.corp_prompt_state = .{
                            .prompt_type = "anoetic-void",
                            .choices = &.{
                                .{ .kind = .string, .text = "Use Anoetic Void" },
                                .{ .kind = .string, .text = "No action" },
                            },
                            .source_card = card.*,
                            .on_choice = &struct {
                                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                    const cg = gameFromEffectContext(cctx);
                                    if (std.mem.eql(u8, choice_text, "Use Anoetic Void")) {
                                        if (cg.corp_credit < 2) return error.InsufficientCredits;
                                        cg.corp_credit -= 2;
                                        var trashed: u8 = 0;
                                        while (trashed < 2 and cg.corp_hand.items.len > 0) {
                                            const c_card = cg.corp_hand.orderedRemove(0);
                                            try cg.corp_discard.append(cg.backing_allocator, c_card);
                                            trashed += 1;
                                        }
                                        if (cg.run) |run| {
                                            const target = findServerByRunPath(cg.corp_servers.items, run.server) catch null;
                                            if (target) |t| {
                                                const server = &cg.corp_servers.items[t.index];
                                                for (server.content.items, 0..) |c, idx| {
                                                    if (c.code != null and c.code.? == 30050) {
                                                        const removed = server.content.orderedRemove(idx);
                                                        try cg.corp_discard.append(cg.backing_allocator, removed);
                                                        break;
                                                    }
                                                }
                                            }
                                        }
                                        try completeUnsuccessfulRun(cg);
                                    } else {
                                        cg.corp_prompt_state = null;
                                        const run = &cg.run.?;
                                        const c_allocator = cg.ephemeralAllocator();
                                        if (try checkServerApproachAbilities(cg)) return;
                                        if (try prepareNextAccess(cg)) {
                                            run.phase = .success;
                                            if (cg.runner_prompt_state) |ps| {
                                                cg.decision_side = .runner;
                                                cg.legal_actions = try promptChoiceActions(c_allocator, .runner, ps);
                                            } else {
                                                cg.decision_side = .runner;
                                                cg.legal_actions = try continueActionsForRun(c_allocator, .runner, run.*);
                                            }
                                            return;
                                        }
                                        try completeSuccessfulRunWithCorpPriority(cg);
                                    }
                                }
                            }.choice,
                        };
                        g.decision_side = .corp;
                        g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    }
                }
            }.handle,
        }},
    },
    // ====================================================================
    // ELEVATION PACK (35001–35082)
    // ====================================================================
    // --- Elevation Identities ---
    .{
        .title = "Ry\xc5\x8d \xe2\x80\x9cPhoenix\xe2\x80\x9d \xc5\x8cno: Out of the Ashes",
        .side = .runner,
        .code = 35001,
        .card_type = "Identity",
        .subtypes = &.{"G-mod"},
        // "Whenever a subroutine resolves during a run: gain 1cr. First time each turn: Corp trashes 1 from HQ."
        .event_abilities = &.{.{
            .event = .successful_run_ends,
            .automatic_priority = state.Priority.force_discard,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, self_card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.run == null) return;
                    if (sumFloatingEffects(g, .subroutine_resolved) == 0) return;
                    if (isAbilityUsedThisTurn(self_card, 0)) return;
                    markAbilityUsedThisTurn(self_card, 0);
                    g.runner_credit += 1;
                    g.systemMsg(.runner, 35001, "Runner uses Ry\xc5\x8d \xe2\x80\x9cPhoenix\xe2\x80\x9d \xc5\x8cno to gain 1 [credit].", .{});
                    if (g.corp_hand.items.len > 0) {
                        const trashed = g.corp_hand.orderedRemove(0);
                        try appendDiscardCard(g, .corp, trashed);
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Topan: Ormas Leader",
        .side = .runner,
        .code = 35002,
        .card_type = "Identity",
        .subtypes = &.{"Natural"},
        // "click: Install 1 card from grip, paying 2cr less. Suffer 1 meat damage."
        .abilities = &.{.{
            .cost = .{ .clicks = 1 },
            .once_per_turn = true,
            .label = "Install 1 card, paying 2[credit] less. Suffer 1 meat damage.",
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    g.systemMsg(.runner, card.code orelse 0, "{s} spends [click] to use {s}.", .{ sideName(.runner), card.title });
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.runner_hand.items) |h| {
                        if (h.runner_install.kind == .none) continue;
                        const base_cost: u16 = h.cost orelse 0;
                        const adjusted_cost = if (base_cost >= 2) base_cost - 2 else 0;
                        if (g.runner_credit < adjusted_cost) continue;
                        try choices.append(allocator, .{ .kind = .card, .text = h.title, .card = .{
                            .title = h.title,
                            .code = h.code,
                            .side = .runner,
                        } });
                    }
                    if (choices.items.len == 0) return; // no installable cards
                    try choices.append(allocator, stringChoice("No action"));
                    g.runner_prompt_state = .{
                        .prompt_type = "topan-install",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = g.runner_identity,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                if (std.mem.eql(u8, choice_text, "No action")) {
                                    cg.runner_prompt_state = null;
                                    const c_allocator = cg.ephemeralAllocator();
                                    cg.decision_side = .runner;
                                    cg.legal_actions = try runnerOpeningActionsForState(c_allocator, cg);
                                    return;
                                }
                                // Find card in hand and install paying 2cr less
                                for (cg.runner_hand.items, 0..) |c_card, idx| {
                                    if (std.mem.eql(u8, c_card.title, choice_text)) {
                                        const base_cost: u16 = c_card.cost orelse 0;
                                        const adjusted_cost = if (base_cost >= 2) base_cost - 2 else 0;
                                        cg.runner_prompt_state = null;
                                        try completeRunnerInstall(cg, @intCast(idx), c_card, adjusted_cost, true);
                                        // Suffer 1 meat damage (trash top c_card of hand)
                                        if (cg.runner_hand.items.len > 0) {
                                            const trashed = cg.runner_hand.orderedRemove(0);
                                            try appendDiscardCard(cg, .runner, trashed);
                                        }
                                        updateTerminalState(cg);
                                        if (cg.game_over) return;
                                        const c_allocator = cg.ephemeralAllocator();
                                        cg.decision_side = .runner;
                                        cg.legal_actions = try runnerOpeningActionsForState(c_allocator, cg);
                                        return;
                                    }
                                }
                            }
                        }.choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Barry \xe2\x80\x9cBaz\xe2\x80\x9d Wong: Tri-Maf Veteran",
        .side = .runner,
        .code = 35012,
        .card_type = "Identity",
        .subtypes = &.{"Cyborg"},
        // "Whenever the Corp rezzes a piece of ice, you may install 1 resource or piece of hardware from your grip."
        .event_abilities = &.{.{
            .event = .corp_rez_ice,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Build choices from runner hand: resources and hardware
                    const allocator = g.ephemeralAllocator();
                    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices_list.deinit(allocator);
                    for (g.runner_hand.items, 0..) |c, idx| {
                        const ct = c.card_type orelse continue;
                        if (!std.mem.eql(u8, ct, "Resource") and !std.mem.eql(u8, ct, "Hardware")) continue;
                        const cost = c.cost orelse 0;
                        if (g.runner_credit < cost) continue;
                        try choices_list.append(allocator, .{
                            .kind = .card,
                            .text = try std.fmt.allocPrint(allocator, "{s}", .{c.title}),
                            .card = .{ .title = c.title, .code = c.code, .side = .runner, .index = @intCast(idx) },
                        });
                    }
                    if (choices_list.items.len == 0) return;
                    try choices_list.append(allocator, stringChoice("No action"));
                    g.runner_prompt_state = .{
                        .prompt_type = "barry-install",
                        .choices = try choices_list.toOwnedSlice(allocator),
                        .source_card = g.runner_identity,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.ephemeralAllocator();
                                if (std.mem.eql(u8, choice_text, "No action")) {
                                    cg.runner_prompt_state = null;
                                    cg.corp_prompt_state = null;
                                    // Return to approach actions
                                    cg.decision_side = .corp;
                                    cg.legal_actions = try continueActionsForRunWithRez(c_allocator, .corp, cg.run, cg);
                                    return;
                                }
                                // Find and install the chosen card
                                const prompt = cg.runner_prompt_state orelse return error.NoPromptState;
                                for (prompt.choices) |ch| {
                                    if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                                        if (ch.card) |card_ref| {
                                            const card_idx = card_ref.index orelse continue;
                                            if (card_idx >= cg.runner_hand.items.len) continue;
                                            const card = cg.runner_hand.items[card_idx];
                                            const install_cost = card.cost orelse 0;
                                            try spendCredits(cg, .runner, install_cost);
                                            _ = try removeCardFromHand(cg, .runner, card_idx);
                                            try appendRunnerInstalledCard(cg, card);
                                            cg.systemMsg(.runner, 35012, "Runner uses Barry to install {s}.", .{card.title});
                                            break;
                                        }
                                    }
                                }
                                cg.runner_prompt_state = null;
                                cg.corp_prompt_state = null;
                                cg.decision_side = .corp;
                                cg.legal_actions = try continueActionsForRunWithRez(c_allocator, .corp, cg.run, cg);
                            }
                        }.choice,
                    };
                    g.corp_prompt_state = .{
                        .prompt_type = "waiting",
                        .choices = &.{},
                        .source_card = null,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "MuslihaT: Multifarious Marketeer",
        .side = .runner,
        .code = 35013,
        .card_type = "Identity",
        .subtypes = &.{"Natural"},
        // "When your turn begins, look at top card of stack. If icebreaker or run event, may reveal and add to grip."
        .event_abilities = &.{.{
            .event = .runner_turn_begins,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.runner_deck.items.len == 0) return;
                    const top_card = g.runner_deck.items[g.runner_deck.items.len - 1];
                    // Check if icebreaker or run event
                    var is_match = false;
                    const ct = top_card.card_type orelse "";
                    if (std.mem.eql(u8, ct, "Program")) {
                        for (top_card.subtypes) |st| {
                            if (std.mem.eql(u8, st, "Icebreaker")) {
                                is_match = true;
                                break;
                            }
                        }
                    } else if (std.mem.eql(u8, ct, "Event")) {
                        for (top_card.subtypes) |st| {
                            if (std.mem.eql(u8, st, "Run")) {
                                is_match = true;
                                break;
                            }
                        }
                    }
                    if (is_match) {
                        // Offer to reveal and add to grip
                        const allocator = g.ephemeralAllocator();
                        const choices = try allocator.alloc(state.PromptChoice, 2);
                        choices[0] = stringChoice("Yes");
                        choices[1] = stringChoice("No");
                        g.runner_prompt_state = .{
                            .prompt_type = "muslihat-reveal",
                            .choices = choices,
                            .source_card = g.runner_identity,
                            .on_choice = &struct {
                                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                    const cg = gameFromEffectContext(cctx);
                                    if (std.mem.eql(u8, choice_text, "Yes")) {
                                        if (cg.runner_deck.items.len > 0) {
                                            const card = cg.runner_deck.pop().?;
                                            try cg.runner_hand.append(cg.backing_allocator, card);
                                            cg.systemMsg(.runner, 35013, "Runner uses MuslihaT to add {s} to the grip.", .{card.title});
                                        }
                                    }
                                    cg.runner_prompt_state = null;
                                    cg.decision_side = .runner;
                                    cg.legal_actions = try runnerOpeningActionsForState(cg.ephemeralAllocator(), cg);
                                }
                            }.choice,
                        };
                        g.decision_side = .runner;
                        g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Dewi Subrotoputri: Pedagogical Dhalang",
        .side = .runner,
        .code = 35023,
        .card_type = "Identity",
        .subtypes = &.{"Natural"},
        // Flippy identity: "Pedagogical Dhalang" (front) / "Shadow Guide" (back)
        // After successful run: flip based on available MU
        // Front → Back: no MU available → gain 1cr + flip
        // Back → Front: MU available → draw 1 + flip
        .event_abilities = &.{.{
            .event = .successful_run_ends,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const mu_available = if (g.runner_memory) |mem| mem.available else 0;
                    if (card.flipped and mu_available > 0) {
                        try drawCards(g, .runner, 1);
                        card.flipped = false;
                    } else if (!card.flipped and mu_available == 0) {
                        g.runner_credit += 1;
                        card.flipped = true;
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Magdalene Keino-Chemutai: Cryptarchitect",
        .side = .runner,
        .code = 35024,
        .card_type = "Identity",
        .subtypes = &.{"Cyborg"},
        // "When discarding to hand size, may install a discarded program or hardware for free."
        .event_abilities = &.{.{
            .event = .runner_discarded_to_hand_size,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    // Find programs and hardware in runner's discard
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.runner_discard.items, 0..) |card, idx| {
                        const ct = card.card_type orelse continue;
                        if (!std.mem.eql(u8, ct, "Program") and !std.mem.eql(u8, ct, "Hardware")) continue;
                        try choices.append(allocator, .{
                            .kind = .card,
                            .text = try std.fmt.allocPrint(allocator, "{s}", .{card.title}),
                            .card = .{ .title = card.title, .code = card.code, .side = .runner, .index = @intCast(idx) },
                        });
                    }
                    if (choices.items.len == 0) return;
                    try choices.append(allocator, stringChoice("No action"));
                    g.runner_prompt_state = .{
                        .prompt_type = "magdalene-install",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = g.runner_identity,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                cg.runner_prompt_state = null;
                                if (!std.mem.eql(u8, choice_text, "No action")) {
                                    // Find the chosen card in runner's discard by title and install it free
                                    for (cg.runner_discard.items, 0..) |card, idx| {
                                        if (std.mem.eql(u8, card.title, choice_text)) {
                                            const installed = cg.runner_discard.orderedRemove(idx);
                                            try appendRunnerInstalledCard(cg, installed);
                                            cg.systemMsg(.runner, 35024, "Magdalene installs {s} from heap for free.", .{installed.title});
                                            break;
                                        }
                                    }
                                }
                                try completeRunnerEndTurn(cg);
                            }
                        }.choice,
                    };
                }
            }.handle,
        }},
    },
    .{
        .title = "LEO Construction: Labor Solutions",
        .side = .corp,
        .code = 35035,
        .card_type = "Identity",
        .subtypes = &.{"Division"},
        // "Once per turn, during a run on a server with bioroid ICE, end the run."
        .abilities = &.{.{
            .once_per_turn = true,
            .label = "End the run",
            .req = &struct {
                fn check(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                    return serverHasBioroidIce(gameFromConstEffectContext(ctx));
                }
            }.check,
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    g.systemMsg(.corp, 35035, "Corp uses LEO Construction to end the run.", .{});
                    try completeUnsuccessfulRun(g);
                }
            }.use,
        }},
    },
    .{
        .title = "Po\xc3\xa9tr\xc3\xaf Luxury Brands: All the Rage",
        .side = .corp,
        .code = 35036,
        .card_type = "Identity",
        .subtypes = &.{"Division"},
        // "When you score an agenda, look at top 3 R&D. May install 1 non-agenda non-operation."
        // "When an agenda is stolen, may install 1 non-agenda non-operation from HQ."
        .event_abilities = &.{
            .{
                // Agenda scored: look at top 3 R&D, may install 1 non-agenda non-operation
                .event = .agenda_scored,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        if (g.corp_deck.items.len == 0) return;
                        const allocator = g.ephemeralAllocator();
                        const peek_count: usize = @min(3, g.corp_deck.items.len);
                        var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                        defer choices_list.deinit(allocator);
                        for (0..peek_count) |i| {
                            const c = g.corp_deck.items[i];
                            const ct = c.card_type orelse continue;
                            if (std.mem.eql(u8, ct, "Agenda") or std.mem.eql(u8, ct, "Operation")) continue;
                            try choices_list.append(allocator, stringChoice(
                                try std.fmt.allocPrint(allocator, "rd|{d}|{s}", .{ i, c.title }),
                            ));
                        }
                        if (choices_list.items.len == 0) return;
                        try choices_list.append(allocator, stringChoice("No action"));
                        g.corp_prompt_state = .{
                            .prompt_type = "poetri-rd-install",
                            .choices = try choices_list.toOwnedSlice(allocator),
                            .on_choice = &struct {
                                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                    const cg = gameFromEffectContext(cctx);
                                    cg.corp_prompt_state = null;
                                    if (std.mem.eql(u8, choice_text, "No action")) return;
                                    // Parse "rd|index|title"
                                    var parts = std.mem.splitScalar(u8, choice_text, '|');
                                    _ = parts.next(); // "rd"
                                    const idx_str = parts.next() orelse return;
                                    const idx = std.fmt.parseInt(usize, idx_str, 10) catch return;
                                    if (idx >= cg.corp_deck.items.len) return;
                                    const card_to_install = cg.corp_deck.orderedRemove(idx);
                                    const ik = card_to_install.install.kind;
                                    // Temporarily put card in hand so installCorpCardFromHand works
                                    try cg.corp_hand.append(cg.backing_allocator, card_to_install);
                                    const hand_idx: u8 = @intCast(cg.corp_hand.items.len - 1);
                                    const c_alloc = cg.ephemeralAllocator();
                                    const srv_choices = try installChoicesForCard(c_alloc, ik, cg);
                                    if (srv_choices.len <= 1) {
                                        const srv = if (srv_choices.len == 1 and srv_choices[0].text != null) srv_choices[0].text.? else "New remote";
                                        try installCorpCardFromHand(cg, hand_idx, srv);
                                        cg.systemMsg(.corp, 35036, "Corp uses Po\xc3\xa9tr\xc3\xaf to install a card from R&D.", .{});
                                    } else {
                                        cg.corp_prompt_state = .{
                                            .prompt_type = "poetri-server",
                                            .choices = srv_choices,
                                            .min_choices = hand_idx,
                                            .on_choice = &struct {
                                                fn ch(ccctx: *state.EffectContext, srv_text: []const u8) anyerror!void {
                                                    const g3 = gameFromEffectContext(ccctx);
                                                    const ci = (g3.corp_prompt_state orelse return).min_choices;
                                                    g3.corp_prompt_state = null;
                                                    try installCorpCardFromHand(g3, ci, srv_text);
                                                    g3.systemMsg(.corp, 35036, "Corp uses Po\xc3\xa9tr\xc3\xaf to install a card from R&D.", .{});
                                                }
                                            }.ch,
                                        };
                                        cg.decision_side = .corp;
                                        cg.legal_actions = try promptChoiceActions(c_alloc, .corp, cg.corp_prompt_state.?);
                                    }
                                }
                            }.choice,
                        };
                        g.systemMsg(.corp, 35036, "Corp looks at the top {d} cards of R&D.", .{peek_count});
                    }
                }.handle,
            },
            .{
                // Agenda stolen: may install 1 non-agenda non-operation from HQ
                .event = .agenda_stolen,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        const allocator = g.ephemeralAllocator();
                        var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                        defer choices_list.deinit(allocator);
                        for (g.corp_hand.items, 0..) |c, idx| {
                            const ct = c.card_type orelse continue;
                            if (std.mem.eql(u8, ct, "Agenda") or std.mem.eql(u8, ct, "Operation")) continue;
                            try choices_list.append(allocator, .{
                                .kind = .card,
                                .text = try std.fmt.allocPrint(allocator, "{s}", .{c.title}),
                                .card = .{ .title = c.title, .code = c.code, .side = .corp, .index = @intCast(idx) },
                            });
                        }
                        if (choices_list.items.len == 0) return;
                        try choices_list.append(allocator, stringChoice("No action"));
                        g.corp_prompt_state = .{
                            .prompt_type = "poetri-install",
                            .choices = try choices_list.toOwnedSlice(allocator),
                            .on_choice = &struct {
                                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                    const cg = gameFromEffectContext(cctx);
                                    cg.corp_prompt_state = null;
                                    if (std.mem.eql(u8, choice_text, "No action")) return;
                                    for (cg.corp_hand.items, 0..) |c, idx| {
                                        if (std.mem.eql(u8, c.title, choice_text)) {
                                            const c_alloc = cg.ephemeralAllocator();
                                            const ik = c.install.kind;
                                            const srv_choices = try installChoicesForCard(c_alloc, ik, cg);
                                            if (srv_choices.len <= 1) {
                                                const srv = if (srv_choices.len == 1 and srv_choices[0].text != null) srv_choices[0].text.? else "New remote";
                                                try installCorpCardFromHand(cg, @intCast(idx), srv);
                                                cg.systemMsg(.corp, 35036, "Corp uses Po\xc3\xa9tr\xc3\xaf to install a card from HQ.", .{});
                                            } else {
                                                cg.corp_prompt_state = .{
                                                    .prompt_type = "poetri-server",
                                                    .choices = srv_choices,
                                                    .min_choices = @intCast(idx),
                                                    .on_choice = &struct {
                                                        fn ch(ccctx: *state.EffectContext, srv_text: []const u8) anyerror!void {
                                                            const g3 = gameFromEffectContext(ccctx);
                                                            const ci = (g3.corp_prompt_state orelse return).min_choices;
                                                            g3.corp_prompt_state = null;
                                                            try installCorpCardFromHand(g3, ci, srv_text);
                                                            g3.systemMsg(.corp, 35036, "Corp uses Po\xc3\xa9tr\xc3\xaf to install a card from HQ.", .{});
                                                        }
                                                    }.ch,
                                                };
                                                cg.decision_side = .corp;
                                                cg.legal_actions = try promptChoiceActions(c_alloc, .corp, cg.corp_prompt_state.?);
                                            }
                                            break;
                                        }
                                    }
                                }
                            }.choice,
                        };
                    }
                }.handle,
            },
        },
    },
    .{
        .title = "AU Co.: The Gold Standard in Clones",
        .side = .corp,
        .code = 35046,
        .card_type = "Identity",
        .subtypes = &.{"Division"},
        // "Whenever you do damage or trash 1+ cards from HQ, place 1 power counter."
        // "When your turn begins, you may spend 2 power counters to look at top 3 R&D, trash 1, add rest to HQ."
        .event_abilities = &.{
            .{
                .event = .corp_dealt_damage,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, self_card: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        self_card.power_counter += 1;
                        g.systemMsg(.corp, 35046, "Corp places 1 power counter on AU Co. (damage dealt).", .{});
                    }
                }.handle,
            },
            .{
                .event = .corp_trash_from_hand,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, self_card: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        self_card.power_counter += 1;
                        g.systemMsg(.corp, 35046, "Corp places 1 power counter on AU Co. (HQ trash).", .{});
                    }
                }.handle,
            },
            .{
                .event = .corp_turn_begins,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (card.power_counter < 2) return;
                        const g = gameFromEffectContext(ctx);
                        if (g.corp_deck.items.len == 0) return;
                        const allocator = g.ephemeralAllocator();
                        // Optional: ask corp if they want to spend 2 power counters
                        g.corp_prompt_state = .{
                            .prompt_type = "au-co-peek",
                            .choices = try allocator.dupe(state.PromptChoice, &.{
                                stringChoice("Look at the top 3 cards of R&D"),
                                stringChoice("No action"),
                            }),
                            .ability_ref = .{ .source_instance_id = card.instance_id, .ability_index = 0 },
                            .on_choice = &struct {
                                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                    const cg = gameFromEffectContext(cctx);
                                    const ref = (cg.corp_prompt_state orelse return).ability_ref orelse return;
                                    cg.corp_prompt_state = null;
                                    if (std.mem.eql(u8, choice_text, "No action")) return;
                                    const live = findCardPtrByInstanceId(cg, ref.source_instance_id) orelse return;
                                    if (live.power_counter < 2) return;
                                    live.power_counter -= 2;
                                    cg.systemMsg(.corp, 35046, "AU Co.: Corp spends 2 power counters to look at top 3 R&D.", .{});
                                    try beginPeekRdTopPrompt(cg, 3, ref.source_instance_id);
                                }
                            }.choice,
                        };
                    }
                }.handle,
            },
        },
    },
    .{
        .title = "PT Untaian: Life's Building Blocks",
        .side = .corp,
        .code = 35047,
        .card_type = "Identity",
        .subtypes = &.{"Division"},
        // "When your discard phase ends, if HQ ≤ 3 cards, pay 1cr to place 1 advancement counter on unrezzed card."
        .event_abilities = &.{.{
            .event = .corp_end_turn,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.corp_hand.items.len > 3) return;
                    if (g.corp_credit < 1) return;
                    // Check if there are advanceable unrezzed cards
                    const allocator = g.ephemeralAllocator();
                    const adv_choices = try installedCardChoices(allocator, g.corp_servers.items);
                    if (adv_choices.len == 0) return;
                    // Add "No action" option
                    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices_list.deinit(allocator);
                    for (adv_choices) |ch| try choices_list.append(allocator, ch);
                    try choices_list.append(allocator, stringChoice("No action"));
                    g.corp_prompt_state = .{
                        .prompt_type = "pt-untaian-advance",
                        .choices = try choices_list.toOwnedSlice(allocator),
                        .source_card = g.corp_identity,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.ephemeralAllocator();
                                if (std.mem.eql(u8, choice_text, "No action")) {
                                    cg.corp_prompt_state = null;
                                    return;
                                }
                                // Pay 1 credit and place advancement counter
                                try spendCredits(cg, .corp, 1);
                                _ = try addAdvancementCounter(cg, choice_text, 1);
                                cg.systemMsg(.corp, 35047, "Corp uses PT Untaian to place 1 advancement counter.", .{});
                                cg.corp_prompt_state = null;
                                _ = c_allocator;
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Nebula Talent Management: Making Stars",
        .side = .corp,
        .code = 35057,
        .card_type = "Identity",
        .subtypes = &.{"Division"},
        // Flippy identity: "Making Stars" (front) / "Gemilang Arena: Burning Bright" (back)
        // Front → Back: End of turn if operation played → flip + gain 1cr
        // Back → Front: Successful run on HQ/R&D → flip
        // Back ongoing: First non-Terminal operation played → gain 1 click
        .event_abilities = &.{
            .{
                .event = .corp_end_turn,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        if (!card.flipped and g.turn_events.operation_played_count > 0) {
                            card.flipped = true;
                            g.corp_credit += 1;
                        }
                    }
                }.handle,
            },
            .{
                .event = .successful_run_ends,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        const run = g.run orelse return;
                        if (!card.flipped) return;
                        if (run.server == .hq or run.server == .rnd) {
                            card.flipped = false;
                        }
                    }
                }.handle,
            },
            .{
                .event = .operation_played,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        if (!card.flipped or g.turn_events.operation_played_count != 1) return;
                        // Filter Terminal operations — no click gain for Terminals
                        if (ctx.event) |payload| {
                            if (payload.source_code) |code| {
                                if (lookupCardSpecByCode(code)) |spec| {
                                    for (spec.subtypes) |st| {
                                        if (std.mem.eql(u8, st, "Terminal")) return;
                                    }
                                }
                            }
                        }
                        g.corp_click += 1;
                    }
                }.handle,
            },
        },
    },
    .{
        .title = "Synapse Global: Faster than Thought",
        .side = .corp,
        .code = 35058,
        .card_type = "Identity",
        .subtypes = &.{"Division"},
        // "When the Runner removes 1+ tags, reveal and install a non-operation from HQ for free."
        .event_abilities = &.{.{
            .event = .runner_lose_tag,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (isAbilityUsedThisTurn(card, 0)) return;
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_hand.items, 0..) |corp_card, idx| {
                        const card_type = corp_card.card_type orelse continue;
                        if (std.mem.eql(u8, card_type, "Operation")) continue;
                        try choices.append(allocator, .{
                            .kind = .card,
                            .text = try allocator.dupe(u8, corp_card.title),
                            .card = .{ .title = corp_card.title, .printed_title = corp_card.printed_title, .code = corp_card.code, .side = .corp, .index = @intCast(idx) },
                        });
                    }
                    if (choices.items.len == 0) return;
                    markAbilityUsedThisTurn(card, 0);
                    try choices.append(allocator, stringChoice("No action"));
                    g.corp_prompt_state = .{
                        .prompt_type = "corp-free-install-card",
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = card.*,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.ephemeralAllocator();
                                const prompt = cg.corp_prompt_state orelse return error.NoPromptState;
                                if (std.mem.eql(u8, prompt.prompt_type, "corp-free-install-card")) {
                                    if (std.mem.eql(u8, choice_text, "No action")) {
                                        cg.corp_prompt_state = null;
                                        try restorePriorityAfterPrompt(cg);
                                        return;
                                    }
                                    for (prompt.choices) |card_choice| {
                                        if (card_choice.text == null or !std.mem.eql(u8, card_choice.text.?, choice_text)) continue;
                                        const card_ref = card_choice.card orelse continue;
                                        const card_idx = card_ref.index orelse continue;
                                        if (card_idx >= cg.corp_hand.items.len) return error.InvalidCardIndex;
                                        const install_kind = cg.corp_hand.items[card_idx].install.kind;
                                        const server_choices = try installChoicesForCard(c_allocator, install_kind, cg);
                                        cg.corp_prompt_state = .{
                                            .prompt_type = "corp-free-install-server",
                                            .choices = server_choices,
                                            .source_card = prompt.source_card,
                                            .min_choices = card_idx,
                                            .on_choice = &@This().choice,
                                        };
                                        cg.decision_side = .corp;
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                                        return;
                                    }
                                    return error.UnsupportedChoice;
                                }
                                if (std.mem.eql(u8, prompt.prompt_type, "corp-free-install-server")) {
                                    const card_idx = prompt.min_choices;
                                    if (card_idx >= cg.corp_hand.items.len) return error.InvalidCardIndex;
                                    const card_title = cg.corp_hand.items[card_idx].title;
                                    try installCorpCardFromHand(cg, card_idx, choice_text);
                                    cg.systemMsg(.corp, 35058, "Corp uses Synapse Global to reveal and install {s}.", .{card_title});
                                    cg.corp_prompt_state = null;
                                    try restorePriorityAfterPrompt(cg);
                                    return;
                                }
                                return error.UnsupportedChoice;
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
        // "[click], Remove 1 tag: Gain 2[Credits]." (runner action on corp identity)
        .abilities = &.{.{
            .cost = .{ .clicks = 1 },
            .allow_opponent_use = true,
            .side = .runner,
            .label = "Remove 1 tag: Gain 2[Credits]",
            .req = &struct {
                fn check(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    return is_runner_tagged(g.runner_tag);
                }
            }.check,
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    try removeRunnerTags(g, 1);
                    g.runner_credit += 2;
                    g.systemMsg(.runner, 35058, "Runner uses Synapse Global to remove 1 tag and gain 2 [credits].", .{});
                }
            }.handle,
        }},
    },
    .{
        .title = "BANGUN: When Disaster Strikes",
        .side = .corp,
        .code = 35068,
        .card_type = "Identity",
        .subtypes = &.{"Corp"},
        .static_abilities = &.{.{ .kind = .faceup_agenda_install }},
        // "When you install a non-ice card in a remote: if agenda, may turn faceup; otherwise 'Nothing to see here'."
        // "On access of faceup agenda: 2 meat damage + 1 tag."
        .event_abilities = &.{
            .{
                .event = .corp_install,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        const payload = ctx.event orelse return;
                        const iid = payload.target_instance_id orelse return;
                        // Only for remote server installs (not centrals)
                        if (payload.is_central) return;
                        const installed = findCardPtrByInstanceId(g, iid) orelse return;
                        const ct = installed.card_type orelse return;
                        if (std.mem.eql(u8, ct, "ICE")) return;
                        const allocator = g.ephemeralAllocator();
                        if (std.mem.eql(u8, ct, "Agenda")) {
                            // Offer to turn agenda faceup
                            g.corp_prompt_state = .{
                                .prompt_type = "bangun-faceup",
                                .choices = try allocator.dupe(state.PromptChoice, &.{
                                    stringChoice(try std.fmt.allocPrint(allocator, "Turn {s} faceup", .{installed.title})),
                                    stringChoice("No action"),
                                }),
                                .ability_ref = .{ .source_instance_id = iid, .ability_index = 0 },
                                .on_choice = &struct {
                                    fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                        const cg = gameFromEffectContext(cctx);
                                        const ref = (cg.corp_prompt_state orelse return).ability_ref orelse return;
                                        cg.corp_prompt_state = null;
                                        if (!std.mem.eql(u8, choice_text, "No action")) {
                                            const card_ptr = findCardPtrByInstanceId(cg, ref.source_instance_id) orelse return;
                                            card_ptr.seen = true;
                                            cg.systemMsg(.corp, 35068, "Corp turns {s} faceup.", .{card_ptr.title});
                                        }
                                    }
                                }.choice,
                            };
                        } else {
                            // Bluff prompt for non-agendas
                            g.corp_prompt_state = .{
                                .prompt_type = "bangun-bluff",
                                .choices = try allocator.dupe(state.PromptChoice, &.{
                                    stringChoice("Nothing to see here"),
                                }),
                                .on_choice = &struct {
                                    fn choice(cctx: *state.EffectContext, _: []const u8) anyerror!void {
                                        const cg = gameFromEffectContext(cctx);
                                        cg.corp_prompt_state = null;
                                    }
                                }.choice,
                            };
                        }
                    }
                }.handle,
            },
            .{
                .event = .access,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        const accessed = currentPendingAccessedServerCard(g) orelse return;
                        const card_type = accessed.card_type orelse return;
                        if (!std.mem.eql(u8, card_type, "Agenda") or !accessed.seen) return;
                        try trashRandomRunnerHandCards(g, 2);
                        g.systemMsg(.corp, 35068, "Corp uses BANGUN to do 2 meat damage and give the Runner 1 tag.", .{});
                        updateTerminalState(g);
                        if (g.game_over) return;
                        _ = try addRunnerTag(g, 1);
                    }
                }.handle,
            },
        },
    },
    .{
        .title = "The Zwicky Group: Invisible Hands",
        .side = .corp,
        .code = 35069,
        .card_type = "Identity",
        .subtypes = &.{"Unsubstantiated"},
        // "First time each turn you gain credits through an ability on an agenda or operation, you may draw 1 card."
        .event_abilities = &.{.{
            .event = .operation_played,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.turn_events.operation_played_count != 1) return;
                    // "you may draw 1 card" - optional prompt
                    const allocator = g.ephemeralAllocator();
                    const choices = try allocator.alloc(state.PromptChoice, 2);
                    choices[0] = stringChoice("Yes");
                    choices[1] = stringChoice("No");
                    g.corp_prompt_state = .{
                        .prompt_type = "zwicky-draw",
                        .choices = choices,
                        .source_card = g.corp_identity,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                if (std.mem.eql(u8, choice_text, "Yes")) {
                                    try drawCards(cg, .corp, 1);
                                    cg.systemMsg(.corp, 35069, "Corp uses The Zwicky Group to draw 1 card.", .{});
                                }
                                cg.corp_prompt_state = null;
                                cg.runner_prompt_state = null;
                                cg.decision_side = .corp;
                                cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                            }
                        }.choice,
                    };
                    g.runner_prompt_state = .{
                        .prompt_type = "waiting",
                        .choices = &.{},
                        .source_card = null,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    // --- Elevation Agendas ---
    .{
        .title = "Aggressive Trendsetting",
        .side = .corp,
        .code = 35037,
        .card_type = "Agenda",
        .subtypes = &.{"Initiative"},
        .agenda_points = 1,
        .advancement_requirement = 3,
        .install = .{ .kind = .corp_remote_only },
        // "First time Runner trashes installed Corp card each turn, they may spend [click]. If not, Corp gets +1 allotted [click] next turn."
        .event_abilities = &.{.{
            .event = .runner_trash_corp_card,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.turn_events.runner_trash_corp_card_count != 1) return;
                    if (g.runner_click == 0) {
                        // Runner has no clicks, corp auto-gets the bonus
                        g.corp_extra_clicks_next_turn += 1;
                        g.systemMsg(.corp, 35037, "Aggressive Trendsetting: Corp gains +1 allotted [click] next turn.", .{});
                        return;
                    }
                    // Ask runner if they want to spend a click to prevent corp bonus
                    const allocator = g.ephemeralAllocator();
                    g.runner_prompt_state = .{
                        .prompt_type = "aggressive-trendsetting",
                        .choices = try allocator.dupe(state.PromptChoice, &.{
                            stringChoice("Spend [click] to prevent"),
                            stringChoice("No action"),
                        }),
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                cg.runner_prompt_state = null;
                                if (std.mem.eql(u8, choice_text, "Spend [click] to prevent")) {
                                    cg.runner_click -= 1;
                                    cg.systemMsg(.runner, 35037, "Runner spends [click] to prevent Aggressive Trendsetting.", .{});
                                } else {
                                    cg.corp_extra_clicks_next_turn += 1;
                                    cg.systemMsg(.corp, 35037, "Aggressive Trendsetting: Corp gains +1 allotted [click] next turn.", .{});
                                }
                            }
                        }.choice,
                    };
                }
            }.handle,
        }},
    },
    .{
        .title = "Project Ingatan",
        .side = .corp,
        .code = 35038,
        .card_type = "Agenda",
        .subtypes = &.{"Research"},
        .agenda_points = 2,
        .advancement_requirement = 3,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Dividends 1: place 1 agenda counter per excess advancement
                    const req = card.advancement_requirement orelse 3;
                    const excess = if (card.advancement_counter > req) card.advancement_counter - req else 0;
                    if (excess > 0) {
                        // Update the scored agenda's counters
                        if (g.corp_scored.items.len > 0) {
                            g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = excess;
                        }
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Proprionegation",
        .side = .corp,
        .code = 35048,
        .card_type = "Agenda",
        .subtypes = &.{"Security"},
        .agenda_points = 2,
        .advancement_requirement = 4,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // "When you score this agenda, place 1 agenda counter on it."
                    if (g.corp_scored.items.len > 0) {
                        g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = 1;
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Sericulture Expansion",
        .side = .corp,
        .code = 35049,
        .card_type = "Agenda",
        .subtypes = &.{"Expansion"},
        .agenda_points = 2,
        .advancement_requirement = 3,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Dividends 1: place 1 agenda counter per excess advancement
                    const req = card.advancement_requirement orelse 3;
                    const excess = if (card.advancement_counter > req) card.advancement_counter - req else 0;
                    if (excess > 0 and g.corp_scored.items.len > 0) {
                        g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = excess;
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Embedded Reporting",
        .side = .corp,
        .code = 35059,
        .card_type = "Agenda",
        .subtypes = &.{"Initiative"},
        .agenda_points = 2,
        .advancement_requirement = 3,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Dividends 2: place 2 agenda counters per excess advancement
                    const req = card.advancement_requirement orelse 3;
                    const excess = if (card.advancement_counter > req) card.advancement_counter - req else 0;
                    if (excess > 0 and g.corp_scored.items.len > 0) {
                        g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = excess * 2;
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Next Big Thing",
        .side = .corp,
        .code = 35060,
        .card_type = "Agenda",
        .subtypes = &.{"Initiative"},
        .agenda_points = 3,
        .advancement_requirement = 5,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // "When scored or stolen, place 1 agenda counter on it."
                    if (g.corp_scored.items.len > 0) {
                        g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = 1;
                    }
                }
            }.handle,
        }},
    },
    .{ .title = "Greenmail", .side = .corp, .code = 35070, .card_type = "Agenda", .subtypes = &.{"Expansion"}, .agenda_points = 1, .advancement_requirement = 2, .install = .{ .kind = .corp_remote_only }, .event_abilities = &.{.{
        .event = .agenda_scored,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                g.corp_credit += 2;
                g.systemMsg(.corp, 0, "Corp gains 2 [credits].", .{});
            }
        }.handle,
    }} },
    .{
        .title = "Off the Books",
        .side = .corp,
        .code = 35071,
        .card_type = "Agenda",
        .subtypes = &.{"Initiative"},
        .agenda_points = 2,
        .advancement_requirement = 3,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Dividends 1: place 1 agenda counter per excess advancement
                    const req = card.advancement_requirement orelse 3;
                    const excess = if (card.advancement_counter > req) card.advancement_counter - req else 0;
                    if (excess > 0 and g.corp_scored.items.len > 0) {
                        g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = excess;
                    }
                }
            }.handle,
        }},
    },
    // --- Elevation ICE ---
    .{
        .title = "Bumi 1.0",
        .side = .corp,
        .code = 35041,
        .card_type = "ICE",
        .subtypes = &.{ "AP", "Bioroid", "Destroyer", "Sentry" },
        .cost = 3,
        .strength = 3,
        .install = .{ .kind = .corp_server_choice },
        .subroutines = &.{
            .{ .resolve = &resolveTrashProgramOrEtr, .label = "Trash 1 program or end the run" },
            .{ .resolve = &resolveBrainDamage, .amount = 1, .label = "Do 1 brain damage" },
        },
        .abilities = &.{.{ .on_use = &encounterBioroidHandler, .allow_opponent_use = true, .req = &isInEncounter, .cost = .{ .clicks = 1 }, .break_count = 1 }},
        // "When you rez this ice during a run against this server, you may trash 1 installed trojan program."
        .event_abilities = &.{.{
            .event = .corp_rez_ice,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.run == null) return;
                    // Find any installed trojan programs on any ICE
                    var has_trojan = false;
                    for (g.corp_servers.items) |server| {
                        for (server.ices.items) |ice| {
                            if (ice.hosted.items.len > 0) {
                                for (ice.hosted.items) |hosted| {
                                    if (hasSubtype(hosted, "Trojan")) {
                                        has_trojan = true;
                                        break;
                                    }
                                }
                            }
                            if (has_trojan) break;
                        }
                        if (has_trojan) break;
                    }
                    if (!has_trojan) return;
                    // Optional: auto-resolve trashes the first trojan found
                    for (g.corp_servers.items) |*server| {
                        for (server.ices.items) |*ice| {
                            for (ice.hosted.items, 0..) |hosted, idx| {
                                if (hasSubtype(hosted, "Trojan")) {
                                    const trashed = ice.hosted.orderedRemove(idx);
                                    g.systemMsg(.corp, 35041, "Corp uses Bumi 1.0 to trash {s}.", .{trashed.title});
                                    try appendDiscardCard(g, .runner, trashed);
                                    return;
                                }
                            }
                        }
                    }
                }
            }.handle,
        }},
    },
    .{ .title = "Scatter Field", .side = .corp, .code = 35042, .card_type = "ICE", .subtypes = &.{"Code Gate"}, .cost = 3, .strength = 0, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolveCorpInstallFromHqArchives, .label = "Install a card from HQ or Archives" },
        .{ .resolve = &resolveEndTheRun, .label = "End the run" },
    } },
    .{
        .title = "Empiricist",
        .side = .corp,
        .code = 35052,
        .card_type = "ICE",
        .subtypes = &.{ "AP", "Observer", "Sentry" },
        .cost = 7,
        .strength = 5,
        .install = .{ .kind = .corp_server_choice },
        .subroutines = &.{
            // Sub 1: "Corp draws 1 card. Corp may add 1 card from HQ to top of R&D."
            // Draw is automatic; add-to-top is optional (auto-declined in oracle)
            .{ .resolve = &resolveCorpGainsCredits, .amount = 0, .label = "Corp draws 1 card" }, // Sub 1: draw (simplified, handler removed)
            .{ .resolve = &resolveNetDamage, .amount = 1, .label = "Do 1 net damage" },
            .{ .resolve = &resolveNetDamage, .amount = 2, .label = "Do 2 net damage" },
        },
    },
    .{
        .title = "Mycoweb",
        .side = .corp,
        .code = 35053,
        .card_type = "ICE",
        .subtypes = &.{"Code Gate"},
        .cost = 8,
        .strength = 5,
        .install = .{ .kind = .corp_server_choice },
        .subroutines = &.{
            // Sub 1: Install a piece of ice from Archives (paying install cost)
            // Sub 2: Rez a piece of ice, paying 2cr less
            // Sub 3: Resolve a sentry subroutine on another rezzed ice
            // Sub 4: Resolve a code gate subroutine on another rezzed ice
            // Subs 3+4 need cross-ICE subroutine resolution (most complex card in set)
            .{ .resolve = &resolveCorpInstallFromHqArchives, .label = "Install a card from HQ or Archives" },
            .{ .resolve = &resolveRezIceWithDiscount, .label = "Rez a piece of ice, paying 2 less" },
            .{ .resolve = &resolveOtherIceSubroutine, .label = "Resolve a sentry subroutine on another rezzed ice" },
            .{ .resolve = &resolveOtherIceSubroutine, .label = "Resolve a code gate subroutine on another rezzed ice" },
        },
    },
    .{ .title = "Semak-samun", .side = .corp, .code = 35054, .card_type = "ICE", .subtypes = &.{ "AP", "Barrier" }, .cost = 3, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolveNetDamageUnlessEtr, .amount = 3, .label = "End the run unless the Runner suffers 3 net damage" },
    } },
    .{ .title = "Doomscroll", .side = .corp, .code = 35063, .card_type = "ICE", .subtypes = &.{ "AP", "Observer", "Sentry" }, .cost = 3, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolveTagRunner, .label = "Give the Runner 1 tag" },
        .{ .resolve = &resolveNetDamage, .amount = 1, .label = "Do 1 net damage" },
        .{ .resolve = &resolveConditionalNetDamageIfTagged, .amount = 2, .label = "Do 2 net damage if the Runner is tagged" },
    } },
    .{ .title = "N-Pot", .side = .corp, .code = 35064, .card_type = "ICE", .subtypes = &.{"Code Gate"}, .cost = 4, .strength = 4, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolveEndTheRun, .label = "End the run" },
        .{ .resolve = &resolveConditionalEtrThreat, .amount = 2, .label = "End the run if threat >= 2" },
        .{ .resolve = &resolveConditionalEtrThreat, .amount = 4, .label = "End the run if threat >= 4" },
    } },
    .{
        .title = "Biawak",
        .side = .corp,
        .code = 35074,
        .card_type = "ICE",
        .subtypes = &.{ "Destroyer", "Sentry" },
        .cost = 14,
        .strength = 6,
        .install = .{ .kind = .corp_server_choice },
        .subroutines = &.{
            .{ .resolve = &resolveTrashProgramOrResourceOrEtr, .amount = 0, .label = "Trash 1 installed card or end the run" }, // trash 1 program or ETR
            .{ .resolve = &resolveTrashProgramOrResourceOrEtr, .amount = 1, .label = "Trash 1 installed card or end the run" }, // trash 1 resource or ETR
            .{ .resolve = &resolveEndTheRun, .label = "End the run" },
        },
    },
    .{ .title = "Kessleroid", .side = .corp, .code = 35075, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 2, .strength = 1, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolveEndTheRun, .label = "End the run" },
        .{ .resolve = &resolveEndTheRun, .label = "End the run" },
    } },
    .{ .title = "Syailendra", .side = .corp, .code = 35076, .card_type = "ICE", .subtypes = &.{ "AP", "Code Gate" }, .cost = 4, .strength = 5, .static_abilities = &.{.{ .kind = .can_advance }}, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .resolve = &resolvePlaceAdvancementCounter, .amount = 1, .label = "Place 1 advancement counter" },
        .{ .resolve = &resolveRunnerLosesCredits, .amount = 2, .label = "Runner loses 2 [Credits]" },
        .{ .resolve = &resolveNetDamage, .amount = 1, .label = "Do 1 net damage" },
    } },
    .{
        .title = "Flyswatter",
        .side = .corp,
        .code = 35079,
        .card_type = "ICE",
        .subtypes = &.{"Code Gate"},
        .cost = 2,
        .strength = 0,
        .install = .{ .kind = .corp_server_choice },
        .subroutines = &.{
            .{ .resolve = &resolveEndTheRun, .label = "End the run" },
        },
        .event_abilities = &.{.{
            .event = .corp_rez_ice,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // "When you rez this ice during a run against this server, purge virus counters."
                    purgeVirusCounters(g);
                    g.systemMsg(.corp, 35079, "Corp uses Flyswatter to purge virus counters.", .{});
                }
            }.handle,
        }},
    },
    .{
        .title = "Lamplighter",
        .side = .corp,
        .code = 35080,
        .card_type = "ICE",
        .subtypes = &.{ "Observer", "Sentry" },
        .cost = 2,
        .strength = 3,
        .install = .{ .kind = .corp_server_choice },
        .subroutines = &.{ .{ .resolve = &resolveTagOrPayCreditsEtr, .amount = 3, .label = "Sub 0" }, .{ .resolve = &resolveEtrIfTagged, .label = "End the run if the Runner is tagged" } },
        .event_abilities = blk: {
            const H = struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (!card.rezzed) return;
                    const g = gameFromEffectContext(ctx);
                    const payload = ctx.event orelse return;
                    const agenda_server = payload.server_index orelse return;
                    // Find which server this ICE is on and trash self if it matches
                    for (g.corp_servers.items, 0..) |*server, si| {
                        for (server.ices.items, 0..) |ice, ii| {
                            if (ice.instance_id == card.instance_id) {
                                if (si == agenda_server) {
                                    const trashed = server.ices.orderedRemove(ii);
                                    try appendDiscardCard(g, .corp, trashed);
                                    g.systemMsg(.corp, 35080, "Corp trashes Lamplighter.", .{});
                                    try removeServerIfEmpty(g, si);
                                }
                                return;
                            }
                        }
                    }
                }
            };
            break :blk &[_]state.EventAbility{
                .{ .event = .agenda_scored, .automatic_priority = state.Priority.pre_draw_cards, .handler = &H.handle },
                .{ .event = .agenda_stolen, .automatic_priority = state.Priority.pre_draw_cards, .handler = &H.handle },
            };
        },
    },
    // --- Elevation Assets ---
    .{
        .title = "Humanoid Resources",
        .side = .corp,
        .code = 35039,
        .card_type = "Asset",
        .cost = 1,
        .trash_cost = 1,
        .install = .{ .kind = .corp_remote_only },
        // "[click][click][click], [trash]: Gain 4cr, draw 3. Install up to 2 from HQ. Play 1 operation from HQ."
        .abilities = &.{.{
            .cost = .{ .clicks = 3 },
            .label = "Gain 4 [Credits], draw 3, install up to 2, play 1 operation",
            .req = &struct {
                fn check(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                    return card.rezzed;
                }
            }.check,
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    try trashCorpServerCardByInstanceId(g, card.instance_id);
                    g.corp_credit += 4;
                    try drawCards(g, .corp, 3);
                    g.systemMsg(.corp, 35039, "Corp uses Humanoid Resources: gains 4 [credits] and draws 3 cards.", .{});
                    try beginInstallStep(g, 0);
                }
                fn beginInstallStep(g: *GE.Game, done: u8) !void {
                    if (done >= 2) { try beginOpStep(g); return; }
                    const alloc = g.ephemeralAllocator();
                    var ch: std.ArrayList(state.PromptChoice) = .empty;
                    defer ch.deinit(alloc);
                    for (g.corp_hand.items, 0..) |c, idx| {
                        const ct = c.card_type orelse continue;
                        if (std.mem.eql(u8, ct, "Operation")) continue;
                        try ch.append(alloc, .{ .kind = .card, .text = try alloc.dupe(u8, c.title),
                            .card = .{ .title = c.title, .code = c.code, .side = .corp, .index = @intCast(idx) } });
                    }
                    if (ch.items.len == 0) { try beginOpStep(g); return; }
                    try ch.append(alloc, stringChoice("Done installing"));
                    g.corp_prompt_state = .{
                        .prompt_type = "humanoid-install-card",
                        .choices = try ch.toOwnedSlice(alloc),
                        .ability_ref = .{ .source_instance_id = 0, .ability_index = done },
                        .on_choice = &onChoice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(alloc, .corp, g.corp_prompt_state.?);
                }
                fn onChoice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const cg = gameFromEffectContext(cctx);
                    const alloc = cg.ephemeralAllocator();
                    const prompt = cg.corp_prompt_state orelse return;
                    const ref = prompt.ability_ref orelse return;
                    const done = ref.ability_index;
                    const pt = prompt.prompt_type;
                    if (std.mem.eql(u8, pt, "humanoid-install-card")) {
                        if (std.mem.eql(u8, choice_text, "Done installing")) {
                            cg.corp_prompt_state = null;
                            try beginOpStep(cg);
                            return;
                        }
                        for (prompt.choices) |pc| {
                            if (pc.text != null and std.mem.eql(u8, pc.text.?, choice_text)) {
                                if (pc.card) |cr| {
                                    const ci = cr.index orelse continue;
                                    if (ci >= cg.corp_hand.items.len) return;
                                    const ik = cg.corp_hand.items[ci].install.kind;
                                    cg.corp_prompt_state = .{
                                        .prompt_type = "humanoid-install-server",
                                        .choices = try installChoicesForCard(alloc, ik, cg),
                                        .ability_ref = .{ .source_instance_id = 0, .ability_index = done },
                                        .min_choices = ci,
                                        .on_choice = &onChoice,
                                    };
                                    cg.decision_side = .corp;
                                    cg.legal_actions = try promptChoiceActions(alloc, .corp, cg.corp_prompt_state.?);
                                    return;
                                }
                            }
                        }
                    } else if (std.mem.eql(u8, pt, "humanoid-install-server")) {
                        const ci = prompt.min_choices;
                        if (ci >= cg.corp_hand.items.len) return;
                        const title = cg.corp_hand.items[ci].title;
                        try installCorpCardFromHand(cg, ci, choice_text);
                        cg.systemMsg(.corp, 35039, "Corp installs {s}.", .{title});
                        cg.corp_prompt_state = null;
                        try beginInstallStep(cg, done + 1);
                    }
                }
                fn beginOpStep(g: *GE.Game) !void {
                    const alloc = g.ephemeralAllocator();
                    var ch: std.ArrayList(state.PromptChoice) = .empty;
                    defer ch.deinit(alloc);
                    for (g.corp_hand.items, 0..) |c, idx| {
                        const ct = c.card_type orelse continue;
                        if (!std.mem.eql(u8, ct, "Operation")) continue;
                        if (g.corp_credit < (c.cost orelse 0)) continue;
                        try ch.append(alloc, .{ .kind = .card, .text = try alloc.dupe(u8, c.title),
                            .card = .{ .title = c.title, .code = c.code, .side = .corp, .index = @intCast(idx) } });
                    }
                    if (ch.items.len == 0) {
                        g.corp_prompt_state = null;
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(alloc, g);
                        return;
                    }
                    try ch.append(alloc, stringChoice("Done"));
                    g.corp_prompt_state = .{
                        .prompt_type = "humanoid-operation",
                        .choices = try ch.toOwnedSlice(alloc),
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, ct: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                cg.corp_prompt_state = null;
                                if (!std.mem.eql(u8, ct, "Done")) {
                                    for (cg.corp_hand.items, 0..) |c, idx| {
                                        if (std.mem.eql(u8, c.title, ct)) {
                                            const op = cg.corp_hand.orderedRemove(idx);
                                            try spendCredits(cg, .corp, op.cost orelse 0);
                                            try logCorpOperationPlay(cg, op, false);
                                            try resolveCorpOperation(cg, op);
                                            if (hasActivePrompt(cg)) return;
                                            break;
                                        }
                                    }
                                }
                                if (try resumePendingEffects(cg)) return;
                                cg.decision_side = .corp;
                                cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(alloc, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Otto Campaign",
        .side = .corp,
        .code = 35040,
        .card_type = "Asset",
        .subtypes = &.{"Advertisement"},
        .cost = 2,
        .trash_cost = 2,
        .install = .{ .kind = .corp_remote_only },
        .initial_credit_counters = 6,
        .take_credits_amount = 2,
        .trash_on_empty = true,
        .clicks_on_empty = 2,
        .event_abilities = &.{.{
            .event = .corp_turn_begins,
            .automatic_priority = state.Priority.gain_credits,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (card.credit_counter == 0) return;
                    const g = gameFromEffectContext(ctx);
                    const take = @min(card.credit_counter, card.take_credits_amount);
                    card.credit_counter -= take;
                    g.corp_credit += take;
                    g.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to take {d} [credit{s}].", .{
                        card.title, take, if (take != 1) "s" else "",
                    });
                    if (card.trash_on_empty and card.credit_counter == 0) {
                        if (card.clicks_on_empty > 0) g.corp_click += card.clicks_on_empty;
                        try trashCorpServerCardByInstanceId(g, card.instance_id);
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Byte!",
        .side = .corp,
        .code = 35050,
        .card_type = "Asset",
        .subtypes = &.{"Ambush"},
        .cost = 0,
        .trash_cost = 0,
        .install = .{ .kind = .corp_remote_only },
        // "When the Runner accesses this asset, you may pay 4[c] to give the Runner 1 tag and do 3 net damage."
        .event_abilities = &.{.{
            .event = .access,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    _ = try beginByteAmbushPrompt(gameFromEffectContext(ctx), card.*);
                }
            }.handle,
        }},
    },
    .{
        .title = "Ph\xe1\xba\xadt Gioan Baotixita",
        .side = .corp,
        .code = 35051,
        .card_type = "Asset",
        .subtypes = &.{"Executive"},
        .cost = 1,
        .trash_cost = 3,
        .install = .{ .kind = .corp_remote_only },
        // "When your turn ends, place 1 power counter on this asset."
        // "When an agenda is scored or stolen, you may remove up to 3 hosted power counters to do that much net damage."
        .event_abilities = &.{
            .{
                .event = .corp_end_turn,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (!card.rezzed) return;
                        card.power_counter += 1;
                        const g = gameFromEffectContext(ctx);
                        g.systemMsg(.corp, 35051, "Corp places 1 power counter on Ph\xe1\xba\xadt Gioan Baotixita ({d} total).", .{card.power_counter});
                    }
                }.handle,
            },
            .{
                .event = .agenda_scored,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (!card.rezzed) return;
                        if (card.power_counter == 0) return;
                        try beginPhatGioanDamagePrompt(gameFromEffectContext(ctx), card);
                    }
                }.handle,
            },
            .{
                .event = .agenda_stolen,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (!card.rezzed) return;
                        if (card.power_counter == 0) return;
                        try beginPhatGioanDamagePrompt(gameFromEffectContext(ctx), card);
                    }
                }.handle,
            },
        },
    },
    .{
        .title = "Idiosyncresis",
        .side = .corp,
        .code = 35061,
        .card_type = "Asset",
        .subtypes = &.{"Hostile"},
        .cost = 1,
        .trash_cost = 2,
        .static_abilities = &.{.{ .kind = .can_advance }},
        .install = .{ .kind = .corp_remote_only },
        // "When your turn begins, you may trash this asset. If you do, for each hosted advancement counter, gain 3[c] and the Runner loses 2[c]."
        .event_abilities = &.{.{
            .event = .corp_turn_begins,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (card.advancement_counter == 0) return;
                    if (!card.rezzed) return;
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    g.corp_prompt_state = .{
                        .prompt_type = "idiosyncresis-trash",
                        .choices = try allocator.dupe(state.PromptChoice, &.{
                            stringChoice("Trash Idiosyncresis"),
                            stringChoice("No action"),
                        }),
                        .ability_ref = .{ .source_instance_id = card.instance_id, .ability_index = 0 },
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const ref = (cg.corp_prompt_state orelse return).ability_ref orelse return;
                                cg.corp_prompt_state = null;
                                if (std.mem.eql(u8, choice_text, "No action")) return;
                                const live_card = findCardPtrByInstanceId(cg, ref.source_instance_id) orelse return;
                                const counters = live_card.advancement_counter;
                                const iid = live_card.instance_id;
                                try trashCorpServerCardByInstanceId(cg, iid);
                                const gain: u16 = @as(u16, counters) * 3;
                                const drain: u16 = @as(u16, counters) * 2;
                                cg.corp_credit += gain;
                                cg.runner_credit = if (cg.runner_credit >= drain) cg.runner_credit - drain else 0;
                                cg.systemMsg(.corp, 35061, "Corp trashes Idiosyncresis: gains {d} [credits], runner loses {d} [credits].", .{ gain, drain });
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Public Access Plaza",
        .side = .corp,
        .code = 35062,
        .card_type = "Asset",
        .cost = 1,
        .trash_cost = 2,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{
            .{
                .event = .corp_turn_begins,
                .automatic_priority = state.Priority.gain_credits,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (!card.rezzed) return;
                        const g = gameFromEffectContext(ctx);
                        g.corp_credit += 1;
                        g.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to gain 1 [credit].", .{card.title});
                    }
                }.handle,
            },
            .{
                // "When the Runner trashes this asset, if the threat level is 2 or more, give the Runner 1 tag."
                .event = .corp_card_runner_trashed,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (!card.rezzed) return;
                        const payload = ctx.event orelse return;
                        if (payload.target_instance_id != card.instance_id) return;
                        const g = gameFromEffectContext(ctx);
                        if (threatLevel(g) < 2) return;
                        _ = try addRunnerTag(g, 1);
                        g.systemMsg(.corp, 35062, "Corp uses {s}: runner trashed at threat {d}, runner gains 1 tag.", .{ card.title, threatLevel(g) });
                    }
                }.handle,
            },
        },
    },
    .{
        .title = "Anthill Excavation Contract",
        .side = .corp,
        .code = 35072,
        .card_type = "Asset",
        .subtypes = &.{"Industrial"},
        .cost = 3,
        .trash_cost = 1,
        .install = .{ .kind = .corp_remote_only },
        .initial_credit_counters = 8,
        .take_credits_amount = 4,
        .trash_on_empty = true,
        .draw_on_take = 1,
        .event_abilities = &.{.{
            .event = .corp_turn_begins,
            .automatic_priority = state.Priority.draw_cards,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (card.credit_counter == 0) return;
                    const g = gameFromEffectContext(ctx);
                    const take = @min(card.credit_counter, card.take_credits_amount);
                    card.credit_counter -= take;
                    g.corp_credit += take;
                    if (card.draw_on_take > 0) try drawCards(g, .corp, card.draw_on_take);
                    g.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to take {d} [credit{s}].", .{
                        card.title, take, if (take != 1) "s" else "",
                    });
                    if (card.trash_on_empty and card.credit_counter == 0) {
                        try trashCorpServerCardByInstanceId(g, card.instance_id);
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Plutus",
        .side = .corp,
        .code = 35073,
        .card_type = "Asset",
        .subtypes = &.{"Deep Net"},
        .cost = 0,
        .trash_cost = 3,
        .install = .{ .kind = .corp_remote_only },
        // "Additional rez cost: forfeit an agenda or trash 3 from HQ."
        // "Start of turn: optionally play a Transaction from Archives (RFG instead of trash)."
        .event_abilities = &.{
            // On-rez: require additional cost (forfeit agenda or trash 3 from HQ)
            .{
                .event = .corp_rez_ice, // fires for non-ice rez too via applyRezNonIce
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (card.code == null or card.code.? != 35073) return;
                        const g = gameFromEffectContext(ctx);
                        const allocator = g.ephemeralAllocator();
                        var choices: std.ArrayList(state.PromptChoice) = .empty;
                        defer choices.deinit(allocator);
                        // Option 1: forfeit a scored agenda
                        if (g.corp_scored.items.len > 0) {
                            for (g.corp_scored.items) |a| {
                                try choices.append(allocator, stringChoice(
                                    try std.fmt.allocPrint(allocator, "Forfeit {s}", .{a.title}),
                                ));
                            }
                        }
                        // Option 2: trash 3 from HQ (requires 3+ cards in HQ)
                        if (g.corp_hand.items.len >= 3) {
                            try choices.append(allocator, stringChoice("Trash 3 cards from HQ"));
                        }
                        if (choices.items.len == 0) {
                            // Can't pay additional cost — derez
                            card.rezzed = false;
                            g.corp_credit += card.cost orelse 0; // refund
                            g.systemMsg(.corp, 35073, "Plutus: Corp cannot pay additional rez cost, derezzing.", .{});
                            return;
                        }
                        g.corp_prompt_state = .{
                            .prompt_type = "plutus-rez-cost",
                            .choices = try choices.toOwnedSlice(allocator),
                            .ability_ref = .{ .source_instance_id = card.instance_id },
                            .on_choice = &struct {
                                fn choice(cctx: *state.EffectContext, ct: []const u8) anyerror!void {
                                    const cg = gameFromEffectContext(cctx);
                                    cg.corp_prompt_state = null;
                                    if (std.mem.startsWith(u8, ct, "Forfeit ")) {
                                        const title = ct["Forfeit ".len..];
                                        for (cg.corp_scored.items, 0..) |a, idx| {
                                            if (std.mem.eql(u8, a.title, title)) {
                                                _ = cg.corp_scored.orderedRemove(idx);
                                                cg.corp_agenda_point -= a.agenda_points orelse 0;
                                                cg.systemMsg(.corp, 35073, "Plutus: Corp forfeits {s} as additional rez cost.", .{title});
                                                break;
                                            }
                                        }
                                    } else if (std.mem.eql(u8, ct, "Trash 3 cards from HQ")) {
                                        // Corp chooses which cards to trash (up to 3)
                                        try beginPlutusTrashPrompt(cg, 0);
                                        return;
                                    }
                                }
                            }.choice,
                        };
                    }
                }.handle,
            },
            .{
            .event = .corp_turn_begins,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (!card.rezzed) return;
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    // Find Transactions in Archives
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_discard.items) |c| {
                        const ct = c.card_type orelse continue;
                        if (!std.mem.eql(u8, ct, "Operation")) continue;
                        if (!hasSubtype(c, "Transaction")) continue;
                        try choices.append(allocator, stringChoice(try allocator.dupe(u8, c.title)));
                    }
                    if (choices.items.len == 0) return;
                    try choices.append(allocator, stringChoice("No action"));
                    g.corp_prompt_state = .{
                        .prompt_type = "plutus-transaction",
                        .choices = try choices.toOwnedSlice(allocator),
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, ct: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                cg.corp_prompt_state = null;
                                if (std.mem.eql(u8, ct, "No action")) return;
                                for (cg.corp_discard.items, 0..) |c, idx| {
                                    if (std.mem.eql(u8, c.title, ct)) {
                                        const op = cg.corp_discard.orderedRemove(idx);
                                        cg.systemMsg(.corp, 35073, "Plutus plays {s} from Archives (removed from game).", .{op.title});
                                        try resolveCorpOperation(cg, op);
                                        // RFG: don't append to discard
                                        return;
                                    }
                                }
                            }
                        }.choice,
                    };
                }
            }.handle,
        }},
    },
    // --- Elevation Upgrades ---
    .{
        .title = "Mercia B4LL4RD",
        .side = .corp,
        .code = 35045,
        .card_type = "Upgrade",
        .subtypes = &.{ "Academic", "Bioroid" },
        .cost = 2,
        .trash_cost = 2,
        .install = .{ .kind = .corp_server_choice },
        // "End of corp action phase: install ICE from HQ at -1[c], move Mercia to that server."
        // Matches Clojure: auto-select first ICE from HQ, show server selection prompt
        .event_abilities = &.{.{
            .event = .corp_end_turn,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    // Find first ICE in HQ (Clojure auto-selects via :choices {:card ...})
                    var ice_idx: ?usize = null;
                    for (g.corp_hand.items, 0..) |hcard, idx| {
                        if (std.mem.eql(u8, hcard.card_type orelse "", "ICE")) {
                            ice_idx = idx;
                            break;
                        }
                    }
                    if (ice_idx == null) return;
                    const selected_ice = g.corp_hand.items[ice_idx.?];
                    const mercia_iid = card.instance_id;
                    // Show server selection prompt (matches oracle's visible prompt)
                    const server_choices = try iceInstallChoices(allocator, g);
                    g.corp_prompt_state = .{
                        .prompt_type = "mercia-install-server",
                        .choices = server_choices,
                        .source_card = selected_ice,
                        .ability_ref = .{ .source_instance_id = mercia_iid, .ability_index = @intCast(ice_idx.?) },
                        .on_choice = &struct {
                            fn choice(sctx: *state.EffectContext, server_name: []const u8) anyerror!void {
                                const sg = gameFromEffectContext(sctx);
                                const ref = (sg.corp_prompt_state orelse return).ability_ref orelse return;
                                const ice = (sg.corp_prompt_state orelse return).source_card orelse return;
                                const m_iid = ref.source_instance_id;
                                const i_idx = ref.ability_index;
                                sg.corp_prompt_state = null;
                                // Install ICE at -1[c] cost via generic corp-install cost model
                                try corpInstallIce(sg, i_idx, server_name, -1);
                                sg.systemMsg(.corp, 35045, "Mercia B4LL4RD: Corp installs {s} at -1[credits].", .{ice.title});
                                // Move Mercia to the target server
                                const target_idx: usize = blk: {
                                    for (sg.corp_servers.items, 0..) |srv, si| {
                                        for (srv.ices.items) |ic| {
                                            if (ic.instance_id == ice.instance_id) break :blk si;
                                        }
                                    }
                                    break :blk sg.corp_servers.items.len - 1;
                                };
                                outer: for (sg.corp_servers.items) |*server| {
                                    for (server.content.items, 0..) |c, ci| {
                                        if (c.instance_id == m_iid) {
                                            const mercia = server.content.orderedRemove(ci);
                                            try sg.corp_servers.items[target_idx].content.append(sg.backing_allocator, mercia);
                                            sg.systemMsg(.corp, 35045, "Mercia B4LL4RD moves to the new server.", .{});
                                            break :outer;
                                        }
                                    }
                                }
                                // End-of-turn ability complete — transition to runner's turn
                                try beginStartTurnSequence(sg, .runner);
                            }
                        }.choice,
                    };
                    // Corp has a prompt — set decision to corp
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Mitra Aman",
        .side = .corp,
        .code = 35056,
        .card_type = "Upgrade",
        .subtypes = &.{"Clone"},
        .cost = 0,
        .trash_cost = 3,
        .install = .{ .kind = .corp_server_choice },
        // "When the Runner approaches this server, you may trash this upgrade to gain 3[c]
        //  and swap the approached ICE with an ICE from HQ or Archives."
        .event_abilities = &.{.{
            .event = .server_approached,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    const choices = try allocator.dupe(state.PromptChoice, &.{
                        stringChoice("Trash Mitra Aman: Gain 3[Credits]"),
                        stringChoice("No action"),
                    });
                    g.corp_prompt_state = .{
                        .prompt_type = "mitra-swap",
                        .choices = choices,
                        .source_card = card.*,
                        .ability_ref = .{ .source_instance_id = card.instance_id },
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                // Capture instance_id before clearing prompt
                                const mitra_iid: u32 = if (cg.corp_prompt_state) |ps|
                                    (if (ps.ability_ref) |ref| ref.source_instance_id else 0)
                                else
                                    0;
                                cg.corp_prompt_state = null;
                                if (std.mem.eql(u8, choice_text, "No action")) {
                                    try continueServerApproach(cg);
                                    return;
                                }
                                // "Trash Mitra Aman: Gain 3[Credits]" — trash Mitra, gain 3cr, continue run
                                cg.corp_credit += 3;
                                cg.systemMsg(.corp, 35056, "Mitra Aman: Corp gains 3[credits].", .{});
                                // Trash Mitra Aman
                                outer: for (cg.corp_servers.items) |*server| {
                                    for (server.content.items, 0..) |c, ci| {
                                        const matches = if (mitra_iid != 0)
                                            c.instance_id == mitra_iid
                                        else
                                            (c.code != null and c.code.? == 35056);
                                        if (matches) {
                                            const trashed = server.content.orderedRemove(ci);
                                            try appendDiscardCard(cg, .corp, trashed);
                                            break :outer;
                                        }
                                    }
                                }
                                // Build swap choices: ICE from HQ and Archives
                                const c_alloc = cg.ephemeralAllocator();
                                var swap_ch: std.ArrayList(state.PromptChoice) = .empty;
                                defer swap_ch.deinit(c_alloc);
                                for (cg.corp_hand.items) |c| {
                                    const ct = c.card_type orelse continue;
                                    if (std.mem.eql(u8, ct, "ICE")) {
                                        try swap_ch.append(c_alloc, stringChoice(try std.fmt.allocPrint(c_alloc, "HQ: {s}", .{c.title})));
                                    }
                                }
                                for (cg.corp_discard.items) |c| {
                                    const ct = c.card_type orelse continue;
                                    if (std.mem.eql(u8, ct, "ICE")) {
                                        try swap_ch.append(c_alloc, stringChoice(try std.fmt.allocPrint(c_alloc, "Archives: {s}", .{c.title})));
                                    }
                                }
                                if (swap_ch.items.len == 0) {
                                    try continueServerApproach(cg);
                                    return;
                                }
                                try swap_ch.append(c_alloc, stringChoice("No swap"));
                                cg.corp_prompt_state = .{
                                    .prompt_type = "mitra-ice-swap",
                                    .choices = try swap_ch.toOwnedSlice(c_alloc),
                                    .on_choice = &struct {
                                        fn ch(ccctx: *state.EffectContext, ct: []const u8) anyerror!void {
                                            const g3 = gameFromEffectContext(ccctx);
                                            g3.corp_prompt_state = null;
                                            if (!std.mem.eql(u8, ct, "No swap")) {
                                                // Find the approached ice position
                                                const run = g3.run orelse {
                                                    try continueServerApproach(g3);
                                                    return;
                                                };
                                                const target_srv = findServerByRunPath(g3.corp_servers.items, run.server) catch {
                                                    try continueServerApproach(g3);
                                                    return;
                                                };
                                                const srv = &g3.corp_servers.items[target_srv.index];
                                                const ice_count = srv.ices.items.len;
                                                const ice_pos = ice_count -| (run.position + 1);
                                                if (ice_pos < ice_count) {
                                                    // Remove approached ice, put it where the new ice came from
                                                    const old_ice = srv.ices.orderedRemove(ice_pos);
                                                    var new_ice: ?state.CardInstance = null;
                                                    if (std.mem.startsWith(u8, ct, "HQ: ")) {
                                                        const title = ct["HQ: ".len..];
                                                        for (g3.corp_hand.items, 0..) |c2, idx2| {
                                                            if (std.mem.eql(u8, c2.title, title)) {
                                                                new_ice = g3.corp_hand.orderedRemove(idx2);
                                                                break;
                                                            }
                                                        }
                                                        // Old ice goes to HQ
                                                        try g3.corp_hand.append(g3.backing_allocator, old_ice);
                                                    } else if (std.mem.startsWith(u8, ct, "Archives: ")) {
                                                        const title = ct["Archives: ".len..];
                                                        for (g3.corp_discard.items, 0..) |c2, idx2| {
                                                            if (std.mem.eql(u8, c2.title, title)) {
                                                                new_ice = g3.corp_discard.orderedRemove(idx2);
                                                                break;
                                                            }
                                                        }
                                                        // Old ice goes to Archives
                                                        try appendDiscardCard(g3, .corp, old_ice);
                                                    }
                                                    if (new_ice) |ni| {
                                                        try srv.ices.insert(g3.backing_allocator, ice_pos, ni);
                                                        g3.systemMsg(.corp, 35056, "Mitra Aman: swaps {s} with {s}.", .{ old_ice.title, ni.title });
                                                    }
                                                }
                                            }
                                            try continueServerApproach(g3);
                                        }
                                    }.ch,
                                };
                                cg.decision_side = .corp;
                                cg.legal_actions = try promptChoiceActions(c_alloc, .corp, cg.corp_prompt_state.?);
                                return;
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Mahkota Langit Grid",
        .side = .corp,
        .code = 35082,
        .card_type = "Upgrade",
        .subtypes = &.{"Region"},
        .cost = 2,
        .trash_cost = 2,
        .install = .{ .kind = .corp_server_choice },
        // "2 recurring credits for rezzing ice/assets in this server."
        // "The trash cost of each asset in this server's root is increased by 2."
        // "When the Runner trashes this upgrade during a run, the trash cost bonus persists until end of run."
        .initial_credit_counters = 2,
        .pay_credits = .{
            .context = .corp_rez,
            .req = &struct {
                fn check(ctx: *const state.EffectContext, source: *const state.CardInstance, target: ?*const state.CardInstance) bool {
                    const t = target orelse return false;
                    // Only for ice or assets
                    const ct = t.card_type orelse return false;
                    if (!std.mem.eql(u8, ct, "ICE") and !std.mem.eql(u8, ct, "Asset")) return false;
                    // Must be in the same server
                    const g = gameFromConstEffectContext(ctx);
                    for (g.corp_servers.items) |server| {
                        var found_source = false;
                        var found_target = false;
                        for (server.content.items) |c| {
                            if (c.instance_id == source.instance_id) found_source = true;
                            if (c.instance_id == t.instance_id) found_target = true;
                        }
                        for (server.ices.items) |ice| {
                            if (ice.instance_id == t.instance_id) found_target = true;
                        }
                        if (found_source and found_target) return true;
                        if (found_source) return false;
                    }
                    return false;
                }
            }.check,
        },
        .event_abilities = &.{
            // Recurring credits: reset to 2 at start of corp turn
            .{
                .event = .corp_turn_begins,
                .handler = &struct {
                    fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (!card.rezzed) return;
                        card.credit_counter = 2;
                    }
                }.handle,
            },
            // On-trash by runner during a run: register lingering +2 trash cost for assets in same server
            .{
                .event = .corp_card_runner_trashed,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (!card.rezzed) return;
                        const payload = ctx.event orelse return;
                        if (payload.target_instance_id != card.instance_id) return;
                        const g = gameFromEffectContext(ctx);
                        if (g.run == null) return; // Only during a run
                        // Find server index for this card
                        for (g.corp_servers.items, 0..) |server, idx| {
                            for (server.content.items) |c| {
                                if (c.instance_id == card.instance_id) {
                                    try addFloatingEffect(g, .{
                                        .kind = .trash_cost,
                                        .duration = .end_of_run,
                                        .value = 2,
                                        .source_code = 35082,
                                        .target_server = @intCast(idx),
                                    });
                                    return;
                                }
                            }
                        }
                    }
                }.handle,
            },
        },
        .static_abilities = &.{.{
            .kind = .trash_cost,
            .value = 2,
            .req = &struct {
                fn check(ctx: *const state.EffectContext, card: *const state.CardInstance, target: ?*const state.CardInstance) i16 {
                    const t = target orelse return 0;
                    // Only boost assets (not upgrades or ICE)
                    if (t.card_type == null) return 0;
                    if (!std.mem.eql(u8, t.card_type.?, "Asset")) return 0;
                    const g = gameFromConstEffectContext(ctx);
                    // Check if both this card and the target are in the same server
                    for (g.corp_servers.items) |server| {
                        var found_self = false;
                        var found_target = false;
                        for (server.content.items) |c| {
                            if (c.instance_id == card.instance_id) found_self = true;
                            if (c.instance_id == t.instance_id) found_target = true;
                        }
                        if (found_self and found_target) return 1;
                        if (found_self) return 0; // target is in a different server
                    }
                    return 0;
                }
            }.check,
        }},
    },
    // --- Elevation Operations ---
    .{ .title = "Nanomanagement", .side = .corp, .code = 35043, .card_type = "Operation", .cost = 4, .abilities = &.{.{ .is_play = true, .on_use = &struct {
        fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
            const g = gameFromEffectContext(ctx);
            g.corp_click += 2;
        }
    }.play }} },
    .{
        .title = "Top-Down Solutions",
        .side = .corp,
        .code = 35044,
        .card_type = "Operation",
        .cost = 2,
        .abilities = &.{.{
            .is_play = true,
            .on_use = &struct {
                const top_down_on_choice = &struct {
                    fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                        const g = gameFromEffectContext(cctx);
                        const allocator = g.ephemeralAllocator();
                        const prompt = g.corp_prompt_state orelse return error.NoPromptState;
                        if (std.mem.eql(u8, prompt.prompt_type, "top-down-card")) {
                            if (std.mem.eql(u8, choice_text, "Done")) {
                                g.corp_prompt_state = null;
                                g.decision_side = .corp;
                                g.legal_actions = try corpOpeningActionsForState(allocator, g);
                                return;
                            }
                            for (prompt.choices) |ch| {
                                if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                                    if (ch.card) |card_ref| {
                                        const card_idx = card_ref.index orelse continue;
                                        const install_kind: state.InstallKind = blk: {
                                            if (card_idx < g.corp_hand.items.len) {
                                                const ct = g.corp_hand.items[card_idx].card_type orelse break :blk .corp_remote_only;
                                                if (std.mem.eql(u8, ct, "ICE")) break :blk .corp_server_choice;
                                            }
                                            break :blk .corp_remote_only;
                                        };
                                        const server_choices = try installChoicesForCard(allocator, install_kind, g);
                                        g.corp_prompt_state = .{
                                            .prompt_type = "top-down-server",
                                            .choices = server_choices,
                                            .ability_ref = prompt.ability_ref,
                                            .min_choices = @intCast((card_idx & 0xF) | (@as(u8, prompt.min_choices) << 4)),
                                            .on_choice = &@This().choice,
                                        };
                                        g.decision_side = .corp;
                                        g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                                        return;
                                    }
                                }
                            }
                            return error.UnsupportedChoice;
                        } else if (std.mem.eql(u8, prompt.prompt_type, "top-down-server")) {
                            const pack_val = prompt.min_choices;
                            const card_idx: u8 = pack_val & 0xF;
                            const installs_done: u8 = pack_val >> 4;
                            try installCorpCardFromHand(g, card_idx, choice_text);
                            g.systemMsg(.corp, 35044, "Corp uses Top-Down Solutions to install a card.", .{});
                            if (installs_done + 1 >= 2) {
                                g.corp_prompt_state = null;
                                g.decision_side = .corp;
                                g.legal_actions = try corpOpeningActionsForState(allocator, g);
                            } else {
                                const ref = prompt.ability_ref orelse return error.MissingAbilityRef;
                                try showTopDownInstallChoices(g, ref.source_instance_id, installs_done + 1, &@This().choice);
                            }
                        } else return error.UnsupportedChoice;
                    }
                }.choice;
                fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // "Draw 2 cards. Install up to 2 cards from HQ (one at a time)."
                    try drawCards(g, .corp, 2);
                    g.systemMsg(.corp, 35044, "Corp uses Top-Down Solutions to draw 2 cards.", .{});
                    // Offer install prompt
                    try showTopDownInstallChoices(g, card.instance_id, 0, top_down_on_choice);
                }
            }.play,
        }},
    },
    .{
        .title = "Peer Review",
        .side = .corp,
        .code = 35055,
        .card_type = "Operation",
        .subtypes = &.{"Transaction"},
        .cost = 4,
        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.ephemeralAllocator();
                if (g.corp_hand.items.len >= 2) {
                    var private_choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer private_choices.deinit(allocator);
                    for (g.corp_hand.items, 0..) |c, idx| {
                        try private_choices.append(allocator, .{
                            .kind = .card,
                            .text = try std.fmt.allocPrint(allocator, "{s}", .{c.title}),
                            .card = .{ .title = c.title, .code = c.code, .side = .corp, .index = @intCast(idx) },
                        });
                    }
                    g.corp_prompt_state = .{
                        .prompt_type = "peer-review-private",
                        .choices = try private_choices.toOwnedSlice(allocator),
                        .ability_ref = .{ .source_instance_id = card.instance_id },
                        .on_choice = peer_review_on_choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    return;
                }
                try beginPeerReviewInstallPrompt(g, card.instance_id, peer_review_on_choice);
            }
        }.play }},
    },
    .{
        .title = "Bigger Picture",
        .side = .corp,
        .code = 35065,
        .card_type = "Operation",
        .subtypes = &.{"Gray Ops"},
        .cost = 0,
        .abilities = &.{.{
            .is_play = true,
            .req = &struct {
                fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    // "Play only if the Runner is tagged."
                    return if (g.runner_tag) |t| t.is_tagged else false;
                }
            }.req,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // "Choose: Give the Runner 1 tag OR Remove any number of tags. Runner loses 5cr per tag. Gain credits equal to credits lost."
                    const allocator = g.ephemeralAllocator();
                    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices_list.deinit(allocator);
                    try choices_list.append(allocator, stringChoice("Give the Runner 1 tag"));
                    try choices_list.append(allocator, stringChoice("Remove tags and drain credits"));
                    g.corp_prompt_state = .{
                        .prompt_type = "bigger-picture",
                        .choices = try choices_list.toOwnedSlice(allocator),
                        .source_card = card.*,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.ephemeralAllocator();
                                if (std.mem.eql(u8, choice_text, "Give the Runner 1 tag")) {
                                    _ = try addRunnerTag(cg, 1);
                                    cg.systemMsg(.corp, 35065, "Corp uses Bigger Picture to give the Runner 1 tag.", .{});
                                    cg.corp_prompt_state = null;
                                    cg.runner_prompt_state = null;
                                    cg.decision_side = .corp;
                                    cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                } else if (std.mem.eql(u8, choice_text, "Remove tags and drain credits")) {
                                    // Prompt: how many tags to remove?
                                    const tag_count = if (cg.runner_tag) |t| t.base else 0;
                                    var num_choices: std.ArrayList(state.PromptChoice) = .empty;
                                    defer num_choices.deinit(c_allocator);
                                    var i: u8 = 0;
                                    while (i <= tag_count) : (i += 1) {
                                        const text = try std.fmt.allocPrint(c_allocator, "{d}", .{i});
                                        try num_choices.append(c_allocator, .{ .kind = .number, .text = text, .number = i });
                                    }
                                    cg.corp_prompt_state = .{
                                        .prompt_type = "bigger-picture-tags",
                                        .choices = try num_choices.toOwnedSlice(c_allocator),
                                        .source_card = cg.corp_prompt_state.?.source_card,
                                        .on_choice = &@This().choice,
                                    };
                                    cg.decision_side = .corp;
                                    cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                                } else {
                                    // Handle number choice for tag removal
                                    const num_tags = std.fmt.parseInt(u8, choice_text, 10) catch return error.UnsupportedChoice;
                                    if (num_tags > 0) {
                                        try removeRunnerTags(cg, num_tags);
                                    }
                                    const drain = @as(u16, num_tags) * 5;
                                    const actual_drain = @min(drain, cg.runner_credit);
                                    cg.runner_credit -= actual_drain;
                                    cg.corp_credit += actual_drain;
                                    cg.systemMsg(.corp, 35065, "Corp uses Bigger Picture to remove {d} tags; Runner loses {d} [credits], Corp gains {d} [credits].", .{ num_tags, actual_drain, actual_drain });
                                    cg.corp_prompt_state = null;
                                    cg.runner_prompt_state = null;
                                    if (try resumePendingEffects(cg)) return;
                                    cg.decision_side = .corp;
                                    cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                }
                            }
                        }.choice,
                    };
                    g.runner_prompt_state = .{
                        .prompt_type = "waiting",
                        .choices = &.{},
                        .source_card = null,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }.play,
        }},
    },
    .{
        .title = "IP Enforcement",
        .side = .corp,
        .code = 35066,
        .card_type = "Operation",
        .subtypes = &.{"Gray Ops"},
        .cost = 0,
        // No play req — the Clojure lets you play it anytime; tag cost is handled at execution
        .abilities = &.{.{
            .is_play = true,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // "As additional cost, remove X tags. Install 1 agenda from Runner's score area with X printed AP."
                    const allocator = g.ephemeralAllocator();
                    const tag_count = if (g.runner_tag) |t| t.base else 0;
                    var num_choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer num_choices.deinit(allocator);
                    var i: u8 = 0;
                    while (i <= tag_count) : (i += 1) {
                        // Check if runner has an agenda with this many printed AP
                        for (g.runner_scored.items) |a| {
                            if (a.agenda_points != null and a.agenda_points.? == i) {
                                const text = try std.fmt.allocPrint(allocator, "{d}", .{i});
                                try num_choices.append(allocator, .{ .kind = .number, .text = text, .number = i });
                                break;
                            }
                        }
                    }
                    if (num_choices.items.len > 0) {
                        g.corp_prompt_state = .{
                            .prompt_type = "ip-enforcement-tags",
                            .choices = try num_choices.toOwnedSlice(allocator),
                            .source_card = card.*,
                            .on_choice = &struct {
                                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                    const cg = gameFromEffectContext(cctx);
                                    const c_allocator = cg.ephemeralAllocator();
                                    const num_tags = std.fmt.parseInt(u8, choice_text, 10) catch return error.UnsupportedChoice;
                                    // Remove tags and credits as additional cost
                                    try removeRunnerTags(cg, num_tags);
                                    try spendCredits(cg, .corp, num_tags);
                                    // Find and move matching agenda from runner score area to corp install
                                    for (cg.runner_scored.items, 0..) |a, idx| {
                                        if (a.agenda_points != null and a.agenda_points.? == num_tags) {
                                            var agenda = cg.runner_scored.orderedRemove(idx);
                                            // Recalculate runner agenda points
                                            cg.runner_agenda_point = 0;
                                            for (cg.runner_scored.items) |sa| {
                                                if (sa.agenda_points) |ap| cg.runner_agenda_point += ap;
                                            }
                                            // Place advancement counter if still tagged
                                            if (is_runner_tagged(cg.runner_tag)) {
                                                agenda.advancement_counter = 1;
                                            }
                                            // Install in new remote
                                            try installCard(cg, agenda, "New remote");
                                            cg.systemMsg(.corp, 35066, "Corp uses IP Enforcement to install {s} from Runner's score area.", .{agenda.title});
                                            break;
                                        }
                                    }
                                    cg.corp_prompt_state = null;
                                    if (try resumePendingEffects(cg)) return;
                                    cg.decision_side = .corp;
                                    cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                }
                            }.choice,
                        };
                        g.decision_side = .corp;
                        g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    }
                }
            }.play,
        }},
    },
    .{
        .title = "Touch-ups",
        .side = .corp,
        .code = 35067,
        .card_type = "Operation",
        .subtypes = &.{"Double"},
        .cost = 2,
        .abilities = &.{.{
            .is_play = true,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Additional cost: spend [click] (Double)
                    try spendClicks(g, .corp, 1);
                    // "Place 2 advancement counters on 1 installed card you can advance."
                    const allocator = g.ephemeralAllocator();
                    const adv_choices = try installedCardChoices(allocator, g.corp_servers.items);
                    if (adv_choices.len > 0) {
                        g.corp_prompt_state = .{
                            .prompt_type = "touch-ups-advance",
                            .choices = adv_choices,
                            .source_card = card.*,
                            .on_choice = &struct {
                                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                    const cg = gameFromEffectContext(cctx);
                                    const c_allocator = cg.ephemeralAllocator();
                                    const prompt = cg.corp_prompt_state orelse return error.NoPromptState;
                                    if (std.mem.eql(u8, prompt.prompt_type, "touch-ups-advance")) {
                                        _ = try addAdvancementCounter(cg, choice_text, 2);
                                        cg.systemMsg(.corp, 35067, "Corp uses Touch-ups to place 2 advancement counters.", .{});
                                        // Step 2: Choose a card type to shuffle from runner's grip
                                        cg.corp_prompt_state = .{
                                            .prompt_type = "touch-ups-type",
                                            .choices = try c_allocator.dupe(state.PromptChoice, &.{
                                                stringChoice("Event"),   stringChoice("Hardware"),
                                                stringChoice("Program"), stringChoice("Resource"),
                                            }),
                                            .on_choice = &@This().choice,
                                        };
                                        cg.decision_side = .corp;
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                                    } else if (std.mem.eql(u8, prompt.prompt_type, "touch-ups-type")) {
                                        // Step 3: Show runner hand cards of chosen type, pick up to 2 to shuffle
                                        const chosen_type = choice_text;
                                        var shuffle_choices: std.ArrayList(state.PromptChoice) = .empty;
                                        defer shuffle_choices.deinit(c_allocator);
                                        for (cg.runner_hand.items) |c| {
                                            const ct = c.card_type orelse continue;
                                            if (std.mem.eql(u8, ct, chosen_type)) {
                                                try shuffle_choices.append(c_allocator, stringChoice(try c_allocator.dupe(u8, c.title)));
                                            }
                                        }
                                        if (shuffle_choices.items.len == 0) {
                                            cg.corp_prompt_state = null;
                                            if (try resumePendingEffects(cg)) return;
                                            cg.decision_side = .corp;
                                            cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                            return;
                                        }
                                        try shuffle_choices.append(c_allocator, stringChoice("Done"));
                                        cg.corp_prompt_state = .{
                                            .prompt_type = "touch-ups-shuffle",
                                            .choices = try shuffle_choices.toOwnedSlice(c_allocator),
                                            .ability_ref = .{ .source_instance_id = 0, .ability_index = 0 }, // tracks count
                                            .on_choice = &@This().choice,
                                        };
                                        cg.decision_side = .corp;
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                                    } else if (std.mem.eql(u8, prompt.prompt_type, "touch-ups-shuffle")) {
                                        const ref = prompt.ability_ref orelse return;
                                        const picked = ref.ability_index;
                                        if (std.mem.eql(u8, choice_text, "Done") or picked >= 2) {
                                            try shuffleDeck(cg, .runner);
                                            cg.corp_prompt_state = null;
                                            if (try resumePendingEffects(cg)) return;
                                            cg.decision_side = .corp;
                                            cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                            return;
                                        }
                                        // Move chosen card from runner hand to runner deck
                                        for (cg.runner_hand.items, 0..) |c, idx| {
                                            if (std.mem.eql(u8, c.title, choice_text)) {
                                                const moved = cg.runner_hand.orderedRemove(idx);
                                                try cg.runner_deck.append(cg.backing_allocator, moved);
                                                cg.systemMsg(.corp, 35067, "Corp shuffles {s} from Runner's grip into the stack.", .{moved.title});
                                                break;
                                            }
                                        }
                                        if (picked + 1 >= 2 or cg.runner_hand.items.len == 0) {
                                            try shuffleDeck(cg, .runner);
                                            cg.corp_prompt_state = null;
                                            if (try resumePendingEffects(cg)) return;
                                            cg.decision_side = .corp;
                                            cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                            return;
                                        }
                                        // Re-present for second pick (rebuild choices for remaining matching cards)
                                        var new_choices: std.ArrayList(state.PromptChoice) = .empty;
                                        defer new_choices.deinit(c_allocator);
                                        // Reconstruct type from previous step — we need to track it
                                        // For simplicity, show all remaining runner hand cards as choices
                                        for (cg.runner_hand.items) |c| {
                                            try new_choices.append(c_allocator, stringChoice(try c_allocator.dupe(u8, c.title)));
                                        }
                                        try new_choices.append(c_allocator, stringChoice("Done"));
                                        cg.corp_prompt_state = .{
                                            .prompt_type = "touch-ups-shuffle",
                                            .choices = try new_choices.toOwnedSlice(c_allocator),
                                            .ability_ref = .{ .source_instance_id = 0, .ability_index = picked + 1 },
                                            .on_choice = &@This().choice,
                                        };
                                        cg.decision_side = .corp;
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .corp, cg.corp_prompt_state.?);
                                    } else return error.UnsupportedChoice;
                                }
                            }.choice,
                        };
                        g.decision_side = .corp;
                        g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    }
                }
            }.play,
        }},
    },
    .{
        .title = "Key Performance Indicators",
        .side = .corp,
        .code = 35077,
        .card_type = "Operation",
        .subtypes = &.{"Transaction"},
        .cost = 1,
        .abilities = &.{.{
            .is_play = true,
            .on_use = &struct {
                const kpi_on_choice = &struct {
                    fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                        const g = gameFromEffectContext(cctx);
                        const allocator = g.ephemeralAllocator();
                        const prompt = g.corp_prompt_state orelse return error.NoPromptState;
                        if (std.mem.eql(u8, prompt.prompt_type, "kpi-choose")) {
                            const choices_made = prompt.min_choices;
                            if (std.mem.eql(u8, choice_text, "Gain 2 [Credits]")) {
                                g.corp_credit += 2;
                                g.systemMsg(.corp, 35077, "Corp uses Key Performance Indicators to gain 2 [credits].", .{});
                            } else if (std.mem.eql(u8, choice_text, "Draw 1 card and shuffle 1 card from HQ into R&D")) {
                                try drawCards(g, .corp, 1);
                                var hand_choices: std.ArrayList(state.PromptChoice) = .empty;
                                defer hand_choices.deinit(allocator);
                                for (g.corp_hand.items, 0..) |corp_card, idx| {
                                    try hand_choices.append(allocator, .{
                                        .kind = .card,
                                        .text = try allocator.dupe(u8, corp_card.title),
                                        .card = .{ .title = corp_card.title, .printed_title = corp_card.printed_title, .code = corp_card.code, .side = .corp, .index = @intCast(idx) },
                                    });
                                }
                                g.corp_prompt_state = .{
                                    .prompt_type = "kpi-shuffle",
                                    .choices = try hand_choices.toOwnedSlice(allocator),
                                    .ability_ref = prompt.ability_ref,
                                    .min_choices = choices_made + 1,
                                    .on_choice = &@This().choice,
                                };
                                g.decision_side = .corp;
                                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                                return;
                            } else if (std.mem.eql(u8, choice_text, "Done")) {
                                g.corp_prompt_state = null;
                                g.decision_side = .corp;
                                g.legal_actions = try corpOpeningActionsForState(allocator, g);
                                return;
                            } else if (std.mem.eql(u8, choice_text, "Place 1 advancement counter")) {
                                const adv_choices = try installedCardChoices(allocator, g.corp_servers.items);
                                if (adv_choices.len > 0) {
                                    g.corp_prompt_state = .{
                                        .prompt_type = "kpi-advance",
                                        .choices = adv_choices,
                                        .ability_ref = prompt.ability_ref,
                                        .min_choices = choices_made + 1,
                                        .on_choice = &@This().choice,
                                    };
                                    g.decision_side = .corp;
                                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                                    return;
                                }
                            } else if (std.mem.eql(u8, choice_text, "Install 1 piece of ice from HQ")) {
                                var ice_choices: std.ArrayList(state.PromptChoice) = .empty;
                                defer ice_choices.deinit(allocator);
                                for (g.corp_hand.items, 0..) |c, idx| {
                                    const ct = c.card_type orelse continue;
                                    if (!std.mem.eql(u8, ct, "ICE")) continue;
                                    try ice_choices.append(allocator, .{
                                        .kind = .card,
                                        .text = try std.fmt.allocPrint(allocator, "{s}", .{c.title}),
                                        .card = .{ .title = c.title, .code = c.code, .side = .corp, .index = @intCast(idx) },
                                    });
                                }
                                if (ice_choices.items.len > 0) {
                                    g.corp_prompt_state = .{
                                        .prompt_type = "kpi-ice-choose",
                                        .choices = try ice_choices.toOwnedSlice(allocator),
                                        .ability_ref = prompt.ability_ref,
                                        .min_choices = choices_made + 1,
                                        .on_choice = &@This().choice,
                                    };
                                    g.decision_side = .corp;
                                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                                    return;
                                }
                            } else return error.UnsupportedChoice;
                            if (choices_made + 1 >= 2) {
                                g.corp_prompt_state = null;
                                g.decision_side = .corp;
                                g.legal_actions = try corpOpeningActionsForState(allocator, g);
                            } else {
                                const ref1 = prompt.ability_ref orelse return error.MissingAbilityRef;
                                try showKpiChoices(g, ref1.source_instance_id, choices_made + 1, &@This().choice);
                            }
                        } else if (std.mem.eql(u8, prompt.prompt_type, "kpi-advance")) {
                            _ = try addAdvancementCounter(g, choice_text, 1);
                            g.systemMsg(.corp, 35077, "Corp uses Key Performance Indicators to place 1 advancement counter.", .{});
                            if (prompt.min_choices >= 2) {
                                g.corp_prompt_state = null;
                                g.decision_side = .corp;
                                g.legal_actions = try corpOpeningActionsForState(allocator, g);
                            } else {
                                const ref2 = prompt.ability_ref orelse return error.MissingAbilityRef;
                                try showKpiChoices(g, ref2.source_instance_id, prompt.min_choices, &@This().choice);
                            }
                        } else if (std.mem.eql(u8, prompt.prompt_type, "kpi-ice-choose")) {
                            for (prompt.choices) |ch| {
                                if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                                    if (ch.card) |card_ref| {
                                        const server_choices = try installChoicesForCard(allocator, .corp_server_choice, g);
                                        g.corp_prompt_state = .{
                                            .prompt_type = "kpi-ice-server",
                                            .choices = server_choices,
                                            .ability_ref = prompt.ability_ref,
                                            .min_choices = @intCast((card_ref.index orelse 0) | (@as(u8, prompt.min_choices) << 4)),
                                            .on_choice = &@This().choice,
                                        };
                                        g.decision_side = .corp;
                                        g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                                        return;
                                    }
                                }
                            }
                            return error.UnsupportedChoice;
                        } else if (std.mem.eql(u8, prompt.prompt_type, "kpi-ice-server")) {
                            const pack_val = prompt.min_choices;
                            const card_idx: u8 = pack_val & 0xF;
                            const choices_done: u8 = pack_val >> 4;
                            try installCorpCardFromHand(g, card_idx, choice_text);
                            g.systemMsg(.corp, 35077, "Corp uses Key Performance Indicators to install a piece of ice.", .{});
                            if (choices_done >= 2) {
                                g.corp_prompt_state = null;
                                g.decision_side = .corp;
                                g.legal_actions = try corpOpeningActionsForState(allocator, g);
                            } else {
                                const ref3 = prompt.ability_ref orelse return error.MissingAbilityRef;
                                try showKpiChoices(g, ref3.source_instance_id, choices_done, &@This().choice);
                            }
                        } else if (std.mem.eql(u8, prompt.prompt_type, "kpi-shuffle")) {
                            for (prompt.choices) |card_choice| {
                                if (card_choice.text == null or !std.mem.eql(u8, card_choice.text.?, choice_text)) continue;
                                const card_ref = card_choice.card orelse continue;
                                const card_idx = card_ref.index orelse continue;
                                try moveCorpHandCardToDeckAndShuffle(g, card_idx);
                                g.systemMsg(.corp, 35077, "Corp uses Key Performance Indicators to draw 1 card and shuffle 1 card from HQ into R&D.", .{});
                                if (prompt.min_choices >= 2) {
                                    g.corp_prompt_state = null;
                                    g.decision_side = .corp;
                                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                                } else {
                                    const ref4 = prompt.ability_ref orelse return error.MissingAbilityRef;
                                    try showKpiChoices(g, ref4.source_instance_id, prompt.min_choices, &@This().choice);
                                }
                                return;
                            }
                            return error.UnsupportedChoice;
                        } else return error.UnsupportedChoice;
                    }
                }.choice;
                fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // "Resolve 2 of: Gain 2cr, Install ice ignoring costs, Place 1 advancement, Draw 1 + shuffle 1"
                    try showKpiChoices(g, card.instance_id, 0, kpi_on_choice);
                }
            }.play,
        }},
    },
    .{
        .title = "Measured Response",
        .side = .corp,
        .code = 35078,
        .card_type = "Operation",
        .subtypes = &.{"Black Ops"},
        .cost = 5,
        .trash_cost = 3,
        .abilities = &.{.{
            .is_play = true,
            .req = &struct {
                fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    // "Play only if the threat level is 4 or greater, and only if the Runner made a successful run during their last turn."
                    return threatLevel(g) >= 4 and runner_had_successful_run_last_turn(g);
                }
            }.req,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // "Do 4 meat damage unless the Runner pays 8[credit]."
                    const allocator = g.ephemeralAllocator();
                    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices_list.deinit(allocator);
                    if (g.runner_credit >= 8) {
                        try choices_list.append(allocator, stringChoice("Pay 8 [Credits]"));
                    }
                    try choices_list.append(allocator, stringChoice("Suffer 4 meat damage"));
                    g.runner_prompt_state = .{
                        .prompt_type = "other",
                        .choices = try choices_list.toOwnedSlice(allocator),
                        .source_card = card.*,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                if (std.mem.eql(u8, choice_text, "Pay 8 [Credits]")) {
                                    try spendCredits(cg, .runner, 8);
                                    cg.systemMsg(.runner, 35078, "Runner pays 8 [credits] to prevent meat damage.", .{});
                                } else if (std.mem.eql(u8, choice_text, "Suffer 4 meat damage")) {
                                    try trashRandomRunnerHandCards(cg, 4);
                                    cg.systemMsg(.corp, 35078, "Corp uses Measured Response to do 4 meat damage.", .{});
                                    updateTerminalState(cg);
                                } else return error.UnsupportedChoice;
                                cg.runner_prompt_state = null;
                                cg.corp_prompt_state = null;
                                cg.decision_side = .corp;
                                cg.legal_actions = try corpOpeningActionsForState(cg.ephemeralAllocator(), cg);
                            }
                        }.choice,
                    };
                    g.corp_prompt_state = .{
                        .prompt_type = "waiting",
                        .choices = &.{},
                        .source_card = null,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.play,
        }},
    },
    .{
        .title = "Petty Cash",
        .side = .corp,
        .code = 35081,
        .card_type = "Operation",
        .subtypes = &.{"Transaction"},
        .cost = 3,
        .abilities = &.{.{
            .is_play = true,
            .is_flashback = true,
            .req = &struct {
                fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    // "Play only if you have not finished an action yet this turn."
                    return g.corp_click == g.corp_click_per_turn;
                }
            }.req,
            .on_use = corpGainCreditsPlayAbility(5, 0).on_use.?,
        }},
        // Flashback params are on the play ability above
        // Params now inline in applyCorpFlashback/isCorpFlashbackPlayable
    },
    // --- Elevation Runner Events ---
    .{
        .title = "Charm Offensive",
        .side = .runner,
        .code = 35003,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 0,
        .abilities = &.{runnerRunEventPlayAbility(.archives_only, 0, 0, 0, 0, 0)},
    },
    .{
        .title = "Scrounge",
        .side = .runner,
        .code = 35004,
        .card_type = "Event",
        .subtypes = &.{"Double"},
        .cost = 1,
        .abilities = &.{.{
            .is_play = true,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Additional cost: spend [click] (Double)
                    try spendClicks(g, .runner, 1);
                    // "Install 1 program from your heap."
                    const allocator = g.ephemeralAllocator();
                    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices_list.deinit(allocator);
                    for (g.runner_discard.items, 0..) |c, idx| {
                        const ct = c.card_type orelse continue;
                        if (!std.mem.eql(u8, ct, "Program")) continue;
                        if (!runnerHandInstallableByEffect(g, c)) continue;
                        try choices_list.append(allocator, .{
                            .kind = .card,
                            .text = try std.fmt.allocPrint(allocator, "{s}", .{c.title}),
                            .card = .{ .title = c.title, .code = c.code, .side = .runner, .index = @intCast(idx) },
                        });
                    }
                    if (choices_list.items.len > 0) {
                        try choices_list.append(allocator, stringChoice("No action"));
                        g.runner_prompt_state = .{
                            .prompt_type = "scrounge-install",
                            .choices = try choices_list.toOwnedSlice(allocator),
                            .ability_ref = .{ .source_instance_id = card.instance_id },
                            .on_choice = scrounge_on_choice,
                        };
                        g.decision_side = .runner;
                        g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                    } else {
                        try g.pending_effects.append(g.backing_allocator, .{ .deferred_prompt = .{
                            .card = card.*,
                            .on_choice = scrounge_on_choice,
                            .open_fn = &openRunnerDiscardToDeckPrompt,
                        } });
                        if (try resumePendingEffects(g)) return;
                        g.decision_side = .runner;
                        g.legal_actions = try runnerOpeningActionsForState(allocator, g);
                    }
                }
            }.play,
        }},
    },
    .{
        .title = "Shred",
        .side = .runner,
        .code = 35005,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 1,
        .abilities = &.{runnerRunEventPlayAbility(.any_runnable, 0, 0, 0, 0, 0)},
    },
    .{ .title = "Clean Getaway", .side = .runner, .code = 35014, .card_type = "Event", .subtypes = &.{"Run"}, .cost = 3, .abilities = &.{runnerRunEventPlayAbility(.any_runnable, 0, 0, 0, 0, 0)} },
    .{
        .title = "Lie Low",
        .side = .runner,
        .code = 35015,
        .card_type = "Event",
        .subtypes = &.{"Double"},
        .cost = 1,
        .abilities = &.{.{
            .is_play = true,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Additional cost: spend [click] (Double)
                    try spendClicks(g, .runner, 1);
                    // "Draw 4 cards OR Remove up to 2 tags"
                    const allocator = g.ephemeralAllocator();
                    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices_list.deinit(allocator);
                    try choices_list.append(allocator, stringChoice("Draw 4 cards"));
                    if (is_runner_tagged(g.runner_tag)) {
                        try choices_list.append(allocator, stringChoice("Remove up to 2 tags"));
                    }
                    g.runner_prompt_state = .{
                        .prompt_type = "lie-low",
                        .choices = try choices_list.toOwnedSlice(allocator),
                        .source_card = null,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.ephemeralAllocator();
                                const prompt = cg.runner_prompt_state orelse return error.NoPromptState;
                                if (std.mem.eql(u8, prompt.prompt_type, "lie-low")) {
                                    if (std.mem.eql(u8, choice_text, "Draw 4 cards")) {
                                        try drawCards(cg, .runner, 4);
                                        cg.systemMsg(.runner, 35015, "Runner uses Lie Low to draw 4 cards.", .{});
                                        cg.runner_prompt_state = null;
                                        cg.decision_side = .runner;
                                        cg.legal_actions = try runnerOpeningActionsForState(c_allocator, cg);
                                    } else if (std.mem.eql(u8, choice_text, "Remove up to 2 tags")) {
                                        // Show tag count choices
                                        const tag_count = if (cg.runner_tag) |t| t.total else 0;
                                        const max_remove: u8 = @min(2, tag_count);
                                        var num_choices: std.ArrayList(state.PromptChoice) = .empty;
                                        defer num_choices.deinit(c_allocator);
                                        var i: u8 = 0;
                                        while (i <= max_remove) : (i += 1) {
                                            const text = try std.fmt.allocPrint(c_allocator, "{d}", .{i});
                                            try num_choices.append(c_allocator, .{ .kind = .number, .text = text, .number = i });
                                        }
                                        cg.runner_prompt_state = .{
                                            .prompt_type = "lie-low-tags",
                                            .choices = try num_choices.toOwnedSlice(c_allocator),
                                            .source_card = null,
                                            .on_choice = &@This().choice,
                                        };
                                        cg.decision_side = .runner;
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .runner, cg.runner_prompt_state.?);
                                    } else return error.UnsupportedChoice;
                                } else if (std.mem.eql(u8, prompt.prompt_type, "lie-low-tags")) {
                                    const num_tags = std.fmt.parseInt(u8, choice_text, 10) catch return error.UnsupportedChoice;
                                    if (num_tags > 0) {
                                        try removeRunnerTags(cg, num_tags);
                                        cg.systemMsg(.runner, 35015, "Runner uses Lie Low to remove {d} tag{s}.", .{ num_tags, if (num_tags != 1) "s" else "" });
                                    }
                                    cg.runner_prompt_state = null;
                                    if (try resumePendingEffects(cg)) return;
                                    cg.decision_side = .runner;
                                    cg.legal_actions = try runnerOpeningActionsForState(c_allocator, cg);
                                } else return error.UnsupportedChoice;
                            }
                        }.choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.play,
        }},
    },
    .{
        .title = "Maintenance Access",
        .side = .runner,
        .code = 35016,
        .card_type = "Event",
        .subtypes = &.{ "Double", "Run" },
        .cost = 0,
        .abilities = &.{runnerRunEventPlayAbility(.archives_only, 1, 0, 0, 0, 0)},
    },
    .{
        .title = "Transfer of Wealth",
        .side = .runner,
        .code = 35017,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 0,
        .abilities = &.{runnerRunEventPlayAbility(.hq_only, 0, 0, 0, 0, 0)},
        .event_abilities = &.{.{
            .event = .successful_run,
            .automatic_priority = state.Priority.drain_credits,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const run = g.run orelse return;
                    // Only fires on HQ runs from this card
                    if (run.server != .hq) return;
                    _ = try addRunnerTag(g, 1);
                    g.systemMsg(.runner, 35017, "Runner uses Transfer of Wealth to take 1 tag.", .{});
                    // Drain: runner loses up to 3 credits, corp gains up to 2
                    const runner_loss = @min(g.runner_credit, 3);
                    g.runner_credit -= runner_loss;
                    const corp_gain = @min(runner_loss, 2);
                    g.corp_credit += corp_gain;
                    if (runner_loss > 0) {
                        g.systemMsg(.runner, 35017, "Runner loses {d} [credit{s}]; Corp gains {d} [credit{s}].", .{
                            runner_loss, if (runner_loss != 1) "s" else "",
                            corp_gain,   if (corp_gain != 1) "s" else "",
                        });
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Illumination",
        .side = .runner,
        .code = 35025,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 0,
        .abilities = &.{runnerRunEventPlayAbility(.rd_only, 0, 0, 0, 0, 0)},
    },
    .{
        .title = "Ritual",
        .side = .runner,
        .code = 35026,
        .card_type = "Event",
        .cost = 0,
        .abilities = &.{.{
            .is_play = true,
            .on_use = &struct {
                fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // "Draw 1 card for each [click] you have remaining."
                    const clicks_remaining: u8 = @intCast(g.runner_click);
                    if (clicks_remaining > 0) {
                        try drawCards(g, .runner, clicks_remaining);
                    }
                    g.decision_side = .runner;
                    g.legal_actions = try runnerOpeningActionsForState(g.ephemeralAllocator(), g);
                }
            }.play,
        }},
    },
    // --- Elevation Runner Hardware ---
    .{
        .title = "Bling",
        .side = .runner,
        .code = 35006,
        .card_type = "Hardware",
        .subtypes = &.{"Console"},
        .cost = 2,
        .runner_install = .{ .kind = .hardware, .mu_cost = 0 },
        .static_abilities = &.{.{ .kind = .mu, .value = 1 }},
        .event_abilities = &.{
            .{
                .event = .card_installed,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        const g = gameFromEffectContext(ctx);
                        const install_ctx = g.runner_install_context orelse return;
                        if (install_ctx.install_cost != 0 or g.runner_deck.items.len == 0) return;
                        // Optional: ask runner if they want to host
                        const allocator = g.ephemeralAllocator();
                        g.runner_prompt_state = .{
                            .prompt_type = "bling-host",
                            .choices = try allocator.dupe(state.PromptChoice, &.{
                                stringChoice("Host the top card of your stack on Bling"),
                                stringChoice("No action"),
                            }),
                            .ability_ref = .{ .source_instance_id = card.instance_id, .ability_index = 0 },
                            .on_choice = &struct {
                                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                    const cg = gameFromEffectContext(cctx);
                                    const ref = (cg.runner_prompt_state orelse return).ability_ref orelse return;
                                    cg.runner_prompt_state = null;
                                    if (std.mem.eql(u8, choice_text, "No action")) return;
                                    const live = findCardPtrByInstanceId(cg, ref.source_instance_id) orelse return;
                                    if (cg.runner_deck.items.len == 0) return;
                                    try hostTopRunnerDeckCard(cg, live);
                                }
                            }.choice,
                        };
                    }
                }.handle,
            },
            .{
                .event = .runner_end_turn,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        try trashHostedRunnerCards(gameFromEffectContext(ctx), card);
                    }
                }.handle,
            },
        },
        .abilities = &.{.{
            .label = "Play or install a hosted card",
            .req = &struct {
                fn check(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                    return countPlayableHostedRunnerCards(gameFromConstEffectContext(ctx), card.*) > 0;
                }
            }.check,
            .on_use = &struct {
                const bling_on_choice = &struct {
                    fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                        const g = gameFromEffectContext(cctx);
                        const prompt = g.runner_prompt_state orelse return error.NoPromptState;
                        if (!std.mem.eql(u8, prompt.prompt_type, "runner-hosted-card")) return error.UnsupportedChoice;
                        if (std.mem.eql(u8, choice_text, "No action")) {
                            g.runner_prompt_state = null;
                            g.decision_side = .runner;
                            g.legal_actions = try runnerOpeningActionsForState(g.ephemeralAllocator(), g);
                            return;
                        }
                        const bling_ref = prompt.ability_ref orelse return error.MissingAbilityRef;
                        const host = findCardPtrByInstanceId(g, bling_ref.source_instance_id) orelse return error.MissingSourceCard;
                        const hosted_index = hostedChoiceIndex(prompt, choice_text) orelse return error.UnsupportedChoice;
                        var chosen = try removeHostedCard(g.arena.allocator(), host, hosted_index);
                        try g.runner_hand.append(g.backing_allocator, chosen);
                        const hand_index: u8 = @intCast(g.runner_hand.items.len - 1);
                        g.runner_prompt_state = null;
                        chosen = g.runner_hand.items[hand_index];
                        if (chosen.runner_install.kind != .none) {
                            try applyInstallFromHand(g, .runner, hand_index);
                        } else {
                            try applyRunnerPlayFromHand(g, hand_index);
                        }
                    }
                }.choice;
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    try beginRunnerHostedCardPrompt(g, card.instance_id, bling_on_choice);
                }
            }.use,
        }},
    },
    .{
        .title = "Detente",
        .side = .runner,
        .code = 35018,
        .card_type = "Hardware",
        .subtypes = &.{"Console"},
        .cost = 3,
        .runner_install = .{ .kind = .hardware, .mu_cost = 0 },
        .static_abilities = &.{.{ .kind = .mu, .value = 1 }},
        .abilities = &.{.{
            .cost = .{ .clicks = 1 },
            .allow_opponent_use = true,
            .label = "Return 2 hosted cards to HQ to access 1 random HQ card",
            .req = &struct {
                fn check(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                    return card.hosted.items.len >= 2;
                }
            }.check,
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    try returnHostedCardsToHq(g, card, 2);
                    try beginRandomHqAccess(g);
                }
            }.use,
        }},
        .event_abilities = &.{.{
            .event = .successful_run,
            .handler = &struct {
                const detente_on_choice = &struct {
                    fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                        const g = gameFromEffectContext(cctx);
                        const prompt = g.runner_prompt_state orelse return error.NoPromptState;
                        if (!std.mem.eql(u8, prompt.prompt_type, "runner-host-confirm")) return error.UnsupportedChoice;
                        g.runner_prompt_state = null;
                        g.corp_prompt_state = null;
                        if (std.mem.eql(u8, choice_text, "Yes")) {
                            const detente_ref = prompt.ability_ref orelse return error.MissingAbilityRef;
                            const host = findCardPtrByInstanceId(g, detente_ref.source_instance_id) orelse return error.MissingSourceCard;
                            try hostRandomHqCard(g, host);
                        } else if (!std.mem.eql(u8, choice_text, "No")) {
                            return error.UnsupportedChoice;
                        }
                        if (try resumePendingEffects(g)) return;
                        try restorePriorityAfterPrompt(g);
                    }
                }.choice;
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const run = g.run orelse return;
                    if (run.server != .hq or g.runner_successful_run_this_turn or g.corp_hand.items.len == 0) return;
                    try beginYesNoPrompt(g, .runner, "runner-host-confirm", card.instance_id, detente_on_choice);
                    g.corp_prompt_state = .{
                        .prompt_type = "waiting",
                        .choices = &.{},
                        .source_card = null,
                    };
                }
            }.handle,
        }},
    },
    .{
        .title = "Maglectric Rapid (748 Mod)",
        .side = .runner,
        .code = 35019,
        .card_type = "Hardware",
        .subtypes = &.{"Weapon"},
        .cost = 1,
        .runner_install = .{ .kind = .hardware, .mu_cost = 0 },
        // "Whenever you make a successful run on HQ, you may trash this hardware to derez 1 installed Corp card."
        .event_abilities = &.{.{
            .event = .successful_run_ends,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.run == null) return;
                    const server = g.run.?.server;
                    if (server != .hq) return;
                    // Find rezzed non-agenda corp cards to derez
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    for (g.corp_servers.items) |srv| {
                        for (srv.ices.items) |ice| {
                            if (ice.rezzed) {
                                choices.append(allocator, .{ .kind = .card, .text = ice.title, .card = .{
                                    .title = ice.title,
                                    .code = ice.code,
                                    .side = .corp,
                                } }) catch continue;
                            }
                        }
                        for (srv.content.items) |c| {
                            if (c.rezzed) {
                                const is_agenda = if (c.card_type) |ct| std.mem.eql(u8, ct, "Agenda") else false;
                                if (!is_agenda) {
                                    choices.append(allocator, .{ .kind = .card, .text = c.title, .card = .{
                                        .title = c.title,
                                        .code = c.code,
                                        .side = .corp,
                                    } }) catch continue;
                                }
                            }
                        }
                    }
                    if (choices.items.len == 0) return; // Nothing to derez
                    choices.append(allocator, stringChoice("No action")) catch return;
                    g.runner_prompt_state = .{
                        .prompt_type = "maglectric-derez",
                        .choices = choices.toOwnedSlice(allocator) catch return,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                if (std.mem.eql(u8, choice_text, "No action")) {
                                    cg.runner_prompt_state = null;
                                    return;
                                }
                                // Self-trash Maglectric Rapid
                                for (cg.runner_rig_hardware.items, 0..) |hw, idx| {
                                    if (hw.code != null and hw.code.? == 35019) {
                                        const trashed = cg.runner_rig_hardware.orderedRemove(idx);
                                        try appendDiscardCard(cg, .runner, trashed);
                                        break;
                                    }
                                }
                                // Derez the selected corp card
                                for (cg.corp_servers.items) |*srv| {
                                    for (srv.ices.items) |*ice| {
                                        if (ice.rezzed and std.mem.eql(u8, ice.title, choice_text)) {
                                            ice.rezzed = false;
                                            cg.systemMsg(.runner, 35019, "Runner uses Maglectric Rapid to derez {s}.", .{choice_text});
                                            cg.runner_prompt_state = null;
                                            return;
                                        }
                                    }
                                    for (srv.content.items) |*c| {
                                        if (c.rezzed and std.mem.eql(u8, c.title, choice_text)) {
                                            c.rezzed = false;
                                            cg.systemMsg(.runner, 35019, "Runner uses Maglectric Rapid to derez {s}.", .{choice_text});
                                            cg.runner_prompt_state = null;
                                            return;
                                        }
                                    }
                                }
                                cg.runner_prompt_state = null;
                            }
                        }.choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = promptChoiceActions(allocator, .runner, g.runner_prompt_state.?) catch return;
                }
            }.handle,
        }},
    },
    .{
        .title = "GAMEDRAGON\xe2\x84\xa2 Pro",
        .side = .runner,
        .code = 35027,
        .card_type = "Hardware",
        .subtypes = &.{"Mod"},
        .cost = 2,
        .runner_install = .{ .kind = .hardware, .mu_cost = 0 },
        // "On install + turn begin: may host on non-AI icebreaker. Host gets +1 str."
        // The +1 str is applied via effectiveStrength scanning card.hosted for self_strength bonuses.
        .static_abilities = &.{.{ .kind = .self_strength, .value = 1 }},
        .event_abilities = &.{
            .{
                .event = .card_installed,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        try showGamedragonHostPrompt(gameFromEffectContext(ctx), card.instance_id, false);
                    }
                }.handle,
            },
            .{
                .event = .runner_turn_begins,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        // Re-host at start of turn (GAMEDRAGON may be hosted on a program already)
                        try showGamedragonHostPrompt(gameFromEffectContext(ctx), card.instance_id, true);
                    }
                }.handle,
            },
        },
    },
    .{
        .title = "Madani",
        .side = .runner,
        .code = 35028,
        .card_type = "Hardware",
        .subtypes = &.{"Console"},
        .cost = 2,
        .runner_install = .{ .kind = .hardware, .mu_cost = 0 },
        .abilities = &.{.{
            .label = "Host programs or install a hosted program",
            .req = &struct {
                fn check(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    if (!isAbilityUsedThisTurn(card, 1)) {
                        for (card.hosted.items) |hosted_card| {
                            if (runnerHandInstallableByEffect(g, hosted_card)) return true;
                        }
                    }
                    if (g.runner_click == 0) return false;
                    for (g.runner_hand.items) |hand_card| {
                        const card_type = hand_card.card_type orelse continue;
                        if (std.mem.eql(u8, card_type, "Program")) return true;
                    }
                    return false;
                }
            }.check,
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    if (g.runner_click > 0) {
                        for (g.runner_hand.items) |hand_card| {
                            const card_type = hand_card.card_type orelse continue;
                            if (!std.mem.eql(u8, card_type, "Program")) continue;
                            try choices.append(allocator, stringChoice("Host programs from grip"));
                            break;
                        }
                    }
                    if (!isAbilityUsedThisTurn(card, 1)) {
                        for (card.hosted.items) |hosted_card| {
                            if (!runnerHandInstallableByEffect(g, hosted_card)) continue;
                            try choices.append(allocator, stringChoice("Install a hosted program"));
                            break;
                        }
                    }
                    if (choices.items.len == 0) return;
                    g.runner_prompt_state = .{
                        .prompt_type = "runner-host-mode",
                        .choices = try choices.toOwnedSlice(allocator),
                        .ability_ref = .{ .source_instance_id = card.instance_id },
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.ephemeralAllocator();
                                const prompt = cg.runner_prompt_state orelse return error.NoPromptState;
                                const madani_ref = prompt.ability_ref orelse return error.MissingAbilityRef;
                                const host = findCardPtrByInstanceId(cg, madani_ref.source_instance_id) orelse return error.MissingSourceCard;
                                if (std.mem.eql(u8, prompt.prompt_type, "runner-host-mode")) {
                                    if (std.mem.eql(u8, choice_text, "Host programs from grip")) {
                                        try spendClicks(cg, .runner, 1);
                                        var c_choices: std.ArrayList(state.PromptChoice) = .empty;
                                        defer c_choices.deinit(c_allocator);
                                        for (cg.runner_hand.items, 0..) |hand_card, idx| {
                                            const card_type = hand_card.card_type orelse continue;
                                            if (!std.mem.eql(u8, card_type, "Program")) continue;
                                            try c_choices.append(c_allocator, .{
                                                .kind = .card,
                                                .text = try c_allocator.dupe(u8, hand_card.title),
                                                .card = .{ .title = hand_card.title, .printed_title = hand_card.printed_title, .code = hand_card.code, .side = .runner, .index = @intCast(idx) },
                                            });
                                        }
                                        try c_choices.append(c_allocator, stringChoice("Done"));
                                        cg.runner_prompt_state = .{
                                            .prompt_type = "runner-host-from-grip",
                                            .choices = try c_choices.toOwnedSlice(c_allocator),
                                            .ability_ref = prompt.ability_ref,
                                            .on_choice = &@This().choice,
                                        };
                                        cg.decision_side = .runner;
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .runner, cg.runner_prompt_state.?);
                                        return;
                                    }
                                    if (std.mem.eql(u8, choice_text, "Install a hosted program")) {
                                        var c_choices: std.ArrayList(state.PromptChoice) = .empty;
                                        defer c_choices.deinit(c_allocator);
                                        for (host.hosted.items, 0..) |hosted_card, idx| {
                                            if (!runnerHandInstallableByEffect(cg, hosted_card)) continue;
                                            try c_choices.append(c_allocator, .{
                                                .kind = .card,
                                                .text = try c_allocator.dupe(u8, hosted_card.title),
                                                .card = .{ .title = hosted_card.title, .printed_title = hosted_card.printed_title, .code = hosted_card.code, .side = .runner, .index = @intCast(idx) },
                                            });
                                        }
                                        if (c_choices.items.len == 0) return error.UnsupportedChoice;
                                        cg.runner_prompt_state = .{
                                            .prompt_type = "runner-hosted-install",
                                            .choices = try c_choices.toOwnedSlice(c_allocator),
                                            .ability_ref = prompt.ability_ref,
                                            .on_choice = &@This().choice,
                                        };
                                        cg.decision_side = .runner;
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .runner, cg.runner_prompt_state.?);
                                        return;
                                    }
                                    return error.UnsupportedChoice;
                                }
                                if (std.mem.eql(u8, prompt.prompt_type, "runner-host-from-grip")) {
                                    if (std.mem.eql(u8, choice_text, "Done")) {
                                        cg.runner_prompt_state = null;
                                        try restorePriorityAfterPrompt(cg);
                                        return;
                                    }
                                    for (cg.runner_hand.items, 0..) |hand_card, idx| {
                                        if (!std.mem.eql(u8, hand_card.title, choice_text)) continue;
                                        const hosted = cg.runner_hand.orderedRemove(idx);
                                        try appendHostedCard(cg.arena.allocator(), host, hosted);
                                        cg.systemMsg(.runner, 35028, "Runner uses Madani to host {s}.", .{hosted.title});
                                        var c_choices: std.ArrayList(state.PromptChoice) = .empty;
                                        defer c_choices.deinit(c_allocator);
                                        for (cg.runner_hand.items, 0..) |remaining_card, remaining_idx| {
                                            const card_type = remaining_card.card_type orelse continue;
                                            if (!std.mem.eql(u8, card_type, "Program")) continue;
                                            try c_choices.append(c_allocator, .{
                                                .kind = .card,
                                                .text = try c_allocator.dupe(u8, remaining_card.title),
                                                .card = .{ .title = remaining_card.title, .printed_title = remaining_card.printed_title, .code = remaining_card.code, .side = .runner, .index = @intCast(remaining_idx) },
                                            });
                                        }
                                        try c_choices.append(c_allocator, stringChoice("Done"));
                                        cg.runner_prompt_state = .{
                                            .prompt_type = "runner-host-from-grip",
                                            .choices = try c_choices.toOwnedSlice(c_allocator),
                                            .ability_ref = prompt.ability_ref,
                                            .on_choice = &@This().choice,
                                        };
                                        cg.decision_side = .runner;
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .runner, cg.runner_prompt_state.?);
                                        return;
                                    }
                                    return error.UnsupportedChoice;
                                }
                                if (std.mem.eql(u8, prompt.prompt_type, "runner-hosted-install")) {
                                    const hosted_index = hostedChoiceIndex(prompt, choice_text) orelse return error.UnsupportedChoice;
                                    const hosted = try removeHostedCard(cg.arena.allocator(), host, hosted_index);
                                    try cg.runner_hand.append(cg.backing_allocator, hosted);
                                    const hand_index: u8 = @intCast(cg.runner_hand.items.len - 1);
                                    markAbilityUsedThisTurn(host, 1);
                                    cg.runner_prompt_state = null;
                                    try beginRunnerInstallFromHand(cg, hand_index, false);
                                    cg.systemMsg(.runner, 35028, "Runner uses Madani to install {s}.", .{hosted.title});
                                    if (hasActivePrompt(cg) or cg.pending_install != null) return;
                                    try restorePriorityAfterPrompt(cg);
                                    return;
                                }
                                return error.UnsupportedChoice;
                            }
                        }.choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.use,
        }},
    },
    // --- Elevation Runner Programs ---
    .{
        .title = "Gourmand",
        .side = .runner,
        .code = 35007,
        .card_type = "Program",
        .cost = 0,
        .runner_install = .{ .kind = .program },
        .abilities = &.{.{
            .is_access_ability = true,
            .label = "Use Gourmand",
            .side = .runner,
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const accessed = (if (g.runner_prompt_state) |ps| ps.source_card else null) orelse return error.MissingSourceCard;
                    const trash_title = card.title;
                    const trash_code = card.code orelse 0;
                    // Find and remove self from rig
                    for (g.runner_rig_program.items, 0..) |prog, idx| {
                        if (prog.instance_id == card.instance_id) {
                            const trashed_prog = g.runner_rig_program.orderedRemove(idx);
                            try appendDiscardCard(g, .runner, trashed_prog);
                            if (g.runner_memory) |*mem| {
                                const mu = trashed_prog.runner_install.mu_cost;
                                mem.used = if (mem.used >= mu) mem.used - mu else 0;
                                mem.available = mem.base - mem.used;
                            }
                            break;
                        }
                    }
                    g.systemMsg(.runner, trash_code, "Runner uses {s} to trash {s}.", .{ trash_title, accessed.title });
                    g.runner_prompt_state = null;
                    g.turn_events.runner_trash_corp_card_count += 1;
                    if (try fireEvent(g, .runner_trash_corp_card)) return;
                    try removeCurrentAccessedCard(g);
                    try appendDiscardCard(g, .corp, accessed);
                    // Draw 1 card
                    try drawCards(g, .runner, 1);
                    try finishAccessCard(g);
                }
            }.handle,
            .req = &struct {
                fn check(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    // Can't use on agendas
                    if (g.runner_prompt_state) |ps| {
                        if (ps.source_card) |accessed| {
                            const is_agenda = if (accessed.card_type) |ct| std.mem.eql(u8, ct, "Agenda") else false;
                            if (is_agenda) return false;
                        }
                    }
                    return true;
                }
            }.check,
        }},
    },
    .{ .title = "Hantu", .side = .runner, .code = 35008, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer", "Virus" }, .cost = 3, .strength = 2, .runner_install = .{ .kind = .program }, .initial_virus_counters = 2, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 1 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 3, .pump_amount = 2, .pump_can_use = &struct {
            fn canUse(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                return card.virus_counter > 0;
            }
        }.canUse, .on_pump = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                if (card.virus_counter == 0) return error.InsufficientCredits;
                card.virus_counter -= 1;
            }
        }.handle },
    } },
    .{ .title = "Rising Tide", .side = .runner, .code = 35009, .card_type = "Program", .subtypes = &.{ "Fracter", "Icebreaker" }, .cost = 1, .strength = 1, .runner_install = .{ .kind = .program }, .static_abilities = &.{.{
        .kind = .self_strength,
        .value = 1,
        .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance, _: ?*const state.CardInstance) i16 {
                return countFractersInHeap(gameFromConstEffectContext(ctx));
            }
        }.req,
    }}, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 1 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 1, .pump_amount = 1 },
    } },
    .{ .title = "Sang Kancil", .side = .runner, .code = 35020, .card_type = "Program", .subtypes = &.{ "Decoder", "Icebreaker" }, .cost = 3, .strength = 2, .runner_install = .{ .kind = .program }, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 1 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 3, .pump_amount = 2 },
    }, .static_abilities = &.{.{
        .kind = .pump_cost,
        .value = -2,
        .req = &struct {
            fn req(ctx: *const state.EffectContext, source: *const state.CardInstance, target: ?*const state.CardInstance) i16 {
                const g = gameFromConstEffectContext(ctx);
                const modified = target orelse return 0;
                if (modified.code == null or source.code == null) return 0;
                return if (modified.code.? == source.code.? and runnerHasActiveRunEvent(g)) 1 else 0;
            }
        }.req,
    }} },
    .{
        .title = "Azimat",
        .side = .runner,
        .code = 35029,
        .card_type = "Program",
        .cost = 1,
        .runner_install = .{ .kind = .program, .mu_cost = 2 },
        // "2 recurring credits. You can spend hosted credits to pay trash costs."
        .initial_credit_counters = 2,
        .pay_credits = .{ .context = .runner_trash_corp },
        .event_abilities = &.{.{
            .event = .runner_turn_begins,
            .handler = &struct {
                fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    card.credit_counter = 2;
                }
            }.handle,
        }},
    },
    .{ .title = "Chromatophores", .side = .runner, .code = 35030, .card_type = "Program", .subtypes = &.{"Trojan"}, .cost = 1, .runner_install = .{ .kind = .program }, .static_abilities = &.{.{ .kind = .gain_subtype }} },
    .{
        .title = "Devadatta Drone",
        .side = .runner,
        .code = 35031,
        .card_type = "Program",
        .cost = 1,
        .runner_install = .{ .kind = .program },
        .initial_power_counters = 2,
        .event_abilities = &.{.{
            .event = .successful_run_ends,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.run == null) return;
                    const server = g.run.?.server;
                    // Only trigger on R&D runs
                    if (server != .rnd) return;
                    if (card.power_counter == 0) return;
                    card.power_counter -= 1;
                    try addFloatingEffect(g, .{ .kind = .access_bonus, .duration = .end_of_run, .value = 1 });
                    g.systemMsg(.runner, 35031, "Runner uses Devadatta Drone to access 1 additional card from R&D.", .{});
                }
            }.handle,
        }},
    },
    .{ .title = "Principia", .side = .runner, .code = 35032, .card_type = "Program", .subtypes = &.{ "Fracter", "Icebreaker" }, .cost = 4, .strength = 2, .runner_install = .{ .kind = .program }, .static_abilities = &.{.{
        .kind = .install_cost,
        .value = -1,
        .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance, _: ?*const state.CardInstance) i16 {
                return @intCast(countInstalledIcebreakers(gameFromConstEffectContext(ctx)));
            }
        }.req,
    }}, .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 1 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 2, .pump_amount = 2 },
    } },
    // --- Elevation Runner Resources ---
    .{
        .title = "Cacophony",
        .side = .runner,
        .code = 35010,
        .card_type = "Resource",
        .subtypes = &.{"Virtual"},
        .cost = 3,
        .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        // "First time each turn you steal or trash a Corp card, place 1 power counter."
        // "When your action phase ends, you may remove 2 hosted power counters to sabotage 3."
        .event_abilities = &.{
            .{
                .event = .agenda_stolen,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (isAbilityUsedThisTurn(card, 0)) return;
                        card.power_counter += 1;
                        markAbilityUsedThisTurn(card, 0);
                        const g = gameFromEffectContext(ctx);
                        g.systemMsg(.runner, 35010, "Runner places 1 power counter on Cacophony.", .{});
                    }
                }.handle,
            },
            .{
                .event = .runner_trash_corp_card,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (isAbilityUsedThisTurn(card, 0)) return;
                        card.power_counter += 1;
                        markAbilityUsedThisTurn(card, 0);
                        const g = gameFromEffectContext(ctx);
                        g.systemMsg(.runner, 35010, "Runner places 1 power counter on Cacophony.", .{});
                    }
                }.handle,
            },
            // "When your action phase ends, remove 2 hosted power counters: Sabotage 3."
            // (Sabotage = corp chooses cards to trash from HQ and/or top of R&D)
            .{
                .event = .runner_end_turn,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (card.power_counter < 2) return;
                        const g = gameFromEffectContext(ctx);
                        const allocator = g.ephemeralAllocator();
                        g.runner_prompt_state = .{
                            .prompt_type = "cacophony-sabotage",
                            .choices = try allocator.dupe(state.PromptChoice, &.{
                                stringChoice("Remove 2 hosted power counters"),
                                stringChoice("No action"),
                            }),
                            .ability_ref = .{ .source_instance_id = card.instance_id, .ability_index = 0 },
                            .on_choice = &struct {
                                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                    const cg = gameFromEffectContext(cctx);
                                    const ref = if (cg.runner_prompt_state) |ps| ps.ability_ref else null;
                                    cg.runner_prompt_state = null;
                                    if (std.mem.eql(u8, choice_text, "Remove 2 hosted power counters")) {
                                        if (ref) |r| {
                                            const live = findCardPtrByInstanceId(cg, r.source_instance_id) orelse {
                                                try beginStartTurnSequence(cg, .corp);
                                                return;
                                            };
                                            if (live.power_counter < 2) {
                                                try beginStartTurnSequence(cg, .corp);
                                                return;
                                            }
                                            live.power_counter -= 2;
                                        }
                                        cg.systemMsg(.runner, 35010, "Cacophony: Sabotage 3.", .{});
                                        // Sabotage 3: corp chooses cards from HQ and/or top of R&D
                                        try beginSabotagePrompt(cg, 3);
                                        return;
                                    }
                                    try beginStartTurnSequence(cg, .corp);
                                }
                            }.choice,
                        };
                    }
                }.handle,
            },
        },
    },
    .{
        .title = "Rent Rioters",
        .side = .runner,
        .code = 35011,
        .card_type = "Resource",
        .subtypes = &.{ "Connection", "Seedy" },
        .cost = 2,
        .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        .abilities = &.{.{
            .cost = .{ .clicks = 3 },
            .label = "Gain 9 [Credits]",
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    g.runner_credit += 9;
                    g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain 9 [credits].", .{card.title});
                    try trashRunnerRigCardByInstanceId(g, card.instance_id);
                }
            }.handle,
        }},
    },
    .{
        .title = "Fransofia Ward",
        .side = .runner,
        .code = 35021,
        .card_type = "Resource",
        .subtypes = &.{"Connection"},
        .cost = 3,
        .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        .static_abilities = &.{.{ .kind = .rez_cost, .value = 1 }},
        // "Whenever you encounter a piece of ice, if the Corp has 15cr or more, you may trash this resource to bypass that ice."
        .event_abilities = &.{.{
            .event = .ice_encountered,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.corp_credit < 15) return;
                    if (g.run == null) return;
                    const allocator = g.ephemeralAllocator();
                    g.runner_prompt_state = .{
                        .prompt_type = "fransofia-bypass",
                        .choices = try allocator.dupe(state.PromptChoice, &.{
                            stringChoice("Trash Fransofia Ward to bypass"),
                            stringChoice("No action"),
                        }),
                        .ability_ref = .{ .source_instance_id = card.instance_id, .ability_index = 0 },
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const ref = (cg.runner_prompt_state orelse return).ability_ref orelse return;
                                cg.runner_prompt_state = null;
                                if (std.mem.eql(u8, choice_text, "No action")) {
                                    // Continue encounter normally
                                    if (cg.run == null) return;
                                    const run = cg.run.?;
                                    const ice_idx = run.current_ice_index orelse return;
                                    const target_server = findServerByRunPath(cg.corp_servers.items, run.server) catch return;
                                    const ice_count = target_server.slot.ices.items.len;
                                    const actual = ice_count - 1 - ice_idx;
                                    const ice = target_server.slot.ices.items[actual];
                                    cg.decision_side = .runner;
                                    cg.legal_actions = try encounterActionsForState(cg.ephemeralAllocator(), cg, ice);
                                    return;
                                }
                                // Trash Fransofia Ward and bypass
                                try trashRunnerRigCardByInstanceId(cg, ref.source_instance_id);
                                cg.systemMsg(.runner, 35021, "Runner trashes Fransofia Ward to bypass ice.", .{});
                                try bypassCurrentIce(cg);
                            }
                        }.choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{
        .title = "Open Market",
        .side = .runner,
        .code = 35022,
        .card_type = "Resource",
        .subtypes = &.{ "Job", "Location" },
        .cost = 2,
        .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        .initial_credit_counters = 6,
        .take_credits_amount = 1,
        .trash_on_empty = true,
        // "You can spend hosted credits to install Job or Connection cards."
        .pay_credits = .{
            .context = .runner_install,
            .req = &struct {
                fn check(_: *const state.EffectContext, _: *const state.CardInstance, target: ?*const state.CardInstance) bool {
                    const t = target orelse return false;
                    return hasSubtype(t.*, "Job") or hasSubtype(t.*, "Connection");
                }
            }.check,
        },
        .event_abilities = &.{.{
            .event = .runner_turn_begins,
            .automatic_priority = state.Priority.gain_credits,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    if (card.credit_counter == 0) return;
                    const g = gameFromEffectContext(ctx);
                    const take = @min(card.credit_counter, card.take_credits_amount);
                    card.credit_counter -= take;
                    g.runner_credit += take;
                    g.systemMsg(.runner, card.code orelse 0, "Runner takes {d} [credit{s}] from {s}.", .{
                        take, if (take != 1) "s" else "", card.title,
                    });
                    if (card.trash_on_empty and card.credit_counter == 0) {
                        try trashRunnerRigCardByInstanceId(g, card.instance_id);
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "\"Knickknack\" O'Brian",
        .side = .runner,
        .code = 35033,
        .card_type = "Resource",
        .subtypes = &.{"Connection"},
        .cost = 2,
        .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        // "First time each turn a run begins, you may trash 1 of your other installed cards.
        //  If you do, gain credits equal to its printed install cost and draw 1 card."
        .event_abilities = &.{.{
            .event = .run_begins,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (isAbilityUsedThisTurn(card, 0)) return;
                    // Don't mark used yet — only mark after runner actually trashes
                    // Check if runner has other installed cards (need at least 2 total)
                    const total_installed = g.runner_rig_resources.items.len + g.runner_rig_program.items.len + g.runner_rig_hardware.items.len;
                    if (total_installed < 2) return; // Only Knickknack itself, nothing to trash
                    // Build choices: all other installed runner cards
                    const allocator = g.ephemeralAllocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    for (g.runner_rig_resources.items) |c| {
                        if (c.code != null and c.code.? == 35033) continue; // skip self
                        choices.append(allocator, .{ .kind = .card, .text = c.title, .card = .{
                            .title = c.title,
                            .code = c.code,
                            .side = .runner,
                        } }) catch continue;
                    }
                    for (g.runner_rig_program.items) |c| {
                        choices.append(allocator, .{ .kind = .card, .text = c.title, .card = .{
                            .title = c.title,
                            .code = c.code,
                            .side = .runner,
                        } }) catch continue;
                    }
                    for (g.runner_rig_hardware.items) |c| {
                        choices.append(allocator, .{ .kind = .card, .text = c.title, .card = .{
                            .title = c.title,
                            .code = c.code,
                            .side = .runner,
                        } }) catch continue;
                    }
                    choices.append(allocator, stringChoice("No action")) catch return;
                    g.runner_prompt_state = .{
                        .prompt_type = "knickknack-trash",
                        .choices = choices.toOwnedSlice(allocator) catch return,
                        .source_card = card.*,
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                if (std.mem.eql(u8, choice_text, "No action")) {
                                    cg.runner_prompt_state = null;
                                    // Run is already in progress, return to run flow
                                    return;
                                }
                                // Find and trash the selected installed card
                                var gain: u16 = 0;
                                // Check resources
                                for (cg.runner_rig_resources.items, 0..) |c, idx| {
                                    if (std.mem.eql(u8, c.title, choice_text)) {
                                        gain = c.cost orelse 0;
                                        const trashed = cg.runner_rig_resources.orderedRemove(idx);
                                        try appendDiscardCard(cg, .runner, trashed);
                                        break;
                                    }
                                }
                                // Check programs
                                if (gain == 0) {
                                    for (cg.runner_rig_program.items, 0..) |c, idx| {
                                        if (std.mem.eql(u8, c.title, choice_text)) {
                                            gain = c.cost orelse 0;
                                            const trashed = cg.runner_rig_program.orderedRemove(idx);
                                            try appendDiscardCard(cg, .runner, trashed);
                                            if (cg.runner_memory) |*mem| {
                                                const mu = trashed.runner_install.mu_cost;
                                                mem.used = if (mem.used >= mu) mem.used - mu else 0;
                                                mem.available = mem.base - mem.used;
                                            }
                                            break;
                                        }
                                    }
                                }
                                // Check hardware
                                if (gain == 0) {
                                    for (cg.runner_rig_hardware.items, 0..) |c, idx| {
                                        if (std.mem.eql(u8, c.title, choice_text)) {
                                            gain = c.cost orelse 0;
                                            const trashed = cg.runner_rig_hardware.orderedRemove(idx);
                                            try appendDiscardCard(cg, .runner, trashed);
                                            break;
                                        }
                                    }
                                }
                                // Mark ability used now (after actual trash, not on decline)
                                if (cg.runner_prompt_state) |ps| {
                                    if (ps.source_card) |sc| {
                                        if (findCardPtrByInstanceId(cg, sc.instance_id)) |live| {
                                            markAbilityUsedThisTurn(live, 0);
                                        }
                                    }
                                }
                                cg.runner_credit += gain;
                                try drawCards(cg, .runner, 1);
                                cg.systemMsg(.runner, 35033, "Runner uses \"Knickknack\" O'Brian to trash {s}, gain {d} [credits], and draw 1 card.", .{ choice_text, gain });
                                cg.runner_prompt_state = null;
                            }
                        }.choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = promptChoiceActions(allocator, .runner, g.runner_prompt_state.?) catch return;
                }
            }.handle,
        }},
    },
    .{
        .title = "Side Hustle",
        .side = .runner,
        .code = 35034,
        .card_type = "Resource",
        .subtypes = &.{"Job"},
        .cost = 2,
        .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        .initial_credit_counters = 1,
        .auto_trash_at_credits = 6,
        .draw_on_auto_trash = 1,
        .event_abilities = &.{.{
            .event = .run_begins,
            .automatic_priority = state.Priority.draw_cards,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    card.credit_counter += 1;
                    g.systemMsg(.runner, card.code orelse 0, "Runner places 1 [credit] on {s}.", .{card.title});
                    if (card.credit_counter >= card.auto_trash_at_credits) {
                        g.runner_credit += card.credit_counter;
                        g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credits] and draw {d} card{s}.", .{
                            card.title,                                                     card.credit_counter, card.draw_on_auto_trash,
                            if (card.draw_on_auto_trash != 1) @as([]const u8, "s") else "",
                        });
                        card.credit_counter = 0;
                        try drawCards(g, .runner, card.draw_on_auto_trash);
                        // Remove self from resources
                        if (findRunnerResourceIndex(g, card.code orelse 0)) |idx| {
                            const trashed = g.runner_rig_resources.orderedRemove(idx);
                            try appendDiscardCard(g, .runner, trashed);
                        }
                    }
                }
            }.handle,
        }},
    },
};

pub fn lookupCardSpecByCode(card_code: u32) ?CardSpec {
    for (all_cards) |spec| {
        if (spec.code == card_code) return spec;
    }
    return null;
}
