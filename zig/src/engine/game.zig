const std = @import("std");
const state = @import("state.zig");

pub const DeckLine = struct {
    qty: u8,
    card_code: u32,
};

// Handler type for card-specific subroutine resolution
// Allows cards like Brân 1.0 to have custom logic without bloating the SubroutineKind enum
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
    remote_strength_bonus: u8 = 0, // Palisade: +N strength when protecting a remote
    agenda_points: ?u8 = null,
    advancement_requirement: ?u8 = null,
    corp_play: state.CorpPlaySpec = .{},
    runner_play: state.RunnerPlaySpec = .{},
    access: state.AccessSpec = .{},
    install: state.InstallSpec = .{},
    runner_install: state.RunnerInstallSpec = .{},
    installed_ability: state.InstalledAbilitySpec = .{},
    pump_ability: state.InstalledAbilitySpec = .{},
    subroutines: []const state.SubroutineSpec = &.{},
    runner_abilities: []const state.RunnerAbilitySpec = &.{}, // Runner abilities printed on ICE cards
    on_score: state.AgendaEffectSpec = .{},
    on_steal: state.AgendaEffectSpec = .{},
    // Card-specific subroutine handler - for complex subroutines that need custom logic
    // Set this instead of/in addition to subroutines for cards like Brân 1.0
    card_subroutine_handler: ?CardSubroutineHandler = null,
    trash_cost: ?u16 = null,
    tag_on_rez: u8 = 0, // Ping: give runner N tags when rezzed during a run
    advanceable: bool = false, // Pharos, Clearinghouse: explicitly advanceable
    advancement_strength_threshold: u8 = 0, // Pharos: str bonus at N+ counters
    advancement_strength_bonus: u8 = 0, // Pharos: str bonus amount
    can_play: ?*const fn (*const Game) bool = null,
    on_play: ?*const fn (*Game, state.CardInstance) anyerror!void = null,
    on_prompt_choice: ?*const fn (*Game, []const u8) anyerror!void = null,
    on_score_fn: ?*const fn (*Game, state.CardInstance) anyerror!void = null,
    on_encounter: ?*const fn (*Game, *const state.CardInstance) anyerror!void = null,
    on_rez: ?*const fn (*Game) anyerror!void = null,
    // Event trigger system: identity/card events fire at game events
    event_match: ?*const fn (state.GameEvent) bool = null,
    on_event: ?*const fn (*Game) anyerror!void = null,
    on_event_server_check: bool = false, // Only fire if event occurred in same server as this card
};

