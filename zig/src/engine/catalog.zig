const std = @import("std");
const state = @import("state.zig");
const runtime = @import("runtime.zig");

const Game = runtime.Game;

const gameFromEffectContext = runtime.gameFromEffectContext;
const gameFromConstEffectContext = runtime.gameFromConstEffectContext;
const addAdvancementCounter = runtime.addAdvancementCounter;
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
const findRunnerHardwareByCode = runtime.findRunnerHardwareByCode;
const findRunnerResourceIndex = runtime.findRunnerResourceIndex;
const findServerByRunPath = runtime.findServerByRunPath;
const hasActivePrompt = runtime.hasActivePrompt;
const hostedChoiceIndex = runtime.hostedChoiceIndex;
const hostRandomHqCard = runtime.hostRandomHqCard;
const hostTopRunnerDeckCard = runtime.hostTopRunnerDeckCard;
const installCard = runtime.installCard;
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

/// Precision Design: select card from Archives to add to HQ
fn precisionDesignOnChoice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
    const g = gameFromEffectContext(ctx);
    if (std.mem.eql(u8, choice_text, "Done")) {
        g.corp_prompt_state = null;
        g.decision_side = .corp;
        g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
        return;
    }
    for (g.corp_discard.items, 0..) |card, idx| {
        if (std.mem.eql(u8, card.title, choice_text)) {
            const removed = g.corp_discard.orderedRemove(idx);
            try g.corp_hand.append(g.backing_allocator, removed);
            break;
        }
    }
    g.corp_prompt_state = null;
    g.decision_side = .corp;
    g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
}

/// Manegarm Skunkworks: runner pays cost or ends run to proceed to access
pub fn manegarmSkunkworksOnChoice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const allocator = g.arena.allocator();
    const prompt = g.runner_prompt_state orelse return error.MissingPrompt;
    const ref = prompt.ability_ref orelse return error.MissingSourceCard;
    const card = findCardPtrByInstanceId(g, ref.source_instance_id) orelse return error.MissingSourceCard;
    var run = &g.run.?;
    if (std.mem.eql(u8, choice_text, "Spend [Click][Click]")) {
        g.runner_click -= card.access.click_cost;
        g.systemMsg(.runner, 30042, "Runner uses Manegarm Skunkworks to spend [Click][Click].", .{});
    } else if (std.mem.eql(u8, choice_text, "Pay 5 [Credits]")) {
        g.runner_credit -= @intCast(card.access.credit_cost);
        g.systemMsg(.runner, 30042, "Runner uses Manegarm Skunkworks to pay 5 [Credits].", .{});
    } else if (std.mem.eql(u8, choice_text, "End the run")) {
        try completeUnsuccessfulRun(g);
        return;
    } else return error.UnsupportedChoice;
    g.runner_prompt_state = null;
    try applySuccessfulRunEffects(g);
    if (try prepareNextAccess(g)) {
        // Clojure's approach-server event resolves directly into breach —
        // no corp priority window between Manegarm payment and access.
        run.phase = try allocator.dupe(u8, "success");
        if (g.runner_prompt_state) |ps| {
            g.decision_side = .runner;
            g.legal_actions = try promptChoiceActions(allocator, .runner, ps);
        } else {
            g.decision_side = .runner;
            g.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
        }
        return;
    }
    try completeSuccessfulRunWithCorpPriority(g);
}

/// Brân 1.0: install ice from HQ/Archives subroutine
pub fn branInstallIceOnChoice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
    const g = gameFromEffectContext(ctx);
    try applyBranInstallIceChoice(g, choice_text);
}

/// Anoetic Void: corp pays 2cr + trash 2 from HQ + trash self to end run, or proceed to access
pub fn anoeticVoidOnChoice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
    const g = gameFromEffectContext(ctx);
    if (std.mem.eql(u8, choice_text, "Use Anoetic Void")) {
        // Corp pays 2 credits
        if (g.corp_credit < 2) return error.InsufficientCredits;
        g.corp_credit -= 2;
        // Trash 2 cards from HQ (first 2 available)
        var trashed: u8 = 0;
        while (trashed < 2 and g.corp_hand.items.len > 0) {
            const card = g.corp_hand.orderedRemove(0);
            try g.corp_discard.append(g.backing_allocator, card);
            trashed += 1;
        }
        // Trash Anoetic Void itself (find it in the server)
        if (g.run) |run| {
            const target = findServerByRunPath(g.corp_servers.items, run.server) catch null;
            if (target) |t| {
                const server = &g.corp_servers.items[t.index];
                for (server.content.items, 0..) |c, idx| {
                    if (c.code != null and c.code.? == 30050) {
                        const removed = server.content.orderedRemove(idx);
                        try g.corp_discard.append(g.backing_allocator, removed);
                        break;
                    }
                }
            }
        }
        // End the run
        try completeUnsuccessfulRun(g);
    } else {
        // "No action" — proceed to access
        g.corp_prompt_state = null;
        const run = &g.run.?;
        const allocator = g.arena.allocator();
        // Check Manegarm next
        if (try checkManegarmSkunkworks(g)) return;
        if (try prepareNextAccess(g)) {
            run.phase = try allocator.dupe(u8, "success");
            if (g.runner_prompt_state) |ps| {
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, ps);
            } else {
                g.decision_side = .runner;
                g.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
            }
            return;
        }
        try completeSuccessfulRunWithCorpPriority(g);
    }
}

/// Pantograph: optional install confirm + install choice
pub fn pantographOnChoice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const prompt = g.runner_prompt_state orelse return error.NoPromptState;
    if (std.mem.eql(u8, prompt.prompt_type, "runner-bonus-install-confirm")) {
        g.runner_prompt_state = null;
        if (std.mem.eql(u8, choice_text, "Yes")) {
            g.runner_credit += 1;
            g.systemMsg(.runner, 30023, "Runner uses Pantograph to gain 1 [credit].", .{});
            try beginRunnerOptionalInstallPrompt(g, (prompt.ability_ref orelse return error.MissingSourceCard).source_instance_id, &pantographOnChoice);
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

/// Top-Down Solutions: install card choice + server choice
pub fn topDownSolutionsOnChoice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const allocator = g.arena.allocator();
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
                        .prompt_type = try allocator.dupe(u8, "top-down-server"),
                        .choices = server_choices,
                        .ability_ref = prompt.ability_ref,
                        .min_choices = @intCast((card_idx & 0xF) | (@as(u8, prompt.min_choices) << 4)),
                        .on_choice = &topDownSolutionsOnChoice,
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
            try showTopDownInstallChoices(g, (prompt.ability_ref orelse return error.NoPromptState).source_instance_id, installs_done + 1);
        }
    } else return error.UnsupportedChoice;
}

/// Peer Review: private card discard + install choice + server choice
pub fn peerReviewOnChoice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const allocator = g.arena.allocator();
    const prompt = g.corp_prompt_state orelse return error.NoPromptState;
    if (std.mem.eql(u8, prompt.prompt_type, "peer-review-private")) {
        try beginPeerReviewInstallPrompt(g, (prompt.ability_ref orelse return error.NoPromptState).source_instance_id);
        return;
    } else if (std.mem.eql(u8, prompt.prompt_type, "peer-review-install")) {
        for (prompt.choices) |ch| {
            if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                if (ch.card) |card_ref| {
                    var server_choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer server_choices.deinit(allocator);
                    for (g.corp_servers.items, 0..) |_, si| {
                        if (si < 4) continue; // skip HQ, R&D, Archives, placeholder
                        const name = try std.fmt.allocPrint(allocator, "Server {d}", .{si - 3});
                        try server_choices.append(allocator, stringChoice(name));
                    }
                    try server_choices.append(allocator, stringChoice("New remote"));
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "peer-review-server"),
                        .choices = try server_choices.toOwnedSlice(allocator),
                        .ability_ref = prompt.ability_ref,
                        .min_choices = card_ref.index orelse 0,
                        .on_choice = &peerReviewOnChoice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    return;
                }
            }
        }
        return error.UnsupportedChoice;
    } else if (std.mem.eql(u8, prompt.prompt_type, "peer-review-server")) {
        const card_index = prompt.min_choices;
        if (card_index >= g.corp_hand.items.len) return error.InvalidCardIndex;
        const card_to_install = g.corp_hand.items[card_index];
        try installCorpCardFromHand(g, card_index, choice_text);
        g.systemMsg(.corp, 35055, "Corp uses Peer Review to install {s}.", .{card_to_install.title});
        g.corp_prompt_state = null;
        g.decision_side = .corp;
        g.legal_actions = try corpOpeningActionsForState(allocator, g);
    } else return error.UnsupportedChoice;
}

/// Key Performance Indicators: resolve 2 of gain credits / install ice / advance / draw+shuffle
pub fn kpiOnChoice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const allocator = g.arena.allocator();
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
                .prompt_type = try allocator.dupe(u8, "kpi-shuffle"),
                .choices = try hand_choices.toOwnedSlice(allocator),
                .ability_ref = prompt.ability_ref,
                .min_choices = choices_made + 1,
                .on_choice = &kpiOnChoice,
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
                    .prompt_type = try allocator.dupe(u8, "kpi-advance"),
                    .choices = adv_choices,
                    .ability_ref = prompt.ability_ref,
                    .min_choices = choices_made + 1,
                    .on_choice = &kpiOnChoice,
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
                    .prompt_type = try allocator.dupe(u8, "kpi-ice-choose"),
                    .choices = try ice_choices.toOwnedSlice(allocator),
                    .ability_ref = prompt.ability_ref,
                    .min_choices = choices_made + 1,
                    .on_choice = &kpiOnChoice,
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
            try showKpiChoices(g, (prompt.ability_ref orelse return error.NoPromptState).source_instance_id, choices_made + 1);
        }
    } else if (std.mem.eql(u8, prompt.prompt_type, "kpi-advance")) {
        _ = try addAdvancementCounter(g, choice_text, 1);
        g.systemMsg(.corp, 35077, "Corp uses Key Performance Indicators to place 1 advancement counter.", .{});
        if (prompt.min_choices >= 2) {
            g.corp_prompt_state = null;
            g.decision_side = .corp;
            g.legal_actions = try corpOpeningActionsForState(allocator, g);
        } else {
            try showKpiChoices(g, (prompt.ability_ref orelse return error.NoPromptState).source_instance_id, prompt.min_choices);
        }
    } else if (std.mem.eql(u8, prompt.prompt_type, "kpi-ice-choose")) {
        for (prompt.choices) |ch| {
            if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                if (ch.card) |card_ref| {
                    const server_choices = try installChoicesForCard(allocator, .corp_server_choice, g);
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "kpi-ice-server"),
                        .choices = server_choices,
                        .ability_ref = prompt.ability_ref,
                        .min_choices = @intCast((card_ref.index orelse 0) | (@as(u8, prompt.min_choices) << 4)),
                        .on_choice = &kpiOnChoice,
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
            try showKpiChoices(g, (prompt.ability_ref orelse return error.NoPromptState).source_instance_id, choices_done);
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
                try showKpiChoices(g, (prompt.ability_ref orelse return error.NoPromptState).source_instance_id, prompt.min_choices);
            }
            return;
        }
        return error.UnsupportedChoice;
    } else return error.UnsupportedChoice;
}

pub fn blingOnChoice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const prompt = g.runner_prompt_state orelse return error.NoPromptState;
    if (!std.mem.eql(u8, prompt.prompt_type, "runner-hosted-card")) return error.UnsupportedChoice;
    if (std.mem.eql(u8, choice_text, "No action")) {
        g.runner_prompt_state = null;
        g.decision_side = .runner;
        g.legal_actions = try runnerOpeningActionsForState(g.arena.allocator(), g);
        return;
    }
    const ref = prompt.ability_ref orelse return error.MissingSourceCard;
    const host = findCardPtrByInstanceId(g, ref.source_instance_id) orelse return error.InvalidCardIndex;
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

pub fn scroungeOnChoice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const prompt = g.runner_prompt_state orelse return error.NoPromptState;
    if (std.mem.eql(u8, prompt.prompt_type, "scrounge-install")) {
        const ref = prompt.ability_ref orelse return error.MissingSourceCard;
        g.runner_prompt_state = null;
        try g.pending_effects.append(g.backing_allocator, .{ .runner_discard_to_deck_prompt = ref.source_instance_id });
        if (std.mem.eql(u8, choice_text, "No action")) {
            if (try resumePendingEffects(g)) return;
            try restorePriorityAfterPrompt(g);
            return;
        }
        for (g.runner_discard.items, 0..) |c, idx| {
            if (!std.mem.eql(u8, c.title, choice_text)) continue;
            const card = g.runner_discard.orderedRemove(idx);
            try g.runner_hand.append(g.backing_allocator, card);
            const hand_index: u8 = @intCast(g.runner_hand.items.len - 1);
            try beginRunnerInstallFromHand(g, hand_index, false);
            g.systemMsg(.runner, 35004, "Runner uses Scrounge to install {s} from the heap.", .{card.title});
            if (hasActivePrompt(g) or g.pending_install != null) return;
            if (try resumePendingEffects(g)) return;
            try restorePriorityAfterPrompt(g);
            return;
        }
        return error.UnsupportedChoice;
    }
    if (std.mem.eql(u8, prompt.prompt_type, "runner-discard-to-deck")) {
        g.runner_prompt_state = null;
        if (!std.mem.eql(u8, choice_text, "No action")) {
            for (g.runner_discard.items, 0..) |card, idx| {
                if (!std.mem.eql(u8, card.title, choice_text)) continue;
                const bottomed = g.runner_discard.orderedRemove(idx);
                try g.runner_deck.append(g.backing_allocator, bottomed);
                g.systemMsg(.runner, 35004, "Runner uses Scrounge to put {s} on the bottom of the stack.", .{card.title});
                break;
            }
        }
        try restorePriorityAfterPrompt(g);
        return;
    }
    return error.UnsupportedChoice;
}

// --- Comptime helpers for icebreaker ability generation ---

/// Generate a break subroutine AbilitySpec for an icebreaker.
/// base_cost: credit cost per activation (before modifiers)
/// break_count: number of subs broken per activation
fn breakAbility(comptime base_cost: u16) state.AbilitySpec {
    return .{
        .req = &struct {
            fn req(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                const run = g.run orelse return false;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return false;
                const ice_idx = run.current_ice_index orelse return false;
                const server = findServerByRunPath(g.corp_servers.items, run.server) catch return false;
                const ice_count = server.slot.ices.items.len;
                if (ice_idx >= ice_count) return false;
                const actual_idx = ice_count - 1 - ice_idx;
                const ice = server.slot.ices.items[actual_idx];
                if (!canBreakIceType(card.*, ice)) return false;
                const ice_str = effectiveIceStrength(ice, run.server, run.ice_strength_modifier);
                if (effectiveStrength(card.*) < ice_str) return false;
                const cost = applyCostModifier(base_cost, sumStaticEffects(g, .runner, .break_cost, card));
                return g.runner_credit >= cost;
            }
        }.req,
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const run = g.run orelse return error.NoRunInProgress;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;
                const ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
                const server = &g.corp_servers.items[target_server.index];
                const ice_count = server.ices.items.len;
                if (ice_idx >= ice_count) return error.InvalidIceIndex;
                const actual_idx = ice_count - 1 - ice_idx;
                const ice = &server.ices.items[actual_idx];
                const cost = applyCostModifier(base_cost, sumStaticEffects(g, .runner, .break_cost, card));
                if (g.runner_credit < cost) return error.InsufficientCredits;
                g.runner_credit -= cost;
                card.used_break_this_run = true;
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to break subroutine on {s}.", .{ card.title, ice.title });
                try openBreakSubPrompt(g, ice, card.*, 0);
            }
        }.use,
        .label = "Break subroutine",
    };
}

/// Generate a pump strength AbilitySpec for an icebreaker.
/// base_cost: credit cost per pump (before modifiers)
/// pump_amount: strength increase per pump
fn pumpAbility(comptime base_cost: u16, comptime pump_amount: u8) state.AbilitySpec {
    return .{
        .req = &struct {
            fn req(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                const run = g.run orelse return false;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return false;
                const ice_idx = run.current_ice_index orelse return false;
                const server = findServerByRunPath(g.corp_servers.items, run.server) catch return false;
                const ice_count = server.slot.ices.items.len;
                if (ice_idx >= ice_count) return false;
                const actual_idx = ice_count - 1 - ice_idx;
                const ice = server.slot.ices.items[actual_idx];
                if (!canBreakIceType(card.*, ice)) return false;
                const cost = applyCostModifier(base_cost, sumStaticEffects(g, .runner, .pump_cost, card));
                return g.runner_credit >= cost;
            }
        }.req,
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const run = g.run orelse return error.NoRunInProgress;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;
                const cost = applyCostModifier(base_cost, sumStaticEffects(g, .runner, .pump_cost, card));
                if (g.runner_credit < cost) return error.InsufficientCredits;
                g.runner_credit -= cost;
                const current = effectiveStrength(card.*);
                card.current_strength = current + pump_amount;
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to increase strength to {d}.", .{ card.title, card.current_strength orelse 0 });
                // Regenerate encounter actions
                const ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
                const server = &g.corp_servers.items[target_server.index];
                const ice_count = server.ices.items.len;
                if (ice_idx >= ice_count) return error.InvalidIceIndex;
                const actual_idx = ice_count - 1 - ice_idx;
                const ice = server.ices.items[actual_idx];
                g.decision_side = .runner;
                g.legal_actions = try encounterActionsForState(g.arena.allocator(), g, ice);
            }
        }.use,
        .label = "Boost strength",
    };
}

