const std = @import("std");
const state = @import("state.zig");

pub const DeckLine = struct {
    qty: u8,
    card_code: u32,
};

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
    // Run event fields (for run-target events)
    run_target_kind: state.RunTargetKind = .any_runnable,
    run_credits: u16 = 0,
    run_rez_cost_bonus: u16 = 0,
    successful_run_effect: state.RunSuccessEffectKind = .none,
    successful_run_draw_cards: u8 = 0,
    successful_run_access_bonus: u8 = 0,
    install: state.InstallSpec = .{},
    runner_install: state.RunnerInstallSpec = .{},
    abilities: []const state.AbilitySpec = &.{},
    static_abilities: []const state.StaticAbility = &.{},
    event_abilities: []const state.EventAbility = &.{},
    // Installed ability data (flattened)
    initial_credit_counters: u16 = 0,
    take_credits_amount: u16 = 0,
    trash_on_empty: bool = false,
    on_install: ?state.InstalledAbilityCallback = null,
    on_take: ?state.InstalledAbilityCallback = null,
    on_empty: ?state.InstalledAbilityCallback = null,
    click_draw_bonus: u8 = 0,
    auto_trash_at_credits: u8 = 0,
    draw_on_auto_trash: u8 = 0,
    place_credits_per_turn: bool = false,
    auto_take_credits: bool = false,
    subroutines: []const state.SubroutineSpec = &.{},
    on_score: state.AgendaEffectSpec = .{},
    on_steal: state.AgendaEffectSpec = .{},
    trash_cost: ?u16 = null,
    on_access: ?*const fn (*Game, state.CardInstance) anyerror!bool = null,
    on_approach: ?*const fn (*Game, *const state.CardInstance) anyerror!bool = null,
    on_play_msg: ?[]const u8 = null, // logged after on_play fires (effect description, not "plays X")
};

/// Deferred effect for the async continuation queue.
/// When multiple effects trigger simultaneously (e.g., scoring an agenda triggers
/// on-score effects + event handlers from multiple cards), they are queued here
/// and processed one at a time. If any effect opens a prompt, processing pauses
/// until the prompt resolves, then continues with the next effect.
pub const CardZone = enum(u8) {
    identity,
    runner_resource,
    runner_program,
    runner_hardware,
    corp_server_content,
    corp_ice_hosted,
};

pub const EventSource = struct {
    code: u32,
    event: state.GameEvent,
    side: state.Side,
    zone: CardZone,
    ability_index: u8 = 0,
    index: u16 = 0, // index within zone at collection time
    server_index: u16 = 0, // for corp_server_content zone
    parent_index: u16 = 0, // host ICE index for corp_ice_hosted zone
};

pub const PendingEffect = union(enum) {
    event_handler: EventSource,
    card_effect: struct { card: state.CardInstance, event: state.GameEvent, ability_index: u8 },
    finish_score: void,
    finish_steal: struct { accessed: state.CardInstance, is_central: bool },
    deferred_prompt: struct {
        card: state.CardInstance,
        on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void,
        open_fn: *const fn (*Game, state.CardInstance, ?*const fn (*state.EffectContext, []const u8) anyerror!void) anyerror!bool,
    },
};

const PendingAccessZone = enum(u8) {
    corp_hand,
    corp_deck,
    corp_discard,
    corp_server_content,
};

const PendingAccess = struct {
    zone: PendingAccessZone,
    card_index: u8,
    server_index: usize = 0,
};

const RunnerInstallContext = struct {
    install_cost: u16,
};

pub const SideSpec = struct {
    identity_code: u32,
    deck_lines: []const DeckLine,
};

pub const MatchupSpec = struct {
    format: []const u8,
    agenda_point_req: u8,
    corp: SideSpec,
    runner: SideSpec,
};

// Shared play ability generators — return AbilitySpec entries for play-from-hand effects
fn corpGainCreditsPlayAbility(comptime credits: u16, comptime draw: u8) state.AbilitySpec {
    return .{ .is_play = true, .on_use = &struct {
        fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
            const g = gameFromEffectContext(ctx);
            g.corp_credit += credits;
            if (draw > 0) try drawCards(g, .corp, draw);
            if (credits > 0) {
                g.turn_events.operation_played_count += 1;
                _ = try fireEvent(g, .operation_played);
            }
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
            g.legal_actions = try runnerOpeningActionsForState(g.arena.allocator(), g);
        }
    }.play };
}

fn runnerRunEventPlayAbility(comptime target_kind: state.RunTargetKind, comptime lose_clicks: u8) state.AbilitySpec {
    return .{ .is_play = true, .on_use = &struct {
        fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
            const g = gameFromEffectContext(ctx);
            const allocator = g.arena.allocator();
            if (lose_clicks > 0) try spendClicks(g, .runner, lose_clicks);
            g.runner_prompt_state = .{
                .prompt_type = try allocator.dupe(u8, "run-target"),
                .choices = try runTargetChoicesFor(allocator, target_kind, g.corp_servers.items),
                .source_card = card.*,
            };
            g.decision_side = .runner;
            g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
        }
    }.play };
}

// Peer Review on_choice handler — handles peer-review-private, peer-review-install, peer-review-server
const peer_review_on_choice: *const fn (*state.EffectContext, []const u8) anyerror!void = &struct {
    fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
        const cg = gameFromEffectContext(cctx);
        const c_allocator = cg.arena.allocator();
        const prompt = cg.corp_prompt_state orelse return error.NoPromptState;
        if (std.mem.eql(u8, prompt.prompt_type, "peer-review-private")) {
            try beginPeerReviewInstallPrompt(cg, prompt.source_card orelse return error.NoPromptState, peer_review_on_choice);
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
                            .prompt_type = try c_allocator.dupe(u8, "peer-review-server"),
                            .choices = try server_choices.toOwnedSlice(c_allocator),
                            .source_card = prompt.source_card,
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
            const source_card = prompt.source_card orelse return error.MissingSourceCard;
            cg.runner_prompt_state = null;
            try cg.pending_effects.append(cg.backing_allocator, .{ .deferred_prompt = .{
                .card = source_card,
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

/// Find the play ability in a card's abilities array
fn findPlayAbility(abilities: []const state.AbilitySpec) ?*const state.AbilitySpec {
    for (abilities) |*ability| {
        if (ability.is_play) return ability;
    }
    return null;
}

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
                                    cg.legal_actions = try runnerOpeningActionsForState(cg.arena.allocator(), cg);
                                } else {
                                    cg.decision_side = .corp;
                                    cg.legal_actions = try corpOpeningActionsForState(cg.arena.allocator(), cg);
                                }
                            }
                        }.choice,
                    };
                    g.runner_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "waiting"),
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
                                cg.legal_actions = try runnerOpeningActionsForState(cg.arena.allocator(), cg);
                            }
                        }.handle,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }.handle,
        }},
    },
    .{ .title = "Offworld Office", .side = .corp, .code = 30067, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 4, .install = .{ .kind = .corp_remote_only }, .on_score = .{ .kind = .gain_credits, .amount = 7 } },
    .{ .title = "Send a Message", .side = .corp, .code = 30069, .card_type = "Agenda", .agenda_points = 3, .advancement_requirement = 5, .install = .{ .kind = .corp_remote_only }, .on_score = .{ .kind = .rez_ice_free }, .on_steal = .{ .kind = .rez_ice_free } },
    .{ .title = "Superconducting Hub", .side = .corp, .code = 30070, .card_type = "Agenda", .agenda_points = 1, .advancement_requirement = 3, .install = .{ .kind = .corp_remote_only }, .static_abilities = &.{.{ .kind = .hand_size, .value = 2 }}, .on_score = .{ .kind = .draw_cards, .amount = 2 } },
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
    .{ .title = "Nico Campaign", .side = .corp, .code = 30037, .card_type = "Asset", .cost = 2, .trash_cost = 2, .install = .{ .kind = .corp_remote_only },
        .auto_take_credits = true,
        .initial_credit_counters = 9,
        .take_credits_amount = 3,
        .trash_on_empty = true,
        .on_empty = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                try drawCards(gameFromEffectContext(ctx), .corp, 1);
            }
        }.handle,
    },
    .{ .title = "Regolith Mining License", .side = .corp, .code = 30071, .card_type = "Asset", .cost = 2, .trash_cost = 3, .install = .{ .kind = .corp_remote_only },
        .initial_credit_counters = 15,
    .abilities = &.{.{
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
    .{ .title = "Urtica Cipher", .side = .corp, .code = 30045, .card_type = "Asset", .cost = 0, .trash_cost = 2, .static_abilities = &.{.{ .kind = .can_advance }}, .install = .{ .kind = .corp_remote_only }, .on_access = &struct {
        fn access(g: *Game, accessed: state.CardInstance) anyerror!bool {
            return try beginNetDamageOnAccessPrompt(g, accessed);
        }
    }.access },
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
                    .source_card = card.*,
                
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            const advanced_card = try addAdvancementCounter(cg, choice_text, 2);
                            cg.systemMsg(.corp, 30040, "Corp uses Seamless Launch to advance {s} 2 times.", .{advanced_card.title});
                            cg.corp_prompt_state = null;
                            cg.decision_side = .corp;
                            cg.legal_actions = try corpOpeningActionsForState(cg.arena.allocator(), cg);
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
                const allocator = g.arena.allocator();
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "other"),
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
                            cg.legal_actions = try corpOpeningActionsForState(cg.arena.allocator(), cg);
                        }
                    }.choice,
                };
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
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

        .abilities = &.{.{ .is_play = true, .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                return runner_had_successful_run_last_turn(g);
            }
        }.req, .on_use = &struct {
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
                            cg.legal_actions = try corpOpeningActionsForState(cg.arena.allocator(), cg);
                        }
                    }.choice,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.play }},
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
                            cg.legal_actions = try corpOpeningActionsForState(cg.arena.allocator(), cg);
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
        .on_approach = &struct {
            fn approach(g: *Game, card: *const state.CardInstance) anyerror!bool {
                if (!card.rezzed) return false;
                const allocator = g.arena.allocator();
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                if (g.runner_click >= 2) {
                    try choices.append(allocator, stringChoice(try allocator.dupe(u8, "Spend [Click][Click]")));
                }
                if (g.runner_credit >= 5) {
                    try choices.append(allocator, stringChoice(try allocator.dupe(u8, "Pay 5 [Credits]")));
                }
                try choices.append(allocator, stringChoice(try allocator.dupe(u8, "End the run")));
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "manegarm-tax"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = card.*,
                
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            cg.systemMsg(.runner, 30042, "Runner uses Manegarm Skunkworks to {s}.", .{choice_text});
                            const c_allocator = cg.arena.allocator();
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
                                // Clojure's approach-server event resolves directly into breach —
                                // no corp priority window between Manegarm payment and access.
                                run.phase = try c_allocator.dupe(u8, "success");
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
                return true;
            }
        }.approach,
    },
    .{ .title = "AMAZE Amusements", .side = .corp, .code = 30058, .card_type = "Upgrade", .cost = 1, .trash_cost = 3, .install = .{ .kind = .corp_server_choice }, .on_access = &struct {
        fn access(g: *Game, _: state.CardInstance) anyerror!bool {
            try addFloatingEffect(g, .{
                .kind = .tags_on_steal,
                .duration = .end_of_run,
                .value = 2,
            });
            return false;
        }
    }.access },
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
        .event_abilities = &.{.{ .event = .ice_encountered, .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                try choices.append(allocator, stringChoice("Take 1 tag"));
                try choices.append(allocator, stringChoice("End the run"));
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "funhouse-encounter"),
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
                                cg.legal_actions = try encounterActionsForState(cg.arena.allocator(), cg, c_ice);
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
        }.handle }},
    },
    .{ .title = "Creative Commission", .side = .runner, .code = 30020, .card_type = "Event", .cost = 1, .abilities = &.{runnerGainCreditsPlayAbility(5, 0, 1)} },
    .{ .title = "Jailbreak", .side = .runner, .code = 30028, .card_type = "Event", .cost = 0, .abilities = &.{runnerRunEventPlayAbility(.hq_and_rnd_only, 0)}, .run_target_kind = .hq_and_rnd_only, .successful_run_effect = .draw_cards, .successful_run_draw_cards = 1, .successful_run_access_bonus = 1 },
    .{ .title = "Overclock", .side = .runner, .code = 30029, .card_type = "Event", .cost = 1, .abilities = &.{runnerRunEventPlayAbility(.any_runnable, 0)}, .run_credits = 5 },
    .{ .title = "Sure Gamble", .side = .runner, .code = 30030, .card_type = "Event", .cost = 5, .abilities = &.{runnerGainCreditsPlayAbility(9, 0, 0)} },
    .{ .title = "Tread Lightly", .side = .runner, .code = 30012, .card_type = "Event", .cost = 1, .abilities = &.{runnerRunEventPlayAbility(.any_runnable, 0)}, .run_rez_cost_bonus = 3 },
    .{
        .title = "Mutual Favor",
        .side = .runner,
        .code = 30011,
        .card_type = "Event",
        .cost = 0,

        .on_play_msg = "search stack for an icebreaker.",
        .abilities = &.{.{ .is_play = true, .on_use = &struct {
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
                    g.arena.allocator(),
                    g,
                );
            }
        }.play }},
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
                const allocator = g.arena.allocator();
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "other"),
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
                                cg.arena.allocator(),
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
    .{ .title = "Red Team", .side = .runner, .code = 30018, .card_type = "Resource", .cost = 5, .runner_install = .{ .kind = .resource },
        .initial_credit_counters = 12,
        .take_credits_amount = 3, // read by applySourceCardOnSuccessfulRun
        .trash_on_empty = true, // read by applySourceCardOnSuccessfulRun
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
                const allocator = g.arena.allocator();
                const choices = try centralNotRunThisTurnChoices(allocator, g.turn_events);
                if (choices.len == 0) return;
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, prompt_run_central),
                    .choices = choices,
                    .source_card = card.*,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.handle,
    }} },
    .{ .title = "Smartware Distributor", .side = .runner, .code = 30033, .card_type = "Resource", .cost = 0, .runner_install = .{ .kind = .resource },
        .place_credits_per_turn = true,
    .abilities = &.{.{
        .cost = .{ .clicks = 1 },
        .label = "Place 3 [Credits] on this card",
        .on_use = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.credit_counter += 3;
            }
        }.handle,
    }} },
    .{ .title = "Telework Contract", .side = .runner, .code = 30027, .card_type = "Resource", .cost = 1, .runner_install = .{ .kind = .resource },
        .initial_credit_counters = 9,
    .abilities = &.{.{
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
        .label = "Run on R&D",
        .on_use = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                try applyRunFromAbility(gameFromEffectContext(ctx), "R&D", card.instance_id);
            }
        }.handle,
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
    .{ .title = "Leech", .side = .runner, .code = 30008, .card_type = "Program", .cost = 1, .runner_install = .{ .kind = .program }, .event_abilities = &.{.{
        .event = .successful_run_ends,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const run = g.run orelse return;
                if (!isCentralRunServer(run.server)) return;
                card.virus_counter += 1;
            }
        }.handle,
    }}, .abilities = &.{.{
        .on_use = &encounterLeechHandler,
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
        .on_score = .{ .kind = .give_runner_tag, .amount = 1 },
        .on_steal = .{ .kind = .give_runner_tag, .amount = 1 },
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

        .on_play_msg = "draw 3 cards.",
        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, src_card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
                try drawCards(g, .corp, 3);
                // Present prompt to choose 2 cards to shuffle back
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                for (g.corp_hand.items, 0..) |card, idx| {
                    try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                }
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "sprint-shuffle"),
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
                                    const c_allocator = cg.arena.allocator();
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
                            cg.legal_actions = try corpOpeningActionsForState(cg.arena.allocator(), cg);
                        }
                    }.choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play }},
    },
    .{
        .title = "Hansei Review",
        .side = .corp,
        .code = 30048,
        .card_type = "Operation",
        .cost = 5,

        .on_play_msg = "gain 10 [credits].",
        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                const allocator = g.arena.allocator();
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
                    .prompt_type = try allocator.dupe(u8, "hansei-trash"),
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
                            cg.legal_actions = try corpOpeningActionsForState(cg.arena.allocator(), cg);
                        }
                    }.choice,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play }},
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
                            cg.legal_actions = try corpOpeningActionsForState(cg.arena.allocator(), cg);
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
    .{ .title = "Fermenter", .side = .runner, .code = 30007, .card_type = "Program", .subtypes = &.{"Virus"}, .cost = 1, .runner_install = .{ .kind = .program },
        .on_install = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 1;
            }
        }.handle,
    .abilities = &.{.{
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
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
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
        .on_score = .{ .kind = .gain_clicks, .amount = 3 },
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
    .{ .title = "Clearinghouse", .side = .corp, .code = 30061, .card_type = "Asset", .subtypes = &.{"Hostile"}, .cost = 0, .trash_cost = 3, .static_abilities = &.{.{ .kind = .can_advance }}, .install = .{ .kind = .corp_remote_only }, .abilities = &.{.{
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
                if (damage > 0) {
                    try trashRandomRunnerHandCards(g, damage);
                    updateTerminalState(g);
                }
            }
        }.handle,
    }} },
    .{
        .title = "Longevity Serum",
        .side = .corp,
        .code = 30044,
        .card_type = "Agenda",
        .agenda_points = 2,
        .advancement_requirement = 3,

        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{ .event = .agenda_scored, .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
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
                
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            const c_allocator = cg.arena.allocator();
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
                                        .prompt_type = try c_allocator.dupe(u8, "longevity-serum-shuffle"),
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
                                    .prompt_type = try c_allocator.dupe(u8, "longevity-serum-trash"),
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
                                    .prompt_type = try c_allocator.dupe(u8, "longevity-serum-shuffle"),
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
        }.handle }},
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
                                const c_allocator = cg.arena.allocator();
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
        // Spin Doctor ability not yet wired (was dead in legacy too)
    },
    // --- Phase 3: Consoles ---
    .{ .title = "Carnivore", .side = .runner, .code = 30003, .card_type = "Hardware", .subtypes = &.{"Console"}, .cost = 4, .runner_install = .{ .kind = .hardware }, .static_abilities = &.{.{ .kind = .mu, .value = 1 }}, .abilities = &.{.{
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
    }} },
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
                                try beginRunnerOptionalInstallPrompt(g, prompt.source_card orelse return error.MissingSourceCard, &@This().choice);
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
                    try beginRunnerOptionalInstallConfirmPrompt(gameFromEffectContext(ctx), self_card.*, pantograph_on_choice);
                }
            };
            break :blk &.{
                .{ .event = .agenda_scored, .handler = &H.trigger },
                .{ .event = .agenda_stolen, .handler = &H.trigger },
            };
        },
    },
    // --- Phase 4: Trojans ---
    .{ .title = "Botulus", .side = .runner, .code = 30004, .card_type = "Program", .subtypes = &.{ "Virus", "Trojan" }, .cost = 2, .runner_install = .{ .kind = .program },
        .on_install = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 1;
            }
        }.handle,
    .abilities = &.{.{
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
    .{ .title = "Tranquilizer", .side = .runner, .code = 30017, .card_type = "Program", .subtypes = &.{ "Virus", "Trojan" }, .cost = 2, .runner_install = .{ .kind = .program },
        .on_install = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 1;
            }
        }.handle,
    .event_abilities = &.{.{
        .event = .runner_turn_begins,
        .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 1;
                const g = gameFromEffectContext(ctx);
                if (card.virus_counter < 3) return;
                for (g.corp_servers.items) |*server| {
                    for (server.ices.items) |*ice| {
                        for (ice.hosted) |hosted| {
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
        .on_approach = &struct {
            fn approach(g: *Game, card: *const state.CardInstance) anyerror!bool {
                if (!card.rezzed) return false;
                if (g.corp_credit >= 2 and g.corp_hand.items.len >= 2) {
                    const allocator = g.arena.allocator();
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "anoetic-void"),
                        .choices = &.{
                            .{ .kind = .string, .text = "Use Anoetic Void" },
                            .{ .kind = .string, .text = "No action" },
                        },
                        .source_card = card.*,
                    
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                if (std.mem.eql(u8, choice_text, "Use Anoetic Void")) {
                                    // Corp pays 2 credits
                                    if (cg.corp_credit < 2) return error.InsufficientCredits;
                                    cg.corp_credit -= 2;
                                    // Trash 2 cards from HQ (first 2 available)
                                    var trashed: u8 = 0;
                                    while (trashed < 2 and cg.corp_hand.items.len > 0) {
                                        const c_card = cg.corp_hand.orderedRemove(0);
                                        try cg.corp_discard.append(cg.backing_allocator, c_card);
                                        trashed += 1;
                                    }
                                    // Trash Anoetic Void itself (find it in the server)
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
                                    // End the run
                                    try completeUnsuccessfulRun(cg);
                                } else {
                                    // "No action" — proceed to access
                                    cg.corp_prompt_state = null;
                                    const run = &cg.run.?;
                                    const c_allocator = cg.arena.allocator();
                                    // Check Manegarm next
                                    if (try checkServerApproachAbilities(cg)) return;
                                    if (try prepareNextAccess(cg)) {
                                        run.phase = try c_allocator.dupe(u8, "success");
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
                    return true;
                }
                return false;
            }
        }.approach,
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
                    const allocator = g.arena.allocator();
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
                        .prompt_type = try allocator.dupe(u8, "topan-install"),
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = g.runner_identity,
                    
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                if (std.mem.eql(u8, choice_text, "No action")) {
                                    cg.runner_prompt_state = null;
                                    const c_allocator = cg.arena.allocator();
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
                                        const c_allocator = cg.arena.allocator();
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
                    
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.arena.allocator();
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
                        .prompt_type = try allocator.dupe(u8, "waiting"),
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
                        const allocator = g.arena.allocator();
                        const choices = try allocator.alloc(state.PromptChoice, 2);
                        choices[0] = stringChoice("Yes");
                        choices[1] = stringChoice("No");
                        g.runner_prompt_state = .{
                            .prompt_type = try allocator.dupe(u8, "muslihat-reveal"),
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
                                    cg.legal_actions = try runnerOpeningActionsForState(cg.arena.allocator(), cg);
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
                    
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.arena.allocator();
                                if (std.mem.eql(u8, choice_text, "No action")) {
                                    cg.corp_prompt_state = null;
                                    cg.decision_side = .corp;
                                    cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                    return;
                                }
                                // Find card in hand and install
                                const prompt = cg.corp_prompt_state orelse return error.NoPromptState;
                                for (prompt.choices) |ch| {
                                    if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                                        if (ch.card) |card_ref| {
                                            const card_idx = card_ref.index orelse continue;
                                            try installCorpCardFromHand(cg, card_idx, "New remote");
                                            cg.systemMsg(.corp, 35036, "Corp uses Po\xc3\xa9tr\xc3\xaf to install a card.", .{});
                                            break;
                                        }
                                    }
                                }
                                cg.corp_prompt_state = null;
                                cg.decision_side = .corp;
                                cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
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
                    
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.arena.allocator();
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
                    if (isAbilityUsedThisTurn(card, 0)) return;
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
                    markAbilityUsedThisTurn(card, 0);
                    try choices.append(allocator, stringChoice("No action"));
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "corp-free-install-card"),
                        .choices = try choices.toOwnedSlice(allocator),
                        .source_card = card.*,
                    
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.arena.allocator();
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
                                            .prompt_type = try c_allocator.dupe(u8, "corp-free-install-server"),
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
    },
    .{
        .title = "BANGUN: When Disaster Strikes",
        .side = .corp,
        .code = 35068,
        .card_type = "Identity",
        .subtypes = &.{"Corp"},
        .static_abilities = &.{.{ .kind = .faceup_agenda_install }},
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
                                cg.legal_actions = try corpOpeningActionsForState(cg.arena.allocator(), cg);
                            }
                        }.choice,
                    };
                    g.runner_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "waiting"),
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

        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{ .event = .agenda_scored, .handler = &struct {
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
        }.handle }},
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
        .event_abilities = &.{.{ .event = .agenda_scored, .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // "When you score this agenda, place 1 agenda counter on it."
                if (g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = 1;
                }
            }
        }.handle }},
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
        .event_abilities = &.{.{ .event = .agenda_scored, .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // Dividends 1: place 1 agenda counter per excess advancement
                const req = card.advancement_requirement orelse 3;
                const excess = if (card.advancement_counter > req) card.advancement_counter - req else 0;
                if (excess > 0 and g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = excess;
                }
            }
        }.handle }},
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
        .event_abilities = &.{.{ .event = .agenda_scored, .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // Dividends 2: place 2 agenda counters per excess advancement
                const req = card.advancement_requirement orelse 3;
                const excess = if (card.advancement_counter > req) card.advancement_counter - req else 0;
                if (excess > 0 and g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = excess * 2;
                }
            }
        }.handle }},
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
        .event_abilities = &.{.{ .event = .agenda_scored, .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // "When scored or stolen, place 1 agenda counter on it."
                if (g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = 1;
                }
            }
        }.handle }},
    },
    .{ .title = "Greenmail", .side = .corp, .code = 35070, .card_type = "Agenda", .subtypes = &.{"Expansion"}, .agenda_points = 1, .advancement_requirement = 2, .install = .{ .kind = .corp_remote_only }, .on_score = .{ .kind = .gain_credits, .amount = 2 } },
    .{
        .title = "Off the Books",
        .side = .corp,
        .code = 35071,
        .card_type = "Agenda",
        .subtypes = &.{"Initiative"},
        .agenda_points = 2,
        .advancement_requirement = 3,

        .install = .{ .kind = .corp_remote_only },
        .event_abilities = &.{.{ .event = .agenda_scored, .handler = &struct {
            fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // Dividends 1: place 1 agenda counter per excess advancement
                const req = card.advancement_requirement orelse 3;
                const excess = if (card.advancement_counter > req) card.advancement_counter - req else 0;
                if (excess > 0 and g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = excess;
                }
            }
        }.handle }},
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
        .event_abilities = &.{.{ .event = .corp_rez_ice, .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
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
        }.handle }},
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
        .event_abilities = &.{.{ .event = .corp_rez_ice, .handler = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // "When you rez this ice during a run against this server, purge virus counters."
                purgeVirusCounters(g);
                g.systemMsg(.corp, 35079, "Corp uses Flyswatter to purge virus counters.", .{});
            }
        }.handle }},
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
            .{ .resolve = &resolveTagOrPayCreditsEtr, .amount = 3, .label = "Sub 0" },
            .{ .resolve = &resolveEtrIfTagged, .label = "End the run if the Runner is tagged" }
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
        // "3 clicks + trash: Gain 9 credits."
        .abilities = &.{.{
            .cost = .{ .clicks = 3 },
            .label = "Gain 9 [Credits]",
            .on_use = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    g.corp_credit += 9;
                    g.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to gain 9 [credits].", .{card.title});
                    try trashCorpServerCardByInstanceId(g, card.instance_id);
                }
            }.handle,
        }},
    },
    .{ .title = "Otto Campaign", .side = .corp, .code = 35040, .card_type = "Asset", .subtypes = &.{"Advertisement"}, .cost = 2, .trash_cost = 2, .install = .{ .kind = .corp_remote_only },
        .auto_take_credits = true,
        .initial_credit_counters = 6,
        .take_credits_amount = 2,
        .trash_on_empty = true,
        .on_empty = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                gameFromEffectContext(ctx).corp_click += 2;
            }
        }.handle,
    },
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
        .static_abilities = &.{.{ .kind = .can_advance }},
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
    .{ .title = "Anthill Excavation Contract", .side = .corp, .code = 35072, .card_type = "Asset", .subtypes = &.{"Industrial"}, .cost = 3, .trash_cost = 1, .install = .{ .kind = .corp_remote_only },
        .auto_take_credits = true,
        .initial_credit_counters = 8,
        .take_credits_amount = 4,
        .trash_on_empty = true,
        .on_take = &struct {
            fn handle(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                try drawCards(gameFromEffectContext(ctx), .corp, 1);
            }
        }.handle,
    },
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
    .{ .title = "Nanomanagement", .side = .corp, .code = 35043, .card_type = "Operation", .cost = 4, .abilities = &.{.{ .is_play = true, .on_use = &struct {
        fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
            const g = gameFromEffectContext(ctx);
            g.corp_click += 2;
        }
    }.play }}, .on_play_msg = "gain [Click][Click]." },
    .{
        .title = "Top-Down Solutions",
        .side = .corp,
        .code = 35044,
        .card_type = "Operation",
        .cost = 2,

        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            const top_down_on_choice = &struct {
                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(cctx);
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
                                        .source_card = prompt.source_card,
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
                            try showTopDownInstallChoices(g, prompt.source_card orelse return error.NoPromptState, installs_done + 1, &@This().choice);
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
                try showTopDownInstallChoices(g, card.*, 0, top_down_on_choice);
            }
        }.play }},
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
                        .source_card = card.*,
                    
                        .on_choice = peer_review_on_choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    return;
                }
                try beginPeerReviewInstallPrompt(g, card.*, peer_review_on_choice);
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

        .abilities = &.{.{ .is_play = true, .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                // "Play only if the Runner is tagged."
                return if (g.runner_tag) |t| t.is_tagged else false;
            }
        }.req, .on_use = &struct {
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
                
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            const c_allocator = cg.arena.allocator();
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
                                    .prompt_type = try c_allocator.dupe(u8, "bigger-picture-tags"),
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
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play }},
    },
    .{
        .title = "IP Enforcement",
        .side = .corp,
        .code = 35066,
        .card_type = "Operation",
        .subtypes = &.{"Gray Ops"},
        .cost = 0,

        .abilities = &.{.{ .is_play = true, .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                // Requires runner to be tagged and have stolen agendas
                const tagged = if (g.runner_tag) |t| t.is_tagged else false;
                return tagged and g.runner_scored.items.len > 0;
            }
        }.req, .on_use = &struct {
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
                    
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.arena.allocator();
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
        }.play }},
    },
    .{
        .title = "Touch-ups",
        .side = .corp,
        .code = 35067,
        .card_type = "Operation",
        .subtypes = &.{"Double"},
        .cost = 2,

        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // Additional cost: spend [click] (Double)
                try spendClicks(g, .corp, 1);
                // "Place 2 advancement counters on 1 installed card you can advance."
                const allocator = g.arena.allocator();
                const adv_choices = try installedCardChoices(allocator, g.corp_servers.items);
                if (adv_choices.len > 0) {
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "touch-ups-advance"),
                        .choices = adv_choices,
                        .source_card = card.*,
                    
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.arena.allocator();
                                const prompt = cg.corp_prompt_state orelse return error.NoPromptState;
                                if (std.mem.eql(u8, prompt.prompt_type, "touch-ups-advance")) {
                                    _ = try addAdvancementCounter(cg, choice_text, 2);
                                    cg.systemMsg(.corp, 35067, "Corp uses Touch-ups to place 2 advancement counters.", .{});
                                    // Simplified: skip the reveal grip + shuffle part for now
                                    // (complex interaction requiring runner hand reveal)
                                    cg.corp_prompt_state = null;
                                    cg.decision_side = .corp;
                                    cg.legal_actions = try corpOpeningActionsForState(c_allocator, cg);
                                } else return error.UnsupportedChoice;
                            }
                        }.choice,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }
        }.play }},
    },
    .{
        .title = "Key Performance Indicators",
        .side = .corp,
        .code = 35077,
        .card_type = "Operation",
        .subtypes = &.{"Transaction"},
        .cost = 1,

        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            const kpi_on_choice = &struct {
                fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                    const g = gameFromEffectContext(cctx);
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
                                .source_card = prompt.source_card,
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
                                    .prompt_type = try allocator.dupe(u8, "kpi-advance"),
                                    .choices = adv_choices,
                                    .source_card = prompt.source_card,
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
                                    .prompt_type = try allocator.dupe(u8, "kpi-ice-choose"),
                                    .choices = try ice_choices.toOwnedSlice(allocator),
                                    .source_card = prompt.source_card,
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
                            try showKpiChoices(g, prompt.source_card orelse return error.NoPromptState, choices_made + 1, &@This().choice);
                        }
                    } else if (std.mem.eql(u8, prompt.prompt_type, "kpi-advance")) {
                        _ = try addAdvancementCounter(g, choice_text, 1);
                        g.systemMsg(.corp, 35077, "Corp uses Key Performance Indicators to place 1 advancement counter.", .{});
                        if (prompt.min_choices >= 2) {
                            g.corp_prompt_state = null;
                            g.decision_side = .corp;
                            g.legal_actions = try corpOpeningActionsForState(allocator, g);
                        } else {
                            try showKpiChoices(g, prompt.source_card orelse return error.NoPromptState, prompt.min_choices, &@This().choice);
                        }
                    } else if (std.mem.eql(u8, prompt.prompt_type, "kpi-ice-choose")) {
                        for (prompt.choices) |ch| {
                            if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                                if (ch.card) |card_ref| {
                                    const server_choices = try installChoicesForCard(allocator, .corp_server_choice, g);
                                    g.corp_prompt_state = .{
                                        .prompt_type = try allocator.dupe(u8, "kpi-ice-server"),
                                        .choices = server_choices,
                                        .source_card = prompt.source_card,
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
                            try showKpiChoices(g, prompt.source_card orelse return error.NoPromptState, choices_done, &@This().choice);
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
                                try showKpiChoices(g, prompt.source_card orelse return error.NoPromptState, prompt.min_choices, &@This().choice);
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
                try showKpiChoices(g, card.*, 0, kpi_on_choice);
            }
        }.play }},
    },
    .{
        .title = "Measured Response",
        .side = .corp,
        .code = 35078,
        .card_type = "Operation",
        .subtypes = &.{"Black Ops"},
        .cost = 5,
        .trash_cost = 3,

        .abilities = &.{.{ .is_play = true, .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                // "Play only if the threat level is 4 or greater, and only if the Runner made a successful run during their last turn."
                return threatLevel(g) >= 4 and runner_had_successful_run_last_turn(g);
            }
        }.req, .on_use = &struct {
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
                            cg.legal_actions = try corpOpeningActionsForState(cg.arena.allocator(), cg);
                        }
                    }.choice,
                };
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.play }},
    },
    .{
        .title = "Petty Cash",
        .side = .corp,
        .code = 35081,
        .card_type = "Operation",
        .subtypes = &.{"Transaction"},
        .cost = 3,
        .abilities = &.{.{ .is_play = true, .flashback_extra_clicks = 1, .flashback_gain_clicks = 1, .req = &struct {
            fn req(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
                const g = gameFromConstEffectContext(ctx);
                // "Play only if you have not finished an action yet this turn."
                return g.corp_click == g.corp_click_per_turn;
            }
        }.req, .on_use = corpGainCreditsPlayAbility(5, 0).on_use.? }},
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
        .abilities = &.{runnerRunEventPlayAbility(.archives_only, 0)},
    },
    .{
        .title = "Scrounge",
        .side = .runner,
        .code = 35004,
        .card_type = "Event",
        .subtypes = &.{"Double"},
        .cost = 1,

        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
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
                        .source_card = card.*,
                    
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
        }.play }},
    },
    .{
        .title = "Shred",
        .side = .runner,
        .code = 35005,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 1,
        .abilities = &.{runnerRunEventPlayAbility(.any_runnable, 0)},
    },
    .{ .title = "Clean Getaway", .side = .runner, .code = 35014, .card_type = "Event", .subtypes = &.{"Run"}, .cost = 3, .abilities = &.{runnerRunEventPlayAbility(.any_runnable, 0)}, .successful_run_effect = .draw_cards },
    .{
        .title = "Lie Low",
        .side = .runner,
        .code = 35015,
        .card_type = "Event",
        .subtypes = &.{"Double"},
        .cost = 1,

        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
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
                
                    .on_choice = &struct {
                        fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                            const cg = gameFromEffectContext(cctx);
                            const c_allocator = cg.arena.allocator();
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
                                        .prompt_type = try c_allocator.dupe(u8, "lie-low-tags"),
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
        }.play }},
    },
    .{
        .title = "Maintenance Access",
        .side = .runner,
        .code = 35016,
        .card_type = "Event",
        .subtypes = &.{ "Double", "Run" },
        .cost = 0,
        .abilities = &.{runnerRunEventPlayAbility(.archives_only, 1)},
    },
    .{
        .title = "Transfer of Wealth",
        .side = .runner,
        .code = 35017,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 0,
        .abilities = &.{runnerRunEventPlayAbility(.hq_only, 0)},
    },
    .{
        .title = "Illumination",
        .side = .runner,
        .code = 35025,
        .card_type = "Event",
        .subtypes = &.{"Run"},
        .cost = 0,
        .abilities = &.{runnerRunEventPlayAbility(.rd_only, 0)},
    },
    .{
        .title = "Ritual",
        .side = .runner,
        .code = 35026,
        .card_type = "Event",
        .cost = 0,

        .abilities = &.{.{ .is_play = true, .on_use = &struct {
            fn play(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
                const g = gameFromEffectContext(ctx);
                // "Draw 1 card for each [click] you have remaining."
                const clicks_remaining: u8 = @intCast(g.runner_click);
                if (clicks_remaining > 0) {
                    try drawCards(g, .runner, clicks_remaining);
                }
                g.decision_side = .runner;
                g.legal_actions = try runnerOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play }},
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
                            g.legal_actions = try runnerOpeningActionsForState(g.arena.allocator(), g);
                            return;
                        }
                        const source_card = prompt.source_card orelse return error.MissingSourceCard;
                        const host = findRunnerHardwareByCode(g, source_card.code orelse return error.MissingSourceCard) orelse return error.InvalidCardIndex;
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
                    try beginRunnerHostedCardPrompt(g, card.*, bling_on_choice);
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
            .label = "Return 2 hosted cards to HQ to access 1 random HQ card",
            .req = &struct {
                fn check(_: *const state.EffectContext, card: *const state.CardInstance) bool {
                    return card.hosted.len >= 2;
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
                            const source_card = prompt.source_card orelse return error.MissingSourceCard;
                            const host = findRunnerHardwareByCode(g, source_card.code orelse return error.MissingSourceCard) orelse return error.InvalidCardIndex;
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
                    if (!std.mem.eql(u8, run.server[0], "hq") or g.runner_successful_run_this_turn or g.corp_hand.items.len == 0) return;
                    try beginYesNoPrompt(g, .runner, "runner-host-confirm", card.*, detente_on_choice);
                    g.corp_prompt_state = .{
                        .prompt_type = try g.arena.allocator().dupe(u8, "waiting"),
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
            .label = "Host programs or install a hosted program",
            .req = &struct {
                fn check(ctx: *const state.EffectContext, card: *const state.CardInstance) bool {
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
            }.check,
            .on_use = &struct {
                fn use(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    const allocator = g.arena.allocator();
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
                    
                        .on_choice = &struct {
                            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                                const cg = gameFromEffectContext(cctx);
                                const c_allocator = cg.arena.allocator();
                                const prompt = cg.runner_prompt_state orelse return error.NoPromptState;
                                const source_card = prompt.source_card orelse return error.MissingSourceCard;
                                const host = findRunnerHardwareByCode(cg, source_card.code orelse return error.MissingSourceCard) orelse return error.InvalidCardIndex;
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
                                            .prompt_type = try c_allocator.dupe(u8, "runner-host-from-grip"),
                                            .choices = try c_choices.toOwnedSlice(c_allocator),
                                            .source_card = source_card,

                                            .on_choice = &@This().choice,
                                        };
                                        cg.decision_side = .runner;
                                        cg.legal_actions = try promptChoiceActions(c_allocator, .runner, cg.runner_prompt_state.?);
                                        return;
                                    }
                                    if (std.mem.eql(u8, choice_text, "Install a hosted program")) {
                                        var c_choices: std.ArrayList(state.PromptChoice) = .empty;
                                        defer c_choices.deinit(c_allocator);
                                        for (host.hosted, 0..) |hosted_card, idx| {
                                            if (!runnerHandInstallableByEffect(cg, hosted_card)) continue;
                                            try c_choices.append(c_allocator, .{
                                                .kind = .card,
                                                .text = try c_allocator.dupe(u8, hosted_card.title),
                                                .card = .{ .title = hosted_card.title, .printed_title = hosted_card.printed_title, .code = hosted_card.code, .side = .runner, .index = @intCast(idx) },
                                            });
                                        }
                                        if (c_choices.items.len == 0) return error.UnsupportedChoice;
                                        cg.runner_prompt_state = .{
                                            .prompt_type = try c_allocator.dupe(u8, "runner-hosted-install"),
                                            .choices = try c_choices.toOwnedSlice(c_allocator),
                                            .source_card = source_card,

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
                                            .prompt_type = try c_allocator.dupe(u8, "runner-host-from-grip"),
                                            .choices = try c_choices.toOwnedSlice(c_allocator),
                                            .source_card = source_card,

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
    .{ .title = "Hantu", .side = .runner, .code = 35008, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer", "Virus" }, .cost = 3, .strength = 2, .runner_install = .{ .kind = .program },
        .on_install = &struct {
            fn handle(_: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                card.virus_counter += 2;
            }
        }.handle,
    .abilities = &.{
        .{ .on_use = &encounterBreakHandler, .req = &isInEncounter, .credit_cost = 1, .break_count = 1 },
        .{ .on_use = &encounterPumpHandler, .req = &isInEncounter, .credit_cost = 0, .pump_amount = 2, .pump_can_use = &struct {
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
        .auto_take_credits = true,
        .initial_credit_counters = 6,
        .take_credits_amount = 1,
        .trash_on_empty = true,
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
            .handler = &struct {
                fn handle(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
                    const g = gameFromEffectContext(ctx);
                    card.credit_counter += 1;
                    g.systemMsg(.runner, card.code orelse 0, "Runner places 1 [credit] on {s}.", .{card.title});
                    if (card.credit_counter >= card.auto_trash_at_credits) {
                        g.runner_credit += card.credit_counter;
                        g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credits] and draw {d} card{s}.", .{
                            card.title,                                                                       card.credit_counter, card.draw_on_auto_trash,
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

const beginner_corp_deck_lines = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 },
    .{ .qty = 2, .card_code = 30069 },
    .{ .qty = 2, .card_code = 30070 },
    .{ .qty = 2, .card_code = 30037 },
    .{ .qty = 2, .card_code = 30071 },
    .{ .qty = 2, .card_code = 30045 },
    .{ .qty = 2, .card_code = 30064 },
    .{ .qty = 3, .card_code = 30075 },
    .{ .qty = 2, .card_code = 30040 },
    .{ .qty = 1, .card_code = 30042 },
    .{ .qty = 2, .card_code = 30039 },
    .{ .qty = 3, .card_code = 30072 },
    .{ .qty = 2, .card_code = 30046 },
    .{ .qty = 2, .card_code = 30074 },
    .{ .qty = 2, .card_code = 30047 },
    .{ .qty = 2, .card_code = 30073 },
};

const beginner_runner_deck_lines = [_]DeckLine{
    .{ .qty = 2, .card_code = 30020 },
    .{ .qty = 3, .card_code = 30028 },
    .{ .qty = 2, .card_code = 30029 },
    .{ .qty = 3, .card_code = 30030 },
    .{ .qty = 2, .card_code = 30012 },
    .{ .qty = 2, .card_code = 30021 },
    .{ .qty = 1, .card_code = 30013 },
    .{ .qty = 1, .card_code = 30014 },
    .{ .qty = 1, .card_code = 30018 },
    .{ .qty = 2, .card_code = 30033 },
    .{ .qty = 2, .card_code = 30027 },
    .{ .qty = 1, .card_code = 30034 },
    .{ .qty = 2, .card_code = 30015 },
    .{ .qty = 2, .card_code = 30006 },
    .{ .qty = 2, .card_code = 30032 },
    .{ .qty = 2, .card_code = 30026 },
};

const intermediate_corp_deck_lines = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 },
    .{ .qty = 2, .card_code = 30069 },
    .{ .qty = 2, .card_code = 30068 },
    .{ .qty = 2, .card_code = 30056 },
    .{ .qty = 2, .card_code = 30057 },
    .{ .qty = 1, .card_code = 30065 },
    .{ .qty = 1, .card_code = 30058 },
    .{ .qty = 2, .card_code = 30054 },
    .{ .qty = 2, .card_code = 30070 },
    .{ .qty = 2, .card_code = 30037 },
    .{ .qty = 2, .card_code = 30071 },
    .{ .qty = 2, .card_code = 30045 },
    .{ .qty = 2, .card_code = 30064 },
    .{ .qty = 3, .card_code = 30075 },
    .{ .qty = 2, .card_code = 30040 },
    .{ .qty = 1, .card_code = 30042 },
    .{ .qty = 2, .card_code = 30039 },
    .{ .qty = 3, .card_code = 30072 },
    .{ .qty = 2, .card_code = 30046 },
    .{ .qty = 2, .card_code = 30074 },
    .{ .qty = 2, .card_code = 30047 },
    .{ .qty = 2, .card_code = 30073 },
};

const intermediate_runner_deck_lines = [_]DeckLine{
    .{ .qty = 2, .card_code = 30020 },
    .{ .qty = 3, .card_code = 30028 },
    .{ .qty = 2, .card_code = 30029 },
    .{ .qty = 2, .card_code = 30011 },
    .{ .qty = 2, .card_code = 30002 },
    .{ .qty = 2, .card_code = 30022 },
    .{ .qty = 2, .card_code = 30024 },
    .{ .qty = 2, .card_code = 30008 },
    .{ .qty = 3, .card_code = 30030 },
    .{ .qty = 2, .card_code = 30012 },
    .{ .qty = 2, .card_code = 30021 },
    .{ .qty = 1, .card_code = 30013 },
    .{ .qty = 1, .card_code = 30014 },
    .{ .qty = 1, .card_code = 30018 },
    .{ .qty = 2, .card_code = 30033 },
    .{ .qty = 2, .card_code = 30027 },
    .{ .qty = 1, .card_code = 30034 },
    .{ .qty = 2, .card_code = 30015 },
    .{ .qty = 2, .card_code = 30006 },
    .{ .qty = 2, .card_code = 30032 },
    .{ .qty = 2, .card_code = 30026 },
};

pub const system_gateway_beginner = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{
        .identity_code = 30077,
        .deck_lines = &beginner_corp_deck_lines,
    },
    .runner = .{
        .identity_code = 30076,
        .deck_lines = &beginner_runner_deck_lines,
    },
};

pub const system_gateway_intermediate = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{
        .identity_code = 30077,
        .deck_lines = &intermediate_corp_deck_lines,
    },
    .runner = .{
        .identity_code = 30076,
        .deck_lines = &intermediate_runner_deck_lines,
    },
};

const advanced_corp_deck_lines = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 }, // Offworld Office
    .{ .qty = 2, .card_code = 30069 }, // Send a Message
    .{ .qty = 2, .card_code = 30052 }, // Tomorrow's Headline
    .{ .qty = 1, .card_code = 30060 }, // Above the Law
    .{ .qty = 1, .card_code = 30070 }, // Superconducting Hub
    .{ .qty = 2, .card_code = 30037 }, // Nico Campaign
    .{ .qty = 2, .card_code = 30071 }, // Regolith Mining License
    .{ .qty = 2, .card_code = 30045 }, // Urtica Cipher
    .{ .qty = 2, .card_code = 30064 }, // Government Subsidy
    .{ .qty = 2, .card_code = 30075 }, // Hedge Fund
    .{ .qty = 2, .card_code = 30040 }, // Seamless Launch
    .{ .qty = 2, .card_code = 30041 }, // Sprint
    .{ .qty = 1, .card_code = 30048 }, // Hansei Review
    .{ .qty = 1, .card_code = 30042 }, // Manegarm Skunkworks
    .{ .qty = 1, .card_code = 30050 }, // Anoetic Void
    .{ .qty = 2, .card_code = 30039 }, // Brân 1.0
    .{ .qty = 2, .card_code = 30072 }, // Palisade
    .{ .qty = 2, .card_code = 30055 }, // Ping
    .{ .qty = 2, .card_code = 30062 }, // Ballista
    .{ .qty = 2, .card_code = 30074 }, // Whitespace
    .{ .qty = 2, .card_code = 30047 }, // Karunā
    .{ .qty = 2, .card_code = 30073 }, // Tithe
};

const advanced_runner_deck_lines = [_]DeckLine{
    .{ .qty = 2, .card_code = 30020 }, // Creative Commission
    .{ .qty = 3, .card_code = 30028 }, // Jailbreak
    .{ .qty = 2, .card_code = 30029 }, // Overclock
    .{ .qty = 2, .card_code = 30011 }, // Mutual Favor
    .{ .qty = 2, .card_code = 30002 }, // Wildcat Strike
    .{ .qty = 3, .card_code = 30030 }, // Sure Gamble
    .{ .qty = 2, .card_code = 30012 }, // Tread Lightly
    .{ .qty = 2, .card_code = 30021 }, // VRcation
    .{ .qty = 1, .card_code = 30013 }, // Docklands Pass
    .{ .qty = 1, .card_code = 30031 }, // T400 Memory Diamond
    .{ .qty = 1, .card_code = 30018 }, // Red Team
    .{ .qty = 2, .card_code = 30033 }, // Smartware Distributor
    .{ .qty = 2, .card_code = 30027 }, // Telework Contract
    .{ .qty = 1, .card_code = 30034 }, // Verbal Plasticity
    .{ .qty = 2, .card_code = 30005 }, // Buzzsaw
    .{ .qty = 2, .card_code = 30025 }, // Echelon
    .{ .qty = 2, .card_code = 30016 }, // Marjanah
    .{ .qty = 2, .card_code = 30024 }, // Conduit
    .{ .qty = 2, .card_code = 30008 }, // Leech
};

pub const system_gateway_advanced = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{
        .identity_code = 30077,
        .deck_lines = &advanced_corp_deck_lines,
    },
    .runner = .{
        .identity_code = 30076,
        .deck_lines = &advanced_runner_deck_lines,
    },
};

const complete_corp_deck_lines = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 }, // Offworld Office
    .{ .qty = 2, .card_code = 30069 }, // Send a Message
    .{ .qty = 1, .card_code = 30052 }, // Tomorrow's Headline
    .{ .qty = 1, .card_code = 30060 }, // Above the Law
    .{ .qty = 1, .card_code = 30036 }, // Luminal Transubstantiation
    .{ .qty = 1, .card_code = 30044 }, // Longevity Serum
    .{ .qty = 2, .card_code = 30037 }, // Nico Campaign
    .{ .qty = 1, .card_code = 30071 }, // Regolith Mining License
    .{ .qty = 1, .card_code = 30045 }, // Urtica Cipher
    .{ .qty = 1, .card_code = 30061 }, // Clearinghouse
    .{ .qty = 1, .card_code = 30053 }, // Spin Doctor
    .{ .qty = 2, .card_code = 30075 }, // Hedge Fund
    .{ .qty = 1, .card_code = 30040 }, // Seamless Launch
    .{ .qty = 1, .card_code = 30041 }, // Sprint
    .{ .qty = 1, .card_code = 30048 }, // Hansei Review
    .{ .qty = 1, .card_code = 30049 }, // Neurospike
    .{ .qty = 1, .card_code = 30042 }, // Manegarm Skunkworks
    .{ .qty = 1, .card_code = 30050 }, // Anoetic Void
    .{ .qty = 1, .card_code = 30066 }, // Malapert Data Vault
    .{ .qty = 2, .card_code = 30039 }, // Brân 1.0
    .{ .qty = 2, .card_code = 30072 }, // Palisade
    .{ .qty = 2, .card_code = 30063 }, // Pharos
    .{ .qty = 2, .card_code = 30055 }, // Ping
    .{ .qty = 1, .card_code = 30062 }, // Ballista
    .{ .qty = 2, .card_code = 30074 }, // Whitespace
    .{ .qty = 2, .card_code = 30047 }, // Karunā
    .{ .qty = 2, .card_code = 30073 }, // Tithe
};

const complete_runner_deck_lines = [_]DeckLine{
    .{ .qty = 2, .card_code = 30020 }, // Creative Commission
    .{ .qty = 3, .card_code = 30028 }, // Jailbreak
    .{ .qty = 2, .card_code = 30029 }, // Overclock
    .{ .qty = 2, .card_code = 30011 }, // Mutual Favor
    .{ .qty = 2, .card_code = 30002 }, // Wildcat Strike
    .{ .qty = 3, .card_code = 30030 }, // Sure Gamble
    .{ .qty = 2, .card_code = 30012 }, // Tread Lightly
    .{ .qty = 2, .card_code = 30021 }, // VRcation
    .{ .qty = 1, .card_code = 30013 }, // Docklands Pass
    .{ .qty = 1, .card_code = 30031 }, // T400 Memory Diamond
    .{ .qty = 1, .card_code = 30018 }, // Red Team
    .{ .qty = 1, .card_code = 30033 }, // Smartware Distributor
    .{ .qty = 2, .card_code = 30027 }, // Telework Contract
    .{ .qty = 1, .card_code = 30034 }, // Verbal Plasticity
    .{ .qty = 1, .card_code = 30009 }, // Cookbook
    .{ .qty = 2, .card_code = 30005 }, // Buzzsaw
    .{ .qty = 2, .card_code = 30025 }, // Echelon
    .{ .qty = 2, .card_code = 30016 }, // Marjanah
    .{ .qty = 2, .card_code = 30024 }, // Conduit
    .{ .qty = 2, .card_code = 30008 }, // Leech
    .{ .qty = 2, .card_code = 30007 }, // Fermenter
    .{ .qty = 1, .card_code = 30023 }, // Pantograph
    .{ .qty = 1, .card_code = 30004 }, // Botulus
    .{ .qty = 1, .card_code = 30017 }, // Tranquilizer
};

pub const system_gateway_complete = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{
        .identity_code = 30077,
        .deck_lines = &complete_corp_deck_lines,
    },
    .runner = .{
        .identity_code = 30076,
        .deck_lines = &complete_runner_deck_lines,
    },
};

// Identity-specific matchups for parity testing
pub const system_gateway_hb = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30035, .deck_lines = &complete_corp_deck_lines }, // HB: Precision Design
    .runner = .{ .identity_code = 30076, .deck_lines = &complete_runner_deck_lines },
};
pub const system_gateway_jinteki = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30043, .deck_lines = &complete_corp_deck_lines }, // Jinteki: Restoring Humanity
    .runner = .{ .identity_code = 30076, .deck_lines = &complete_runner_deck_lines },
};
pub const system_gateway_nbn = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30051, .deck_lines = &complete_corp_deck_lines }, // NBN: Reality Plus
    .runner = .{ .identity_code = 30076, .deck_lines = &complete_runner_deck_lines },
};
pub const system_gateway_weyland = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30059, .deck_lines = &complete_corp_deck_lines }, // Weyland: Built to Last
    .runner = .{ .identity_code = 30076, .deck_lines = &complete_runner_deck_lines },
};
pub const system_gateway_zahya = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30077, .deck_lines = &complete_corp_deck_lines },
    .runner = .{ .identity_code = 30010, .deck_lines = &complete_runner_deck_lines }, // Zahya
};
pub const system_gateway_loup = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30077, .deck_lines = &complete_corp_deck_lines },
    .runner = .{ .identity_code = 30001, .deck_lines = &complete_runner_deck_lines }, // Loup
};
pub const system_gateway_tao = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30077, .deck_lines = &complete_corp_deck_lines },
    .runner = .{ .identity_code = 30019, .deck_lines = &complete_runner_deck_lines }, // Tao
};

// Full pack deck: includes Ansel 1.0 and Carnivore (swaps some duplicates)
// Full pack: complete deck + Ansel 1.0 in corp, + Carnivore in runner (replacing 1 Fermenter)
// Must match Clojure oracle's fullpack deck construction exactly.
const fullpack_corp_deck_lines = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 }, // Offworld Office
    .{ .qty = 2, .card_code = 30069 }, // Send a Message
    .{ .qty = 1, .card_code = 30052 }, // Tomorrow's Headline
    .{ .qty = 1, .card_code = 30060 }, // Above the Law
    .{ .qty = 1, .card_code = 30036 }, // Luminal Transubstantiation
    .{ .qty = 1, .card_code = 30044 }, // Longevity Serum
    .{ .qty = 2, .card_code = 30037 }, // Nico Campaign
    .{ .qty = 1, .card_code = 30071 }, // Regolith Mining License
    .{ .qty = 1, .card_code = 30045 }, // Urtica Cipher
    .{ .qty = 1, .card_code = 30061 }, // Clearinghouse
    .{ .qty = 1, .card_code = 30053 }, // Spin Doctor
    .{ .qty = 2, .card_code = 30075 }, // Hedge Fund
    .{ .qty = 1, .card_code = 30040 }, // Seamless Launch
    .{ .qty = 1, .card_code = 30041 }, // Sprint
    .{ .qty = 1, .card_code = 30048 }, // Hansei Review
    .{ .qty = 1, .card_code = 30049 }, // Neurospike
    .{ .qty = 1, .card_code = 30042 }, // Manegarm Skunkworks
    .{ .qty = 1, .card_code = 30050 }, // Anoetic Void
    .{ .qty = 1, .card_code = 30066 }, // Malapert Data Vault
    .{ .qty = 2, .card_code = 30039 }, // Brân 1.0
    .{ .qty = 2, .card_code = 30072 }, // Palisade
    .{ .qty = 2, .card_code = 30063 }, // Pharos
    .{ .qty = 2, .card_code = 30055 }, // Ping
    .{ .qty = 1, .card_code = 30062 }, // Ballista
    .{ .qty = 2, .card_code = 30074 }, // Whitespace
    .{ .qty = 2, .card_code = 30047 }, // Karunā
    .{ .qty = 2, .card_code = 30073 }, // Tithe
    .{ .qty = 1, .card_code = 30038 }, // Ansel 1.0 (appended to match Clojure conj order)
};

const fullpack_runner_deck_lines = [_]DeckLine{
    .{ .qty = 2, .card_code = 30020 }, // Creative Commission
    .{ .qty = 3, .card_code = 30028 }, // Jailbreak
    .{ .qty = 2, .card_code = 30029 }, // Overclock
    .{ .qty = 2, .card_code = 30011 }, // Mutual Favor
    .{ .qty = 2, .card_code = 30002 }, // Wildcat Strike
    .{ .qty = 3, .card_code = 30030 }, // Sure Gamble
    .{ .qty = 2, .card_code = 30012 }, // Tread Lightly
    .{ .qty = 2, .card_code = 30021 }, // VRcation
    .{ .qty = 1, .card_code = 30013 }, // Docklands Pass
    .{ .qty = 1, .card_code = 30031 }, // T400 Memory Diamond
    .{ .qty = 1, .card_code = 30018 }, // Red Team
    .{ .qty = 1, .card_code = 30033 }, // Smartware Distributor
    .{ .qty = 2, .card_code = 30027 }, // Telework Contract
    .{ .qty = 1, .card_code = 30034 }, // Verbal Plasticity
    .{ .qty = 1, .card_code = 30009 }, // Cookbook
    .{ .qty = 2, .card_code = 30005 }, // Buzzsaw
    .{ .qty = 2, .card_code = 30025 }, // Echelon
    .{ .qty = 2, .card_code = 30016 }, // Marjanah
    .{ .qty = 2, .card_code = 30024 }, // Conduit
    .{ .qty = 2, .card_code = 30008 }, // Leech
    .{ .qty = 1, .card_code = 30007 }, // Fermenter (reduced from 2 to fit Carnivore)
    .{ .qty = 1, .card_code = 30023 }, // Pantograph
    .{ .qty = 1, .card_code = 30004 }, // Botulus
    .{ .qty = 1, .card_code = 30017 }, // Tranquilizer
    .{ .qty = 1, .card_code = 30003 }, // Carnivore (appended to match Clojure conj order)
};

pub const system_gateway_fullpack = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30077, .deck_lines = &fullpack_corp_deck_lines },
    .runner = .{ .identity_code = 30019, .deck_lines = &fullpack_runner_deck_lines }, // Tao
};

// [SG Only] Bounce Rate Metrics (NBN) vs 'Laxin' Loup (Anarch)
// 1st @ Galaxy of Games GNK
const gnk_corp_deck_lines = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 }, // Offworld Office
    .{ .qty = 2, .card_code = 30068 }, // Orbital Superiority
    .{ .qty = 2, .card_code = 30069 }, // Send a Message
    .{ .qty = 1, .card_code = 30052 }, // Tomorrow's Headline
    .{ .qty = 3, .card_code = 30071 }, // Regolith Mining License
    .{ .qty = 3, .card_code = 30053 }, // Spin Doctor
    .{ .qty = 3, .card_code = 30062 }, // Ballista
    .{ .qty = 2, .card_code = 30054 }, // Funhouse
    .{ .qty = 3, .card_code = 30072 }, // Palisade
    .{ .qty = 3, .card_code = 30055 }, // Ping
    .{ .qty = 3, .card_code = 30074 }, // Whitespace
    .{ .qty = 3, .card_code = 30075 }, // Hedge Fund
    .{ .qty = 3, .card_code = 30056 }, // Predictive Planogram
    .{ .qty = 3, .card_code = 30057 }, // Public Trail
    .{ .qty = 3, .card_code = 30065 }, // Retribution
    .{ .qty = 2, .card_code = 30058 }, // AMAZE Amusements
    .{ .qty = 2, .card_code = 30042 }, // Manegarm Skunkworks
};

const gnk_runner_deck_lines = [_]DeckLine{
    .{ .qty = 3, .card_code = 30028 }, // Jailbreak
    .{ .qty = 3, .card_code = 30030 }, // Sure Gamble
    .{ .qty = 1, .card_code = 30012 }, // Tread Lightly
    .{ .qty = 2, .card_code = 30021 }, // VRcation
    .{ .qty = 3, .card_code = 30002 }, // Wildcat Strike
    .{ .qty = 2, .card_code = 30003 }, // Carnivore
    .{ .qty = 1, .card_code = 30013 }, // Docklands Pass
    .{ .qty = 1, .card_code = 30031 }, // T400 Memory Diamond
    .{ .qty = 3, .card_code = 30004 }, // Botulus
    .{ .qty = 2, .card_code = 30005 }, // Buzzsaw
    .{ .qty = 1, .card_code = 30015 }, // Carmen
    .{ .qty = 2, .card_code = 30006 }, // Cleaver
    .{ .qty = 1, .card_code = 30024 }, // Conduit
    .{ .qty = 3, .card_code = 30007 }, // Fermenter
    .{ .qty = 2, .card_code = 30008 }, // Leech
    .{ .qty = 2, .card_code = 30032 }, // Mayfly
    .{ .qty = 3, .card_code = 30009 }, // Cookbook
    .{ .qty = 1, .card_code = 30033 }, // Smartware Distributor
    .{ .qty = 1, .card_code = 30027 }, // Telework Contract
    .{ .qty = 3, .card_code = 30034 }, // Verbal Plasticity
};

pub const gnk_nbn_vs_loup = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30051, .deck_lines = &gnk_corp_deck_lines },
    .runner = .{ .identity_code = 30001, .deck_lines = &gnk_runner_deck_lines },
};

// Elevation HB: LEO Construction vs Catalyst (SG runner)
// Uses HB Elevation cards + SG filler for a legal 40-card corp deck
const elevation_hb_corp_deck = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 }, // Offworld Office
    .{ .qty = 2, .card_code = 30069 }, // Send a Message
    .{ .qty = 2, .card_code = 35037 }, // Aggressive Trendsetting
    .{ .qty = 2, .card_code = 35038 }, // Project Ingatan
    .{ .qty = 2, .card_code = 35040 }, // Otto Campaign
    .{ .qty = 2, .card_code = 35039 }, // Humanoid Resources
    .{ .qty = 2, .card_code = 35041 }, // Bumi 1.0
    .{ .qty = 2, .card_code = 35042 }, // Scatter Field
    .{ .qty = 3, .card_code = 30075 }, // Hedge Fund
    .{ .qty = 2, .card_code = 35043 }, // Nanomanagement
    .{ .qty = 2, .card_code = 35044 }, // Top-Down Solutions
    .{ .qty = 2, .card_code = 35045 }, // Mercia B4LL4RD
    .{ .qty = 3, .card_code = 30072 }, // Palisade
    .{ .qty = 2, .card_code = 30039 }, // Brân 1.0
    .{ .qty = 2, .card_code = 30037 }, // Nico Campaign
    .{ .qty = 2, .card_code = 30040 }, // Seamless Launch
};
const elevation_hb_runner_deck = [_]DeckLine{
    .{ .qty = 3, .card_code = 30028 }, // Jailbreak
    .{ .qty = 3, .card_code = 30030 }, // Sure Gamble
    .{ .qty = 3, .card_code = 30002 }, // Wildcat Strike
    .{ .qty = 2, .card_code = 30021 }, // VRcation
    .{ .qty = 1, .card_code = 30012 }, // Tread Lightly
    .{ .qty = 1, .card_code = 30023 }, // Pantograph
    .{ .qty = 2, .card_code = 30005 }, // Buzzsaw
    .{ .qty = 2, .card_code = 30006 }, // Cleaver
    .{ .qty = 2, .card_code = 30025 }, // Echelon
    .{ .qty = 2, .card_code = 30026 }, // Unity
    .{ .qty = 2, .card_code = 30024 }, // Conduit
    .{ .qty = 2, .card_code = 30008 }, // Leech
    .{ .qty = 2, .card_code = 30007 }, // Fermenter
    .{ .qty = 2, .card_code = 30033 }, // Smartware Distributor
    .{ .qty = 2, .card_code = 30034 }, // Verbal Plasticity
    .{ .qty = 2, .card_code = 30027 }, // Telework Contract
    .{ .qty = 1, .card_code = 30031 }, // T400 Memory Diamond
};
pub const elevation_hb = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 35035, .deck_lines = &elevation_hb_corp_deck },
    .runner = .{ .identity_code = 30076, .deck_lines = &elevation_hb_runner_deck }, // Catalyst
};

// Elevation Weyland: Zwicky vs Catalyst
const elevation_weyland_corp_deck = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 }, // Offworld Office
    .{ .qty = 3, .card_code = 35070 }, // Greenmail
    .{ .qty = 2, .card_code = 35071 }, // Off the Books
    .{ .qty = 2, .card_code = 30069 }, // Send a Message
    .{ .qty = 2, .card_code = 35072 }, // Anthill Excavation Contract
    .{ .qty = 2, .card_code = 35073 }, // Plutus
    .{ .qty = 2, .card_code = 35074 }, // Biawak
    .{ .qty = 2, .card_code = 35075 }, // Kessleroid
    .{ .qty = 2, .card_code = 35076 }, // Syailendra
    .{ .qty = 3, .card_code = 30075 }, // Hedge Fund
    .{ .qty = 2, .card_code = 35077 }, // Key Performance Indicators
    .{ .qty = 2, .card_code = 35078 }, // Measured Response
    .{ .qty = 2, .card_code = 35081 }, // Petty Cash
    .{ .qty = 3, .card_code = 30072 }, // Palisade
    .{ .qty = 2, .card_code = 30037 }, // Nico Campaign
};
pub const elevation_weyland = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 35069, .deck_lines = &elevation_weyland_corp_deck },
    .runner = .{ .identity_code = 30076, .deck_lines = &elevation_hb_runner_deck }, // Catalyst (shared)
};

// Elevation NBN: Nebula vs Catalyst
const elevation_nbn_corp_deck = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 }, // Offworld Office
    .{ .qty = 2, .card_code = 35059 }, // Embedded Reporting
    .{ .qty = 2, .card_code = 35060 }, // Next Big Thing
    .{ .qty = 2, .card_code = 30069 }, // Send a Message
    .{ .qty = 2, .card_code = 35061 }, // Idiosyncresis
    .{ .qty = 2, .card_code = 35062 }, // Public Access Plaza
    .{ .qty = 2, .card_code = 35063 }, // Doomscroll
    .{ .qty = 2, .card_code = 35064 }, // N-Pot
    .{ .qty = 3, .card_code = 30075 }, // Hedge Fund
    .{ .qty = 2, .card_code = 35065 }, // Bigger Picture
    .{ .qty = 2, .card_code = 35067 }, // Touch-ups
    .{ .qty = 3, .card_code = 30072 }, // Palisade
    .{ .qty = 2, .card_code = 30055 }, // Ping
    .{ .qty = 2, .card_code = 30037 }, // Nico Campaign
    .{ .qty = 2, .card_code = 30040 }, // Seamless Launch
};
pub const elevation_nbn = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 35057, .deck_lines = &elevation_nbn_corp_deck },
    .runner = .{ .identity_code = 30076, .deck_lines = &elevation_hb_runner_deck }, // Catalyst (shared)
};

// Elevation Jinteki: AU Co. vs Catalyst
const elevation_jinteki_corp_deck = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 }, // Offworld Office
    .{ .qty = 2, .card_code = 35048 }, // Proprionegation
    .{ .qty = 2, .card_code = 35049 }, // Sericulture Expansion
    .{ .qty = 2, .card_code = 30069 }, // Send a Message
    .{ .qty = 2, .card_code = 35050 }, // Byte!
    .{ .qty = 2, .card_code = 35051 }, // Phật Gioan
    .{ .qty = 2, .card_code = 35052 }, // Empiricist
    .{ .qty = 2, .card_code = 35054 }, // Semak-samun
    .{ .qty = 3, .card_code = 30075 }, // Hedge Fund
    .{ .qty = 2, .card_code = 35055 }, // Peer Review
    .{ .qty = 2, .card_code = 35056 }, // Mitra Aman
    .{ .qty = 3, .card_code = 30072 }, // Palisade
    .{ .qty = 2, .card_code = 30037 }, // Nico Campaign
    .{ .qty = 2, .card_code = 30040 }, // Seamless Launch
    .{ .qty = 2, .card_code = 30045 }, // Urtica Cipher
};
pub const elevation_jinteki = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 35046, .deck_lines = &elevation_jinteki_corp_deck },
    .runner = .{ .identity_code = 30076, .deck_lines = &elevation_hb_runner_deck }, // Catalyst (shared)
};

// Elevation neutral ICE test: uses Flyswatter + Lamplighter + Kessleroid
const elevation_neutral_corp_deck = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 }, // Offworld Office
    .{ .qty = 2, .card_code = 35070 }, // Greenmail
    .{ .qty = 2, .card_code = 30069 }, // Send a Message
    .{ .qty = 2, .card_code = 30068 }, // Orbital Superiority
    .{ .qty = 3, .card_code = 35079 }, // Flyswatter
    .{ .qty = 3, .card_code = 35080 }, // Lamplighter
    .{ .qty = 3, .card_code = 35075 }, // Kessleroid
    .{ .qty = 3, .card_code = 30072 }, // Palisade
    .{ .qty = 3, .card_code = 30075 }, // Hedge Fund
    .{ .qty = 2, .card_code = 35081 }, // Petty Cash
    .{ .qty = 2, .card_code = 30037 }, // Nico Campaign
    .{ .qty = 2, .card_code = 30071 }, // Regolith Mining License
    .{ .qty = 2, .card_code = 30040 }, // Seamless Launch
    .{ .qty = 2, .card_code = 35082 }, // Mahkota Langit Grid
};
pub const elevation_neutral = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30059, .deck_lines = &elevation_neutral_corp_deck }, // Weyland BTL
    .runner = .{ .identity_code = 30076, .deck_lines = &elevation_hb_runner_deck }, // Catalyst
};

// Elevation Runner matchup: Catalyst vs SG Corp with Elevation runner cards
const elevation_runner_deck = [_]DeckLine{
    // 30 cards for individual parity tests - includes Elevation runner cards
    .{ .qty = 3, .card_code = 30030 }, // Sure Gamble (3)
    .{ .qty = 2, .card_code = 35026 }, // Ritual (5)
    .{ .qty = 2, .card_code = 35014 }, // Clean Getaway (7)
    .{ .qty = 3, .card_code = 30028 }, // Jailbreak (10)
    .{ .qty = 1, .card_code = 35006 }, // Bling (11)
    .{ .qty = 2, .card_code = 35008 }, // Hantu (13)
    .{ .qty = 2, .card_code = 35009 }, // Rising Tide (15)
    .{ .qty = 2, .card_code = 35020 }, // Sang Kancil (17)
    .{ .qty = 2, .card_code = 35032 }, // Principia (19)
    .{ .qty = 2, .card_code = 35022 }, // Open Market (21)
    .{ .qty = 2, .card_code = 35011 }, // Rent Rioters (23)
    .{ .qty = 2, .card_code = 35034 }, // Side Hustle (25)
    .{ .qty = 2, .card_code = 35003 }, // Charm Offensive (27)
    .{ .qty = 2, .card_code = 30033 }, // Smartware Distributor (29)
    .{ .qty = 1, .card_code = 30031 }, // T400 Memory Diamond (30)
};
pub const elevation_runner = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30059, .deck_lines = &elevation_neutral_corp_deck }, // BTL
    .runner = .{ .identity_code = 30076, .deck_lines = &elevation_runner_deck }, // Catalyst
};

// Second Elevation Runner matchup with remaining runner cards
const elevation_runner2_deck = [_]DeckLine{
    .{ .qty = 3, .card_code = 30030 }, // Sure Gamble (3)
    .{ .qty = 3, .card_code = 30028 }, // Jailbreak (6)
    .{ .qty = 1, .card_code = 35007 }, // Gourmand (7)
    .{ .qty = 1, .card_code = 35010 }, // Cacophony (8)
    .{ .qty = 1, .card_code = 35018 }, // Detente (9)
    .{ .qty = 1, .card_code = 35019 }, // Maglectric Rapid (10)
    .{ .qty = 1, .card_code = 35021 }, // Fransofia Ward (11)
    .{ .qty = 1, .card_code = 35027 }, // GAMEDRAGON Pro (12)
    .{ .qty = 1, .card_code = 35028 }, // Madani (13)
    .{ .qty = 2, .card_code = 35029 }, // Azimat (15)
    .{ .qty = 2, .card_code = 35030 }, // Chromatophores (17)
    .{ .qty = 2, .card_code = 35031 }, // Devadatta Drone (19)
    .{ .qty = 1, .card_code = 35033 }, // "Knickknack" O'Brian (20)
    .{ .qty = 2, .card_code = 35008 }, // Hantu (22)
    .{ .qty = 2, .card_code = 35020 }, // Sang Kancil (24)
    .{ .qty = 3, .card_code = 30033 }, // Smartware Distributor (27)
    .{ .qty = 2, .card_code = 35022 }, // Open Market (29)
    .{ .qty = 1, .card_code = 30031 }, // T400 Memory Diamond (30)
};
pub const elevation_runner2 = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30059, .deck_lines = &elevation_neutral_corp_deck }, // BTL
    .runner = .{ .identity_code = 30076, .deck_lines = &elevation_runner2_deck }, // Catalyst
};

pub fn lookupCardSpecByCode(card_code: u32) ?CardSpec {
    for (all_cards) |spec| {
        if (spec.code == card_code) return spec;
    }
    return null;
}

const MutableServer = struct {
    name: []const u8,
    ices: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    content: std.ArrayListUnmanaged(state.CardInstance) = .empty,
};

pub const LogEntry = struct {
    side: state.Side,
    text: []const u8,
    card_code: u32, // 0 = no associated card
};

pub const Game = struct {
    arena: std.heap.ArenaAllocator,
    backing_allocator: std.mem.Allocator,

    // --- Game log (engine-level, like Clojure's system-msg) ---
    log_entries: std.ArrayListUnmanaged(LogEntry) = .empty,

    // --- Internal card collections (source of truth) ---
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

    // --- Internal scalar state (source of truth) ---
    // Game-level
    format: []const u8 = "",
    seed: u64 = 0,
    rng_seed: ?i64 = null,
    active_player: state.Side = .corp,
    turn: u16 = 0,
    end_turn: bool = true,
    run: ?state.RunState = null,
    runner_successful_run_last_turn: bool = false,
    runner_successful_run_this_turn: bool = false,
    turn_events: state.TurnEvents = .{},
    game_over: bool = false,
    winner: ?state.Side = null,
    pending_install: ?state.PendingInstall = null,
    pending_access: ?PendingAccess = null,
    corp_phase_12: bool = false,
    last_scored_server_index: ?usize = null, // Server from which last agenda was scored
    // cannot_score_agendas_this_turn replaced by floating effect .prevent_score
    tao_first_ice: ?[]const u8 = null, // Tao: first ICE selection (server_idx|ice_idx|title)
    pending_effects: std.ArrayListUnmanaged(PendingEffect) = .empty, // Async effect continuation queue
    floating_effects: std.ArrayListUnmanaged(state.FloatingEffect) = .empty, // Duration-scoped runtime effects
    pending_sprint_selections: std.ArrayListUnmanaged([]const u8) = .empty, // Sprint batched card selections
    runner_install_context: ?RunnerInstallContext = null,

    // Corp scalars
    corp_identity: state.CardInstance = undefined,
    corp_basic_action_card: state.CardInstance = undefined,
    corp_click: u8 = 0,
    corp_click_per_turn: u8 = 3,
    corp_credit: u16 = 5,
    corp_agenda_point: u8 = 0,
    corp_agenda_point_req: u8 = 7,
    corp_hand_size: state.HandSize = .{ .base = 5, .total = 5 },
    corp_bad_publicity: ?state.BadPublicity = .{ .base = 0, .additional = 0 },
    corp_keep: state.KeepState = .undecided,
    corp_prompt_state: ?state.PromptState = null,

    // Runner scalars
    runner_identity: state.CardInstance = undefined,
    runner_basic_action_card: state.CardInstance = undefined,
    runner_click: u8 = 0,
    runner_click_per_turn: u8 = 4,
    runner_credit: u16 = 5,
    runner_agenda_point: u8 = 0,
    runner_agenda_point_req: u8 = 7,
    runner_hand_size: state.HandSize = .{ .base = 5, .total = 5 },
    runner_run_credit: u16 = 0,
    runner_link: u8 = 0,
    runner_tag: ?state.TagState = .{ .base = 0, .total = 0, .is_tagged = false },
    runner_memory: ?state.MemoryState = .{ .base = 4, .available = 4, .used = 0 },
    runner_brain_damage: u8 = 0,
    runner_keep: state.KeepState = .undecided,
    runner_prompt_state: ?state.PromptState = null,

    // Decision state
    decision_side: state.Side = .corp,
    legal_actions: []const state.LegalAction = &.{},

    // Remote server counter (monotonically increasing, never resets on server removal)
    next_remote_number: usize = 1,

    // Instance ID allocator (monotonically increasing, never reused)
    next_instance_id: u32 = 1,

    // Typed effect context (replaces @ptrCast to anyopaque)
    effect_ctx: state.EffectContext = .{ .game_ptr = undefined },

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
        self.pending_effects.deinit(self.backing_allocator);
        self.floating_effects.deinit(self.backing_allocator);
        self.pending_sprint_selections.deinit(self.backing_allocator);
        for (self.log_entries.items) |entry| {
            self.backing_allocator.free(entry.text);
        }
        self.log_entries.deinit(self.backing_allocator);
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn systemMsg(self: *Game, side: state.Side, card_code: u32, comptime fmt: []const u8, args: anytype) void {
        const text = std.fmt.allocPrint(self.backing_allocator, fmt, args) catch return;
        self.log_entries.append(self.backing_allocator, .{
            .side = side,
            .text = text,
            .card_code = card_code,
        }) catch {
            self.backing_allocator.free(text);
        };
    }

    pub fn hasInstalledCards(self: *const Game) bool {
        return countInstalledCards(self.corp_servers.items) > 0;
    }

    pub fn toSnapshot(self: *Game) !state.GameSnapshot {
        refreshDerivedStates(self);
        const allocator = self.arena.allocator();

        // Deep clone servers
        const servers = try allocator.alloc(state.ServerSlot, self.corp_servers.items.len);
        for (self.corp_servers.items, 0..) |server, idx| {
            const ice_copy = try allocator.alloc(state.CardInstance, server.ices.items.len);
            const content_copy = try allocator.alloc(state.CardInstance, server.content.items.len);
            for (server.ices.items, 0..) |card, i| ice_copy[i] = try deepCloneCard(allocator, card);
            for (server.content.items, 0..) |card, i| content_copy[i] = try deepCloneCard(allocator, card);
            servers[idx] = .{
                .name = server.name,
                .state = .{ .ices = ice_copy, .content = content_copy },
            };
        }

        return .{
            .state = .{
                .format = self.format,
                .seed = self.seed,
                .rng_seed = self.rng_seed,
                .active_player = self.active_player,
                .turn = self.turn,
                .end_turn = self.end_turn,
                .run = self.run,
                .runner_successful_run_last_turn = self.runner_successful_run_last_turn,
                .runner_successful_run_this_turn = self.runner_successful_run_this_turn,
                .turn_events = self.turn_events,
                .game_over = self.game_over,
                .winner = self.winner,
                .pending_install = self.pending_install,
                .corp = .{
                    .identity = self.corp_identity,
                    .basic_action_card = self.corp_basic_action_card,
                    .click = self.corp_click,
                    .click_per_turn = self.corp_click_per_turn,
                    .credit = self.corp_credit,
                    .agenda_point = self.corp_agenda_point,
                    .agenda_point_req = self.corp_agenda_point_req,
                    .hand_size = self.corp_hand_size,
                    .bad_publicity = self.corp_bad_publicity,
                    .keep = self.corp_keep,
                    .prompt_state = self.corp_prompt_state,
                    .hand = self.corp_hand.items,
                    .deck = self.corp_deck.items,
                    .discard = self.corp_discard.items,
                    .scored = self.corp_scored.items,
                    .servers = servers,
                },
                .runner = .{
                    .identity = self.runner_identity,
                    .basic_action_card = self.runner_basic_action_card,
                    .click = self.runner_click,
                    .click_per_turn = self.runner_click_per_turn,
                    .credit = self.runner_credit,
                    .agenda_point = self.runner_agenda_point,
                    .agenda_point_req = self.runner_agenda_point_req,
                    .hand_size = self.runner_hand_size,
                    .run_credit = self.runner_run_credit,
                    .link = self.runner_link,
                    .tag = self.runner_tag,
                    .memory = self.runner_memory,
                    .brain_damage = self.runner_brain_damage,
                    .keep = self.runner_keep,
                    .prompt_state = self.runner_prompt_state,
                    .hand = self.runner_hand.items,
                    .deck = self.runner_deck.items,
                    .discard = self.runner_discard.items,
                    .scored = self.runner_scored.items,
                    .rig_hardware = self.runner_rig_hardware.items,
                    .rig_program = self.runner_rig_program.items,
                    .rig_resources = self.runner_rig_resources.items,
                },
            },
            .decision_side = self.decision_side,
            .legal_actions = self.legal_actions,
        };
    }
};

pub const RngState = u64;

const splitmix_gamma: u64 = 0x9E3779B97F4A7C15;
const splitmix_mul_1: u64 = 0xBF58476D1CE4E5B9;
const splitmix_mul_2: u64 = 0x94D049BB133111EB;

const corp_basic_action = CardSpec{
    .title = "Corp Basic Action Card",
    .side = .corp,
    .code = 0,
    .card_type = "Basic Action",
};

const runner_basic_action = CardSpec{
    .title = "Runner Basic Action Card",
    .side = .runner,
    .code = 1,
    .card_type = "Basic Action",
};

// --- Ability usage tracking (per-ability bitmask) ---
// Bit 0 is reserved for legacy installed_ability and event handler once-per-turn tracking.
// Bits 0..N map to abilities[0..N] for AbilitySpec-backed cards.
// Higher bits can be used by card handlers for sub-ability tracking (e.g., Madani install branch = bit 1).

fn isAbilityUsedThisTurn(card: *const state.CardInstance, ability_index: u4) bool {
    return (card.abilities_used_this_turn & (@as(u16, 1) << ability_index)) != 0;
}

fn markAbilityUsedThisTurn(card: *state.CardInstance, ability_index: u4) void {
    card.abilities_used_this_turn |= (@as(u16, 1) << ability_index);
}

fn clearAbilityUsage(card: *state.CardInstance) void {
    card.abilities_used_this_turn = 0;
}

const prompt_install_destination = "install-destination";
const prompt_advance_installed = "advance-installed";
const prompt_score_agenda = "score-agenda";
const prompt_access_choice = "access-choice";
const prompt_access_cleanup = "access-cleanup";
const prompt_rez_ice_free = "send-message-rez";
const prompt_rez_ice_free_score = "send-message-rez-score";
const prompt_run_target = "run-target";

const prompt_run_central = "run-central";
const prompt_hq_access = "hq-access";
const prompt_discard = "discard";
const prompt_manegarm_tax = "manegarm-tax";

fn effectContext(game: *Game) *state.EffectContext {
    game.effect_ctx = .{ .game_ptr = game };
    return &game.effect_ctx;
}

fn effectContextWithEvent(game: *Game, payload: state.EffectContext.EventPayload) *state.EffectContext {
    game.effect_ctx = .{ .game_ptr = game, .event = payload };
    return &game.effect_ctx;
}

fn constEffectContext(game: *const Game) *const state.EffectContext {
    const mutable = @constCast(game);
    mutable.effect_ctx = .{ .game_ptr = mutable };
    return &mutable.effect_ctx;
}

fn effectContextConst(game: *const Game) *const state.EffectContext {
    const mutable = @constCast(game);
    mutable.effect_ctx = .{ .game_ptr = mutable };
    return &mutable.effect_ctx;
}

fn gameFromEffectContext(ctx: *state.EffectContext) *Game {
    return ctx.game_ptr;
}

fn gameFromConstEffectContext(ctx: *const state.EffectContext) *const Game {
    return ctx.game_ptr;
}

pub fn addFloatingEffect(game: *Game, effect: state.FloatingEffect) !void {
    try game.floating_effects.append(game.backing_allocator, effect);
}

pub fn sumFloatingEffects(game: *const Game, kind: state.FloatingEffectKind) i16 {
    var total: i16 = 0;
    for (game.floating_effects.items) |fe| {
        if (fe.kind == kind) total += fe.value;
    }
    return total;
}

fn hasFloatingEffect(game: *const Game, kind: state.FloatingEffectKind) bool {
    for (game.floating_effects.items) |fe| {
        if (fe.kind == kind) return true;
    }
    return false;
}

pub fn hasFloatingEffectFromSource(game: *const Game, kind: state.FloatingEffectKind, source: u32) bool {
    for (game.floating_effects.items) |fe| {
        if (fe.kind == kind and fe.source_code != null and fe.source_code.? == source) return true;
    }
    return false;
}

fn expireFloatingEffects(game: *Game, duration: state.FloatingEffectDuration) void {
    var i: usize = 0;
    while (i < game.floating_effects.items.len) {
        if (game.floating_effects.items[i].duration == duration) {
            _ = game.floating_effects.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

fn clampStaticTotal(value: i16) u8 {
    if (value <= 0) return 0;
    if (value >= std.math.maxInt(u8)) return std.math.maxInt(u8);
    return @intCast(value);
}

fn applyCostModifier(base: u16, modifier: i16) u16 {
    const total = @as(i32, base) + modifier;
    if (total <= 0) return 0;
    if (total >= std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(total);
}

fn sumCardStaticEffects(
    game: *const Game,
    card: *const state.CardInstance,
    kind: state.StaticAbilityKind,
    target: ?*const state.CardInstance,
) i16 {
    var total: i16 = 0;
    for (card.static_abilities) |ability| {
        if (ability.kind != kind) continue;
        const mult: i16 = if (ability.req) |req_fn| req_fn(effectContextConst(game), card, target) else 1;
        if (mult <= 0) continue;
        total += @as(i16, ability.value) * mult;
    }
    return total;
}

fn sumCardAndHostedStaticEffects(
    game: *const Game,
    card: state.CardInstance,
    kind: state.StaticAbilityKind,
    target: ?*const state.CardInstance,
) i16 {
    return sumCardStaticEffects(game, &card, kind, target);
}

fn sumStaticEffectsInCards(
    game: *const Game,
    cards: []const state.CardInstance,
    kind: state.StaticAbilityKind,
    target: ?*const state.CardInstance,
) i16 {
    var total: i16 = 0;
    for (cards) |card| {
        total += sumCardAndHostedStaticEffects(game, card, kind, target);
    }
    return total;
}

fn sumStaticEffects(
    game: *const Game,
    side: state.Side,
    kind: state.StaticAbilityKind,
    target: ?*const state.CardInstance,
) i16 {
    var total: i16 = 0;
    switch (side) {
        .corp => {
            total += sumCardStaticEffects(game, &game.corp_identity, kind, target);
            total += sumStaticEffectsInCards(game, game.corp_scored.items, kind, target);
            for (game.corp_servers.items) |server| {
                for (server.ices.items) |ice| {
                    if (!ice.rezzed) continue;
                    total += sumCardAndHostedStaticEffects(game, ice, kind, target);
                }
                for (server.content.items) |card| {
                    if (!card.rezzed) continue;
                    total += sumCardAndHostedStaticEffects(game, card, kind, target);
                }
            }
        },
        .runner => {
            total += sumCardStaticEffects(game, &game.runner_identity, kind, target);
            total += sumStaticEffectsInCards(game, game.runner_scored.items, kind, target);
            total += sumStaticEffectsInCards(game, game.runner_rig_hardware.items, kind, target);
            total += sumStaticEffectsInCards(game, game.runner_rig_program.items, kind, target);
            total += sumStaticEffectsInCards(game, game.runner_rig_resources.items, kind, target);
            for (game.corp_servers.items) |server| {
                for (server.ices.items) |ice| {
                    total += sumStaticEffectsInCards(game, ice.hosted, kind, target);
                }
            }
        },
    }
    return total;
}

fn refreshDerivedStates(game: *Game) void {
    game.corp_hand_size.base = clampStaticTotal(5 + sumStaticEffects(game, .corp, .hand_size, null));
    game.corp_hand_size.total = game.corp_hand_size.base;
    game.runner_hand_size.base = clampStaticTotal(5 + sumStaticEffects(game, .runner, .hand_size, null));
    game.runner_hand_size.total = game.runner_hand_size.base;
    if (game.runner_memory) |*mem| {
        mem.base = clampStaticTotal(4 + sumStaticEffects(game, .runner, .mu, null));
        mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
    }
}

fn runnerInstallCostModifier(generated: *const Game, card: *const state.CardInstance) i16 {
    return sumStaticEffects(generated, .runner, .install_cost, card) + sumCardStaticEffects(generated, card, .install_cost, card);
}

fn lookupCardSpec(card: state.CardInstance) ?CardSpec {
    if (card.code) |code| return lookupCardSpecByCode(code);
    return null;
}

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
    matchup: MatchupSpec,
    seed: u64,
) !Game {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();

    var game = Game{
        .arena = arena,
        .backing_allocator = backing_allocator,
    };
    errdefer game.deinit();

    const allocator = game.arena.allocator();
    var rng_state = init(seed);

    const corp_full_deck = try buildDeck(allocator, &rng_state, matchup.corp, &game.next_instance_id);
    const runner_full_deck = try buildDeck(allocator, &rng_state, matchup.runner, &game.next_instance_id);
    const corp_identity = try makeCardInstance(allocator, try lookupRequiredCardSpec(matchup.corp.identity_code), &game.next_instance_id);
    const runner_identity = try makeCardInstance(allocator, try lookupRequiredCardSpec(matchup.runner.identity_code), &game.next_instance_id);

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

    // Initialize internal scalar state
    game.format = try allocator.dupe(u8, matchup.format);
    game.seed = seed;
    game.rng_seed = oracleSeed(rng_state);
    game.active_player = .runner;
    game.turn = 0;
    game.end_turn = true;

    game.corp_identity = corp_identity;
    game.corp_basic_action_card = try makeCardInstance(allocator, corp_basic_action, &game.next_instance_id);
    game.corp_credit = 5;
    game.corp_agenda_point_req = matchup.agenda_point_req;
    game.corp_keep = .undecided;
    game.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "mulligan"),
        .choices = mulligan_prompt,
        .source_card = null,
    };

    game.runner_identity = runner_identity;
    game.runner_basic_action_card = try makeCardInstance(allocator, runner_basic_action, &game.next_instance_id);
    game.runner_credit = 5;
    game.runner_agenda_point_req = matchup.agenda_point_req;
    game.runner_keep = .undecided;
    game.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "waiting"),
        .choices = &.{},
        .source_card = null,
    };

    game.decision_side = .corp;
    game.legal_actions = &corp_mulligan_actions;
    refreshDerivedStates(&game);

    return game;
}

pub fn currentPlayer(snapshot: *const Game) state.Side {
    return snapshot.decision_side;
}

pub fn legalActionCount(snapshot: *const Game) usize {
    return snapshot.legal_actions.len;
}

pub fn legalActionAt(
    snapshot: *const Game,
    index: usize,
) !state.LegalAction {
    if (index >= snapshot.legal_actions.len) return error.InvalidActionIndex;
    return snapshot.legal_actions[index];
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
    if (generated.decision_side != action.side) return error.NotCurrentDecision;

    switch (action.kind) {
        .prompt_choice => {
            const choice = action.choice orelse return error.MissingChoice;
            const text = choice.text orelse if (choice.card) |c| c.title else null;
            if (text == null) return error.UnsupportedChoice;
            try applyPromptChoice(generated, action.side, text.?);
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
            try applyAbilityRef(generated, action);
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
        .use_runner_ability => {
            try applyAbilityRef(generated, action);
        },
        .rez_non_ice => {
            const card_index = action.card_index orelse return error.MissingCardIndex;
            const server = action.server orelse return error.MissingServer;
            try applyRezNonIce(generated, server, card_index);
        },
        .rez_ice => {
            try applyRezApproachedIce(generated);
        },
        .advance => {
            const choice = action.choice orelse return error.MissingChoice;
            const choice_text = choice.text orelse return error.MissingChoice;
            try applyAdvanceInstalledChoice(generated, choice_text);
        },
        .flashback => {
            const card_index = action.card_index orelse return error.MissingCardIndex;
            try applyCorpFlashback(generated, card_index);
        },
        .score => {
            const choice = action.choice orelse return error.MissingChoice;
            const choice_text = choice.text orelse return error.MissingChoice;
            try applyScoreAgendaChoice(generated, choice_text);
        },
        .use_identity_ability => {
            try applyAbilityRef(generated, action);
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
    if (generated.decision_side != side) return error.NotCurrentDecision;

    const allocator = generated.arena.allocator();
    const hand = handList(generated, side).items;
    const deck = deckList(generated, side).items;
    switch (side) {
        .corp => {
            generated.corp_keep = choice;
        },
        .runner => {
            generated.runner_keep = choice;
        },
    }

    generated.systemMsg(side, 0, "{s} {s}.", .{
        sideName(side),
        if (choice == .mulligan) "takes a mulligan" else "keeps their hand",
    });

    if (choice == .mulligan) {
        var rng_state = fromOracleSeed(generated.rng_seed orelse return error.MissingRngSeed);
        const combined = try combineCards(allocator, hand, deck);
        shuffleInPlace(state.CardInstance, &rng_state, combined);
        try replaceCardList(generated.backing_allocator, handList(generated, side), combined[0..5]);
        try replaceCardList(generated.backing_allocator, deckList(generated, side), combined[5..]);
        generated.rng_seed = oracleSeed(rng_state);
    }

    switch (side) {
        .corp => {
            generated.corp_prompt_state = .{
                .prompt_type = try allocator.dupe(u8, "waiting"),
                .choices = &.{},
                .source_card = null,
            };

            generated.runner_prompt_state = .{
                .prompt_type = try allocator.dupe(u8, "mulligan"),
                .choices = try dupPromptChoices(allocator),
                .source_card = null,
            };
            generated.decision_side = .runner;
            generated.legal_actions = try mulliganActionsForSide(allocator, .runner);
        },
        .runner => {
            generated.corp_prompt_state = null;
            generated.runner_prompt_state = null;
            generated.decision_side = .corp;
            generated.legal_actions = try startTurnActions(allocator, .corp);
        },
    }
}

pub fn applyStartTurn(
    generated: *Game,
    side: state.Side,
) !void {
    if (generated.decision_side != side) return error.NotCurrentDecision;

    const allocator = generated.arena.allocator();
    if (!generated.end_turn) return error.TurnAlreadyStarted;

    generated.systemMsg(side, 0, "{s} starts their turn.", .{sideName(side)});

    switch (side) {
        .corp => {
            generated.active_player = .corp;
            generated.turn += 1;
            generated.end_turn = false;
            generated.turn_events = .{};
            resetInstalledAbilityUsage(generated);
            // Auto-complete phase 12 when no phase-12 abilities exist (matching Clojure)
            try endCorpPhase12(generated);
        },
        .runner => {
            generated.runner_click = generated.runner_click_per_turn;
            generated.turn_events = .{};
            resetInstalledAbilityUsage(generated);

            // Start-of-turn: take 1 credit from each card with place_credits ability and counters
            for (generated.runner_rig_resources.items) |*card| {
                if (card.place_credits_per_turn and card.credit_counter > 0) {
                    card.credit_counter -= 1;
                    generated.runner_credit += 1;
                    generated.systemMsg(.runner, card.code orelse 0, "Runner gains 1 [credit] from {s}.", .{card.title});
                }
            }

            // Start-of-turn: auto-take credits from loaded resources (Open Market)
            {
                var ri: usize = 0;
                while (ri < generated.runner_rig_resources.items.len) {
                    var card = &generated.runner_rig_resources.items[ri];
                    if (card.auto_take_credits and card.credit_counter > 0) {
                        const take = @min(card.credit_counter, card.take_credits_amount);
                        card.credit_counter -= take;
                        generated.runner_credit += take;
                        generated.systemMsg(.runner, card.code orelse 0, "Runner takes {d} [credit{s}] from {s}.", .{
                            take, if (take != 1) "s" else "", card.title,
                        });
                        if (card.trash_on_empty and card.credit_counter == 0) {
                            if (card.on_empty) |callback| {
                                try callback(effectContext(generated), card);
                            }
                            const trashed = generated.runner_rig_resources.orderedRemove(ri);
                            try appendDiscardCard(generated, .runner, trashed);
                            continue;
                        }
                    }
                    ri += 1;
                }
            }
            generated.active_player = .runner;
            generated.end_turn = false;

            // Fire runner_turn_begins event (MuslihaT: peek at top card)
            if (try fireEvent(generated, .runner_turn_begins)) return;

            generated.decision_side = .runner;
            generated.legal_actions = try runnerOpeningActionsForState(
                allocator,
                generated,
            );
        },
    }
}

pub fn applyEndTurn(
    generated: *Game,
    side: state.Side,
) !void {
    if (generated.end_turn) return error.TurnAlreadyEnded;
    if (generated.active_player != side) return error.NotActivePlayer;

    // Runner end-of-turn: Cacophony sabotage (spend 2 power counters to sabotage 3)
    if (side == .runner) {
        for (generated.runner_rig_resources.items) |*card| {
            if (card.power_counter >= 2 and card.code != null and card.code.? == 35010) {
                // Cacophony end-of-turn sabotage is still auto-declined in oracle mode.
            }
        }
    }

    const hand_len = handList(generated, side).items.len;
    const hand_size = switch (side) {
        .corp => generated.corp_hand_size.total,
        .runner => generated.runner_hand_size.total,
    };

    if (hand_len > hand_size) {
        // Must discard down to hand size
        try beginDiscardPrompt(generated, side, hand_len - hand_size);
        return;
    }

    try finishEndTurn(generated, side);
}

fn beginDiscardPrompt(generated: *Game, side: state.Side, discard_count: usize) !void {
    const allocator = generated.arena.allocator();
    const hand = handList(generated, side).items;
    const choices = try allocator.alloc(state.PromptChoice, hand.len);
    for (hand, 0..) |card, idx| {
        choices[idx] = .{
            .kind = .card,
            .card = .{
                .title = card.title,
                .code = card.code,
                .index = @intCast(idx),
            },
        };
    }

    (switch (side) {
        .corp => generated.corp_prompt_state,
        .runner => generated.runner_prompt_state,
    }) = .{
        .prompt_type = try allocator.dupe(u8, prompt_discard),
        .choices = choices,
        .source_card = null,
        .min_choices = @intCast(discard_count),
    };
    generated.decision_side = side;
    generated.legal_actions = try promptChoiceActions(allocator, side, (switch (side) {
        .corp => generated.corp_prompt_state,
        .runner => generated.runner_prompt_state,
    }).?);
}

fn applyDiscardChoice(generated: *Game, side: state.Side, choice_text: []const u8) !void {
    // choice_text is the card title — find it in hand and discard it
    const hand = handList(generated, side);
    var found: ?usize = null;
    for (hand.items, 0..) |card, idx| {
        if (std.mem.eql(u8, card.title, choice_text)) {
            found = idx;
            break;
        }
    }
    const idx = found orelse return error.UnsupportedChoice;
    const discarded = hand.orderedRemove(idx);
    try appendDiscardCard(generated, side, discarded);
    generated.systemMsg(side, discarded.code orelse 0, "{s} discards {s}.", .{ sideName(side), discarded.title });

    // Check if more discards needed
    const hand_len = hand.items.len;
    const hand_size = switch (side) {
        .corp => generated.corp_hand_size.total,
        .runner => generated.runner_hand_size.total,
    };

    if (hand_len > hand_size) {
        try beginDiscardPrompt(generated, side, hand_len - hand_size);
        return;
    }

    try finishEndTurn(generated, side);
}

fn finishEndTurn(generated: *Game, side: state.Side) !void {
    generated.systemMsg(side, 0, "{s} ends their turn.", .{sideName(side)});
    const next_side = otherSide(side);
    generated.end_turn = true;
    // Clear any discard prompt
    switch (side) {
        .corp => generated.corp_prompt_state = null,
        .runner => generated.runner_prompt_state = null,
    }
    // Fire end-turn events
    if (side == .corp) {
        _ = try fireEvent(generated, .corp_end_turn);
    } else {
        _ = try fireEvent(generated, .runner_end_turn);
    }
    generated.decision_side = next_side;
    generated.legal_actions = try startTurnActions(generated.arena.allocator(), next_side);
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
    const prompt = (switch (side) {
        .corp => generated.corp_prompt_state,
        .runner => generated.runner_prompt_state,
    }) orelse return error.MissingPrompt;

    if (std.mem.eql(u8, prompt.prompt_type, "mulligan")) {
        const keep_state = parseKeepState(choice_text);
        try applyMulliganChoice(generated, side, keep_state);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_install_destination) and generated.pending_install != null and prompt.source_card != null) {
        try applyPendingInstallChoice(generated, choice_text);
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
        try applyAccessCleanupChoice(generated, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_rez_ice_free) and prompt.source_card != null) {
        try applyRezIceFreeChoice(generated, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_rez_ice_free_score) and prompt.source_card != null) {
        try applyRezIceFreeScoreChoice(generated, choice_text);
        return;
    }

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, "net-damage-on-access")) {
        try applyNetDamageOnAccessChoice(generated, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_access_choice) and prompt.source_card != null) {
        try applyAccessPromptChoice(generated, side, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_hq_access)) {
        try applyHqAccessChoice(generated, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_run_target) and prompt.source_card != null) {
        try applyRunnerRunTargetChoice(generated, choice_text);
        return;
    }

    if (std.mem.eql(u8, prompt.prompt_type, prompt_discard)) {
        try applyDiscardChoice(generated, side, choice_text);
        return;
    }

    if (std.mem.eql(u8, prompt.prompt_type, prompt_run_central)) {
        // Red Team: click already spent in run_central handler, just start the run
        try applyRunFromAbility(generated, choice_text, if (prompt.source_card) |sc| sc.instance_id else null);
        return;
    }

    if (std.mem.eql(u8, prompt.prompt_type, "trace")) {
        try applyTraceChoice(generated, side, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_break_sub)) {
        try applyBreakSubChoice(generated, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_mu_overflow)) {
        try applyMuOverflowChoice(generated, choice_text);
        return;
    }

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, "jack-out")) {
        try applyJackOutPromptChoice(generated, choice_text);
        return;
    }

    // Tao Salonga: swap 2 pieces of ICE
    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, "tao-swap-ice")) {
        try applyTaoSwapIceChoice(generated, choice_text);
        return;
    }

    // Trojan: runner selects ICE to host on
    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, "trojan-host")) {
        try applyTrojanHostChoice(generated, choice_text);
        return;
    }

    // Prompt-level on_choice handler: set directly when opening the prompt
    if (prompt.on_choice) |handler| {
        try handler(effectContext(generated), choice_text);
        if (hasActivePrompt(generated)) return;
        if (try resumePendingEffects(generated)) return;
        return;
    }


    // HB: Precision Design: select card from Archives to add to HQ
    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, "precision-design-archive")) {
        if (std.mem.eql(u8, choice_text, "Done")) {
            generated.corp_prompt_state = null;
            if (try resumePendingEffects(generated)) return;
            generated.decision_side = .corp;
            generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
            return;
        }
        // Find the card in Archives by title and move to HQ
        for (generated.corp_discard.items, 0..) |card, idx| {
            if (std.mem.eql(u8, card.title, choice_text)) {
                const removed = generated.corp_discard.orderedRemove(idx);
                try generated.corp_hand.append(generated.backing_allocator, removed);
                break;
            }
        }
        generated.corp_prompt_state = null;
        if (try resumePendingEffects(generated)) return;
        generated.decision_side = .corp;
        generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
        return;
    }


    // Ansel 1.0: corp chooses a card from HQ/Archives to install
    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, "ansel-install")) {
        try applyAnselInstallChoice(generated, choice_text);
        return;
    }

    // Ballista: corp chooses a program to trash during subroutine
    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, "ballista-trash")) {
        try applyBallistaTrashChoice(generated, choice_text);
        return;
    }

    // Install-ICE subroutine prompt (Brân, Scatter Field): "other" type with pending_subroutine
    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, "other")) {
        if (generated.run) |run| {
            if (run.pending_subroutine) |_| {
                try applyBranInstallIceChoice(generated, choice_text);
                return;
            }
        }
    }


    return error.UnsupportedPrompt;
}

fn applyBasicActionAbility(
    generated: *Game,
    side: state.Side,
    basic_action: state.BasicAction,
) !void {
    if (generated.end_turn) return error.TurnNotStarted;
    if (generated.active_player != side) return error.NotActivePlayer;

    switch (side) {
        .corp => try applyCorpBasicActionAbility(generated, basic_action),
        .runner => try applyRunnerBasicActionAbility(generated, basic_action),
    }
}

fn applyCorpBasicActionAbility(
    generated: *Game,
    basic_action: state.BasicAction,
) !void {
    switch (basic_action) {
        .gain_credit => {
            try spendClicks(generated, .corp, 1);
            generated.corp_credit += 1;
            generated.systemMsg(.corp, 0, "Corp spends [click] to gain 1 [credit].", .{});
        },
        .draw_card => {
            try spendClicks(generated, .corp, 1);
            try drawCard(generated, .corp);
            generated.systemMsg(.corp, 0, "Corp spends [click] to draw 1 card.", .{});
        },
        .advance_installed => {
            if (countInstalledCards(generated.corp_servers.items) == 0) {
                // No installed cards - advance action does nothing useful
                try spendClicks(generated, .corp, 1);
                try spendCredits(generated, .corp, 1);
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
            try spendClicks(generated, .corp, 3);
            purgeVirusCounters(generated);
            generated.systemMsg(.corp, 0, "Corp spends [click][click][click] to purge virus counters.", .{});
        },
        else => return error.UnsupportedAbility,
    }

    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
}

fn applyRunnerBasicActionAbility(
    generated: *Game,
    basic_action: state.BasicAction,
) !void {
    switch (basic_action) {
        .gain_credit => {
            try spendClicks(generated, .runner, 1);
            generated.runner_credit += 1;
            generated.systemMsg(.runner, 0, "Runner spends [click] to gain 1 [credit].", .{});
        },
        .draw_card => {
            try spendClicks(generated, .runner, 1);
            var draw_amount: u8 = 1;
            if (generated.turn_events.runner_click_draws == 0) {
                draw_amount += runner_installed_click_draw_bonus(generated);
            }
            try drawCards(generated, .runner, draw_amount);
            generated.turn_events.runner_click_draws += 1;
            if (draw_amount > 1) {
                generated.systemMsg(.runner, 0, "Runner spends [click] to draw {d} cards.", .{draw_amount});
            } else {
                generated.systemMsg(.runner, 0, "Runner spends [click] to draw 1 card.", .{});
            }
        },
        .run_any_server => return error.UnsupportedAbility,
        .remove_tag => {
            try spendClicks(generated, .runner, 1);
            try spendCredits(generated, .runner, 2);
            try removeRunnerTags(generated, 1);
            generated.systemMsg(.runner, 0, "Runner spends [click] and pays 2 [credits] to remove 1 tag.", .{});
            if (try resumePendingEffects(generated)) return;
        },
        else => return error.UnsupportedAbility,
    }

    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(
        generated.arena.allocator(),
        generated,
    );
}

const InstalledTarget = struct {
    server_index: usize,
    is_ice: bool,
    card_index: usize,
};

fn beginAdvanceInstalledPrompt(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const choices = try installedCardChoices(allocator, generated.corp_servers.items);
    if (choices.len == 0) {
        generated.decision_side = .corp;
        generated.legal_actions = try corpOpeningActionsForState(allocator, generated);
        return;
    }

    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_advance_installed),
        .choices = choices,
        .source_card = null,
    };
    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
}

fn applyAdvanceInstalledChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    // Basic advance action: always 1 advancement, costs 1 click + 1 credit
    try spendClicks(generated, .corp, 1);
    try spendCredits(generated, .corp, 1);
    const advanced_card = try addAdvancementCounter(generated, choice_text, 1);
    generated.systemMsg(.corp, advanced_card.code orelse 0, "Corp spends [click] and pays 1 [credit] to advance {s}.", .{advanced_card.title});
    generated.corp_prompt_state = null;
    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
}

fn beginScoreAgendaPrompt(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const choices = try scoreableAgendaChoices(allocator, generated.corp_servers.items);
    if (choices.len == 0) return error.UnsupportedAbility;

    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_score_agenda),
        .choices = choices,
        .source_card = null,
    };
    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
}

fn applyScoreAgendaChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    generated.corp_prompt_state = null;
    const target = try parseInstalledTargetChoice(choice_text, generated.corp_servers.items);
    if (target.is_ice) return error.UnsupportedChoice;
    if (target.server_index < 3) return error.UnsupportedChoice;
    if (target.server_index >= generated.corp_servers.items.len) return error.UnsupportedChoice;

    const server = generated.corp_servers.items[target.server_index];
    if (target.card_index >= server.content.items.len) return error.UnsupportedChoice;
    const agenda = server.content.items[target.card_index];
    const agenda_points = agenda.agenda_points orelse return error.UnsupportedChoice;
    const requirement = agenda.advancement_requirement orelse return error.UnsupportedChoice;
    if (agenda.advancement_counter < requirement) return error.UnsupportedChoice;

    generated.last_scored_server_index = target.server_index;
    const scored_agenda = removeServerContentCard(generated, target.server_index, @intCast(target.card_index));
    try generated.corp_scored.append(generated.backing_allocator, scored_agenda);
    try removeServerIfEmpty(generated, target.server_index);

    generated.corp_agenda_point += agenda_points;
    generated.systemMsg(.corp, agenda.code orelse 0, "Corp scores {s} and gains {d} agenda point{s}.", .{
        agenda.title,
        agenda_points,
        if (agenda_points != 1) "s" else "",
    });

    // Track agenda points scored this turn
    try addFloatingEffect(generated, .{ .kind = .agenda_points_scored, .duration = .end_of_turn, .value = @intCast(agenda_points) });

    // Queue all score effects + event handlers into the pending effects queue.
    // They will be processed one at a time via drainPendingEffects, pausing
    // whenever a prompt is opened and resuming when it resolves.
    const allocator = generated.backing_allocator;

    if (lookupCardSpec(scored_agenda)) |spec| {
        // Queue on_score event_abilities (e.g. Orbital Superiority meat damage)
        for (spec.event_abilities, 0..) |ea, ea_idx| {
            if (ea.event == .agenda_scored) {
                try generated.pending_effects.append(allocator, .{ .card_effect = .{
                    .card = scored_agenda,
                    .event = .agenda_scored,
                    .ability_index = @intCast(ea_idx),
                } });
                break;
            }
        }
        // Apply simple on-score effects inline; queue prompt-opening ones
        switch (spec.on_score.kind) {
            .gain_credits => {
                const amount = spec.on_score.amount;
                generated.corp_credit += amount;
                generated.systemMsg(.corp, 0, "Corp gains {d} [credit{s}].", .{ amount, if (amount != 1) @as([]const u8, "s") else "" });
            },
            .draw_cards => {
                try drawCards(generated, .corp, spec.on_score.amount);
                generated.systemMsg(.corp, spec.code, "Corp draws {d} card{s}.", .{ spec.on_score.amount, if (spec.on_score.amount != 1) @as([]const u8, "s") else "" });
            },
            .give_runner_tag => {
                const amount = spec.on_score.amount;
                if (generated.runner_tag == null) {
                    generated.runner_tag = .{ .base = 0, .total = amount, .is_tagged = amount > 0 };
                } else {
                    generated.runner_tag.?.total += amount;
                    generated.runner_tag.?.is_tagged = generated.runner_tag.?.total > 0;
                }
                generated.systemMsg(.corp, 0, "Runner gains {d} tag{s}.", .{ amount, if (amount != 1) @as([]const u8, "s") else "" });
                if (amount > 0) {
                    generated.turn_events.runner_gain_tag_count += 1;
                    try collectEventHandlers(generated, .runner_gain_tag);
                }
            },
            .gain_clicks => {
                const amount = spec.on_score.amount;
                generated.corp_click += amount;
                try addFloatingEffect(generated, .{
                    .kind = .prevent_score,
                    .duration = .end_of_turn,
                    .value = 1,
                });
                generated.systemMsg(.corp, 0, "Corp gains {d} [click{s}].", .{ amount, if (amount != 1) @as([]const u8, "s") else "" });
            },
            .rez_ice_free => try generated.pending_effects.append(allocator, .{ .deferred_prompt = .{
                .card = scored_agenda,
                .on_choice = null,
                .open_fn = &openRezIceFreeForScore,
            } }),
            .none => {},
        }
    }

    // Collect event handlers (appends to pending_effects without draining)
    try collectEventHandlers(generated, .agenda_scored);

    // Terminal: check game state and return to corp actions
    try generated.pending_effects.append(allocator, .{ .finish_score = {} });

    // Start processing the queue
    if (try drainPendingEffects(generated)) return;
}

fn scoreableAgendaChoices(
    allocator: std.mem.Allocator,
    servers: []const MutableServer,
) ![]const state.PromptChoice {
    var count: usize = 0;
    for (servers, 0..) |server, server_index| {
        if (server_index < 3) continue;
        for (server.content.items) |card| {
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
        for (server.content.items, 0..) |card, card_index| {
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

fn isAdvanceable(card: state.CardInstance) bool {
    if (card.card_type) |ct| {
        if (std.mem.eql(u8, ct, "Agenda")) return true;
    }
    // Check can_advance static ability (Urtica Cipher, Pharos, Clearinghouse, etc.)
    for (card.static_abilities) |sa| {
        if (sa.kind == .can_advance) return true;
    }
    return false;
}

fn advanceableCardChoices(
    allocator: std.mem.Allocator,
    servers: []const MutableServer,
) ![]const state.PromptChoice {
    var count: usize = 0;
    for (servers) |server| {
        for (server.content.items) |card| {
            if (isAdvanceable(card)) count += 1;
        }
    }
    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    for (servers) |server| {
        for (server.content.items, 0..) |card, card_index| {
            if (!isAdvanceable(card)) continue;
            const text = try std.fmt.allocPrint(allocator, "{s}|c|{d}", .{ server.name, card_index });
            choices[next] = stringChoice(text);
            next += 1;
        }
    }
    return choices;
}

fn installedCardChoices(
    allocator: std.mem.Allocator,
    servers: []const MutableServer,
) ![]const state.PromptChoice {
    var count: usize = 0;
    for (servers) |server| {
        count += server.ices.items.len + server.content.items.len;
    }
    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    for (servers) |server| {
        for (server.ices.items, 0..) |_, card_index| {
            const text = try std.fmt.allocPrint(allocator, "{s}|i|{d}", .{ server.name, card_index });
            choices[next] = stringChoice(text);
            next += 1;
        }
        for (server.content.items, 0..) |_, card_index| {
            const text = try std.fmt.allocPrint(allocator, "{s}|c|{d}", .{ server.name, card_index });
            choices[next] = stringChoice(text);
            next += 1;
        }
    }
    return choices;
}

fn installedNotThisTurnChoices(
    allocator: std.mem.Allocator,
    servers: []const MutableServer,
) ![]const state.PromptChoice {
    var count: usize = 0;
    for (servers) |server| {
        for (server.ices.items) |card| {
            if (!card.installed_this_turn) count += 1;
        }
        for (server.content.items) |card| {
            if (!card.installed_this_turn) count += 1;
        }
    }
    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    for (servers) |server| {
        for (server.ices.items, 0..) |card, card_index| {
            if (card.installed_this_turn) continue;
            const text = try std.fmt.allocPrint(allocator, "{s}|i|{d}", .{ server.name, card_index });
            choices[next] = stringChoice(text);
            next += 1;
        }
        for (server.content.items, 0..) |card, card_index| {
            if (card.installed_this_turn) continue;
            const text = try std.fmt.allocPrint(allocator, "{s}|c|{d}", .{ server.name, card_index });
            choices[next] = stringChoice(text);
            next += 1;
        }
    }
    return choices;
}

fn parseInstalledTargetChoice(
    choice_text: []const u8,
    servers: []const MutableServer,
) !InstalledTarget {
    var iter = std.mem.splitScalar(u8, choice_text, '|');
    const server_name = iter.next() orelse return error.UnsupportedChoice;
    const zone = iter.next() orelse return error.UnsupportedChoice;
    const index_text = iter.next() orelse return error.UnsupportedChoice;
    const card_index = try std.fmt.parseInt(usize, index_text, 10);
    const server_index = findServerIndexByName(servers, server_name) catch return error.UnsupportedChoice;
    return .{
        .server_index = server_index,
        .is_ice = std.mem.eql(u8, zone, "i"),
        .card_index = card_index,
    };
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
    const target = try parseInstalledTargetChoice(choice_text, generated.corp_servers.items);
    if (target.server_index >= generated.corp_servers.items.len) return error.UnsupportedChoice;
    var server = &generated.corp_servers.items[target.server_index];
    if (target.is_ice) {
        if (target.card_index >= server.ices.items.len) return error.UnsupportedChoice;
        var card = &server.ices.items[target.card_index];
        const was_zero = card.advancement_counter == 0;
        card.advancement_counter += amount;
        // Weyland: Built to Last — gain 2cr when advancing a card with no advancement counters
        if (was_zero and generated.corp_identity.code != null and generated.corp_identity.code.? == 30059) {
            generated.corp_credit += 2;
        }
        return card.*;
    }
    if (target.card_index >= server.content.items.len) return error.UnsupportedChoice;
    var card = &server.content.items[target.card_index];
    const was_zero = card.advancement_counter == 0;
    card.advancement_counter += amount;
    // Weyland: Built to Last — gain 2cr when advancing a card with no advancement counters
    if (was_zero and generated.corp_identity.code != null and generated.corp_identity.code.? == 30059) {
        generated.corp_credit += 2;
    }
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

fn setGameOver(generated: *Game, winner: state.Side) void {
    generated.game_over = true;
    generated.winner = winner;
    generated.systemMsg(winner, 0, "{s} wins the game.", .{sideName(winner)});
    generated.run = null;
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    generated.legal_actions = &.{};
    generated.decision_side = winner;
}

fn updateTerminalState(generated: *Game) void {
    refreshDerivedStates(generated);
    // Check flatline: runner has damage >= hand size
    if (generated.runner_brain_damage >= generated.runner_hand_size.total) {
        setGameOver(generated, .corp);
        return;
    }

    // Check flatline: runner hand emptied by net/meat damage
    if (generated.runner_hand.items.len == 0) {
        setGameOver(generated, .corp);
        return;
    }

    // Check agenda point victories
    if (generated.corp_agenda_point >= generated.corp_agenda_point_req) {
        setGameOver(generated, .corp);
        return;
    }
    if (generated.runner_agenda_point >= generated.runner_agenda_point_req) {
        setGameOver(generated, .runner);
    }
}

fn is_runner_tagged(tag: ?state.TagState) bool {
    if (tag) |tag_state| return tag_state.is_tagged or tag_state.total > 0;
    return false;
}

/// Give the runner tags and fire the runner_gain_tag event.
/// Returns true if an event handler opened a prompt (caller should return).
fn purgeVirusCounters(generated: *Game) void {
    for (generated.runner_rig_program.items) |*card| {
        card.virus_counter = 0;
    }
    // Also purge from trojans hosted on ICE
    for (generated.corp_servers.items) |*server| {
        for (server.ices.items) |*ice| {
            for (ice.hosted) |*hosted| {
                hosted.virus_counter = 0;
            }
        }
    }
}

fn removeRunnerTags(generated: *Game, count: u8) !void {
    var removed: u8 = 0;
    if (generated.runner_tag) |*tag| {
        var remaining = count;
        while (remaining > 0 and tag.total > 0) : (remaining -= 1) {
            tag.total -= 1;
            removed += 1;
        }
        tag.is_tagged = tag.total > 0;
    }
    if (removed > 0) {
        try collectEventHandlers(generated, .runner_lose_tag);
    }
}

fn addRunnerTag(generated: *Game, count: u8) !bool {
    if (generated.runner_tag == null) {
        generated.runner_tag = .{ .base = 0, .total = count, .is_tagged = count > 0 };
    } else {
        generated.runner_tag.?.total += count;
        generated.runner_tag.?.is_tagged = generated.runner_tag.?.total > 0;
    }
    if (count > 0) {
        generated.turn_events.runner_gain_tag_count += 1;
        return try fireEvent(generated, .runner_gain_tag);
    }
    return false;
}

/// Process queued pending effects one at a time. Stops when an effect opens
/// a prompt (the prompt handler will call this again after resolving).
/// Returns true if a prompt was opened (caller should return).
/// Find a mutable reference to a card based on its event source location.
/// Falls back to searching by code if the stored index is stale (card was moved/removed).
fn findCardByEventSource(generated: *Game, src: EventSource) ?*state.CardInstance {
    switch (src.zone) {
        .identity => {
            if (src.side == .corp) return &generated.corp_identity;
            return &generated.runner_identity;
        },
        .runner_resource => {
            // Try stored index first
            if (src.index < generated.runner_rig_resources.items.len) {
                const card = &generated.runner_rig_resources.items[src.index];
                if (card.code != null and card.code.? == src.code) return card;
            }
            // Fallback: search by code
            for (generated.runner_rig_resources.items) |*card| {
                if (card.code != null and card.code.? == src.code) return card;
            }
            return null;
        },
        .runner_program => {
            if (src.index < generated.runner_rig_program.items.len) {
                const card = &generated.runner_rig_program.items[src.index];
                if (card.code != null and card.code.? == src.code) return card;
            }
            for (generated.runner_rig_program.items) |*card| {
                if (card.code != null and card.code.? == src.code) return card;
            }
            return null;
        },
        .runner_hardware => {
            if (src.index < generated.runner_rig_hardware.items.len) {
                const card = &generated.runner_rig_hardware.items[src.index];
                if (card.code != null and card.code.? == src.code) return card;
            }
            for (generated.runner_rig_hardware.items) |*card| {
                if (card.code != null and card.code.? == src.code) return card;
            }
            return null;
        },
        .corp_server_content => {
            if (src.server_index < generated.corp_servers.items.len) {
                const server = &generated.corp_servers.items[src.server_index];
                if (src.index < server.content.items.len) {
                    const card = &server.content.items[src.index];
                    if (card.code != null and card.code.? == src.code) return card;
                }
                for (server.content.items) |*card| {
                    if (card.code != null and card.code.? == src.code) return card;
                }
            }
            return null;
        },
        .corp_ice_hosted => {
            if (src.server_index < generated.corp_servers.items.len) {
                const server = &generated.corp_servers.items[src.server_index];
                if (src.parent_index < server.ices.items.len) {
                    const ice = &server.ices.items[src.parent_index];
                    if (src.index < ice.hosted.len) {
                        const card = &ice.hosted[src.index];
                        if (card.code != null and card.code.? == src.code) return card;
                    }
                    for (ice.hosted) |*card| {
                        if (card.code != null and card.code.? == src.code) return card;
                    }
                }
            }
            return null;
        },
    }
}

/// Find the array index of a card in runner resources by code (for removal after event)
fn findRunnerResourceIndex(generated: *const Game, code: u32) ?usize {
    for (generated.runner_rig_resources.items, 0..) |card, i| {
        if (card.code != null and card.code.? == code) return i;
    }
    return null;
}

fn appendEventHandlersForCard(
    generated: *Game,
    allocator: std.mem.Allocator,
    card: state.CardInstance,
    side: state.Side,
    zone: CardZone,
    index: u16,
    server_index: u16,
    parent_index: u16,
    event: state.GameEvent,
) !void {
    if (card.code == null) return;
    for (card.event_abilities, 0..) |ability, ability_index| {
        if (ability.event != event) continue;
        try generated.pending_effects.append(allocator, .{ .event_handler = .{
            .code = card.code.?,
            .event = event,
            .side = side,
            .zone = zone,
            .ability_index = @intCast(ability_index),
            .index = index,
            .server_index = server_index,
            .parent_index = parent_index,
        } });
    }
}

fn drainPendingEffects(generated: *Game) anyerror!bool {
    while (generated.pending_effects.items.len > 0) {
        const effect = generated.pending_effects.orderedRemove(0);
        switch (effect) {
            .event_handler => |src| {
                const card = findCardByEventSource(generated, src) orelse continue;
                if (src.ability_index >= card.event_abilities.len) continue;
                const ability = card.event_abilities[src.ability_index];
                if (ability.event != src.event) continue;
                try ability.handler(effectContext(generated), card);
                if (hasActivePrompt(generated)) return true;
            },
            .card_effect => |ce| {
                // Find the card in corp_scored (for agenda_scored) and call the event ability
                if (ce.event == .agenda_scored) {
                    if (lookupCardSpecByCode(ce.card.code orelse continue)) |spec| {
                        if (ce.ability_index >= spec.event_abilities.len) continue;
                        const ea = spec.event_abilities[ce.ability_index];
                        if (ea.event != ce.event) continue;
                        // Get a mutable pointer to the scored agenda in corp_scored
                        var mutable_card: *state.CardInstance = undefined;
                        if (generated.corp_scored.items.len > 0) {
                            mutable_card = &generated.corp_scored.items[generated.corp_scored.items.len - 1];
                        } else continue;
                        const old_corp_prompt = generated.corp_prompt_state;
                        const old_runner_prompt = generated.runner_prompt_state;
                        try ea.handler(effectContext(generated), mutable_card);
                        if (generated.game_over) return true;
                        // Check if a new prompt was opened
                        if (generated.corp_prompt_state != null and
                            (old_corp_prompt == null or @intFromPtr(generated.corp_prompt_state.?.prompt_type.ptr) != @intFromPtr(old_corp_prompt.?.prompt_type.ptr)))
                            return true;
                        if (generated.runner_prompt_state != null and
                            (old_runner_prompt == null or @intFromPtr(generated.runner_prompt_state.?.prompt_type.ptr) != @intFromPtr(old_runner_prompt.?.prompt_type.ptr)))
                            return true;
                    }
                }
            },
            .deferred_prompt => |dp| {
                if (try dp.open_fn(generated, dp.card, dp.on_choice)) return true;
            },
            .finish_steal => |info| {
                try removeCurrentAccessedCard(generated);

                if (generated.run != null and info.is_central) {
                    try continueOrCompleteAfterSteal(generated, true);
                    return false;
                }

                if (generated.run == null) {
                    generated.pending_access = null;
                    try restorePriorityAfterPrompt(generated);
                    return false;
                }

                const allocator = generated.arena.allocator();
                generated.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                generated.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, prompt_access_cleanup),
                    .choices = try singleStringChoice(allocator, "Done"),
                    .source_card = info.accessed,
                };
                generated.decision_side = .corp;
                generated.legal_actions = try promptChoiceActions(
                    allocator,
                    .corp,
                    generated.corp_prompt_state.?,
                );
                return true;
            },
            .finish_score => {
                updateTerminalState(generated);
                if (generated.game_over) {
                    generated.corp_prompt_state = null;
                    return true;
                }
                generated.corp_prompt_state = null;
                generated.decision_side = .corp;
                generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
                return false;
            },
        }
    }
    return false;
}

/// Resume pending effects after a prompt resolves.
/// Call this instead of returning directly to corp/runner opening actions
/// when the prompt was triggered by a queued effect.
/// Returns true if another prompt was opened (caller should return).
fn resumePendingEffects(generated: *Game) anyerror!bool {
    if (generated.pending_effects.items.len > 0) {
        return try drainPendingEffects(generated);
    }
    return false;
}

fn hasActivePrompt(generated: *const Game) bool {
    if (generated.corp_prompt_state) |ps| {
        if (!std.mem.eql(u8, ps.prompt_type, "run") and !std.mem.eql(u8, ps.prompt_type, "waiting")) return true;
    }
    if (generated.runner_prompt_state) |ps| {
        if (!std.mem.eql(u8, ps.prompt_type, "run") and !std.mem.eql(u8, ps.prompt_type, "waiting")) return true;
    }
    return false;
}

/// Collect all matching event handlers into the pending effects queue.
/// Does NOT drain — caller decides when to drain.
fn collectEventHandlers(generated: *Game, event: state.GameEvent) !void {
    const allocator = generated.backing_allocator;

    try appendEventHandlersForCard(generated, allocator, generated.corp_identity, .corp, .identity, 0, 0, 0, event);
    try appendEventHandlersForCard(generated, allocator, generated.runner_identity, .runner, .identity, 0, 0, 0, event);

    for (generated.runner_rig_hardware.items, 0..) |hw, idx| {
        try appendEventHandlersForCard(generated, allocator, hw, .runner, .runner_hardware, @intCast(idx), 0, 0, event);
    }
    for (generated.runner_rig_resources.items, 0..) |res, idx| {
        try appendEventHandlersForCard(generated, allocator, res, .runner, .runner_resource, @intCast(idx), 0, 0, event);
    }
    for (generated.runner_rig_program.items, 0..) |prog, idx| {
        try appendEventHandlersForCard(generated, allocator, prog, .runner, .runner_program, @intCast(idx), 0, 0, event);
    }
    for (generated.corp_servers.items, 0..) |server, server_idx| {
        for (server.content.items, 0..) |card, card_idx| {
            if (!card.rezzed) continue;
            try appendEventHandlersForCard(generated, allocator, card, .corp, .corp_server_content, @intCast(card_idx), @intCast(server_idx), 0, event);
        }
        for (server.ices.items, 0..) |ice, ice_idx| {
            for (ice.hosted, 0..) |hosted, hosted_idx| {
                try appendEventHandlersForCard(generated, allocator, hosted, .runner, .corp_ice_hosted, @intCast(hosted_idx), @intCast(server_idx), @intCast(ice_idx), event);
            }
        }
    }
}

/// Collect event handlers and immediately drain (for non-scoring event sites like addRunnerTag).
fn fireEvent(generated: *Game, event: state.GameEvent) anyerror!bool {
    try collectEventHandlers(generated, event);
    return try drainPendingEffects(generated);
}

fn applyTaoSwapIceChoice(generated: *Game, choice_text: []const u8) !void {
    if (std.mem.eql(u8, choice_text, "Done")) {
        // Declined to swap
        generated.tao_first_ice = null;
        generated.runner_prompt_state = null;
        if (try resumePendingEffects(generated)) return;
        generated.decision_side = .corp;
        generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
        return;
    }

    if (generated.tao_first_ice == null) {
        // First ICE selected — store it and present second pick (excluding the first)
        generated.tao_first_ice = choice_text;
        const allocator = generated.arena.allocator();
        var choices: std.ArrayList(state.PromptChoice) = .empty;
        defer choices.deinit(allocator);
        for (generated.corp_servers.items, 0..) |server, si| {
            for (server.ices.items, 0..) |ice, ii| {
                const text = try std.fmt.allocPrint(allocator, "{d}|{d}|{s}", .{ si, ii, ice.title });
                if (std.mem.eql(u8, text, choice_text)) continue; // skip the first pick
                try choices.append(allocator, .{ .kind = .card, .text = text, .card = .{ .title = ice.title, .side = .corp, .index = @intCast(ii) } });
            }
        }
        try choices.append(allocator, stringChoice("Done"));
        generated.runner_prompt_state = .{
            .prompt_type = try allocator.dupe(u8, "tao-swap-ice"),
            .choices = try choices.toOwnedSlice(allocator),
            .source_card = null,
            .min_choices = 1,
        };
        generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
        return;
    }

    // Second ICE selected — perform the swap
    const first_text = generated.tao_first_ice.?;
    var pieces_a = std.mem.splitScalar(u8, first_text, '|');
    const srv_a = try std.fmt.parseInt(usize, pieces_a.next() orelse return error.UnsupportedChoice, 10);
    const idx_a = try std.fmt.parseInt(usize, pieces_a.next() orelse return error.UnsupportedChoice, 10);

    var pieces_b = std.mem.splitScalar(u8, choice_text, '|');
    const srv_b = try std.fmt.parseInt(usize, pieces_b.next() orelse return error.UnsupportedChoice, 10);
    const idx_b = try std.fmt.parseInt(usize, pieces_b.next() orelse return error.UnsupportedChoice, 10);

    // Swap the two ICE cards
    const ice_a = generated.corp_servers.items[srv_a].ices.items[idx_a];
    const ice_b = generated.corp_servers.items[srv_b].ices.items[idx_b];
    generated.corp_servers.items[srv_a].ices.items[idx_a] = ice_b;
    generated.corp_servers.items[srv_b].ices.items[idx_b] = ice_a;

    generated.tao_first_ice = null;
    generated.runner_prompt_state = null;
    if (try resumePendingEffects(generated)) return;
    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
}

fn applyTrojanHostChoice(generated: *Game, choice_text: []const u8) !void {
    const pending = generated.pending_install orelse return error.MissingPendingInstall;
    // Parse "server_idx|ice_idx|title"
    var pieces = std.mem.splitScalar(u8, choice_text, '|');
    const server_text = pieces.next() orelse return error.UnsupportedChoice;
    const ice_text = pieces.next() orelse return error.UnsupportedChoice;
    const server_idx = try std.fmt.parseInt(usize, server_text, 10);
    const ice_idx = try std.fmt.parseInt(usize, ice_text, 10);

    if (pending.runner_spend_click) {
        try spendClicks(generated, .runner, 1);
    }
    try spendCredits(generated, .runner, pending.runner_install_cost);
    var installed_card = try removeCardFromHand(generated, .runner, pending.card_index);
    installed_card.credit_counter = installed_card.initial_credit_counters;
    clearAbilityUsage(&installed_card);
    // Host trojan on the ICE card (matching Clojure's model)
    const allocator = generated.arena.allocator();
    var ice = &generated.corp_servers.items[server_idx].ices.items[ice_idx];
    const new_hosted = try allocator.alloc(state.CardInstance, ice.hosted.len + 1);
    @memcpy(new_hosted[0..ice.hosted.len], ice.hosted);
    new_hosted[ice.hosted.len] = installed_card;
    ice.hosted = new_hosted;
    generated.runner_install_context = .{ .install_cost = pending.runner_install_cost };
    defer generated.runner_install_context = null;
    applyRunnerInstalledCardCounters(generated, &ice.hosted[ice.hosted.len - 1]);

    generated.turn_events.programs_installed_this_turn += 1;
    if (generated.runner_memory) |*mem| {
        mem.used += pending.card.runner_install.mu_cost;
        mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
    }
    // Tranquilizer: check derez threshold (3) immediately after install
    const hosted_card = ice.hosted[ice.hosted.len - 1];
    if (hosted_card.code != null and hosted_card.code.? == 30017 and hosted_card.virus_counter >= 3) {
        ice.rezzed = false;
    }
    generated.pending_install = null;
    generated.runner_prompt_state = null;
    if (try resumePendingEffects(generated)) return;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), generated);
}

fn runner_had_successful_run_last_turn(generated: *const Game) bool {
    return generated.runner_successful_run_last_turn;
}

fn runner_installed_click_draw_bonus(generated: *const Game) u8 {
    var bonus: u8 = 0;
    for (generated.runner_rig_resources.items) |card| {
        bonus += card.click_draw_bonus;
    }
    for (generated.runner_rig_hardware.items) |card| {
        bonus += card.click_draw_bonus;
    }
    return bonus;
}

fn runner_installed_hq_access_bonus(generated: *const Game) u8 {
    return clampStaticTotal(sumStaticEffects(generated, .runner, .hq_access, null));
}

fn predictive_planogram_choices(
    allocator: std.mem.Allocator,
    tag: ?state.TagState,
) ![]const state.PromptChoice {
    const tagged = is_runner_tagged(tag);
    const count: usize = if (tagged) 3 else 2;
    const choices = try allocator.alloc(state.PromptChoice, count);
    choices[0] = stringChoice("Gain 3 [Credits]");
    choices[1] = stringChoice("Draw 3 cards");
    if (tagged) choices[2] = stringChoice("Gain 3 [Credits] and draw 3 cards");
    return choices;
}

fn public_trail_choices(
    allocator: std.mem.Allocator,
    runner_credit: u16,
) ![]const state.PromptChoice {
    const count: usize = if (runner_credit >= 8) 2 else 1;
    const choices = try allocator.alloc(state.PromptChoice, count);
    choices[0] = stringChoice("Take 1 tag");
    if (runner_credit >= 8) choices[1] = stringChoice("Pay 8 [Credits]");
    return choices;
}

fn retribution_choices(
    allocator: std.mem.Allocator,
    hardware: []const state.CardInstance,
    programs: []const state.CardInstance,
) ![]const state.PromptChoice {
    const count = hardware.len + programs.len;
    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    for (hardware, 0..) |_, idx| {
        const text = try std.fmt.allocPrint(allocator, "h|{d}", .{idx});
        choices[next] = stringChoice(text);
        next += 1;
    }
    for (programs, 0..) |_, idx| {
        const text = try std.fmt.allocPrint(allocator, "p|{d}", .{idx});
        choices[next] = stringChoice(text);
        next += 1;
    }
    return choices;
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

fn iceHasSubtype(ice: state.CardInstance, subtype: []const u8) bool {
    if (hasSubtype(ice, subtype)) return true;
    // Chromatophores: hosted trojan with gain_subtype adds all subtypes to host ICE
    for (ice.hosted) |hosted| {
        for (hosted.static_abilities) |sa| {
            if (sa.kind == .gain_subtype) return true;
        }
    }
    return false;
}

fn canBreakIceType(breaker: state.CardInstance, ice: state.CardInstance) bool {
    if (hasSubtype(breaker, "AI")) return true;
    if (hasSubtype(breaker, "Fracter") and iceHasSubtype(ice, "Barrier")) return true;
    if (hasSubtype(breaker, "Killer") and iceHasSubtype(ice, "Sentry")) return true;
    if (hasSubtype(breaker, "Decoder") and iceHasSubtype(ice, "Code Gate")) return true;
    return false;
}

pub fn effectiveStrength(card: state.CardInstance) u8 {
    return card.current_strength orelse card.strength orelse 0;
}

fn effectiveIceStrength(g: *const Game, card: state.CardInstance, server_path: []const []const u8, ice_strength_modifier: i8) u8 {
    _ = server_path;
    const base = card.strength orelse 0;
    const static_bonus = sumCardStaticEffects(g, &card, .self_strength, null);
    const total = @as(i16, base) + static_bonus + @as(i16, ice_strength_modifier);
    return if (total > 0) @intCast(total) else 0;
}

pub fn effectiveIceStrengthForDisplay(generated: *const Game, server_index: usize, ice_index: usize) ?u8 {
    if (server_index >= generated.corp_servers.items.len) return null;
    const server = generated.corp_servers.items[server_index];
    if (ice_index >= server.ices.items.len) return null;

    const ice = server.ices.items[ice_index];
    if (ice.strength == null) return null;

    var modifier: i8 = 0;
    if (generated.run) |run| {
        if (run.server.len > 0 and std.mem.eql(u8, run.server[0], server.name)) {
            if (run.current_ice_index) |current_ice_idx| {
                const ice_count = server.ices.items.len;
                if (current_ice_idx < ice_count) {
                    const actual_ice_idx = ice_count - 1 - current_ice_idx;
                    if (actual_ice_idx == ice_index) {
                        modifier = @intCast(@as(i16, @truncate(sumFloatingEffects(generated, .ice_strength_modifier))));
                    }
                }
            }
        }
    }

    const server_path = [_][]const u8{server.name};
    return effectiveIceStrength(generated, ice, &server_path, modifier);
}

fn isRemoteServerPath(server_path: []const []const u8) bool {
    if (server_path.len == 0) return false;
    return std.mem.startsWith(u8, server_path[0], "remote");
}

fn wildcat_strike_choices(allocator: std.mem.Allocator) ![]const state.PromptChoice {
    const choices = try allocator.alloc(state.PromptChoice, 2);
    choices[0] = stringChoice("Runner gains 6 [Credits]");
    choices[1] = stringChoice("Runner draws 4 cards");
    return choices;
}

fn applyPlayFromHand(
    generated: *Game,
    side: state.Side,
    card_index: u8,
) !void {
    if (generated.end_turn) return error.TurnNotStarted;
    if (generated.active_player != side) return error.NotActivePlayer;

    switch (side) {
        .corp => try applyCorpPlayFromHand(generated, card_index),
        .runner => try applyRunnerPlayFromHand(generated, card_index),
    }
}

fn applyCorpPlayFromHand(
    generated: *Game,
    card_index: u8,
) !void {
    if (card_index >= generated.corp_hand.items.len) return error.InvalidCardIndex;

    const card = generated.corp_hand.items[card_index];
    const card_type = card.card_type orelse return error.MissingCardType;

    if (std.mem.eql(u8, card_type, "Operation")) {
        try playCorpOperation(generated, card_index, card);
        return;
    }

    if (card.install.kind != .none) {
        const allocator = generated.arena.allocator();
        const is_ice = std.mem.eql(u8, card_type, "ICE");
        generated.corp_prompt_state = .{
            .prompt_type = try allocator.dupe(u8, prompt_install_destination),
            .choices = if (is_ice)
                try iceInstallChoices(allocator, generated)
            else
                try installChoicesForCard(allocator, card.install.kind, generated),
            .source_card = card,
        };
        generated.pending_install = .{
            .card = card,
            .card_index = card_index,
        };
        generated.decision_side = .corp;
        generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
        return;
    }

    return error.UnsupportedCardType;
}

fn applyPendingInstallChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    const source_card = (if (generated.corp_prompt_state) |ps| ps.source_card else null) orelse return error.MissingSourceCard;
    const pending_install = generated.pending_install orelse return error.MissingPendingInstall;
    if (pending_install.card.install.kind != source_card.install.kind) return error.UnsupportedPrompt;

    try spendClicks(generated, .corp, 1);

    // ICE install cost: credits equal to the number of ICE already on the server
    const card_type = pending_install.card.card_type orelse "";
    if (std.mem.eql(u8, card_type, "ICE")) {
        const ice_cost = iceInstallCost(generated, choice_text);
        try spendCredits(generated, .corp, ice_cost);
    }

    _ = try removeCardFromHand(generated, .corp, pending_install.card_index);
    var installed = pending_install.card;
    installed.credit_counter = installed.initial_credit_counters;
    clearAbilityUsage(&installed);
    try installCard(generated, installed, choice_text);

    generated.systemMsg(.corp, installed.code orelse 0, "Corp spends [click] to install {s} in {s}.", .{ installed.title, choice_text });

    generated.corp_prompt_state = null;
    generated.pending_install = null;
    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
}

fn iceInstallCost(generated: *const Game, choice_text: []const u8) u16 {
    const server_index: ?usize = if (std.mem.eql(u8, choice_text, "HQ"))
        0
    else if (std.mem.eql(u8, choice_text, "R&D"))
        1
    else if (std.mem.eql(u8, choice_text, "Archives"))
        2
    else if (std.mem.eql(u8, choice_text, "New remote"))
        null
    else
        null;

    const idx = server_index orelse return 0; // New remote has no existing ICE
    if (idx >= generated.corp_servers.items.len) return 0;
    return @intCast(generated.corp_servers.items[idx].ices.items.len);
}

fn applyAccessPromptChoice(
    generated: *Game,
    side: state.Side,
    choice_text: []const u8,
) !void {
    if (side != .runner) return error.UnsupportedSide;
    const accessed = (if (generated.runner_prompt_state) |ps| ps.source_card else null) orelse return error.MissingSourceCard;
    // Check for trash/no-action choices first
    if (std.mem.eql(u8, choice_text, "No action")) {
        try finishAccessCard(generated);
        return;
    }
    if (std.mem.startsWith(u8, choice_text, "Pay ") and std.mem.endsWith(u8, choice_text, " to trash")) {
        try applyTrashOnAccess(generated, accessed);
        return;
    }
    // Generic access ability dispatch (Carnivore, Gourmand, etc.)
    if (try applyAccessAbilityChoice(generated, choice_text)) {
        return;
    }
    const is_agenda = if (accessed.card_type) |ct| std.mem.eql(u8, ct, "Agenda") else false;
    if (is_agenda) {
        try applyStealAgendaChoice(generated, accessed, choice_text);
    } else {
        return error.UnsupportedAccessTarget;
    }
}

/// Generic access ability dispatch: find an access ability whose label matches choice_text, invoke it.
fn applyAccessAbilityChoice(generated: *Game, choice_text: []const u8) !bool {
    // Search all runner rig zones for cards with is_access_ability
    const rig_zones = [_]*std.ArrayListUnmanaged(state.CardInstance){
        &generated.runner_rig_hardware,
        &generated.runner_rig_program,
        &generated.runner_rig_resources,
    };
    for (rig_zones) |zone| {
        for (zone.items) |*card| {
            for (card.abilities) |ability| {
                if (!ability.is_access_ability) continue;
                const label = ability.label orelse continue;
                if (!std.mem.eql(u8, label, choice_text)) continue;
                if (ability.on_use) |handler| {
                    try handler(effectContext(generated), card);
                    return true;
                }
            }
        }
    }
    return false;
}

fn applyTrashOnAccess(generated: *Game, accessed: state.CardInstance) !void {
    const spec = lookupCardSpec(accessed) orelse return error.UnsupportedAccessTarget;
    const trash_cost = spec.trash_cost orelse return error.UnsupportedAccessTarget;
    try spendCredits(generated, .runner, trash_cost);
    if (trash_cost > 0) {
        generated.systemMsg(.runner, accessed.code orelse 0, "Runner pays {d} [credit{s}] to trash {s}.", .{
            trash_cost, if (trash_cost != 1) "s" else "", accessed.title,
        });
    } else {
        generated.systemMsg(.runner, accessed.code orelse 0, "Runner trashes {s}.", .{accessed.title});
    }
    // Clear access prompt before firing event — otherwise hasActivePrompt sees the
    // stale access prompt and short-circuits, skipping finishAccessCard
    generated.runner_prompt_state = null;
    // Fire runner_trash_corp_card event (Loup trigger)
    generated.turn_events.runner_trash_corp_card_count += 1;
    if (try fireEvent(generated, .runner_trash_corp_card)) return;
    try removeCurrentAccessedCard(generated);
    // Move to corp discard
    try appendDiscardCard(generated, .corp, accessed);
    try finishAccessCard(generated);
}

fn finishAccessCard(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.runner_prompt_state = null;

    if (generated.run == null) {
        generated.pending_access = null;
        try restorePriorityAfterPrompt(generated);
        return;
    }

    const run = &generated.run.?;

    // If more accesses remain, immediately prepare the next access
    // (matches Clojure's recursive access flow — no continues between accesses)
    if (run.accesses_remaining > 0) {
        if (try prepareNextAccess(generated)) {
            run.phase = try allocator.dupe(u8, "success");
            generated.decision_side = .runner;
            if (generated.runner_prompt_state) |ps| {
                generated.legal_actions = try promptChoiceActions(allocator, .runner, ps);
            } else {
                generated.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
            }
            return;
        }
    }

    if (std.mem.eql(u8, run.server[0], "rnd")) {
        run.phase = try allocator.dupe(u8, "success");
        generated.decision_side = .runner;
        generated.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
        return;
    }

    try completeRunAfterAccess(generated);
}

fn applyStealAgendaChoice(
    generated: *Game,
    accessed: state.CardInstance,
    choice_text: []const u8,
) !void {
    if (!std.mem.eql(u8, choice_text, "Steal")) return error.UnsupportedChoice;

    const stolen_points = accessed.agenda_points orelse return error.MissingAgendaPoints;
    generated.runner_agenda_point += stolen_points;
    generated.systemMsg(.runner, accessed.code orelse 0, "Runner steals {s} and gains {d} agenda point{s}.", .{
        accessed.title, stolen_points, if (stolen_points != 1) "s" else "",
    });
    const is_central = if (generated.run) |run| isCentralRunServer(run.server) else false;
    // Apply tags_on_steal floating effects immediately on steal
    const tags_from_effects = sumFloatingEffects(generated, .tags_on_steal);
    if (tags_from_effects > 0) {
        _ = addRunnerTag(generated, @intCast(tags_from_effects)) catch {};
    }
    try collectEventHandlers(generated, .agenda_stolen);

    // On-steal agenda effects
    const pending_allocator = generated.backing_allocator;
    if (lookupCardSpec(accessed)) |spec| {
        switch (spec.on_steal.kind) {
            .rez_ice_free => {
                try generated.pending_effects.append(pending_allocator, .{ .deferred_prompt = .{
                    .card = accessed,
                    .on_choice = null,
                    .open_fn = &openRezIceFreeForSteal,
                } });
            },
            .give_runner_tag => {
                const amount = spec.on_steal.amount;
                if (generated.runner_tag == null) {
                    generated.runner_tag = .{ .base = 0, .total = amount, .is_tagged = amount > 0 };
                } else {
                    generated.runner_tag.?.total += amount;
                    generated.runner_tag.?.is_tagged = generated.runner_tag.?.total > 0;
                }
                generated.systemMsg(.corp, 0, "Runner gains {d} tag{s}.", .{ amount, if (amount != 1) @as([]const u8, "s") else "" });
                if (amount > 0) {
                    generated.turn_events.runner_gain_tag_count += 1;
                    try collectEventHandlers(generated, .runner_gain_tag);
                }
            },
            .none => {},
            else => {},
        }
    }
    try generated.pending_effects.append(pending_allocator, .{ .finish_steal = .{
        .accessed = accessed,
        .is_central = is_central,
    } });
    if (try drainPendingEffects(generated)) return;
}

fn beginRezIceFreePrompt(
    generated: *Game,
    accessed: state.CardInstance,
) !bool {
    const allocator = generated.arena.allocator();
    const choices = try rezIceFreeChoices(allocator, generated.corp_servers.items);
    if (choices.len == 0) return false;

    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "waiting"),
        .choices = &.{},
        .source_card = null,
    };
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_rez_ice_free),
        .choices = choices,
        .source_card = accessed,
    };
    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(
        allocator,
        .corp,
        generated.corp_prompt_state.?,
    );
    return true;
}

fn beginRezIceFreePromptForScore(
    generated: *Game,
    scored_agenda: state.CardInstance,
) !bool {
    const allocator = generated.arena.allocator();
    const choices = try rezIceFreeChoices(allocator, generated.corp_servers.items);
    if (choices.len == 0) return false;

    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_rez_ice_free_score),
        .choices = choices,
        .source_card = scored_agenda,
    };
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "waiting"),
        .choices = &.{},
        .source_card = null,
    };
    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(
        allocator,
        .corp,
        generated.corp_prompt_state.?,
    );
    return true;
}

/// Wrapper for deferred_prompt: open rez-ice-free prompt after scoring
fn openRezIceFreeForScore(g: *Game, card: state.CardInstance, _: ?*const fn (*state.EffectContext, []const u8) anyerror!void) anyerror!bool {
    return beginRezIceFreePromptForScore(g, card);
}

/// Wrapper for deferred_prompt: open rez-ice-free prompt after stealing
fn openRezIceFreeForSteal(g: *Game, card: state.CardInstance, _: ?*const fn (*state.EffectContext, []const u8) anyerror!void) anyerror!bool {
    return beginRezIceFreePrompt(g, card);
}

/// Wrapper for deferred_prompt: open runner discard-program-to-deck prompt
fn openRunnerDiscardToDeckPrompt(g: *Game, card: state.CardInstance, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) anyerror!bool {
    return beginRunnerDiscardProgramToDeckPromptWithChoice(g, card, on_choice);
}

fn applyRezIceFreeChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    if (!try rezInstalledIceByTitle(generated, choice_text)) return error.UnsupportedChoice;
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    _ = try resumePendingEffects(generated);
}

fn applyRezIceFreeScoreChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    if (!try rezInstalledIceByTitle(generated, choice_text)) return error.UnsupportedChoice;
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
}

fn continueOrCompleteAfterSteal(
    generated: *Game,
    is_central: bool,
) !void {
    updateTerminalState(generated);
    if (generated.game_over) return;

    const allocator = generated.arena.allocator();
    if (is_central) {
        generated.runner_prompt_state = null;
        generated.corp_prompt_state = null;
        generated.run.?.no_action = null;
        if (generated.run.?.accesses_remaining > 0) {
            generated.run.?.phase = try allocator.dupe(u8, "success");
            generated.decision_side = .corp;
            generated.legal_actions = try continueActionsForRun(allocator, .corp, generated.run);
            return;
        }
        try completeRunWithoutAccess(generated);
        return;
    }
    try completeRunWithoutAccess(generated);
}

fn rezIceFreeChoices(
    allocator: std.mem.Allocator,
    servers: []const MutableServer,
) ![]const state.PromptChoice {
    var count: usize = 0;
    for (servers) |server| {
        for (server.ices.items) |ice| {
            if (!ice.rezzed) count += 1;
        }
    }
    if (count == 0) return try allocator.alloc(state.PromptChoice, 0);

    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    for (servers) |server| {
        for (server.ices.items) |ice| {
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
    const run = generated.run orelse return error.NoRunInProgress;
    if (!run.jack_out_available) return error.JackOutNotAvailable;

    generated.systemMsg(.runner, 0, "Runner jacks out.", .{});
    const allocator = generated.arena.allocator();
    endOfRunCleanup(generated);
    generated.run = null;
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    generated.runner_run_credit = 0;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(
        allocator,
        generated,
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
    const run = generated.run orelse return error.NoRunInProgress;
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
        if (ice.abilities.len == 0) return error.NoBioroidAbility;
        const bioroid_ability = ice.abilities[0];
        const click_cost = if (bioroid_ability.cost) |c| c.clicks else return error.NoBioroidAbility;

        if (generated.runner_click < click_cost) return error.InsufficientClicks;
        generated.runner_click -= click_cost;

        const break_qty = bioroid_ability.break_count;
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

            if (!isIcebreaker(icebreaker)) return error.NotAnIcebreaker;

            // Validate subtype matching
            if (!canBreakIceType(icebreaker, ice.*)) return error.CannotBreakIceType;
            // Validate strength (ICE strength includes remote bonus)
            const ice_str_mod: i8 = @intCast(@as(i16, @truncate(sumFloatingEffects(generated, .ice_strength_modifier))));
            const ice_str = effectiveIceStrength(generated, ice.*, run.server, ice_str_mod);
            if (effectiveStrength(icebreaker) < ice_str) return error.InsufficientStrength;

            // Check which subroutine to break based on subroutine_index
            const sub_idx: u8 = switch (subroutine_index.kind) {
                .number => @intCast(subroutine_index.number orelse return error.InvalidSubroutine),
                else => return error.InvalidSubroutine,
            };

            if (sub_idx >= ice.subroutines.len) return error.InvalidSubroutine;

            // Check if we have enough credits
            const break_credit = if (icebreaker.abilities.len > 0) icebreaker.abilities[0].credit_cost else 0;
            if (generated.runner_credit < break_credit) return error.InsufficientCredits;
            generated.runner_credit -= break_credit;

            // Mark subroutine as broken
            ice.broken_subroutines |= (@as(u16, 1) << @as(u4, @intCast(sub_idx)));

            // Track that this breaker was used
            try addFloatingEffect(generated, .{ .kind = .icebreaker_broke, .duration = .end_of_run, .source_code = generated.runner_rig_program.items[icebreaker_idx].instance_id });
        } else {
            return error.NotAnIcebreaker;
        }
    }

    // Generate new legal actions - still in encounter, can break more or continue
    const allocator = generated.arena.allocator();
    generated.decision_side = .runner;
    generated.legal_actions = try encounterActionsForState(allocator, generated, ice.*);
}

fn removeRunAccessedCard(
    generated: *Game,
    run: state.RunState,
) !void {
    const access_index = run.access_card_index orelse return error.MissingAccessTarget;
    const target_server = try findServerByRunPath(generated.corp_servers.items, run.server);
    if (std.mem.eql(u8, run.server[0], "hq")) {
        if (access_index >= generated.corp_hand.items.len) return error.MissingAccessTarget;
        _ = generated.corp_hand.orderedRemove(access_index);
        // Adjust tracked accessed indexes: shift down indexes > removed index
        if (generated.run) |*mutable_run| {
            adjustAccessedIndexes(mutable_run, access_index);
        }
        return;
    }
    if (std.mem.eql(u8, run.server[0], "rnd")) {
        if (access_index >= generated.corp_deck.items.len) return error.MissingAccessTarget;
        _ = generated.corp_deck.orderedRemove(access_index);
        return;
    }
    if (std.mem.eql(u8, run.server[0], "archives")) {
        if (access_index >= generated.corp_discard.items.len) return error.MissingAccessTarget;
        _ = generated.corp_discard.orderedRemove(access_index);
        return;
    }

    _ = removeServerContentCard(generated, target_server.index, 0);
    const updated_server = generated.corp_servers.items[target_server.index];
    if (target_server.index >= 3 and updated_server.ices.items.len == 0 and updated_server.content.items.len == 0) {
        var removed_server = generated.corp_servers.orderedRemove(target_server.index);
        removed_server.ices.deinit(generated.backing_allocator);
        removed_server.content.deinit(generated.backing_allocator);
    }
}

fn removePendingAccessedCard(generated: *Game, pending_access: PendingAccess) !void {
    switch (pending_access.zone) {
        .corp_hand => {
            if (pending_access.card_index >= generated.corp_hand.items.len) return error.MissingAccessTarget;
            _ = generated.corp_hand.orderedRemove(pending_access.card_index);
        },
        .corp_deck => {
            if (pending_access.card_index >= generated.corp_deck.items.len) return error.MissingAccessTarget;
            _ = generated.corp_deck.orderedRemove(pending_access.card_index);
        },
        .corp_discard => {
            if (pending_access.card_index >= generated.corp_discard.items.len) return error.MissingAccessTarget;
            _ = generated.corp_discard.orderedRemove(pending_access.card_index);
        },
        .corp_server_content => {
            _ = removeServerContentCard(generated, pending_access.server_index, pending_access.card_index);
            const updated_server = generated.corp_servers.items[pending_access.server_index];
            if (pending_access.server_index >= 3 and updated_server.ices.items.len == 0 and updated_server.content.items.len == 0) {
                var removed_server = generated.corp_servers.orderedRemove(pending_access.server_index);
                removed_server.ices.deinit(generated.backing_allocator);
                removed_server.content.deinit(generated.backing_allocator);
            }
        },
    }
}

fn removeCurrentAccessedCard(generated: *Game) !void {
    if (generated.run) |run| {
        try removeRunAccessedCard(generated, run);
        return;
    }
    const pending_access = generated.pending_access orelse return error.MissingAccessTarget;
    try removePendingAccessedCard(generated, pending_access);
    generated.pending_access = null;
}

fn applyAccessCleanupChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    const accessed = (if (generated.corp_prompt_state) |ps| ps.source_card else null) orelse return error.MissingSourceCard;
    const is_agenda = if (accessed.card_type) |ct| std.mem.eql(u8, ct, "Agenda") else false;
    if (is_agenda) {
        if (!std.mem.eql(u8, choice_text, "Done")) return error.UnsupportedChoice;
        try completeRunAfterAccess(generated);
    } else {
        return error.UnsupportedChoice;
    }
}

fn playCorpOperation(
    generated: *Game,
    card_index: u8,
    card: state.CardInstance,
) !void {
    _ = try removeCardFromHand(generated, .corp, card_index);
    try spendClicks(generated, .corp, 1);
    try spendCredits(generated, .corp, card.cost orelse 0);
    try logCorpOperationPlay(generated, card, false);
    try resolveCorpOperation(generated, card);
    try appendDiscardCard(generated, .corp, card);
}

fn applyCorpFlashback(generated: *Game, card_index: u8) !void {
    if (card_index >= generated.corp_discard.items.len) return error.InvalidCardIndex;
    const card = generated.corp_discard.items[card_index];
    if (!isCorpFlashbackPlayable(generated, card)) return error.UnsupportedOperation;

    const spec = lookupCardSpec(card) orelse return error.UnsupportedOperation;
    const play_ability = findPlayAbility(spec.abilities) orelse return error.UnsupportedOperation;

    _ = generated.corp_discard.orderedRemove(card_index);
    try spendClicks(generated, .corp, play_ability.flashback_extra_clicks);
    try spendCredits(generated, .corp, card.cost orelse 0);
    try logCorpOperationPlay(generated, card, true);
    try resolveCorpOperation(generated, card);
    if (play_ability.flashback_gain_clicks > 0) {
        generated.corp_click += play_ability.flashback_gain_clicks;
        generated.decision_side = .corp;
        generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
    }
}

fn logCorpOperationPlay(generated: *Game, card: state.CardInstance, from_archives: bool) !void {
    const cost = card.cost orelse 0;
    if (from_archives) {
        if (cost > 0) {
            generated.systemMsg(.corp, card.code orelse 0, "Corp spends [click] and pays {d} [credit{s}] to play {s} from Archives.", .{
                cost, if (cost != 1) "s" else "", card.title,
            });
        } else {
            generated.systemMsg(.corp, card.code orelse 0, "Corp spends [click] to play {s} from Archives.", .{card.title});
        }
        return;
    }
    if (cost > 0) {
        generated.systemMsg(.corp, card.code orelse 0, "Corp spends [click] and pays {d} [credit{s}] to play {s}.", .{
            cost, if (cost != 1) "s" else "", card.title,
        });
    } else {
        generated.systemMsg(.corp, card.code orelse 0, "Corp spends [click] to play {s}.", .{card.title});
    }
}

fn resolveCorpOperation(generated: *Game, card: state.CardInstance) !void {
    const spec = lookupCardSpec(card) orelse return error.UnsupportedOperation;
    const play_ability = findPlayAbility(spec.abilities) orelse return error.UnsupportedOperation;
    const handler = play_ability.on_use orelse return error.UnsupportedOperation;
    var mutable_card = card;
    try handler(effectContext(generated), &mutable_card);
    if (spec.on_play_msg) |msg| {
        generated.systemMsg(.corp, spec.code, "Corp uses {s} to {s}", .{ spec.title, msg });
    }
    if (generated.corp_prompt_state != null or generated.runner_prompt_state != null) return;
    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
}

fn applyRunnerPlayFromHand(
    generated: *Game,
    card_index: u8,
) !void {
    if (card_index >= generated.runner_hand.items.len) return error.InvalidCardIndex;

    const card = generated.runner_hand.items[card_index];
    if (card.runner_install.kind != .none) return applyInstallFromHand(generated, .runner, card_index);

    const card_type = card.card_type orelse return error.MissingCardType;
    if (!std.mem.eql(u8, card_type, "Event")) return error.UnsupportedCardType;

    const spec = lookupCardSpec(card) orelse return error.UnsupportedCardType;

    // Common event play flow: spend click, pay cost, remove from hand, discard, log
    const ev_cost = card.cost orelse 0;
    try spendClicks(generated, .runner, 1);
    try spendCredits(generated, .runner, ev_cost);
    _ = try removeCardFromHand(generated, .runner, card_index);
    try appendDiscardCard(generated, .runner, card);
    if (ev_cost > 0) {
        generated.systemMsg(.runner, card.code orelse 0, "Runner spends [click] and pays {d} [credit{s}] to play {s}.", .{
            ev_cost, if (ev_cost != 1) "s" else "", card.title,
        });
    } else {
        generated.systemMsg(.runner, card.code orelse 0, "Runner spends [click] to play {s}.", .{card.title});
    }
    const play_ability = findPlayAbility(spec.abilities) orelse return error.UnsupportedCardType;
    const handler = play_ability.on_use orelse return error.UnsupportedCardType;
    var mutable_card = card;
    try handler(effectContext(generated), &mutable_card);
    if (spec.on_play_msg) |msg| {
        generated.systemMsg(.runner, spec.code, "Runner uses {s} to {s}", .{ spec.title, msg });
    }
}

fn applyInstallFromHand(
    generated: *Game,
    side: state.Side,
    card_index: u8,
) !void {
    if (generated.end_turn) return error.TurnNotStarted;
    if (generated.active_player != side) return error.NotActivePlayer;
    if (side != .runner) return error.UnsupportedSide;
    try beginRunnerInstallFromHand(generated, card_index, true);
}

fn runnerInstallCostForCard(generated: *const Game, card: *const state.CardInstance) u16 {
    var install_cost: u16 = card.cost orelse 0;
    if (card.runner_install.install_cost_reduction_if_successful_run > 0 and generated.runner_successful_run_this_turn) {
        install_cost = if (install_cost >= card.runner_install.install_cost_reduction_if_successful_run)
            install_cost - card.runner_install.install_cost_reduction_if_successful_run
        else
            0;
    }
    return applyCostModifier(install_cost, runnerInstallCostModifier(generated, card));
}

fn hasInstalledIce(generated: *const Game) bool {
    for (generated.corp_servers.items) |server| {
        if (server.ices.items.len > 0) return true;
    }
    return false;
}

fn runnerHandInstallableByEffect(generated: *const Game, card: state.CardInstance) bool {
    if (card.runner_install.kind == .none) return false;
    if (generated.runner_credit < runnerInstallCostForCard(generated, &card)) return false;
    if (hasSubtype(card, "Trojan") and !hasInstalledIce(generated)) return false;
    return true;
}

fn beginRunnerOptionalInstallConfirmPrompt(generated: *Game, source_card: state.CardInstance, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
    const allocator = generated.arena.allocator();
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "runner-bonus-install-confirm"),
        .choices = try allocator.dupe(state.PromptChoice, &.{ stringChoice("Yes"), stringChoice("No") }),
        .source_card = source_card,
        .on_choice = on_choice,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
}

fn beginRunnerOptionalInstallPrompt(generated: *Game, source_card: state.CardInstance, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
    const allocator = generated.arena.allocator();
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);

    for (generated.runner_hand.items, 0..) |card, idx| {
        if (!runnerHandInstallableByEffect(generated, card)) continue;
        try choices.append(allocator, .{
            .kind = .card,
            .text = try std.fmt.allocPrint(allocator, "{s}", .{card.title}),
            .card = .{ .title = card.title, .code = card.code, .side = .runner, .index = @intCast(idx) },
        });
    }

    if (choices.items.len == 0) return;

    try choices.append(allocator, stringChoice("No action"));
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "runner-bonus-install"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = source_card,
        .on_choice = on_choice,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
}

fn beginRunnerInstallFromHand(generated: *Game, card_index: u8, spend_click: bool) !void {
    if (card_index >= generated.runner_hand.items.len) return error.InvalidCardIndex;

    const card = generated.runner_hand.items[card_index];
    if (card.runner_install.kind == .none) return error.UnsupportedRunnerInstall;

    const install_cost = runnerInstallCostForCard(generated, &card);

    if (hasSubtype(card, "Trojan")) {
        const allocator = generated.arena.allocator();
        var choices: std.ArrayList(state.PromptChoice) = .empty;
        defer choices.deinit(allocator);
        for (generated.corp_servers.items, 0..) |server, si| {
            for (server.ices.items, 0..) |ice, ii| {
                const label = try std.fmt.allocPrint(allocator, "{d}|{d}|{s}", .{ si, ii, ice.title });
                try choices.append(allocator, .{ .kind = .card, .text = label, .card = .{ .title = ice.title, .printed_title = ice.title, .code = ice.code, .side = .corp } });
            }
        }
        if (choices.items.len == 0) return error.UnsupportedRunnerInstall;
        generated.pending_install = .{
            .card = card,
            .card_index = card_index,
            .runner_install_cost = install_cost,
            .runner_spend_click = spend_click,
        };
        generated.runner_prompt_state = .{
            .prompt_type = try allocator.dupe(u8, "trojan-host"),
            .choices = try choices.toOwnedSlice(allocator),
            .source_card = card,
        };
        generated.decision_side = .runner;
        generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
        return;
    }

    if (card.runner_install.kind == .program) {
        generated.pending_install = .{
            .card = card,
            .card_index = card_index,
            .runner_install_cost = install_cost,
            .runner_spend_click = spend_click,
        };
        if (try beginMuOverflowPromptWithExtra(generated, card.runner_install.mu_cost)) return;
        generated.pending_install = null;
    }

    if (spend_click) try spendClicks(generated, .runner, 1);
    try completeRunnerInstall(generated, card_index, card, install_cost, spend_click);
}

fn completeRunnerInstall(generated: *Game, card_index: u8, _: state.CardInstance, install_cost: u16, spend_click: bool) !void {
    const allocator = generated.arena.allocator();
    try spendCredits(generated, .runner, install_cost);

    var installed_card = try removeCardFromHand(generated, .runner, card_index);
    installed_card.credit_counter = installed_card.initial_credit_counters;
    clearAbilityUsage(&installed_card);
    try appendRunnerInstalledCard(generated, installed_card);
    generated.runner_install_context = .{ .install_cost = install_cost };
    defer generated.runner_install_context = null;
    switch (installed_card.runner_install.kind) {
        .hardware => {
            if (generated.runner_rig_hardware.items.len > 0) {
                if (generated.runner_rig_hardware.items[generated.runner_rig_hardware.items.len - 1].on_install) |callback| {
                    try callback(effectContext(generated), &generated.runner_rig_hardware.items[generated.runner_rig_hardware.items.len - 1]);
                }
            }
        },
        .resource => {
            if (generated.runner_rig_resources.items.len > 0) {
                if (generated.runner_rig_resources.items[generated.runner_rig_resources.items.len - 1].on_install) |callback| {
                    try callback(effectContext(generated), &generated.runner_rig_resources.items[generated.runner_rig_resources.items.len - 1]);
                }
            }
        },
        .program, .none => {},
    }

    if (spend_click) {
        if (install_cost > 0) {
            generated.systemMsg(.runner, installed_card.code orelse 0, "Runner spends [click] and pays {d} [credit{s}] to install {s}.", .{
                install_cost, if (install_cost != 1) "s" else "", installed_card.title,
            });
        } else {
            generated.systemMsg(.runner, installed_card.code orelse 0, "Runner spends [click] to install {s}.", .{installed_card.title});
        }
    } else if (install_cost > 0) {
        generated.systemMsg(.runner, installed_card.code orelse 0, "Runner pays {d} [credit{s}] to install {s}.", .{
            install_cost, if (install_cost != 1) "s" else "", installed_card.title,
        });
    } else {
        generated.systemMsg(.runner, installed_card.code orelse 0, "Runner installs {s}.", .{installed_card.title});
    }

    if (installed_card.runner_install.kind == .program) {
        generated.turn_events.programs_installed_this_turn += 1;
        if (generated.runner_memory) |*mem| {
            mem.used += installed_card.runner_install.mu_cost;
            mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
        }
        if (generated.runner_rig_program.items.len > 0) {
            applyRunnerInstalledCardCounters(generated, &generated.runner_rig_program.items[generated.runner_rig_program.items.len - 1]);
        }
    }

    generated.pending_install = null;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
}

fn applyRunnerRunTargetChoice(
    generated: *Game,
    server: []const u8,
) !void {
    const source_card = (if (generated.runner_prompt_state) |ps| ps.source_card else null) orelse return error.MissingSourceCard;
    const spec = lookupCardSpec(source_card) orelse return error.UnsupportedPrompt;
    const allocator = generated.arena.allocator();

    const run_server = try canonicalRunServer(allocator, server);
    trackMadeRun(generated, run_server);
    const target_server = try findServerByRunPath(generated.corp_servers.items, run_server);
    const initial_position: u8 = @intCast(target_server.slot.ices.items.len);

    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    generated.run = .{
        .server = run_server,
        .position = initial_position,
        .phase = try allocator.dupe(u8, "initiation"),
        .encounter_phase = .none,
        .current_ice_index = null,
        .corp_auto_no_action = false,
        .no_action = null,
        .accesses_remaining = 0,
        .accessed_count = 0,
        .accessed_card_indexes = .{ null, null, null, null },
        .access_card_index = null,
        .jack_out_available = false,
    };
    // Add run-scoped floating effects from card spec
    if (spec.run_credits > 0) {
        try addFloatingEffect(generated, .{ .kind = .run_credits, .duration = .end_of_run, .value = @intCast(spec.run_credits) });
    }
    if (spec.run_rez_cost_bonus > 0) {
        try addFloatingEffect(generated, .{ .kind = .rez_cost_bonus, .duration = .end_of_run, .value = @intCast(spec.run_rez_cost_bonus) });
    }
    if (spec.successful_run_access_bonus > 0) {
        try addFloatingEffect(generated, .{ .kind = .access_bonus, .duration = .end_of_run, .value = @intCast(spec.successful_run_access_bonus) });
    }
    if (spec.successful_run_effect == .draw_cards and spec.successful_run_draw_cards > 0) {
        try addFloatingEffect(generated, .{ .kind = .successful_run_draw, .duration = .end_of_run, .value = @intCast(spec.successful_run_draw_cards) });
    }
    // Fire run_begins event (Side Hustle: place credit)
    if (try fireEvent(generated, .run_begins)) return;
    generated.decision_side = .corp;
    generated.legal_actions = try continueActions(allocator, .corp);
}

fn applyRun(
    generated: *Game,
    side: state.Side,
    server: []const u8,
) !void {
    if (generated.end_turn) return error.TurnNotStarted;
    if (generated.active_player != side) return error.NotActivePlayer;
    if (side != .runner) return error.UnsupportedSide;

    const allocator = generated.arena.allocator();
    try spendClicks(generated, .runner, 1);

    const run_server = try canonicalRunServer(allocator, server);
    generated.systemMsg(.runner, 0, "Runner spends [click] to make a run on {s}.", .{server});
    trackMadeRun(generated, run_server);
    const target_server = try findServerByRunPath(generated.corp_servers.items, run_server);
    const initial_position: u8 = @intCast(target_server.slot.ices.items.len);
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    generated.run = .{
        .server = run_server,
        .position = initial_position,
        .phase = try allocator.dupe(u8, "initiation"),
        .encounter_phase = .none,
        .current_ice_index = null,
        .corp_auto_no_action = false,
        .no_action = null,
        .accesses_remaining = 0,
        .accessed_count = 0,
        .accessed_card_indexes = .{ null, null, null, null },
        .access_card_index = null,
        .jack_out_available = false,
    };
    // Fire run_begins event (Side Hustle: place credit)
    if (try fireEvent(generated, .run_begins)) return;
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, generated.run, generated);
}

fn applyRunFromAbility(
    generated: *Game,
    server: []const u8,
    source_instance_id: ?u32,
) !void {
    const allocator = generated.arena.allocator();
    const run_server = try canonicalRunServer(allocator, server);
    const target_server = try findServerByRunPath(generated.corp_servers.items, run_server);
    const initial_position: u8 = @intCast(target_server.slot.ices.items.len);

    // Track made_run for this server
    trackMadeRun(generated, run_server);

    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    generated.run = .{
        .server = run_server,
        .position = initial_position,
        .phase = try allocator.dupe(u8, "initiation"),
        .encounter_phase = .none,
        .current_ice_index = null,
        .corp_auto_no_action = false,
        .no_action = null,
        .accesses_remaining = 0,
        .accessed_count = 0,
        .accessed_card_indexes = .{ null, null, null, null },
        .access_card_index = null,
        .jack_out_available = false,
        .source_instance_id = source_instance_id,
    };
    // Fire run_begins event (Side Hustle: place credit)
    if (try fireEvent(generated, .run_begins)) return;
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, generated.run, generated);
}

fn applyContinue(
    generated: *Game,
    side: state.Side,
) !void {
    const allocator = generated.arena.allocator();

    // Corp phase 12: both sides pass priority before main phase
    if (generated.corp_phase_12) {
        if (side == .corp) {
            // Corp passed, now runner passes
            generated.decision_side = .runner;
            generated.legal_actions = try continueActions(allocator, .runner);
            return;
        }
        if (side == .runner) {
            // Both passed — end phase 12, enter main corp turn
            try endCorpPhase12(generated);
            return;
        }
    }

    const run = &generated.run;
    if (run.* == null) return error.NoRunInProgress;
    if (generated.decision_side != side) return error.NotCurrentDecision;

    if (std.mem.eql(u8, run.*.?.phase, "success")) return try advanceSuccessPhase(generated, side);

    if (run.*.?.no_action == null) {
        run.*.?.no_action = side;
        generated.decision_side = otherSide(side);
        generated.legal_actions = try continueActionsForRunWithRez(allocator, otherSide(side), run.*, generated);
        return;
    }

    if (run.*.?.no_action.? == side) return error.InvalidAction;

    run.*.?.no_action = null;
    if (std.mem.eql(u8, run.*.?.phase, "initiation")) return try advanceInitiationPhase(generated);
    if (std.mem.eql(u8, run.*.?.phase, "approach-ice")) return try advanceApproachIcePhase(generated);
    if (std.mem.eql(u8, run.*.?.phase, "encounter-ice")) return try advanceEncounterPhase(generated);
    if (std.mem.eql(u8, run.*.?.phase, "movement")) return try advanceMovementPhase(generated);

    return error.UnsupportedRunPhase;
}

fn applyRezApproachedIce(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const target = (try currentApproachedIce(generated)) orelse return error.UnsupportedChoice;
    if (target.ice.rezzed) return error.UnsupportedChoice;
    const rez_cost = target.ice.cost orelse 0;
    _ = generated.run orelse return error.NoRunInProgress;
    const floating_rez_bonus: u16 = @intCast(@max(0, sumFloatingEffects(generated, .rez_cost_bonus)));
    const adjusted_cost = applyCostModifier(rez_cost + floating_rez_bonus, sumStaticEffects(generated, .runner, .rez_cost, &target.ice));
    try spendCredits(generated, .corp, adjusted_cost);
    generated.corp_servers.items[target.server_index].ices.items[target.ice_index].rezzed = true;
    if (adjusted_cost > 0) {
        generated.systemMsg(.corp, target.ice.code orelse 0, "Corp pays {d} [credit{s}] to rez {s}.", .{
            adjusted_cost, if (adjusted_cost != 1) "s" else "", target.ice.title,
        });
    } else {
        generated.systemMsg(.corp, target.ice.code orelse 0, "Corp rezzes {s}.", .{target.ice.title});
    }
    // On-rez trigger: iterate event_abilities for corp_rez_ice
    const ice = &generated.corp_servers.items[target.server_index].ices.items[target.ice_index];
    for (ice.event_abilities) |ea| {
        if (ea.event == .corp_rez_ice) {
            try ea.handler(effectContext(generated), ice);
            break;
        }
    }
    // Fire corp_rez_ice event (Barry: install on rez)
    if (try fireEvent(generated, .corp_rez_ice)) return;
    // Corp still has priority during approach — regenerate actions
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, generated.run, generated);
}

fn applyRezNonIce(generated: *Game, server_name: []const u8, card_index: u8) !void {
    const allocator = generated.arena.allocator();
    const server_path = [_][]const u8{server_name};
    const target_server = try findMutableServerByRunPath(generated.corp_servers.items, &server_path);
    const server = &generated.corp_servers.items[target_server.index];

    if (card_index >= server.content.items.len) return error.InvalidCardIndex;
    var card = &server.content.items[card_index];
    if (card.rezzed) return error.AlreadyRezzed;

    const rez_cost = card.cost orelse return error.InvalidCost;
    if (generated.corp_credit < rez_cost) return error.InsufficientCredits;

    // Pay rez cost and set rezzed
    generated.corp_credit -= rez_cost;
    card.rezzed = true;

    if (rez_cost > 0) {
        generated.systemMsg(.corp, card.code orelse 0, "Corp pays {d} [credit{s}] to rez {s}.", .{
            rez_cost, if (rez_cost != 1) "s" else "", card.title,
        });
    } else {
        generated.systemMsg(.corp, card.code orelse 0, "Corp rezzes {s}.", .{card.title});
    }

    // On-rez trigger: iterate event_abilities for corp_rez_ice
    for (card.event_abilities) |ea| {
        if (ea.event == .corp_rez_ice) {
            try ea.handler(effectContext(generated), card);
            break;
        }
    }

    // After rezzing, regenerate actions with updated state
    if (generated.run != null) {
        // During a run: corp still has priority
        generated.decision_side = .corp;
        generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, generated.run, generated);
    } else {
        // Outside of a run: return to normal corp actions
        generated.decision_side = .corp;
        generated.legal_actions = try corpOpeningActionsForState(allocator, generated);
    }
}

const ApproachedIceTarget = struct {
    server_index: usize,
    ice_index: usize,
    ice: state.CardInstance,
};

// Find approached ice using internal mutable state
fn currentApproachedIceInternal(generated: *const Game) !?ApproachedIceTarget {
    const run = generated.run orelse return null;
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
fn currentApproachedIce(generated: *const Game) !?ApproachedIceTarget {
    return currentApproachedIceInternal(generated);
}

fn advanceSuccessPhase(generated: *Game, side: state.Side) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.run.?;
    if (generated.corp_prompt_state) |corp_prompt| {
        if (!std.mem.eql(u8, corp_prompt.prompt_type, "run")) {
            if (side != .corp) return error.InvalidAction;
            generated.decision_side = .corp;
            generated.legal_actions = try promptChoiceActions(allocator, .corp, corp_prompt);
            return;
        }
    }

    // Corp's success continue is a pass-through — Clojure's continue :success
    // is a no-op, so no_action stays null. Just deliver the pending access prompt.
    if (side == .corp) {
        // If runner has a pending access prompt, deliver it now
        if (generated.runner_prompt_state) |runner_prompt| {
            if (!std.mem.eql(u8, runner_prompt.prompt_type, "waiting") and !std.mem.eql(u8, runner_prompt.prompt_type, "run")) {
                generated.decision_side = .runner;
                generated.legal_actions = try promptChoiceActions(allocator, .runner, runner_prompt);
                return;
            }
        }
        generated.decision_side = .runner;
        generated.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
        return;
    }

    // Runner's success continue: both sides have now passed.
    run.no_action = null;
    if (try prepareNextAccess(generated)) {
        run.phase = try allocator.dupe(u8, "success");
        generated.decision_side = .corp;
        generated.legal_actions = try continueActionsForRun(allocator, .corp, run.*);
        return;
    }
    try completeRunWithoutAccess(generated);
}

fn enterSuccessAccessPhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.run.?;
    run.phase = try allocator.dupe(u8, "success");
    if (try prepareNextAccess(generated)) {
        // Clojure resolves the successful-run window directly into breach/access
        // unless a prompt interrupts that sequence.
        if (generated.corp_prompt_state) |cp| {
            if (!std.mem.eql(u8, cp.prompt_type, "run")) {
                generated.decision_side = .corp;
                generated.legal_actions = try promptChoiceActions(allocator, .corp, cp);
                return;
            }
        }
        if (generated.runner_prompt_state) |ps| {
            generated.decision_side = .runner;
            generated.legal_actions = try promptChoiceActions(allocator, .runner, ps);
            return;
        }
        generated.decision_side = .runner;
        generated.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
        return;
    }
    try completeRunWithoutAccess(generated);
}

fn advanceInitiationPhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.run.?;
    if (run.position == 0) {
        run.phase = try allocator.dupe(u8, "movement");
        run.jack_out_available = false;
    } else {
        run.phase = try allocator.dupe(u8, "approach-ice");
        run.jack_out_available = false;
    }
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, run.*, generated);
}

fn advanceApproachIcePhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.run.?;

    // Check if there's approached ice to encounter
    if (try currentApproachedIce(generated)) |target| {
        if (target.ice.rezzed) {
            // Enter encounter phase - runner gets to use icebreakers
            run.phase = try allocator.dupe(u8, "encounter-ice");
            run.encounter_phase = .encounter;
            // Store runner-perspective ice index for applyUseSubroutine
            const ice_count = generated.corp_servers.items[target.server_index].ices.items.len;
            run.current_ice_index = @intCast(ice_count - 1 - target.ice_index);
            // Reset broken_subroutines and expire encounter-scoped floating effects
            generated.corp_servers.items[target.server_index].ices.items[target.ice_index].broken_subroutines = 0;
            expireFloatingEffects(generated, .end_of_encounter);

            // Dynamic strength bonuses for encounter
            for (generated.runner_rig_program.items) |*prog| {
                const base_strength: i16 = prog.strength orelse 0;
                const bonus_strength = sumStaticEffects(generated, .runner, .self_strength, prog);
                prog.current_strength = clampStaticTotal(base_strength + bonus_strength);
            }

            // Check for on-encounter abilities (e.g., Funhouse)
            const ice = &generated.corp_servers.items[target.server_index].ices.items[target.ice_index];
            for (ice.event_abilities) |ea| {
                if (ea.event == .ice_encountered) {
                    try ea.handler(effectContext(generated), ice);
                    return;
                }
            }

            generated.decision_side = .runner;
            generated.legal_actions = try encounterActionsForState(allocator, generated, ice.*);
            return;
        }
    }

    // Unrezzed or no ice - move to movement
    if (run.position > 0) run.position -= 1;
    run.phase = try allocator.dupe(u8, "movement");
    run.jack_out_available = true;
    run.no_action = null;
    // Corp gets priority first in movement phase (matching Clojure)
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, run.*, generated);
}

const prompt_break_sub = "break-sub";

fn subroutineLabel(allocator: std.mem.Allocator, sub: state.SubroutineSpec, idx: usize) ![]const u8 {
    if (sub.label) |label| {
        return std.fmt.allocPrint(allocator, "{s}", .{label});
    }
    return std.fmt.allocPrint(allocator, "Sub {d}", .{idx});
}

fn openBreakSubPrompt(
    generated: *Game,
    ice: *state.CardInstance,
    breaker: state.CardInstance,
    subs_selected: u8,
) !void {
    const allocator = generated.arena.allocator();
    const break_count = if (breaker.abilities.len > 0) @max(@as(u8, 1), breaker.abilities[0].break_count) else 1;

    // Build choices: each unbroken sub + "Done"
    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
    defer choices_list.deinit(allocator);

    for (ice.subroutines, 0..) |sub, idx| {
        const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(idx))) != 0;
        if (!is_broken) {
            const label = try subroutineLabel(allocator, sub, idx);
            try choices_list.append(allocator, .{
                .kind = .number,
                .text = label,
                .number = @intCast(idx),
            });
        }
    }
    // Add "Done" choice
    try choices_list.append(allocator, stringChoice("Done"));

    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_break_sub),
        .choices = try choices_list.toOwnedSlice(allocator),
        .source_card = breaker,
    };
    // Store break state in the run
    generated.run.?.break_subs_selected = subs_selected;
    generated.run.?.break_subs_max = break_count;
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
}

fn applyBreakSubChoice(generated: *Game, choice_text: []const u8) !void {
    const allocator = generated.arena.allocator();
    const prompt = generated.runner_prompt_state orelse return error.MissingPrompt;
    const breaker = prompt.source_card orelse return error.MissingSourceCard;
    const run = &generated.run.?;

    const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
    const target_server = try findMutableServerByRunPath(generated.corp_servers.items, run.server);
    const server = &generated.corp_servers.items[target_server.index];
    const ice_count = server.ices.items.len;
    if (current_ice_idx >= ice_count) return error.InvalidIceIndex;
    const actual_ice_idx = ice_count - 1 - current_ice_idx;
    var ice = &server.ices.items[actual_ice_idx];

    if (std.mem.eql(u8, choice_text, "Done")) {
        // Done selecting — return to encounter actions
        generated.runner_prompt_state = null;
        run.break_subs_selected = 0;
        run.break_subs_max = 0;
        generated.decision_side = .runner;
        generated.legal_actions = try encounterActionsForState(allocator, generated, ice.*);
        return;
    }

    // Find the sub index from the choice — match by text against prompt choices
    var sub_idx: ?u8 = null;
    for (prompt.choices) |ch| {
        if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
            if (ch.number) |n| {
                sub_idx = @intCast(n);
                break;
            }
        }
    }
    const idx = sub_idx orelse return error.UnsupportedChoice;

    // Mark this sub as broken
    ice.broken_subroutines |= (@as(u16, 1) << @as(u4, @intCast(idx)));
    run.break_subs_selected += 1;

    // Check if we've hit the max for this activation
    if (run.break_subs_selected >= run.break_subs_max) {
        // Activation complete — return to encounter actions
        generated.runner_prompt_state = null;
        run.break_subs_selected = 0;
        run.break_subs_max = 0;
        generated.decision_side = .runner;
        generated.legal_actions = try encounterActionsForState(allocator, generated, ice.*);
        return;
    }

    // More subs can be selected in this activation — refresh prompt
    try openBreakSubPrompt(generated, ice, breaker, run.break_subs_selected);
}

fn advanceEncounterPhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();

    // Both sides passed during encounter — fire unbroken subroutines
    const current_ice_idx = generated.run.?.current_ice_index orelse return error.NoIceEncountered;
    const target_server = try findMutableServerByRunPath(generated.corp_servers.items, generated.run.?.server);
    const server_index = target_server.index;
    const server = &generated.corp_servers.items[server_index];
    const ice_count = server.ices.items.len;
    if (current_ice_idx >= ice_count) return error.InvalidIceIndex;
    const actual_ice_idx = ice_count - 1 - current_ice_idx;
    const ice = server.ices.items[actual_ice_idx];

    try resolveEncounteredIceSubroutines(generated, ice, server_index, actual_ice_idx, 0);
    if (generated.run == null) return; // ETR fired
    if (generated.corp_prompt_state) |ps| {
        if (!std.mem.eql(u8, ps.prompt_type, "run")) return; // Sub opened prompt (e.g., Brân)
    }

    // Clear temporary strength boosts on all icebreakers
    for (generated.runner_rig_program.items) |*card| {
        card.current_strength = null;
    }

    // Move to movement phase
    var run = &generated.run.?;
    if (run.position > 0) run.position -= 1;
    run.phase = try allocator.dupe(u8, "movement");
    run.encounter_phase = .none;
    run.current_ice_index = null;
    run.jack_out_available = true;
    run.no_action = null;
    // Corp gets priority first in movement phase (matching Clojure)
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, run.*, generated);
}

// --- Subroutine resolve handlers ---
// Each returns true to stop processing further subroutines, false to continue.

pub fn resolveEndTheRun(generated: *Game, _: state.SubroutineContext) anyerror!bool {
    const allocator = generated.arena.allocator();
    endOfRunCleanup(generated);
    generated.run = null;
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    generated.runner_run_credit = 0;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
    return true;
}

pub fn resolveNetDamage(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    try trashRandomRunnerHandCards(generated, ctx.amount);
    updateTerminalState(generated);
    return generated.game_over;
}

pub fn resolveBrainDamage(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    generated.runner_brain_damage += ctx.amount;
    try trashRandomRunnerHandCards(generated, ctx.amount);
    updateTerminalState(generated);
    return generated.game_over;
}

pub fn resolveTagRunner(generated: *Game, _: state.SubroutineContext) anyerror!bool {
    _ = try addRunnerTag(generated, 1);
    return false;
}

pub fn resolveTraceTag(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const allocator = generated.arena.allocator();
    const ice = generated.corp_servers.items[ctx.server_index].ices.items[ctx.ice_index];
    const run = &(generated.run orelse return error.NoRunInProgress);
    run.pending_subroutine = .{
        .server_index = ctx.server_index,
        .ice_index = ctx.ice_index,
        .subroutine_index = ctx.subroutine_index + 1,
    };
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    try choices.append(allocator, stringChoice("Take 1 tag"));
    if (generated.runner_credit >= ctx.base_trace) {
        const text = try std.fmt.allocPrint(allocator, "Pay {d} [Credits]", .{ctx.base_trace});
        try choices.append(allocator, stringChoice(text));
    }
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "trace"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = ice,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
    return true;
}

pub fn resolveGiveRunnerTags(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    _ = try addRunnerTag(generated, ctx.amount);
    return false;
}

pub fn resolveRunnerLosesCredits(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const loss = @min(ctx.amount, @as(u8, @intCast(generated.runner_credit)));
    generated.runner_credit -= loss;
    return false;
}

pub fn resolveCorpGainsCredits(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    generated.corp_credit += ctx.amount;
    return false;
}

pub fn resolveNetDamageConditionalEtr(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const allocator = generated.arena.allocator();
    // Diviner: do N net damage, if trashed card has odd cost, end the run
    const hand_before = generated.runner_hand.items.len;
    try trashRandomRunnerHandCards(generated, ctx.amount);
    updateTerminalState(generated);
    if (generated.game_over) return true;
    // Check if a card was trashed and if it has odd cost
    if (generated.runner_hand.items.len < hand_before) {
        if (generated.runner_discard.items.len > 0) {
            const trashed_card = generated.runner_discard.items[generated.runner_discard.items.len - 1];
            const card_cost = trashed_card.cost orelse 0;
            if (card_cost % 2 == 1) {
                endOfRunCleanup(generated);
                generated.run = null;
                generated.corp_prompt_state = null;
                generated.runner_prompt_state = null;
                generated.runner_run_credit = 0;
                generated.decision_side = .runner;
                generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
                return true;
            }
        }
    }
    return false;
}

pub fn resolveRunnerLosesCreditsOrEtr(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const allocator = generated.arena.allocator();
    // Whitespace sub2: end the run if runner has N credits or less
    const total_credits = generated.runner_credit + generated.runner_run_credit;
    if (total_credits <= ctx.amount) {
        endOfRunCleanup(generated);
        generated.run = null;
        generated.corp_prompt_state = null;
        generated.runner_prompt_state = null;
        generated.runner_run_credit = 0;
        generated.decision_side = .runner;
        generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
        return true;
    }
    return false;
}

pub fn resolveNetDamageThenJackOut(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const allocator = generated.arena.allocator();
    const ice = generated.corp_servers.items[ctx.server_index].ices.items[ctx.ice_index];
    // Karunā sub1: do N net damage, then runner may jack out
    try trashRandomRunnerHandCards(generated, ctx.amount);
    updateTerminalState(generated);
    if (generated.game_over) return true;
    // Offer jack out - pause subroutines and show jack-out prompt
    const run = &(generated.run orelse return error.NoRunInProgress);
    run.pending_subroutine = .{
        .server_index = ctx.server_index,
        .ice_index = ctx.ice_index,
        .subroutine_index = ctx.subroutine_index + 1,
    };
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    try choices.append(allocator, stringChoice("Jack out"));
    try choices.append(allocator, stringChoice("Continue"));
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "jack-out"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = ice,
    };
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "waiting"),
        .choices = &.{},
        .source_card = null,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
    return true;
}

pub fn resolveGiveTagOrPayCredits(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const allocator = generated.arena.allocator();
    const ice = generated.corp_servers.items[ctx.server_index].ices.items[ctx.ice_index];
    // Funhouse sub: give 1 tag unless runner pays N credits
    const run = &(generated.run orelse return error.NoRunInProgress);
    run.pending_subroutine = .{
        .server_index = ctx.server_index,
        .ice_index = ctx.ice_index,
        .subroutine_index = ctx.subroutine_index + 1,
    };
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    try choices.append(allocator, stringChoice("Take 1 tag"));
    if (generated.runner_credit >= ctx.amount) {
        const text = try std.fmt.allocPrint(allocator, "Pay {d} [Credits]", .{ctx.amount});
        try choices.append(allocator, stringChoice(text));
    }
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "trace"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = ice,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
    return true;
}

pub fn resolveInstallIceFromHqArchives(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    try beginBranInstallIcePrompt(generated, ctx.server_index, ctx.ice_index, ctx.subroutine_index);
    return true;
}

pub fn resolveTrashProgramOrEtr(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const allocator = generated.arena.allocator();
    const ice = generated.corp_servers.items[ctx.server_index].ices.items[ctx.ice_index];
    if (generated.runner_rig_program.items.len == 0) {
        try completeUnsuccessfulRun(generated);
        return true;
    }
    generated.run.?.pending_subroutine = .{
        .server_index = ctx.server_index,
        .ice_index = ctx.ice_index,
        .subroutine_index = ctx.subroutine_index,
    };
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    for (generated.runner_rig_program.items, 0..) |prog, pidx| {
        const label = try std.fmt.allocPrint(allocator, "p|{d}", .{pidx});
        try choices.append(allocator, .{ .kind = .string, .text = label, .card = .{ .title = prog.title, .side = .runner, .index = @intCast(pidx) } });
    }
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "ballista-trash"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = ice,
    };
    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
    return true;
}

pub fn resolveCorpInstallFromHqArchives(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    try beginAnselInstallPrompt(generated, ctx.server_index, ctx.ice_index, ctx.subroutine_index);
    return true;
}

pub fn resolvePreventStealTrash(generated: *Game, _: state.SubroutineContext) anyerror!bool {
    if (generated.run != null) {
        try addFloatingEffect(generated, .{
            .kind = .prevent_steal_or_trash,
            .duration = .end_of_run,
            .value = 1,
        });
    }
    return false;
}

pub fn resolveConditionalNetDamageIfTagged(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    // Doomscroll: do N net damage if runner has N+ tags
    const tag_count = if (generated.runner_tag) |t| t.base else 0;
    if (tag_count >= ctx.amount) {
        try trashRandomRunnerHandCards(generated, ctx.amount);
        updateTerminalState(generated);
        if (generated.game_over) return true;
    }
    return false;
}

pub fn resolveConditionalEtrThreat(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    // N-Pot: ETR if threat level >= amount
    if (threatLevel(generated) >= ctx.amount) {
        try completeUnsuccessfulRun(generated);
        return true;
    }
    return false;
}

pub fn resolveNetDamageUnlessEtr(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const allocator = generated.arena.allocator();
    const ice = generated.corp_servers.items[ctx.server_index].ices.items[ctx.ice_index];
    // Semak-samun: ETR unless runner suffers N net damage
    const run = &(generated.run orelse return error.NoRunInProgress);
    run.pending_subroutine = .{
        .server_index = ctx.server_index,
        .ice_index = ctx.ice_index,
        .subroutine_index = ctx.subroutine_index + 1,
    };
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    try choices.append(allocator, stringChoice("End the run"));
    const text = try std.fmt.allocPrint(allocator, "Suffer {d} net damage", .{ctx.amount});
    try choices.append(allocator, stringChoice(text));
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "net-damage-or-etr"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = ice,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
    return true;
}

pub fn resolveTrashProgramOrResourceOrEtr(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const allocator = generated.arena.allocator();
    const ice = generated.corp_servers.items[ctx.server_index].ices.items[ctx.ice_index];
    // Biawak: trash 1 program or 1 resource, or ETR if none
    const has_programs = generated.runner_rig_program.items.len > 0;
    const has_resources = generated.runner_rig_resources.items.len > 0;
    if (!has_programs and !has_resources) {
        try completeUnsuccessfulRun(generated);
        return true;
    }
    generated.run.?.pending_subroutine = .{
        .server_index = ctx.server_index,
        .ice_index = ctx.ice_index,
        .subroutine_index = ctx.subroutine_index + 1,
    };
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    // Use ctx.amount to distinguish: 0 = programs only, 1 = resources only
    if (ctx.amount == 0 or ctx.amount == 2) {
        for (generated.runner_rig_program.items, 0..) |prog, pidx| {
            const label = try std.fmt.allocPrint(allocator, "p|{d}", .{pidx});
            try choices.append(allocator, .{ .kind = .string, .text = label, .card = .{ .title = prog.title, .side = .runner, .index = @intCast(pidx) } });
        }
    }
    if (ctx.amount == 1 or ctx.amount == 2) {
        for (generated.runner_rig_resources.items, 0..) |res, ridx| {
            const label = try std.fmt.allocPrint(allocator, "r|{d}", .{ridx});
            try choices.append(allocator, .{ .kind = .string, .text = label, .card = .{ .title = res.title, .side = .runner, .index = @intCast(ridx) } });
        }
    }
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "ballista-trash"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = ice,
    };
    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
    return true;
}

pub fn resolveRunnerLosesCreditsAndNetDamage(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    // Syailendra: runner loses N credits
    const loss = @min(ctx.amount, @as(u8, @intCast(generated.runner_credit)));
    generated.runner_credit -= loss;
    return false;
}

pub fn resolveTagOrPayCreditsEtr(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const allocator = generated.arena.allocator();
    const ice = generated.corp_servers.items[ctx.server_index].ices.items[ctx.ice_index];
    // Lamplighter: give 1 tag unless runner pays N; then ETR if tagged
    const run = &(generated.run orelse return error.NoRunInProgress);
    run.pending_subroutine = .{
        .server_index = ctx.server_index,
        .ice_index = ctx.ice_index,
        .subroutine_index = ctx.subroutine_index + 1,
    };
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    try choices.append(allocator, stringChoice("Take 1 tag"));
    if (generated.runner_credit >= ctx.amount) {
        const text = try std.fmt.allocPrint(allocator, "Pay {d} [Credits]", .{ctx.amount});
        try choices.append(allocator, stringChoice(text));
    }
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "trace"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = ice,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
    return true;
}

pub fn resolvePlaceAdvancementCounter(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    const ice = generated.corp_servers.items[ctx.server_index].ices.items[ctx.ice_index];
    generated.corp_servers.items[ctx.server_index].ices.items[ctx.ice_index].advancement_counter += ctx.amount;
    generated.systemMsg(.corp, ice.code orelse 0, "Corp places {d} advancement counter{s} on {s}.", .{
        ctx.amount, if (ctx.amount != 1) @as([]const u8, "s") else @as([]const u8, ""), ice.title,
    });
    return false;
}

pub fn resolveEtrIfTagged(generated: *Game, _: state.SubroutineContext) anyerror!bool {
    // Lamplighter sub 2: ETR if runner is tagged
    const tag_count = if (generated.runner_tag) |t| t.base else 0;
    if (tag_count > 0) {
        return resolveEndTheRun(generated, undefined_ctx);
    }
    return false;
}

const undefined_ctx = state.SubroutineContext{ .server_index = 0, .ice_index = 0, .subroutine_index = 0 };

pub fn resolveRezIceWithDiscount(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    // Mycoweb sub 2: rez a piece of ice, paying 2cr less
    // Currently a no-op placeholder (needs rez prompt with discount)
    _ = generated;
    _ = ctx;
    return false;
}

pub fn resolveOtherIceSubroutine(generated: *Game, ctx: state.SubroutineContext) anyerror!bool {
    // Mycoweb subs 3+4: resolve a subroutine on another rezzed ice
    // Currently a no-op placeholder (needs cross-ICE resolution)
    _ = generated;
    _ = ctx;
    return false;
}

fn resolveEncounteredIceSubroutines(
    generated: *Game,
    ice: state.CardInstance,
    server_index: usize,
    ice_index: usize,
    start_subroutine: u8,
) !void {
    const subroutines = ice.subroutines;

    for (subroutines, 0..) |sub, idx| {
        if (idx < start_subroutine) continue;
        const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(idx))) != 0;
        if (is_broken) continue;

        // Track subroutines resolved this run
        try addFloatingEffect(generated, .{ .kind = .subroutine_resolved, .duration = .end_of_run, .value = 1 });

        const ctx = state.SubroutineContext{
            .server_index = @intCast(server_index),
            .ice_index = @intCast(ice_index),
            .subroutine_index = @intCast(idx),
            .amount = sub.amount,
            .base_trace = sub.base_trace,
        };
        const stop = try sub.resolve(generated, ctx);
        if (stop) return;
    }
}

fn checkServerApproachAbilities(generated: *Game) !bool {
    const run = generated.run orelse return false;
    if (run.position != 0) return false;

    const target_server = try findServerByRunPath(generated.corp_servers.items, run.server);
    const server = target_server.slot;

    for (server.content.items) |*card| {
        if (card.code) |code| {
            if (lookupCardSpecByCode(code)) |spec| {
                if (spec.on_approach) |handler| {
                    if (try handler(generated, card)) return true;
                }
            }
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
    const run = &generated.run.?;

    // Build list of ice cards in HQ and Archives
    var choices: std.ArrayList(state.PromptChoice) = .empty;

    // Add ice from HQ
    for (generated.corp_hand.items, 0..) |card, idx| {
        if (std.mem.eql(u8, card.card_type orelse "", "ICE")) {
            try choices.append(allocator, .{
                .kind = .string,
                .text = try std.fmt.allocPrint(allocator, "HQ|{d}|{s}", .{ idx, card.title }),
            });
        }
    }

    // Add ice from Archives (face-up ice)
    for (generated.corp_discard.items, 0..) |card, idx| {
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
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "other"),
        .choices = try choices.toOwnedSlice(allocator),
        .on_choice = &struct {
            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const g = gameFromEffectContext(cctx);
                try applyBranInstallIceChoice(g, choice_text);
            }
        }.choice,
    };

    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
}

fn beginAnselInstallPrompt(
    generated: *Game,
    server_index: usize,
    ice_index: usize,
    subroutine_index: u8,
) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.run.?;

    // Build list of installable cards from HQ and Archives
    var choices: std.ArrayList(state.PromptChoice) = .empty;

    // Add installable cards from HQ (anything except Operations)
    for (generated.corp_hand.items, 0..) |card, idx| {
        const ct = card.card_type orelse continue;
        if (std.mem.eql(u8, ct, "Operation")) continue;
        try choices.append(allocator, .{
            .kind = .string,
            .text = try std.fmt.allocPrint(allocator, "HQ|{d}|{s}", .{ idx, card.title }),
        });
    }

    // Add installable cards from Archives
    for (generated.corp_discard.items, 0..) |card, idx| {
        const ct = card.card_type orelse continue;
        if (std.mem.eql(u8, ct, "Operation")) continue;
        try choices.append(allocator, .{
            .kind = .string,
            .text = try std.fmt.allocPrint(allocator, "Archives|{d}|{s}", .{ idx, card.title }),
        });
    }

    if (choices.items.len == 0) {
        // No installable cards — skip subroutine, continue to next
        return;
    }

    // Store continuation state
    run.pending_subroutine = .{
        .server_index = @intCast(server_index),
        .ice_index = @intCast(ice_index),
        .subroutine_index = subroutine_index,
    };

    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "ansel-install"),
        .choices = try choices.toOwnedSlice(allocator),
    };

    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
}

fn applyAnselInstallChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    const allocator = generated.arena.allocator();
    const run = generated.run orelse return error.NoRunInProgress;
    const pending = run.pending_subroutine orelse return error.MissingPendingSubroutine;

    // Parse choice: "HQ|index|title" or "Archives|index|title"
    var pieces = std.mem.splitScalar(u8, choice_text, '|');
    const zone = pieces.next() orelse return error.UnsupportedChoice;
    const index_text = pieces.next() orelse return error.UnsupportedChoice;
    const card_index = try std.fmt.parseInt(usize, index_text, 10);

    var card_to_install: state.CardInstance = undefined;
    if (std.mem.eql(u8, zone, "HQ")) {
        if (card_index >= generated.corp_hand.items.len) return error.InvalidCardIndex;
        card_to_install = generated.corp_hand.orderedRemove(card_index);
    } else if (std.mem.eql(u8, zone, "Archives")) {
        if (card_index >= generated.corp_discard.items.len) return error.InvalidCardIndex;
        card_to_install = generated.corp_discard.orderedRemove(card_index);
    } else return error.UnsupportedChoice;

    // Install the card: ICE goes on the current server, non-ICE goes into the server content
    const ct = card_to_install.card_type orelse "";
    const target_server = &generated.corp_servers.items[pending.server_index];
    card_to_install.installed_this_turn = true;
    if (std.mem.eql(u8, ct, "ICE")) {
        try target_server.ices.insert(generated.backing_allocator, 0, card_to_install);
    } else {
        try target_server.content.append(generated.backing_allocator, card_to_install);
    }

    generated.corp_prompt_state = null;

    // Resume subroutine resolution from next subroutine
    const ansel_ice_index = if (std.mem.eql(u8, ct, "ICE")) pending.ice_index + 1 else pending.ice_index;
    const ansel_ice = target_server.ices.items[ansel_ice_index];
    try resolveEncounteredIceSubroutines(generated, ansel_ice, pending.server_index, ansel_ice_index, pending.subroutine_index + 1);

    generated.run.?.pending_subroutine = null;
    if (generated.run == null) return;
    if (generated.corp_prompt_state != null) return;

    const current_run = &generated.run.?;
    if (current_run.position > 0) current_run.position -= 1;
    current_run.phase = try allocator.dupe(u8, "movement");
    current_run.jack_out_available = true;
    current_run.no_action = null;
    // Corp gets priority first in movement phase (matching Clojure)
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, current_run.*, generated);
}

fn applyBranInstallIceChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    const allocator = generated.arena.allocator();
    const run = generated.run orelse return error.NoRunInProgress;
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
    } else if (std.mem.eql(u8, zone, "Archives")) {
        if (card_index >= generated.corp_discard.items.len) return error.InvalidCardIndex;
        ice_to_install = generated.corp_discard.orderedRemove(card_index);
    } else return error.UnsupportedChoice;

    // Install ice at position 0 (outermost position)
    // This pushes all existing ice outward by 1 position
    const target_server = &generated.corp_servers.items[pending.server_index];
    try target_server.ices.insert(generated.backing_allocator, 0, ice_to_install);

    // Clear prompt
    generated.corp_prompt_state = null;

    // After installation, Bran 1.0 is now at position (ice_index + 1)
    // because we inserted a new ice at position 0
    const new_bran_position = pending.ice_index + 1;
    const bran_ice = target_server.ices.items[new_bran_position];

    // Resume subroutine resolution from next subroutine
    try resolveEncounteredIceSubroutines(generated, bran_ice, pending.server_index, new_bran_position, pending.subroutine_index + 1);

    // Clear pending state
    generated.run.?.pending_subroutine = null;

    // If ETR fired, we're done
    if (generated.run == null) return;

    // If another prompt opened, return
    if (generated.corp_prompt_state != null) return;

    // Continue with movement phase
    const current_run = &generated.run.?;
    if (current_run.position > 0) current_run.position -= 1;
    current_run.phase = try allocator.dupe(u8, "movement");
    current_run.jack_out_available = true;
    current_run.no_action = null;
    // Corp gets priority first in movement phase (matching Clojure)
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, current_run.*, generated);
}

fn applyBallistaTrashChoice(generated: *Game, choice_text: []const u8) !void {
    const allocator = generated.arena.allocator();
    const run = generated.run orelse return error.NoRunInProgress;
    const pending = run.pending_subroutine orelse return error.MissingPendingSubroutine;

    // Parse "p|index" format
    var pieces = std.mem.splitScalar(u8, choice_text, '|');
    const zone = pieces.next() orelse return error.UnsupportedChoice;
    if (!std.mem.eql(u8, zone, "p")) return error.UnsupportedChoice;
    const index_text = pieces.next() orelse return error.UnsupportedChoice;
    const index = try std.fmt.parseInt(usize, index_text, 10);

    if (index >= generated.runner_rig_program.items.len) return error.UnsupportedChoice;
    const trashed = generated.runner_rig_program.orderedRemove(index);
    try generated.runner_discard.append(generated.backing_allocator, trashed);
    if (generated.runner_memory) |*mem| {
        const mu = trashed.runner_install.mu_cost;
        if (mem.used >= mu) mem.used -= mu else mem.used = 0;
        mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
    }

    generated.corp_prompt_state = null;

    // Resume subroutine resolution from the next sub
    const server = &generated.corp_servers.items[pending.server_index];
    const ice = server.ices.items[pending.ice_index];
    try resolveEncounteredIceSubroutines(generated, ice, pending.server_index, pending.ice_index, pending.subroutine_index + 1);
    generated.run.?.pending_subroutine = null;

    if (generated.run == null) return;
    if (generated.corp_prompt_state != null) return;

    // Continue with movement phase
    const current_run = &generated.run.?;
    if (current_run.position > 0) current_run.position -= 1;
    current_run.phase = try allocator.dupe(u8, "movement");
    current_run.jack_out_available = true;
    current_run.no_action = null;
    // Corp gets priority first in movement phase (matching Clojure)
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, current_run.*, generated);
}

fn applyTraceChoice(generated: *Game, side: state.Side, choice_text: []const u8) !void {
    _ = side;
    if (std.mem.eql(u8, choice_text, "Take 1 tag")) {
        _ = try addRunnerTag(generated, 1);
    } else if (std.mem.startsWith(u8, choice_text, "Pay ")) {
        var iter = std.mem.splitScalar(u8, choice_text, ' ');
        _ = iter.next(); // "Pay"
        const amount_str = iter.next() orelse return error.UnsupportedChoice;
        const amount = try std.fmt.parseInt(u16, amount_str, 10);
        try spendCredits(generated, .runner, amount);
    } else return error.UnsupportedChoice;

    generated.runner_prompt_state = null;

    // Resume subroutine resolution
    const run = &(generated.run orelse return error.NoRunInProgress);
    const pending = run.pending_subroutine orelse return error.MissingPendingSubroutine;
    run.pending_subroutine = null;

    const server = &generated.corp_servers.items[pending.server_index];
    const ice = server.ices.items[pending.ice_index];
    try resolveEncounteredIceSubroutines(generated, ice, pending.server_index, pending.ice_index, pending.subroutine_index);

    // If run ended (ETR) or another prompt opened, we're done
    if (generated.run == null) return;
    if (generated.runner_prompt_state != null) return;
    if (generated.game_over) return;

    // Continue with movement phase after subroutines
    const allocator = generated.arena.allocator();
    for (generated.runner_rig_program.items) |*card| {
        card.current_strength = null;
    }
    const next_run = &generated.run.?;
    if (next_run.position > 0) next_run.position -= 1;
    next_run.phase = try allocator.dupe(u8, "movement");
    next_run.encounter_phase = .none;
    next_run.current_ice_index = null;
    next_run.jack_out_available = true;
    next_run.no_action = null;
    // Corp gets priority first in movement phase (matching Clojure)
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, next_run.*, generated);
}

fn applyJackOutPromptChoice(generated: *Game, choice_text: []const u8) !void {
    const allocator = generated.arena.allocator();

    generated.runner_prompt_state = null;
    generated.corp_prompt_state = null;

    if (std.mem.eql(u8, choice_text, "Jack out")) {
        // End the run
        endOfRunCleanup(generated);
        generated.run = null;
        generated.runner_run_credit = 0;
        generated.decision_side = .runner;
        generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
        return;
    }

    if (std.mem.eql(u8, choice_text, "Continue")) {
        // Resume subroutine resolution
        const run = &(generated.run orelse return error.NoRunInProgress);
        const pending = run.pending_subroutine orelse return error.MissingPendingSubroutine;
        run.pending_subroutine = null;

        const server = &generated.corp_servers.items[pending.server_index];
        const ice = server.ices.items[pending.ice_index];
        try resolveEncounteredIceSubroutines(generated, ice, pending.server_index, pending.ice_index, pending.subroutine_index);

        if (generated.run == null) return;
        if (generated.runner_prompt_state != null) return;
        if (generated.game_over) return;

        // Continue with movement phase after subroutines
        for (generated.runner_rig_program.items) |*card| {
            card.current_strength = null;
        }
        const next_run = &generated.run.?;
        if (next_run.position > 0) next_run.position -= 1;
        next_run.phase = try allocator.dupe(u8, "movement");
        next_run.encounter_phase = .none;
        next_run.current_ice_index = null;
        next_run.jack_out_available = true;
        next_run.no_action = null;
        // Corp gets priority first in movement phase (matching Clojure)
        generated.decision_side = .corp;
        generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, next_run.*, generated);
        return;
    }

    return error.UnsupportedChoice;
}

fn advanceMovementPhase(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.run.?;

    // Clear jack-out flag since both players passed
    run.jack_out_available = false;
    run.no_action = null;

    // Check for more ice or success
    if (run.position > 0) {
        run.phase = try allocator.dupe(u8, "approach-ice");
        generated.decision_side = .corp;
        generated.legal_actions = try continueActionsForRun(allocator, .corp, run.*);
        return;
    }

    // Check for Manegarm Skunkworks when approaching server (position == 0)
    if (try checkServerApproachAbilities(generated)) {
        return;
    }

    try applySuccessfulRunEffects(generated);
    run.phase = try allocator.dupe(u8, "success");
    if (try fireEvent(generated, .successful_run)) {
        return;
    }
    try enterSuccessAccessPhase(generated);
}

fn prepareNextAccess(generated: *Game) !bool {
    const run = &generated.run.?;
    generated.runner_prompt_state = null;
    try ensureAccessesInitialized(generated);

    if (run.accesses_remaining == 0) return false;
    if (std.mem.eql(u8, run.server[0], "hq")) {
        if (generated.corp_hand.items.len == 0) {
            run.accesses_remaining = 0;
            return false;
        }
        // Shuffle HQ and auto-access the random card immediately
        // (matches Clojure's access-helper-hq auto-execute behavior).
        const maybe_access = try nextHqAccessTarget(generated, run);
        if (maybe_access == null) {
            run.accesses_remaining = 0;
            return false;
        }
        run.access_card_index = maybe_access.?.index;
        rememberAccessedIndex(run, maybe_access.?.index);
        run.accesses_remaining -= 1;
        if (try beginAccessFlow(generated, maybe_access.?.card)) return true;
        return try beginNoActionAccessPrompt(generated, maybe_access.?.card);
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
    if (std.mem.eql(u8, run.server[0], "rnd")) {
        return try beginNoActionAccessPrompt(generated, maybe_access.?.card);
    }
    return run.accesses_remaining > 0;
}

fn ensureAccessesInitialized(generated: *Game) !void {
    const run = &generated.run.?;
    if (run.accesses_remaining != 0 or run.accessed_count != 0) return;

    const floating_access = sumFloatingEffects(generated, .access_bonus);
    var bonus: u8 = if (floating_access > 0) @intCast(floating_access) else 0;
    if (std.mem.eql(u8, run.server[0], "hq") and generated.turn_events.runner_hq_breaches == 0) {
        bonus += runner_installed_hq_access_bonus(generated);
        generated.turn_events.runner_hq_breaches += 1;
    }
    // Conduit: R&D access bonus = virus counters on Conduit
    if (std.mem.eql(u8, run.server[0], "rnd")) {
        bonus += runnerRdAccessBonus(generated);
    }
    run.accesses_remaining = 1 + bonus;
}

fn applySuccessfulRunEffects(generated: *Game) !void {
    _ = generated.run orelse return error.NoRunInProgress;
    const draw_amount = sumFloatingEffects(generated, .successful_run_draw);
    if (draw_amount > 0) {
        try drawCards(generated, .runner, @intCast(draw_amount));
    }
}

fn completeRunWithoutAccess(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.runner_successful_run_this_turn = true;
    try applySourceCardOnSuccessfulRun(generated);
    // Clear prompts before firing events so we can detect if an event sets a new one
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    try applyIdentityOnSuccessfulRun(generated);
    applyAmazeTagsOnRunEnd(generated);
    _ = try fireEvent(generated, .run_ends);
    endOfRunCleanup(generated);
    generated.run = null;
    generated.runner_run_credit = 0;
    // If an event handler (e.g., Zahya) set a prompt, preserve it
    if (generated.runner_prompt_state != null) return;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
}

fn completeRunAfterAccess(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.runner_successful_run_this_turn = true;
    try applySourceCardOnSuccessfulRun(generated);
    // Clear prompts before firing events so we can detect if an event sets a new one
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    try applyIdentityOnSuccessfulRun(generated);
    applyAmazeTagsOnRunEnd(generated);
    _ = try fireEvent(generated, .run_ends);
    endOfRunCleanup(generated);
    generated.run = null;
    generated.runner_run_credit = 0;
    // If an event handler (e.g., Zahya) set a prompt, preserve it
    if (generated.runner_prompt_state != null) return;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
}

fn completeSuccessfulRunWithCorpPriority(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.runner_successful_run_this_turn = true;
    try applySourceCardOnSuccessfulRun(generated);
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    try applyIdentityOnSuccessfulRun(generated);
    applyAmazeTagsOnRunEnd(generated);
    _ = try fireEvent(generated, .run_ends);
    endOfRunCleanup(generated);
    generated.run = null;
    generated.runner_run_credit = 0;
    generated.decision_side = .corp;
    generated.legal_actions = try continueActions(allocator, .corp);
}

fn completeUnsuccessfulRun(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    _ = try fireEvent(generated, .run_ends);
    endOfRunCleanup(generated);
    generated.run = null;
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    generated.runner_run_credit = 0;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
}

fn beginAccessFlow(
    generated: *Game,
    accessed: state.CardInstance,
) !bool {
    const allocator = generated.arena.allocator();
    const no_steal_or_trash = hasFloatingEffect(generated, .prevent_steal_or_trash);
    if (try fireEvent(generated, .access)) return true;
    if (generated.game_over) return true;
    // Card-specific access handler (Urtica Cipher net damage, etc.)
    if (lookupCardSpec(accessed)) |spec| {
        if (spec.on_access) |handler| {
            return try handler(generated, accessed);
        }
    }
    // Agendas: steal flow
    const is_agenda = if (accessed.card_type) |ct| std.mem.eql(u8, ct, "Agenda") else false;
    if (is_agenda) {
        if (no_steal_or_trash) {
            return try beginNoActionAccessPrompt(generated, accessed);
        }
        generated.runner_prompt_state = .{
            .prompt_type = try allocator.dupe(u8, prompt_access_choice),
            .choices = try singleStringChoice(allocator, "Steal"),
            .source_card = accessed,
        };
        return true;
    }
    // Default: trash prompt
    return try beginTrashAccessPrompt(generated, accessed);
}

fn beginNoActionAccessPrompt(generated: *Game, accessed: state.CardInstance) !bool {
    const allocator = generated.arena.allocator();
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_access_choice),
        .choices = try singleStringChoice(allocator, "No action"),
        .source_card = accessed,
    };
    return true;
}

/// Count available access abilities across all runner rig zones
fn countAccessAbilities(generated: *const Game, no_steal_or_trash: bool, is_agenda: bool) usize {
    if (no_steal_or_trash) return 0;
    var count: usize = 0;
    const rig_zones = [_][]const state.CardInstance{
        generated.runner_rig_hardware.items,
        generated.runner_rig_program.items,
        generated.runner_rig_resources.items,
    };
    for (rig_zones) |zone| {
        for (zone) |card| {
            for (card.abilities, 0..) |ability, ability_idx| {
                if (!ability.is_access_ability) continue;
                if (ability.once_per_turn and isAbilityUsedThisTurn(&card, @intCast(ability_idx))) continue;
                if (ability.req) |req| {
                    if (!req(effectContextConst(generated), &card)) continue;
                }
                _ = is_agenda;
                count += 1;
            }
        }
    }
    return count;
}

/// Append access ability choices to the choices list
fn appendAccessAbilityChoices(
    allocator: std.mem.Allocator,
    generated: *const Game,
    choices: []state.PromptChoice,
    start_idx: usize,
    no_steal_or_trash: bool,
    is_agenda: bool,
) usize {
    if (no_steal_or_trash) return start_idx;
    var idx = start_idx;
    const rig_zones = [_][]const state.CardInstance{
        generated.runner_rig_hardware.items,
        generated.runner_rig_program.items,
        generated.runner_rig_resources.items,
    };
    for (rig_zones) |zone| {
        for (zone) |card| {
            for (card.abilities, 0..) |ability, ability_idx| {
                if (!ability.is_access_ability) continue;
                if (ability.once_per_turn and isAbilityUsedThisTurn(&card, @intCast(ability_idx))) continue;
                if (ability.req) |req| {
                    if (!req(effectContextConst(generated), &card)) continue;
                }
                _ = is_agenda;
                _ = allocator;
                choices[idx] = stringChoice(ability.label orelse "Use ability");
                idx += 1;
            }
        }
    }
    return idx;
}

fn beginTrashAccessPrompt(generated: *Game, accessed: state.CardInstance) !bool {
    const spec = lookupCardSpec(accessed);
    const trash_cost = if (spec) |s| s.trash_cost else null;
    const allocator = generated.arena.allocator();
    const no_steal_or_trash = hasFloatingEffect(generated, .prevent_steal_or_trash);
    const is_agenda = if (accessed.card_type) |ct| std.mem.eql(u8, ct, "Agenda") else false;

    const can_afford = if (trash_cost) |tc| generated.runner_credit >= tc and !no_steal_or_trash else false;
    const access_ability_count = countAccessAbilities(generated, no_steal_or_trash, is_agenda);
    var choice_count: usize = 1; // "No action"
    if (can_afford) choice_count += 1;
    choice_count += access_ability_count;
    const choices = try allocator.alloc(state.PromptChoice, choice_count);
    var idx: usize = 0;
    if (can_afford) {
        choices[idx] = stringChoice(try std.fmt.allocPrint(allocator, "Pay {d} [Credits] to trash", .{trash_cost.?}));
        idx += 1;
    }
    idx = appendAccessAbilityChoices(allocator, generated, choices, idx, no_steal_or_trash, is_agenda);
    if (trash_cost == null and access_ability_count == 0) {
        generated.systemMsg(.runner, accessed.code orelse 0, "Runner accesses {s}.", .{accessed.title});
        return false;
    }
    choices[idx] = stringChoice("No action");
    generated.systemMsg(.runner, accessed.code orelse 0, "Runner accesses {s}.", .{accessed.title});
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_access_choice),
        .choices = choices,
        .source_card = accessed,
    };
    return true;
}

fn beginNetDamageOnAccessPrompt(
    generated: *Game,
    accessed: state.CardInstance,
) !bool {
    const allocator = generated.arena.allocator();
    // Urtica Cipher: 2 base damage + advancement counters, costs 2 credits
    const damage: u8 = 2 + accessed.advancement_counter;
    const cost: u16 = 2;

    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    if (generated.corp_credit >= cost) {
        const text = try std.fmt.allocPrint(allocator, "Pay {d} [Credits] to do {d} net damage", .{ cost, damage });
        try choices.append(allocator, stringChoice(text));
    }
    try choices.append(allocator, stringChoice("No action"));

    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "net-damage-on-access"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = accessed,
    };
    return true;
}

fn applyNetDamageOnAccessChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    const accessed = (if (generated.corp_prompt_state) |ps| ps.source_card else null) orelse return error.MissingSourceCard;
    generated.corp_prompt_state = null;

    if (std.mem.startsWith(u8, choice_text, "Pay ")) {
        // Urtica Cipher: 2 credits, 2 base damage + advancement counters
        try spendCredits(generated, .corp, 2);
        const damage: u8 = 2 + accessed.advancement_counter;
        try trashRandomRunnerHandCards(generated, damage);
        updateTerminalState(generated);
        if (generated.game_over) return;
    }

    // Proceed to trash-on-access prompt for the runner
    if (try beginTrashAccessPrompt(generated, accessed)) {
        generated.decision_side = .runner;
        generated.legal_actions = try promptChoiceActions(
            generated.arena.allocator(),
            .runner,
            generated.runner_prompt_state.?,
        );
        return;
    }

    // No trash prompt, finish access
    try finishAccessCard(generated);
}

fn beginHqAccessChoicePrompt(generated: *Game) !bool {
    const allocator = generated.arena.allocator();
    generated.runner_prompt_state = .{
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
    const run = &generated.run.?;
    if (run.accesses_remaining == 0) return error.MissingAccessTarget;
    // Shuffle HQ now (when player picks "Card from hand"), matching Clojure's timing
    const maybe_access = try nextHqAccessTarget(generated, run);
    if (maybe_access == null) return error.MissingAccessTarget;
    const access_index = maybe_access.?.index;
    if (access_index >= generated.corp_hand.items.len) return error.MissingAccessTarget;
    const accessed = generated.corp_hand.items[access_index];
    rememberAccessedIndex(run, access_index);
    run.accesses_remaining -= 1;
    if (try beginAccessFlow(generated, accessed)) {
        generated.decision_side = .runner;
        generated.legal_actions = try promptChoiceActions(
            generated.arena.allocator(),
            .runner,
            generated.runner_prompt_state.?,
        );
        return;
    }

    // If more accesses remain, immediately prepare the next access
    // (matches Clojure's recursive access-helper-hq behavior — no continues between accesses)
    if (run.accesses_remaining > 0) {
        if (try prepareNextAccess(generated)) {
            run.phase = try generated.arena.allocator().dupe(u8, "success");
            generated.decision_side = .runner;
            // If a prompt was set (e.g., another hq-access), use it
            if (generated.runner_prompt_state) |ps| {
                generated.legal_actions = try promptChoiceActions(generated.arena.allocator(), .runner, ps);
            } else {
                generated.legal_actions = try continueActionsForRun(generated.arena.allocator(), .runner, run.*);
            }
            return;
        }
    }
    try completeRunWithoutAccess(generated);
}

const AccessTarget = struct {
    index: u8,
    card: state.CardInstance,
};

fn nextAccessTarget(generated: *Game) !?AccessTarget {
    const run = &generated.run.?;
    if (std.mem.eql(u8, run.server[0], "rnd")) {
        return nextIndexedAccessTarget(generated.corp_deck.items, run.accessed_count);
    }
    if (std.mem.eql(u8, run.server[0], "archives")) {
        return nextIndexedAccessTarget(generated.corp_discard.items, run.accessed_count);
    }
    const target_server = try findServerByRunPath(generated.corp_servers.items, run.server);
    return nextIndexedAccessTarget(target_server.slot.content.items, run.accessed_count);
}

fn nextIndexedAccessTarget(cards: []const state.CardInstance, accessed_count: u8) ?AccessTarget {
    if (accessed_count >= cards.len) return null;
    return .{
        .index = accessed_count,
        .card = cards[accessed_count],
    };
}

fn nextHqAccessTarget(generated: *Game, run: *state.RunState) !?AccessTarget {
    if (generated.corp_hand.items.len == 0) return null;
    var shuffled_indexes: [64]u8 = undefined;
    for (generated.corp_hand.items, 0..) |_, idx| {
        shuffled_indexes[idx] = @intCast(idx);
    }
    var rng_state = fromOracleSeed(generated.rng_seed orelse return error.MissingRngSeed);
    shuffleInPlace(u8, &rng_state, shuffled_indexes[0..generated.corp_hand.items.len]);
    generated.rng_seed = oracleSeed(rng_state);
    for (shuffled_indexes[0..generated.corp_hand.items.len]) |chosen_index| {
        if (wasIndexAccessed(run.*, chosen_index)) continue;
        return .{
            .index = chosen_index,
            .card = generated.corp_hand.items[chosen_index],
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

fn adjustAccessedIndexes(run: *state.RunState, removed_index: u8) void {
    var idx: usize = 0;
    while (idx < run.accessed_count and idx < run.accessed_card_indexes.len) : (idx += 1) {
        if (run.accessed_card_indexes[idx]) |ai| {
            if (ai > removed_index) {
                run.accessed_card_indexes[idx] = ai - 1;
            }
        }
    }
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
    return continueActionsForRunWithRez(allocator, side, run, null);
}

fn continueActionsForRunWithRez(
    allocator: std.mem.Allocator,
    side: state.Side,
    run: ?state.RunState,
    game: ?*const Game,
) ![]const state.LegalAction {
    return switch (side) {
        .corp => blk: {
            // Check if corp can rez any non-ICE cards in the run target server
            const rez_actions = if (game) |g| try corpRezNonIceActions(allocator, g) else &[_]state.LegalAction{};
            // Check if corp can rez approached ICE
            const has_ice_rez = if (game) |g| try canRezApproachedIce(g) else false;
            const extra = rez_actions.len + @as(usize, if (has_ice_rez) 1 else 0);
            if (extra == 0) break :blk &corp_continue_actions;
            // Combine continue + rez actions
            var combined = try allocator.alloc(state.LegalAction, 1 + extra);
            combined[0] = corp_continue_actions[0]; // continue action
            @memcpy(combined[1 .. 1 + rez_actions.len], rez_actions);
            if (has_ice_rez) {
                combined[1 + rez_actions.len] = .{
                    .kind = .rez_ice,
                    .side = .corp,
                };
            }
            break :blk combined;
        },
        .runner => runnerContinueActions(allocator, run != null and run.?.jack_out_available),
    };
}

fn canRezApproachedIce(game: *const Game) !bool {
    const run = game.run orelse return false;
    if (!std.mem.eql(u8, run.phase, "approach-ice")) return false;
    const target = try currentApproachedIce(@constCast(game)) orelse return false;
    if (target.ice.rezzed) return false;
    const rez_cost = target.ice.cost orelse 0;
    const floating_rez_bonus: u16 = @intCast(@max(0, sumFloatingEffects(game, .rez_cost_bonus)));
    const adjusted_cost = applyCostModifier(rez_cost + floating_rez_bonus, sumStaticEffects(game, .runner, .rez_cost, &target.ice));
    return game.corp_credit >= adjusted_cost;
}

fn corpRezNonIceActions(allocator: std.mem.Allocator, game: *const Game) ![]const state.LegalAction {
    const run = game.run orelse return &[_]state.LegalAction{};
    const target_server = findServerByRunPath(game.corp_servers.items, run.server) catch return &[_]state.LegalAction{};
    const server = target_server.slot;

    var count: usize = 0;
    for (server.content.items) |card| {
        if (!card.rezzed and card.cost != null and game.corp_credit >= card.cost.?) count += 1;
    }
    if (count == 0) return &[_]state.LegalAction{};

    const actions = try allocator.alloc(state.LegalAction, count);
    var idx: usize = 0;
    for (server.content.items, 0..) |card, card_idx| {
        if (!card.rezzed and card.cost != null and game.corp_credit >= card.cost.?) {
            actions[idx] = .{
                .kind = .rez_non_ice,
                .side = .corp,
                .card_title = card.title,
                .card_index = @intCast(card_idx),
                .server = if (run.server.len > 0) run.server[0] else null,
            };
            idx += 1;
        }
    }
    return actions;
}

// --- Shared encounter ability helpers and handlers ---

fn isInEncounter(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
    const g = gameFromConstEffectContext(ctx);
    const run = g.run orelse return false;
    return std.mem.eql(u8, run.phase, "encounter-ice");
}

fn encounterBreakHandler(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const allocator = g.arena.allocator();
    const run = g.run orelse return error.NoRunInProgress;
    if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;

    const icebreaker = card;
    const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
    const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
    const server = &g.corp_servers.items[target_server.index];
    const ice_count = server.ices.items.len;
    if (current_ice_idx >= ice_count) return error.InvalidIceIndex;
    const actual_ice_idx = ice_count - 1 - current_ice_idx;
    const ice = &server.ices.items[actual_ice_idx];

    if (!isIcebreaker(icebreaker.*)) return error.NotAnIcebreaker;
    if (!canBreakIceType(icebreaker.*, ice.*)) return error.CannotBreakIceType;
    const ice_str_mod: i8 = @intCast(@as(i16, @truncate(sumFloatingEffects(g, .ice_strength_modifier))));
    const ice_str = effectiveIceStrength(g, ice.*, run.server, ice_str_mod);
    if (effectiveStrength(icebreaker.*) < ice_str) return error.InsufficientStrength;

    const break_ability = icebreaker.abilities[0];
    const credit_cost = applyCostModifier(
        break_ability.credit_cost,
        sumStaticEffects(g, .runner, .break_cost, icebreaker),
    );
    if (g.runner_credit < credit_cost) return error.InsufficientCredits;
    g.runner_credit -= credit_cost;

    try addFloatingEffect(g, .{ .kind = .icebreaker_broke, .duration = .end_of_run, .source_code = icebreaker.instance_id });
    if (break_ability.on_break) |callback| {
        try callback(effectContext(g), icebreaker);
    }

    g.systemMsg(.runner, icebreaker.code orelse 0, "Runner uses {s} to break subroutine on {s}.", .{
        icebreaker.title, ice.title,
    });
    try openBreakSubPrompt(g, ice, icebreaker.*, 0);
    _ = allocator;
}

fn encounterPumpHandler(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const allocator = g.arena.allocator();
    const run = g.run orelse return error.NoRunInProgress;
    if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;

    var icebreaker = card;

    const pump_spec = icebreaker.abilities[1];
    if (pump_spec.pump_can_use) |can_use| {
        if (!can_use(effectContextConst(g), icebreaker)) return error.InsufficientCredits;
    }
    const pump_cost = applyCostModifier(
        pump_spec.credit_cost,
        sumStaticEffects(g, .runner, .pump_cost, icebreaker),
    );
    if (g.runner_credit < pump_cost) return error.InsufficientCredits;
    g.runner_credit -= pump_cost;

    const current = effectiveStrength(icebreaker.*);
    const pump_amount_val = if (pump_spec.pump_amount_fn) |amount_fn|
        amount_fn(effectContextConst(g), icebreaker)
    else
        pump_spec.pump_amount;
    icebreaker.current_strength = current + pump_amount_val;
    if (pump_spec.on_pump) |callback| {
        try callback(effectContext(g), icebreaker);
    }

    g.systemMsg(.runner, icebreaker.code orelse 0, "Runner uses {s} to increase strength to {d}.", .{
        icebreaker.title, icebreaker.current_strength orelse 0,
    });

    const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
    const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
    const server = &g.corp_servers.items[target_server.index];
    const ice_count = server.ices.items.len;
    if (current_ice_idx >= ice_count) return error.InvalidIceIndex;
    const actual_ice_idx = ice_count - 1 - current_ice_idx;
    const ice = server.ices.items[actual_ice_idx];
    g.decision_side = .runner;
    g.legal_actions = try encounterActionsForState(allocator, g, ice);
}

fn encounterLeechHandler(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const allocator = g.arena.allocator();
    if (g.run == null) return error.NoRunInProgress;
    card.virus_counter -= 1;
    try addFloatingEffect(g, .{
        .kind = .ice_strength_modifier,
        .duration = .end_of_encounter,
        .value = -1,
    });
    g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to give ICE -{d} strength.", .{
        card.title, @as(u8, 1),
    });
    const run = g.run.?;
    const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
    const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
    const server = &g.corp_servers.items[target_server.index];
    const ice_count = server.ices.items.len;
    const actual_ice_idx = ice_count - 1 - current_ice_idx;
    const ice = server.ices.items[actual_ice_idx];
    g.decision_side = .runner;
    g.legal_actions = try encounterActionsForState(allocator, g, ice);
}

fn encounterBotulusHandler(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const run = g.run orelse return error.NoRunInProgress;
    if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;

    const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
    const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
    const server = &g.corp_servers.items[target_server.index];
    const ice_count = server.ices.items.len;
    if (current_ice_idx >= ice_count) return error.InvalidIceIndex;
    const actual_ice_idx = ice_count - 1 - current_ice_idx;
    const ice = &server.ices.items[actual_ice_idx];

    card.virus_counter -= 1;
    g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to break subroutine on {s}.", .{
        card.title, ice.title,
    });
    try openBreakSubPrompt(g, ice, card.*, 0);
}

fn encounterBioroidHandler(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
    const g = gameFromEffectContext(ctx);
    const allocator = g.arena.allocator();
    const run = g.run orelse return error.NoRunInProgress;
    if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;

    const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
    const target_server = try findMutableServerByRunPath(g.corp_servers.items, run.server);
    const server = &g.corp_servers.items[target_server.index];
    const ice_count = server.ices.items.len;
    if (current_ice_idx >= ice_count) return error.InvalidIceIndex;
    const actual_ice_idx = ice_count - 1 - current_ice_idx;
    var ice = &server.ices.items[actual_ice_idx];

    // Read bioroid params from ICE's abilities[0]
    if (ice.abilities.len == 0) return error.NoBioroidAbility;
    const bioroid_ability = ice.abilities[0];
    const click_cost = if (bioroid_ability.cost) |c| c.clicks else return error.NoBioroidAbility;

    if (g.runner_click < click_cost) return error.InsufficientClicks;
    g.runner_click -= click_cost;

    var broken_count: u8 = 0;
    for (ice.subroutines, 0..) |_, sub_idx| {
        if (broken_count >= bioroid_ability.break_count) break;
        const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(sub_idx))) != 0;
        if (!is_broken) {
            ice.broken_subroutines |= (@as(u16, 1) << @as(u4, @intCast(sub_idx)));
            broken_count += 1;
        }
    }

    g.decision_side = .runner;
    g.legal_actions = try encounterActionsForState(allocator, g, ice.*);
}

fn encounterActionsForState(
    allocator: std.mem.Allocator,
    generated: *Game,
    ice: state.CardInstance,
) ![]const state.LegalAction {
    const run = generated.run orelse return error.NoRunInProgress;
    const encounter_ice_mod: i8 = @intCast(@as(i16, @truncate(sumFloatingEffects(generated, .ice_strength_modifier))));
    const ice_str = effectiveIceStrength(generated, ice, run.server, encounter_ice_mod);

    // Count unbroken subroutines
    var unbroken_count: u16 = 0;
    for (ice.subroutines, 0..) |_, idx| {
        const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(idx))) != 0;
        if (!is_broken) unbroken_count += 1;
    }

    // Count icebreaker break actions (one per qualified icebreaker with abilities[0] = break)
    var breaker_count: usize = 0;
    if (unbroken_count > 0) {
        for (generated.runner_rig_program.items) |card| {
            if (!isIcebreaker(card)) continue;
            if (card.abilities.len < 1) continue;
            if (!canBreakIceType(card, ice)) continue;
            if (effectiveStrength(card) < ice_str) continue;
            var break_cost = card.abilities[0].credit_cost;
            break_cost = applyCostModifier(break_cost, sumStaticEffects(generated, .runner, .break_cost, &card));
            if (generated.runner_credit < break_cost) continue;
            breaker_count += 1;
        }
    }

    // Only offer pump/leech/bioroid/botulus if there are unbroken subroutines remaining
    var bioroid_ability_count: usize = 0;
    var pump_count: usize = 0;
    var leech_count: usize = 0;
    var botulus_count: usize = 0;
    if (unbroken_count > 0) {
        // Bioroid: count opponent-usable abilities on ICE
        bioroid_ability_count = countCardAbilityActions(generated, .runner, ice);
        // Pump: icebreakers with abilities[1] = pump
        for (generated.runner_rig_program.items) |card| {
            if (!isIcebreaker(card)) continue;
            if (card.abilities.len < 2) continue;
            const pump_spec = card.abilities[1];
            if (!canBreakIceType(card, ice)) continue;
            if (pump_spec.pump_can_use) |can_use| {
                if (!can_use(effectContextConst(generated), &card)) continue;
            }
            const pump_cost = applyCostModifier(pump_spec.credit_cost, sumStaticEffects(generated, .runner, .pump_cost, &card));
            if (generated.runner_credit < pump_cost) continue;
            pump_count += 1;
        }
        // Leech: non-icebreaker programs with virus counter and encounter ability
        for (generated.runner_rig_program.items) |card| {
            if (!isIcebreaker(card) and card.abilities.len > 0 and card.abilities[0].on_use == &encounterLeechHandler and card.virus_counter > 0) {
                leech_count += 1;
            }
        }
        // Botulus: hosted cards on ICE with abilities
        for (ice.hosted) |hosted| {
            if (hosted.abilities.len > 0 and hosted.virus_counter > 0) {
                botulus_count += 1;
            }
        }
    }

    const total_actions = 1 + breaker_count + bioroid_ability_count + pump_count + leech_count + botulus_count;
    const actions = try allocator.alloc(state.LegalAction, total_actions);

    // Continue action (let unbroken subs fire)
    actions[0] = .{
        .kind = .@"continue",
        .side = .runner,
        .prompt_type = "run",
        .label = "Continue",
    };

    var next: usize = 1;

    // Break actions: one per qualified icebreaker with abilities[0] = break
    if (unbroken_count > 0) {
        for (generated.runner_rig_program.items, 0..) |card, card_idx| {
            if (!isIcebreaker(card)) continue;
            if (card.abilities.len < 1) continue;
            if (!canBreakIceType(card, ice)) continue;
            if (effectiveStrength(card) < ice_str) continue;
            const break_spec = card.abilities[0];
            const break_count = @max(@as(u16, 1), @as(u16, break_spec.break_count));
            const activations = (unbroken_count + break_count - 1) / break_count;
            const total_cost = activations * break_spec.credit_cost;
            if (generated.runner_credit < total_cost) continue;

            const combined_idx = generated.runner_rig_resources.items.len + card_idx;
            actions[next] = .{
                .kind = .use_installed_ability,
                .side = .runner,
                .card_index = @intCast(combined_idx),
                .card_title = try allocator.dupe(u8, card.title),
                .ability_ref = .{ .source_instance_id = card.instance_id, .ability_index = 0 },
                .label = try std.fmt.allocPrint(allocator, "Break subroutines with {s}", .{card.title}),
            };
            next += 1;
        }

        // Bioroid break: emit from ICE abilities with allow_opponent_use
        next = try emitCardAbilityActions(allocator, generated, .runner, ice, actions, next);

        // Pump actions: icebreakers with abilities[1] = pump
        for (generated.runner_rig_program.items, 0..) |card, card_idx| {
            if (!isIcebreaker(card)) continue;
            if (card.abilities.len < 2) continue;
            const pump_spec = card.abilities[1];
            if (!canBreakIceType(card, ice)) continue;
            if (pump_spec.pump_can_use) |can_use| {
                if (!can_use(effectContextConst(generated), &card)) continue;
            }
            if (generated.runner_credit < pump_spec.credit_cost) continue;

            const combined_idx = generated.runner_rig_resources.items.len + card_idx;
            actions[next] = .{
                .kind = .use_installed_ability,
                .side = .runner,
                .card_index = @intCast(combined_idx),
                .card_title = try allocator.dupe(u8, card.title),
                .ability_ref = .{ .source_instance_id = card.instance_id, .ability_index = 1 },
                .label = try std.fmt.allocPrint(allocator, "+{d} strength to {s}", .{ pump_spec.pump_amount, card.title }),
            };
            next += 1;
        }

        // Leech: non-icebreaker programs with virus counter and encounter ability
        for (generated.runner_rig_program.items, 0..) |card, card_idx| {
            if (!isIcebreaker(card) and card.abilities.len > 0 and card.abilities[0].on_use == &encounterLeechHandler and card.virus_counter > 0) {
                const combined_idx = generated.runner_rig_resources.items.len + card_idx;
                actions[next] = .{
                    .kind = .use_installed_ability,
                    .side = .runner,
                    .card_index = @intCast(combined_idx),
                    .card_title = try allocator.dupe(u8, card.title),
                    .ability_ref = .{ .source_instance_id = card.instance_id, .ability_index = 0 },
                    .label = try std.fmt.allocPrint(allocator, "Give -1 strength to {s}", .{ice.title}),
                };
                next += 1;
            }
        }

        // Botulus: hosted cards on ICE with abilities
        for (ice.hosted) |hosted| {
            if (hosted.abilities.len == 0 or hosted.virus_counter == 0) continue;
            actions[next] = .{
                .kind = .use_installed_ability,
                .side = .runner,
                .card_title = try allocator.dupe(u8, hosted.title),
                .ability_ref = .{ .source_instance_id = hosted.instance_id, .ability_index = 0 },
                .label = try std.fmt.allocPrint(allocator, "Break 1 subroutine with {s}", .{hosted.title}),
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
    g: *const Game,
) ![]const state.LegalAction {
    if (g.corp_click == 0) return endTurnActions(allocator, .corp);
    const servers = g.corp_servers.items;
    const scoreable_count = countScoreableAgendas(servers);
    var playable_hand_count: usize = 0;
    for (g.corp_hand.items) |card| {
        if (isCorpCardPlayableFromHand(g, card)) playable_hand_count += 1;
    }

    const installed_ability_count = countCorpInstalledAbilityActions(g, servers);
    const opponent_resource_ability_count = countRunnerInstalledAbilityActions(g, .corp, g.runner_rig_resources.items);
    const opponent_program_ability_count = countRunnerInstalledAbilityActions(g, .corp, g.runner_rig_program.items);
    const opponent_hardware_ability_count = countRunnerInstalledAbilityActions(g, .corp, g.runner_rig_hardware.items);
    const opponent_ability_count = opponent_resource_ability_count + opponent_program_ability_count + opponent_hardware_ability_count;
    const raw_advanceable = if (g.corp_click >= 1 and g.corp_credit >= 1) countAdvanceableCards(servers) else 0;
    // Don't count scoreable agendas as advanceable (score replaces advance)
    const cannot_score = hasFloatingEffect(g, .prevent_score);
    const advanceable_count = if (!cannot_score) raw_advanceable -| scoreable_count else raw_advanceable;
    const rezzable_count = countRezzableNonIce(g);
    const flashback_count = countCorpFlashbackActions(g);
    var count: usize = playable_hand_count + flashback_count + installed_ability_count + opponent_ability_count + advanceable_count + rezzable_count;
    if (g.corp_click >= 1) count += 1; // gain credit
    if (g.corp_click >= 1 and g.corp_deck.items.len > 0) count += 1; // draw card
    if (scoreable_count > 0 and !cannot_score) count += scoreable_count;
    if (g.corp_click >= 3) count += 1; // purge viruses

    const actions = try allocator.alloc(state.LegalAction, count);
    var next: usize = 0;
    for (g.corp_hand.items, 0..) |card, idx| {
        if (!isCorpCardPlayableFromHand(g, card)) continue;
        actions[next] = .{
            .kind = .play_from_hand,
            .side = .corp,
            .card_index = @intCast(idx),
            .card_title = try allocator.dupe(u8, card.title),
        };
        next += 1;
    }
    for (g.corp_discard.items, 0..) |card, idx| {
        if (!isCorpFlashbackPlayable(g, card)) continue;
        actions[next] = .{
            .kind = .flashback,
            .side = .corp,
            .card_index = @intCast(idx),
            .card_title = try allocator.dupe(u8, card.title),
        };
        next += 1;
    }
    for (servers) |server| {
        for (server.content.items) |card| {
            if (card.rezzed) {
                next = try emitCardAbilityActions(allocator, g, .corp, card, actions, next);
            }
        }
    }
    for (g.runner_rig_resources.items) |card| {
        next = try emitCardAbilityActions(allocator, g, .corp, card, actions, next);
    }
    for (g.runner_rig_program.items) |card| {
        next = try emitCardAbilityActions(allocator, g, .corp, card, actions, next);
    }
    for (g.runner_rig_hardware.items) |card| {
        next = try emitCardAbilityActions(allocator, g, .corp, card, actions, next);
    }

    if (g.corp_click >= 1) {
        actions[next] = try basicAbilityAction(allocator, .corp, .gain_credit, "Gain 1 [Credits]");
        next += 1;
    }
    if (g.corp_click >= 1 and g.corp_deck.items.len > 0) {
        actions[next] = try basicAbilityAction(allocator, .corp, .draw_card, "Draw 1 card");
        next += 1;
    }
    // Per-card advance actions — only advanceable cards per rule 1.18.3:
    // - Agendas can always be advanced
    // - Cards with .advanceable = true can be advanced
    // - Unrezzed (facedown) cards can be targeted (bluff advancing)
    if (g.corp_click >= 1 and g.corp_credit >= 1) {
        for (servers) |server| {
            for (server.ices.items, 0..) |card, card_index| {
                if (!canBeAdvanced(card)) continue;
                const text = try std.fmt.allocPrint(allocator, "{s}|i|{d}", .{ server.name, card_index });
                actions[next] = .{
                    .kind = .advance,
                    .side = .corp,
                    .choice = stringChoice(text),
                    .basic_action = .advance_installed,
                };
                next += 1;
            }
            for (server.content.items, 0..) |card, card_index| {
                if (!canBeAdvanced(card)) continue;
                // Skip advance for agendas that are already scoreable
                if (card.agenda_points != null and card.advancement_requirement != null and
                    card.advancement_counter >= card.advancement_requirement.? and
                    !cannot_score) continue;
                const text = try std.fmt.allocPrint(allocator, "{s}|c|{d}", .{ server.name, card_index });
                actions[next] = .{
                    .kind = .advance,
                    .side = .corp,
                    .choice = stringChoice(text),
                    .basic_action = .advance_installed,
                };
                next += 1;
            }
        }
    }
    // Per-agenda score actions
    if (scoreable_count > 0 and !cannot_score) {
        for (servers, 0..) |server, server_index| {
            if (server_index < 3) continue;
            for (server.content.items, 0..) |card, card_index| {
                if (card.agenda_points == null) continue;
                if (card.advancement_requirement == null) continue;
                if (card.advancement_counter < card.advancement_requirement.?) continue;
                const text = try std.fmt.allocPrint(allocator, "{s}|c|{d}", .{ server.name, card_index });
                actions[next] = .{
                    .kind = .score,
                    .side = .corp,
                    .choice = stringChoice(text),
                    .card_title = try allocator.dupe(u8, card.title),
                    .basic_action = .score_agenda,
                };
                next += 1;
            }
        }
    }
    if (g.corp_click >= 3) {
        actions[next] = try basicAbilityAction(allocator, .corp, .purge_viruses, "Purge virus counters");
        next += 1;
    }

    // Rez non-ICE cards (free action, no click cost)
    for (servers) |server| {
        for (server.content.items, 0..) |card, card_idx| {
            if (!card.rezzed and card.cost != null and g.corp_credit >= card.cost.?) {
                actions[next] = .{
                    .kind = .rez_non_ice,
                    .side = .corp,
                    .card_title = card.title,
                    .card_index = @intCast(card_idx),
                    .server = server.name,
                };
                next += 1;
            }
        }
    }

    return actions;
}

fn countScoreableAgendas(servers: []const MutableServer) usize {
    var count: usize = 0;
    for (servers, 0..) |server, server_index| {
        if (server_index < 3) continue;
        for (server.content.items) |card| {
            if (card.agenda_points == null) continue;
            if (card.advancement_requirement == null) continue;
            if (card.advancement_counter < card.advancement_requirement.?) continue;
            count += 1;
        }
    }
    return count;
}

fn countRezzableNonIce(g: *const Game) usize {
    var count: usize = 0;
    for (g.corp_servers.items) |server| {
        for (server.content.items) |card| {
            if (!card.rezzed and card.cost != null and g.corp_credit >= card.cost.?) count += 1;
        }
    }
    return count;
}

fn countInstalledCards(servers: []const MutableServer) usize {
    var count: usize = 0;
    for (servers) |server| {
        count += server.ices.items.len;
        count += server.content.items.len;
    }
    return count;
}

/// Rule 1.18.3: A card can be advanced if:
/// - It's unrezzed/facedown (corp can bluff-advance any facedown card)
/// - It's an agenda (always advanceable)
/// - It has the advanceable flag (e.g. Pharos, Clearinghouse)
/// - It has adds_advancement access (e.g. Urtica Cipher)
fn canBeAdvanced(card: state.CardInstance) bool {
    if (!card.rezzed) return true;
    return isAdvanceable(card);
}

fn countAdvanceableCards(servers: []const MutableServer) usize {
    var count: usize = 0;
    for (servers) |server| {
        for (server.ices.items) |card| {
            if (canBeAdvanced(card)) count += 1;
        }
        for (server.content.items) |card| {
            if (canBeAdvanced(card)) count += 1;
        }
    }
    return count;
}

fn runnerOpeningActionsForState(
    allocator: std.mem.Allocator,
    g: *const Game,
) ![]const state.LegalAction {
    if (g.runner_click == 0) return endTurnActions(allocator, .runner);

    const runnable_servers = try runnableServers(allocator, g.corp_servers.items);

    var playable_hand_count: usize = 0;
    for (g.runner_hand.items) |card| {
        const first_program_discount = if (card.runner_install.kind == .program) runnerInstalledFirstProgramDiscount(g, &card) else 0;
        if (isRunnerCardPlayableFromHand(g.runner_click, g.runner_credit, card, g.runner_successful_run_this_turn, first_program_discount, runnerHasConsoleInstalled(g), corpHasInstalledIce(g))) playable_hand_count += 1;
    }
    const resource_ability_count = countRunnerInstalledAbilityActions(g, .runner, g.runner_rig_resources.items);
    const hardware_ability_count = countRunnerInstalledAbilityActions(g, .runner, g.runner_rig_hardware.items);
    const program_ability_count = countRunnerInstalledAbilityActions(g, .runner, g.runner_rig_program.items);
    const installed_ability_count = resource_ability_count + hardware_ability_count + program_ability_count;

    // Identity abilities from abilities array
    var identity_ability_count: usize = 0;
    for (g.runner_identity.abilities, 0..) |ability, ability_idx| {
        const click_cost = if (ability.cost) |c| c.clicks else 0;
        const credit_cost = if (ability.cost) |c| c.credits else 0;
        if (click_cost > 0 and g.runner_click >= click_cost and g.runner_credit >= credit_cost and
            (!ability.once_per_turn or !isAbilityUsedThisTurn(&g.runner_identity, @intCast(ability_idx))))
        {
            if (ability.req) |req| {
                if (!req(effectContextConst(g), &g.runner_identity)) continue;
            }
            identity_ability_count += 1;
        }
    }

    var count: usize = playable_hand_count + installed_ability_count;
    if (g.runner_click >= 1) count += 1; // gain credit
    if (g.runner_click >= 1 and g.runner_deck.items.len > 0) count += 1; // draw card
    if (g.runner_click >= 1) count += runnable_servers.len; // run actions
    if (g.runner_click >= 1 and g.runner_credit >= 2 and is_runner_tagged(g.runner_tag)) count += 1;
    count += identity_ability_count;

    const actions = try allocator.alloc(state.LegalAction, count);
    var next: usize = 0;
    for (g.runner_hand.items, 0..) |card, idx| {
        const first_program_discount = if (card.runner_install.kind == .program) runnerInstalledFirstProgramDiscount(g, &card) else 0;
        if (!isRunnerCardPlayableFromHand(g.runner_click, g.runner_credit, card, g.runner_successful_run_this_turn, first_program_discount, runnerHasConsoleInstalled(g), corpHasInstalledIce(g))) continue;
        actions[next] = .{
            .kind = .play_from_hand,
            .side = .runner,
            .card_index = @intCast(idx),
            .card_title = try allocator.dupe(u8, card.title),
        };
        next += 1;
    }
    for (g.runner_rig_resources.items) |card| {
        next = try emitCardAbilityActions(allocator, g, .runner, card, actions, next);
    }
    for (g.runner_rig_program.items) |card| {
        next = try emitCardAbilityActions(allocator, g, .runner, card, actions, next);
    }
    for (g.runner_rig_hardware.items) |card| {
        next = try emitCardAbilityActions(allocator, g, .runner, card, actions, next);
    }

    if (g.runner_click >= 1) {
        actions[next] = try basicAbilityAction(allocator, .runner, .gain_credit, "Gain 1 [Credits]");
        next += 1;
    }
    if (g.runner_click >= 1 and g.runner_deck.items.len > 0) {
        actions[next] = try basicAbilityAction(allocator, .runner, .draw_card, "Draw 1 card");
        next += 1;
    }
    if (g.runner_click >= 1) {
        for (runnable_servers) |server_name| {
            actions[next] = .{
                .kind = .run,
                .side = .runner,
                .server = server_name,
            };
            next += 1;
        }
    }
    if (g.runner_click >= 1 and g.runner_credit >= 2 and is_runner_tagged(g.runner_tag)) {
        actions[next] = try basicAbilityAction(allocator, .runner, .remove_tag, "Remove 1 tag");
        next += 1;
    }
    for (g.runner_identity.abilities, 0..) |ability, ability_idx| {
        const click_cost = if (ability.cost) |c| c.clicks else 0;
        const credit_cost = if (ability.cost) |c| c.credits else 0;
        if (click_cost > 0 and g.runner_click >= click_cost and g.runner_credit >= credit_cost and
            (!ability.once_per_turn or !isAbilityUsedThisTurn(&g.runner_identity, @intCast(ability_idx))))
        {
            if (ability.req) |req| {
                if (!req(effectContextConst(g), &g.runner_identity)) continue;
            }
            actions[next] = .{
                .kind = .use_identity_ability,
                .side = .runner,
                .card_title = try allocator.dupe(u8, g.runner_identity.title),
                .ability_ref = .{ .source_instance_id = g.runner_identity.instance_id, .ability_index = @intCast(ability_idx) },
                .label = try allocator.dupe(u8, ability.label orelse "Use identity ability"),
            };
            next += 1;
        }
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

fn countCardAbilityActions(generated: *const Game, side: state.Side, card: state.CardInstance) usize {
    var count: usize = 0;
    for (card.abilities, 0..) |ability, ability_idx| {
        if (ability.is_access_ability) continue;
        if (side != card.side and !ability.allow_opponent_use) continue;
        const click_cost = if (ability.cost) |c| c.clicks else 0;
        const credit_cost = if (ability.cost) |c| c.credits else 0;
        const clicks = if (side == .runner) generated.runner_click else generated.corp_click;
        const credits = if (side == .runner) generated.runner_credit else generated.corp_credit;
        if (clicks < click_cost or credits < credit_cost) continue;
        if (ability.once_per_turn and isAbilityUsedThisTurn(&card, @intCast(ability_idx))) continue;
        if (ability.req) |req| {
            if (!req(effectContextConst(generated), &card)) continue;
        }
        count += 1;
    }
    return count;
}

fn emitCardAbilityActions(
    allocator: std.mem.Allocator,
    generated: *const Game,
    side: state.Side,
    card: state.CardInstance,
    actions: []state.LegalAction,
    start: usize,
) !usize {
    var next = start;
    for (card.abilities, 0..) |ability, ability_idx| {
        if (ability.is_access_ability) continue;
        if (side != card.side and !ability.allow_opponent_use) continue;
        const click_cost = if (ability.cost) |c| c.clicks else 0;
        const credit_cost = if (ability.cost) |c| c.credits else 0;
        const clicks = if (side == .runner) generated.runner_click else generated.corp_click;
        const credits = if (side == .runner) generated.runner_credit else generated.corp_credit;
        if (clicks < click_cost or credits < credit_cost) continue;
        if (ability.once_per_turn and isAbilityUsedThisTurn(&card, @intCast(ability_idx))) continue;
        if (ability.req) |req| {
            if (!req(effectContextConst(generated), &card)) continue;
        }
        actions[next] = .{
            .kind = .use_installed_ability,
            .side = side,
            .card_title = try allocator.dupe(u8, card.title),
            .ability_ref = .{ .source_instance_id = card.instance_id, .ability_index = @intCast(ability_idx) },
            .label = try allocator.dupe(u8, ability.label orelse "Use ability"),
        };
        next += 1;
    }
    return next;
}

fn countRunnerInstalledAbilityActions(generated: *const Game, side: state.Side, cards: []const state.CardInstance) usize {
    var count: usize = 0;
    for (cards) |card| {
        count += countCardAbilityActions(generated, side, card);
    }
    return count;
}

fn countCorpInstalledAbilityActions(generated: *const Game, servers: []const MutableServer) usize {
    var count: usize = 0;
    for (servers) |server| {
        for (server.content.items) |card| {
            if (card.rezzed) count += countCardAbilityActions(generated, .corp, card);
        }
    }
    return count;
}

fn buildDeck(
    allocator: std.mem.Allocator,
    rng_state: *RngState,
    side_spec: SideSpec,
    next_id: *u32,
) ![]state.CardInstance {
    const shuffled_lines = try allocator.dupe(DeckLine, side_spec.deck_lines);
    shuffleInPlace(DeckLine, rng_state, shuffled_lines);

    const total_cards = countCards(shuffled_lines);
    const cards = try allocator.alloc(state.CardInstance, total_cards);

    var idx: usize = 0;
    for (shuffled_lines) |line| {
        var copy_idx: u8 = 0;
        while (copy_idx < line.qty) : (copy_idx += 1) {
            cards[idx] = try makeCardInstance(allocator, try lookupRequiredCardSpec(line.card_code), next_id);
            idx += 1;
        }
    }

    shuffleInPlace(state.CardInstance, rng_state, cards);
    return cards;
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
    if (card.hosted.len > 0) {
        const hosted_copy = try allocator.alloc(state.CardInstance, card.hosted.len);
        for (card.hosted, 0..) |h, i| hosted_copy[i] = try deepCloneCard(allocator, h);
        cloned.hosted = hosted_copy;
    }
    return cloned;
}

fn cloneCards(
    allocator: std.mem.Allocator,
    cards: []const state.CardInstance,
) ![]const state.CardInstance {
    const copy = try allocator.alloc(state.CardInstance, cards.len);
    for (cards, 0..) |card, idx| copy[idx] = card;
    return copy;
}

fn countCards(lines: []const DeckLine) usize {
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

const RunnerRigZone = enum(u8) {
    resources,
    programs,
    hardware,
};

const RunnerRigCardRef = struct {
    zone: RunnerRigZone,
    zone_index: usize,
    combined_index: u8,
    card: *state.CardInstance,
};

fn appendHostedCard(
    allocator: std.mem.Allocator,
    host: *state.CardInstance,
    card: state.CardInstance,
) !void {
    const hosted = try allocator.alloc(state.CardInstance, host.hosted.len + 1);
    @memcpy(hosted[0..host.hosted.len], host.hosted);
    hosted[host.hosted.len] = card;
    host.hosted = hosted;
}

fn removeHostedCard(
    allocator: std.mem.Allocator,
    host: *state.CardInstance,
    hosted_index: usize,
) !state.CardInstance {
    if (hosted_index >= host.hosted.len) return error.InvalidCardIndex;
    const removed = host.hosted[hosted_index];
    if (host.hosted.len == 1) {
        host.hosted = &.{};
        return removed;
    }
    const hosted = try allocator.alloc(state.CardInstance, host.hosted.len - 1);
    if (hosted_index > 0) @memcpy(hosted[0..hosted_index], host.hosted[0..hosted_index]);
    if (hosted_index + 1 < host.hosted.len) {
        @memcpy(hosted[hosted_index..], host.hosted[hosted_index + 1 ..]);
    }
    host.hosted = hosted;
    return removed;
}

fn hostedChoiceIndex(prompt: state.PromptState, choice_text: []const u8) ?usize {
    for (prompt.choices) |choice| {
        if (choice.text == null or !std.mem.eql(u8, choice.text.?, choice_text)) continue;
        if (choice.card) |card_ref| {
            if (card_ref.index) |index| return index;
        }
    }
    return null;
}

fn restorePriorityAfterPrompt(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    if (generated.run != null and std.mem.eql(u8, generated.run.?.phase, "success")) {
        try enterSuccessAccessPhase(generated);
        return;
    }
    generated.decision_side = generated.active_player;
    generated.legal_actions = switch (generated.active_player) {
        .corp => try corpOpeningActionsForState(allocator, generated),
        .runner => try runnerOpeningActionsForState(allocator, generated),
    };
}

fn beginYesNoPrompt(
    generated: *Game,
    side: state.Side,
    prompt_type: []const u8,
    source_card: state.CardInstance,
    on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void,
) !void {
    const allocator = generated.arena.allocator();
    const prompt_state: state.PromptState = .{
        .prompt_type = try allocator.dupe(u8, prompt_type),
        .choices = try allocator.dupe(state.PromptChoice, &.{ stringChoice("Yes"), stringChoice("No") }),
        .source_card = source_card,
        .on_choice = on_choice,
    };
    switch (side) {
        .corp => generated.corp_prompt_state = prompt_state,
        .runner => generated.runner_prompt_state = prompt_state,
    }
    generated.decision_side = side;
    generated.legal_actions = try promptChoiceActions(allocator, side, switch (side) {
        .corp => generated.corp_prompt_state.?,
        .runner => generated.runner_prompt_state.?,
    });
}

fn findRunnerHardwareByCode(generated: *Game, code: u32) ?*state.CardInstance {
    for (generated.runner_rig_hardware.items) |*card| {
        if (card.code != null and card.code.? == code) return card;
    }
    return null;
}

fn findCardPtrByInstanceId(generated: *Game, instance_id: u32) ?*state.CardInstance {
    if (generated.corp_identity.instance_id == instance_id) return &generated.corp_identity;
    if (generated.runner_identity.instance_id == instance_id) return &generated.runner_identity;
    for (generated.corp_hand.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.corp_deck.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.corp_discard.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.corp_scored.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.runner_hand.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.runner_deck.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.runner_discard.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.runner_scored.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.runner_rig_hardware.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.runner_rig_program.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.runner_rig_resources.items) |*card| {
        if (card.instance_id == instance_id) return card;
    }
    for (generated.corp_servers.items) |*server| {
        for (server.ices.items) |*card| {
            if (card.instance_id == instance_id) return card;
            for (card.hosted) |*hosted| {
                if (hosted.instance_id == instance_id) return hosted;
            }
        }
        for (server.content.items) |*card| {
            if (card.instance_id == instance_id) return card;
        }
    }
    return null;
}

fn findRunnerRigCardByInstanceId(generated: *Game, instance_id: u32) ?RunnerRigCardRef {
    for (generated.runner_rig_resources.items, 0..) |*card, idx| {
        if (card.instance_id == instance_id) return .{
            .zone = .resources,
            .zone_index = idx,
            .combined_index = @intCast(idx),
            .card = card,
        };
    }
    const res_len = generated.runner_rig_resources.items.len;
    for (generated.runner_rig_program.items, 0..) |*card, idx| {
        if (card.instance_id == instance_id) return .{
            .zone = .programs,
            .zone_index = idx,
            .combined_index = @intCast(res_len + idx),
            .card = card,
        };
    }
    const prog_start = res_len + generated.runner_rig_program.items.len;
    for (generated.runner_rig_hardware.items, 0..) |*card, idx| {
        if (card.instance_id == instance_id) return .{
            .zone = .hardware,
            .zone_index = idx,
            .combined_index = @intCast(prog_start + idx),
            .card = card,
        };
    }
    return null;
}

const CorpServerCardRef = struct {
    server_index: usize,
    content_index: usize,
    card: *state.CardInstance,
};

fn findCorpServerCardByInstanceId(generated: *Game, instance_id: u32) ?CorpServerCardRef {
    for (generated.corp_servers.items, 0..) |*server, server_idx| {
        for (server.content.items, 0..) |*card, content_idx| {
            if (card.instance_id == instance_id) return .{
                .server_index = server_idx,
                .content_index = content_idx,
                .card = card,
            };
        }
    }
    return null;
}

fn findHostedCardOnIce(generated: *Game, instance_id: u32) ?*state.CardInstance {
    for (generated.corp_servers.items) |*server| {
        for (server.ices.items) |*ice| {
            for (ice.hosted) |*hosted| {
                if (hosted.instance_id == instance_id) return hosted;
            }
        }
    }
    return null;
}

fn trashRunnerRigCardByInstanceId(generated: *Game, instance_id: u32) !void {
    const rig_ref = findRunnerRigCardByInstanceId(generated, instance_id) orelse return error.CardNotFound;
    const trashed = switch (rig_ref.zone) {
        .resources => generated.runner_rig_resources.orderedRemove(rig_ref.zone_index),
        .programs => blk: {
            const t = generated.runner_rig_program.orderedRemove(rig_ref.zone_index);
            if (generated.runner_memory) |*mem| {
                const mu = t.runner_install.mu_cost;
                if (mem.used >= mu) mem.used -= mu else mem.used = 0;
                mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
            }
            break :blk t;
        },
        .hardware => generated.runner_rig_hardware.orderedRemove(rig_ref.zone_index),
    };
    try appendDiscardCard(generated, .runner, trashed);
}

fn trashCorpServerCardByInstanceId(generated: *Game, instance_id: u32) !void {
    const ref = findCorpServerCardByInstanceId(generated, instance_id) orelse return error.CardNotFound;
    const trashed = generated.corp_servers.items[ref.server_index].content.orderedRemove(ref.content_index);
    try appendDiscardCard(generated, .corp, trashed);
    try removeServerIfEmpty(generated, ref.server_index);
}

fn applyAbilityRef(generated: *Game, action: state.LegalAction) !void {
    const ref = action.ability_ref orelse return error.MissingAbilityRef;
    const allocator = generated.arena.allocator();

    // --- Generic AbilitySpec dispatch: resolve through abilities array ---
    {
        const card = findCardPtrByInstanceId(generated, ref.source_instance_id) orelse return error.CardNotFound;
        if (ref.ability_index < card.abilities.len) {
            const ability = card.abilities[ref.ability_index];

            if (ability.once_per_turn and isAbilityUsedThisTurn(card, @intCast(ref.ability_index))) return error.AbilityAlreadyUsed;
            if (ability.req) |req| {
                if (!req(effectContextConst(generated), card)) return error.UnsupportedAction;
            }

            if (ability.cost) |cost| {
                try spendClicks(generated, action.side, cost.clicks);
                try spendCredits(generated, action.side, cost.credits);
            }
            if (ability.once_per_turn) markAbilityUsedThisTurn(card, @intCast(ref.ability_index));

            if (ability.on_use) |handler| {
                try handler(effectContext(generated), card);
            }
            if (!hasActivePrompt(generated) and generated.pending_access == null and generated.run == null) {
                generated.decision_side = action.side;
                if (action.side == .runner) {
                    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
                } else {
                    generated.legal_actions = try corpOpeningActionsForState(allocator, generated);
                }
            }
            return;
        }
    }

    // All abilities (encounter, manual, identity, bioroid) are now resolved through the
    // generic AbilitySpec dispatch above. If we reach here, the ability was not found.
    return error.UnsupportedAbility;
}

fn findRunnerRigCardRef(generated: *Game, combined_index: u8) ?RunnerRigCardRef {
    if (combined_index < generated.runner_rig_resources.items.len) {
        return .{
            .zone = .resources,
            .zone_index = combined_index,
            .combined_index = combined_index,
            .card = &generated.runner_rig_resources.items[combined_index],
        };
    }
    const program_start = generated.runner_rig_resources.items.len;
    if (combined_index < program_start + generated.runner_rig_program.items.len) {
        const zone_index = combined_index - @as(u8, @intCast(program_start));
        return .{
            .zone = .programs,
            .zone_index = zone_index,
            .combined_index = combined_index,
            .card = &generated.runner_rig_program.items[zone_index],
        };
    }
    const hardware_start = generated.runner_rig_resources.items.len + generated.runner_rig_program.items.len;
    if (combined_index < hardware_start + generated.runner_rig_hardware.items.len) {
        const zone_index = combined_index - @as(u8, @intCast(hardware_start));
        return .{
            .zone = .hardware,
            .zone_index = zone_index,
            .combined_index = combined_index,
            .card = &generated.runner_rig_hardware.items[zone_index],
        };
    }
    return null;
}

fn countPlayableHostedRunnerCards(generated: *const Game, host: state.CardInstance) usize {
    var count: usize = 0;
    const has_console = runnerHasConsoleInstalled(generated);
    const has_ice = corpHasInstalledIce(generated);
    for (host.hosted) |card| {
        const first_program_discount = if (card.runner_install.kind == .program) runnerInstalledFirstProgramDiscount(generated, &card) else 0;
        if (isRunnerCardPlayableFromHand(
            generated.runner_click,
            generated.runner_credit,
            card,
            generated.runner_successful_run_this_turn,
            first_program_discount,
            has_console,
            has_ice,
        )) count += 1;
    }
    return count;
}

fn beginRunnerHostedCardPrompt(generated: *Game, source_card: state.CardInstance, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
    const allocator = generated.arena.allocator();
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);

    const has_console = runnerHasConsoleInstalled(generated);
    const has_ice = corpHasInstalledIce(generated);
    for (source_card.hosted, 0..) |card, idx| {
        const first_program_discount = if (card.runner_install.kind == .program) runnerInstalledFirstProgramDiscount(generated, &card) else 0;
        if (!isRunnerCardPlayableFromHand(
            generated.runner_click,
            generated.runner_credit,
            card,
            generated.runner_successful_run_this_turn,
            first_program_discount,
            has_console,
            has_ice,
        )) continue;
        try choices.append(allocator, .{
            .kind = .card,
            .text = try allocator.dupe(u8, card.title),
            .card = .{ .title = card.title, .printed_title = card.printed_title, .code = card.code, .side = card.side, .index = @intCast(idx) },
        });
    }
    if (choices.items.len == 0) return;
    try choices.append(allocator, stringChoice("No action"));
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "runner-hosted-card"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = source_card,
        .on_choice = on_choice,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
}

fn hostTopRunnerDeckCard(generated: *Game, host: *state.CardInstance) !void {
    if (generated.runner_deck.items.len == 0) return;
    const card = generated.runner_deck.orderedRemove(0);
    try appendHostedCard(generated.arena.allocator(), host, card);
}

fn trashHostedRunnerCards(generated: *Game, host: *state.CardInstance) !void {
    while (host.hosted.len > 0) {
        const trashed = try removeHostedCard(generated.arena.allocator(), host, 0);
        try appendDiscardCard(generated, .runner, trashed);
    }
}

fn returnHostedCardsToHq(generated: *Game, host: *state.CardInstance, count: usize) !void {
    var remaining = count;
    while (remaining > 0 and host.hosted.len > 0) : (remaining -= 1) {
        const returned = try removeHostedCard(generated.arena.allocator(), host, 0);
        try generated.corp_hand.append(generated.backing_allocator, returned);
    }
}

fn shuffledCorpHandIndex(generated: *Game) !?u8 {
    if (generated.corp_hand.items.len == 0) return null;
    const chosen = try peekShuffledCorpHandIndex(generated);
    var shuffled_indexes: [64]usize = undefined;
    for (generated.corp_hand.items, 0..) |_, idx| {
        shuffled_indexes[idx] = idx;
    }
    var rng_state = fromOracleSeed(generated.rng_seed orelse return error.MissingRngSeed);
    shuffleInPlace(usize, &rng_state, shuffled_indexes[0..generated.corp_hand.items.len]);
    generated.rng_seed = oracleSeed(rng_state);
    return chosen;
}

fn peekShuffledCorpHandIndex(generated: *const Game) !?u8 {
    if (generated.corp_hand.items.len == 0) return null;
    var shuffled_indexes: [64]usize = undefined;
    for (generated.corp_hand.items, 0..) |_, idx| {
        shuffled_indexes[idx] = idx;
    }
    var rng_state = fromOracleSeed(generated.rng_seed orelse return error.MissingRngSeed);
    shuffleInPlace(usize, &rng_state, shuffled_indexes[0..generated.corp_hand.items.len]);
    return @intCast(shuffled_indexes[0]);
}

fn hostRandomHqCard(generated: *Game, host: *state.CardInstance) !void {
    const chosen = try peekShuffledCorpHandIndex(generated) orelse return;
    var card = generated.corp_hand.orderedRemove(chosen);
    card.seen = true;
    try appendHostedCard(generated.arena.allocator(), host, card);
}

fn beginRandomHqAccess(generated: *Game) !void {
    const chosen = try shuffledCorpHandIndex(generated) orelse return;
    const accessed = generated.corp_hand.items[chosen];
    generated.pending_access = .{ .zone = .corp_hand, .card_index = chosen };
    if (try beginAccessFlow(generated, accessed)) {
        generated.decision_side = .runner;
        generated.legal_actions = try promptChoiceActions(generated.arena.allocator(), .runner, generated.runner_prompt_state.?);
        return;
    }
    if (try beginNoActionAccessPrompt(generated, accessed)) {
        generated.decision_side = .runner;
        generated.legal_actions = try promptChoiceActions(generated.arena.allocator(), .runner, generated.runner_prompt_state.?);
        return;
    }
    try finishAccessCard(generated);
}

fn makeCardInstance(
    allocator: std.mem.Allocator,
    spec: CardSpec,
    next_id: *u32,
) !state.CardInstance {
    const subtypes = try allocator.alloc([]const u8, spec.subtypes.len);
    for (spec.subtypes, 0..) |subtype, i| {
        subtypes[i] = try allocator.dupe(u8, subtype);
    }

    const id = next_id.*;
    next_id.* += 1;

    return .{
        .instance_id = id,
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
        .install = spec.install,
        .runner_install = spec.runner_install,
        .abilities = spec.abilities,
        .static_abilities = spec.static_abilities,
        .event_abilities = spec.event_abilities,
        .initial_credit_counters = spec.initial_credit_counters,
        .take_credits_amount = spec.take_credits_amount,
        .trash_on_empty = spec.trash_on_empty,
        .on_install = spec.on_install,
        .on_take = spec.on_take,
        .on_empty = spec.on_empty,
        .click_draw_bonus = spec.click_draw_bonus,
        .auto_trash_at_credits = spec.auto_trash_at_credits,
        .draw_on_auto_trash = spec.draw_on_auto_trash,
        .place_credits_per_turn = spec.place_credits_per_turn,
        .auto_take_credits = spec.auto_take_credits,
        .subroutines = spec.subroutines,
        .advancement_counter = 0,
        .credit_counter = 0,
        .abilities_used_this_turn = 0,
        .broken_subroutines = 0,
    };
}

fn makeGameCard(game: *Game, spec: CardSpec) !state.CardInstance {
    return makeCardInstance(game.arena.allocator(), spec, &game.next_instance_id);
}

fn lookupRequiredCardSpec(card_code: u32) !CardSpec {
    return lookupCardSpecByCode(card_code) orelse error.UnknownCardCode;
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
    refreshDerivedStates(game);
}

fn resetInstalledAbilityUsage(game: *Game) void {
    clearAbilityUsage(&game.corp_identity);
    clearAbilityUsage(&game.runner_identity);
    for (game.corp_servers.items) |*server| {
        for (server.content.items) |*card| {
            clearAbilityUsage(card);
        }
    }
    for (game.runner_rig_hardware.items) |*card| {
        clearAbilityUsage(card);
    }
    for (game.runner_rig_program.items) |*card| {
        clearAbilityUsage(card);
    }
    for (game.runner_rig_resources.items) |*card| {
        clearAbilityUsage(card);
    }
}

fn applyCorpStartOfTurnAbilities(game: *Game) !void {
    // Nico Campaign and similar: auto-take credits at start of corp turn
    var server_index: usize = 0;
    while (server_index < game.corp_servers.items.len) {
        var removed_server = false;
        var i: usize = 0;
        while (i < game.corp_servers.items[server_index].content.items.len) {
            var card = &game.corp_servers.items[server_index].content.items[i];
            if (card.auto_take_credits and card.rezzed and card.credit_counter > 0) {
                const take = @min(card.credit_counter, card.take_credits_amount);
                card.credit_counter -= take;
                game.corp_credit += take;
                if (card.on_take) |callback| {
                    try callback(effectContext(game), card);
                }

                if (card.trash_on_empty and card.credit_counter == 0) {
                    if (card.on_empty) |callback| {
                        try callback(effectContext(game), card);
                    }
                    const trashed = game.corp_servers.items[server_index].content.orderedRemove(i);
                    try appendDiscardCard(game, .corp, trashed);
                    const server_count = game.corp_servers.items.len;
                    try removeServerIfEmpty(game, server_index);
                    if (game.corp_servers.items.len < server_count) {
                        removed_server = true;
                        break;
                    }
                    continue; // Don't increment i
                }
            }
            i += 1;
        }
        if (!removed_server) server_index += 1;
    }
}

fn endCorpPhase12(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.corp_phase_12 = false;
    expireFloatingEffects(generated, .end_of_turn);

    // Corp must draw at start of turn — empty deck means runner wins
    if (generated.corp_deck.items.len == 0) {
        setGameOver(generated, .runner);
        return;
    }
    try drawCard(generated, .corp);
    generated.systemMsg(.corp, 0, "Corp draws 1 card for their mandatory draw.", .{});
    generated.corp_click = generated.corp_click_per_turn;
    generated.runner_successful_run_last_turn = generated.runner_successful_run_this_turn;
    generated.runner_successful_run_this_turn = false;

    // Clear installed_this_turn flags for all corp cards
    clearInstalledThisTurnFlags(generated);

    if (try fireEvent(generated, .corp_turn_begins)) return;
    if (generated.game_over) return;

    // Auto-trigger start-of-turn abilities (Nico Campaign)
    try applyCorpStartOfTurnAbilities(generated);
    if (generated.game_over) return;

    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(allocator, generated);
}

fn clearInstalledThisTurnFlags(game: *Game) void {
    for (game.corp_servers.items) |*server| {
        for (server.ices.items) |*card| {
            card.installed_this_turn = false;
        }
        for (server.content.items) |*card| {
            card.installed_this_turn = false;
        }
    }
}

fn applySourceCardOnSuccessfulRun(game: *Game) !void {
    const run = game.run orelse return;
    const source_id = run.source_instance_id orelse return;

    // Find the source card in runner's rig by instance_id
    for (game.runner_rig_resources.items, 0..) |*card, idx| {
        if (card.instance_id == source_id and card.credit_counter > 0) {
            const take = @min(card.credit_counter, card.take_credits_amount);
            card.credit_counter -= take;
            game.runner_credit += take;

            // Trash card if empty and trash_on_empty
            if (card.trash_on_empty and card.credit_counter == 0) {
                const trashed = game.runner_rig_resources.orderedRemove(idx);
                try appendDiscardCard(game, .runner, trashed);
            }
            return;
        }
    }
}

fn runnerRdAccessBonus(generated: *const Game) u8 {
    return clampStaticTotal(sumStaticEffects(generated, .runner, .rd_access, null));
}

fn runnerInstalledFirstProgramDiscount(generated: *const Game, target: *const state.CardInstance) u16 {
    const modifier = runnerInstallCostModifier(generated, target);
    return if (modifier < 0) @intCast(-modifier) else 0;
}

fn runnerCookbookBonus(generated: *const Game, card: *const state.CardInstance) u16 {
    return clampStaticTotal(sumStaticEffects(generated, .runner, .virus_install_bonus, card));
}

fn applyRunnerInstalledCardCounters(generated: *Game, card: *state.CardInstance) void {
    if (card.runner_install.kind != .program) return;
    if (card.on_install) |callback| {
        callback(effectContext(generated), card) catch unreachable;
    }
    if (card.virus_counter > 0 or hasSubtype(card.*, "Virus")) {
        card.virus_counter += runnerCookbookBonus(generated, card);
    }
}

/// Check if runner has a run event in play area (Sang Kancil pump discount)
fn runnerHasActiveRunEvent(generated: *const Game) bool {
    // Run events are in the play area when active — check if run has a source card
    // that is a run event (subtypes include "Run")
    if (generated.run) |run| {
        if (run.source_instance_id) |_| return true;
    }
    return false;
}

/// Count fracters in runner's heap (Rising Tide strength bonus)
fn countFractersInHeap(generated: *const Game) u8 {
    var count: u8 = 0;
    for (generated.runner_discard.items) |card| {
        if (hasSubtype(card, "Fracter")) count += 1;
    }
    return count;
}

/// Count installed icebreakers (Principia install cost reduction)
fn countInstalledIcebreakers(generated: *const Game) u16 {
    var count: u16 = 0;
    for (generated.runner_rig_program.items) |card| {
        if (isIcebreaker(card)) count += 1;
    }
    return count;
}

fn applyAmazeTagsOnRunEnd(_: *Game) void {
    // Tags on steal are now applied immediately in applyStealAgendaChoice
}

fn applyIdentityOnSuccessfulRun(game: *Game) !void {
    game.turn_events.successful_run_ends_count += 1;
    _ = try fireEvent(game, .successful_run_ends);
}

fn endOfRunCleanup(game: *Game) void {
    // Expire run-scoped and encounter-scoped floating effects
    expireFloatingEffects(game, .end_of_run);
    expireFloatingEffects(game, .end_of_encounter);
}

fn drawCard(game: *Game, side: state.Side) !void {
    const deck = deckList(game, side);
    if (deck.items.len == 0) {
        // Deck-out: if corp can't draw at start of turn, they lose
        if (side == .corp) {
            setGameOver(game, .runner);
            return error.EmptyDeck;
        }
        return error.EmptyDeck;
    }
    const drawn = deck.orderedRemove(0);
    try handList(game, side).append(game.backing_allocator, drawn);
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
    // Trash from front of hand (index 0). Clojure uses Java's rand-nth which is
    // separate from the game RNG, so we must NOT consume the game RNG here.
    // Both engines agree on the number of cards trashed; specific cards may differ
    // but parity comparison checks hand titles as a set, not order.
    var remaining = amount;
    while (remaining > 0 and game.runner_hand.items.len > 0) : (remaining -= 1) {
        const trashed = game.runner_hand.orderedRemove(0);
        try game.runner_discard.append(game.backing_allocator, trashed);
    }
}

fn shuffleDeck(game: *Game, side: state.Side) !void {
    const deck = deckList(game, side);
    var rng_state = fromOracleSeed(game.rng_seed orelse return error.MissingRngSeed);
    shuffleInPlace(state.CardInstance, &rng_state, deck.items);
    game.rng_seed = oracleSeed(rng_state);
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
    return removed;
}

fn appendDiscardCard(
    game: *Game,
    side: state.Side,
    card: state.CardInstance,
) !void {
    try discardList(game, side).append(game.backing_allocator, card);
}

fn moveCorpHandCardToDeckAndShuffle(game: *Game, card_index: u8) !void {
    if (card_index >= game.corp_hand.items.len) return error.InvalidCardIndex;
    const shuffled = game.corp_hand.orderedRemove(card_index);
    try game.corp_deck.append(game.backing_allocator, shuffled);
    try shuffleDeck(game, .corp);
}

fn beginRunnerDiscardProgramToDeckPrompt(
    game: *Game,
    source_card: state.CardInstance,
) !bool {
    return beginRunnerDiscardProgramToDeckPromptWithChoice(game, source_card, null);
}

fn beginRunnerDiscardProgramToDeckPromptWithChoice(
    game: *Game,
    source_card: state.CardInstance,
    on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void,
) !bool {
    const allocator = game.arena.allocator();
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    for (game.runner_discard.items, 0..) |card, idx| {
        const card_type = card.card_type orelse continue;
        if (!std.mem.eql(u8, card_type, "Program")) continue;
        try choices.append(allocator, .{
            .kind = .card,
            .text = try allocator.dupe(u8, card.title),
            .card = .{ .title = card.title, .printed_title = card.printed_title, .code = card.code, .side = .runner, .index = @intCast(idx) },
        });
    }
    if (choices.items.len == 0) return false;
    try choices.append(allocator, stringChoice("No action"));
    game.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "runner-discard-to-deck"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = source_card,
        .on_choice = on_choice,
    };
    game.decision_side = .runner;
    game.legal_actions = try promptChoiceActions(allocator, .runner, game.runner_prompt_state.?);
    return true;
}

fn spendClicks(
    game: *Game,
    side: state.Side,
    amount: u8,
) !void {
    const click = switch (side) {
        .corp => &game.corp_click,
        .runner => &game.runner_click,
    };
    if (click.* < amount) return error.InsufficientClicks;
    click.* -= amount;
}

fn spendCredits(
    game: *Game,
    side: state.Side,
    amount: u16,
) !void {
    const credit = switch (side) {
        .corp => &game.corp_credit,
        .runner => &game.runner_credit,
    };
    if (credit.* < amount) return error.InsufficientCredits;
    credit.* -= amount;
}

fn parseKeepState(text: []const u8) state.KeepState {
    if (std.mem.eql(u8, text, "Keep")) return .keep;
    if (std.mem.eql(u8, text, "Mulligan")) return .mulligan;
    return .undecided;
}

fn isCorpCardPlayableFromHand(
    g: *const Game,
    card: state.CardInstance,
) bool {
    if (g.corp_click < 1) return false;
    const card_type = card.card_type orelse return false;
    if (std.mem.eql(u8, card_type, "Operation")) {
        if (g.corp_credit < (card.cost orelse 0)) return false;
        // Check card-specific preconditions (e.g., Public Trail requires runner ran last turn)
        if (card.code) |code| {
            if (lookupCardSpecByCode(code)) |spec| {
                if (findPlayAbility(spec.abilities)) |play_ability| {
                    if (play_ability.req) |req| {
                        var dummy_card = card;
                        if (!req(constEffectContext(g), &dummy_card)) return false;
                    }
                }
            }
        }
        return true;
    }

    return card.install.kind != .none;
}

fn isCorpFlashbackPlayable(g: *const Game, card: state.CardInstance) bool {
    const card_type = card.card_type orelse return false;
    if (!std.mem.eql(u8, card_type, "Operation")) return false;
    const code = card.code orelse return false;
    const spec = lookupCardSpecByCode(code) orelse return false;
    const play_ability = findPlayAbility(spec.abilities) orelse return false;
    if (play_ability.flashback_extra_clicks == 0) return false; // no flashback
    if (g.corp_click < 1 + play_ability.flashback_extra_clicks) return false;
    if (g.corp_credit < (card.cost orelse 0)) return false;
    if (play_ability.req) |req| {
        var dummy_card = card;
        if (!req(constEffectContext(g), &dummy_card)) return false;
    }
    return true;
}

fn countCorpFlashbackActions(g: *const Game) usize {
    var count: usize = 0;
    for (g.corp_discard.items) |card| {
        if (isCorpFlashbackPlayable(g, card)) count += 1;
    }
    return count;
}

fn runnerHasConsoleInstalled(g: *const Game) bool {
    for (g.runner_rig_hardware.items) |card| {
        if (hasSubtype(card, "Console")) return true;
    }
    return false;
}

fn corpHasInstalledIce(g: *const Game) bool {
    for (g.corp_servers.items) |server| {
        if (server.ices.items.len > 0) return true;
    }
    return false;
}

fn isRunnerCardPlayableFromHand(
    click: u8,
    credit: u16,
    card: state.CardInstance,
    successful_run_this_turn: bool,
    first_program_discount: u16,
    has_console: bool,
    has_ice: bool,
) bool {
    if (click < 1) return false;
    if (card.runner_install.kind != .none) {
        // Console restriction: can't install a console if one is already installed
        if (hasSubtype(card, "Console") and has_console) return false;
        // Trojan restriction: can't install trojan if no ICE exists
        if (hasSubtype(card, "Trojan") and !has_ice) return false;
        var cost = card.cost orelse 0;
        if (card.runner_install.install_cost_reduction_if_successful_run > 0 and successful_run_this_turn) {
            cost = if (cost >= card.runner_install.install_cost_reduction_if_successful_run)
                cost - card.runner_install.install_cost_reduction_if_successful_run
            else
                0;
        }
        if (card.runner_install.kind == .program and first_program_discount > 0) {
            cost = if (cost >= first_program_discount) cost - first_program_discount else 0;
        }
        return credit >= cost;
    }
    const card_type = card.card_type orelse return false;
    if (!std.mem.eql(u8, card_type, "Event")) return false;
    return credit >= (card.cost orelse 0);
}

fn iceInstallChoices(
    allocator: std.mem.Allocator,
    game: *const Game,
) ![]const state.PromptChoice {
    // ICE can be installed on any server (centrals + existing remotes + "New remote")
    // Show all servers regardless of affordability (matching Clojure)
    // Order must match oracle: Archives, HQ, New remote, R&D, Server 1, Server 2, ...
    var remote_count: usize = 0;
    for (game.corp_servers.items, 0..) |_, si| {
        if (si >= 3) remote_count += 1;
    }
    const count: usize = 4 + remote_count;
    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    choices[next] = stringChoice("Archives");
    next += 1;
    choices[next] = stringChoice("HQ");
    next += 1;
    choices[next] = stringChoice("New remote");
    next += 1;
    choices[next] = stringChoice("R&D");
    next += 1;
    var remote_num: usize = 1;
    for (game.corp_servers.items, 0..) |_, si| {
        if (si >= 3) {
            choices[next] = stringChoice(try std.fmt.allocPrint(allocator, "Server {}", .{remote_num}));
            next += 1;
            remote_num += 1;
        }
    }
    return choices;
}

fn installChoicesForCard(
    allocator: std.mem.Allocator,
    install_kind: state.InstallKind,
    game: ?*const Game,
) ![]const state.PromptChoice {
    return switch (install_kind) {
        .corp_server_choice => blk: {
            // ICE/upgrades: any server (centrals + remotes + new remote)
            var remote_count: usize = 0;
            if (game) |g| {
                for (g.corp_servers.items, 0..) |_, si| {
                    if (si >= 3) remote_count += 1;
                }
            }
            const choices = try allocator.alloc(state.PromptChoice, 4 + remote_count);
            choices[0] = stringChoice("Archives");
            choices[1] = stringChoice("HQ");
            choices[2] = stringChoice("New remote");
            choices[3] = stringChoice("R&D");
            if (game) |g| {
                var idx: usize = 4;
                var remote_num: usize = 1;
                for (g.corp_servers.items, 0..) |_, si| {
                    if (si >= 3) {
                        choices[idx] = stringChoice(try std.fmt.allocPrint(allocator, "Server {d}", .{remote_num}));
                        idx += 1;
                        remote_num += 1;
                    }
                }
            }
            break :blk choices;
        },
        .corp_remote_only => blk: {
            // Assets: remotes only (new remote + existing remotes)
            var remote_count: usize = 0;
            if (game) |g| {
                for (g.corp_servers.items, 0..) |_, si| {
                    if (si >= 3) remote_count += 1;
                }
            }
            const choices = try allocator.alloc(state.PromptChoice, 1 + remote_count);
            choices[0] = stringChoice("New remote");
            if (game) |g| {
                var idx: usize = 1;
                var remote_num: usize = 1;
                for (g.corp_servers.items, 0..) |_, si| {
                    if (si >= 3) {
                        choices[idx] = stringChoice(try std.fmt.allocPrint(allocator, "Server {d}", .{remote_num}));
                        idx += 1;
                        remote_num += 1;
                    }
                }
            }
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
    servers: []const MutableServer,
) ![]const state.PromptChoice {
    const names: []const []const u8 = switch (kind) {
        .any_runnable => try runnableServers(allocator, servers),
        .hq_and_rnd_only => try allocator.dupe([]const u8, &.{ "HQ", "R&D" }),
        .central_only => try allocator.dupe([]const u8, &.{ "HQ", "R&D", "Archives" }),
        .archives_only => try allocator.dupe([]const u8, &.{"Archives"}),
        .hq_only => try allocator.dupe([]const u8, &.{"HQ"}),
        .rd_only => try allocator.dupe([]const u8, &.{"R&D"}),
    };
    const choices = try allocator.alloc(state.PromptChoice, names.len);
    for (names, 0..) |name, idx| {
        choices[idx] = stringChoice(name);
    }
    return choices;
}

fn trackMadeRun(generated: *Game, run_server: []const []const u8) void {
    if (run_server.len == 0) return;
    if (std.mem.eql(u8, run_server[0], "hq")) {
        generated.turn_events.made_run_on_hq = true;
    } else if (std.mem.eql(u8, run_server[0], "rnd")) {
        generated.turn_events.made_run_on_rnd = true;
    } else if (std.mem.eql(u8, run_server[0], "archives")) {
        generated.turn_events.made_run_on_archives = true;
    }
}

fn centralNotRunThisTurnChoices(
    allocator: std.mem.Allocator,
    turn_events: state.TurnEvents,
) ![]const state.PromptChoice {
    var count: usize = 0;
    if (!turn_events.made_run_on_hq) count += 1;
    if (!turn_events.made_run_on_rnd) count += 1;
    if (!turn_events.made_run_on_archives) count += 1;
    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    if (!turn_events.made_run_on_hq) {
        choices[next] = stringChoice("HQ");
        next += 1;
    }
    if (!turn_events.made_run_on_rnd) {
        choices[next] = stringChoice("R&D");
        next += 1;
    }
    if (!turn_events.made_run_on_archives) {
        choices[next] = stringChoice("Archives");
        next += 1;
    }
    return choices;
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
    else if (std.mem.startsWith(u8, choice_text, "Server "))
        (std.fmt.parseInt(usize, choice_text["Server ".len..], 10) catch return error.UnsupportedChoice) + 2
    else
        return error.UnsupportedChoice;

    var installed = card;
    installed.installed_this_turn = true;
    if (corpIdentityInstallsAgendasFaceup(game)) {
        const installed_type = installed.card_type orelse "";
        if (std.mem.eql(u8, installed_type, "Agenda")) {
            installed.seen = true;
        }
    }

    const allocator = game.backing_allocator;
    if (target_index) |server_index| {
        if (server_index >= game.corp_servers.items.len) return error.UnknownServer;
        var server = &game.corp_servers.items[server_index];
        if (installs_in_ice) {
            try server.ices.append(allocator, installed);
        } else {
            try server.content.append(allocator, installed);
        }
        return;
    }

    var server = MutableServer{
        .name = try std.fmt.allocPrint(game.arena.allocator(), "remote{}", .{game.next_remote_number}),
    };
    game.next_remote_number += 1;
    if (installs_in_ice) {
        try server.ices.append(allocator, installed);
    } else {
        try server.content.append(allocator, installed);
    }
    try game.corp_servers.append(allocator, server);
}

/// Install a corp card from hand to a server, removing it from hand.
fn installCorpCardFromHand(game: *Game, card_index: u8, server_choice: []const u8) !void {
    if (card_index >= game.corp_hand.items.len) return error.InvalidCardIndex;
    const card = game.corp_hand.orderedRemove(card_index);
    try installCard(game, card, server_choice);
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
    servers: []const MutableServer,
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
    slot: MutableServer,
};

fn findServerByRunPath(
    servers: []const MutableServer,
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
    servers: []const MutableServer,
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
    servers: []const MutableServer,
    display_name: []const u8,
) !usize {
    if (std.mem.eql(u8, display_name, "HQ")) return findServerIndexByName(servers, "hq");
    if (std.mem.eql(u8, display_name, "R&D")) return findServerIndexByName(servers, "rnd");
    if (std.mem.eql(u8, display_name, "Archives")) return findServerIndexByName(servers, "archives");
    if (std.mem.startsWith(u8, display_name, "Server ")) {
        const suffix = display_name["Server ".len..];
        for (servers, 0..) |server, idx| {
            if (!std.mem.startsWith(u8, server.name, "remote")) continue;
            if (std.mem.eql(u8, server.name["remote".len..], suffix)) return idx;
        }
        return error.UnknownServer;
    }
    return error.UnsupportedServer;
}

fn isCentralRunServer(run_server: []const []const u8) bool {
    if (run_server.len == 0) return false;
    return std.mem.eql(u8, run_server[0], "hq") or
        std.mem.eql(u8, run_server[0], "rnd") or
        std.mem.eql(u8, run_server[0], "archives");
}

fn otherSide(side: state.Side) state.Side {
    return switch (side) {
        .corp => .runner,
        .runner => .corp,
    };
}

fn threatLevel(g: *const Game) u8 {
    return g.corp_agenda_point + g.runner_agenda_point;
}

fn corpIdentityInstallsAgendasFaceup(g: *const Game) bool {
    for (g.corp_identity.static_abilities) |sa| {
        if (sa.kind == .faceup_agenda_install) return true;
    }
    return false;
}

fn currentPendingAccessedServerCard(g: *Game) ?*state.CardInstance {
    const pending = g.pending_access orelse return null;
    if (pending.zone != .corp_server_content) return null;
    if (pending.server_index >= g.corp_servers.items.len) return null;
    const server = &g.corp_servers.items[pending.server_index];
    if (pending.card_index >= server.content.items.len) return null;
    return &server.content.items[pending.card_index];
}

fn showTopDownInstallChoices(g: *Game, card: ?state.CardInstance, installs_done: u8, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
    const allocator = g.arena.allocator();
    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
    defer choices_list.deinit(allocator);
    for (g.corp_hand.items, 0..) |c, idx| {
        const ct = c.card_type orelse continue;
        if (std.mem.eql(u8, ct, "Operation")) continue; // Can't install operations
        try choices_list.append(allocator, .{
            .kind = .card,
            .text = try std.fmt.allocPrint(allocator, "{s}", .{c.title}),
            .card = .{ .title = c.title, .code = c.code, .side = .corp, .index = @intCast(idx) },
        });
    }
    try choices_list.append(allocator, stringChoice("Done"));
    g.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "top-down-card"),
        .choices = try choices_list.toOwnedSlice(allocator),
        .source_card = card,
        .min_choices = installs_done,
        .on_choice = on_choice,
    };
    g.decision_side = .corp;
    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
}

fn beginPeerReviewInstallPrompt(g: *Game, card: state.CardInstance, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
    const allocator = g.arena.allocator();
    g.corp_credit += 7;
    g.systemMsg(.corp, 35055, "Corp uses Peer Review to gain 7 [credits].", .{});
    var installable: std.ArrayList(state.PromptChoice) = .empty;
    defer installable.deinit(allocator);
    for (g.corp_hand.items, 0..) |c, idx| {
        const ct = c.card_type orelse continue;
        if (std.mem.eql(u8, ct, "ICE") or std.mem.eql(u8, ct, "Operation")) continue;
        try installable.append(allocator, .{
            .kind = .card,
            .text = try std.fmt.allocPrint(allocator, "{s}", .{c.title}),
            .card = .{ .title = c.title, .code = c.code, .side = .corp, .index = @intCast(idx) },
        });
    }
    if (installable.items.len == 0) {
        g.corp_prompt_state = null;
        g.decision_side = .corp;
        g.legal_actions = try corpOpeningActionsForState(allocator, g);
        return;
    }
    g.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "peer-review-install"),
        .choices = try installable.toOwnedSlice(allocator),
        .source_card = card,
        .on_choice = on_choice,
    };
    g.decision_side = .corp;
    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
}

fn showKpiChoices(g: *Game, card: ?state.CardInstance, choices_made: u8, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
    const allocator = g.arena.allocator();
    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
    defer choices_list.deinit(allocator);
    try choices_list.append(allocator, stringChoice("Gain 2 [Credits]"));
    // Only show "Install ice" if there's ice in hand
    for (g.corp_hand.items) |c| {
        const ct = c.card_type orelse continue;
        if (std.mem.eql(u8, ct, "ICE")) {
            try choices_list.append(allocator, stringChoice("Install 1 piece of ice from HQ"));
            break;
        }
    }
    // Only show "Place advancement" if there are advanceable cards
    if ((try installedCardChoices(allocator, g.corp_servers.items)).len > 0) {
        try choices_list.append(allocator, stringChoice("Place 1 advancement counter"));
    }
    try choices_list.append(allocator, stringChoice("Draw 1 card and shuffle 1 card from HQ into R&D"));
    if (choices_made > 0) {
        try choices_list.append(allocator, stringChoice("Done"));
    }
    g.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "kpi-choose"),
        .choices = try choices_list.toOwnedSlice(allocator),
        .source_card = card,
        .min_choices = choices_made,
        .on_choice = on_choice,
    };
    g.decision_side = .corp;
    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
}

fn sideName(side: state.Side) []const u8 {
    return switch (side) {
        .corp => "Corp",
        .runner => "Runner",
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
        system_gateway_beginner,
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

    try applyActionByIndex(&generated, 0); // start_turn (auto-completes phase 12)
    try std.testing.expectEqual(state.Side.corp, currentPlayer(&generated));
    try std.testing.expectEqual(@as(usize, 9), legalActionCount(&generated));

    try applyActionByIndex(&generated, 0);
    try std.testing.expectEqual(@as(u16, 9), generated.corp_credit);
    try std.testing.expectEqual(@as(u8, 2), generated.corp_click);
    try std.testing.expectEqual(@as(usize, 7), legalActionCount(&generated));

    var install_generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        1,
    );
    defer install_generated.deinit();

    try applyActionByIndex(&install_generated, 0); // Keep corp
    try applyActionByIndex(&install_generated, 0); // Keep runner
    try corpStartTurnFull(&install_generated);
    try applyActionByIndex(&install_generated, 1); // install card
    try std.testing.expectEqual(@as(usize, 4), legalActionCount(&install_generated));

    try applyActionByIndex(&install_generated, 0);
    try std.testing.expectEqual(@as(u8, 2), install_generated.corp_click);
    try std.testing.expectEqual(@as(usize, 8), legalActionCount(&install_generated));
    try expectInstalledIceTitle(install_generated.corp_servers.items, "Brân 1.0");
}

test "intermediate matchup snapshot initializes" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_intermediate,
        1,
    );
    defer generated.deinit();

    try std.testing.expectEqualStrings("system-gateway", generated.format);
    try std.testing.expectEqual(@as(u8, 7), generated.corp_agenda_point_req);
    try std.testing.expectEqual(@as(u8, 7), generated.runner_agenda_point_req);
    try std.testing.expectEqual(@as(usize, 39), generated.corp_deck.items.len);
    try std.testing.expectEqual(@as(usize, 35), generated.runner_deck.items.len);
    try std.testing.expectEqual(state.Side.corp, currentPlayer(&generated));
}

test "runner telework contract install and hosted-credit ability" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        7,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);
    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    const install_action = findActionByTitle(generated.legal_actions, .play_from_hand, "Telework Contract") orelse return error.MissingAction;
    try applyAction(&generated, install_action);

    try std.testing.expectEqual(@as(usize, 1), generated.runner_rig_resources.items.len);
    try std.testing.expectEqualStrings("Telework Contract", generated.runner_rig_resources.items[0].title);
    try std.testing.expectEqual(@as(u16, 9), generated.runner_rig_resources.items[0].credit_counter);
    try std.testing.expectEqual(@as(u16, 4), generated.runner_credit);
    try std.testing.expectEqual(@as(u8, 3), generated.runner_click);

    const use_action = findInstalledAbilityAction(generated.legal_actions, "Telework Contract") orelse return error.MissingAction;
    try applyAction(&generated, use_action);

    try std.testing.expectEqual(@as(u16, 7), generated.runner_credit);
    try std.testing.expectEqual(@as(u8, 2), generated.runner_click);
    try std.testing.expectEqual(@as(u16, 6), generated.runner_rig_resources.items[0].credit_counter);
    try std.testing.expect(findInstalledAbilityAction(generated.legal_actions, "Telework Contract") == null);
}

test "send a message steal triggers corp rez choice when unrezzed ice exists" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        2,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    const ice_install = findFirstCorpIceInstallPlay(generated.legal_actions, generated.corp_hand.items) orelse return error.MissingAction;
    const ice_title = ice_install.card_title orelse return error.MissingAction;
    try applyAction(&generated, ice_install);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_install_destination,
        .choice = stringChoice("New remote"),
    });

    try applyAction(&generated, findActionByTitle(generated.legal_actions, .play_from_hand, "Send a Message") orelse return error.MissingAction);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_install_destination,
        .choice = stringChoice("New remote"),
    });
    generated.corp_credit = 20;
    try endTurnAndDiscard(&generated, .corp);

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    try startRun(&generated, "Server 2");
    try applyAction(&generated, .{ .kind = .@"continue", .side = .corp, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .runner, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .corp, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .runner, .prompt_type = "run" });
    // After movement completes, runner gets access prompt directly
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Steal") orelse return error.MissingAction);

    const rez_choice = findPromptChoiceAction(generated.legal_actions, .corp, ice_title) orelse return error.MissingAction;
    try applyAction(&generated, rez_choice);

    try std.testing.expect(iceIsRezzed(generated.corp_servers.items, ice_title));
}

test "run ice windows can prompt corp rez on approached ice when enabled" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        2,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    const ice_install = findFirstCorpIceInstallPlay(generated.legal_actions, generated.corp_hand.items) orelse return error.MissingAction;
    const ice_title = ice_install.card_title orelse return error.MissingAction;
    try applyAction(&generated, ice_install);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_install_destination,
        .choice = stringChoice("New remote"),
    });
    generated.corp_credit = 20;
    while (findBasicAbilityAction(generated.legal_actions, .corp, .gain_credit)) |gain_action| {
        try applyAction(&generated, gain_action);
    }
    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    try startRun(&generated, "Server 1");

    var found_rez_action = false;
    var guard: usize = 0;
    while (guard < 12 and generated.run != null) : (guard += 1) {
        if (generated.decision_side == .corp) {
            if (findActionByKind(generated.legal_actions, .rez_ice, .corp)) |rez_action| {
                try applyAction(&generated, rez_action);
                found_rez_action = true;
                break;
            }
        }
        const continue_action = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse return error.MissingAction;
        try applyAction(&generated, continue_action);
    }
    try std.testing.expect(found_rez_action);

    try std.testing.expect(iceIsRezzed(generated.corp_servers.items, ice_title));
}

test "corp installed credit ability on regolith pays out and trashes when empty" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        11,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    var regolith = try makeGameCard(&generated, try lookupRequiredCardSpec(30071));
    regolith.credit_counter = regolith.initial_credit_counters;
    regolith.rezzed = true;
    try installCard(&generated, regolith, "New remote");

    generated.corp_click = 6;
    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated);
    const credit_before = generated.corp_credit;

    var use_count: usize = 0;
    while (use_count < 5) : (use_count += 1) {
        const action = findInstalledAbilityAction(generated.legal_actions, "Regolith Mining License") orelse return error.MissingAction;
        try applyAction(&generated, action);
    }

    try std.testing.expectEqual(@as(u16, credit_before + 15), generated.corp_credit);
    try std.testing.expect(findInstalledAbilityAction(generated.legal_actions, "Regolith Mining License") == null);

    var found_discard = false;
    for (generated.corp_discard.items) |card| {
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
        system_gateway_beginner,
        12,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    var offworld = try makeGameCard(&generated, try lookupRequiredCardSpec(30067));
    offworld.advancement_counter = 4;
    try installCard(&generated, offworld, "New remote");

    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated);

    const credit_before = generated.corp_credit;
    const score_action = findBasicAbilityAction(generated.legal_actions, .corp, .score_agenda) orelse return error.MissingAction;
    try applyAction(&generated, score_action);

    try std.testing.expectEqual(@as(u8, 2), generated.corp_agenda_point);
    try std.testing.expectEqual(@as(u16, credit_before + 7), generated.corp_credit);
}

test "urtica cipher access applies net damage when corp can pay" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        13,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    var urtica = try makeGameCard(&generated, try lookupRequiredCardSpec(30045));
    urtica.advancement_counter = 2;
    try installCard(&generated, urtica, "New remote");
    generated.corp_credit = 20;

    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const hand_before = generated.runner_hand.items.len;
    const discard_before = generated.runner_discard.items.len;
    const corp_credit_before = generated.corp_credit;

    try startRun(&generated, "Server 1");
    var guard: usize = 0;
    while (guard < 32 and generated.run != null and !generated.game_over) : (guard += 1) {
        // Handle corp net-damage-on-access prompt (shown after corp continues in success phase)
        if (generated.decision_side == .corp) {
            if (generated.corp_prompt_state) |ps| {
                if (std.mem.eql(u8, ps.prompt_type, "net-damage-on-access")) {
                    // Find any pay action starting with "Pay"
                    var found_pay: ?state.LegalAction = null;
                    for (generated.legal_actions) |action| {
                        if (action.kind == .prompt_choice and action.side == .corp) {
                            if (action.choice) |choice| {
                                if (choice.text) |text| {
                                    if (std.mem.startsWith(u8, text, "Pay ")) {
                                        found_pay = action;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                    if (found_pay) |pay_action| {
                        try applyAction(&generated, pay_action);
                        continue;
                    }
                }
            }
        }
        // Handle runner access choices (trash / no action)
        if (findPromptChoiceAction(generated.legal_actions, .runner, "No action")) |no_action| {
            try applyAction(&generated, no_action);
            continue;
        }
        const continue_action = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    const expected_damage: usize = @min(hand_before, @as(usize, 4));
    try std.testing.expectEqual(hand_before - expected_damage, generated.runner_hand.items.len);
    try std.testing.expectEqual(discard_before + expected_damage, generated.runner_discard.items.len);
    try std.testing.expectEqual(corp_credit_before - 2, generated.corp_credit);
}

fn expectInstalledIceTitle(servers: []const MutableServer, title: []const u8) !void {
    var match_count: usize = 0;
    for (servers) |server| {
        for (server.ices.items) |ice| {
            if (std.mem.eql(u8, ice.title, title)) match_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), match_count);
}

fn endTurnAndDiscard(generated: *Game, side: state.Side) !void {
    // Spend remaining clicks before ending turn (unit test convenience)
    switch (side) {
        .corp => {
            while (generated.corp_click > 0) {
                generated.corp_click -= 1;
                generated.corp_credit += 1;
            }
        },
        .runner => {
            while (generated.runner_click > 0) {
                generated.runner_click -= 1;
                generated.runner_credit += 1;
            }
        },
    }
    try applyAction(generated, .{ .kind = .end_turn, .side = side });
    // Handle discard prompts
    const player_ps = switch (side) {
        .corp => generated.corp_prompt_state,
        .runner => generated.runner_prompt_state,
    };
    if (player_ps) |ps| {
        if (std.mem.eql(u8, ps.prompt_type, prompt_discard)) {
            while (true) {
                const pp = switch (side) {
                    .corp => generated.corp_prompt_state,
                    .runner => generated.runner_prompt_state,
                };
                if (pp == null) break;
                if (!std.mem.eql(u8, pp.?.prompt_type, prompt_discard)) break;
                if (pp.?.choices.len == 0) break;
                // Discard first available card
                const choice = pp.?.choices[0];
                const title = choice.card.?.title orelse break;
                try applyAction(generated, .{ .kind = .prompt_choice, .side = side, .prompt_type = prompt_discard, .choice = .{ .kind = .card, .text = title } });
            }
        }
    }
}

const prompt_mu_overflow = "mu-overflow";

fn beginMuOverflowPrompt(generated: *Game) !bool {
    return beginMuOverflowPromptWithExtra(generated, 0);
}

fn beginMuOverflowPromptWithExtra(generated: *Game, extra_mu: u8) !bool {
    refreshDerivedStates(generated);
    const mem = generated.runner_memory orelse return false;
    if (mem.used + extra_mu <= mem.base) return false;

    const allocator = generated.arena.allocator();
    // List installed programs as trash choices (trojans are on ICE, not in rig)
    var choices_list: std.ArrayList(state.PromptChoice) = .empty;
    defer choices_list.deinit(allocator);
    for (generated.runner_rig_program.items, 0..) |card, idx| {
        const text = try std.fmt.allocPrint(allocator, "p|{d}", .{idx});
        try choices_list.append(allocator, .{ .kind = .string, .text = text, .card = .{ .title = card.title } });
    }
    if (choices_list.items.len == 0) return false;

    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_mu_overflow),
        .choices = try choices_list.toOwnedSlice(allocator),
        .source_card = null,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
    return true;
}

fn applyMuOverflowChoice(generated: *Game, choice_text: []const u8) !void {
    var pieces = std.mem.splitScalar(u8, choice_text, '|');
    _ = pieces.next(); // "p"
    const index_text = pieces.next() orelse return error.UnsupportedChoice;
    const index = try std.fmt.parseInt(usize, index_text, 10);
    if (index >= generated.runner_rig_program.items.len) return error.UnsupportedChoice;

    const trashed = generated.runner_rig_program.orderedRemove(index);
    try appendDiscardCard(generated, .runner, trashed);
    if (generated.runner_memory) |*mem| {
        const mu = trashed.runner_install.mu_cost;
        if (mem.used >= mu) mem.used -= mu else mem.used = 0;
        mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
    }

    // Check if still over limit (include pending program's MU cost)
    const pending_mu: u8 = if (generated.pending_install) |p| p.card.runner_install.mu_cost else 0;
    if (try beginMuOverflowPromptWithExtra(generated, pending_mu)) return;

    // MU resolved — complete the pending program install if any
    if (generated.pending_install) |pending| {
        const pi_card = pending.card;
        const pi_index = pending.card_index;
        const pi_cost = pending.runner_install_cost;
        generated.runner_prompt_state = null;
        if (pending.runner_spend_click) {
            try spendClicks(generated, .runner, 1);
        }
        try completeRunnerInstall(generated, pi_index, pi_card, pi_cost, pending.runner_spend_click);
        if (try resumePendingEffects(generated)) return;
        return;
    }

    generated.runner_prompt_state = null;
    const allocator = generated.arena.allocator();
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
}

pub fn corpStartTurnFull(generated: *Game) !void {
    try applyAction(generated, .{ .kind = .start_turn, .side = .corp });
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
        if (action.side != side) continue;
        if (basic_action == .advance_installed and action.kind == .advance) return action;
        if (basic_action == .score_agenda and action.kind == .score) return action;
        if (action.kind == .use_ability and action.basic_action != null and action.basic_action.? == basic_action) return action;
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
        if (choice.text == null) continue;
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

fn startRun(generated: *Game, server: []const u8) !void {
    try applyAction(generated, findRunAction(generated.legal_actions, server) orelse return error.MissingAction);
}

fn findRemoteWithIce(servers: []const MutableServer) ?[]const u8 {
    for (servers) |server| {
        if (!std.mem.startsWith(u8, server.name, "remote")) continue;
        if (server.ices.items.len == 0) continue;
        return server.name;
    }
    return null;
}

fn iceIsRezzed(servers: []const MutableServer, title: []const u8) bool {
    for (servers) |server| {
        for (server.ices.items) |ice| {
            if (std.mem.eql(u8, ice.title, title) and ice.rezzed) return true;
        }
    }
    return false;
}

test "flatline terminal condition when brain damage equals hand size" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        100,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);
    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    // Set up flatline condition: brain damage >= hand size
    generated.runner_brain_damage = 5;
    const hand_size = generated.runner_hand.items.len;
    generated.runner_brain_damage = @intCast(hand_size);

    updateTerminalState(&generated);
    try std.testing.expect(generated.game_over);
    try std.testing.expectEqual(state.Side.corp, generated.winner);
}

test "jack out is available after passing ice" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        101,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    // Install unrezzed ICE on a remote
    const ice_install = findFirstCorpIceInstallPlay(generated.legal_actions, generated.corp_hand.items) orelse return error.MissingAction;
    try applyAction(&generated, ice_install);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_install_destination,
        .choice = stringChoice("New remote"),
    });

    // End turn (ice remains unrezzed)
    try endTurnAndDiscard(&generated, .corp);

    // Runner starts turn and runs the remote
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    try startRun(&generated, "Server 1");

    // Progress: initiation -> approach-ice -> movement (no rez, no encounter since ice is unrezzed)
    var guard: usize = 0;
    var found_jack_out = false;
    while (guard < 30 and generated.run != null) : (guard += 1) {
        // Debug: print current phase
        // std.debug.print("Phase: {s}, Side: {any}, Actions: {d}\n", .{
        //     generated.run.?.phase,
        //     generated.decision_side,
        //     generated.legal_actions.len
        // });

        // Check for jack_out action when it's runner's turn
        if (generated.decision_side == .runner) {
            for (generated.legal_actions) |action| {
                if (action.kind == .jack_out) {
                    found_jack_out = true;
                    break;
                }
            }
            if (found_jack_out) break;
        }

        // Continue through the run
        const continue_action = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    try std.testing.expect(found_jack_out);
}

test "ICE subroutine end the run fires" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        102,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    // Install Tithe (1 net damage, ETR) on a remote
    var tithe = try makeGameCard(&generated, try lookupRequiredCardSpec(30073));
    tithe.rezzed = true;
    try installCard(&generated, tithe, "New remote");

    generated.corp_credit = 20;
    try endTurnAndDiscard(&generated, .corp);

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const hand_before = generated.runner_hand.items.len;

    try startRun(&generated, "Server 1");

    // Progress through the run - ICE should fire and ETR
    var guard: usize = 0;
    while (guard < 20 and generated.run != null) : (guard += 1) {
        const continue_action = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    // Run should have ended (ETR fired)
    try std.testing.expect(generated.run == null);
    // Net damage should have been dealt (1 card from Tithe's first subroutine)
    try std.testing.expectEqual(hand_before - 1, generated.runner_hand.items.len);
}

test "ICE net damage subroutine applies damage" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        103,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    // Install Karunā (2 net damage, 2 net damage) on a remote
    var karuna = try makeGameCard(&generated, try lookupRequiredCardSpec(30047));
    karuna.rezzed = true;
    try installCard(&generated, karuna, "New remote");

    generated.corp_credit = 20;
    try endTurnAndDiscard(&generated, .corp);

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const hand_before = generated.runner_hand.items.len;

    try startRun(&generated, "Server 1");

    // Progress through the run, handling jack-out prompts
    var guard: usize = 0;
    while (guard < 30 and generated.run != null) : (guard += 1) {
        // Handle jack-out prompt from Karunā sub1 - choose to continue
        if (generated.runner_prompt_state) |ps| {
            if (std.mem.eql(u8, ps.prompt_type, "jack-out")) {
                try applyAction(&generated, .{
                    .kind = .prompt_choice,
                    .side = .runner,
                    .prompt_type = "jack-out",
                    .choice = stringChoice("Continue"),
                });
                continue;
            }
        }
        const continue_action = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    // Karunā should have dealt 4 net damage (2 + 2)
    try std.testing.expectEqual(@as(usize, @max(0, hand_before - 4)), generated.runner_hand.items.len);
}

test "runner loses credits subroutine" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        104,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    // Install Whitespace (sub1: runner loses 3 credits, sub2: ETR if runner ≤ 6 credits)
    var whitespace = try makeGameCard(&generated, try lookupRequiredCardSpec(30074));
    whitespace.rezzed = true;
    try installCard(&generated, whitespace, "New remote");

    generated.corp_credit = 20;
    // Give runner enough credits that sub2 won't end the run
    generated.runner_credit = 20;
    try endTurnAndDiscard(&generated, .corp);

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const credit_before = generated.runner_credit;

    try startRun(&generated, "Server 1");

    // Progress through the run
    var guard: usize = 0;
    while (guard < 20 and generated.run != null) : (guard += 1) {
        const continue_action = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    // Whitespace sub1 should have reduced runner credits by 3
    // Sub2 should NOT end the run because runner has > 6 credits
    try std.testing.expectEqual(@as(u16, credit_before - 3), generated.runner_credit);
}

test "tread lightly run rez cost bonus is applied during corp rez window" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        1,
    );
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    // Install unrezzed ICE on a remote
    const ice_install = findFirstCorpIceInstallPlay(generated.legal_actions, generated.corp_hand.items) orelse return error.MissingAction;
    const ice_title = ice_install.card_title orelse return error.MissingAction;
    try applyAction(&generated, ice_install);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_install_destination,
        .choice = stringChoice("New remote"),
    });

    generated.corp_credit = 20;
    try endTurnAndDiscard(&generated, .corp);

    // Runner plays Tread Lightly which sets rez cost bonus to 3
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    try applyAction(&generated, findActionByTitle(generated.legal_actions, .play_from_hand, "Tread Lightly") orelse return error.MissingAction);

    // Tread Lightly prompts for run target
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Server 1") orelse return error.MissingAction);

    // Verify rez cost bonus is set via floating effect
    try std.testing.expectEqual(@as(i16, 3), sumFloatingEffects(&generated, .rez_cost_bonus));

    // Run through to approach-ice phase
    var guard: usize = 0;
    var found_rez_action = false;
    while (guard < 20 and generated.run != null) : (guard += 1) {
        // Look for rez_ice action
        if (findActionByKind(generated.legal_actions, .rez_ice, .corp)) |rez_action| {
            found_rez_action = true;
            // Corp has 20 credits, should be able to rez regardless of ice cost
            try std.testing.expect(generated.corp_credit >= 4);
            try applyAction(&generated, rez_action);
            break;
        }
        const continue_action = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    try std.testing.expect(found_rez_action);
    // ICE should be rezzed
    try std.testing.expect(iceIsRezzed(generated.corp_servers.items, ice_title));
}

test "sure gamble gains credits without losing extra clicks" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        1,
    );
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);
    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    // Runner starts turn with 4 clicks and 5 credits
    try std.testing.expectEqual(@as(u8, 4), generated.runner_click);
    try std.testing.expectEqual(@as(u16, 5), generated.runner_credit);

    // Play Sure Gamble: costs 5 credits, 1 click, no lose_clicks
    const sg_action = findActionByTitle(generated.legal_actions, .play_from_hand, "Sure Gamble") orelse return error.MissingAction;
    try applyAction(&generated, sg_action);

    // Should have spent only 1 click (not 2 like Creative Commission)
    try std.testing.expectEqual(@as(u8, 3), generated.runner_click);
    // Should have gained 9 credits (spent 5, gained 9, net 4 from starting 5 = 9)
    try std.testing.expectEqual(@as(u16, 9), generated.runner_credit);
}

test "corp gain credit 3 times then turn transitions to runner" {
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        1,
    );
    defer generated.deinit();

    // Mulligan keep/keep
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });

    // Corp start turn
    try corpStartTurnFull(&generated);
    try std.testing.expectEqual(state.Side.corp, generated.decision_side);
    try std.testing.expectEqual(@as(u8, 3), generated.corp_click);

    // Corp gains credit 3 times
    const gc1 = findBasicAbilityAction(generated.legal_actions, .corp, .gain_credit) orelse return error.MissingAction;
    try applyAction(&generated, gc1);
    try std.testing.expectEqual(@as(u8, 2), generated.corp_click);

    const gc2 = findBasicAbilityAction(generated.legal_actions, .corp, .gain_credit) orelse return error.MissingAction;
    try applyAction(&generated, gc2);
    try std.testing.expectEqual(@as(u8, 1), generated.corp_click);

    const gc3 = findBasicAbilityAction(generated.legal_actions, .corp, .gain_credit) orelse return error.MissingAction;
    try applyAction(&generated, gc3);
    try std.testing.expectEqual(@as(u8, 0), generated.corp_click);

    // Corp should have only end_turn action now
    try std.testing.expectEqual(@as(usize, 1), generated.legal_actions.len);
    try std.testing.expectEqual(state.ActionKind.end_turn, generated.legal_actions[0].kind);

    // Apply end turn — corp drew a card at start so hand=6, needs to discard to 5
    try applyAction(&generated, generated.legal_actions[0]);

    // Corp must discard (hand 6 > hand size 5), so decision stays with corp
    try std.testing.expectEqual(state.Side.corp, generated.decision_side);
    try std.testing.expectEqual(state.ActionKind.prompt_choice, generated.legal_actions[0].kind);

    // Discard a card
    try applyAction(&generated, generated.legal_actions[0]);

    // Now should transition to runner start_turn
    try std.testing.expectEqual(state.Side.runner, generated.decision_side);
    try std.testing.expectEqual(@as(usize, 1), generated.legal_actions.len);
    try std.testing.expectEqual(state.ActionKind.start_turn, generated.legal_actions[0].kind);

    // Apply runner start turn
    try applyAction(&generated, generated.legal_actions[0]);

    // Runner should now have multiple actions and be deciding
    try std.testing.expectEqual(state.Side.runner, generated.decision_side);
    try std.testing.expect(generated.legal_actions.len > 1);

    // Verify run actions exist
    try std.testing.expect(findRunAction(generated.legal_actions, "Archives") != null);
    try std.testing.expect(findRunAction(generated.legal_actions, "HQ") != null);
    try std.testing.expect(findRunAction(generated.legal_actions, "R&D") != null);
}

test "access remote card only once then run ends" {
    // Seed 1: corp hand has Regolith Mining License
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        system_gateway_beginner,
        1,
    );
    defer generated.deinit();

    // Keep/keep
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });

    // Corp: start turn, install Regolith in remote
    try corpStartTurnFull(&generated);
    try applyAction(&generated, findActionByTitle(generated.legal_actions, .play_from_hand, "Regolith Mining License") orelse return error.MissingAction);
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "install-destination", .choice = stringChoice("New remote") });
    try endTurnAndDiscard(&generated, .corp);

    // Runner: start turn, run the remote
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    try startRun(&generated, "Server 1");

    // Continue through the run (no ICE)
    var guard: usize = 0;
    while (guard < 10 and generated.run != null) : (guard += 1) {
        const cont = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse break;
        try applyAction(&generated, cont);
    }

    // Should get an access prompt for Regolith
    try std.testing.expect(generated.runner_prompt_state != null);
    try std.testing.expectEqualStrings("access-choice", generated.runner_prompt_state.?.prompt_type);
    try std.testing.expectEqualStrings("Regolith Mining License", generated.runner_prompt_state.?.source_card.?.title);

    // Find and apply the trash action
    const trash_action = findPromptChoiceAction(generated.legal_actions, .runner, "No action") orelse return error.MissingAction;
    try applyAction(&generated, trash_action);

    // Run should be over — NOT offered the same card again
    try std.testing.expect(generated.run == null);
    try std.testing.expect(generated.runner_prompt_state == null);
    try std.testing.expectEqual(state.Side.runner, generated.decision_side);
    try std.testing.expect(generated.legal_actions.len > 1);

    // Regolith should still be installed (we picked No action, not trash)
    try std.testing.expectEqual(@as(usize, 1), generated.corp_servers.items[3].content.items.len);

    // Run the remote again to test trash
    try startRun(&generated, "Server 1");
    var guard2: usize = 0;
    while (guard2 < 10 and generated.run != null) : (guard2 += 1) {
        const cont2 = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse break;
        try applyAction(&generated, cont2);
    }

    // Access prompt again — this time trash it
    try std.testing.expect(generated.runner_prompt_state != null);
    try std.testing.expectEqualStrings("access-choice", generated.runner_prompt_state.?.prompt_type);
    // Regolith has trash cost 3, runner starts with 5cr - should be able to afford
    const pay_trash = findPromptChoiceAction(generated.legal_actions, .runner, "Pay 3 [Credits] to trash") orelse return error.MissingAction;
    const credit_before = generated.runner_credit;
    try applyAction(&generated, pay_trash);

    // Card should be trashed, credits spent, run over — NOT offered again
    try std.testing.expectEqual(credit_before - 3, generated.runner_credit);
    try std.testing.expect(generated.run == null);
    try std.testing.expect(generated.runner_prompt_state == null);
    try std.testing.expectEqual(state.Side.runner, generated.decision_side);
}

test "Loup trash on HQ access completes run and does not repeat access" {
    // GNK matchup: Loup is the runner. Loup's ability: first trash each turn gains 1cr + draw 1.
    // Spin Doctor (code 30053) has trash cost 2.
    var generated = try createInitialSnapshot(
        std.testing.allocator,
        gnk_nbn_vs_loup,
        5,
    );
    defer generated.deinit();

    // Keep/keep
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });

    // Corp: start turn, spend all clicks on credits
    try corpStartTurnFull(&generated);
    for (0..3) |_| {
        const gc = findBasicAbilityAction(generated.legal_actions, .corp, .gain_credit) orelse break;
        try applyAction(&generated, gc);
    }

    // Force a Spin Doctor into corp hand for deterministic test
    generated.corp_hand.clearRetainingCapacity();
    try generated.corp_hand.append(generated.backing_allocator, .{
        .title = "Spin Doctor",
        .side = .corp,
        .code = 30053,
        .card_type = "Asset",
    });

    try endTurnAndDiscard(&generated, .corp);

    // Runner: start turn, run HQ
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    try startRun(&generated, "HQ");

    // Continue through run (no ICE on HQ)
    var guard: usize = 0;
    while (guard < 10 and generated.run != null) : (guard += 1) {
        const cont = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse break;
        try applyAction(&generated, cont);
    }

    // With 1 card in hand, may go directly to access-choice or show hq-access first
    if (generated.runner_prompt_state) |ps| {
        if (std.mem.eql(u8, ps.prompt_type, "hq-access")) {
            try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Card from hand") orelse return error.MissingAction);
        }
    }

    // Access-choice prompt for Spin Doctor
    try std.testing.expect(generated.runner_prompt_state != null);
    try std.testing.expectEqualStrings("access-choice", generated.runner_prompt_state.?.prompt_type);
    try std.testing.expectEqualStrings("Spin Doctor", generated.runner_prompt_state.?.source_card.?.title);

    // Trash it
    const credit_before = generated.runner_credit;
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Pay 2 [Credits] to trash") orelse return error.MissingAction);

    // Loup trigger: +1cr +1 draw. Net credit change: -2 + 1 = -1
    try std.testing.expectEqual(credit_before - 1, generated.runner_credit);

    // Run must be over — NOT showing the same access prompt again
    try std.testing.expect(generated.run == null);
    try std.testing.expect(generated.runner_prompt_state == null);
    try std.testing.expectEqual(state.Side.runner, generated.decision_side);
    try std.testing.expect(generated.legal_actions.len > 1);
}

test "Bling free install hosts and can play hosted card" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_runner, 1);
    defer generated.deinit();

    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);
    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    generated.runner_hand.clearRetainingCapacity();
    generated.runner_deck.clearRetainingCapacity();
    try generated.runner_hand.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35006)));
    try generated.runner_deck.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(30030)));
    generated.runner_credit = 5;
    generated.runner_click = 4;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), &generated);

    const bling = generated.runner_hand.items[0];
    try completeRunnerInstall(&generated, 0, bling, 0, false);

    try std.testing.expectEqual(@as(usize, 1), generated.runner_rig_hardware.items.len);
    try std.testing.expectEqual(@as(usize, 1), generated.runner_rig_hardware.items[0].hosted.len);
    try std.testing.expectEqualStrings("Sure Gamble", generated.runner_rig_hardware.items[0].hosted[0].title);

    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), &generated);
    try applyAction(&generated, findInstalledAbilityAction(generated.legal_actions, "Bling") orelse return error.MissingAction);
    try std.testing.expectEqualStrings("runner-hosted-card", generated.runner_prompt_state.?.prompt_type);
    const hosted_choice = for (generated.legal_actions) |action| {
        if (action.kind == .prompt_choice and action.choice != null and action.choice.?.text != null and !std.mem.eql(u8, action.choice.?.text.?, "No action")) {
            break action;
        }
    } else return error.MissingAction;
    try applyAction(&generated, hosted_choice);

    try std.testing.expectEqual(@as(usize, 0), generated.runner_rig_hardware.items[0].hosted.len);
    try std.testing.expectEqual(@as(u16, 9), generated.runner_credit);
}

test "Bling trashes hosted cards at runner end turn" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_runner, 1);
    defer generated.deinit();

    var bling = try makeGameCard(&generated, try lookupRequiredCardSpec(35006));
    try appendHostedCard(generated.arena.allocator(), &bling, try makeGameCard(&generated, try lookupRequiredCardSpec(35014)));
    try generated.runner_rig_hardware.append(generated.backing_allocator, bling);

    generated.active_player = .runner;
    generated.decision_side = .runner;
    generated.end_turn = false;
    try finishEndTurn(&generated, .runner);

    try std.testing.expectEqual(@as(usize, 0), generated.runner_rig_hardware.items[0].hosted.len);
    try std.testing.expectEqual(@as(usize, 1), generated.runner_discard.items.len);
    try std.testing.expectEqualStrings("Clean Getaway", generated.runner_discard.items[0].title);
}

test "Detente returns hosted cards to HQ and opens a random access" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_runner2, 1);
    defer generated.deinit();

    var detente = try makeGameCard(&generated, try lookupRequiredCardSpec(35018));
    try appendHostedCard(generated.arena.allocator(), &detente, try makeGameCard(&generated, try lookupRequiredCardSpec(30040)));
    try appendHostedCard(generated.arena.allocator(), &detente, try makeGameCard(&generated, try lookupRequiredCardSpec(30046)));
    try generated.runner_rig_hardware.append(generated.backing_allocator, detente);

    generated.active_player = .runner;
    generated.decision_side = .runner;
    generated.end_turn = false;
    generated.runner_click = 4;
    generated.corp_hand.clearRetainingCapacity();
    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), &generated);

    try applyAction(&generated, findInstalledAbilityAction(generated.legal_actions, "Detente") orelse return error.MissingAction);

    try std.testing.expectEqual(@as(u8, 3), generated.runner_click);
    try std.testing.expectEqual(@as(usize, 0), generated.runner_rig_hardware.items[0].hosted.len);
    try std.testing.expectEqual(@as(usize, 2), generated.corp_hand.items.len);
    try std.testing.expect(generated.runner_prompt_state != null);
    try std.testing.expectEqualStrings("access-choice", generated.runner_prompt_state.?.prompt_type);
    try std.testing.expect(generated.runner_prompt_state.?.source_card != null);
}

test "Detente ability is available to the corp" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_runner2, 1);
    defer generated.deinit();

    var detente = try makeGameCard(&generated, try lookupRequiredCardSpec(35018));
    try appendHostedCard(generated.arena.allocator(), &detente, try makeGameCard(&generated, try lookupRequiredCardSpec(30040)));
    try appendHostedCard(generated.arena.allocator(), &detente, try makeGameCard(&generated, try lookupRequiredCardSpec(30046)));
    try generated.runner_rig_hardware.append(generated.backing_allocator, detente);

    generated.active_player = .corp;
    generated.decision_side = .corp;
    generated.end_turn = false;
    generated.corp_click = 3;
    generated.corp_hand.clearRetainingCapacity();
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated);

    try applyAction(&generated, findInstalledAbilityAction(generated.legal_actions, "Detente") orelse return error.MissingAction);

    try std.testing.expectEqual(@as(u8, 2), generated.corp_click);
    try std.testing.expect(generated.runner_prompt_state != null);
    try std.testing.expectEqualStrings("access-choice", generated.runner_prompt_state.?.prompt_type);
}

test "Measured Response requires successful runner run last turn" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_weyland, 1);
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    try generated.corp_hand.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35078)));
    generated.corp_agenda_point = 2;
    generated.runner_agenda_point = 2;
    generated.corp_credit = 10;
    generated.runner_successful_run_last_turn = false;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated);
    try std.testing.expect(findActionByTitle(generated.legal_actions, .play_from_hand, "Measured Response") == null);

    generated.runner_successful_run_last_turn = true;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated);
    try std.testing.expect(findActionByTitle(generated.legal_actions, .play_from_hand, "Measured Response") != null);
}

test "Key Performance Indicators draw branch shuffles a card from HQ into R&D" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_weyland, 2);
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    try generated.corp_hand.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35077)));
    try generated.corp_hand.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35056)));
    generated.corp_credit = 10;
    const deck_before = generated.corp_deck.items.len;
    var mitra_before: usize = 0;
    for (generated.corp_hand.items) |card| {
        if (std.mem.eql(u8, card.title, "Mitra Aman")) mitra_before += 1;
    }

    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated);
    try applyAction(&generated, findActionByTitle(generated.legal_actions, .play_from_hand, "Key Performance Indicators") orelse return error.MissingAction);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .corp, "Draw 1 card and shuffle 1 card from HQ into R&D") orelse return error.MissingAction);
    try std.testing.expectEqualStrings("kpi-shuffle", generated.corp_prompt_state.?.prompt_type);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .corp, "Mitra Aman") orelse return error.MissingAction);

    try std.testing.expectEqual(deck_before, generated.corp_deck.items.len);
    var mitra_after: usize = 0;
    for (generated.corp_hand.items) |card| {
        if (std.mem.eql(u8, card.title, "Mitra Aman")) mitra_after += 1;
    }
    try std.testing.expectEqual(mitra_before - 1, mitra_after);
}

test "Scrounge installs from heap and can bottom a program" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_hb, 3);
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);
    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    try generated.runner_hand.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35004)));
    try generated.runner_discard.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35008)));
    try generated.runner_discard.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35009)));
    generated.runner_credit = 10;
    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), &generated);

    try applyAction(&generated, findActionByTitle(generated.legal_actions, .play_from_hand, "Scrounge") orelse return error.MissingAction);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Hantu") orelse return error.MissingAction);
    try std.testing.expectEqualStrings("runner-discard-to-deck", generated.runner_prompt_state.?.prompt_type);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Rising Tide") orelse return error.MissingAction);

    try std.testing.expectEqual(@as(usize, 1), generated.runner_rig_program.items.len);
    try std.testing.expectEqualStrings("Hantu", generated.runner_rig_program.items[0].title);
    try std.testing.expectEqual(@as(usize, 1), generated.runner_discard.items.len);
    try std.testing.expectEqualStrings("Scrounge", generated.runner_discard.items[0].title);
    try std.testing.expectEqualStrings("Rising Tide", generated.runner_deck.items[generated.runner_deck.items.len - 1].title);
}

test "Scrounge cancel still allows bottoming a program" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_hb, 4);
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);
    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    try generated.runner_hand.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35004)));
    try generated.runner_discard.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35008)));
    generated.runner_credit = 10;
    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), &generated);

    try applyAction(&generated, findActionByTitle(generated.legal_actions, .play_from_hand, "Scrounge") orelse return error.MissingAction);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "No action") orelse return error.MissingAction);
    try std.testing.expectEqualStrings("runner-discard-to-deck", generated.runner_prompt_state.?.prompt_type);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Hantu") orelse return error.MissingAction);

    try std.testing.expectEqual(@as(usize, 0), generated.runner_rig_program.items.len);
    try std.testing.expectEqual(@as(usize, 1), generated.runner_discard.items.len);
    try std.testing.expectEqualStrings("Scrounge", generated.runner_discard.items[0].title);
    try std.testing.expectEqualStrings("Hantu", generated.runner_deck.items[generated.runner_deck.items.len - 1].title);
}

test "Synapse Global prompts on tag removal and installs for free" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_hb, 5);
    defer generated.deinit();
    generated.corp_identity = try makeGameCard(&generated, try lookupRequiredCardSpec(35058));
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);
    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    generated.runner_tag = .{ .base = 0, .total = 1, .is_tagged = true };
    try generated.corp_hand.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35073)));
    generated.corp_credit = 5;
    generated.runner_credit = 5;
    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), &generated);

    try applyAction(&generated, findBasicAbilityAction(generated.legal_actions, .runner, .remove_tag) orelse return error.MissingAction);
    try std.testing.expectEqualStrings("corp-free-install-card", generated.corp_prompt_state.?.prompt_type);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .corp, "Plutus") orelse return error.MissingAction);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .corp, "New remote") orelse return error.MissingAction);

    try std.testing.expectEqual(@as(usize, 1), generated.corp_servers.items[3].content.items.len);
    try std.testing.expectEqualStrings("Plutus", generated.corp_servers.items[3].content.items[0].title);
    try std.testing.expect(generated.runner_tag == null or generated.runner_tag.?.total == 0);
}

test "BANGUN installs agendas faceup and punishes access" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_hb, 6);
    defer generated.deinit();
    generated.corp_identity = try makeGameCard(&generated, try lookupRequiredCardSpec(35068));
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);

    try installCard(&generated, try makeGameCard(&generated, try lookupRequiredCardSpec(30067)), "New remote");
    try std.testing.expect(generated.corp_servers.items[3].content.items[0].seen);

    generated.pending_access = .{ .zone = .corp_server_content, .server_index = 3, .card_index = 0 };
    const hand_before = generated.runner_hand.items.len;
    _ = try beginAccessFlow(&generated, generated.corp_servers.items[3].content.items[0]);

    try std.testing.expectEqual(hand_before - 2, generated.runner_hand.items.len);
    try std.testing.expect(generated.runner_tag != null and generated.runner_tag.?.total == 1);
    try std.testing.expectEqualStrings("access-choice", generated.runner_prompt_state.?.prompt_type);
}

test "Madani can host from grip and then install a hosted program" {
    var generated = try createInitialSnapshot(std.testing.allocator, elevation_hb, 7);
    defer generated.deinit();
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .corp, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "mulligan", .choice = stringChoice("Keep") });
    try corpStartTurnFull(&generated);
    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });

    try appendRunnerInstalledCard(&generated, try makeGameCard(&generated, try lookupRequiredCardSpec(35028)));
    try generated.runner_hand.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35008)));
    try generated.runner_hand.append(generated.backing_allocator, try makeGameCard(&generated, try lookupRequiredCardSpec(35009)));
    generated.runner_credit = 10;
    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), &generated);

    try applyAction(&generated, findInstalledAbilityAction(generated.legal_actions, "Madani") orelse return error.MissingAction);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Host programs from grip") orelse return error.MissingAction);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Hantu") orelse return error.MissingAction);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Done") orelse return error.MissingAction);

    try std.testing.expectEqual(@as(usize, 1), generated.runner_rig_hardware.items[0].hosted.len);
    try std.testing.expectEqualStrings("Hantu", generated.runner_rig_hardware.items[0].hosted[0].title);

    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), &generated);
    try applyAction(&generated, findInstalledAbilityAction(generated.legal_actions, "Madani") orelse return error.MissingAction);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Install a hosted program") orelse return error.MissingAction);
    try applyAction(&generated, findPromptChoiceAction(generated.legal_actions, .runner, "Hantu") orelse return error.MissingAction);

    try std.testing.expectEqual(@as(usize, 1), generated.runner_rig_program.items.len);
    try std.testing.expectEqualStrings("Hantu", generated.runner_rig_program.items[0].title);
    try std.testing.expectEqual(@as(usize, 0), generated.runner_rig_hardware.items[0].hosted.len);

    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), &generated);
    try applyAction(&generated, findInstalledAbilityAction(generated.legal_actions, "Madani") orelse return error.MissingAction);
    try std.testing.expect(findPromptChoiceAction(generated.legal_actions, .runner, "Install a hosted program") == null);
    try std.testing.expect(findPromptChoiceAction(generated.legal_actions, .runner, "Host programs from grip") != null);
}