/// Deferred effect for the async continuation queue.
/// When multiple effects trigger simultaneously (e.g., scoring an agenda triggers
/// on-score effects + event handlers from multiple cards), they are queued here
/// and processed one at a time. If any effect opens a prompt, processing pauses
/// until the prompt resolves, then continues with the next effect.
pub const PendingEffect = union(enum) {
    event_handler: u32, // card code — look up spec and call on_event
    on_score_gain_credits: u16,
    on_score_draw_cards: struct { amount: u8, card_code: u32 },
    on_score_give_runner_tag: u8,
    on_score_gain_clicks: u8,
    on_score_rez_ice_free: state.CardInstance, // the scored agenda
    on_score_fn: state.CardInstance, // the scored agenda — look up spec and call on_score_fn
    finish_score: void, // terminal: updateTerminalState + return to corp actions
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

pub const all_cards = [_]CardSpec{
    .{ .title = "The Syndicate: Profit over Principle", .side = .corp, .code = 30077, .card_type = "Identity" },
    .{ .title = "The Catalyst: Convention Breaker", .side = .runner, .code = 30076, .card_type = "Identity" },
    .{ .title = "Haas-Bioroid: Precision Design", .side = .corp, .code = 30035, .card_type = "Identity",
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .agenda_scored; } }.m,
        .on_event = &struct {
            fn handle(g: *Game) anyerror!void {
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
    },
    .{ .title = "Jinteki: Restoring Humanity", .side = .corp, .code = 30043, .card_type = "Identity",
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .corp_end_turn; } }.m,
        .on_event = &struct {
            fn handle(g: *Game) anyerror!void {
                if (g.corp_discard.items.len > 0) {
                    g.corp_credit += 1;
                }
            }
        }.handle,
    },
    .{ .title = "NBN: Reality Plus", .side = .corp, .code = 30051, .card_type = "Identity",
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .runner_gain_tag; } }.m,
        .on_event = &struct {
            fn handle(g: *Game) anyerror!void {
                if (g.turn_events.runner_gain_tag_count != 1) return; // first-event? check
                const allocator = g.arena.allocator();
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                try choices.append(allocator, stringChoice("Gain 2 [Credits]"));
                try choices.append(allocator, stringChoice("Draw 2 cards"));
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "reality-plus"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = null,
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
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                if (std.mem.eql(u8, choice_text, "Gain 2 [Credits]")) {
                    g.corp_credit += 2;
                } else if (std.mem.eql(u8, choice_text, "Draw 2 cards")) {
                    try drawCards(g, .corp, 2);
                } else return error.UnsupportedChoice;
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
        }.choice,
    },
    .{ .title = "Weyland Consortium: Built to Last", .side = .corp, .code = 30059, .card_type = "Identity",
        // Advance trigger is handled inline in addAdvancementCounter since it needs the card's old state
    },
    .{ .title = "Ren\xc3\xa9 \"Loup\" Arcemont: Party Animal", .side = .runner, .code = 30001, .card_type = "Identity",
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .runner_trash_corp_card; } }.m,
        .on_event = &struct {
            fn handle(g: *Game) anyerror!void {
                if (g.turn_events.runner_trash_corp_card_count == 1) { // first-event?
                    g.runner_credit += 1;
                    try drawCards(g, .runner, 1);
                }
            }
        }.handle,
    },
    .{ .title = "T\xc4\x81o Salonga: Telepresence Magician", .side = .runner, .code = 30019, .card_type = "Identity",
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .agenda_scored or e == .agenda_stolen; } }.m,
        .on_event = &struct {
            fn handle(g: *Game) anyerror!void {
                // Count installed ICE across all servers
                var ice_count: usize = 0;
                for (g.corp_servers.items) |server| {
                    ice_count += server.ices.items.len;
                }
                if (ice_count < 2) return; // need at least 2 ICE to swap
                const allocator = g.arena.allocator();
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                for (g.corp_servers.items, 0..) |server, si| {
                    for (server.ices.items, 0..) |ice, ii| {
                        // Format: "server_idx|ice_idx|title"
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
        }.handle,
    },
    .{ .title = "Zahya Sadeghi: Versatile Smuggler", .side = .runner, .code = 30010, .card_type = "Identity",
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .successful_run_ends; } }.m,
        .on_event = &struct {
            fn handle(g: *Game) anyerror!void {
                if (g.turn_events.successful_run_ends_count != 1) return; // once per turn
                const run = g.run orelse return;
                if (run.server.len == 0) return;
                if (!std.mem.eql(u8, run.server[0], "hq") and !std.mem.eql(u8, run.server[0], "rnd")) return;
                const accessed = run.accessed_count;
                if (accessed == 0) return;
                // Zahya: auto-accept (Clojure's optional prompt always accepted in competitive play)
                // The credit gain happens regardless of prompt — Clojure auto-resolves "Yes"
                g.runner_credit += accessed;
            }
        }.handle,
    },
    .{ .title = "Offworld Office", .side = .corp, .code = 30067, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 4, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only }, .on_score = .{ .kind = .gain_credits, .amount = 7 } },
    .{ .title = "Send a Message", .side = .corp, .code = 30069, .card_type = "Agenda", .agenda_points = 3, .advancement_requirement = 5, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only }, .on_score = .{ .kind = .rez_ice_free }, .on_steal = .{ .kind = .rez_ice_free } },
    .{ .title = "Superconducting Hub", .side = .corp, .code = 30070, .card_type = "Agenda", .agenda_points = 1, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only }, .on_score = .{ .kind = .draw_cards, .amount = 2 } },
    .{ .title = "Orbital Superiority", .side = .corp, .code = 30068, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 4, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                if (is_runner_tagged(g.runner_tag)) {
                    try trashRandomRunnerHandCards(g, 4);
                    updateTerminalState(g);
                } else {
                    _ = try addRunnerTag(g, 1);
                }
            }
        }.score,
    },
    .{ .title = "Nico Campaign", .side = .corp, .code = 30037, .card_type = "Asset", .cost = 2, .trash_cost = 2, .install = .{ .kind = .corp_remote_only }, .installed_ability = .{
        .kind = .take_credits,
        .click_cost = 1,
        .initial_credit_counters = 9,
        .take_credits_amount = 3,
        .trash_on_empty = true,
        .draw_on_empty = 1,
    } },
    .{ .title = "Regolith Mining License", .side = .corp, .code = 30071, .card_type = "Asset", .cost = 2, .trash_cost = 3, .install = .{ .kind = .corp_remote_only }, .installed_ability = .{
        .kind = .take_credits,
        .click_cost = 1,
        .initial_credit_counters = 15,
        .take_credits_amount = 3,
        .trash_on_empty = true,
    } },
    .{ .title = "Urtica Cipher", .side = .corp, .code = 30045, .card_type = "Asset", .cost = 0, .trash_cost = 2, .access = .{ .kind = .net_damage_on_access, .corp_credit_cost = 2, .base_damage = 2, .adds_advancement = true }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Government Subsidy", .side = .corp, .code = 30064, .card_type = "Operation", .cost = 10, .corp_play = .{ .kind = .gain_credits, .gain_credits = 15 } },
    .{ .title = "Hedge Fund", .side = .corp, .code = 30075, .card_type = "Operation", .cost = 5, .corp_play = .{ .kind = .gain_credits, .gain_credits = 9 } },
    .{ .title = "Seamless Launch", .side = .corp, .code = 30040, .card_type = "Operation", .cost = 1, .corp_play = .{ .kind = .advance_installed, .advancement_amount = 2, .not_installed_this_turn = true } },
    .{ .title = "Predictive Planogram", .side = .corp, .code = 30056, .card_type = "Operation", .cost = 0, .corp_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
                const allocator = g.arena.allocator();
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "other"),
                    .choices = try predictive_planogram_choices(allocator, g.runner_tag),
                    .source_card = card,
                };
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                if (std.mem.eql(u8, choice_text, "Gain 3 [Credits]")) {
                    g.corp_credit += 3;
                } else if (std.mem.eql(u8, choice_text, "Draw 3 cards")) {
                    try drawCards(g, .corp, 3);
                } else if (std.mem.eql(u8, choice_text, "Gain 3 [Credits] and draw 3 cards")) {
                    g.corp_credit += 3;
                    try drawCards(g, .corp, 3);
                } else return error.UnsupportedChoice;
                g.corp_prompt_state = null;
                g.runner_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.choice,
    },
    .{ .title = "Public Trail", .side = .corp, .code = 30057, .card_type = "Operation", .cost = 4, .corp_play = .{ .kind = .custom },
        .can_play = &struct {
            fn check(g: *const Game) bool {
                return runner_had_successful_run_last_turn(g);
            }
        }.check,
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
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
                    .source_card = card,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                if (std.mem.eql(u8, choice_text, "Take 1 tag")) {
                    if (try addRunnerTag(g, 1)) return; // Event handler opened prompt
                } else if (std.mem.eql(u8, choice_text, "Pay 8 [Credits]")) {
                    try spendCredits(g, .runner, 8);
                } else return error.UnsupportedChoice;
                g.runner_prompt_state = null;
                g.corp_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.choice,
    },
    .{ .title = "Retribution", .side = .corp, .code = 30065, .card_type = "Operation", .cost = 1, .corp_play = .{ .kind = .custom },
        .can_play = &struct {
            fn check(g: *const Game) bool {
                return is_runner_tagged(g.runner_tag) and
                    (g.runner_rig_hardware.items.len > 0 or g.runner_rig_program.items.len > 0);
            }
        }.check,
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
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
                    .source_card = card,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                var pieces = std.mem.splitScalar(u8, choice_text, '|');
                const zone = pieces.next() orelse return error.UnsupportedChoice;
                const index_text = pieces.next() orelse return error.UnsupportedChoice;
                const index = try std.fmt.parseInt(usize, index_text, 10);
                if (std.mem.eql(u8, zone, "h")) {
                    if (index >= g.runner_rig_hardware.items.len) return error.UnsupportedChoice;
                    const trashed = g.runner_rig_hardware.orderedRemove(index);
                    try g.runner_discard.append(g.backing_allocator, trashed);
                } else if (std.mem.eql(u8, zone, "p")) {
                    if (index >= g.runner_rig_program.items.len) return error.UnsupportedChoice;
                    const trashed = g.runner_rig_program.orderedRemove(index);
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
        }.choice,
    },
    .{ .title = "Manegarm Skunkworks", .side = .corp, .code = 30042, .card_type = "Upgrade", .cost = 2, .trash_cost = 3, .access = .{ .kind = .tax_or_etr, .click_cost = 2, .credit_cost = 5 }, .install = .{ .kind = .corp_remote_only },
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                const allocator = g.arena.allocator();
                const prompt = g.runner_prompt_state orelse return error.MissingPrompt;
                const card = prompt.source_card orelse return error.MissingSourceCard;
                var run = &g.run.?;
                if (std.mem.eql(u8, choice_text, "Spend [Click][Click]")) {
                    g.runner_click -= card.access.click_cost;
                } else if (std.mem.eql(u8, choice_text, "Pay 5 [Credits]")) {
                    g.runner_credit -= @intCast(card.access.credit_cost);
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
        }.choice,
    },
    .{ .title = "AMAZE Amusements", .side = .corp, .code = 30058, .card_type = "Upgrade", .cost = 1, .trash_cost = 3, .install = .{ .kind = .corp_remote_only }, .installed_ability = .{ .tags_on_agenda_steal_from_server = 2 } },
    .{ .title = "Brân 1.0", .side = .corp, .code = 30039, .card_type = "ICE", .subtypes = &.{ "Bioroid", "Barrier" }, .cost = 6, .strength = 6, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .install_ice_from_hq_archives },
        .{ .kind = .end_the_run },
        .{ .kind = .end_the_run },
    }, .runner_abilities = &.{
        .{ .kind = .bioroid_break, .click_cost = 1, .break_quantity = 1 },
    },
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                try applyBranInstallIceChoice(g, choice_text);
            }
        }.choice,
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
    .{ .title = "Funhouse", .side = .corp, .code = 30054, .card_type = "ICE", .subtypes = &.{"Code Gate"}, .cost = 5, .strength = 4, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .give_tag_or_pay_credits, .amount = 4 },
    },
        .on_encounter = &struct {
            fn encounter(g: *Game, ice: *const state.CardInstance) anyerror!void {
                _ = ice;
                const allocator = g.arena.allocator();
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                try choices.append(allocator, stringChoice("Take 1 tag"));
                try choices.append(allocator, stringChoice("End the run"));
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "funhouse-encounter"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = null,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.encounter,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                if (std.mem.eql(u8, choice_text, "Take 1 tag")) {
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
        }.choice,
    },
    .{ .title = "Creative Commission", .side = .runner, .code = 30020, .card_type = "Event", .cost = 1, .runner_play = .{ .kind = .gain_credits, .gain_credits = 5, .lose_clicks = 1 } },
    .{ .title = "Jailbreak", .side = .runner, .code = 30028, .card_type = "Event", .cost = 0, .runner_play = .{
        .kind = .choose_run_target,
        .run_target_kind = .hq_and_rnd_only,
        .successful_run_effect = .draw_cards,
        .successful_run_draw_cards = 1,
        .successful_run_access_bonus = 1,
    } },
    .{ .title = "Overclock", .side = .runner, .code = 30029, .card_type = "Event", .cost = 1, .runner_play = .{
        .kind = .choose_run_target,
        .run_target_kind = .any_runnable,
        .run_credits = 5,
    } },
    .{ .title = "Sure Gamble", .side = .runner, .code = 30030, .card_type = "Event", .cost = 5, .runner_play = .{ .kind = .gain_credits, .gain_credits = 9 } },
    .{ .title = "Tread Lightly", .side = .runner, .code = 30012, .card_type = "Event", .cost = 1, .runner_play = .{
        .kind = .choose_run_target,
        .run_target_kind = .any_runnable,
        .run_rez_cost_bonus = 3,
    } },
    .{ .title = "Mutual Favor", .side = .runner, .code = 30011, .card_type = "Event", .cost = 0, .runner_play = .{ .kind = .custom },
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
    .{ .title = "Wildcat Strike", .side = .runner, .code = 30002, .card_type = "Event", .cost = 2, .runner_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, _: state.CardInstance) anyerror!void {
                const allocator = g.arena.allocator();
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "other"),
                    .choices = try wildcat_strike_choices(allocator),
                    .source_card = null,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                if (std.mem.eql(u8, choice_text, "Runner gains 6 [Credits]")) {
                    g.runner_credit += 6;
                } else if (std.mem.eql(u8, choice_text, "Runner draws 4 cards")) {
                    try drawCards(g, .runner, 4);
                } else return error.UnsupportedChoice;
                g.corp_prompt_state = null;
                g.runner_prompt_state = null;
                g.decision_side = .runner;
                g.legal_actions = try runnerOpeningActionsForState(
                    g.arena.allocator(),
                    g,
                );
            }
        }.choice,
    },
    .{ .title = "VRcation", .side = .runner, .code = 30021, .card_type = "Event", .cost = 1, .runner_play = .{ .kind = .gain_credits, .draw_cards = 4, .lose_clicks = 1 } },
    .{ .title = "Docklands Pass", .side = .runner, .code = 30013, .card_type = "Hardware", .cost = 2, .runner_install = .{ .kind = .hardware }, .installed_ability = .{ .hq_access_bonus = 1 } },
    .{ .title = "Pennyshaver", .side = .runner, .code = 30014, .card_type = "Hardware", .cost = 3, .runner_install = .{ .kind = .hardware }, .installed_ability = .{
        .kind = .take_credits,
        .click_cost = 1,
        .initial_credit_counters = 0,
        .takes_all_credits = true,
        .on_successful_run_place_credits = 1,
    } },
    .{ .title = "DZMZ Optimizer", .side = .runner, .code = 30022, .card_type = "Hardware", .cost = 2, .runner_install = .{ .kind = .hardware }, .installed_ability = .{ .mu_provided = 1, .first_program_install_discount = 1 } },
    .{ .title = "Red Team", .side = .runner, .code = 30018, .card_type = "Resource", .cost = 5, .runner_install = .{ .kind = .resource }, .installed_ability = .{
        .kind = .run_central,
        .click_cost = 1,
        .initial_credit_counters = 12,
        .take_credits_amount = 3,
        .trash_on_empty = true,
    } },
    .{ .title = "Smartware Distributor", .side = .runner, .code = 30033, .card_type = "Resource", .cost = 0, .runner_install = .{ .kind = .resource }, .installed_ability = .{
        .kind = .place_credits,
        .click_cost = 1,
        .place_credits_amount = 3,
        .initial_credit_counters = 0,
    } },
    .{ .title = "Telework Contract", .side = .runner, .code = 30027, .card_type = "Resource", .cost = 1, .runner_install = .{ .kind = .resource }, .installed_ability = .{
        .kind = .take_credits,
        .click_cost = 1,
        .initial_credit_counters = 9,
        .take_credits_amount = 3,
        .trash_on_empty = true,
        .once_per_turn = true,
    } },
    .{ .title = "Verbal Plasticity", .side = .runner, .code = 30034, .card_type = "Resource", .cost = 3, .runner_install = .{ .kind = .resource }, .installed_ability = .{ .click_draw_bonus = 1 } },
    .{ .title = "Carmen", .side = .runner, .code = 30015, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer" }, .cost = 5, .strength = 2, .runner_install = .{ .kind = .program, .install_cost_reduction_if_successful_run = 2 }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 1,
        .break_subroutine_count = 1,
    }, .pump_ability = .{ .kind = .pump_strength, .credit_cost = 2, .pump_strength_amount = 3 } },
    .{ .title = "Cleaver", .side = .runner, .code = 30006, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Fracter" }, .cost = 3, .strength = 3, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 1,
        .break_subroutine_count = 2,
    }, .pump_ability = .{ .kind = .pump_strength, .credit_cost = 2, .pump_strength_amount = 1 } },
    .{ .title = "Mayfly", .side = .runner, .code = 30032, .card_type = "Program", .subtypes = &.{ "Icebreaker", "AI" }, .cost = 1, .strength = 1, .runner_install = .{ .kind = .program, .mu_cost = 2 }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 1,
        .break_subroutine_count = 1,
        .trashes_after_break = true,
    }, .pump_ability = .{ .kind = .pump_strength, .credit_cost = 1, .pump_strength_amount = 1 } },
    .{ .title = "Unity", .side = .runner, .code = 30026, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Decoder" }, .cost = 3, .strength = 1, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 1,
        .break_subroutine_count = 1,
    }, .pump_ability = .{ .kind = .pump_strength, .credit_cost = 1, .pump_strength_amount = 0, .pump_is_variable = true } },
    .{ .title = "Conduit", .side = .runner, .code = 30024, .card_type = "Program", .cost = 4, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .run_rd,
        .click_cost = 1,
        .virus_on_successful_rd = true,
        .rd_access_bonus_per_virus = true,
    } },
    .{ .title = "Leech", .side = .runner, .code = 30008, .card_type = "Program", .cost = 1, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .virus_on_successful_central = true,
        .virus_ice_strength_reduction = 1,
    } },
    // --- System Gateway cards beyond beginner/intermediate ---
    .{ .title = "Buzzsaw", .side = .runner, .code = 30005, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Decoder" }, .cost = 4, .strength = 3, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 1,
        .break_subroutine_count = 2,
    }, .pump_ability = .{ .kind = .pump_strength, .credit_cost = 3, .pump_strength_amount = 1 } },
    .{ .title = "Echelon", .side = .runner, .code = 30025, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer" }, .cost = 3, .strength = 0, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 1,
        .break_subroutine_count = 1,
        .strength_per_icebreaker = true,
    }, .pump_ability = .{ .kind = .pump_strength, .credit_cost = 3, .pump_strength_amount = 2 } },
    .{ .title = "Marjanah", .side = .runner, .code = 30016, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Fracter" }, .cost = 0, .strength = 1, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 2,
        .break_subroutine_count = 1,
        .break_cost_reduction_if_successful_run = 1,
    }, .pump_ability = .{ .kind = .pump_strength, .credit_cost = 1, .pump_strength_amount = 1 } },
    .{ .title = "T400 Memory Diamond", .side = .runner, .code = 30031, .card_type = "Hardware", .cost = 2, .runner_install = .{ .kind = .hardware }, .installed_ability = .{ .mu_provided = 1, .hand_size_bonus = 1 } },
    .{ .title = "Tomorrow's Headline", .side = .corp, .code = 30052, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
        .on_score = .{ .kind = .give_runner_tag, .amount = 1 },
        .on_steal = .{ .kind = .give_runner_tag, .amount = 1 },
    },
    .{ .title = "Ping", .side = .corp, .code = 30055, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 2, .strength = 1, .tag_on_rez = 1, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .end_the_run },
    } },
    .{ .title = "Ballista", .side = .corp, .code = 30062, .card_type = "ICE", .subtypes = &.{"Sentry"}, .cost = 5, .strength = 4, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .trash_program_or_etr },
        .{ .kind = .trash_program_or_etr },
    } },
    .{ .title = "Sprint", .side = .corp, .code = 30041, .card_type = "Operation", .cost = 0, .corp_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, src_card: state.CardInstance) anyerror!void {
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
                    .source_card = src_card,
                    .min_choices = 2,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                // Find the card in hand and move it to deck
                for (g.corp_hand.items, 0..) |card, idx| {
                    if (std.mem.eql(u8, card.title, choice_text)) {
                        const removed = g.corp_hand.orderedRemove(idx);
                        try g.corp_deck.append(g.backing_allocator, removed);
                        break;
                    }
                }
                // Check if we need to pick one more
                if (g.corp_prompt_state) |*ps| {
                    if (ps.min_choices > 1) {
                        ps.min_choices -= 1;
                        // Rebuild choices with updated hand
                        const allocator = g.arena.allocator();
                        var choices: std.ArrayList(state.PromptChoice) = .empty;
                        defer choices.deinit(allocator);
                        for (g.corp_hand.items, 0..) |card, idx| {
                            try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                        }
                        ps.choices = try choices.toOwnedSlice(allocator);
                        g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                        return;
                    }
                }
                // Done — shuffle R&D and return to corp actions
                try shuffleDeck(g, .corp);
                g.corp_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.choice,
    },
    .{ .title = "Hansei Review", .side = .corp, .code = 30048, .card_type = "Operation", .cost = 5, .corp_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
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
                    .source_card = card,
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                for (g.corp_hand.items, 0..) |card, idx| {
                    if (std.mem.eql(u8, card.title, choice_text)) {
                        const removed = g.corp_hand.orderedRemove(idx);
                        try g.corp_discard.append(g.backing_allocator, removed);
                        break;
                    }
                }
                g.corp_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.choice,
    },
    .{ .title = "Above the Law", .side = .corp, .code = 30060, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
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
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.score,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
        }.choice,
    },
    // --- Phase 1: Pharos, Fermenter, Neurospike, Luminal Transubstantiation, Cookbook ---
    .{ .title = "Pharos", .side = .corp, .code = 30063, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 7, .strength = 5, .advanceable = true, .advancement_strength_threshold = 3, .advancement_strength_bonus = 5, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .give_runner_tags, .amount = 1 },
        .{ .kind = .end_the_run },
        .{ .kind = .end_the_run },
    } },
    .{ .title = "Fermenter", .side = .runner, .code = 30007, .card_type = "Program", .subtypes = &.{"Virus"}, .cost = 1, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .trash_for_virus_credits,
        .click_cost = 1,
        .trash_for_virus_credits = 2,
        .virus_on_install = true,
        .virus_on_turn_start = true,
    } },
    .{ .title = "Neurospike", .side = .corp, .code = 30049, .card_type = "Operation", .cost = 3, .corp_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, _: state.CardInstance) anyerror!void {
                const damage = g.turn_events.agenda_points_scored_this_turn;
                if (damage > 0) {
                    try trashRandomRunnerHandCards(g, damage);
                    updateTerminalState(g);
                    if (g.game_over) return;
                }
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.play,
    },
    .{ .title = "Luminal Transubstantiation", .side = .corp, .code = 30036, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
        .on_score = .{ .kind = .gain_clicks, .amount = 3 },
    },
    .{ .title = "Cookbook", .side = .runner, .code = 30009, .card_type = "Resource", .subtypes = &.{"Virtual"}, .cost = 1, .runner_install = .{ .kind = .resource }, .installed_ability = .{ .bonus_virus_on_install = 1 } },
    // --- Phase 2: Clearinghouse, Longevity Serum, Malapert Data Vault, Spin Doctor ---
    .{ .title = "Clearinghouse", .side = .corp, .code = 30061, .card_type = "Asset", .subtypes = &.{"Hostile"}, .cost = 0, .trash_cost = 3, .advanceable = true, .install = .{ .kind = .corp_remote_only }, .installed_ability = .{
        .kind = .trash_for_damage,
        .click_cost = 1,
    } },
    .{ .title = "Longevity Serum", .side = .corp, .code = 30044, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
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
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.score,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
                            .min_choices = 0,
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
                        .min_choices = prompt.min_choices + 1,
                    };
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    return;
                }
                return error.UnsupportedPrompt;
            }
        }.choice,
    },
    .{ .title = "Malapert Data Vault", .side = .corp, .code = 30066, .card_type = "Upgrade", .cost = 1, .trash_cost = 4, .install = .{ .kind = .corp_remote_only },
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .agenda_scored; } }.m,
        .on_event_server_check = true,
        .on_event = &struct {
            fn handle(g: *Game) anyerror!void {
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
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.handle,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
        }.choice,
    },
    .{ .title = "Spin Doctor", .side = .corp, .code = 30053, .card_type = "Asset", .subtypes = &.{"Character"}, .cost = 0, .trash_cost = 2, .install = .{ .kind = .corp_remote_only },
        .on_rez = &struct {
            fn rez(g: *Game) anyerror!void {
                try drawCards(g, .corp, 2);
            }
        }.rez,
        .installed_ability = .{
            .kind = .remove_from_game_shuffle,
            .click_cost = 0, // no click cost — it's a paid ability usable anytime
        },
    },
    // --- Phase 3: Consoles ---
    .{ .title = "Carnivore", .side = .runner, .code = 30003, .card_type = "Hardware", .subtypes = &.{"Console"}, .cost = 4, .runner_install = .{ .kind = .hardware }, .installed_ability = .{ .mu_provided = 1, .is_console = true } },
    .{ .title = "Pantograph", .side = .runner, .code = 30023, .card_type = "Hardware", .subtypes = &.{"Console"}, .cost = 2, .runner_install = .{ .kind = .hardware }, .installed_ability = .{ .mu_provided = 1, .is_console = true },
        .event_match = &struct {
            fn m(e: state.GameEvent) bool { return e == .agenda_scored or e == .agenda_stolen; }
        }.m,
        .on_event = &struct {
            fn handle(g: *Game) anyerror!void {
                g.runner_credit += 1;
            }
        }.handle,
    },
    // --- Phase 4: Trojans ---
    .{ .title = "Botulus", .side = .runner, .code = 30004, .card_type = "Program", .subtypes = &.{ "Virus", "Trojan" }, .cost = 2, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .is_trojan = true,
        .trojan_break_any = true,
        .virus_on_install = true,
        .virus_on_turn_start = true,
    } },
    .{ .title = "Tranquilizer", .side = .runner, .code = 30017, .card_type = "Program", .subtypes = &.{ "Virus", "Trojan" }, .cost = 2, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .is_trojan = true,
        .trojan_derez_threshold = 3,
        .virus_on_install = true,
        .virus_on_turn_start = true,
    } },
    // --- Phase 5: Ansel 1.0 ---
    .{ .title = "Ansel 1.0", .side = .corp, .code = 30038, .card_type = "ICE", .subtypes = &.{ "Bioroid", "Sentry", "Destroyer" }, .cost = 6, .strength = 4, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .trash_program_or_etr }, // trash 1 installed Runner card
        .{ .kind = .none }, // install from HQ or Archives (placeholder)
        .{ .kind = .none }, // no steal/trash for rest of run (placeholder)
    }, .runner_abilities = &.{
        .{ .kind = .bioroid_break, .click_cost = 1, .break_quantity = 1 },
    } },
    .{ .title = "Anoetic Void", .side = .corp, .code = 30050, .card_type = "Upgrade", .cost = 0, .trash_cost = 1, .install = .{ .kind = .corp_remote_only },
        .access = .{ .kind = .corp_pay_etr, .credit_cost = 2 },
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
        }.choice,
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
    .format = "system-gateway", .agenda_point_req = 7,
    .corp = .{ .identity_code = 30035, .deck_lines = &complete_corp_deck_lines }, // HB: Precision Design
    .runner = .{ .identity_code = 30076, .deck_lines = &complete_runner_deck_lines },
};
pub const system_gateway_jinteki = MatchupSpec{
    .format = "system-gateway", .agenda_point_req = 7,
    .corp = .{ .identity_code = 30043, .deck_lines = &complete_corp_deck_lines }, // Jinteki: Restoring Humanity
    .runner = .{ .identity_code = 30076, .deck_lines = &complete_runner_deck_lines },
};
pub const system_gateway_nbn = MatchupSpec{
    .format = "system-gateway", .agenda_point_req = 7,
    .corp = .{ .identity_code = 30051, .deck_lines = &complete_corp_deck_lines }, // NBN: Reality Plus
    .runner = .{ .identity_code = 30076, .deck_lines = &complete_runner_deck_lines },
};
pub const system_gateway_weyland = MatchupSpec{
    .format = "system-gateway", .agenda_point_req = 7,
    .corp = .{ .identity_code = 30059, .deck_lines = &complete_corp_deck_lines }, // Weyland: Built to Last
    .runner = .{ .identity_code = 30076, .deck_lines = &complete_runner_deck_lines },
};
pub const system_gateway_zahya = MatchupSpec{
    .format = "system-gateway", .agenda_point_req = 7,
    .corp = .{ .identity_code = 30077, .deck_lines = &complete_corp_deck_lines },
    .runner = .{ .identity_code = 30010, .deck_lines = &complete_runner_deck_lines }, // Zahya
};
pub const system_gateway_loup = MatchupSpec{
    .format = "system-gateway", .agenda_point_req = 7,
    .corp = .{ .identity_code = 30077, .deck_lines = &complete_corp_deck_lines },
    .runner = .{ .identity_code = 30001, .deck_lines = &complete_runner_deck_lines }, // Loup
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

pub const Game = struct {
    arena: std.heap.ArenaAllocator,
    backing_allocator: std.mem.Allocator,

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
    corp_phase_12: bool = false,
    cannot_score_agendas_this_turn: bool = false, // Luminal Transubstantiation
    last_scored_server_index: ?usize = null, // Server from which last agenda was scored
    tao_first_ice: ?[]const u8 = null, // Tao: first ICE selection (server_idx|ice_idx|title)
    pending_effects: std.ArrayListUnmanaged(PendingEffect) = .empty, // Async effect continuation queue

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
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn hasInstalledCards(self: *const Game) bool {
        return countInstalledCards(self.corp_servers.items) > 0;
    }

    pub fn toSnapshot(self: *Game) !state.GameSnapshot {
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

const prompt_install_destination = "install-destination";
const prompt_advance_installed = "advance-installed";
const prompt_score_agenda = "score-agenda";
const prompt_access_choice = "access-choice";
const prompt_access_cleanup = "access-cleanup";
const prompt_rez_ice_free = "send-message-rez";
const prompt_rez_ice_free_score = "send-message-rez-score";
const prompt_run_target = "run-target";
const prompt_run_any_server_basic = "run-any-server-basic";
const prompt_run_central = "run-central";
const prompt_hq_access = "hq-access";
const prompt_rez_window = "rez-window";
const prompt_discard = "discard";
const prompt_manegarm_tax = "manegarm-tax";

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

    // Initialize internal scalar state
    game.format = try allocator.dupe(u8, matchup.format);
    game.seed = seed;
    game.rng_seed = oracleSeed(rng_state);
    game.active_player = .runner;
    game.turn = 0;
    game.end_turn = true;

    game.corp_identity = corp_identity;
    game.corp_basic_action_card = try makeCardInstance(allocator, corp_basic_action);
    game.corp_credit = 5;
    game.corp_agenda_point_req = matchup.agenda_point_req;
    // HB: Precision Design: +1 max hand size
    if (matchup.corp.identity_code == 30035) {
        game.corp_hand_size.base += 1;
        game.corp_hand_size.total += 1;
    }
    game.corp_keep = .undecided;
    game.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "mulligan"),
        .choices = mulligan_prompt,
        .source_card = null,
    };

    game.runner_identity = runner_identity;
    game.runner_basic_action_card = try makeCardInstance(allocator, runner_basic_action);
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
        .use_runner_ability => {
            try applyRunnerAbility(generated, action);
        },
        .rez_non_ice => {
            const card_index = action.card_index orelse return error.MissingCardIndex;
            const server = action.server orelse return error.MissingServer;
            try applyRezNonIce(generated, server, card_index);
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
    switch (side) { .corp => { generated.corp_keep = choice; }, .runner => { generated.runner_keep = choice; } }

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

    switch (side) {
        .corp => {
            // Enter corp phase 12 — both players must pass before main phase
            generated.active_player = .corp;
            generated.turn += 1;
            generated.end_turn = false;
            generated.corp_phase_12 = true;
            generated.decision_side = .corp;
            generated.legal_actions = try continueActions(allocator, .corp);
        },
        .runner => {
            generated.runner_click = generated.runner_click_per_turn;
            generated.turn_events = .{};
            resetInstalledAbilityUsage(generated);

            // Start-of-turn: take 1 credit from each card with place_credits ability and counters
            for (generated.runner_rig_resources.items) |*card| {
                if (card.installed_ability.kind == .place_credits and card.credit_counter > 0) {
                    card.credit_counter -= 1;
                    generated.runner_credit += 1;
                }
            }

            // Virus-on-turn-start: Fermenter, Botulus, Tranquilizer
            for (generated.runner_rig_program.items) |*prog| {
                if (prog.installed_ability.virus_on_turn_start) {
                    prog.virus_counter += 1;
                    // Tranquilizer: derez host ICE when virus counters >= threshold
                    if (prog.installed_ability.trojan_derez_threshold > 0 and prog.virus_counter >= prog.installed_ability.trojan_derez_threshold) {
                        if (prog.hosted_on_ice_server) |si| {
                            if (prog.hosted_on_ice_index) |ii| {
                                if (si < generated.corp_servers.items.len and ii < generated.corp_servers.items[si].ices.items.len) {
                                    generated.corp_servers.items[si].ices.items[ii].rezzed = false;
                                }
                            }
                        }
                    }
                }
            }

            generated.active_player = .runner;
            generated.end_turn = false;
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

    (switch (side) { .corp => generated.corp_prompt_state, .runner => generated.runner_prompt_state }) = .{
        .prompt_type = try allocator.dupe(u8, prompt_discard),
        .choices = choices,
        .source_card = null,
        .min_choices = @intCast(discard_count),
    };
    generated.decision_side = side;
    generated.legal_actions = try promptChoiceActions(allocator, side, (switch (side) { .corp => generated.corp_prompt_state, .runner => generated.runner_prompt_state }).?);
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
    const next_side = otherSide(side);
    generated.end_turn = true;
    // Clear any discard prompt
    switch (side) {
        .corp => generated.corp_prompt_state = null,
        .runner => generated.runner_prompt_state = null,
    }
    // Fire corp_end_turn event (Jinteki: Restoring Humanity trigger)
    if (side == .corp) {
        _ = try fireEvent(generated, .corp_end_turn);
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

    const prompt = (switch (side) { .corp => generated.corp_prompt_state, .runner => generated.runner_prompt_state }) orelse return error.MissingPrompt;

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

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, prompt_rez_window)) {
        try applyRezWindowChoice(generated, choice_text);
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

    if (std.mem.eql(u8, prompt.prompt_type, prompt_run_any_server_basic)) {
        try applyRun(generated, .runner, choice_text);
        return;
    }

    if (std.mem.eql(u8, prompt.prompt_type, prompt_run_central)) {
        // Red Team: click already spent in run_central handler, just start the run
        try applyRunFromAbility(generated, choice_text, prompt.source_card);
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

    // NBN: Reality Plus: handled by card spec on_prompt_choice via generic handler below
    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, "reality-plus")) {
        if (lookupCardSpecByCode(30051)) |spec| {
            if (spec.on_prompt_choice) |handler| {
                try handler(generated, choice_text);
                if (try resumePendingEffects(generated)) return;
                return;
            }
        }
        return error.UnsupportedPrompt;
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

    // Malapert Data Vault: search R&D for non-agenda card
    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, "malapert-search")) {
        if (lookupCardSpecByCode(30066)) |spec| {
            if (spec.on_prompt_choice) |handler| {
                try handler(generated, choice_text);
                generated.corp_prompt_state = null;
                // Resume pending effects chain (remaining on-score effects, other triggers)
                if (try resumePendingEffects(generated)) return;
                generated.decision_side = .corp;
                generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
                return;
            }
        }
        return error.UnsupportedPrompt;
    }

    // Longevity Serum: trash from HQ / shuffle from Archives
    if (side == .corp and (std.mem.eql(u8, prompt.prompt_type, "longevity-serum-trash") or std.mem.eql(u8, prompt.prompt_type, "longevity-serum-shuffle"))) {
        if (lookupCardSpecByCode(30044)) |spec| {
            if (spec.on_prompt_choice) |handler| {
                try handler(generated, choice_text);
                return;
            }
        }
        return error.UnsupportedPrompt;
    }

    // Anoetic Void: corp chooses to use ability (pay 2cr + trash 2 from HQ → ETR)
    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, "anoetic-void")) {
        if (prompt.source_card) |sc| {
            if (lookupCardSpec(sc)) |spec| {
                if (spec.on_prompt_choice) |handler| {
                    try handler(generated, choice_text);
                    return;
                }
            }
        }
        return error.UnsupportedPrompt;
    }

    // Ballista: corp chooses a program to trash during subroutine
    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, "ballista-trash")) {
        try applyBallistaTrashChoice(generated, choice_text);
        return;
    }

    // Funhouse on-encounter and other ICE on-encounter prompts
    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, "funhouse-encounter")) {
        const spec = if (generated.run) |run| blk: {
            const ice_idx = run.current_ice_index orelse break :blk @as(?CardSpec, null);
            const target_server = findServerByRunPath(generated.corp_servers.items, run.server) catch break :blk @as(?CardSpec, null);
            const ice_count = target_server.slot.ices.items.len;
            const actual_ice_idx = ice_count - 1 - ice_idx;
            const ice = target_server.slot.ices.items[actual_ice_idx];
            break :blk lookupCardSpec(ice);
        } else null;
        if (spec) |s| {
            if (s.on_prompt_choice) |handler| {
                try handler(generated, choice_text);
                return;
            }
        }
        return error.UnsupportedPrompt;
    }

    // Generic card prompt resolution: look up on_prompt_choice from card spec
    if (prompt.source_card) |sc| {
        if (lookupCardSpec(sc)) |spec| {
            if (spec.on_prompt_choice) |handler| {
                try handler(generated, choice_text);
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
        },
        .draw_card => {
            try spendClicks(generated, .corp, 1);
            try drawCard(generated, .corp);
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
            // Clear all virus counters from runner's installed programs
            for (generated.runner_rig_program.items) |*card| {
                card.virus_counter = 0;
            }
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
        },
        .draw_card => {
            try spendClicks(generated, .runner, 1);
            var draw_amount: u8 = 1;
            if (generated.turn_events.runner_click_draws == 0) {
                draw_amount += runner_installed_click_draw_bonus(generated);
            }
            try drawCards(generated, .runner, draw_amount);
            generated.turn_events.runner_click_draws += 1;
        },
        .run_any_server => {
            try beginRunAnyServerPrompt(generated);
            return;
        },
        .remove_tag => {
            try spendClicks(generated, .runner, 1);
            try spendCredits(generated, .runner, 2);
            if (generated.runner_tag) |*tag| {
                if (tag.total > 0) {
                    tag.total -= 1;
                    tag.is_tagged = tag.total > 0;
                }
            }
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
    const source_card = if (generated.corp_prompt_state) |prompt_state| prompt_state.source_card else null;
    const advancement_amount = if (source_card) |card| card.corp_play.advancement_amount else 1;
    if (advancement_amount == 1) {
        try spendClicks(generated, .corp, 1);
        try spendCredits(generated, .corp, 1);
    }
    _ = try addAdvancementCounter(generated, choice_text, advancement_amount);
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

    generated.last_scored_server_index = target.server_index;
    const scored_agenda = removeServerContentCard(generated, target.server_index, @intCast(target.card_index));
    try generated.corp_scored.append(generated.backing_allocator, scored_agenda);
    try removeServerIfEmpty(generated, target.server_index);

    generated.corp_agenda_point += agenda_points;

    // Track agenda points scored this turn (Neurospike)
    generated.turn_events.agenda_points_scored_this_turn += agenda_points;

    // Queue all score effects + event handlers into the pending effects queue.
    // They will be processed one at a time via drainPendingEffects, pausing
    // whenever a prompt is opened and resuming when it resolves.
    const allocator = generated.backing_allocator;

    if (lookupCardSpec(scored_agenda)) |spec| {
        // Queue on_score_fn (e.g. Orbital Superiority meat damage)
        if (spec.on_score_fn != null) {
            try generated.pending_effects.append(allocator, .{ .on_score_fn = scored_agenda });
        }
        // Queue on-score effects
        switch (spec.on_score.kind) {
            .gain_credits => try generated.pending_effects.append(allocator, .{ .on_score_gain_credits = spec.on_score.amount }),
            .draw_cards => try generated.pending_effects.append(allocator, .{ .on_score_draw_cards = .{ .amount = spec.on_score.amount, .card_code = spec.code } }),
            .give_runner_tag => try generated.pending_effects.append(allocator, .{ .on_score_give_runner_tag = spec.on_score.amount }),
            .gain_clicks => try generated.pending_effects.append(allocator, .{ .on_score_gain_clicks = spec.on_score.amount }),
            .rez_ice_free => try generated.pending_effects.append(allocator, .{ .on_score_rez_ice_free = scored_agenda }),
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

fn beginRunAnyServerPrompt(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const choices = try runTargetChoicesFor(allocator, .any_runnable, generated.corp_servers.items);
    if (choices.len == 0) return error.UnsupportedAbility;
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_run_any_server_basic),
        .choices = choices,
        .source_card = null,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
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
    // Assets with net_damage_on_access and adds_advancement (Urtica Cipher)
    if (card.access.adds_advancement) return true;
    // Explicitly advanceable cards (Pharos, Clearinghouse)
    if (card.advanceable) return true;
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
    generated.run = null;
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    generated.legal_actions = &.{};
    generated.decision_side = winner;
}

fn updateTerminalState(generated: *Game) void {
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


/// Fire a game event, checking identity and installed cards for matching triggers.
/// Returns true if a prompt was opened (caller should return to let prompt resolve).
fn cardMatchesEvent(code: ?u32, event: state.GameEvent) bool {
    const c = code orelse return false;
    const spec = lookupCardSpecByCode(c) orelse return false;
    const matcher = spec.event_match orelse return false;
    return matcher(event);
}

/// Process queued pending effects one at a time. Stops when an effect opens
/// a prompt (the prompt handler will call this again after resolving).
/// Returns true if a prompt was opened (caller should return).
fn drainPendingEffects(generated: *Game) !bool {
    while (generated.pending_effects.items.len > 0) {
        const effect = generated.pending_effects.orderedRemove(0);
        switch (effect) {
            .event_handler => |card_code| {
                if (lookupCardSpecByCode(card_code)) |spec| {
                    if (spec.on_event) |handler| {
                        try handler(generated);
                        if (hasActivePrompt(generated)) return true;
                    }
                }
            },
            .on_score_gain_credits => |amount| {
                generated.corp_credit += amount;
            },
            .on_score_draw_cards => |info| {
                try drawCards(generated, .corp, info.amount);
                if (info.card_code == 30070) { // Superconducting Hub
                    generated.corp_hand_size.base += 2;
                    generated.corp_hand_size.total += 2;
                }
            },
            .on_score_give_runner_tag => |amount| {
                // Add tag directly (don't use addRunnerTag which calls fireEvent recursively)
                if (generated.runner_tag == null) {
                    generated.runner_tag = .{ .base = 0, .total = amount, .is_tagged = amount > 0 };
                } else {
                    generated.runner_tag.?.total += amount;
                    generated.runner_tag.?.is_tagged = generated.runner_tag.?.total > 0;
                }
                if (amount > 0) {
                    generated.turn_events.runner_gain_tag_count += 1;
                    // Queue event handlers for runner_gain_tag (instead of calling fireEvent)
                    try collectEventHandlers(generated, .runner_gain_tag);
                }
            },
            .on_score_gain_clicks => |amount| {
                generated.corp_click += amount;
                generated.cannot_score_agendas_this_turn = true;
            },
            .on_score_rez_ice_free => |scored_agenda| {
                if (try beginRezIceFreePromptForScore(generated, scored_agenda)) return true;
            },
            .on_score_fn => |scored_agenda| {
                if (lookupCardSpec(scored_agenda)) |spec| {
                    if (spec.on_score_fn) |handler| {
                        try handler(generated, scored_agenda);
                        if (generated.game_over) return true;
                        if (hasActivePrompt(generated)) return true;
                    }
                }
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
fn resumePendingEffects(generated: *Game) !bool {
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

    // Corp identity
    if (cardMatchesEvent(generated.corp_identity.code, event)) {
        if (lookupCardSpecByCode(generated.corp_identity.code.?)) |spec| {
            if (spec.on_event != null) {
                try generated.pending_effects.append(allocator, .{ .event_handler = spec.code });
            }
        }
    }
    // Runner identity
    if (cardMatchesEvent(generated.runner_identity.code, event)) {
        if (lookupCardSpecByCode(generated.runner_identity.code.?)) |spec| {
            if (spec.on_event != null) {
                try generated.pending_effects.append(allocator, .{ .event_handler = spec.code });
            }
        }
    }
    // Runner installed hardware
    for (generated.runner_rig_hardware.items) |hw| {
        if (cardMatchesEvent(hw.code, event)) {
            if (lookupCardSpecByCode(hw.code.?)) |spec| {
                if (spec.on_event != null) {
                    try generated.pending_effects.append(allocator, .{ .event_handler = spec.code });
                }
            }
        }
    }
    // Corp installed cards in servers (upgrades/assets with event triggers)
    for (generated.corp_servers.items, 0..) |server, server_idx| {
        for (server.content.items) |card| {
            if (!card.rezzed) continue;
            if (cardMatchesEvent(card.code, event)) {
                if (lookupCardSpecByCode(card.code.?)) |spec| {
                    if (spec.on_event != null) {
                        if (spec.on_event_server_check) {
                            if (generated.last_scored_server_index != server_idx) continue;
                        }
                        try generated.pending_effects.append(allocator, .{ .event_handler = spec.code });
                    }
                }
            }
        }
    }
}

/// Collect event handlers and immediately drain (for non-scoring event sites like addRunnerTag).
fn fireEvent(generated: *Game, event: state.GameEvent) !bool {
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

    try spendCredits(generated, .runner, pending.runner_install_cost);
    var installed_card = try removeCardFromHand(generated, .runner, pending.card_index);
    installed_card.credit_counter = installed_card.installed_ability.initial_credit_counters;
    installed_card.ability_used_this_turn = false;
    installed_card.hosted_on_ice_server = @intCast(server_idx);
    installed_card.hosted_on_ice_index = @intCast(ice_idx);

    // Virus-on-install
    if (installed_card.installed_ability.virus_on_install) {
        installed_card.virus_counter += 1;
        installed_card.virus_counter += @intCast(runnerCookbookBonus(generated));
    }
    try generated.runner_rig_program.append(generated.backing_allocator, installed_card);
    generated.turn_events.programs_installed_this_turn += 1;
    if (generated.runner_memory) |*mem| {
        mem.used += pending.card.runner_install.mu_cost;
        mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
    }
    // Tranquilizer: check derez threshold immediately after install
    if (installed_card.installed_ability.trojan_derez_threshold > 0 and installed_card.virus_counter >= installed_card.installed_ability.trojan_derez_threshold) {
        if (server_idx < generated.corp_servers.items.len and ice_idx < generated.corp_servers.items[server_idx].ices.items.len) {
            generated.corp_servers.items[server_idx].ices.items[ice_idx].rezzed = false;
        }
    }
    generated.pending_install = null;
    generated.runner_prompt_state = null;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), generated);
}

fn runner_had_successful_run_last_turn(generated: *const Game) bool {
    return generated.runner_successful_run_last_turn;
}

fn runner_installed_click_draw_bonus(generated: *const Game) u8 {
    var bonus: u8 = 0;
    for (generated.runner_rig_resources.items) |card| {
        bonus += card.installed_ability.click_draw_bonus;
    }
    for (generated.runner_rig_hardware.items) |card| {
        bonus += card.installed_ability.click_draw_bonus;
    }
    return bonus;
}

fn runner_installed_hq_access_bonus(generated: *const Game) u8 {
    var bonus: u8 = 0;
    for (generated.runner_rig_hardware.items) |card| {
        bonus += card.installed_ability.hq_access_bonus;
    }
    for (generated.runner_rig_resources.items) |card| {
        bonus += card.installed_ability.hq_access_bonus;
    }
    return bonus;
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

fn canBreakIceType(breaker: state.CardInstance, ice: state.CardInstance) bool {
    if (hasSubtype(breaker, "AI")) return true;
    if (hasSubtype(breaker, "Fracter") and hasSubtype(ice, "Barrier")) return true;
    if (hasSubtype(breaker, "Killer") and hasSubtype(ice, "Sentry")) return true;
    if (hasSubtype(breaker, "Decoder") and hasSubtype(ice, "Code Gate")) return true;
    return false;
}

fn effectiveStrength(card: state.CardInstance) u8 {
    return card.current_strength orelse card.strength orelse 0;
}

fn effectiveIceStrength(card: state.CardInstance, server_path: []const []const u8, ice_strength_modifier: i8) u8 {
    const base = card.strength orelse 0;
    var bonus: u8 = 0;
    // Palisade: +N strength on remote servers
    if (card.remote_strength_bonus > 0 and isRemoteServerPath(server_path)) {
        bonus += card.remote_strength_bonus;
    }
    // Pharos: +N strength at M+ advancement counters
    if (card.advancement_strength_threshold > 0 and card.advancement_counter >= card.advancement_strength_threshold) {
        bonus += card.advancement_strength_bonus;
    }
    const total = @as(i16, base) + @as(i16, bonus) + @as(i16, ice_strength_modifier);
    return if (total > 0) @intCast(total) else 0;
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
                try installChoicesForCard(allocator, card.install.kind),
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
    installed.credit_counter = installed.installed_ability.initial_credit_counters;
    installed.ability_used_this_turn = false;
    try installCard(generated, installed, choice_text);

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
    switch (accessed.access.kind) {
        .steal_agenda => try applyStealAgendaChoice(generated, accessed, choice_text),
        .net_damage_on_access => return error.UnsupportedAccessTarget,
        .tax_or_etr => return error.UnsupportedAccessTarget,
        .corp_pay_etr => return error.UnsupportedAccessTarget,
        .none => return error.UnsupportedAccessTarget,
    }
}

fn applyTrashOnAccess(generated: *Game, accessed: state.CardInstance) !void {
    const spec = lookupCardSpec(accessed) orelse return error.UnsupportedAccessTarget;
    const trash_cost = spec.trash_cost orelse return error.UnsupportedAccessTarget;
    try spendCredits(generated, .runner, trash_cost);
    // Fire runner_trash_corp_card event (Loup trigger)
    generated.turn_events.runner_trash_corp_card_count += 1;
    if (try fireEvent(generated, .runner_trash_corp_card)) return;
    // AMAZE Amusements: if trashed during a run, record pending tags
    if (accessed.installed_ability.tags_on_agenda_steal_from_server > 0) {
        if (generated.run) |*mutable_run| {
            mutable_run.tags_pending_on_steal += accessed.installed_ability.tags_on_agenda_steal_from_server;
        }
    }
    const run = generated.run orelse return error.NoRunInProgress;
    try removeAccessedCard(generated, run);
    // Move to corp discard
    try appendDiscardCard(generated, .corp, accessed);
    try finishAccessCard(generated);
}

fn finishAccessCard(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &generated.run.?;
    generated.runner_prompt_state = null;

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

    try completeRunAfterAccess(generated);
}

fn applyStealAgendaChoice(
    generated: *Game,
    accessed: state.CardInstance,
    choice_text: []const u8,
) !void {
    if (!std.mem.eql(u8, choice_text, "Steal")) return error.UnsupportedChoice;

    const allocator = generated.arena.allocator();
    const run = generated.run orelse return error.NoRunInProgress;

    generated.runner_agenda_point += accessed.agenda_points orelse return error.MissingAgendaPoints;
    // Track that an agenda was stolen during this run (for AMAZE Amusements)
    if (generated.run) |*mutable_run| {
        mutable_run.did_steal_this_run = true;
    }
    _ = try fireEvent(generated, .agenda_stolen);
    try removeAccessedCard(generated, run);

    // On-steal agenda effects
    if (lookupCardSpec(accessed)) |spec| {
        switch (spec.on_steal.kind) {
            .rez_ice_free => {
                if (try beginRezIceFreePrompt(generated, accessed)) return;
            },
            .give_runner_tag => {
                _ = try addRunnerTag(generated, spec.on_steal.amount);
            },
            .none => {},
            else => {},
        }
    }

    const is_central = isCentralRunServer(run.server);
    if (is_central) {
        try continueOrCompleteAfterSteal(generated, true);
        return;
    }

    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "waiting"),
        .choices = &.{},
        .source_card = null,
    };
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_access_cleanup),
        .choices = try singleStringChoice(allocator, "Done"),
        .source_card = accessed,
    };
    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(
        allocator,
        .corp,
        generated.corp_prompt_state.?,
    );
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

fn applyRezIceFreeChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    if (!try rezInstalledIceByTitle(generated, choice_text)) return error.UnsupportedChoice;
    try continueOrCompleteAfterSteal(generated, false);
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
        if (generated.runner_click < ability.click_cost) return error.InsufficientClicks;

        // Spend clicks
        generated.runner_click -= ability.click_cost;

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

            // Validate subtype matching
            if (!canBreakIceType(icebreaker, ice.*)) return error.CannotBreakIceType;
            // Validate strength (ICE strength includes remote bonus)
            const ice_str = effectiveIceStrength(ice.*, run.server, run.ice_strength_modifier);
            if (effectiveStrength(icebreaker) < ice_str) return error.InsufficientStrength;

            // Check which subroutine to break based on subroutine_index
            const sub_idx: u8 = switch (subroutine_index.kind) {
                .number => @intCast(subroutine_index.number orelse return error.InvalidSubroutine),
                else => return error.InvalidSubroutine,
            };

            if (sub_idx >= ice.subroutines.len) return error.InvalidSubroutine;

            // Check if we have enough credits
            if (generated.runner_credit < icebreaker.installed_ability.credit_cost) return error.InsufficientCredits;

            // Spend credits
            generated.runner_credit -= icebreaker.installed_ability.credit_cost;

            // Mark subroutine as broken
            ice.broken_subroutines |= (@as(u16, 1) << @as(u4, @intCast(sub_idx)));

            // Track that this breaker was used (for Mayfly end-of-run trash)
            generated.runner_rig_program.items[icebreaker_idx].used_break_this_run = true;
        } else {
            return error.NotAnIcebreaker;
        }
    }

    // Generate new legal actions - still in encounter, can break more or continue
    const allocator = generated.arena.allocator();
    generated.decision_side = .runner;
    generated.legal_actions = try encounterActionsForState(allocator, generated, ice.*);
}

fn applyRunnerAbility(generated: *Game, action: state.LegalAction) !void {
    // Bioroid break: spend clicks to break subroutines on the encountered ICE
    const run = generated.run orelse return error.NoRunInProgress;
    if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;

    const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
    const target_server = try findMutableServerByRunPath(generated.corp_servers.items, run.server);
    const server = &generated.corp_servers.items[target_server.index];
    const ice_count = server.ices.items.len;
    if (current_ice_idx >= ice_count) return error.InvalidIceIndex;
    const actual_ice_idx = ice_count - 1 - current_ice_idx;
    var ice = &server.ices.items[actual_ice_idx];

    // Find the bioroid ability on the ICE
    const ice_title = action.card_title orelse return error.NoBioroidAbility;
    if (!std.mem.eql(u8, ice_title, ice.title)) return error.NoBioroidAbility;

    var found_ability: ?state.RunnerAbilitySpec = null;
    for (ice.runner_abilities) |ability| {
        if (ability.kind == .bioroid_break) {
            found_ability = ability;
            break;
        }
    }
    const ability = found_ability orelse return error.NoBioroidAbility;

    // Pay click cost
    if (generated.runner_click < ability.click_cost) return error.InsufficientClicks;
    generated.runner_click -= ability.click_cost;

    // Break first break_quantity unbroken subroutines
    var broken_count: u8 = 0;
    for (ice.subroutines, 0..) |_, sub_idx| {
        if (broken_count >= ability.break_quantity) break;
        const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(sub_idx))) != 0;
        if (!is_broken) {
            ice.broken_subroutines |= (@as(u16, 1) << @as(u4, @intCast(sub_idx)));
            broken_count += 1;
        }
    }

    // Regenerate encounter actions
    const allocator = generated.arena.allocator();
    generated.decision_side = .runner;
    generated.legal_actions = try encounterActionsForState(allocator, generated, ice.*);
}