/// Generate a bioroid click-to-break AbilitySpec for ICE.
/// click_cost: clicks to spend per activation
/// break_qty: number of subs broken per activation
fn bioroidBreakAbility(comptime click_cost: u8, comptime break_qty: u8) state.AbilitySpec {
    return .{
        .cost = .{ .clicks = click_cost },
        .allow_opponent_use = true,
        .side = .corp,
        .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                const run = g.run orelse return false;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return false;
                return true;
            }
        }.req,
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const run = g.run orelse return error.NoRunInProgress;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;
                const ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
                const server = &g.corp_servers.items[target_server.index];
                const ice_count = server.ices.items.len;
                if (ice_idx >= ice_count) return error.InvalidIceIndex;
                const actual_idx = ice_count - 1 - ice_idx;
                var ice = &server.ices.items[actual_idx];
                // Break first break_qty unbroken subroutines
                var broken_count: u8 = 0;
                for (ice.subroutines, 0..) |_, sub_idx| {
                    if (broken_count >= break_qty) break;
                    const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(sub_idx))) != 0;
                    if (!is_broken) {
                        ice.broken_subroutines |= (@as(u16, 1) << @as(u4, @intCast(sub_idx)));
                        broken_count += 1;
                    }
                }
                g.systemMsg(.runner, card.code orelse 0, "Runner spends [click] to break {d} subroutine(s) on {s}.", .{ broken_count, ice.title });
                // Regenerate encounter actions
                g.decision_side = .runner;
                g.legal_actions = try encounterActionsForState(g.arena.allocator(), g, ice.*);
            }
        }.use,
        .label = "Lose click(s) to break subroutine(s)",
    };
}

/// Create an AbilitySpec for playing a corp operation from hand.
/// card_cost: credit cost to play the card
/// gain: credits gained by the effect
/// draw: cards drawn by the effect
fn corpPlayAbility(comptime card_cost: u16, comptime gain: u16, comptime draw: u8) state.AbilitySpec {
    return .{
        .cost = .{ .clicks = 1, .credits = card_cost },
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const side = card.side;
                // Remove from hand and discard (clicks+credits already spent by payAbilityCost)
                const played = try removeCardFromHandByInstanceId(g, side, card.instance_id);
                try appendDiscardCard(g, side, played);
                // Resolve effect
                if (gain > 0) {
                    g.corp_credit += gain;
                }
                try drawCards(g, side, draw);
                if (gain > 0) {
                    g.turn_events.operation_played_count += 1;
                    _ = try fireEvent(g, .operation_played);
                }
                // Log
                if (card_cost > 0) {
                    g.systemMsg(side, card.code orelse 0, "Corp spends [click] and pays {d} [credit{s}] to play {s}.", .{
                        card_cost, if (card_cost != 1) "s" else "", card.title,
                    });
                } else {
                    g.systemMsg(side, card.code orelse 0, "Corp spends [click] to play {s}.", .{card.title});
                }
                // Set legal actions
                if (!hasActivePrompt(g)) {
                    g.decision_side = side;
                    g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
                }
            }
        }.use,
        .label = "Play",
    };
}

/// Create an AbilitySpec for playing a corp operation with a custom handler.
/// card_cost: credit cost to play the card
/// extra_clicks: additional clicks beyond the base 1 (e.g. 1 for Double operations)
/// req_fn: optional requirement check
/// handler: the custom effect handler
fn corpCustomPlayAbility(
    comptime card_cost: u16,
    comptime extra_clicks: u8,
    comptime req_fn: ?*const fn (*const state.EffectContext, *const state.CardInstance) bool,
    comptime handler: *const fn (*state.EffectContext, *state.CardInstance) anyerror!void,
) state.AbilitySpec {
    return .{
        .cost = .{ .clicks = 1 + extra_clicks, .credits = card_cost },
        .req = req_fn,
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const played = try removeCardFromHandByInstanceId(g, card.side, card.instance_id);
                try appendDiscardCard(g, card.side, played);
                if (card_cost > 0) {
                    g.systemMsg(.corp, card.code orelse 0, "Corp spends [click] and pays {d} [credit{s}] to play {s}.", .{
                        card_cost, if (card_cost != 1) "s" else "", card.title,
                    });
                } else {
                    g.systemMsg(.corp, card.code orelse 0, "Corp spends [click] to play {s}.", .{card.title});
                }
                try handler(ctx, card);
            }
        }.use,
        .label = "Play",
    };
}

/// Create an AbilitySpec for playing a runner event that gains credits from hand.
fn runnerGainCreditsPlayAbility(comptime gain: u16, comptime draw: u8, comptime lose_clicks: u8) state.AbilitySpec {
    return .{
        .cost = .{ .clicks = 1 + lose_clicks },
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const side = card.side;
                const card_cost = card.cost orelse 0;
                // Remove from hand and discard
                const played = try removeCardFromHandByInstanceId(g, side, card.instance_id);
                try appendDiscardCard(g, side, played);
                // Pay card cost (clicks already spent by payAbilityCost)
                try spendCredits(g, side, card_cost);
                // Resolve effect
                g.runner_credit += gain;
                try drawCards(g, side, draw);
                // Log
                if (card_cost > 0) {
                    g.systemMsg(side, card.code orelse 0, "Runner spends [click] and pays {d} [credit{s}] to play {s}.", .{
                        card_cost, if (card_cost != 1) "s" else "", card.title,
                    });
                } else {
                    g.systemMsg(side, card.code orelse 0, "Runner spends [click] to play {s}.", .{card.title});
                }
                // Set legal actions
                if (!hasActivePrompt(g)) {
                    g.decision_side = side;
                    g.legal_actions = try runnerOpeningActionsForState(g.arena.allocator(), g);
                }
            }
        }.use,
        .label = "Play",
    };
}

/// Create an AbilitySpec for playing a runner event with a custom handler.
fn runnerCustomPlayAbility(
    comptime extra_clicks: u8,
    comptime req_fn: ?*const fn (*const state.EffectContext, *const state.CardInstance) bool,
    comptime handler: *const fn (*state.EffectContext, *state.CardInstance) anyerror!void,
) state.AbilitySpec {
    return .{
        .cost = .{ .clicks = 1 + extra_clicks },
        .req = req_fn,
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const card_cost = card.cost orelse 0;
                const played = try removeCardFromHandByInstanceId(g, card.side, card.instance_id);
                try appendDiscardCard(g, card.side, played);
                try spendCredits(g, .runner, card_cost);
                if (card_cost > 0) {
                    g.systemMsg(.runner, card.code orelse 0, "Runner spends [click] and pays {d} [credit{s}] to play {s}.", .{
                        card_cost, if (card_cost != 1) "s" else "", card.title,
                    });
                } else {
                    g.systemMsg(.runner, card.code orelse 0, "Runner spends [click] to play {s}.", .{card.title});
                }
                try handler(ctx, card);
            }
        }.use,
        .label = "Play",
    };
}

/// Create an AbilitySpec for playing a runner run event that prompts for a run target.
fn runnerRunEventPlayAbility(
    comptime extra_clicks: u8,
    comptime run_target_kind: state.RunTargetKind,
    comptime run_credits: u16,
    comptime run_rez_cost_bonus: u16,
    comptime successful_run_access_bonus: u8,
    comptime gain_credits: u16,
    comptime successful_run_draw_cards: u8,
) state.AbilitySpec {
    return .{
        .cost = .{ .clicks = 1 + extra_clicks },
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                const card_cost = card.cost orelse 0;
                const played = try removeCardFromHandByInstanceId(g, card.side, card.instance_id);
                try appendDiscardCard(g, card.side, played);
                try spendCredits(g, .runner, card_cost);
                if (gain_credits > 0) {
                    g.runner_credit += gain_credits;
                }
                if (card_cost > 0) {
                    g.systemMsg(.runner, card.code orelse 0, "Runner spends [click] and pays {d} [credit{s}] to play {s}.", .{
                        card_cost, if (card_cost != 1) "s" else "", card.title,
                    });
                } else {
                    g.systemMsg(.runner, card.code orelse 0, "Runner spends [click] to play {s}.", .{card.title});
                }
                const run_target_choices = try runTargetChoicesFor(allocator, run_target_kind, g.corp_servers.items);
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "run-target"),
                    .choices = run_target_choices,
                    .source_card = card.*,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &struct {
                        fn handle(ctx2: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const g2 = gameFromEffectContext(ctx2);
                            const allocator2 = g2.arena.allocator();
                            const run_server = try canonicalRunServer(allocator2, choice_text);
                            trackMadeRun(g2, run_server);
                            const target_server = try findServerByRunPath(g2.corp_servers.items, run_server);
                            const initial_position: u8 = @intCast(target_server.slot.ices.items.len);
                            g2.runner_prompt_state = .{ .prompt_type = try allocator2.dupe(u8, "run"), .choices = &.{}, .source_card = null };
                            g2.corp_prompt_state = .{ .prompt_type = try allocator2.dupe(u8, "run"), .choices = &.{}, .source_card = null };
                            const prompt = g2.runner_prompt_state orelse return error.MissingPrompt;
                            _ = prompt;
                            g2.run = .{
                                .server = run_server,
                                .position = initial_position,
                                .phase = try allocator2.dupe(u8, "initiation"),
                                .encounter_phase = .none,
                                .current_ice_index = null,
                                .corp_auto_no_action = false,
                                .no_action = null,
                                .temporary_run_credits = run_credits,
                                .accesses_remaining = 0,
                                .accessed_count = 0,
                                .accessed_card_indexes = .{ null, null, null, null },
                                .access_card_index = null,
                                .rez_cost_bonus = run_rez_cost_bonus,
                                .access_bonus = successful_run_access_bonus,
                                .jack_out_available = false,
                                .source_card_code = null,
                            };
                            if (successful_run_draw_cards > 0) {
                                g2.run.?.successful_run_draw_cards = successful_run_draw_cards;
                            }
                            if (try fireEvent(g2, .run_begins)) return;
                            g2.decision_side = .corp;
                            g2.legal_actions = try continueActions(allocator2, .corp);
                        }
                    }.handle,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.use,
        .label = "Play",
    };
}

// Handler type for card-specific subroutine resolution
pub const CardSubroutineHandler = *const fn (
    generated: *Game,
    ice: *const state.CardInstance,
    subroutine_index: u8,
) anyerror!void;