fn removeAccessedCard(
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

fn applyAccessCleanupChoice(
    generated: *Game,
    choice_text: []const u8,
) !void {
    const accessed = (if (generated.corp_prompt_state) |ps| ps.source_card else null) orelse return error.MissingSourceCard;
    switch (accessed.access.kind) {
        .steal_agenda => {
            if (!std.mem.eql(u8, choice_text, "Done")) return error.UnsupportedChoice;
            try completeRunAfterAccess(generated);
        },
        .net_damage_on_access => return error.UnsupportedChoice,
        .tax_or_etr => return error.UnsupportedChoice,
        .corp_pay_etr => return error.UnsupportedChoice,
        .none => return error.UnsupportedChoice,
    }
}

fn playCorpOperation(
    generated: *Game,
    card_index: u8,
    card: state.CardInstance,
) !void {
    const allocator = generated.arena.allocator();
    try spendClicks(generated, .corp, 1);
    try spendCredits(generated, .corp, card.cost orelse 0);
    _ = try removeCardFromHand(generated, .corp, card_index);

    switch (card.corp_play.kind) {
        .gain_credits => {
            generated.corp_credit += card.corp_play.gain_credits;
            try drawCards(generated, .corp, card.corp_play.draw_cards);
        },
        .advance_installed => {
            const choices = if (card.corp_play.not_installed_this_turn)
                try installedNotThisTurnChoices(allocator, generated.corp_servers.items)
            else
                try installedCardChoices(allocator, generated.corp_servers.items);
            if (choices.len == 0) {
                generated.decision_side = .corp;
                generated.legal_actions = try corpOpeningActionsForState(allocator, generated);
                return;
            }
            generated.corp_prompt_state = .{
                .prompt_type = try allocator.dupe(u8, prompt_advance_installed),
                .choices = choices,
                .source_card = card,
            };
            generated.decision_side = .corp;
            generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
            return;
        },
        .custom => {
            const spec = lookupCardSpec(card) orelse return error.UnsupportedOperation;
            if (spec.on_play) |handler| {
                try handler(generated, card);
            } else {
                return error.UnsupportedOperation;
            }
            return;
        },
        .no_op => {},
        .none => return error.UnsupportedOperation,
    }

    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(allocator, generated);
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

    switch (card.runner_play.kind) {
        .gain_credits => try playRunnerGainCredits(generated, card_index, card),
        .choose_run_target => try playRunnerChooseRunTarget(generated, card_index, card),
        .custom => {
            const spec = lookupCardSpec(card) orelse return error.UnsupportedCardType;
            const handler = spec.on_play orelse return error.UnsupportedCardType;
            // Common event play flow: spend click, pay cost, remove from hand, discard
            try spendClicks(generated, .runner, 1);
            try spendCredits(generated, .runner, card.cost orelse 0);
            _ = try removeCardFromHand(generated, .runner, card_index);
            try appendDiscardCard(generated, .runner, card);
            try handler(generated, card);
        },
        .none => return error.UnsupportedCardType,
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

    if (card_index >= generated.runner_hand.items.len) return error.InvalidCardIndex;

    const card = generated.runner_hand.items[card_index];
    if (card.runner_install.kind == .none) return error.UnsupportedRunnerInstall;

    try spendClicks(generated, .runner, 1);
    var install_cost: u16 = card.cost orelse 0;
    if (card.runner_install.install_cost_reduction_if_successful_run > 0 and generated.runner_successful_run_this_turn) {
        install_cost = if (install_cost >= card.runner_install.install_cost_reduction_if_successful_run)
            install_cost - card.runner_install.install_cost_reduction_if_successful_run
        else
            0;
    }
    // DZMZ Optimizer: first program install each turn costs N less
    if (card.runner_install.kind == .program) {
        const dzmz_discount = runnerInstalledFirstProgramDiscount(generated);
        install_cost = if (install_cost >= dzmz_discount) install_cost - dzmz_discount else 0;
    }

    // Trojan: install on ICE — show ICE selection prompt
    if (card.installed_ability.is_trojan) {
        const allocator = generated.arena.allocator();
        // Build list of all installed ICE as choices
        var choices: std.ArrayList(state.PromptChoice) = .empty;
        defer choices.deinit(allocator);
        for (generated.corp_servers.items, 0..) |server, si| {
            for (server.ices.items, 0..) |ice, ii| {
                const label = try std.fmt.allocPrint(allocator, "{d}|{d}|{s}", .{ si, ii, ice.title });
                try choices.append(allocator, .{ .kind = .string, .text = label, .card = .{ .title = ice.title, .side = .corp, .index = @intCast(ii) } });
            }
        }
        if (choices.items.len == 0) {
            // No ICE to host on — can't install trojan
            // Refund click (already spent)
            return error.UnsupportedRunnerInstall;
        }
        generated.pending_install = .{
            .card = card,
            .card_index = card_index,
            .runner_install_cost = install_cost,
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

    // For programs, check MU BEFORE paying credits (matches Clojure's runner-install-pay flow).
    // If MU would overflow, show the trash prompt first; install completes after resolution.
    if (card.runner_install.kind == .program) {
        generated.pending_install = .{
            .card = card,
            .card_index = card_index,
            .runner_install_cost = install_cost,
        };
        if (try beginMuOverflowPromptWithExtra(generated, card.runner_install.mu_cost)) return;
        generated.pending_install = null;
    }

    try completeRunnerInstall(generated, card_index, card, install_cost);
}

fn completeRunnerInstall(generated: *Game, card_index: u8, card: state.CardInstance, install_cost: u16) !void {
    const allocator = generated.arena.allocator();
    try spendCredits(generated, .runner, install_cost);

    var installed_card = try removeCardFromHand(generated, .runner, card_index);
    installed_card.credit_counter = installed_card.installed_ability.initial_credit_counters;
    installed_card.ability_used_this_turn = false;
    try appendRunnerInstalledCard(generated, installed_card);

    if (card.runner_install.kind == .program) {
        generated.turn_events.programs_installed_this_turn += 1;
        if (generated.runner_memory) |*mem| {
            mem.used += card.runner_install.mu_cost;
            mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
        }
        // Virus-on-install: place initial virus counter (Fermenter, Botulus, Tranquilizer)
        if (installed_card.installed_ability.virus_on_install) {
            // Find the card we just installed and add virus counter
            if (generated.runner_rig_program.items.len > 0) {
                var prog = &generated.runner_rig_program.items[generated.runner_rig_program.items.len - 1];
                prog.virus_counter += 1;
                // Cookbook: bonus virus counter on virus install
                prog.virus_counter += runnerCookbookBonus(generated);
            }
        }
    }

    generated.pending_install = null;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
}

fn playRunnerGainCredits(
    generated: *Game,
    card_index: u8,
    card: state.CardInstance,
) !void {
    const allocator = generated.arena.allocator();
    try spendClicks(generated, .runner, 1);
    try spendCredits(generated, .runner, card.cost orelse 0);
    _ = try removeCardFromHand(generated, .runner, card_index);
    try appendDiscardCard(generated, .runner, card);
    try spendClicks(generated, .runner, card.runner_play.lose_clicks);
    generated.runner_credit += card.runner_play.gain_credits;
    try drawCards(generated, .runner, card.runner_play.draw_cards);

    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(
        allocator,
        generated,
    );
}

fn playRunnerChooseRunTarget(
    generated: *Game,
    card_index: u8,
    card: state.CardInstance,
) !void {
    const allocator = generated.arena.allocator();
    try spendClicks(generated, .runner, 1);
    try spendCredits(generated, .runner, card.cost orelse 0);
    _ = try removeCardFromHand(generated, .runner, card_index);
    try appendDiscardCard(generated, .runner, card);
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, prompt_run_target),
        .choices = try runTargetChoicesFor(allocator, card.runner_play.run_target_kind, generated.corp_servers.items),
        .source_card = card,
    };

    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
}

fn applyRunnerRunTargetChoice(
    generated: *Game,
    server: []const u8,
) !void {
    const source_card = (if (generated.runner_prompt_state) |ps| ps.source_card else null) orelse return error.MissingSourceCard;
    if (source_card.runner_play.kind != .choose_run_target) return error.UnsupportedPrompt;
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
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, generated.run, generated);
}

fn applyRunFromAbility(
    generated: *Game,
    server: []const u8,
    source_card: ?state.CardInstance,
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
        .source_card_code = if (source_card) |sc| sc.code else null,
    };
    generated.decision_side = .corp;
    generated.legal_actions = try continueActions(allocator, .corp);
}

fn applyInstalledAbility(
    generated: *Game,
    side: state.Side,
    server_name: ?[]const u8,
    card_index_opt: ?u8,
    installed_ability: state.InstalledAbilityKind,
) !void {
    if (generated.end_turn) return error.TurnNotStarted;
    if (generated.active_player != side) return error.NotActivePlayer;
    const allocator = generated.arena.allocator();
    const card_index = card_index_opt orelse return error.MissingCardIndex;

    switch (side) {
        .runner => {
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

            // Leech: virus ICE strength reduction during encounter (kind=.none but has virus ability)
            if (installed_ability == .none and card.installed_ability.virus_ice_strength_reduction > 0 and card.virus_counter > 0) {
                if (generated.run == null) return error.NoRunInProgress;
                card.virus_counter -= 1;
                generated.run.?.ice_strength_modifier -= @intCast(card.installed_ability.virus_ice_strength_reduction);
                // Regenerate encounter actions
                const run = generated.run.?;
                const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                const target_server = try findMutableServerByRunPath(generated.corp_servers.items, run.server);
                const server = &generated.corp_servers.items[target_server.index];
                const ice_count = server.ices.items.len;
                const actual_ice_idx = ice_count - 1 - current_ice_idx;
                const ice = server.ices.items[actual_ice_idx];
                generated.decision_side = .runner;
                generated.legal_actions = try encounterActionsForState(allocator, generated, ice);
                return;
            }

            // Pump strength is a separate ability from the card's primary installed_ability.kind
            // (icebreakers have .break_subroutine as primary but also support pump via pump_ability)
            if (card.installed_ability.kind != installed_ability and
                !(installed_ability == .pump_strength and card.pump_ability.kind == .pump_strength))
            {
                return error.UnsupportedAbility;
            }
            if (card.installed_ability.once_per_turn and card.ability_used_this_turn) return error.AbilityAlreadyUsed;

            switch (installed_ability) {
                .take_credits => {
                    try spendClicks(generated, .runner, card.installed_ability.click_cost);
                    if (card.installed_ability.takes_all_credits) {
                        // Pennyshaver: gain 1 + all hosted credits
                        const total = @as(u16, card.credit_counter) + 1;
                        generated.runner_credit += total;
                        card.credit_counter = 0;
                    } else {
                        const amount = @min(card.credit_counter, card.installed_ability.take_credits_amount);
                        generated.runner_credit += amount;
                        card.credit_counter -= amount;
                    }
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
                                if (generated.runner_memory) |*mem| {
                                    const mu = trashed.runner_install.mu_cost;
                                    if (mem.used >= mu) mem.used -= mu else mem.used = 0;
                                    mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
                                }
                            },
                            .hardware => {
                                const hardware_index = card_index - @as(u8, @intCast(generated.runner_rig_resources.items.len + generated.runner_rig_program.items.len));
                                const trashed = generated.runner_rig_hardware.orderedRemove(hardware_index);
                                try appendDiscardCard(generated, .runner, trashed);
                            },
                        }
                    }
                },
                .place_credits => {
                    try spendClicks(generated, .runner, card.installed_ability.click_cost);
                    card.credit_counter += card.installed_ability.place_credits_amount;
                    card.ability_used_this_turn = true;
                },
                .break_subroutine => {
                    // Activate break ability: pay cost, then open sub selection prompt
                    const run = generated.run orelse return error.NoRunInProgress;
                    if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;

                    const program_index = card_index - @as(u8, @intCast(generated.runner_rig_resources.items.len));
                    var icebreaker = &generated.runner_rig_program.items[program_index];

                    const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                    const target_server = try findMutableServerByRunPath(generated.corp_servers.items, run.server);
                    const server = &generated.corp_servers.items[target_server.index];
                    const ice_count = server.ices.items.len;
                    if (current_ice_idx >= ice_count) return error.InvalidIceIndex;
                    const actual_ice_idx = ice_count - 1 - current_ice_idx;
                    const ice = &server.ices.items[actual_ice_idx];

                    if (!isIcebreaker(icebreaker.*)) return error.NotAnIcebreaker;
                    if (icebreaker.installed_ability.kind != .break_subroutine) return error.UnsupportedAbility;
                    if (!canBreakIceType(icebreaker.*, ice.*)) return error.CannotBreakIceType;
                    const ice_str = effectiveIceStrength(ice.*, run.server, run.ice_strength_modifier);
                    if (effectiveStrength(icebreaker.*) < ice_str) return error.InsufficientStrength;

                    // Pay cost for this activation (Marjanah: discount if successful run this turn)
                    var credit_cost = icebreaker.installed_ability.credit_cost;
                    if (icebreaker.installed_ability.break_cost_reduction_if_successful_run > 0 and generated.runner_successful_run_this_turn) {
                        credit_cost = if (credit_cost >= icebreaker.installed_ability.break_cost_reduction_if_successful_run)
                            credit_cost - icebreaker.installed_ability.break_cost_reduction_if_successful_run
                        else
                            0;
                    }
                    if (generated.runner_credit < credit_cost) return error.InsufficientCredits;
                    generated.runner_credit -= credit_cost;

                    // Track breaker usage (Mayfly)
                    icebreaker.used_break_this_run = true;

                    // Open sub selection prompt
                    try openBreakSubPrompt(generated, ice, icebreaker.*, 0);
                    return;
                },
                .pump_strength => {
                    // Pump strength during encounter
                    const run = generated.run orelse return error.NoRunInProgress;
                    if (!std.mem.eql(u8, run.phase, "encounter-ice")) return error.UnsupportedAbility;

                    // card_index is the combined rig index; convert to program index
                    const program_index = card_index - @as(u8, @intCast(generated.runner_rig_resources.items.len));
                    var icebreaker = &generated.runner_rig_program.items[program_index];

                    // Spend credits for pump
                    if (generated.runner_credit < icebreaker.pump_ability.credit_cost) return error.InsufficientCredits;
                    generated.runner_credit -= icebreaker.pump_ability.credit_cost;

                    // Boost strength
                    const current = effectiveStrength(icebreaker.*);
                    const pump_amount = if (icebreaker.pump_ability.pump_is_variable)
                        // Unity: pump = number of installed icebreakers
                        @as(u8, @intCast(generated.runner_rig_program.items.len))
                    else
                        icebreaker.pump_ability.pump_strength_amount;
                    icebreaker.current_strength = current + pump_amount;

                    // Regenerate encounter actions
                    const current_ice_idx = run.current_ice_index orelse return error.NoIceEncountered;
                    const target_server = try findMutableServerByRunPath(generated.corp_servers.items, run.server);
                    const server = &generated.corp_servers.items[target_server.index];
                    const ice_count = server.ices.items.len;
                    if (current_ice_idx >= ice_count) return error.InvalidIceIndex;
                    const actual_ice_idx = ice_count - 1 - current_ice_idx;
                    const ice = server.ices.items[actual_ice_idx];
                    generated.decision_side = .runner;
                    generated.legal_actions = try encounterActionsForState(allocator, generated, ice);
                    return;
                },
                .run_central => {
                    try spendClicks(generated, .runner, card.installed_ability.click_cost);
                    card.ability_used_this_turn = true;

                    // Open central server choice prompt (filtered by not-run-this-turn)
                    const choices = try centralNotRunThisTurnChoices(allocator, generated.turn_events);
                    if (choices.len == 0) return error.UnsupportedAbility;
                    generated.runner_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, prompt_run_central),
                        .choices = choices,
                        .source_card = card.*,
                    };
                    generated.decision_side = .runner;
                    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
                    return;
                },
                .run_rd => {
                    try spendClicks(generated, .runner, card.installed_ability.click_cost);
                    card.ability_used_this_turn = true;
                    // Conduit: directly run R&D, no prompt needed
                    try applyRunFromAbility(generated, "R&D", card.*);
                    return;
                },
                .trash_for_virus_credits => {
                    // Fermenter: click + trash self, gain N credits per virus counter
                    try spendClicks(generated, .runner, card.installed_ability.click_cost);
                    const gain = @as(u16, card.virus_counter) * @as(u16, card.installed_ability.trash_for_virus_credits);
                    generated.runner_credit += gain;
                    // Trash the program
                    const program_index = card_index - @as(u8, @intCast(generated.runner_rig_resources.items.len));
                    const trashed = generated.runner_rig_program.orderedRemove(program_index);
                    try appendDiscardCard(generated, .runner, trashed);
                    if (generated.runner_memory) |*mem| {
                        const mu = trashed.runner_install.mu_cost;
                        if (mem.used >= mu) mem.used -= mu else mem.used = 0;
                        mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
                    }
                },
                .start_of_turn_credits => return error.UnsupportedAbility, // auto-trigger, not a click action
                .trash_for_damage => return error.UnsupportedAbility, // corp-only
                .remove_from_game_shuffle => return error.UnsupportedAbility, // corp-only
                .none => return error.UnsupportedAbility,
            }

            generated.decision_side = .runner;
            generated.legal_actions = try runnerOpeningActionsForState(
                allocator,
                generated,
            );
        },
        .corp => {
            const server_display = server_name orelse return error.MissingServer;
            const server_index = try findServerIndexByDisplayName(generated.corp_servers.items, server_display);
            if (server_index >= generated.corp_servers.items.len) return error.UnknownServer;
            if (card_index >= generated.corp_servers.items[server_index].content.items.len) return error.InvalidCardIndex;
            var card = &generated.corp_servers.items[server_index].content.items[card_index];
            if (card.installed_ability.kind != installed_ability) return error.UnsupportedAbility;
            if (card.installed_ability.once_per_turn and card.ability_used_this_turn) return error.AbilityAlreadyUsed;

            switch (installed_ability) {
                .take_credits => {
                    try spendClicks(generated, .corp, card.installed_ability.click_cost);
                    const amount = @min(card.credit_counter, card.installed_ability.take_credits_amount);
                    generated.corp_credit += amount;
                    card.credit_counter -= amount;
                    card.ability_used_this_turn = true;

                    if (card.installed_ability.trash_on_empty and card.credit_counter == 0) {
                        // Nico Campaign: draw cards before trashing
                        if (card.installed_ability.draw_on_empty > 0) {
                            try drawCards(generated, .corp, card.installed_ability.draw_on_empty);
                        }
                        const trashed = generated.corp_servers.items[server_index].content.orderedRemove(card_index);
                        try appendDiscardCard(generated, .corp, trashed);
                    }
                },
                .trash_for_damage => {
                    // Clearinghouse: click + trash self, do 1 meat damage per advancement counter
                    try spendClicks(generated, .corp, card.installed_ability.click_cost);
                    const damage = card.advancement_counter;
                    // Trash the card from the server
                    const trashed = generated.corp_servers.items[server_index].content.orderedRemove(card_index);
                    try appendDiscardCard(generated, .corp, trashed);
                    // Remove server if empty
                    try removeServerIfEmpty(generated, server_index);
                    // Do meat damage (mechanically same as net damage)
                    if (damage > 0) {
                        try trashRandomRunnerHandCards(generated, damage);
                        updateTerminalState(generated);
                        if (generated.game_over) return;
                    }
                },
                .remove_from_game_shuffle => {
                    // Spin Doctor: remove from game, shuffle up to 2 from Archives into R&D
                    // Remove card from server (remove from game, not to Archives)
                    _ = generated.corp_servers.items[server_index].content.orderedRemove(card_index);
                    try removeServerIfEmpty(generated, server_index);
                    // Shuffle up to 2 cards from Archives into R&D (auto-pick first 2)
                    var shuffled: u8 = 0;
                    while (shuffled < 2 and generated.corp_discard.items.len > 0) : (shuffled += 1) {
                        const removed = generated.corp_discard.orderedRemove(0);
                        try generated.corp_deck.append(generated.backing_allocator, removed);
                    }
                    if (shuffled > 0) {
                        try shuffleDeck(generated, .corp);
                    }
                },
                .place_credits, .break_subroutine, .pump_strength, .run_central, .run_rd, .start_of_turn_credits, .trash_for_virus_credits => return error.UnsupportedAbility,
                .none => return error.UnsupportedAbility,
            }

            generated.decision_side = .corp;
            generated.legal_actions = try corpOpeningActionsForState(allocator, generated);
        },
    }
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

    // Handle movement phase jack-out window
    if (std.mem.eql(u8, run.*.?.phase, "movement") and run.*.?.jack_out_available) {
        if (run.*.?.no_action == null) {
            // First pass - if runner, they had chance to jack out
            // Now corp gets to pass
            run.*.?.no_action = side;
            generated.decision_side = otherSide(side);
            generated.legal_actions = try continueActionsForRun(allocator, otherSide(side), run.*);
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

fn maybeOpenRezWindowPrompt(generated: *Game) !bool {
    if (generated.corp_prompt_state) |prompt_state| {
        if (!std.mem.eql(u8, prompt_state.prompt_type, "run")) {
            return false;
        }
    } else {
        return false;
    }
    if (generated.run == null) {
        return false;
    }
    const target = try currentApproachedIce(generated) orelse {
        return false;
    };
    if (target.ice.rezzed) {
        return false;
    }
    if (generated.corp_credit < (target.ice.cost orelse 0)) {
        return false;
    }

    generated.corp_prompt_state = .{
        .prompt_type = try generated.arena.allocator().dupe(u8, prompt_rez_window),
        .choices = try rezWindowChoices(generated.arena.allocator()),
        .source_card = target.ice,
    };
    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(
        generated.arena.allocator(),
        .corp,
        generated.corp_prompt_state.?,
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
        const run = generated.run orelse return error.NoRunInProgress;
        const adjusted_cost = rez_cost + run.rez_cost_bonus;
        try spendCredits(generated, .corp, adjusted_cost);
        generated.corp_servers.items[target.server_index].ices.items[target.ice_index].rezzed = true;
        // Ping: give runner tags when rezzed during a run
        if (target.ice.tag_on_rez > 0) {
            if (try addRunnerTag(generated, target.ice.tag_on_rez)) return;
        }
    } else if (!std.mem.eql(u8, choice_text, "No rez")) {
        return error.UnsupportedChoice;
    }

    // Restore "run" prompt state (run is still in progress)
    const allocator = generated.arena.allocator();
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "run"),
        .choices = &.{},
        .source_card = null,
    };
    const run = &generated.run;
    if (run.* == null) return error.NoRunInProgress;
    run.*.?.no_action = .corp;
    generated.decision_side = .runner;
    generated.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
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

    // On-rez trigger (Spin Doctor: draw 2)
    if (card.code) |code| {
        if (lookupCardSpecByCode(code)) |spec| {
            if (spec.on_rez) |handler| {
                try handler(generated);
            }
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
    if (generated.runner_prompt_state) |runner_prompt| {
        if (!std.mem.eql(u8, runner_prompt.prompt_type, "waiting") and !std.mem.eql(u8, runner_prompt.prompt_type, "run")) {
            if (side != .corp) return error.InvalidAction;
            generated.corp_prompt_state = null;
            generated.decision_side = .runner;
            generated.legal_actions = try promptChoiceActions(allocator, .runner, runner_prompt);
            return;
        }
    }

    if (run.no_action == null) {
        run.no_action = side;
        generated.decision_side = otherSide(side);
        generated.legal_actions = try continueActionsForRun(allocator, otherSide(side), run.*);
        return;
    }

    if (run.no_action.? == side) return error.InvalidAction;
    run.no_action = null;
    if (try prepareNextAccess(generated)) {
        run.phase = try allocator.dupe(u8, "success");
        generated.decision_side = .corp;
        generated.legal_actions = try continueActionsForRun(allocator, .corp, run.*);
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
            // Reset broken_subroutines and ice_strength_modifier for this encounter
            generated.corp_servers.items[target.server_index].ices.items[target.ice_index].broken_subroutines = 0;
            run.ice_strength_modifier = 0;

            // Echelon: set current_strength = base + installed icebreaker count
            for (generated.runner_rig_program.items) |*prog| {
                if (prog.installed_ability.strength_per_icebreaker) {
                    var icebreaker_count: u8 = 0;
                    for (generated.runner_rig_program.items) |p| {
                        if (isIcebreaker(p)) icebreaker_count += 1;
                    }
                    prog.current_strength = (prog.strength orelse 0) + icebreaker_count;
                }
            }

            // Check for on-encounter abilities (e.g., Funhouse)
            const ice = generated.corp_servers.items[target.server_index].ices.items[target.ice_index];
            if (lookupCardSpec(ice)) |spec| {
                if (spec.on_encounter) |handler| {
                    try handler(generated, &ice);
                    return;
                }
            }

            generated.decision_side = .runner;
            generated.legal_actions = try encounterActionsForState(allocator, generated, ice);
            return;
        }
    }

    // Unrezzed or no ice - move to movement
    if (run.position > 0) run.position -= 1;
    run.phase = try allocator.dupe(u8, "movement");
    run.jack_out_available = true;
    run.no_action = null;
    generated.decision_side = .runner;
    generated.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
}

const prompt_break_sub = "break-sub";

fn subroutineLabel(allocator: std.mem.Allocator, sub: state.SubroutineSpec, idx: usize) ![]const u8 {
    return switch (sub.kind) {
        .end_the_run => std.fmt.allocPrint(allocator, "End the run", .{}),
        .do_net_damage => std.fmt.allocPrint(allocator, "Do {d} net damage", .{sub.amount}),
        .do_brain_damage => std.fmt.allocPrint(allocator, "Do {d} brain damage", .{sub.amount}),
        .tag_runner => std.fmt.allocPrint(allocator, "Give the Runner 1 tag", .{}),
        .give_runner_tags => std.fmt.allocPrint(allocator, "Give the Runner {d} tags", .{sub.amount}),
        .runner_loses_credits => std.fmt.allocPrint(allocator, "Runner loses {d} [Credits]", .{sub.amount}),
        .give_tag_or_pay_credits => std.fmt.allocPrint(allocator, "Sub {d}", .{idx}),
        .corp_gains_credits => std.fmt.allocPrint(allocator, "Corp gains {d} [Credits]", .{sub.amount}),
        .install_ice_from_hq_archives => std.fmt.allocPrint(allocator, "Install a card from HQ or Archives", .{}),
        .trace_tag => std.fmt.allocPrint(allocator, "Trace[{d}] - Give the Runner 1 tag", .{sub.base_trace}),
        .do_net_damage_conditional_etr => std.fmt.allocPrint(allocator, "Sub {d}", .{idx}),
        .runner_loses_credits_or_etr => std.fmt.allocPrint(allocator, "Sub {d}", .{idx}),
        .do_net_damage_then_jack_out => std.fmt.allocPrint(allocator, "Sub {d}", .{idx}),
        .trash_program_or_etr => std.fmt.allocPrint(allocator, "Trash 1 program or end the run", .{}),
        .none => std.fmt.allocPrint(allocator, "Sub {d}", .{idx}),
    };
}

fn openBreakSubPrompt(
    generated: *Game,
    ice: *state.CardInstance,
    breaker: state.CardInstance,
    subs_selected: u8,
) !void {
    const allocator = generated.arena.allocator();
    const break_count = @max(@as(u8, 1), breaker.installed_ability.break_subroutine_count);

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
    generated.decision_side = .runner;
    generated.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
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
                return;
            },
            .do_net_damage => {
                const damage = sub.amount;
                try trashRandomRunnerHandCards(generated, damage);
                updateTerminalState(generated);
                if (generated.game_over) return;
            },
            .do_brain_damage => {
                const damage = sub.amount;
                generated.runner_brain_damage += damage;
                try trashRandomRunnerHandCards(generated, damage);
                updateTerminalState(generated);
                if (generated.game_over) return;
            },
            .tag_runner => {
                _ = try addRunnerTag(generated, 1);
            },
            .trace_tag => {
                const run = &(generated.run orelse return error.NoRunInProgress);
                run.pending_subroutine = .{
                    .server_index = @intCast(server_index),
                    .ice_index = @intCast(ice_index),
                    .subroutine_index = @intCast(idx + 1),
                };
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                try choices.append(allocator, stringChoice("Take 1 tag"));
                if (generated.runner_credit >= sub.base_trace) {
                    const text = try std.fmt.allocPrint(allocator, "Pay {d} [Credits]", .{sub.base_trace});
                    try choices.append(allocator, stringChoice(text));
                }
                generated.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "trace"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = ice,
                };
                generated.decision_side = .runner;
                generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
                return;
            },
            .give_runner_tags => {
                _ = try addRunnerTag(generated, sub.amount);
            },
            .runner_loses_credits => {
                const loss = @min(sub.amount, @as(u8, @intCast(generated.runner_credit)));
                generated.runner_credit -= loss;
            },
            .corp_gains_credits => {
                generated.corp_credit += sub.amount;
            },
            .do_net_damage_conditional_etr => {
                // Diviner: do N net damage, if trashed card has odd cost, end the run
                const damage = sub.amount;
                const hand_before = generated.runner_hand.items.len;
                try trashRandomRunnerHandCards(generated, damage);
                updateTerminalState(generated);
                if (generated.game_over) return;
                // Check if a card was trashed and if it has odd cost
                if (generated.runner_hand.items.len < hand_before) {
                    // The last trashed card went to discard
                    if (generated.runner_discard.items.len > 0) {
                        const trashed_card = generated.runner_discard.items[generated.runner_discard.items.len - 1];
                        const card_cost = trashed_card.cost orelse 0;
                        if (card_cost % 2 == 1) {
                            // Odd cost - end the run
                            endOfRunCleanup(generated);
                            generated.run = null;
                            generated.corp_prompt_state = null;
                            generated.runner_prompt_state = null;
                            generated.runner_run_credit = 0;
                            generated.decision_side = .runner;
                            generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
                            return;
                        }
                    }
                }
            },
            .runner_loses_credits_or_etr => {
                // Whitespace sub2: end the run if runner has N credits or less
                const total_credits = generated.runner_credit + generated.runner_run_credit;
                if (total_credits <= sub.amount) {
                    endOfRunCleanup(generated);
                    generated.run = null;
                    generated.corp_prompt_state = null;
                    generated.runner_prompt_state = null;
                    generated.runner_run_credit = 0;
                    generated.decision_side = .runner;
                    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
                    return;
                }
            },
            .do_net_damage_then_jack_out => {
                // Karunā sub1: do N net damage, then runner may jack out
                const damage = sub.amount;
                try trashRandomRunnerHandCards(generated, damage);
                updateTerminalState(generated);
                if (generated.game_over) return;
                // Offer jack out - pause subroutines and show jack-out prompt
                const run = &(generated.run orelse return error.NoRunInProgress);
                run.pending_subroutine = .{
                    .server_index = @intCast(server_index),
                    .ice_index = @intCast(ice_index),
                    .subroutine_index = @intCast(idx + 1),
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
                return;
            },
            .give_tag_or_pay_credits => {
                // Funhouse sub: give 1 tag unless runner pays N credits
                const run = &(generated.run orelse return error.NoRunInProgress);
                run.pending_subroutine = .{
                    .server_index = @intCast(server_index),
                    .ice_index = @intCast(ice_index),
                    .subroutine_index = @intCast(idx + 1),
                };
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                try choices.append(allocator, stringChoice("Take 1 tag"));
                if (generated.runner_credit >= sub.amount) {
                    const text = try std.fmt.allocPrint(allocator, "Pay {d} [Credits]", .{sub.amount});
                    try choices.append(allocator, stringChoice(text));
                }
                generated.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "trace"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = ice,
                };
                generated.decision_side = .runner;
                generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
                return;
            },
            .install_ice_from_hq_archives => {
                try beginBranInstallIcePrompt(generated, server_index, ice_index, @intCast(idx));
                return;
            },
            .trash_program_or_etr => {
                if (generated.runner_rig_program.items.len == 0) {
                    // No programs — end the run
                    try completeUnsuccessfulRun(generated);
                    return;
                }
                // Corp chooses a program to trash — use pending_subroutine for multi-sub ICE
                generated.run.?.pending_subroutine = .{
                    .server_index = @intCast(server_index),
                    .ice_index = @intCast(ice_index),
                    .subroutine_index = @intCast(idx),
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
                return;
            },
            .none => {},
        }
    }
}