pub const CardSpec = struct {
    title: []const u8,
    side: state.Side,
    code: u32,
    card_type: ?[]const u8 = null,
    subtypes: []const []const u8 = &.{},
    cost: ?u16 = null,
    strength: ?u8 = null,
    remote_strength_bonus: u8 = 0,
    agenda_points: ?u8 = null,
    advancement_requirement: ?u8 = null,
    corp_play: state.CorpPlaySpec = .{},
    runner_play: state.RunnerPlaySpec = .{},
    access: state.AccessSpec = .{},
    install: state.InstallSpec = .{},
    runner_install: state.RunnerInstallSpec = .{},
    static_abilities: []const state.StaticAbility = &.{},
    event_abilities: []const state.EventAbility = &.{},
    installed_ability: state.InstalledAbilitySpec = .{},
    subroutines: []const state.SubroutineSpec = &.{},
    abilities: []const state.AbilitySpec = &.{},
    initial_credit_counters: u16 = 0,
    on_install: ?*const fn (*state.EffectContext, *state.CardInstance) anyerror!void = null,
    break_subroutine_count: u8 = 0,
    on_steal_fn: ?*const fn (*Game, state.CardInstance) anyerror!void = null,
    card_subroutine_handler: ?CardSubroutineHandler = null,
    trash_cost: ?u16 = null,
    tag_on_rez: u8 = 0,
    advanceable: bool = false,
    advancement_strength_threshold: u8 = 0,
    advancement_strength_bonus: u8 = 0,
    can_play: ?*const fn (*const Game) bool = null,
    on_play: ?*const fn (*Game, state.CardInstance) anyerror!void = null,
    on_score_fn: ?*const fn (*Game, state.CardInstance) anyerror!void = null,
    on_encounter: ?*const fn (*Game, *const state.CardInstance) anyerror!void = null,
    on_rez: ?*const fn (*Game) anyerror!void = null,
    on_rez_msg: ?[]const u8 = null,
    on_play_msg: ?[]const u8 = null,
    on_score_msg: ?[]const u8 = null,
    flashback_click_cost: u8 = 0,
    flashback_gain_clicks: u8 = 0,
    installs_agendas_faceup: bool = false,
    identity_ability_click_cost: u8 = 0,
    identity_ability_once_per_turn: bool = true,
    identity_ability_label: ?[]const u8 = null,
    // Encounter/access/trojan mechanics (moved from InstalledAbilitySpec)
    virus_ice_strength_reduction: u8 = 0,
    tags_on_agenda_steal_from_server: u8 = 0,
    trash_access_hand_cost: u8 = 0,
    trash_access_self_trash: bool = false,
    trash_access_draw: u8 = 0,
    trojan_break_any: bool = false,
    trojan_derez_threshold: u8 = 0,
    trojan_adds_all_subtypes: bool = false,
};

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
                    const allocator = g.arena.allocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_discard.items, 0..) |card, idx| {
                        try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                    }
                    try choices.append(allocator, stringChoice("Done"));
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "precision-design-archive"),
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = null,
                        .ability_ref = .{ .source_instance_id = g.corp_identity.instance_id },
                        .on_choice = &precisionDesignOnChoice,
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
                    const allocator = g.arena.allocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    try choices.append(allocator, stringChoice("Gain 2 [Credits]"));
                    try choices.append(allocator, stringChoice("Draw 2 cards"));
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "reality-plus"),
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = g.corp_identity,
                        .ability_ref = .{ .source_instance_id = g.corp_identity.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.runner_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "waiting"),
                        .choices = &.{},
                        .source_card = null,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (std.mem.eql(u8, choice_text, "Gain 2 [Credits]")) {
                        g.corp_credit += 2;
                    } else if (std.mem.eql(u8, choice_text, "Draw 2 cards")) {
                        try drawCards(g, .corp, 2);
                    } else return error.UnsupportedChoice;
                    g.systemMsg(.corp, 30051, "Corp uses NBN: Reality Plus to {s}.", .{choice_text});
                    g.corp_prompt_state = null;
                    g.runner_prompt_state = null;
                    if (g.run != null) {
                        g.decision_side = .runner;
                        g.legal_actions = try runnerOpeningActionsForState(g.arena.allocator(), g);
                    } else {
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
                    }
                }
            }.handle,
        }},
    },
    .{
        .title = "Weyland Consortium: Built to Last",
        .side = .corp,
        .code = 30059,
        .card_type = "Identity",
        // Advance trigger is handled inline in addAdvancementCounter since it needs the card's old state
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
                    const allocator = g.arena.allocator();
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
                        .prompt_type = try allocator.dupe(u8, "tao-swap-ice"),
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = null,
                        .ability_ref = .{ .source_instance_id = g.runner_identity.instance_id },
                        .min_choices = 0,
                        .on_choice = &applyTaoSwapIceOnChoice,
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
                    if (run.server.len == 0) return;
                    if (!std.mem.eql(u8, run.server[0], "hq") and !std.mem.eql(u8, run.server[0], "rnd")) return;
                    const accessed = run.accessed_count;
                    if (accessed == 0) return;
                    // Optional prompt: can decline to save once-per-turn ability for later run
                    const allocator = g.arena.allocator();
                    const choices = try allocator.alloc(state.PromptChoice, 2);
                    choices[0] = stringChoice("Yes");
                    choices[1] = stringChoice("No");
                    g.runner_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "zahya-gain"),
                        .choices = choices,
                        .source_card = g.runner_identity,
                        .ability_ref = .{ .source_instance_id = g.runner_identity.instance_id },
                        .min_choices = @intCast(accessed), // stash accessed count for resolution
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (std.mem.eql(u8, choice_text, "Yes")) {
                        const accessed = g.runner_prompt_state.?.min_choices;
                        g.runner_credit += accessed;
                        g.systemMsg(.runner, 30010, "Runner uses Zahya to gain {d} [credit{s}].", .{ accessed, if (accessed != 1) "s" else "" });
                    }
                    g.runner_prompt_state = null;
                    g.decision_side = .runner;
                    g.legal_actions = try runnerOpeningActionsForState(g.arena.allocator(), g);
                }
            }.handle,
        }},
    },
    .{
        .title = "Offworld Office",
        .side = .corp,
        .code = 30067,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 4,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                g.corp_credit += 7;
                g.systemMsg(.corp, 0, "Corp gains 7 [credits].", .{});
            }
        }.score,
    },
    .{
        .title = "Send a Message",
        .side = .corp,
        .code = 30069,
        .card_type = "Agenda",
        .agenda_points = 3,
        .advancement_requirement = 5,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, card: state.CardInstance) anyerror!void {
                try g.pending_effects.insert(g.backing_allocator, 0, .{ .on_score_rez_ice_free = card });
            }
        }.score,
        .on_steal_fn = &struct {
            fn steal(g: *Game, card: state.CardInstance) anyerror!void {
                try g.pending_effects.append(g.backing_allocator, .{ .on_steal_rez_ice_free = card });
            }
        }.steal,
    },
    .{
        .title = "Superconducting Hub",
        .side = .corp,
        .code = 30070,
        .card_type = "Agenda",
        .agenda_points = 1,
        .advancement_requirement = 3,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .static_abilities = &.{.{ .kind = .hand_size, .value = 2 }},
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                try drawCards(g, .corp, 2);
                g.systemMsg(.corp, 30070, "Corp draws 2 cards.", .{});
            }
        }.score,
    },
    .{
        .title = "Orbital Superiority",
        .side = .corp,
        .code = 30068,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 4,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                if (is_runner_tagged(g.runner_tag)) {
                    try trashRandomRunnerHandCards(g, 4);
                    g.systemMsg(.corp, 30068, "Corp uses Orbital Superiority to do 4 meat damage.", .{});
                    updateTerminalState(g);
                } else {
                    _ = try addRunnerTag(g, 1);
                    g.systemMsg(.corp, 30068, "Corp uses Orbital Superiority to give Runner 1 tag.", .{});
                }
            }
        }.score,
    },
    .{ .title = "Nico Campaign", .side = .corp, .code = 30037, .card_type = "Asset", .cost = 2, .trash_cost = 2, .install = .{ .kind = .corp_remote_only }, .initial_credit_counters = 9, .installed_ability = .{
        .kind = .start_of_turn_credits,
        .take_credits_amount = 3,
        .trash_on_empty = true,
        .on_empty = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                try drawCards(gameFromEffectContext(ctx), .corp, 1);
            }
        }.handle,
    } },
    .{ .title = "Regolith Mining License", .side = .corp, .code = 30071, .card_type = "Asset", .cost = 2, .trash_cost = 3, .install = .{ .kind = .corp_remote_only }, .initial_credit_counters = 15, .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .req = &struct {
            fn req(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                return card.credit_counter > 0;
            }
        }.req,
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const amount = @min(card.credit_counter, 3);
                g.corp_credit += amount;
                card.credit_counter -= amount;
                g.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to gain {d} [credit{s}].", .{
                    card.title, amount, if (amount != 1) @as([]const u8, "s") else "",
                });
                if (card.credit_counter == 0) {
                    try trashCorpInstalledSelf(g, card.code orelse return error.MissingCardCode);
                }
            }
        }.use,
        .label = "Take 3 [Credits]",
    }} },
    .{ .title = "Urtica Cipher", .side = .corp, .code = 30045, .card_type = "Asset", .cost = 0, .trash_cost = 2, .access = .{ .kind = .net_damage_on_access, .corp_credit_cost = 2, .base_damage = 2, .adds_advancement = true }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Government Subsidy", .side = .corp, .code = 30064, .card_type = "Operation", .cost = 10, .abilities = &.{corpPlayAbility(10, 15, 0)} },
    .{ .title = "Hedge Fund", .side = .corp, .code = 30075, .card_type = "Operation", .cost = 5, .abilities = &.{corpPlayAbility(5, 9, 0)} },
    .{
        .title = "Seamless Launch",
        .side = .corp,
        .code = 30040,
        .card_type = "Operation",
        .cost = 1,
        .abilities = &.{corpCustomPlayAbility(1, 0, null, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                _ = card;
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                const choices = try installedNotThisTurnChoices(allocator, g.corp_servers.items);
                if (choices.len == 0) {
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                    return;
                }
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "seamless-advance"),
                    .choices = choices,
                    .on_choice = &on_choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
            fn on_choice(ctx2: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g2 = gameFromEffectContext(ctx2);
                const advanced_card = try addAdvancementCounter(g2, choice_text, 2);
                g2.systemMsg(.corp, 30040, "Corp uses Seamless Launch to advance {s} 2 times.", .{advanced_card.title});
                g2.corp_prompt_state = null;
                g2.decision_side = .corp;
                g2.legal_actions = try corpOpeningActionsForState(g2.arena.allocator(), g2);
            }
        }.play)},
    },
    .{
        .title = "Predictive Planogram",
        .side = .corp,
        .code = 30056,
        .card_type = "Operation",
        .cost = 0,
        .abilities = &.{corpCustomPlayAbility(0, 0, null, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "other"),
                    .choices = try predictive_planogram_choices(allocator, g.runner_tag),
                    .source_card = card.*,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &on_choice,
                };
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                if (std.mem.eql(u8, choice_text, "Gain 3 [Credits]")) {
                    g.corp_credit += 3;
                } else if (std.mem.eql(u8, choice_text, "Draw 3 cards")) {
                    try drawCards(g, .corp, 3);
                } else if (std.mem.eql(u8, choice_text, "Gain 3 [Credits] and draw 3 cards")) {
                    g.corp_credit += 3;
                    try drawCards(g, .corp, 3);
                } else return error.UnsupportedChoice;
                g.systemMsg(.corp, 30056, "Corp uses Predictive Planogram to {s}.", .{choice_text});
                g.corp_prompt_state = null;
                g.runner_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play)},
    },
    .{
        .title = "Public Trail",
        .side = .corp,
        .code = 30057,
        .card_type = "Operation",
        .cost = 4,
        .abilities = &.{corpCustomPlayAbility(4, 0, &struct {
            fn check(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                return runner_had_successful_run_last_turn(g);
            }
        }.check, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                if (!runner_had_successful_run_last_turn(g)) {
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                    return;
                }
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "other"),
                    .choices = try public_trail_choices(allocator, g.runner_credit),
                    .source_card = card.*,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &on_choice,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                if (std.mem.eql(u8, choice_text, "Take 1 tag")) {
                    g.systemMsg(.runner, 30057, "Runner uses Public Trail to {s}.", .{choice_text});
                    if (try addRunnerTag(g, 1)) return; // Event handler opened prompt
                } else if (std.mem.eql(u8, choice_text, "Pay 8 [Credits]")) {
                    g.systemMsg(.runner, 30057, "Runner uses Public Trail to {s}.", .{choice_text});
                    try spendCredits(g, .runner, 8);
                } else return error.UnsupportedChoice;
                g.runner_prompt_state = null;
                g.corp_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play)},
    },
    .{
        .title = "Retribution",
        .side = .corp,
        .code = 30065,
        .card_type = "Operation",
        .cost = 1,
        .abilities = &.{corpCustomPlayAbility(1, 0, &struct {
            fn check(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                return is_runner_tagged(g.runner_tag) and
                    (g.runner_rig_hardware.items.len > 0 or g.runner_rig_program.items.len > 0);
            }
        }.check, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
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
                    .prompt_type = try allocator.dupe(u8, "retribution-trash"),
                    .choices = choices,
                    .source_card = card.*,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &on_choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                var pieces = std.mem.splitScalar(u8, choice_text, '|');
                const zone = pieces.next() orelse return error.UnsupportedChoice;
                const index_text = pieces.next() orelse return error.UnsupportedChoice;
                const index = try std.fmt.parseInt(usize, index_text, 10);
                if (std.mem.eql(u8, zone, "h")) {
                    if (index >= g.runner_rig_hardware.items.len) return error.UnsupportedChoice;
                    const trashed = g.runner_rig_hardware.orderedRemove(index);
                    g.systemMsg(.corp, 30065, "Corp uses Retribution to trash {s}.", .{trashed.title});
                    try g.runner_discard.append(g.backing_allocator, trashed);
                } else if (std.mem.eql(u8, zone, "p")) {
                    if (index >= g.runner_rig_program.items.len) return error.UnsupportedChoice;
                    const trashed = g.runner_rig_program.orderedRemove(index);
                    g.systemMsg(.corp, 30065, "Corp uses Retribution to trash {s}.", .{trashed.title});
                    try g.runner_discard.append(g.backing_allocator, trashed);
                    if (g.runner_memory) |*mem| {
                        const mu = trashed.runner_install.mu_cost;
                        if (mem.used >= mu) mem.used -= mu else mem.used = 0;
                        mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
                    }
                } else return error.UnsupportedChoice;
                g.corp_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play)},
    },
    .{
        .title = "Manegarm Skunkworks",
        .side = .corp,
        .code = 30042,
        .card_type = "Upgrade",
        .cost = 2,
        .trash_cost = 3,
        .access = .{ .kind = .tax_or_etr, .click_cost = 2, .credit_cost = 5 },
        .install = .{ .kind = .corp_server_choice },
    },
    .{ .title = "AMAZE Amusements", .side = .corp, .code = 30058, .card_type = "Upgrade", .cost = 1, .trash_cost = 3, .install = .{ .kind = .corp_server_choice }, .tags_on_agenda_steal_from_server = 2 },
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
            .{ .kind = .install_ice_from_hq_archives },
            .{ .kind = .end_the_run },
            .{ .kind = .end_the_run },
        },
        .abilities = &.{bioroidBreakAbility(1, 1)},
    },
    .{ .title = "Palisade", .side = .corp, .code = 30072, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 3, .strength = 2, .remote_strength_bonus = 2, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .end_the_run },
    } },
    .{ .title = "Diviner", .side = .corp, .code = 30046, .card_type = "ICE", .subtypes = &.{ "Code Gate", "AP" }, .cost = 2, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .do_net_damage_conditional_etr, .amount = 1 },
    } },
    .{ .title = "Whitespace", .side = .corp, .code = 30074, .card_type = "ICE", .subtypes = &.{"Code Gate"}, .cost = 2, .strength = 0, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .runner_loses_credits, .amount = 3 },
        .{ .kind = .runner_loses_credits_or_etr, .amount = 6 },
    } },
    .{ .title = "Karunā", .side = .corp, .code = 30047, .card_type = "ICE", .subtypes = &.{ "Sentry", "AP" }, .cost = 4, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .do_net_damage_then_jack_out, .amount = 2 },
        .{ .kind = .do_net_damage, .amount = 2 },
    } },
    .{ .title = "Tithe", .side = .corp, .code = 30073, .card_type = "ICE", .subtypes = &.{ "Sentry", "AP" }, .cost = 1, .strength = 1, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .do_net_damage, .amount = 1 },
        .{ .kind = .corp_gains_credits, .amount = 1 },
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
            .{ .kind = .give_tag_or_pay_credits, .amount = 4 },
        },
        .on_encounter = &struct {
            fn encounter(g: *Game, ice: *const state.CardInstance) anyerror!void {
                const allocator = g.arena.allocator();
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                try choices.append(allocator, stringChoice("Take 1 tag"));
                try choices.append(allocator, stringChoice("End the run"));
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "funhouse-encounter"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = null,
                    .ability_ref = .{ .source_instance_id = ice.instance_id },
                    .on_choice = &on_choice,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                if (std.mem.eql(u8, choice_text, "Take 1 tag")) {
                    g.systemMsg(.runner, 30054, "Runner uses Funhouse to {s}.", .{choice_text});
                    if (try addRunnerTag(g, 1)) return; // Event handler opened prompt
                    g.runner_prompt_state = null;
                    // Continue encounter normally
                    const run = g.run orelse return error.NoRunInProgress;
                    const ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                    const target_server = try findServerByRunPath(g.corp_servers.items, run.server);
                    const server = target_server.slot;
                    const ice_count = server.ices.items.len;
                    const actual_ice_idx = ice_count - 1 - ice_idx;
                    const ice = server.ices.items[actual_ice_idx];
                    g.decision_side = .runner;
                    g.legal_actions = try encounterActionsForState(g.arena.allocator(), g, ice);
                } else if (std.mem.eql(u8, choice_text, "End the run")) {
                    g.runner_prompt_state = null;
                    try completeUnsuccessfulRun(g);
                } else return error.UnsupportedChoice;
            }
        }.encounter,
    },
    .{ .title = "Creative Commission", .side = .runner, .code = 30020, .card_type = "Event", .cost = 1, .abilities = &.{runnerGainCreditsPlayAbility(5, 0, 1)} },
    .{ .title = "Jailbreak", .side = .runner, .code = 30028, .card_type = "Event", .cost = 0, .abilities = &.{runnerRunEventPlayAbility(0, .hq_and_rnd_only, 0, 0, 1, 0, 1)} },
    .{ .title = "Overclock", .side = .runner, .code = 30029, .card_type = "Event", .cost = 1, .abilities = &.{runnerRunEventPlayAbility(0, .any_runnable, 5, 0, 0, 0, 0)} },
    .{ .title = "Sure Gamble", .side = .runner, .code = 30030, .card_type = "Event", .cost = 5, .abilities = &.{runnerGainCreditsPlayAbility(9, 0, 0)} },
    .{ .title = "Tread Lightly", .side = .runner, .code = 30012, .card_type = "Event", .cost = 1, .abilities = &.{runnerRunEventPlayAbility(0, .any_runnable, 0, 3, 0, 0, 0)} },
    .{
        .title = "Mutual Favor",
        .side = .runner,
        .code = 30011,
        .card_type = "Event",
        .cost = 0,
        .runner_play = .{ .kind = .custom },
        .on_play_msg = "search stack for an icebreaker.",
        .on_play = &struct {
            fn play(g: *Game, _: state.CardInstance) anyerror!void {
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
                    g.arena.allocator(),
                    g,
                );
            }
        }.play,
    },
    .{
        .title = "Wildcat Strike",
        .side = .runner,
        .code = 30002,
        .card_type = "Event",
        .cost = 2,
        .runner_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
                const allocator = g.arena.allocator();
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "other"),
                    .choices = try wildcat_strike_choices(allocator),
                    .source_card = card,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &on_choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                if (std.mem.eql(u8, choice_text, "Runner gains 6 [Credits]")) {
                    g.runner_credit += 6;
                } else if (std.mem.eql(u8, choice_text, "Runner draws 4 cards")) {
                    try drawCards(g, .runner, 4);
                } else return error.UnsupportedChoice;
                g.systemMsg(.runner, 30002, "Runner uses Wildcat Strike to {s}.", .{choice_text});
                g.corp_prompt_state = null;
                g.runner_prompt_state = null;
                g.decision_side = .runner;
                g.legal_actions = try runnerOpeningActionsForState(
                    g.arena.allocator(),
                    g,
                );
            }
        }.play,
    },
    .{ .title = "VRcation", .side = .runner, .code = 30021, .card_type = "Event", .cost = 1, .abilities = &.{runnerGainCreditsPlayAbility(0, 4, 1)} },
    .{ .title = "Docklands Pass", .side = .runner, .code = 30013, .card_type = "Hardware", .cost = 2, .runner_install = .{ .kind = .hardware }, .static_abilities = &.{.{ .kind = .hq_access, .value = 1 }} },
    .{ .title = "Pennyshaver", .side = .runner, .code = 30014, .card_type = "Hardware", .cost = 3, .runner_install = .{ .kind = .hardware }, .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const total = @as(u16, card.credit_counter) + 1;
                g.runner_credit += total;
                card.credit_counter = 0;
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                    card.title, total, if (total != 1) @as([]const u8, "s") else "",
                });
            }
        }.use,
        .label_fn = &struct {
            fn label(allocator: std.mem.Allocator, card: state.CardInstance) anyerror![]const u8 {
                return std.fmt.allocPrint(allocator, "Gain {d} [Credits]", .{@as(u16, card.credit_counter) + 1});
            }
        }.label,
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
    .{ .title = "Red Team", .side = .runner, .code = 30018, .card_type = "Resource", .cost = 5, .runner_install = .{ .kind = .resource }, .initial_credit_counters = 12, .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .choices_fn = &struct {
            fn choices(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                const choices_list = try centralNotRunThisTurnChoices(allocator, g.turn_events);
                if (choices_list.len == 0) return error.AbilityNotUsable;
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "run-central"),
                    .choices = choices_list,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &on_choice,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                g.runner_prompt_state = null;
                try applyRunFromAbility(g, choice_text, null);
            }
        }.choices,
        .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                return !g.turn_events.made_run_on_hq or !g.turn_events.made_run_on_rnd or !g.turn_events.made_run_on_archives;
            }
        }.req,
        .label = "Make a run on a central server",
    }} },
    .{ .title = "Smartware Distributor", .side = .runner, .code = 30033, .card_type = "Resource", .cost = 0, .runner_install = .{ .kind = .resource }, .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                card.credit_counter += 3;
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to place 3 [credits] on it.", .{card.title});
            }
        }.use,
        .label = "Place 3 [Credits]",
    }}, .event_abilities = &.{.{
        .event = .runner_turn_begins,
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
        .req = &struct {
            fn req(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                return card.credit_counter > 0;
            }
        }.req,
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const amount = @min(card.credit_counter, 3);
                g.runner_credit += amount;
                card.credit_counter -= amount;
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                    card.title, amount, if (amount != 1) @as([]const u8, "s") else "",
                });
                if (card.credit_counter == 0) {
                    if (findRunnerResourceIndex(g, card.code orelse return error.MissingCardCode)) |idx| {
                        const trashed = g.runner_rig_resources.orderedRemove(idx);
                        try appendDiscardCard(g, .runner, trashed);
                    }
                }
            }
        }.use,
        .label = "Take 3 [Credits]",
    }} },
    .{ .title = "Verbal Plasticity", .side = .runner, .code = 30034, .card_type = "Resource", .cost = 3, .runner_install = .{ .kind = .resource }, .static_abilities = &.{.{ .kind = .click_draw_bonus, .value = 1 }} },
    .{ .title = "Carmen", .side = .runner, .code = 30015, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer" }, .cost = 5, .strength = 2, .runner_install = .{ .kind = .program, .install_cost_reduction_if_successful_run = 2 }, .abilities = &.{ breakAbility(1), pumpAbility(2, 3) } },
    .{ .title = "Cleaver", .side = .runner, .code = 30006, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Fracter" }, .cost = 3, .strength = 3, .runner_install = .{ .kind = .program }, .abilities = &.{ breakAbility(1), pumpAbility(2, 1) } },
    .{ .title = "Mayfly", .side = .runner, .code = 30032, .card_type = "Program", .subtypes = &.{ "Icebreaker", "AI" }, .cost = 1, .strength = 1, .runner_install = .{ .kind = .program, .mu_cost = 2 }, .abilities = &.{ breakAbility(1), pumpAbility(1, 1) }, .event_abilities = &.{.{
        .event = .run_ends,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, self_card: *state.CardInstance) anyerror!void {
                if (!self_card.used_break_this_run) return;
                const g = gameFromEffectContext(ctx);
                var i: usize = 0;
                while (i < g.runner_rig_program.items.len) : (i += 1) {
                    const card = g.runner_rig_program.items[i];
                    if (card.code == null or self_card.code == null) continue;
                    if (card.code.? != self_card.code.?) continue;
                    if (!card.used_break_this_run) continue;
                    const trashed = g.runner_rig_program.orderedRemove(i);
                    try appendDiscardCard(g, .runner, trashed);
                    return;
                }
            }
        }.handle,
    }} },
    .{ .title = "Unity", .side = .runner, .code = 30026, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Decoder" }, .cost = 3, .strength = 1, .runner_install = .{ .kind = .program }, .abilities = &.{ breakAbility(1), .{
        .req = &struct {
            fn req(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                const run = g.run orelse return false;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return false;
                const ice_idx = run.current_ice_index orelse return false;
                const server = findServerByRunPath(g.corp_servers.items, run.server) catch return false;
                const ice_count = server.slot.ices.items.len;
                if (ice_idx >= ice_count) return false;
                const actual_idx = ice_count - 1 - ice_idx;
                const ice = server.slot.ices.items[actual_idx];
                if (!canBreakIceType(card.*, ice)) return false;
                const cost = applyCostModifier(1, sumStaticEffects(g, .runner, .pump_cost, card));
                return g.runner_credit >= cost;
            }
        }.req,
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const run = g.run orelse return error.NoRunInProgress;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;
                const cost = applyCostModifier(1, sumStaticEffects(g, .runner, .pump_cost, card));
                if (g.runner_credit < cost) return error.InsufficientCredits;
                g.runner_credit -= cost;
                const pump_amount: u8 = @intCast(countInstalledIcebreakers(g));
                const current = effectiveStrength(card.*);
                card.current_strength = current + pump_amount;
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to increase strength to {d}.", .{ card.title, card.current_strength orelse 0 });
                const ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
                const server = &g.corp_servers.items[target_server.index];
                const ice_count = server.ices.items.len;
                if (ice_idx >= ice_count) return error.InvalidIceIndex;
                const actual_idx = ice_count - 1 - ice_idx;
                const ice = server.ices.items[actual_idx];
                g.decision_side = .runner;
                g.legal_actions = try encounterActionsForState(g.arena.allocator(), g, ice);
            }
        }.use,
        .label = "Boost strength",
    } } },
    .{ .title = "Conduit", .side = .runner, .code = 30024, .card_type = "Program", .cost = 4, .runner_install = .{ .kind = .program }, .static_abilities = &.{.{
        .kind = .rd_access,
        .value = 1,
        .req = &struct {
            fn req(_: *const state.EffectContext, source: *const state.CardInstance, _: ?*const state.CardInstance) i16 {
                return @intCast(source.virus_counter);
            }
        }.req,
    }}, .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                try applyRunFromAbility(gameFromEffectContext(ctx), "R&D", card.*);
            }
        }.use,
        .label_fn = &struct {
            fn label(allocator: std.mem.Allocator, _: state.CardInstance) anyerror![]const u8 {
                return allocator.dupe(u8, "Run on R&D");
            }
        }.label,
    }}, .event_abilities = &.{.{
        .event = .successful_run_ends,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const run = g.run orelse return;
                if (run.server.len == 0 or !std.mem.eql(u8, run.server[0], "rnd")) return;
                card.virus_counter += 1;
            }
        }.handle,
    }} },
    .{
        .title = "Leech",
        .side = .runner,
        .code = 30008,
        .card_type = "Program",
        .cost = 1,
        .runner_install = .{ .kind = .program },
        .event_abilities = &.{.{
            .event = .successful_run_ends,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const run = g.run orelse return;
                    if (!isCentralRunServer(run.server)) return;
                    card.virus_counter += 1;
                }
            }.handle,
        }},
        .abilities = &.{.{
            .cost = .{ .virus_counters = 1 },
            .req = &struct {
                fn req(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    const run = g.run orelse return false;
                    if (!std.mem.eql(u8, run.phase, "encounter-ice")) return false;
                    return card.virus_counter > 0;
                }
            }.req,
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    var run = &g.run.?;
                    run.ice_strength_modifier -= 1;
                    g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to give -1 strength to encountered ICE.", .{card.title});
                    // Regenerate encounter actions
                    const ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                    const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
                    const server_ice = target_server.server.ices.items;
                    const actual_idx = server_ice.len - 1 - ice_idx;
                    g.decision_side = .runner;
                    g.legal_actions = try encounterActionsForState(g.arena.allocator(), g, server_ice[actual_idx]);
                }
            }.use,
            .label = "Give -1 strength to ICE",
        }},
    },
    // --- System Gateway cards beyond beginner/intermediate ---
    .{ .title = "Buzzsaw", .side = .runner, .code = 30005, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Decoder" }, .cost = 4, .strength = 3, .runner_install = .{ .kind = .program }, .abilities = &.{ breakAbility(1), pumpAbility(3, 1) } },
    .{ .title = "Echelon", .side = .runner, .code = 30025, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer" }, .cost = 3, .strength = 0, .runner_install = .{ .kind = .program }, .static_abilities = &.{.{
        .kind = .self_strength,
        .value = 1,
        .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance, _: ?*const state.CardInstance) i16 {
                return @intCast(countInstalledIcebreakers(gameFromConstEffectContext(ctx)));
            }
        }.req,
    }}, .abilities = &.{ breakAbility(1), pumpAbility(3, 2) } },
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
    }}, .abilities = &.{ breakAbility(2), pumpAbility(1, 1) } },
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
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                try g.pending_effects.insert(g.backing_allocator, 0, .{ .on_score_give_runner_tag = 1 });
            }
        }.score,
        .on_steal_fn = &struct {
            fn steal(g: *Game, _: state.CardInstance) anyerror!void {
                try g.pending_effects.append(g.backing_allocator, .{ .on_steal_give_runner_tag = 1 });
            }
        }.steal,
    },
    .{ .title = "Ping", .side = .corp, .code = 30055, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 2, .strength = 1, .tag_on_rez = 1, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .end_the_run },
    } },
    .{ .title = "Ballista", .side = .corp, .code = 30062, .card_type = "ICE", .subtypes = &.{"Sentry"}, .cost = 5, .strength = 4, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .trash_program_or_etr },
        .{ .kind = .trash_program_or_etr },
    } },
    .{
        .title = "Sprint",
        .side = .corp,
        .code = 30041,
        .card_type = "Operation",
        .cost = 0,
        .abilities = &.{corpCustomPlayAbility(0, 0, null, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                try drawCards(g, .corp, 3);
                g.systemMsg(.corp, 30041, "Corp uses Sprint to draw 3 cards.", .{});
                // Present prompt to choose 2 cards to shuffle back
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                for (g.corp_hand.items, 0..) |c, idx| {
                    try choices.append(allocator, .{ .kind = .card, .text = c.title, .card = .{ .title = c.title, .side = .corp, .index = @intCast(idx) } });
                }
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "sprint-shuffle"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = card.*,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .min_choices = 2,
                    .on_choice = &on_choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // Mark the card as selected (don't move yet -- batch like Clojure)
                // Track selected card titles in pending_sprint_selections
                try g.pending_sprint_selections.append(g.backing_allocator, choice_text);
                // Check if we need to pick one more
                if (g.corp_prompt_state) |*ps| {
                    if (ps.min_choices > 1) {
                        ps.min_choices -= 1;
                        // Rebuild choices excluding already-selected cards
                        const allocator = g.arena.allocator();
                        var choices: std.ArrayList(state.PromptChoice) = .empty;
                        defer choices.deinit(allocator);
                        for (g.corp_hand.items, 0..) |c, idx| {
                            var already_selected = false;
                            for (g.pending_sprint_selections.items) |sel| {
                                if (std.mem.eql(u8, c.title, sel)) {
                                    already_selected = true;
                                    break;
                                }
                            }
                            if (!already_selected) {
                                try choices.append(allocator, .{ .kind = .card, .text = c.title, .card = .{ .title = c.title, .side = .corp, .index = @intCast(idx) } });
                            }
                        }
                        ps.choices = try choices.toOwnedSlice(allocator);
                        g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                        return;
                    }
                }
                // All selected -- now move all selected cards from hand to deck
                for (g.pending_sprint_selections.items) |sel_title| {
                    for (g.corp_hand.items, 0..) |c, idx| {
                        if (std.mem.eql(u8, c.title, sel_title)) {
                            const removed = g.corp_hand.orderedRemove(idx);
                            try g.corp_deck.append(g.backing_allocator, removed);
                            break;
                        }
                    }
                }
                g.pending_sprint_selections.clearRetainingCapacity();
                // Done -- shuffle R&D and return to corp actions
                try shuffleDeck(g, .corp);
                g.corp_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play)},
    },
    .{
        .title = "Hansei Review",
        .side = .corp,
        .code = 30048,
        .card_type = "Operation",
        .cost = 5,
        .abilities = &.{corpCustomPlayAbility(5, 0, null, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                g.corp_credit += 10;
                g.systemMsg(.corp, 30048, "Corp uses Hansei Review to gain 10 [credits].", .{});
                if (g.corp_hand.items.len == 0) {
                    // No cards to trash -- just return
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
                    .prompt_type = try allocator.dupe(u8, "hansei-trash"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = card.*,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &on_choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                for (g.corp_hand.items, 0..) |c, idx| {
                    if (std.mem.eql(u8, c.title, choice_text)) {
                        const removed = g.corp_hand.orderedRemove(idx);
                        try g.corp_discard.append(g.backing_allocator, removed);
                        break;
                    }
                }
                g.corp_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play)},
    },
    .{
        .title = "Above the Law",
        .side = .corp,
        .code = 30060,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 3,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, card: state.CardInstance) anyerror!void {
                if (g.runner_rig_resources.items.len == 0) return;
                const allocator = g.arena.allocator();
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                for (g.runner_rig_resources.items, 0..) |res, idx| {
                    const label = try std.fmt.allocPrint(allocator, "r|{d}", .{idx});
                    try choices.append(allocator, .{ .kind = .string, .text = label, .card = .{ .title = res.title, .side = .runner, .index = @intCast(idx) } });
                }
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "above-the-law-trash"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = null,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &on_choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                var pieces = std.mem.splitScalar(u8, choice_text, '|');
                const zone = pieces.next() orelse return error.UnsupportedChoice;
                if (!std.mem.eql(u8, zone, "r")) return error.UnsupportedChoice;
                const index_text = pieces.next() orelse return error.UnsupportedChoice;
                const index = try std.fmt.parseInt(usize, index_text, 10);
                if (index >= g.runner_rig_resources.items.len) return error.UnsupportedChoice;
                const trashed = g.runner_rig_resources.orderedRemove(index);
                try g.runner_discard.append(g.backing_allocator, trashed);
                g.corp_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.score,
    },
    // --- Phase 1: Pharos, Fermenter, Neurospike, Luminal Transubstantiation, Cookbook ---
    .{ .title = "Pharos", .side = .corp, .code = 30063, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 7, .strength = 5, .advanceable = true, .advancement_strength_threshold = 3, .advancement_strength_bonus = 5, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .give_runner_tags, .amount = 1 },
        .{ .kind = .end_the_run },
        .{ .kind = .end_the_run },
    } },
    .{
        .title = "Fermenter",
        .side = .runner,
        .code = 30007,
        .card_type = "Program",
        .subtypes = &.{"Virus"},
        .cost = 1,
        .runner_install = .{ .kind = .program },
        .on_install = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 1;
            }
        }.handle,
        .abilities = &.{.{
            .cost = .{ .clicks = 1 },
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const gain = @as(u16, card.virus_counter) * 2;
                    g.runner_credit += gain;
                    g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                        card.title, gain, if (gain != 1) @as([]const u8, "s") else "",
                    });
                    // Trash self from program rig
                    for (g.runner_rig_program.items, 0..) |prog, idx| {
                        if (prog.code != null and prog.code.? == (card.code orelse 0)) {
                            const trashed = g.runner_rig_program.orderedRemove(idx);
                            try appendDiscardCard(g, .runner, trashed);
                            if (g.runner_memory) |*mem| {
                                const mu = trashed.runner_install.mu_cost;
                                if (mem.used >= mu) mem.used -= mu else mem.used = 0;
                                mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
                            }
                            break;
                        }
                    }
                }
            }.use,
            .req = &struct {
                fn can(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                    return card.virus_counter > 0;
                }
            }.can,
            .label_fn = &struct {
                fn label(allocator: std.mem.Allocator, card: state.CardInstance) anyerror![]const u8 {
                    const gain = @as(u16, card.virus_counter) * 2;
                    return std.fmt.allocPrint(allocator, "Gain {d} [Credits]", .{gain});
                }
            }.label,
        }},
        .event_abilities = &.{.{
            .event = .runner_turn_begins,
            .handler = &struct {
                fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    card.virus_counter += 1;
                }
            }.handle,
        }},
    },
    .{
        .title = "Neurospike",
        .side = .corp,
        .code = 30049,
        .card_type = "Operation",
        .cost = 3,
        .abilities = &.{corpCustomPlayAbility(3, 0, null, &struct {
            fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const damage = g.turn_events.agenda_points_scored_this_turn;
                if (damage > 0) {
                    try trashRandomRunnerHandCards(g, damage);
                    g.systemMsg(.corp, 30049, "Corp uses Neurospike to do {d} net damage.", .{damage});
                    updateTerminalState(g);
                    if (g.game_over) return;
                }
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play)},
    },
    .{
        .title = "Luminal Transubstantiation",
        .side = .corp,
        .code = 30036,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 3,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                g.corp_click += 3;
                g.cannot_score_agendas_this_turn = true;
                g.systemMsg(.corp, 0, "Corp gains 3 [clicks].", .{});
            }
        }.score,
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
        .advanceable = true,
        .install = .{ .kind = .corp_remote_only },
        .abilities = &.{.{
            .cost = .{ .clicks = 1 },
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const damage = card.advancement_counter;
                    // Trash self from server
                    try trashCorpInstalledSelf(g, card.code orelse 0);
                    // Do meat damage
                    if (damage > 0) {
                        try trashRandomRunnerHandCards(g, damage);
                        updateTerminalState(g);
                    }
                }
            }.use,
            .req = &struct {
                fn can(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                    return card.advancement_counter > 0;
                }
            }.can,
            .label_fn = &struct {
                fn label(allocator: std.mem.Allocator, card: state.CardInstance) anyerror![]const u8 {
                    return std.fmt.allocPrint(allocator, "Trash to do {d} meat damage", .{card.advancement_counter});
                }
            }.label,
        }},
    },
    .{
        .title = "Longevity Serum",
        .side = .corp,
        .code = 30044,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 3,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, scored_card: state.CardInstance) anyerror!void {
                // Present prompt to trash cards from HQ, then shuffle up to 3 from Archives into R&D
                const allocator = g.arena.allocator();
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
                    .prompt_type = try allocator.dupe(u8, "longevity-serum-trash"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = null,
                    .ability_ref = .{ .source_instance_id = scored_card.instance_id },
                    .on_choice = &on_choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                const prompt = g.corp_prompt_state orelse return error.MissingPrompt;
                if (std.mem.eql(u8, prompt.prompt_type, "longevity-serum-trash")) {
                    if (std.mem.eql(u8, choice_text, "Done")) {
                        // Move to shuffle phase: choose up to 3 cards from Archives
                        if (g.corp_discard.items.len == 0) {
                            g.corp_prompt_state = null;
                            g.decision_side = .corp;
                            g.legal_actions = try corpOpeningActionsForState(allocator, g);
                            return;
                        }
                        var choices: std.ArrayList(state.PromptChoice) = .empty;
                        defer choices.deinit(allocator);
                        for (g.corp_discard.items, 0..) |card, idx| {
                            try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                        }
                        try choices.append(allocator, stringChoice("Done"));
                        g.corp_prompt_state = .{
                            .prompt_type = try allocator.dupe(u8, "longevity-serum-shuffle"),
                            .choices = try choices.toOwnedSlice(allocator),
                            .source_card = null,
                            .ability_ref = prompt.ability_ref,
                            .min_choices = 0,
                            .on_choice = &on_choice,
                        };
                        g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                        return;
                    }
                    // Trash chosen card from hand
                    for (g.corp_hand.items, 0..) |card, idx| {
                        if (std.mem.eql(u8, card.title, choice_text)) {
                            const removed = g.corp_hand.orderedRemove(idx);
                            try g.corp_discard.append(g.backing_allocator, removed);
                            break;
                        }
                    }
                    // Rebuild trash choices
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_hand.items, 0..) |card, idx| {
                        try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                    }
                    try choices.append(allocator, stringChoice("Done"));
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "longevity-serum-trash"),
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = null,
                        .ability_ref = prompt.ability_ref,
                        .on_choice = &on_choice,
                    };
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    return;
                }
                if (std.mem.eql(u8, prompt.prompt_type, "longevity-serum-shuffle")) {
                    if (std.mem.eql(u8, choice_text, "Done")) {
                        try shuffleDeck(g, .corp);
                        g.corp_prompt_state = null;
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                        return;
                    }
                    // Move chosen card from Archives to R&D
                    for (g.corp_discard.items, 0..) |card, idx| {
                        if (std.mem.eql(u8, card.title, choice_text)) {
                            const removed = g.corp_discard.orderedRemove(idx);
                            try g.corp_deck.append(g.backing_allocator, removed);
                            break;
                        }
                    }
                    // Check if we've hit 3 shuffles
                    if (prompt.min_choices >= 2) {
                        // Already shuffled 3, done
                        try shuffleDeck(g, .corp);
                        g.corp_prompt_state = null;
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                        return;
                    }
                    if (g.corp_discard.items.len == 0) {
                        try shuffleDeck(g, .corp);
                        g.corp_prompt_state = null;
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                        return;
                    }
                    // Rebuild shuffle choices
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_discard.items, 0..) |card, idx| {
                        try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                    }
                    try choices.append(allocator, stringChoice("Done"));
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "longevity-serum-shuffle"),
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = null,
                        .ability_ref = prompt.ability_ref,
                        .min_choices = prompt.min_choices + 1,
                        .on_choice = &on_choice,
                    };
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    return;
                }
                return error.UnsupportedPrompt;
            }
        }.score,
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
                    var same_server = false;
                    if (g.last_scored_server_index) |scored_server_index| {
                        if (scored_server_index < g.corp_servers.items.len) {
                            const server = g.corp_servers.items[scored_server_index];
                            for (server.content.items) |card| {
                                if (card.code != null and self_card.code != null and card.code.? == self_card.code.?) {
                                    same_server = true;
                                    break;
                                }
                            }
                        }
                    }
                    if (!same_server) return;
                    // Search R&D for a non-agenda card
                    if (g.corp_deck.items.len == 0) return;
                    const allocator = g.arena.allocator();
                    var choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices.deinit(allocator);
                    for (g.corp_deck.items, 0..) |card, idx| {
                        if (card.agenda_points != null) continue; // skip agendas
                        try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                    }
                    if (choices.items.len == 0) return; // no non-agenda cards in R&D
                    try choices.append(allocator, stringChoice("Done"));
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "malapert-search"),
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = null,
                        .ability_ref = .{ .source_instance_id = self_card.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (std.mem.eql(u8, choice_text, "Done")) {
                        // Declined or cancelled — shuffle R&D
                        try shuffleDeck(g, .corp);
                        return;
                    }
                    // Clojure: reveal → shuffle R&D → move card to HQ
                    // Shuffle first (before removing), then find and move
                    try shuffleDeck(g, .corp);
                    const allocator = g.arena.allocator();
                    for (g.corp_deck.items, 0..) |card, idx| {
                        if (std.mem.eql(u8, card.title, choice_text)) {
                            const removed = g.corp_deck.orderedRemove(idx);
                            try g.corp_hand.append(allocator, removed);
                            break;
                        }
                    }
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
        .on_rez_msg = "draw 2 cards.",
        .on_rez = &struct {
            fn rez(g: *Game) anyerror!void {
                try drawCards(g, .corp, 2);
            }
        }.rez,
        .abilities = &.{.{
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Remove from game (not to discard)
                    try removeCorpInstalledFromGame(g, card.code orelse 0);
                    // Shuffle up to 2 cards from Archives into R&D
                    var shuffled: u8 = 0;
                    while (shuffled < 2 and g.corp_discard.items.len > 0) : (shuffled += 1) {
                        const removed = g.corp_discard.orderedRemove(0);
                        try g.corp_deck.append(g.backing_allocator, removed);
                    }
                    if (shuffled > 0) {
                        try shuffleDeck(g, .corp);
                    }
                }
            }.use,
            .label_fn = &struct {
                fn label(allocator: std.mem.Allocator, _: state.CardInstance) anyerror![]const u8 {
                    return allocator.dupe(u8, "Remove from game to shuffle Archives");
                }
            }.label,
        }},
    },
    // --- Phase 3: Consoles ---
    .{ .title = "Carnivore", .side = .runner, .code = 30003, .card_type = "Hardware", .subtypes = &.{"Console"}, .cost = 4, .runner_install = .{ .kind = .hardware }, .static_abilities = &.{.{ .kind = .mu, .value = 1 }}, .trash_access_hand_cost = 2 },
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
                fn trigger(ctx: *state.EffectContext, self_card: *state.CardInstance) anyerror!void {
                    try beginRunnerOptionalInstallConfirmPrompt(gameFromEffectContext(ctx), self_card.instance_id, &pantographOnChoice);
                }
            };
            break :blk &.{
                .{ .event = .agenda_scored, .handler = &H.trigger },
                .{ .event = .agenda_stolen, .handler = &H.trigger },
            };
        },
    },
    // --- Phase 4: Trojans ---
    .{ .title = "Botulus", .side = .runner, .code = 30004, .card_type = "Program", .subtypes = &.{ "Virus", "Trojan" }, .cost = 2, .runner_install = .{ .kind = .program }, .trojan_break_any = true, .on_install = &struct {
        fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
            card.virus_counter += 1;
        }
    }.handle, .abilities = &.{.{
        .cost = .{ .virus_counters = 1 },
        .req = &struct {
            fn req(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                const run = g.run orelse return false;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return false;
                return card.virus_counter > 0;
            }
        }.req,
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const run = g.run orelse return error.NoRunInProgress;
                const ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
                const server = &g.corp_servers.items[target_server.index];
                const ice_count = server.ices.items.len;
                const actual_idx = ice_count - 1 - ice_idx;
                const ice = &server.ices.items[actual_idx];
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to break subroutine on {s}.", .{ card.title, ice.title });
                try openBreakSubPrompt(g, ice, card.*, 0);
            }
        }.use,
        .label = "Break 1 subroutine",
    }}, .event_abilities = &.{.{
        .event = .runner_turn_begins,
        .handler = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 1;
            }
        }.handle,
    }} },
    .{ .title = "Tranquilizer", .side = .runner, .code = 30017, .card_type = "Program", .subtypes = &.{ "Virus", "Trojan" }, .cost = 2, .runner_install = .{ .kind = .program }, .trojan_derez_threshold = 3, .on_install = &struct {
        fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
            card.virus_counter += 1;
        }
    }.handle, .event_abilities = &.{.{
        .event = .runner_turn_begins,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 1;
                const g = gameFromEffectContext(ctx);
                if (card.code) |code| {
                    const card_spec = lookupCardSpecByCode(code) orelse return;
                    if (card.virus_counter < card_spec.trojan_derez_threshold) return;
                } else return;
                for (g.corp_servers.items) |*server| {
                    for (server.ices.items) |*ice| {
                        for (ice.hosted) |hosted| {
                            if (hosted.code != null and card.code != null and hosted.code.? == card.code.?) {
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
            .{ .kind = .trash_program_or_etr }, // trash 1 installed Runner card
            .{ .kind = .corp_install_from_hq_archives }, // install a card from HQ or Archives
            .{ .kind = .prevent_steal_trash }, // prevent stealing/trashing for rest of run
        },
        .abilities = &.{bioroidBreakAbility(1, 1)},
    },
    .{
        .title = "Anoetic Void",
        .side = .corp,
        .code = 30050,
        .card_type = "Upgrade",
        .cost = 0,
        .trash_cost = 1,
        .install = .{ .kind = .corp_server_choice },
        .access = .{ .kind = .corp_pay_etr, .credit_cost = 2 },
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
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, self_card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.run == null) return;
                    if (g.run.?.subroutines_fired == 0) return;
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
        .abilities = &.{.{
            .cost = .{ .clicks = 1 },
            .once_per_turn = true,
            .label = "Install 1 card, paying 2[credit] less. Suffer 1 meat damage.",
            .choices_fn = &struct {
                fn open(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    // Build installable choices from grip
                    const allocator = g.arena.allocator();
                    var choice_list: std.ArrayList(state.PromptChoice) = .empty;
                    defer choice_list.deinit(allocator);
                    for (g.runner_hand.items) |h| {
                        if (h.runner_install.kind == .none) continue;
                        const base_cost: u16 = h.cost orelse 0;
                        const adjusted_cost = if (base_cost >= 2) base_cost - 2 else 0;
                        if (g.runner_credit < adjusted_cost) continue;
                        try choice_list.append(allocator, .{ .kind = .card, .text = h.title, .card = .{
                            .title = h.title,
                            .code = h.code,
                            .side = .runner,
                        } });
                    }
                    if (choice_list.items.len == 0) return;
                    try choice_list.append(allocator, stringChoice("No action"));
                    g.runner_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "topan-install"),
                        .choices = try choice_list.toOwnedSlice(allocator),
                        .source_card = g.runner_identity,
                        .ability_ref = .{ .source_instance_id = g.runner_identity.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (std.mem.eql(u8, choice_text, "No action")) {
                        g.runner_prompt_state = null;
                        const allocator = g.arena.allocator();
                        g.decision_side = .runner;
                        g.legal_actions = try runnerOpeningActionsForState(allocator, g);
                        return;
                    }
                    // Find card in hand and install paying 2cr less
                    for (g.runner_hand.items, 0..) |card, idx| {
                        if (std.mem.eql(u8, card.title, choice_text)) {
                            const base_cost: u16 = card.cost orelse 0;
                            const adjusted_cost = if (base_cost >= 2) base_cost - 2 else 0;
                            g.runner_prompt_state = null;
                            try completeRunnerInstall(g, @intCast(idx), card, adjusted_cost, true);
                            // Suffer 1 meat damage (trash top card of hand)
                            if (g.runner_hand.items.len > 0) {
                                const trashed = g.runner_hand.orderedRemove(0);
                                try appendDiscardCard(g, .runner, trashed);
                            }
                            updateTerminalState(g);
                            if (g.game_over) return;
                            const allocator = g.arena.allocator();
                            g.decision_side = .runner;
                            g.legal_actions = try runnerOpeningActionsForState(allocator, g);
                            return;
                        }
                    }
                }
            }.open,
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
                    const allocator = g.arena.allocator();
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
                        .prompt_type = try allocator.dupe(u8, "barry-install"),
                        .choices = try choices_list.toOwnedSlice(allocator),
                        .source_card = g.runner_identity,
                        .ability_ref = .{ .source_instance_id = g.runner_identity.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "waiting"),
                        .choices = &.{},
                        .source_card = null,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.arena.allocator();
                    if (std.mem.eql(u8, choice_text, "No action")) {
                        g.runner_prompt_state = null;
                        g.corp_prompt_state = null;
                        // Return to approach actions
                        g.decision_side = .corp;
                        g.legal_actions = try continueActionsForRunWithRez(allocator, .corp, g.run, g);
                        return;
                    }
                    // Find and install the chosen card
                    const prompt = g.runner_prompt_state orelse return error.NoPromptState;
                    for (prompt.choices) |ch| {
                        if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                            if (ch.card) |card_ref| {
                                const card_idx = card_ref.index orelse continue;
                                if (card_idx >= g.runner_hand.items.len) continue;
                                const card = g.runner_hand.items[card_idx];
                                const install_cost = card.cost orelse 0;
                                try spendCredits(g, .runner, install_cost);
                                _ = try removeCardFromHand(g, .runner, card_idx);
                                try appendRunnerInstalledCard(g, card);
                                g.systemMsg(.runner, 35012, "Runner uses Barry to install {s}.", .{card.title});
                                break;
                            }
                        }
                    }
                    g.runner_prompt_state = null;
                    g.corp_prompt_state = null;
                    g.decision_side = .corp;
                    g.legal_actions = try continueActionsForRunWithRez(allocator, .corp, g.run, g);
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
                        const allocator = g.arena.allocator();
                        const choices = try allocator.alloc(state.PromptChoice, 2);
                        choices[0] = stringChoice("Yes");
                        choices[1] = stringChoice("No");
                        g.runner_prompt_state = .{
                            .prompt_type = try allocator.dupe(u8, "muslihat-reveal"),
                            .choices = choices,
                            .source_card = g.runner_identity,
                            .ability_ref = .{ .source_instance_id = g.runner_identity.instance_id },
                            .on_choice = &on_choice,
                        };
                        g.decision_side = .runner;
                        g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                    }
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (std.mem.eql(u8, choice_text, "Yes")) {
                        if (g.runner_deck.items.len > 0) {
                            const card = g.runner_deck.pop().?;
                            try g.runner_hand.append(g.backing_allocator, card);
                            g.systemMsg(.runner, 35013, "Runner uses MuslihaT to add {s} to the grip.", .{card.title});
                        }
                    }
                    g.runner_prompt_state = null;
                    g.decision_side = .runner;
                    g.legal_actions = try runnerOpeningActionsForState(g.arena.allocator(), g);
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
        // "When discarding to hand size, may install a discarded program or hardware."
        // Triggers after runner discard phase — needs discard-to-hand-size event
        // Auto-declined in oracle auto-resolve mode (optional install prompt)
    },
    .{
        .title = "LEO Construction: Labor Solutions",
        .side = .corp,
        .code = 35035,
        .card_type = "Identity",
        .subtypes = &.{"Division"},
        // "Once per turn, during a run on a server with bioroid ICE, end the run."
        // This is a corp action during runs — handled via run-time corp ability.
        // Auto-declined in oracle auto-resolve mode (complex conditions).
    },
    .{
        .title = "Po\xc3\xa9tr\xc3\xaf Luxury Brands: All the Rage",
        .side = .corp,
        .code = 35036,
        .card_type = "Identity",
        .subtypes = &.{"Division"},
        // "When you score an agenda, look at top 3 R&D. May install 1 non-agenda non-operation."
        // "When an agenda is stolen, may install 1 non-agenda non-operation from HQ."
        .event_abilities = blk: {
            const H = struct {
                fn trigger(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.arena.allocator();
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
                        .prompt_type = try allocator.dupe(u8, "poetri-install"),
                        .choices = try choices_list.toOwnedSlice(allocator),
                        .source_card = g.corp_identity,
                        .ability_ref = .{ .source_instance_id = g.corp_identity.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.arena.allocator();
                    if (std.mem.eql(u8, choice_text, "No action")) {
                        g.corp_prompt_state = null;
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                        return;
                    }
                    // Find card in hand and install
                    const prompt = g.corp_prompt_state orelse return error.NoPromptState;
                    for (prompt.choices) |ch| {
                        if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                            if (ch.card) |card_ref| {
                                const card_idx = card_ref.index orelse continue;
                                try installCorpCardFromHand(g, card_idx, "New remote");
                                g.systemMsg(.corp, 35036, "Corp uses Po\xc3\xa9tr\xc3\xaf to install a card.", .{});
                                break;
                            }
                        }
                    }
                    g.corp_prompt_state = null;
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                }
            };
            break :blk &.{
                .{ .event = .agenda_scored, .handler = &H.trigger },
                .{ .event = .agenda_stolen, .handler = &H.trigger },
            };
        },
    },
    .{
        .title = "AU Co.: The Gold Standard in Clones",
        .side = .corp,
        .code = 35046,
        .card_type = "Identity",
        .subtypes = &.{"Division"},
        // Place 1 power counter on damage/corp-trash events (auto via event handlers)
        // Start of turn: optional spend 2 power counters to peek top 3 R&D, trash 1, draw rest
        .event_abilities = &.{.{
            .event = .agenda_scored,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, self_card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    self_card.power_counter += 1;
                    g.systemMsg(.corp, 35046, "Corp places 1 power counter on AU Co.", .{});
                }
            }.handle,
        }},
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
                    const allocator = g.arena.allocator();
                    const adv_choices = try installedCardChoices(allocator, g.corp_servers.items);
                    if (adv_choices.len == 0) return;
                    // Add "No action" option
                    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                    defer choices_list.deinit(allocator);
                    for (adv_choices) |ch| try choices_list.append(allocator, ch);
                    try choices_list.append(allocator, stringChoice("No action"));
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "pt-untaian-advance"),
                        .choices = try choices_list.toOwnedSlice(allocator),
                        .source_card = g.corp_identity,
                        .ability_ref = .{ .source_instance_id = g.corp_identity.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (std.mem.eql(u8, choice_text, "No action")) {
                        g.corp_prompt_state = null;
                        return;
                    }
                    // Pay 1 credit and place advancement counter
                    try spendCredits(g, .corp, 1);
                    _ = try addAdvancementCounter(g, choice_text, 1);
                    g.systemMsg(.corp, 35047, "Corp uses PT Untaian to place 1 advancement counter.", .{});
                    g.corp_prompt_state = null;
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
                        if (!card.flipped or run.server.len == 0) return;
                        if (std.mem.eql(u8, run.server[0], "hq") or std.mem.eql(u8, run.server[0], "rnd")) {
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
                        if (card.flipped and g.turn_events.operation_played_count == 1) {
                            g.corp_click += 1;
                        }
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
                    if (card.ability_used_this_turn) return;
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.arena.allocator();
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
                    card.ability_used_this_turn = true;
                    try choices.append(allocator, stringChoice("No action"));
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "corp-free-install-card"),
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = card.*,
                        .ability_ref = .{ .source_instance_id = card.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.arena.allocator();
                    const prompt = g.corp_prompt_state orelse return error.NoPromptState;
                    if (std.mem.eql(u8, prompt.prompt_type, "corp-free-install-card")) {
                        if (std.mem.eql(u8, choice_text, "No action")) {
                            g.corp_prompt_state = null;
                            try restorePriorityAfterPrompt(g);
                            return;
                        }
                        for (prompt.choices) |card_choice| {
                            if (card_choice.text == null or !std.mem.eql(u8, card_choice.text.?, choice_text)) continue;
                            const card_ref = card_choice.card orelse continue;
                            const card_idx = card_ref.index orelse continue;
                            if (card_idx >= g.corp_hand.items.len) return error.InvalidCardIndex;
                            const install_kind = g.corp_hand.items[card_idx].install.kind;
                            const server_choices = try installChoicesForCard(allocator, install_kind, g);
                            g.corp_prompt_state = .{
                                .prompt_type = try allocator.dupe(u8, "corp-free-install-server"),
                                .choices = server_choices,
                                .ability_ref = prompt.ability_ref,
                                .min_choices = card_idx,
                                .on_choice = &on_choice,
                            };
                            g.decision_side = .corp;
                            g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                            return;
                        }
                        return error.UnsupportedChoice;
                    }
                    if (std.mem.eql(u8, prompt.prompt_type, "corp-free-install-server")) {
                        const card_idx = prompt.min_choices;
                        if (card_idx >= g.corp_hand.items.len) return error.InvalidCardIndex;
                        const card_title = g.corp_hand.items[card_idx].title;
                        try installCorpCardFromHand(g, card_idx, choice_text);
                        g.systemMsg(.corp, 35058, "Corp uses Synapse Global to reveal and install {s}.", .{card_title});
                        g.corp_prompt_state = null;
                        try restorePriorityAfterPrompt(g);
                        return;
                    }
                    return error.UnsupportedChoice;
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
        .installs_agendas_faceup = true,
        // "Install agendas faceup. On access of faceup agenda: 2 meat damage + 1 tag."
        .event_abilities = &.{.{
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
        }},
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
                    const allocator = g.arena.allocator();
                    const choices = try allocator.alloc(state.PromptChoice, 2);
                    choices[0] = stringChoice("Yes");
                    choices[1] = stringChoice("No");
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "zwicky-draw"),
                        .choices = choices,
                        .source_card = g.corp_identity,
                        .ability_ref = .{ .source_instance_id = g.corp_identity.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.runner_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "waiting"),
                        .choices = &.{},
                        .source_card = null,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (std.mem.eql(u8, choice_text, "Yes")) {
                        try drawCards(g, .corp, 1);
                        g.systemMsg(.corp, 35069, "Corp uses The Zwicky Group to draw 1 card.", .{});
                    }
                    g.corp_prompt_state = null;
                    g.runner_prompt_state = null;
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
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
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        // "First time Runner trashes installed Corp card each turn, they may spend [click]. If not, Corp gets +1 allotted [click] next turn."
        // Complex trigger - requires event system enhancement
    },
    .{
        .title = "Project Ingatan",
        .side = .corp,
        .code = 35038,
        .card_type = "Agenda",
        .subtypes = &.{"Research"},
        .agenda_points = 2,
        .advancement_requirement = 3,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, card: state.CardInstance) anyerror!void {
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
        }.score,
    },
    .{
        .title = "Proprionegation",
        .side = .corp,
        .code = 35048,
        .card_type = "Agenda",
        .subtypes = &.{"Security"},
        .agenda_points = 2,
        .advancement_requirement = 4,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                // "When you score this agenda, place 1 agenda counter on it."
                if (g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = 1;
                }
            }
        }.score,
    },
    .{
        .title = "Sericulture Expansion",
        .side = .corp,
        .code = 35049,
        .card_type = "Agenda",
        .subtypes = &.{"Expansion"},
        .agenda_points = 2,
        .advancement_requirement = 3,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, card: state.CardInstance) anyerror!void {
                // Dividends 1: place 1 agenda counter per excess advancement
                const req = card.advancement_requirement orelse 3;
                const excess = if (card.advancement_counter > req) card.advancement_counter - req else 0;
                if (excess > 0 and g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = excess;
                }
            }
        }.score,
    },
    .{
        .title = "Embedded Reporting",
        .side = .corp,
        .code = 35059,
        .card_type = "Agenda",
        .subtypes = &.{"Initiative"},
        .agenda_points = 2,
        .advancement_requirement = 3,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, card: state.CardInstance) anyerror!void {
                // Dividends 2: place 2 agenda counters per excess advancement
                const req = card.advancement_requirement orelse 3;
                const excess = if (card.advancement_counter > req) card.advancement_counter - req else 0;
                if (excess > 0 and g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = excess * 2;
                }
            }
        }.score,
    },
    .{
        .title = "Next Big Thing",
        .side = .corp,
        .code = 35060,
        .card_type = "Agenda",
        .subtypes = &.{"Initiative"},
        .agenda_points = 3,
        .advancement_requirement = 5,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                // "When scored or stolen, place 1 agenda counter on it."
                if (g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = 1;
                }
            }
        }.score,
    },
    .{
        .title = "Greenmail",
        .side = .corp,
        .code = 35070,
        .card_type = "Agenda",
        .subtypes = &.{"Expansion"},
        .agenda_points = 1,
        .advancement_requirement = 2,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                g.corp_credit += 2;
                g.systemMsg(.corp, 0, "Corp gains 2 [credits].", .{});
            }
        }.score,
    },
    .{
        .title = "Off the Books",
        .side = .corp,
        .code = 35071,
        .card_type = "Agenda",
        .subtypes = &.{"Initiative"},
        .agenda_points = 2,
        .advancement_requirement = 3,
        .access = .{ .kind = .steal_agenda },
        .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, card: state.CardInstance) anyerror!void {
                // Dividends 1: place 1 agenda counter per excess advancement
                const req = card.advancement_requirement orelse 3;
                const excess = if (card.advancement_counter > req) card.advancement_counter - req else 0;
                if (excess > 0 and g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = excess;
                }
            }
        }.score,
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
            .{ .kind = .trash_program_or_etr },
            .{ .kind = .do_brain_damage, .amount = 1 },
        },
        .abilities = &.{bioroidBreakAbility(1, 1)},
        // "When you rez this ice during a run against this server, you may trash 1 installed trojan program."
        .on_rez = &struct {
            fn rez(g: *Game) anyerror!void {
                if (g.run == null) return;
                // Find any installed trojan programs on any ICE
                var has_trojan = false;
                for (g.corp_servers.items) |server| {
                    for (server.ices.items) |ice| {
                        if (ice.hosted.len > 0) {
                            for (ice.hosted) |hosted| {
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
                        if (ice.hosted.len > 0) {
                            const allocator = g.arena.allocator();
                            var new_hosted: std.ArrayList(state.CardInstance) = .empty;
                            var trashed_title: ?[]const u8 = null;
                            for (ice.hosted) |hosted| {
                                if (hasSubtype(hosted, "Trojan") and trashed_title == null) {
                                    trashed_title = hosted.title;
                                    try appendDiscardCard(g, .runner, hosted);
                                } else {
                                    try new_hosted.append(allocator, hosted);
                                }
                            }
                            if (trashed_title) |title| {
                                ice.hosted = try new_hosted.toOwnedSlice(allocator);
                                g.systemMsg(.corp, 35041, "Corp uses Bumi 1.0 to trash {s}.", .{title});
                                return;
                            }
                        }
                    }
                }
            }
        }.rez,
    },
    .{ .title = "Scatter Field", .side = .corp, .code = 35042, .card_type = "ICE", .subtypes = &.{"Code Gate"}, .cost = 3, .strength = 0, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .corp_install_from_hq_archives },
        .{ .kind = .end_the_run },
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
            .{ .kind = .corp_gains_credits, .amount = 0 }, // Simplified: draw handled by card_subroutine_handler
            .{ .kind = .do_net_damage, .amount = 1 },
            .{ .kind = .do_net_damage, .amount = 2 },
        },
        .card_subroutine_handler = &struct {
            fn handle(g: *Game, _: *const state.CardInstance, sub_idx: u8) anyerror!void {
                if (sub_idx == 0) {
                    // Sub 1: Corp draws 1 card
                    try drawCards(g, .corp, 1);
                    g.systemMsg(.corp, 35052, "Corp uses Empiricist to draw 1 card.", .{});
                    // Optional: add 1 from HQ to top of R&D (auto-declined)
                }
            }
        }.handle,
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
            .{ .kind = .corp_install_from_hq_archives },
            .{ .kind = .none }, // rez ice -2 (needs rez prompt with discount)
            .{ .kind = .none }, // resolve sentry sub (needs cross-ICE resolution)
            .{ .kind = .none }, // resolve code gate sub (needs cross-ICE resolution)
        },
    },
    .{ .title = "Semak-samun", .side = .corp, .code = 35054, .card_type = "ICE", .subtypes = &.{ "AP", "Barrier" }, .cost = 3, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .net_damage_unless_etr, .amount = 3 },
    } },
    .{ .title = "Doomscroll", .side = .corp, .code = 35063, .card_type = "ICE", .subtypes = &.{ "AP", "Observer", "Sentry" }, .cost = 3, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .tag_runner },
        .{ .kind = .do_net_damage, .amount = 1 },
        .{ .kind = .conditional_net_damage_if_tagged, .amount = 2 },
    } },
    .{ .title = "N-Pot", .side = .corp, .code = 35064, .card_type = "ICE", .subtypes = &.{"Code Gate"}, .cost = 4, .strength = 4, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .end_the_run },
        .{ .kind = .conditional_etr_threat, .amount = 2 },
        .{ .kind = .conditional_etr_threat, .amount = 4 },
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
            .{ .kind = .trash_program_or_resource_or_etr, .amount = 0 }, // trash 1 program or ETR
            .{ .kind = .trash_program_or_resource_or_etr, .amount = 1 }, // trash 1 resource or ETR
            .{ .kind = .end_the_run },
        },
    },
    .{ .title = "Kessleroid", .side = .corp, .code = 35075, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 2, .strength = 1, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .end_the_run },
        .{ .kind = .end_the_run },
    } },
    .{ .title = "Syailendra", .side = .corp, .code = 35076, .card_type = "ICE", .subtypes = &.{ "AP", "Code Gate" }, .cost = 4, .strength = 5, .advanceable = true, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .place_advancement_counter, .amount = 1 },
        .{ .kind = .runner_loses_credits, .amount = 2 },
        .{ .kind = .do_net_damage, .amount = 1 },
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
            .{ .kind = .end_the_run },
        },
        .on_rez = &struct {
            fn rez(g: *Game) anyerror!void {
                // "When you rez this ice during a run against this server, purge virus counters."
                purgeVirusCounters(g);
                g.systemMsg(.corp, 35079, "Corp uses Flyswatter to purge virus counters.", .{});
            }
        }.rez,
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
        .subroutines = &.{
            .{ .kind = .tag_or_pay_credits_etr, .amount = 3 },
            .{ .kind = .none }, // ETR if tagged (custom)
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
        // "3 clicks + trash: Gain 9 credits." (corp click ability)
        .abilities = &.{.{
            .cost = .{ .clicks = 3 },
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    g.corp_credit += 9;
                    g.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to gain 9 [credits].", .{card.title});
                    // Trash self from server
                    try trashCorpInstalledSelf(g, card.code orelse 0);
                }
            }.use,
            .label_fn = &struct {
                fn label(allocator: std.mem.Allocator, _: state.CardInstance) anyerror![]const u8 {
                    return allocator.dupe(u8, "Gain 9 [Credits]");
                }
            }.label,
        }},
    },
    .{ .title = "Otto Campaign", .side = .corp, .code = 35040, .card_type = "Asset", .subtypes = &.{"Advertisement"}, .cost = 2, .trash_cost = 2, .install = .{ .kind = .corp_remote_only }, .initial_credit_counters = 6, .installed_ability = .{
        .kind = .start_of_turn_credits,
        .take_credits_amount = 2,
        .trash_on_empty = true,
        .on_empty = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                gameFromEffectContext(ctx).corp_click += 2;
            }
        }.handle,
    } },
    .{ .title = "Byte!", .side = .corp, .code = 35050, .card_type = "Asset", .subtypes = &.{"Ambush"}, .cost = 0, .trash_cost = 0, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Ph\xe1\xba\xadt Gioan Baotixita", .side = .corp, .code = 35051, .card_type = "Asset", .subtypes = &.{"Executive"}, .cost = 1, .trash_cost = 3, .install = .{ .kind = .corp_remote_only } },
    .{
        .title = "Idiosyncresis",
        .side = .corp,
        .code = 35061,
        .card_type = "Asset",
        .subtypes = &.{"Hostile"},
        .cost = 1,
        .trash_cost = 2,
        .advanceable = true,
        .install = .{ .kind = .corp_remote_only },
        // "When your turn begins, you may trash this asset. If you do, for each hosted advancement counter, gain 3cr and the Runner loses 2cr."
        // This is a start-of-turn optional effect - implemented as auto-trigger when advancement counters > 0
    },
    .{
        .title = "Public Access Plaza",
        .side = .corp,
        .code = 35062,
        .card_type = "Asset",
        .cost = 1,
        .trash_cost = 2,
        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{
            .event = .corp_turn_begins,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    g.corp_credit += 1;
                    g.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to gain 1 [credit].", .{card.title});
                }
            }.handle,
        }},
    },
    .{ .title = "Anthill Excavation Contract", .side = .corp, .code = 35072, .card_type = "Asset", .subtypes = &.{"Industrial"}, .cost = 3, .trash_cost = 1, .install = .{ .kind = .corp_remote_only }, .initial_credit_counters = 8, .installed_ability = .{
        .kind = .start_of_turn_credits,
        .take_credits_amount = 4,
        .trash_on_empty = true,
        .on_take = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                try drawCards(gameFromEffectContext(ctx), .corp, 1);
            }
        }.handle,
    } },
    .{ .title = "Plutus", .side = .corp, .code = 35073, .card_type = "Asset", .subtypes = &.{"Deep Net"}, .cost = 0, .trash_cost = 3, .install = .{ .kind = .corp_remote_only } },
    // --- Elevation Upgrades ---
    .{ .title = "Mercia B4LL4RD", .side = .corp, .code = 35045, .card_type = "Upgrade", .subtypes = &.{ "Academic", "Bioroid" }, .cost = 2, .trash_cost = 2, .install = .{ .kind = .corp_server_choice } },
    .{ .title = "Mitra Aman", .side = .corp, .code = 35056, .card_type = "Upgrade", .subtypes = &.{"Clone"}, .cost = 0, .trash_cost = 3, .install = .{ .kind = .corp_server_choice } },
    .{
        .title = "Mahkota Langit Grid",
        .side = .corp,
        .code = 35082,
        .card_type = "Upgrade",
        .subtypes = &.{"Region"},
        .cost = 2,
        .trash_cost = 2,
        .install = .{ .kind = .corp_server_choice },
        // "2 recurring credits for rez costs. Persistent: trash cost of assets in root +2."
        // Recurring credits handled via initial counters. Trash cost increase is static.
        .initial_credit_counters = 2,
    },
    // --- Elevation Operations ---
    .{
        .title = "Nanomanagement",
        .side = .corp,
        .code = 35043,
        .card_type = "Operation",
        .cost = 4,
        .abilities = &.{corpCustomPlayAbility(4, 0, null, &struct {
            fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                g.corp_click += 2;
                g.systemMsg(.corp, 35043, "Corp uses Nanomanagement to gain [Click][Click].", .{});
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play)},
    },
    .{
        .title = "Top-Down Solutions",
        .side = .corp,
        .code = 35044,
        .card_type = "Operation",
        .cost = 2,
        .abilities = &.{corpCustomPlayAbility(2, 0, null, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // "Draw 2 cards. Install up to 2 cards from HQ (one at a time)."
                try drawCards(g, .corp, 2);
                g.systemMsg(.corp, 35044, "Corp uses Top-Down Solutions to draw 2 cards.", .{});
                // Offer install prompt
                try showTopDownInstallChoices(g, card.instance_id, 0);
            }
        }.play)},
    },
    .{
        .title = "Peer Review",
        .side = .corp,
        .code = 35055,
        .card_type = "Operation",
        .subtypes = &.{"Transaction"},
        .cost = 4,
        .abilities = &.{corpCustomPlayAbility(4, 0, null, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
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
                        .prompt_type = try allocator.dupe(u8, "peer-review-private"),
                        .choices = try private_choices.toOwnedSlice(allocator),
                        .ability_ref = .{ .source_instance_id = card.instance_id },
                        .on_choice = &peerReviewOnChoice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    return;
                }
                try beginPeerReviewInstallPrompt(g, card.instance_id);
            }
        }.play)},
    },
    .{
        .title = "Bigger Picture",
        .side = .corp,
        .code = 35065,
        .card_type = "Operation",
        .subtypes = &.{"Gray Ops"},
        .cost = 0,
        .abilities = &.{corpCustomPlayAbility(0, 0, &struct {
            fn check(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                // "Play only if the Runner is tagged."
                return if (g.runner_tag) |t| t.is_tagged else false;
            }
        }.check, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // "Choose: Give the Runner 1 tag OR Remove any number of tags. Runner loses 5cr per tag. Gain credits equal to credits lost."
                const allocator = g.arena.allocator();
                var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                defer choices_list.deinit(allocator);
                try choices_list.append(allocator, stringChoice("Give the Runner 1 tag"));
                try choices_list.append(allocator, stringChoice("Remove tags and drain credits"));
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "bigger-picture"),
                    .choices = try choices_list.toOwnedSlice(allocator),
                    .source_card = card.*,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &on_choice,
                };
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                if (std.mem.eql(u8, choice_text, "Give the Runner 1 tag")) {
                    _ = try addRunnerTag(g, 1);
                    g.systemMsg(.corp, 35065, "Corp uses Bigger Picture to give the Runner 1 tag.", .{});
                    g.corp_prompt_state = null;
                    g.runner_prompt_state = null;
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                } else if (std.mem.eql(u8, choice_text, "Remove tags and drain credits")) {
                    // Prompt: how many tags to remove?
                    const tag_count = if (g.runner_tag) |t| t.base else 0;
                    var num_choices: std.ArrayList(state.PromptChoice) = .empty;
                    defer num_choices.deinit(allocator);
                    var i: u8 = 0;
                    while (i <= tag_count) : (i += 1) {
                        const text = try std.fmt.allocPrint(allocator, "{d}", .{i});
                        try num_choices.append(allocator, .{ .kind = .number, .text = text, .number = i });
                    }
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "bigger-picture-tags"),
                        .choices = try num_choices.toOwnedSlice(allocator),
                        .source_card = g.corp_prompt_state.?.source_card,
                        .ability_ref = g.corp_prompt_state.?.ability_ref,
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                } else {
                    // Handle number choice for tag removal
                    const num_tags = std.fmt.parseInt(u8, choice_text, 10) catch return error.UnsupportedChoice;
                    if (num_tags > 0) {
                        try removeRunnerTags(g, num_tags);
                    }
                    const drain = @as(u16, num_tags) * 5;
                    const actual_drain = @min(drain, g.runner_credit);
                    g.runner_credit -= actual_drain;
                    g.corp_credit += actual_drain;
                    g.systemMsg(.corp, 35065, "Corp uses Bigger Picture to remove {d} tags; Runner loses {d} [credits], Corp gains {d} [credits].", .{ num_tags, actual_drain, actual_drain });
                    g.corp_prompt_state = null;
                    g.runner_prompt_state = null;
                    if (try resumePendingEffects(g)) return;
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                }
            }
        }.play)},
    },
    .{
        .title = "IP Enforcement",
        .side = .corp,
        .code = 35066,
        .card_type = "Operation",
        .subtypes = &.{"Gray Ops"},
        .cost = 0,
        .abilities = &.{corpCustomPlayAbility(0, 0, &struct {
            fn check(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                // Requires runner to be tagged and have stolen agendas
                const tagged = if (g.runner_tag) |t| t.is_tagged else false;
                return tagged and g.runner_scored.items.len > 0;
            }
        }.check, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // "As additional cost, remove X tags. Install 1 agenda from Runner's score area with X printed AP."
                const allocator = g.arena.allocator();
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
                        .prompt_type = try allocator.dupe(u8, "ip-enforcement-tags"),
                        .choices = try num_choices.toOwnedSlice(allocator),
                        .source_card = card.*,
                        .ability_ref = .{ .source_instance_id = card.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                const num_tags = std.fmt.parseInt(u8, choice_text, 10) catch return error.UnsupportedChoice;
                // Remove tags and credits as additional cost
                try removeRunnerTags(g, num_tags);
                try spendCredits(g, .corp, num_tags);
                // Find and move matching agenda from runner score area to corp install
                for (g.runner_scored.items, 0..) |a, idx| {
                    if (a.agenda_points != null and a.agenda_points.? == num_tags) {
                        var agenda = g.runner_scored.orderedRemove(idx);
                        // Recalculate runner agenda points
                        g.runner_agenda_point = 0;
                        for (g.runner_scored.items) |sa| {
                            if (sa.agenda_points) |ap| g.runner_agenda_point += ap;
                        }
                        // Place advancement counter if still tagged
                        if (is_runner_tagged(g.runner_tag)) {
                            agenda.advancement_counter = 1;
                        }
                        // Install in new remote
                        try installCard(g, agenda, "New remote");
                        g.systemMsg(.corp, 35066, "Corp uses IP Enforcement to install {s} from Runner's score area.", .{agenda.title});
                        break;
                    }
                }
                g.corp_prompt_state = null;
                if (try resumePendingEffects(g)) return;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(allocator, g);
            }
        }.play)},
    },
    .{
        .title = "Touch-ups",
        .side = .corp,
        .code = 35067,
        .card_type = "Operation",
        .subtypes = &.{"Double"},
        .cost = 2,
        .abilities = &.{corpCustomPlayAbility(2, 1, null, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // "Place 2 advancement counters on 1 installed card you can advance."
                const allocator = g.arena.allocator();
                const adv_choices = try installedCardChoices(allocator, g.corp_servers.items);
                if (adv_choices.len > 0) {
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "touch-ups-advance"),
                        .choices = adv_choices,
                        .source_card = card.*,
                        .ability_ref = .{ .source_instance_id = card.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                const prompt = g.corp_prompt_state orelse return error.NoPromptState;
                if (std.mem.eql(u8, prompt.prompt_type, "touch-ups-advance")) {
                    _ = try addAdvancementCounter(g, choice_text, 2);
                    g.systemMsg(.corp, 35067, "Corp uses Touch-ups to place 2 advancement counters.", .{});
                    // Simplified: skip the reveal grip + shuffle part for now
                    // (complex interaction requiring runner hand reveal)
                    g.corp_prompt_state = null;
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                } else return error.UnsupportedChoice;
            }
        }.play)},
    },
    .{
        .title = "Key Performance Indicators",
        .side = .corp,
        .code = 35077,
        .card_type = "Operation",
        .subtypes = &.{"Transaction"},
        .cost = 1,
        .abilities = &.{corpCustomPlayAbility(1, 0, null, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // "Resolve 2 of: Gain 2cr, Install ice ignoring costs, Place 1 advancement, Draw 1 + shuffle 1"
                try showKpiChoices(g, card.instance_id, 0);
            }
        }.play)},
    },
    .{
        .title = "Measured Response",
        .side = .corp,
        .code = 35078,
        .card_type = "Operation",
        .subtypes = &.{"Black Ops"},
        .cost = 5,
        .trash_cost = 3,
        .abilities = &.{corpCustomPlayAbility(5, 0, &struct {
            fn check(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                // "Play only if the threat level is 4 or greater, and only if the Runner made a successful run during their last turn."
                return threatLevel(g) >= 4 and runner_had_successful_run_last_turn(g);
            }
        }.check, &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // "Do 4 meat damage unless the Runner pays 8[credit]."
                const allocator = g.arena.allocator();
                var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                defer choices_list.deinit(allocator);
                if (g.runner_credit >= 8) {
                    try choices_list.append(allocator, stringChoice("Pay 8 [Credits]"));
                }
                try choices_list.append(allocator, stringChoice("Suffer 4 meat damage"));
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "other"),
                    .choices = try choices_list.toOwnedSlice(allocator),
                    .source_card = card.*,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &on_choice,
                };
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                if (std.mem.eql(u8, choice_text, "Pay 8 [Credits]")) {
                    try spendCredits(g, .runner, 8);
                    g.systemMsg(.runner, 35078, "Runner pays 8 [credits] to prevent meat damage.", .{});
                } else if (std.mem.eql(u8, choice_text, "Suffer 4 meat damage")) {
                    try trashRandomRunnerHandCards(g, 4);
                    g.systemMsg(.corp, 35078, "Corp uses Measured Response to do 4 meat damage.", .{});
                    updateTerminalState(g);
                } else return error.UnsupportedChoice;
                g.runner_prompt_state = null;
                g.corp_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play)},
    },
    .{
        .title = "Petty Cash",
        .side = .corp,
        .code = 35081,
        .card_type = "Operation",
        .subtypes = &.{"Transaction"},
        .cost = 3,
        .abilities = &.{.{
            .cost = .{ .clicks = 1, .credits = 3 },
            .req = &struct {
                fn check(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    // "Play only if you have not finished an action yet this turn."
                    return g.corp_click == g.corp_click_per_turn;
                }
            }.check,
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const side = card.side;
                    const played = try removeCardFromHandByInstanceId(g, side, card.instance_id);
                    try appendDiscardCard(g, side, played);
                    g.corp_credit += 5;
                    g.turn_events.operation_played_count += 1;
                    _ = try fireEvent(g, .operation_played);
                    g.systemMsg(side, card.code orelse 0, "Corp spends [click] and pays 3 [credits] to play {s}.", .{card.title});
                    if (!hasActivePrompt(g)) {
                        g.decision_side = side;
                        g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
                    }
                }
            }.use,
            .label = "Play",
        }},
        .flashback_click_cost = 1,
        .flashback_gain_clicks = 1,
    },
    // --- Elevation Runner Events ---
    .{
        .title = "Charm Offensive",
        .side = .runner,
        .code = 35003,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 0,
        .runner_play = .{ .kind = .choose_run_target, .run_target_kind = .archives_only },
    },
    .{
        .title = "Scrounge",
        .side = .runner,
        .code = 35004,
        .card_type = "Event",
        .subtypes = &.{"Double"},
        .cost = 1,
        .runner_play = .{ .kind = .custom, .lose_clicks = 1 },
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
                // Additional cost: spend [click] (Double)
                try spendClicks(g, .runner, 1);
                // "Install 1 program from your heap."
                const allocator = g.arena.allocator();
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
                        .prompt_type = try allocator.dupe(u8, "scrounge-install"),
                        .choices = try choices_list.toOwnedSlice(allocator),
                        .ability_ref = .{ .source_instance_id = card.instance_id },
                        .on_choice = &scroungeOnChoice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                } else {
                    try g.pending_effects.append(g.backing_allocator, .{ .runner_discard_to_deck_prompt = card.instance_id });
                    if (try resumePendingEffects(g)) return;
                    g.decision_side = .runner;
                    g.legal_actions = try runnerOpeningActionsForState(allocator, g);
                }
            }
        }.play,
    },
    .{
        .title = "Shred",
        .side = .runner,
        .code = 35005,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 1,
        .runner_play = .{ .kind = .choose_run_target },
    },
    .{ .title = "Clean Getaway", .side = .runner, .code = 35014, .card_type = "Event", .subtypes = &.{"Run"}, .cost = 3, .runner_play = .{ .kind = .choose_run_target, .gain_credits = 6, .successful_run_draw_cards = 0 } },
    .{
        .title = "Lie Low",
        .side = .runner,
        .code = 35015,
        .card_type = "Event",
        .subtypes = &.{"Double"},
        .cost = 1,
        .runner_play = .{ .kind = .custom, .lose_clicks = 1 },
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
                // Additional cost: spend [click] (Double)
                try spendClicks(g, .runner, 1);
                // "Draw 4 cards OR Remove up to 2 tags"
                const allocator = g.arena.allocator();
                var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                defer choices_list.deinit(allocator);
                try choices_list.append(allocator, stringChoice("Draw 4 cards"));
                if (is_runner_tagged(g.runner_tag)) {
                    try choices_list.append(allocator, stringChoice("Remove up to 2 tags"));
                }
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "lie-low"),
                    .choices = try choices_list.toOwnedSlice(allocator),
                    .source_card = null,
                    .ability_ref = .{ .source_instance_id = card.instance_id },
                    .on_choice = &on_choice,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
            fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                const prompt = g.runner_prompt_state orelse return error.NoPromptState;
                if (std.mem.eql(u8, prompt.prompt_type, "lie-low")) {
                    if (std.mem.eql(u8, choice_text, "Draw 4 cards")) {
                        try drawCards(g, .runner, 4);
                        g.systemMsg(.runner, 35015, "Runner uses Lie Low to draw 4 cards.", .{});
                        g.runner_prompt_state = null;
                        g.decision_side = .runner;
                        g.legal_actions = try runnerOpeningActionsForState(allocator, g);
                    } else if (std.mem.eql(u8, choice_text, "Remove up to 2 tags")) {
                        // Show tag count choices
                        const tag_count = if (g.runner_tag) |t| t.total else 0;
                        const max_remove: u8 = @min(2, tag_count);
                        var num_choices: std.ArrayList(state.PromptChoice) = .empty;
                        defer num_choices.deinit(allocator);
                        var i: u8 = 0;
                        while (i <= max_remove) : (i += 1) {
                            const text = try std.fmt.allocPrint(allocator, "{d}", .{i});
                            try num_choices.append(allocator, .{ .kind = .number, .text = text, .number = i });
                        }
                        g.runner_prompt_state = .{
                            .prompt_type = try allocator.dupe(u8, "lie-low-tags"),
                            .choices = try num_choices.toOwnedSlice(allocator),
                            .source_card = null,
                            .ability_ref = prompt.ability_ref,
                            .on_choice = &on_choice,
                        };
                        g.decision_side = .runner;
                        g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                    } else return error.UnsupportedChoice;
                } else if (std.mem.eql(u8, prompt.prompt_type, "lie-low-tags")) {
                    const num_tags = std.fmt.parseInt(u8, choice_text, 10) catch return error.UnsupportedChoice;
                    if (num_tags > 0) {
                        try removeRunnerTags(g, num_tags);
                        g.systemMsg(.runner, 35015, "Runner uses Lie Low to remove {d} tag{s}.", .{ num_tags, if (num_tags != 1) "s" else "" });
                    }
                    g.runner_prompt_state = null;
                    if (try resumePendingEffects(g)) return;
                    g.decision_side = .runner;
                    g.legal_actions = try runnerOpeningActionsForState(allocator, g);
                } else return error.UnsupportedChoice;
            }
        }.play,
    },
    .{
        .title = "Maintenance Access",
        .side = .runner,
        .code = 35016,
        .card_type = "Event",
        .subtypes = &.{ "Double", "Run" },
        .cost = 0,
        .runner_play = .{ .kind = .choose_run_target, .run_target_kind = .archives_only, .lose_clicks = 1 },
    },
    .{
        .title = "Transfer of Wealth",
        .side = .runner,
        .code = 35017,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 0,
        .runner_play = .{ .kind = .choose_run_target, .run_target_kind = .hq_only },
    },
    .{
        .title = "Illumination",
        .side = .runner,
        .code = 35025,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 0,
        .runner_play = .{ .kind = .choose_run_target, .run_target_kind = .rd_only },
    },
    .{
        .title = "Ritual",
        .side = .runner,
        .code = 35026,
        .card_type = "Event",
        .cost = 0,
        .runner_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, _: state.CardInstance) anyerror!void {
                // "Draw 1 card for each [click] you have remaining."
                const clicks_remaining: u8 = @intCast(g.runner_click);
                if (clicks_remaining > 0) {
                    try drawCards(g, .runner, clicks_remaining);
                }
                g.decision_side = .runner;
                g.legal_actions = try runnerOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play,
        .on_play_msg = "draw cards equal to remaining clicks.",
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
        .on_install = &struct {
            fn install(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const install_ctx = g.runner_install_context orelse return;
                if (install_ctx.install_cost != 0 or g.runner_deck.items.len == 0) return;
                try hostTopRunnerDeckCard(g, card);
            }
        }.install,
        .abilities = &.{.{
            .label_fn = &struct {
                fn label(allocator: std.mem.Allocator, _: state.CardInstance) anyerror![]const u8 {
                    return allocator.dupe(u8, "Play or install a hosted card");
                }
            }.label,
            .req = &struct {
                fn can(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                    return countPlayableHostedRunnerCards(gameFromConstEffectContext(ctx), card.*) > 0;
                }
            }.can,
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    try beginRunnerHostedCardPrompt(g, card.instance_id, &blingOnChoice);
                }
            }.use,
        }},
        .event_abilities = &.{.{
            .event = .runner_end_turn,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    try trashHostedRunnerCards(gameFromEffectContext(ctx), card);
                }
            }.handle,
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
            .label_fn = &struct {
                fn label(allocator: std.mem.Allocator, _: state.CardInstance) anyerror![]const u8 {
                    return allocator.dupe(u8, "Return 2 hosted cards to HQ to access 1 random HQ card");
                }
            }.label,
            .req = &struct {
                fn can(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    if (card.hosted.len < 2) return false;
                    return switch (g.active_player) {
                        .corp => g.corp_click >= 1,
                        .runner => g.runner_click >= 1,
                    };
                }
            }.can,
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
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const run = g.run orelse return;
                    if (!std.mem.eql(u8, run.server[0], "hq") or g.runner_successful_run_this_turn or g.corp_hand.items.len == 0) return;
                    try beginYesNoPrompt(g, .runner, "runner-host-confirm", card.*);
                    if (g.runner_prompt_state) |*ps| {
                        ps.on_choice = &on_choice;
                        ps.ability_ref = .{ .source_instance_id = card.instance_id };
                    }
                    g.corp_prompt_state = .{
                        .prompt_type = try g.arena.allocator().dupe(u8, "waiting"),
                        .choices = &.{},
                        .source_card = null,
                    };
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const prompt = g.runner_prompt_state orelse return error.NoPromptState;
                    if (!std.mem.eql(u8, prompt.prompt_type, "runner-host-confirm")) return error.UnsupportedChoice;
                    g.runner_prompt_state = null;
                    g.corp_prompt_state = null;
                    if (std.mem.eql(u8, choice_text, "Yes")) {
                        const ref = prompt.ability_ref orelse return error.MissingSourceCard;
                        const host = findCardPtrByInstanceId(g, ref.source_instance_id) orelse return error.InvalidCardIndex;
                        try hostRandomHqCard(g, host);
                    } else if (!std.mem.eql(u8, choice_text, "No")) {
                        return error.UnsupportedChoice;
                    }
                    if (try resumePendingEffects(g)) return;
                    try restorePriorityAfterPrompt(g);
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
                    if (server.len == 0 or !std.mem.eql(u8, server[0], "hq")) return;
                    // Find rezzed non-agenda corp cards to derez
                    const allocator = g.arena.allocator();
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
                        .prompt_type = allocator.dupe(u8, "maglectric-derez") catch return,
                        .choices = choices.toOwnedSlice(allocator) catch return,
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = promptChoiceActions(allocator, .runner, g.runner_prompt_state.?) catch return;
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (std.mem.eql(u8, choice_text, "No action")) {
                        g.runner_prompt_state = null;
                        return;
                    }
                    // Self-trash Maglectric Rapid
                    for (g.runner_rig_hardware.items, 0..) |hw, idx| {
                        if (hw.code != null and hw.code.? == 35019) {
                            const trashed = g.runner_rig_hardware.orderedRemove(idx);
                            try appendDiscardCard(g, .runner, trashed);
                            break;
                        }
                    }
                    // Derez the selected corp card
                    for (g.corp_servers.items) |*srv| {
                        for (srv.ices.items) |*ice| {
                            if (ice.rezzed and std.mem.eql(u8, ice.title, choice_text)) {
                                ice.rezzed = false;
                                g.systemMsg(.runner, 35019, "Runner uses Maglectric Rapid to derez {s}.", .{choice_text});
                                g.runner_prompt_state = null;
                                return;
                            }
                        }
                        for (srv.content.items) |*c| {
                            if (c.rezzed and std.mem.eql(u8, c.title, choice_text)) {
                                c.rezzed = false;
                                g.systemMsg(.runner, 35019, "Runner uses Maglectric Rapid to derez {s}.", .{choice_text});
                                g.runner_prompt_state = null;
                                return;
                            }
                        }
                    }
                    g.runner_prompt_state = null;
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
        // "On install + turn begin: may host on non-AI icebreaker. Host gets +1 str.
        //  Pump abilities last for remainder of run instead of shorter duration."
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
            .label_fn = &struct {
                fn label(allocator: std.mem.Allocator, _: state.CardInstance) anyerror![]const u8 {
                    return allocator.dupe(u8, "Host programs or install a hosted program");
                }
            }.label,
            .req = &struct {
                fn can(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                    const g = gameFromConstEffectContext(ctx);
                    if (!isAbilityUsedThisTurn(card, 1)) {
                        for (card.hosted) |hosted_card| {
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
            }.can,
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.arena.allocator();
                    // ability_used_this_turn reset removed: per-ability tracking via bit 1 for install sub-branch
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
                        for (card.hosted) |hosted_card| {
                            if (!runnerHandInstallableByEffect(g, hosted_card)) continue;
                            try choices.append(allocator, stringChoice("Install a hosted program"));
                            break;
                        }
                    }
                    if (choices.items.len == 0) return;
                    g.runner_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "runner-host-mode"),
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = card.*,
                        .ability_ref = .{ .source_instance_id = card.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.arena.allocator();
                    const prompt = g.runner_prompt_state orelse return error.NoPromptState;
                    const ref = prompt.ability_ref orelse return error.MissingSourceCard;
                    const host = findCardPtrByInstanceId(g, ref.source_instance_id) orelse return error.InvalidCardIndex;
                    if (std.mem.eql(u8, prompt.prompt_type, "runner-host-mode")) {
                        if (std.mem.eql(u8, choice_text, "Host programs from grip")) {
                            try spendClicks(g, .runner, 1);
                            var choices: std.ArrayList(state.PromptChoice) = .empty;
                            defer choices.deinit(allocator);
                            for (g.runner_hand.items, 0..) |hand_card, idx| {
                                const card_type = hand_card.card_type orelse continue;
                                if (!std.mem.eql(u8, card_type, "Program")) continue;
                                try choices.append(allocator, .{
                                    .kind = .card,
                                    .text = try allocator.dupe(u8, hand_card.title),
                                    .card = .{ .title = hand_card.title, .printed_title = hand_card.printed_title, .code = hand_card.code, .side = .runner, .index = @intCast(idx) },
                                });
                            }
                            try choices.append(allocator, stringChoice("Done"));
                            g.runner_prompt_state = .{
                                .prompt_type = try allocator.dupe(u8, "runner-host-from-grip"),
                                .choices = try choices.toOwnedSlice(allocator),
                                .ability_ref = ref,
                                .on_choice = &on_choice,
                            };
                            g.decision_side = .runner;
                            g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                            return;
                        }
                        if (std.mem.eql(u8, choice_text, "Install a hosted program")) {
                            var choices: std.ArrayList(state.PromptChoice) = .empty;
                            defer choices.deinit(allocator);
                            for (host.hosted, 0..) |hosted_card, idx| {
                                if (!runnerHandInstallableByEffect(g, hosted_card)) continue;
                                try choices.append(allocator, .{
                                    .kind = .card,
                                    .text = try allocator.dupe(u8, hosted_card.title),
                                    .card = .{ .title = hosted_card.title, .printed_title = hosted_card.printed_title, .code = hosted_card.code, .side = .runner, .index = @intCast(idx) },
                                });
                            }
                            if (choices.items.len == 0) return error.UnsupportedChoice;
                            g.runner_prompt_state = .{
                                .prompt_type = try allocator.dupe(u8, "runner-hosted-install"),
                                .choices = try choices.toOwnedSlice(allocator),
                                .ability_ref = ref,
                                .on_choice = &on_choice,
                            };
                            g.decision_side = .runner;
                            g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                            return;
                        }
                        return error.UnsupportedChoice;
                    }
                    if (std.mem.eql(u8, prompt.prompt_type, "runner-host-from-grip")) {
                        if (std.mem.eql(u8, choice_text, "Done")) {
                            g.runner_prompt_state = null;
                            try restorePriorityAfterPrompt(g);
                            return;
                        }
                        for (g.runner_hand.items, 0..) |hand_card, idx| {
                            if (!std.mem.eql(u8, hand_card.title, choice_text)) continue;
                            const hosted = g.runner_hand.orderedRemove(idx);
                            try appendHostedCard(g.arena.allocator(), host, hosted);
                            g.systemMsg(.runner, 35028, "Runner uses Madani to host {s}.", .{hosted.title});
                            var choices: std.ArrayList(state.PromptChoice) = .empty;
                            defer choices.deinit(allocator);
                            for (g.runner_hand.items, 0..) |remaining_card, remaining_idx| {
                                const card_type = remaining_card.card_type orelse continue;
                                if (!std.mem.eql(u8, card_type, "Program")) continue;
                                try choices.append(allocator, .{
                                    .kind = .card,
                                    .text = try allocator.dupe(u8, remaining_card.title),
                                    .card = .{ .title = remaining_card.title, .printed_title = remaining_card.printed_title, .code = remaining_card.code, .side = .runner, .index = @intCast(remaining_idx) },
                                });
                            }
                            try choices.append(allocator, stringChoice("Done"));
                            g.runner_prompt_state = .{
                                .prompt_type = try allocator.dupe(u8, "runner-host-from-grip"),
                                .choices = try choices.toOwnedSlice(allocator),
                                .ability_ref = ref,
                                .on_choice = &on_choice,
                            };
                            g.decision_side = .runner;
                            g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                            return;
                        }
                        return error.UnsupportedChoice;
                    }
                    if (std.mem.eql(u8, prompt.prompt_type, "runner-hosted-install")) {
                        const hosted_index = hostedChoiceIndex(prompt, choice_text) orelse return error.UnsupportedChoice;
                        const hosted = try removeHostedCard(g.arena.allocator(), host, hosted_index);
                        try g.runner_hand.append(g.backing_allocator, hosted);
                        const hand_index: u8 = @intCast(g.runner_hand.items.len - 1);
                        markAbilityUsedThisTurn(host, 0);
                        g.runner_prompt_state = null;
                        try beginRunnerInstallFromHand(g, hand_index, false);
                        g.systemMsg(.runner, 35028, "Runner uses Madani to install {s}.", .{hosted.title});
                        if (hasActivePrompt(g) or g.pending_install != null) return;
                        try restorePriorityAfterPrompt(g);
                        return;
                    }
                    return error.UnsupportedChoice;
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
        .trash_access_self_trash = true,
        .trash_access_draw = 1,
    },
    .{ .title = "Hantu", .side = .runner, .code = 35008, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer", "Virus" }, .cost = 3, .strength = 2, .runner_install = .{ .kind = .program }, .on_install = &struct {
        fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
            card.virus_counter += 2;
        }
    }.handle, .abilities = &.{ breakAbility(1), .{
        .req = &struct {
            fn req(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                const run = g.run orelse return false;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return false;
                const ice_idx = run.current_ice_index orelse return false;
                const server = findServerByRunPath(g.corp_servers.items, run.server) catch return false;
                const ice_count = server.slot.ices.items.len;
                if (ice_idx >= ice_count) return false;
                const actual_idx = ice_count - 1 - ice_idx;
                const ice = server.slot.ices.items[actual_idx];
                if (!canBreakIceType(card.*, ice)) return false;
                return card.virus_counter > 0;
            }
        }.req,
        .on_use = &struct {
            fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const run = g.run orelse return error.NoRunInProgress;
                if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;
                if (card.virus_counter == 0) return error.InsufficientCredits;
                card.virus_counter -= 1;
                const current = effectiveStrength(card.*);
                card.current_strength = current + 2;
                g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to increase strength to {d}.", .{ card.title, card.current_strength orelse 0 });
                const ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
                const server = &g.corp_servers.items[target_server.index];
                const ice_count = server.ices.items.len;
                if (ice_idx >= ice_count) return error.InvalidIceIndex;
                const actual_idx = ice_count - 1 - ice_idx;
                const ice = server.ices.items[actual_idx];
                g.decision_side = .runner;
                g.legal_actions = try encounterActionsForState(g.arena.allocator(), g, ice);
            }
        }.use,
        .label = "Boost strength",
    } } },
    .{ .title = "Rising Tide", .side = .runner, .code = 35009, .card_type = "Program", .subtypes = &.{ "Fracter", "Icebreaker" }, .cost = 1, .strength = 1, .runner_install = .{ .kind = .program }, .static_abilities = &.{.{
        .kind = .self_strength,
        .value = 1,
        .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance, _: ?*const state.CardInstance) i16 {
                return countFractersInHeap(gameFromConstEffectContext(ctx));
            }
        }.req,
    }}, .abilities = &.{ breakAbility(1), pumpAbility(1, 1) } },
    .{ .title = "Sang Kancil", .side = .runner, .code = 35020, .card_type = "Program", .subtypes = &.{ "Decoder", "Icebreaker" }, .cost = 3, .strength = 2, .runner_install = .{ .kind = .program }, .abilities = &.{ breakAbility(1), pumpAbility(3, 2) }, .static_abilities = &.{.{
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
        .event_abilities = &.{.{
            .event = .runner_turn_begins,
            .handler = &struct {
                fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    card.credit_counter = 2;
                }
            }.handle,
        }},
    },
    .{ .title = "Chromatophores", .side = .runner, .code = 35030, .card_type = "Program", .subtypes = &.{"Trojan"}, .cost = 1, .runner_install = .{ .kind = .program }, .trojan_adds_all_subtypes = true },
    .{
        .title = "Devadatta Drone",
        .side = .runner,
        .code = 35031,
        .card_type = "Program",
        .cost = 1,
        .runner_install = .{ .kind = .program },
        .on_install = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.power_counter += 2;
            }
        }.handle,
        .event_abilities = &.{.{
            .event = .successful_run_ends,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (g.run == null) return;
                    const server = g.run.?.server;
                    // Only trigger on R&D runs
                    if (server.len == 0 or !std.mem.eql(u8, server[0], "rnd")) return;
                    if (card.power_counter == 0) return;
                    card.power_counter -= 1;
                    g.run.?.access_bonus += 1;
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
    }}, .abilities = &.{ breakAbility(1), pumpAbility(2, 2) } },
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
                        if (card.ability_used_this_turn) return;
                        card.power_counter += 1;
                        card.ability_used_this_turn = true;
                        const g = gameFromEffectContext(ctx);
                        g.systemMsg(.runner, 35010, "Runner places 1 power counter on Cacophony.", .{});
                    }
                }.handle,
            },
            .{
                .event = .runner_trash_corp_card,
                .handler = &struct {
                    fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                        if (card.ability_used_this_turn) return;
                        card.power_counter += 1;
                        card.ability_used_this_turn = true;
                        const g = gameFromEffectContext(ctx);
                        g.systemMsg(.runner, 35010, "Runner places 1 power counter on Cacophony.", .{});
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
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    g.runner_credit += 9;
                    g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain 9 [credits].", .{card.title});
                    // Trash self from resources
                    if (findRunnerResourceIndex(g, card.code orelse 0)) |idx| {
                        const trashed = g.runner_rig_resources.orderedRemove(idx);
                        try appendDiscardCard(g, .runner, trashed);
                    }
                }
            }.use,
            .label_fn = &struct {
                fn label(allocator: std.mem.Allocator, _: state.CardInstance) anyerror![]const u8 {
                    return allocator.dupe(u8, "Gain 9 [Credits]");
                }
            }.label,
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
        // Bypass handled via encounter event check
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
        .installed_ability = .{
            .kind = .start_of_turn_credits,
            .take_credits_amount = 1,
            .trash_on_empty = true,
        },
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
                    markAbilityUsedThisTurn(card, 0);
                    // Check if runner has other installed cards (need at least 2 total)
                    const total_installed = g.runner_rig_resources.items.len + g.runner_rig_program.items.len + g.runner_rig_hardware.items.len;
                    if (total_installed < 2) return; // Only Knickknack itself, nothing to trash
                    // Build choices: all other installed runner cards
                    const allocator = g.arena.allocator();
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
                        .prompt_type = allocator.dupe(u8, "knickknack-trash") catch return,
                        .choices = choices.toOwnedSlice(allocator) catch return,
                        .source_card = card.*,
                        .ability_ref = .{ .source_instance_id = card.instance_id },
                        .on_choice = &on_choice,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = promptChoiceActions(allocator, .runner, g.runner_prompt_state.?) catch return;
                }
                fn on_choice(ctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    if (std.mem.eql(u8, choice_text, "No action")) {
                        g.runner_prompt_state = null;
                        // Run is already in progress, return to run flow
                        return;
                    }
                    // Find and trash the selected installed card
                    var gain: u16 = 0;
                    // Check resources
                    for (g.runner_rig_resources.items, 0..) |c, idx| {
                        if (std.mem.eql(u8, c.title, choice_text)) {
                            gain = c.cost orelse 0;
                            const trashed = g.runner_rig_resources.orderedRemove(idx);
                            try appendDiscardCard(g, .runner, trashed);
                            break;
                        }
                    }
                    // Check programs
                    if (gain == 0) {
                        for (g.runner_rig_program.items, 0..) |c, idx| {
                            if (std.mem.eql(u8, c.title, choice_text)) {
                                gain = c.cost orelse 0;
                                const trashed = g.runner_rig_program.orderedRemove(idx);
                                try appendDiscardCard(g, .runner, trashed);
                                if (g.runner_memory) |*mem| {
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
                        for (g.runner_rig_hardware.items, 0..) |c, idx| {
                            if (std.mem.eql(u8, c.title, choice_text)) {
                                gain = c.cost orelse 0;
                                const trashed = g.runner_rig_hardware.orderedRemove(idx);
                                try appendDiscardCard(g, .runner, trashed);
                                break;
                            }
                        }
                    }
                    g.runner_credit += gain;
                    try drawCards(g, .runner, 1);
                    g.systemMsg(.runner, 35033, "Runner uses \"Knickknack\" O'Brian to trash {s}, gain {d} [credits], and draw 1 card.", .{ choice_text, gain });
                    g.runner_prompt_state = null;
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
        .event_abilities = &.{.{
            .event = .run_begins,
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    card.credit_counter += 1;
                    g.systemMsg(.runner, card.code orelse 0, "Runner places 1 [credit] on {s}.", .{card.title});
                    if (card.credit_counter >= 6) {
                        g.runner_credit += card.credit_counter;
                        g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credits] and draw 1 card.", .{
                            card.title, card.credit_counter,
                        });
                        card.credit_counter = 0;
                        try drawCards(g, .runner, 1);
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