fn checkManegarmSkunkworks(generated: *Game) !bool {
    const run = generated.run orelse return false;
    if (run.position != 0) return false;

    const target_server = try findServerByRunPath(generated.corp_servers.items, run.server);
    const server = target_server.slot;

    for (server.content.items) |card| {
        if (card.access.kind == .tax_or_etr and card.rezzed) {
            const allocator = generated.arena.allocator();
            var choices: std.ArrayList(state.PromptChoice) = .empty;

            if (generated.runner_click >= card.access.click_cost) {
                try choices.append(allocator, .{
                    .kind = .string,
                    .text = try allocator.dupe(u8, "Spend [Click][Click]"),
                });
            }

            if (generated.runner_credit >= card.access.credit_cost) {
                try choices.append(allocator, .{
                    .kind = .string,
                    .text = try allocator.dupe(u8, "Pay 5 [Credits]"),
                });
            }

            try choices.append(allocator, .{
                .kind = .string,
                .text = try allocator.dupe(u8, "End the run"),
            });

            generated.runner_prompt_state = .{
                .prompt_type = try allocator.dupe(u8, prompt_manegarm_tax),
                .choices = try choices.toOwnedSlice(allocator),
                .source_card = card,
            };

            generated.decision_side = .runner;
            generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
            return true;
        }

        // Anoetic Void: corp may pay 2cr + trash 2 from HQ to ETR
        if (card.access.kind == .corp_pay_etr and card.rezzed) {
            if (generated.corp_credit >= card.access.credit_cost and generated.corp_hand.items.len >= 2) {
                const allocator = generated.arena.allocator();
                generated.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "anoetic-void"),
                    .choices = &.{
                        .{ .kind = .string, .text = "Use Anoetic Void" },
                        .{ .kind = .string, .text = "No action" },
                    },
                    .source_card = card,
                };
                generated.decision_side = .corp;
                generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
                return true;
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
    };

    generated.decision_side = .corp;
    generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
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
    generated.decision_side = .runner;
    generated.legal_actions = try continueActionsForRun(allocator, .runner, current_run.*);
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
    generated.decision_side = .runner;
    generated.legal_actions = try continueActionsForRun(allocator, .runner, current_run.*);
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
    generated.decision_side = .runner;
    generated.legal_actions = try continueActionsForRun(allocator, .runner, next_run.*);
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
        generated.decision_side = .runner;
        generated.legal_actions = try continueActionsForRun(allocator, .runner, next_run.*);
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
    if (try checkManegarmSkunkworks(generated)) {
        return;
    }

    try applySuccessfulRunEffects(generated);
    if (try prepareNextAccess(generated)) {
        run.phase = try allocator.dupe(u8, "success");
        generated.decision_side = .corp;
        generated.legal_actions = try continueActionsForRun(allocator, .corp, run.*);
        return;
    }

    try completeRunWithoutAccess(generated);
}

fn prepareNextAccess(generated: *Game) !bool {
    const run = &generated.run.?;
    if (run.accesses_remaining == 0) {
        var bonus: u8 = run.access_bonus;
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
        // Always show an access prompt (even "No action") per card.
        // This matches Clojure which always shows access options.
        if (try beginAccessFlow(generated, maybe_access.?.card)) return true;
        // Card has no special access interaction — show "No action" prompt
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
    return run.accesses_remaining > 0;
}

fn applySuccessfulRunEffects(generated: *Game) !void {
    const run = generated.run orelse return error.NoRunInProgress;
    switch (run.successful_run_effect) {
        .none => {},
        .draw_cards => try drawCards(generated, .runner, run.successful_run_draw_cards),
    }
}

fn completeRunWithoutAccess(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.runner_successful_run_this_turn = true;
    try applySourceCardOnSuccessfulRun(generated);
    applyVirusCountersOnSuccessfulRun(generated);
    applyPennyshaverOnSuccessfulRun(generated);
    try applyIdentityOnSuccessfulRun(generated);
    applyAmazeTagsOnRunEnd(generated);
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

fn completeRunAfterAccess(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.runner_successful_run_this_turn = true;
    try applySourceCardOnSuccessfulRun(generated);
    applyVirusCountersOnSuccessfulRun(generated);
    applyPennyshaverOnSuccessfulRun(generated);
    try applyIdentityOnSuccessfulRun(generated);
    applyAmazeTagsOnRunEnd(generated);
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

fn completeSuccessfulRunWithCorpPriority(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.runner_successful_run_this_turn = true;
    try applySourceCardOnSuccessfulRun(generated);
    applyVirusCountersOnSuccessfulRun(generated);
    applyPennyshaverOnSuccessfulRun(generated);
    try applyIdentityOnSuccessfulRun(generated);
    applyAmazeTagsOnRunEnd(generated);
    endOfRunCleanup(generated);
    generated.run = null;
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    generated.runner_run_credit = 0;
    generated.decision_side = .corp;
    generated.legal_actions = try continueActions(allocator, .corp);
}

fn completeUnsuccessfulRun(generated: *Game) !void {
    const allocator = generated.arena.allocator();
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
    switch (accessed.access.kind) {
        .steal_agenda => {
            generated.runner_prompt_state = .{
                .prompt_type = try allocator.dupe(u8, prompt_access_choice),
                .choices = try singleStringChoice(allocator, "Steal"),
                .source_card = accessed,
            };
            return true;
        },
        .net_damage_on_access => {
            return try beginNetDamageOnAccessPrompt(generated, accessed);
        },
        .tax_or_etr => return try beginTrashAccessPrompt(generated, accessed),
        .corp_pay_etr => return try beginTrashAccessPrompt(generated, accessed),
        .none => return try beginTrashAccessPrompt(generated, accessed),
    }
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

fn beginTrashAccessPrompt(generated: *Game, accessed: state.CardInstance) !bool {
    const spec = lookupCardSpec(accessed) orelse return false;
    const trash_cost = spec.trash_cost orelse return false;
    const allocator = generated.arena.allocator();

    const can_afford = generated.runner_credit >= trash_cost;
    const choice_count: usize = if (can_afford) 2 else 1;
    const choices = try allocator.alloc(state.PromptChoice, choice_count);
    var idx: usize = 0;
    if (can_afford) {
        choices[idx] = stringChoice(try std.fmt.allocPrint(allocator, "Pay {d} [Credits] to trash", .{trash_cost}));
        idx += 1;
    }
    choices[idx] = stringChoice("No action");
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
    const damage: u8 = accessed.access.base_damage + if (accessed.access.adds_advancement) accessed.advancement_counter else 0;
    const cost = accessed.access.corp_credit_cost;

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
        try spendCredits(generated, .corp, accessed.access.corp_credit_cost);
        const damage: u8 = accessed.access.base_damage + if (accessed.access.adds_advancement) accessed.advancement_counter else 0;
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
            if (rez_actions.len == 0) break :blk &corp_continue_actions;
            // Combine continue + rez actions
            var combined = try allocator.alloc(state.LegalAction, 1 + rez_actions.len);
            combined[0] = corp_continue_actions[0]; // continue action
            @memcpy(combined[1..], rez_actions);
            break :blk combined;
        },
        .runner => runnerContinueActions(allocator, run != null and run.?.jack_out_available),
    };
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

fn encounterActionsForState(
    allocator: std.mem.Allocator,
    generated: *Game,
    ice: state.CardInstance,
) ![]const state.LegalAction {
    const run = generated.run orelse return error.NoRunInProgress;
    const ice_str = effectiveIceStrength(ice, run.server, run.ice_strength_modifier);

    // Count unbroken subroutines
    var unbroken_count: u16 = 0;
    for (ice.subroutines, 0..) |_, idx| {
        const is_broken = (ice.broken_subroutines & (@as(u16, 1) << @intCast(idx))) != 0;
        if (!is_broken) unbroken_count += 1;
    }

    // Count icebreaker break actions (one per qualified icebreaker that can afford one activation)
    var breaker_count: usize = 0;
    if (unbroken_count > 0) {
        for (generated.runner_rig_program.items) |card| {
            if (!isIcebreaker(card)) continue;
            if (card.installed_ability.kind != .break_subroutine) continue;
            if (!canBreakIceType(card, ice)) continue;
            if (effectiveStrength(card) < ice_str) continue;
            // Check affordability: one activation cost (Marjanah discount if ran this turn)
            var break_cost = card.installed_ability.credit_cost;
            if (card.installed_ability.break_cost_reduction_if_successful_run > 0 and generated.runner_successful_run_this_turn) {
                break_cost = if (break_cost >= card.installed_ability.break_cost_reduction_if_successful_run)
                    break_cost - card.installed_ability.break_cost_reduction_if_successful_run
                else
                    0;
            }
            if (generated.runner_credit < break_cost) continue;
            breaker_count += 1;
        }
    }

    // Only offer pump/leech/bioroid if there are unbroken subroutines remaining
    var bioroid_ability_count: usize = 0;
    var pump_count: usize = 0;
    var leech_count: usize = 0;
    var botulus_count: usize = 0;
    if (unbroken_count > 0) {
        for (ice.runner_abilities) |ability| {
            if (ability.kind == .bioroid_break and generated.runner_click >= ability.click_cost) {
                bioroid_ability_count += 1;
            }
        }
        for (generated.runner_rig_program.items) |card| {
            if (!isIcebreaker(card)) continue;
            if (card.pump_ability.kind != .pump_strength) continue;
            if (!canBreakIceType(card, ice)) continue;
            if (generated.runner_credit < card.pump_ability.credit_cost) continue;
            pump_count += 1;
        }
        for (generated.runner_rig_program.items) |card| {
            if (card.installed_ability.virus_ice_strength_reduction > 0 and card.virus_counter > 0) {
                leech_count += 1;
            }
            // Botulus: trojan hosted on current ICE with virus counters can break any sub
            if (card.installed_ability.trojan_break_any and card.virus_counter > 0) {
                // Check if this Botulus is hosted on the current ICE
                if (card.hosted_on_ice_server != null and card.hosted_on_ice_index != null) {
                    const run_2 = generated.run orelse continue;
                    const target_2 = findMutableServerByRunPath(generated.corp_servers.items, run_2.server) catch continue;
                    const ice_count_2 = target_2.server.ices.items.len;
                    const current_ice_idx_2 = run_2.current_ice_index orelse continue;
                    const actual_ice_idx_2 = ice_count_2 - 1 - current_ice_idx_2;
                    if (card.hosted_on_ice_server.? == @as(u8, @intCast(target_2.index)) and card.hosted_on_ice_index.? == @as(u8, @intCast(actual_ice_idx_2))) {
                        botulus_count += 1;
                    }
                }
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

    // Break-all actions: one per qualified icebreaker
    if (unbroken_count > 0) {
        for (generated.runner_rig_program.items, 0..) |card, card_idx| {
            if (!isIcebreaker(card)) continue;
            if (card.installed_ability.kind != .break_subroutine) continue;
            if (!canBreakIceType(card, ice)) continue;
            if (effectiveStrength(card) < ice_str) continue;
            const break_count = @max(@as(u16, 1), @as(u16, card.installed_ability.break_subroutine_count));
            const activations = (unbroken_count + break_count - 1) / break_count;
            const total_cost = activations * card.installed_ability.credit_cost;
            if (generated.runner_credit < total_cost) continue;

            const combined_idx = generated.runner_rig_resources.items.len + card_idx;
            actions[next] = .{
                .kind = .use_installed_ability,
                .side = .runner,
                .card_index = @intCast(combined_idx),
                .card_title = try allocator.dupe(u8, card.title),
                .installed_ability = .break_subroutine,
                .label = try std.fmt.allocPrint(allocator, "Break subroutines with {s}", .{card.title}),
            };
            next += 1;
        }

        // Bioroid break actions
        for (ice.runner_abilities) |ability| {
            if (ability.kind == .bioroid_break and generated.runner_click >= ability.click_cost) {
                actions[next] = .{
                    .kind = .use_runner_ability,
                    .side = .runner,
                    .card_title = try allocator.dupe(u8, ice.title),
                    .label = try std.fmt.allocPrint(allocator, "Lose {d} click(s) to break {d} subroutine(s)", .{ ability.click_cost, ability.break_quantity }),
                };
                next += 1;
            }
        }

        // Pump strength actions
        for (generated.runner_rig_program.items, 0..) |card, card_idx| {
            if (!isIcebreaker(card)) continue;
            if (card.pump_ability.kind != .pump_strength) continue;
            if (!canBreakIceType(card, ice)) continue;
            if (generated.runner_credit < card.pump_ability.credit_cost) continue;

            const combined_idx = generated.runner_rig_resources.items.len + card_idx;
            actions[next] = .{
                .kind = .use_installed_ability,
                .side = .runner,
                .card_index = @intCast(combined_idx),
                .card_title = try allocator.dupe(u8, card.title),
                .installed_ability = .pump_strength,
                .label = try std.fmt.allocPrint(allocator, "+{d} strength to {s}", .{ card.pump_ability.pump_strength_amount, card.title }),
            };
            next += 1;
        }

        // Leech-like virus ICE strength reduction actions
        for (generated.runner_rig_program.items, 0..) |card, card_idx| {
            if (card.installed_ability.virus_ice_strength_reduction > 0 and card.virus_counter > 0) {
                const combined_idx = generated.runner_rig_resources.items.len + card_idx;
                actions[next] = .{
                    .kind = .use_installed_ability,
                    .side = .runner,
                    .card_index = @intCast(combined_idx),
                    .card_title = try allocator.dupe(u8, card.title),
                    .installed_ability = .none,
                    .label = try std.fmt.allocPrint(allocator, "Give -{d} strength to {s}", .{ card.installed_ability.virus_ice_strength_reduction, ice.title }),
                };
                next += 1;
            }
        }

        // Botulus: trojan break any subroutine (hosted on current ICE)
        for (generated.runner_rig_program.items, 0..) |card, card_idx| {
            if (!card.installed_ability.trojan_break_any or card.virus_counter == 0) continue;
            if (card.hosted_on_ice_server == null or card.hosted_on_ice_index == null) continue;
            const run_3 = generated.run orelse continue;
            const target_3 = findMutableServerByRunPath(generated.corp_servers.items, run_3.server) catch continue;
            const ice_count_3 = target_3.server.ices.items.len;
            const current_ice_idx_3 = run_3.current_ice_index orelse continue;
            const actual_ice_idx_3 = ice_count_3 - 1 - current_ice_idx_3;
            if (card.hosted_on_ice_server.? != @as(u8, @intCast(target_3.index))) continue;
            if (card.hosted_on_ice_index.? != @as(u8, @intCast(actual_ice_idx_3))) continue;

            const combined_idx = generated.runner_rig_resources.items.len + card_idx;
            actions[next] = .{
                .kind = .use_installed_ability,
                .side = .runner,
                .card_index = @intCast(combined_idx),
                .card_title = try allocator.dupe(u8, card.title),
                .installed_ability = .break_subroutine,
                .label = try std.fmt.allocPrint(allocator, "Break 1 subroutine with {s}", .{card.title}),
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

    const installed_ability_count = countCorpInstalledAbilityActions(servers);
    var count: usize = playable_hand_count + installed_ability_count;
    if (g.corp_click >= 1) count += 1;
    if (g.corp_click >= 1 and g.corp_deck.items.len > 0) count += 1;
    if (g.corp_click >= 1 and g.corp_credit >= 1) count += 1;
    if (g.corp_click >= 1 and scoreable_count > 0 and !g.cannot_score_agendas_this_turn) count += 1;
    if (g.corp_click >= 3) count += 1;

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
    for (servers, 0..) |server, server_index| {
        const display_name = try displayNameForServer(allocator, server.name, server_index);
        for (server.content.items, 0..) |card, content_index| {
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

    if (g.corp_click >= 1) {
        actions[next] = try basicAbilityAction(allocator, .corp, .gain_credit, "Gain 1 [Credits]");
        next += 1;
    }
    if (g.corp_click >= 1 and g.corp_deck.items.len > 0) {
        actions[next] = try basicAbilityAction(allocator, .corp, .draw_card, "Draw 1 card");
        next += 1;
    }
    if (g.corp_click >= 1 and g.corp_credit >= 1) {
        actions[next] = try basicAbilityAction(allocator, .corp, .advance_installed, "Advance 1 installed card");
        next += 1;
    }
    if (g.corp_click >= 1 and scoreable_count > 0 and !g.cannot_score_agendas_this_turn) {
        actions[next] = try basicAbilityAction(allocator, .corp, .score_agenda, "Score an agenda");
        next += 1;
    }
    if (g.corp_click >= 3) {
        actions[next] = try basicAbilityAction(allocator, .corp, .purge_viruses, "Purge virus counters");
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

fn countAdvanceableCards(servers: []const MutableServer) usize {
    var count: usize = 0;
    for (servers) |server| {
        for (server.content.items) |card| {
            if (isAdvanceable(card)) count += 1;
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

fn runnerOpeningActionsForState(
    allocator: std.mem.Allocator,
    g: *const Game,
) ![]const state.LegalAction {
    if (g.runner_click == 0) return endTurnActions(allocator, .runner);

    const runnable = try runnableServers(allocator, g.corp_servers.items);

    var playable_hand_count: usize = 0;
    for (g.runner_hand.items) |card| {
        if (isRunnerCardPlayableFromHand(g.runner_click, g.runner_credit, card, g.runner_successful_run_this_turn, runnerInstalledFirstProgramDiscount(g), runnerHasConsoleInstalled(g), corpHasInstalledIce(g))) playable_hand_count += 1;
    }
    const resource_ability_count = countRunnerInstalledAbilityActions(g.runner_rig_resources.items, g.turn_events);
    const hardware_ability_count = countRunnerInstalledAbilityActions(g.runner_rig_hardware.items, g.turn_events);
    const program_ability_count = countRunnerInstalledAbilityActions(g.runner_rig_program.items, g.turn_events);
    const installed_ability_count = resource_ability_count + hardware_ability_count + program_ability_count;

    var count: usize = playable_hand_count + runnable.len + installed_ability_count;
    if (g.runner_click >= 1) count += 1;
    if (g.runner_click >= 1 and g.runner_deck.items.len > 0) count += 1;
    if (g.runner_click >= 1 and runnable.len > 0) count += 1;
    if (g.runner_click >= 1 and g.runner_credit >= 2 and is_runner_tagged(g.runner_tag)) count += 1;

    const actions = try allocator.alloc(state.LegalAction, count);
    var next: usize = 0;
    for (g.runner_hand.items, 0..) |card, idx| {
        if (!isRunnerCardPlayableFromHand(g.runner_click, g.runner_credit, card, g.runner_successful_run_this_turn, runnerInstalledFirstProgramDiscount(g), runnerHasConsoleInstalled(g), corpHasInstalledIce(g))) continue;
        actions[next] = .{
            .kind = .play_from_hand,
            .side = .runner,
            .card_index = @intCast(idx),
            .card_title = try allocator.dupe(u8, card.title),
        };
        next += 1;
    }
    for (runnable) |server_name| {
        actions[next] = .{
            .kind = .run,
            .side = .runner,
            .server = server_name,
        };
        next += 1;
    }
    // Combined indices: resources[0..R], programs[R..R+P], hardware[R+P..R+P+H]
    const res_len = g.runner_rig_resources.items.len;
    const prog_len = g.runner_rig_program.items.len;
    for (g.runner_rig_resources.items, 0..) |card, idx| {
        if (!hasRunnerInstalledAbilityAction(card, g.turn_events)) continue;
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
    for (g.runner_rig_program.items, 0..) |card, idx| {
        if (!hasRunnerInstalledAbilityAction(card, g.turn_events)) continue;
        actions[next] = .{
            .kind = .use_installed_ability,
            .side = .runner,
            .card_index = @intCast(res_len + idx),
            .card_title = try allocator.dupe(u8, card.title),
            .installed_ability = card.installed_ability.kind,
            .label = try installedAbilityLabel(allocator, card),
        };
        next += 1;
    }
    for (g.runner_rig_hardware.items, 0..) |card, idx| {
        if (!hasRunnerInstalledAbilityAction(card, g.turn_events)) continue;
        actions[next] = .{
            .kind = .use_installed_ability,
            .side = .runner,
            .card_index = @intCast(res_len + prog_len + idx),
            .card_title = try allocator.dupe(u8, card.title),
            .installed_ability = card.installed_ability.kind,
            .label = try installedAbilityLabel(allocator, card),
        };
        next += 1;
    }

    if (g.runner_click >= 1) {
        actions[next] = try basicAbilityAction(allocator, .runner, .gain_credit, "Gain 1 [Credits]");
        next += 1;
    }
    if (g.runner_click >= 1 and g.runner_deck.items.len > 0) {
        actions[next] = try basicAbilityAction(allocator, .runner, .draw_card, "Draw 1 card");
        next += 1;
    }
    if (g.runner_click >= 1 and runnable.len > 0) {
        actions[next] = try basicAbilityAction(allocator, .runner, .run_any_server, "Run any server");
        next += 1;
    }
    if (g.runner_click >= 1 and g.runner_credit >= 2 and is_runner_tagged(g.runner_tag)) {
        actions[next] = try basicAbilityAction(allocator, .runner, .remove_tag, "Remove 1 tag");
        next += 1;
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
        .take_credits => if (card.installed_ability.takes_all_credits)
            std.fmt.allocPrint(allocator, "Gain {d} [Credits]", .{@as(u16, card.credit_counter) + 1})
        else
            std.fmt.allocPrint(allocator, "Take {d} [Credits] from this card", .{card.installed_ability.take_credits_amount}),
        .place_credits => std.fmt.allocPrint(allocator, "Place {d} [Credits] on this card", .{card.installed_ability.place_credits_amount}),
        .break_subroutine => std.fmt.allocPrint(allocator, "Break {d} subroutine(s)", .{card.installed_ability.break_subroutine_count}),
        .pump_strength => std.fmt.allocPrint(allocator, "Add {d} strength", .{card.installed_ability.pump_strength_amount}),
        .run_central => allocator.dupe(u8, "Make a run on a central server"),
        .run_rd => allocator.dupe(u8, "Run on R&D"),
        .start_of_turn_credits => allocator.dupe(u8, "Take credits (automatic)"),
        .trash_for_virus_credits => std.fmt.allocPrint(allocator, "Gain {d} [Credits]", .{@as(u16, card.virus_counter) * @as(u16, card.installed_ability.trash_for_virus_credits)}),
        .trash_for_damage => std.fmt.allocPrint(allocator, "Trash to do {d} meat damage", .{card.advancement_counter}),
        .remove_from_game_shuffle => allocator.dupe(u8, "Remove from game to shuffle Archives"),
        .none => allocator.dupe(u8, "Use ability"),
    };
}

fn hasRunnerInstalledAbilityAction(card: state.CardInstance, turn_events: state.TurnEvents) bool {
    if (card.installed_ability.kind == .none) return false;
    if (card.ability_used_this_turn and card.installed_ability.once_per_turn) return false;

    // For run_central, check if there are un-run central servers this turn
    if (card.installed_ability.kind == .run_central) {
        if (card.installed_ability.click_cost == 0) return false;
        const has_unrun_central = !turn_events.made_run_on_hq or !turn_events.made_run_on_rnd or !turn_events.made_run_on_archives;
        return has_unrun_central;
    }

    // For run_rd (Conduit), just check click cost
    if (card.installed_ability.kind == .run_rd) {
        return card.installed_ability.click_cost > 0;
    }

    // Combat abilities (break/pump) are only valid during encounter — handled by encounterActionsForState
    if (card.installed_ability.kind == .break_subroutine or card.installed_ability.kind == .pump_strength) {
        return false;
    }

    // Fermenter: click + trash to gain credits (always available if has virus counters)
    if (card.installed_ability.kind == .trash_for_virus_credits) {
        return card.installed_ability.click_cost > 0 and card.virus_counter > 0;
    }

    // For abilities that require clicks, check click cost
    if (card.installed_ability.click_cost > 0) {
        return true;
    }

    return false;
}

fn hasCorpInstalledAbilityAction(card: state.CardInstance) bool {
    if (card.installed_ability.kind == .none) return false;
    if (!card.rezzed) return false;
    if (card.installed_ability.click_cost == 0) return false;
    if (card.ability_used_this_turn and card.installed_ability.once_per_turn) return false;
    // Clearinghouse: trash_for_damage requires advancement counters
    if (card.installed_ability.kind == .trash_for_damage) return card.advancement_counter > 0;
    // Spin Doctor: remove_from_game_shuffle is always available when rezzed (no click cost, no counters needed)
    if (card.installed_ability.kind == .remove_from_game_shuffle) return true;
    return card.credit_counter > 0;
}

fn countRunnerInstalledAbilityActions(cards: []const state.CardInstance, turn_events: state.TurnEvents) usize {
    var count: usize = 0;
    for (cards) |card| {
        if (hasRunnerInstalledAbilityAction(card, turn_events)) count += 1;
    }
    return count;
}

fn countCorpInstalledAbilityActions(servers: []const MutableServer) usize {
    var count: usize = 0;
    for (servers) |server| {
        for (server.content.items) |card| {
            if (hasCorpInstalledAbilityAction(card)) count += 1;
        }
    }
    return count;
}

fn buildDeck(
    allocator: std.mem.Allocator,
    rng_state: *RngState,
    side_spec: SideSpec,
) ![]state.CardInstance {
    const shuffled_lines = try allocator.dupe(DeckLine, side_spec.deck_lines);
    shuffleInPlace(DeckLine, rng_state, shuffled_lines);

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

fn makeCardInstance(
    allocator: std.mem.Allocator,
    spec: CardSpec,
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
        .remote_strength_bonus = spec.remote_strength_bonus,
        .agenda_points = spec.agenda_points,
        .advancement_requirement = spec.advancement_requirement,
        .corp_play = spec.corp_play,
        .runner_play = spec.runner_play,
        .access = spec.access,
        .install = spec.install,
        .runner_install = spec.runner_install,
        .installed_ability = spec.installed_ability,
        .pump_ability = spec.pump_ability,
        .subroutines = spec.subroutines,
        .runner_abilities = spec.runner_abilities,
        .advancement_counter = 0,
        .credit_counter = 0,
        .ability_used_this_turn = false,
        .broken_subroutines = 0,
        .tag_on_rez = spec.tag_on_rez,
        .advanceable = spec.advanceable,
        .advancement_strength_threshold = spec.advancement_strength_threshold,
        .advancement_strength_bonus = spec.advancement_strength_bonus,
    };
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
        .hardware => {
            try game.runner_rig_hardware.append(game.backing_allocator, card);
            // DZMZ Optimizer / T400 Memory Diamond: update MU when hardware provides it
            if (card.installed_ability.mu_provided > 0) {
                if (game.runner_memory) |*mem| {
                    mem.base += card.installed_ability.mu_provided;
                    mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
                }
            }
            // T400 Memory Diamond: increase hand size
            if (card.installed_ability.hand_size_bonus > 0) {
                game.runner_hand_size.base += card.installed_ability.hand_size_bonus;
                game.runner_hand_size.total += card.installed_ability.hand_size_bonus;
            }
        },
        .program => try game.runner_rig_program.append(game.backing_allocator, card),
        .resource => try game.runner_rig_resources.append(game.backing_allocator, card),
        else => return error.UnsupportedRunnerInstall,
    }
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

fn applyCorpStartOfTurnAbilities(game: *Game) !void {
    // Nico Campaign and similar: auto-take credits at start of corp turn
    for (game.corp_servers.items) |*server| {
        var i: usize = 0;
        while (i < server.content.items.len) {
            var card = &server.content.items[i];
            if (card.installed_ability.kind == .start_of_turn_credits and card.credit_counter > 0) {
                const take = @min(card.credit_counter, card.installed_ability.take_credits_amount);
                card.credit_counter -= take;
                game.corp_credit += take;

                if (card.installed_ability.trash_on_empty and card.credit_counter == 0) {
                    // Draw cards before trashing if draw_on_empty > 0
                    if (card.installed_ability.draw_on_empty > 0) {
                        try drawCards(game, .corp, card.installed_ability.draw_on_empty);
                    }
                    const trashed = server.content.orderedRemove(i);
                    try appendDiscardCard(game, .corp, trashed);
                    continue; // Don't increment i
                }
            }
            i += 1;
        }
    }
}

fn endCorpPhase12(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    generated.corp_phase_12 = false;
    generated.cannot_score_agendas_this_turn = false;

    // Corp must draw at start of turn — empty deck means runner wins
    if (generated.corp_deck.items.len == 0) {
        setGameOver(generated, .runner);
        return;
    }
    try drawCard(generated, .corp);
    generated.corp_click = generated.corp_click_per_turn;
    generated.runner_successful_run_last_turn = generated.runner_successful_run_this_turn;
    generated.runner_successful_run_this_turn = false;

    // Clear installed_this_turn flags for all corp cards
    clearInstalledThisTurnFlags(generated);

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
    const source_code = run.source_card_code orelse return;

    // Find the source card in runner's rig (Red Team is a resource)
    for (game.runner_rig_resources.items, 0..) |*card, idx| {
        if (card.code != null and card.code.? == source_code and card.credit_counter > 0) {
            const take = @min(card.credit_counter, card.installed_ability.take_credits_amount);
            card.credit_counter -= take;
            game.runner_credit += take;

            // Trash card if empty and trash_on_empty
            if (card.installed_ability.trash_on_empty and card.credit_counter == 0) {
                const trashed = game.runner_rig_resources.orderedRemove(idx);
                try appendDiscardCard(game, .runner, trashed);
            }
            return;
        }
    }
}

fn runnerRdAccessBonus(generated: *const Game) u8 {
    var bonus: u8 = 0;
    for (generated.runner_rig_program.items) |card| {
        if (card.installed_ability.rd_access_bonus_per_virus) {
            bonus += @intCast(@min(card.virus_counter, 255));
        }
    }
    return bonus;
}

fn runnerInstalledFirstProgramDiscount(generated: *const Game) u16 {
    if (generated.turn_events.programs_installed_this_turn > 0) return 0;
    var discount: u16 = 0;
    for (generated.runner_rig_hardware.items) |card| {
        discount += card.installed_ability.first_program_install_discount;
    }
    return discount;
}

fn runnerCookbookBonus(generated: *const Game) u16 {
    var bonus: u16 = 0;
    for (generated.runner_rig_resources.items) |card| {
        bonus += card.installed_ability.bonus_virus_on_install;
    }
    return bonus;
}

fn runnerInstalledMuBonus(generated: *const Game) u8 {
    var bonus: u8 = 0;
    for (generated.runner_rig_hardware.items) |card| {
        bonus += card.installed_ability.mu_provided;
    }
    return bonus;
}

fn applyAmazeTagsOnRunEnd(game: *Game) void {
    const run = game.run orelse return;
    if (!run.did_steal_this_run) return;

    // Check the run's target server for cards with tags_on_agenda_steal_from_server
    const target_server = findServerByRunPath(game.corp_servers.items, run.server) catch return;
    var tags: u8 = 0;
    for (target_server.slot.content.items) |card| {
        if (card.installed_ability.tags_on_agenda_steal_from_server > 0 and card.rezzed) {
            tags += card.installed_ability.tags_on_agenda_steal_from_server;
        }
    }
    // Also check pending tags from trashed AMAZE
    tags += run.tags_pending_on_steal;

    if (tags > 0) {
        _ = addRunnerTag(game, tags) catch {};
    }
}

fn applyVirusCountersOnSuccessfulRun(game: *Game) void {
    const run = game.run orelse return;
    const is_central = isCentralRunServer(run.server);
    const is_rd = run.server.len > 0 and std.mem.eql(u8, run.server[0], "rnd");

    for (game.runner_rig_program.items) |*card| {
        // Leech: place virus counter on successful central run
        if (card.installed_ability.virus_on_successful_central and is_central) {
            card.virus_counter += 1;
        }
        // Conduit: place virus counter on successful R&D run
        if (card.installed_ability.virus_on_successful_rd and is_rd) {
            card.virus_counter += 1;
        }
    }
}

fn applyIdentityOnSuccessfulRun(game: *Game) !void {
    game.turn_events.successful_run_ends_count += 1;
    _ = try fireEvent(game, .successful_run_ends);
}

fn applyPennyshaverOnSuccessfulRun(game: *Game) void {
    // Pennyshaver: place 1 credit on successful run
    for (game.runner_rig_hardware.items) |*card| {
        if (card.installed_ability.on_successful_run_place_credits > 0) {
            card.credit_counter += card.installed_ability.on_successful_run_place_credits;
        }
    }
}

fn endOfRunCleanup(game: *Game) void {
    // Mayfly: trash icebreakers that used their break ability this run
    var i: usize = 0;
    while (i < game.runner_rig_program.items.len) {
        const card = game.runner_rig_program.items[i];
        if (card.installed_ability.trashes_after_break and card.used_break_this_run) {
            const trashed = game.runner_rig_program.orderedRemove(i);
            appendDiscardCard(game, .runner, trashed) catch {};
            continue;
        }
        i += 1;
    }
    // Reset used_break_this_run for remaining breakers
    for (game.runner_rig_program.items) |*card| {
        card.used_break_this_run = false;
    }
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

fn spendClicks(
    game: *Game,
    side: state.Side,
    amount: u8,
) !void {
    const click = switch (side) { .corp => &game.corp_click, .runner => &game.runner_click };
    if (click.* < amount) return error.InsufficientClicks;
    click.* -= amount;
}

fn spendCredits(
    game: *Game,
    side: state.Side,
    amount: u16,
) !void {
    const credit = switch (side) { .corp => &game.corp_credit, .runner => &game.runner_credit };
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
                if (spec.can_play) |can_play| {
                    if (!can_play(g)) return false;
                }
            }
        }
        return true;
    }

    return card.install.kind != .none;
}

fn runnerHasConsoleInstalled(g: *const Game) bool {
    for (g.runner_rig_hardware.items) |card| {
        if (card.installed_ability.is_console) return true;
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
        if (card.installed_ability.is_console and has_console) return false;
        // Trojan restriction: can't install trojan if no ICE exists
        if (card.installed_ability.is_trojan and !has_ice) return false;
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
    // ICE can be installed on any central or "New remote"
    // Filter out servers where the install cost exceeds available credits
    // Order must match oracle: Archives, HQ, New remote, R&D
    const entries = [_]struct { name: []const u8, index: ?usize }{
        .{ .name = "Archives", .index = 2 },
        .{ .name = "HQ", .index = 0 },
        .{ .name = "New remote", .index = null }, // always cost 0
        .{ .name = "R&D", .index = 1 },
    };
    var count: usize = 0;
    for (entries) |entry| {
        if (entry.index) |idx| {
            if (idx < game.corp_servers.items.len) {
                const ice_count: u16 = @intCast(game.corp_servers.items[idx].ices.items.len);
                if (game.corp_credit >= ice_count) count += 1;
            }
        } else {
            count += 1; // New remote always affordable
        }
    }
    const choices = try allocator.alloc(state.PromptChoice, count);
    var next: usize = 0;
    for (entries) |entry| {
        if (entry.index) |idx| {
            if (idx < game.corp_servers.items.len) {
                const ice_count: u16 = @intCast(game.corp_servers.items[idx].ices.items.len);
                if (game.corp_credit >= ice_count) {
                    choices[next] = stringChoice(entry.name);
                    next += 1;
                }
            }
        } else {
            choices[next] = stringChoice(entry.name);
            next += 1;
        }
    }
    return choices;
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
    servers: []const MutableServer,
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
    else
        return error.UnsupportedChoice;

    var installed = card;
    installed.installed_this_turn = true;

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

    try applyActionByIndex(&generated, 0); // start_turn
    // Phase 12: corp continue, runner continue
    try applyAction(&generated, .{ .kind = .@"continue", .side = .corp });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .runner });
    try std.testing.expectEqual(state.Side.corp, currentPlayer(&generated));
    try std.testing.expectEqual(@as(usize, 10), legalActionCount(&generated));

    try applyActionByIndex(&generated, 0);
    try std.testing.expectEqual(@as(u16, 9), generated.corp_credit);
    try std.testing.expectEqual(@as(u8, 2), generated.corp_click);
    try std.testing.expectEqual(@as(usize, 8), legalActionCount(&generated));

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
    try applyAction(&generated, findRunAction(generated.legal_actions, "Server 2") orelse return error.MissingAction);
    try applyAction(&generated, .{ .kind = .@"continue", .side = .corp, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .runner, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .corp, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .runner, .prompt_type = "run" });
    try applyAction(&generated, .{ .kind = .@"continue", .side = .corp, .prompt_type = "run" });
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
    const run_action = findRunAction(generated.legal_actions, "Server 1") orelse return error.MissingAction;
    try applyAction(&generated, run_action);

    var found_rez_prompt = false;
    var guard: usize = 0;
    while (guard < 12 and generated.run != null) : (guard += 1) {
        if (generated.decision_side == .corp) {
            if (findPromptChoiceAction(generated.legal_actions, .corp, "Rez approached ice")) |rez_action| {
                try applyAction(&generated, rez_action);
                found_rez_prompt = true;
                break;
            }
        }
        const continue_action = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse return error.MissingAction;
        try applyAction(&generated, continue_action);
    }
    try std.testing.expect(found_rez_prompt);

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

    var regolith = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30071));
    regolith.credit_counter = regolith.installed_ability.initial_credit_counters;
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

    var offworld = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30067));
    offworld.advancement_counter = 4;
    try installCard(&generated, offworld, "New remote");

    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), &generated);

    const credit_before = generated.corp_credit;
    const score_action = findBasicAbilityAction(generated.legal_actions, .corp, .score_agenda) orelse return error.MissingAction;
    try applyAction(&generated, score_action);
    try applyAction(&generated, .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = prompt_score_agenda,
        .choice = stringChoice("remote1|c|0"),
    });

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

    var urtica = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30045));
    urtica.advancement_counter = 2;
    try installCard(&generated, urtica, "New remote");
    generated.corp_credit = 20;

    try endTurnAndDiscard(&generated, .corp);
    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const hand_before = generated.runner_hand.items.len;
    const discard_before = generated.runner_discard.items.len;
    const corp_credit_before = generated.corp_credit;

    try applyAction(&generated, findRunAction(generated.legal_actions, "Server 1") orelse return error.MissingAction);
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
    const mem = generated.runner_memory orelse return false;
    if (mem.used + extra_mu <= mem.base) return false;

    const allocator = generated.arena.allocator();
    // List all installed programs as trash choices
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
        try completeRunnerInstall(generated, pi_index, pi_card, pi_cost);
        return;
    }

    generated.runner_prompt_state = null;
    const allocator = generated.arena.allocator();
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
}

pub fn corpStartTurnFull(generated: *Game) !void {
    try applyAction(generated, .{ .kind = .start_turn, .side = .corp });
    // Phase 12: corp passes, runner passes
    try applyAction(generated, .{ .kind = .@"continue", .side = .corp });
    try applyAction(generated, .{ .kind = .@"continue", .side = .runner });
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
    try applyAction(&generated, findRunAction(generated.legal_actions, "Server 1") orelse return error.MissingAction);

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

        // Handle rez window - corp should decline
        if (findPromptChoiceAction(generated.legal_actions, .corp, "No rez")) |no_rez| {
            try applyAction(&generated, no_rez);
            continue;
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
    var tithe = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30073));
    tithe.rezzed = true;
    try installCard(&generated, tithe, "New remote");

    generated.corp_credit = 20;
    try endTurnAndDiscard(&generated, .corp);

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const hand_before = generated.runner_hand.items.len;

    try applyAction(&generated, findRunAction(generated.legal_actions, "Server 1") orelse return error.MissingAction);

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
    var karuna = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30047));
    karuna.rezzed = true;
    try installCard(&generated, karuna, "New remote");

    generated.corp_credit = 20;
    try endTurnAndDiscard(&generated, .corp);

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const hand_before = generated.runner_hand.items.len;

    try applyAction(&generated, findRunAction(generated.legal_actions, "Server 1") orelse return error.MissingAction);

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
    var whitespace = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30074));
    whitespace.rezzed = true;
    try installCard(&generated, whitespace, "New remote");

    generated.corp_credit = 20;
    // Give runner enough credits that sub2 won't end the run
    generated.runner_credit = 20;
    try endTurnAndDiscard(&generated, .corp);

    try applyAction(&generated, .{ .kind = .start_turn, .side = .runner });
    const credit_before = generated.runner_credit;

    try applyAction(&generated, findRunAction(generated.legal_actions, "Server 1") orelse return error.MissingAction);

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

    // Verify rez cost bonus is set
    try std.testing.expectEqual(@as(u16, 3), generated.run.?.rez_cost_bonus);

    // Run through to approach-ice phase
    var guard: usize = 0;
    var found_rez_prompt = false;
    while (guard < 20 and generated.run != null) : (guard += 1) {
        // Look for rez window prompt
        if (findPromptChoiceAction(generated.legal_actions, .corp, "Rez approached ice")) |rez_action| {
            found_rez_prompt = true;
            // Corp has 20 credits, should be able to rez regardless of ice cost
            try std.testing.expect(generated.corp_credit >= 4);
            try applyAction(&generated, rez_action);
            break;
        }
        const continue_action = findActionByKind(generated.legal_actions, .@"continue", generated.decision_side) orelse break;
        try applyAction(&generated, continue_action);
    }

    try std.testing.expect(found_rez_prompt);
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
