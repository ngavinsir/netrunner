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
    on_event: ?*const fn (*Game, ?*state.CardInstance) anyerror!void = null,
    on_event_server_check: bool = false, // Only fire if event occurred in same server as this card
    // Declarative log messages (like Clojure's :msg) — auto-logged as "{Side} uses {title} to {msg}"
    on_event_msg: ?[]const u8 = null, // logged after on_event fires
    on_rez_msg: ?[]const u8 = null, // logged after on_rez fires
    on_play_msg: ?[]const u8 = null, // logged after on_play fires (effect description, not "plays X")
    on_score_msg: ?[]const u8 = null, // logged after on_score_fn fires
    // For prompt-based abilities: auto-log choice text as "{Side} uses {title} to {choice}."
    log_prompt_choice: bool = false,
    // Identity click ability (Topan, AU Co.)
    identity_ability_click_cost: u8 = 0, // 0 = no identity ability; N = costs N clicks
    identity_ability_once_per_turn: bool = true,
    identity_ability_label: ?[]const u8 = null,
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
};

pub const EventSource = struct {
    code: u32,
    side: state.Side,
    zone: CardZone,
    index: u16 = 0, // index within zone at collection time
    server_index: u16 = 0, // for corp_server_content zone
};

pub const PendingEffect = union(enum) {
    event_handler: EventSource, // source card info — find card and call on_event
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
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
        .on_event_msg = "gain 1 [credit].",
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .corp_end_turn; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
                if (g.corp_discard.items.len > 0) {
                    g.corp_credit += 1;
                }
            }
        }.handle,
    },
    .{ .title = "NBN: Reality Plus", .side = .corp, .code = 30051, .card_type = "Identity",
        .log_prompt_choice = true,
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .runner_gain_tag; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
        .on_event_msg = "gain 1 [credit] and draw 1 card.",
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .runner_trash_corp_card; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.handle,
        .on_prompt_choice = &struct {
            fn handle(g: *Game, choice_text: []const u8) anyerror!void {
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
    },
    .{ .title = "Offworld Office", .side = .corp, .code = 30067, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 4, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only }, .on_score = .{ .kind = .gain_credits, .amount = 7 } },
    .{ .title = "Send a Message", .side = .corp, .code = 30069, .card_type = "Agenda", .agenda_points = 3, .advancement_requirement = 5, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only }, .on_score = .{ .kind = .rez_ice_free }, .on_steal = .{ .kind = .rez_ice_free } },
    .{ .title = "Superconducting Hub", .side = .corp, .code = 30070, .card_type = "Agenda", .agenda_points = 1, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only }, .on_score = .{ .kind = .draw_cards, .amount = 2, .hand_size_bonus = 2 } },
    .{ .title = "Orbital Superiority", .side = .corp, .code = 30068, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 4, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
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
    .{ .title = "Nico Campaign", .side = .corp, .code = 30037, .card_type = "Asset", .cost = 2, .trash_cost = 2, .install = .{ .kind = .corp_remote_only }, .installed_ability = .{
        .kind = .start_of_turn_credits,
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
    .{ .title = "Predictive Planogram", .side = .corp, .code = 30056, .card_type = "Operation", .cost = 0, .corp_play = .{ .kind = .custom }, .log_prompt_choice = true,
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
    .{ .title = "Public Trail", .side = .corp, .code = 30057, .card_type = "Operation", .cost = 4, .corp_play = .{ .kind = .custom }, .log_prompt_choice = true,
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
        }.choice,
    },
    .{ .title = "Manegarm Skunkworks", .side = .corp, .code = 30042, .card_type = "Upgrade", .cost = 2, .trash_cost = 3, .access = .{ .kind = .tax_or_etr, .click_cost = 2, .credit_cost = 5 }, .install = .{ .kind = .corp_server_choice }, .log_prompt_choice = true,
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
    .{ .title = "AMAZE Amusements", .side = .corp, .code = 30058, .card_type = "Upgrade", .cost = 1, .trash_cost = 3, .install = .{ .kind = .corp_server_choice }, .installed_ability = .{ .tags_on_agenda_steal_from_server = 2 } },
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
    .{ .title = "Funhouse", .side = .corp, .code = 30054, .card_type = "ICE", .subtypes = &.{"Code Gate"}, .cost = 5, .strength = 4, .install = .{ .kind = .corp_server_choice }, .log_prompt_choice = true, .subroutines = &.{
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
    .{ .title = "Mutual Favor", .side = .runner, .code = 30011, .card_type = "Event", .cost = 0, .runner_play = .{ .kind = .custom }, .on_play_msg = "search stack for an icebreaker.",
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
    .{ .title = "Wildcat Strike", .side = .runner, .code = 30002, .card_type = "Event", .cost = 2, .runner_play = .{ .kind = .custom }, .log_prompt_choice = true,
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
    .{ .title = "Sprint", .side = .corp, .code = 30041, .card_type = "Operation", .cost = 0, .corp_play = .{ .kind = .custom }, .on_play_msg = "draw 3 cards.",
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
                // Mark the card as selected (don't move yet — batch like Clojure)
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
                        for (g.corp_hand.items, 0..) |card, idx| {
                            var already_selected = false;
                            for (g.pending_sprint_selections.items) |sel| {
                                if (std.mem.eql(u8, card.title, sel)) {
                                    already_selected = true;
                                    break;
                                }
                            }
                            if (!already_selected) {
                                try choices.append(allocator, .{ .kind = .card, .text = card.title, .card = .{ .title = card.title, .side = .corp, .index = @intCast(idx) } });
                            }
                        }
                        ps.choices = try choices.toOwnedSlice(allocator);
                        g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                        return;
                    }
                }
                // All selected — now move all selected cards from hand to deck
                for (g.pending_sprint_selections.items) |sel_title| {
                    for (g.corp_hand.items, 0..) |card, idx| {
                        if (std.mem.eql(u8, card.title, sel_title)) {
                            const removed = g.corp_hand.orderedRemove(idx);
                            try g.corp_deck.append(g.backing_allocator, removed);
                            break;
                        }
                    }
                }
                g.pending_sprint_selections.clearRetainingCapacity();
                // Done — shuffle R&D and return to corp actions
                try shuffleDeck(g, .corp);
                g.corp_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.choice,
    },
    .{ .title = "Hansei Review", .side = .corp, .code = 30048, .card_type = "Operation", .cost = 5, .corp_play = .{ .kind = .custom }, .on_play_msg = "gain 10 [credits].",
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
                    g.systemMsg(.corp, 30049, "Corp uses Neurospike to do {d} net damage.", .{damage});
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
    .{ .title = "Malapert Data Vault", .side = .corp, .code = 30066, .card_type = "Upgrade", .cost = 1, .trash_cost = 4, .install = .{ .kind = .corp_server_choice },
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .agenda_scored; } }.m,
        .on_event_server_check = true,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
        .on_rez_msg = "draw 2 cards.",
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
    .{ .title = "Carnivore", .side = .runner, .code = 30003, .card_type = "Hardware", .subtypes = &.{"Console"}, .cost = 4, .runner_install = .{ .kind = .hardware }, .installed_ability = .{ .mu_provided = 1, .is_console = true, .trash_access_hand_cost = 2 } },
    .{ .title = "Pantograph", .side = .runner, .code = 30023, .card_type = "Hardware", .subtypes = &.{"Console"}, .cost = 2, .runner_install = .{ .kind = .hardware }, .installed_ability = .{ .mu_provided = 1, .is_console = true },
        .on_event_msg = "gain 1 [credit].",
        .event_match = &struct {
            fn m(e: state.GameEvent) bool { return e == .agenda_scored or e == .agenda_stolen; }
        }.m,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
        .{ .kind = .corp_install_from_hq_archives }, // install a card from HQ or Archives
        .{ .kind = .prevent_steal_trash }, // prevent stealing/trashing for rest of run
    }, .runner_abilities = &.{
        .{ .kind = .bioroid_break, .click_cost = 1, .break_quantity = 1 },
    } },
    .{ .title = "Anoetic Void", .side = .corp, .code = 30050, .card_type = "Upgrade", .cost = 0, .trash_cost = 1, .install = .{ .kind = .corp_server_choice },
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
    // ====================================================================
    // ELEVATION PACK (35001–35082)
    // ====================================================================
    // --- Elevation Identities ---
    .{ .title = "Ry\xc5\x8d \xe2\x80\x9cPhoenix\xe2\x80\x9d \xc5\x8cno: Out of the Ashes", .side = .runner, .code = 35001, .card_type = "Identity", .subtypes = &.{"G-mod"},
        // "Whenever a subroutine resolves during a run: gain 1cr. First time each turn: Corp trashes 1 from HQ."
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .successful_run_ends; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, self_card: ?*state.CardInstance) anyerror!void {
                if (g.run == null) return;
                if (g.run.?.subroutines_fired == 0) return;
                const card = self_card orelse return;
                if (card.ability_used_this_turn) return;
                card.ability_used_this_turn = true;
                g.runner_credit += 1;
                // Corp trashes 1 from HQ (simplified: auto-resolve first card)
                if (g.corp_hand.items.len > 0) {
                    const trashed = g.corp_hand.orderedRemove(0);
                    try appendDiscardCard(g, .corp, trashed);
                }
            }
        }.handle,
        .on_event_msg = "gain 1 [credit].",
    },
    .{ .title = "Topan: Ormas Leader", .side = .runner, .code = 35002, .card_type = "Identity", .subtypes = &.{"Natural"},
        // "click: Install 1 card from grip, paying 2cr less. Suffer 1 meat damage."
        .identity_ability_click_cost = 1,
        .identity_ability_once_per_turn = true,
        .identity_ability_label = "Install 1 card, paying 2[credit] less. Suffer 1 meat damage.",
        .on_play = &struct {
            fn play(g: *Game, _: state.CardInstance) anyerror!void {
                // Build installable choices from grip (hardware, resource, program that can be afforded -2cr)
                const allocator = g.arena.allocator();
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                for (g.runner_hand.items) |h| {
                    if (h.runner_install.kind == .none) continue;
                    const base_cost: u16 = h.cost orelse 0;
                    const adjusted_cost = if (base_cost >= 2) base_cost - 2 else 0;
                    if (g.runner_credit < adjusted_cost) continue;
                    try choices.append(allocator, .{ .kind = .card, .text = h.title, .card = .{
                        .title = h.title, .code = h.code, .side = .runner,
                    } });
                }
                if (choices.items.len == 0) return; // no installable cards
                try choices.append(allocator, stringChoice("No action"));
                g.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "topan-install"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = g.runner_identity,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
                        try completeRunnerInstall(g, @intCast(idx), card, adjusted_cost);
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
        }.choice,
    },
    .{ .title = "Barry \xe2\x80\x9cBaz\xe2\x80\x9d Wong: Tri-Maf Veteran", .side = .runner, .code = 35012, .card_type = "Identity", .subtypes = &.{"Cyborg"},
        // "Whenever the Corp rezzes a piece of ice, you may install 1 resource or piece of hardware from your grip."
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .corp_rez_ice; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
        }.choice,
    },
    .{ .title = "MuslihaT: Multifarious Marketeer", .side = .runner, .code = 35013, .card_type = "Identity", .subtypes = &.{"Natural"},
        // "When your turn begins, look at top card of stack. If icebreaker or run event, may reveal and add to grip."
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .runner_turn_begins; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
                if (g.runner_deck.items.len == 0) return;
                const top_card = g.runner_deck.items[g.runner_deck.items.len - 1];
                // Check if icebreaker or run event
                var is_match = false;
                const ct = top_card.card_type orelse "";
                if (std.mem.eql(u8, ct, "Program")) {
                    for (top_card.subtypes) |st| {
                        if (std.mem.eql(u8, st, "Icebreaker")) { is_match = true; break; }
                    }
                } else if (std.mem.eql(u8, ct, "Event")) {
                    for (top_card.subtypes) |st| {
                        if (std.mem.eql(u8, st, "Run")) { is_match = true; break; }
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
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                }
            }
        }.handle,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
        }.choice,
    },
    .{ .title = "Dewi Subrotoputri: Pedagogical Dhalang", .side = .runner, .code = 35023, .card_type = "Identity", .subtypes = &.{"Natural"},
        // Flippy identity: "Pedagogical Dhalang" (front) / "Shadow Guide" (back)
        // After successful run: flip based on available MU
        // Front → Back: no MU available → gain 1cr + flip
        // Back → Front: MU available → draw 1 + flip
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .successful_run_ends; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, self_card: ?*state.CardInstance) anyerror!void {
                const card = self_card orelse return;
                const mu_available = if (g.runner_memory) |mem| mem.available else 0;
                if (card.flipped and mu_available > 0) {
                    // Back → Front: draw 1 + flip
                    try drawCards(g, .runner, 1);
                    card.flipped = false;
                } else if (!card.flipped and mu_available == 0) {
                    // Front → Back: gain 1cr + flip
                    g.runner_credit += 1;
                    card.flipped = true;
                }
                // Otherwise: no flip (conditions not met)
            }
        }.handle,
    },
    .{ .title = "Magdalene Keino-Chemutai: Cryptarchitect", .side = .runner, .code = 35024, .card_type = "Identity", .subtypes = &.{"Cyborg"},
        // "When discarding to hand size, may install a discarded program or hardware."
        // Triggers after runner discard phase — needs discard-to-hand-size event
        // Auto-declined in oracle auto-resolve mode (optional install prompt)
    },
    .{ .title = "LEO Construction: Labor Solutions", .side = .corp, .code = 35035, .card_type = "Identity", .subtypes = &.{"Division"},
        // "Once per turn, during a run on a server with bioroid ICE, end the run."
        // This is a corp action during runs — handled via run-time corp ability.
        // Auto-declined in oracle auto-resolve mode (complex conditions).
    },
    .{ .title = "Po\xc3\xa9tr\xc3\xaf Luxury Brands: All the Rage", .side = .corp, .code = 35036, .card_type = "Identity", .subtypes = &.{"Division"},
        // "When you score an agenda, look at top 3 R&D. May install 1 non-agenda non-operation."
        // "When an agenda is stolen, may install 1 non-agenda non-operation from HQ."
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .agenda_scored or e == .agenda_stolen; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
                // For agenda_stolen: offer to install from HQ
                // For agenda_scored: simplified - just offer install from HQ too
                // (R&D peek is complex - would need card reveal + choice)
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
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.handle,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
        }.choice,
    },
    .{ .title = "AU Co.: The Gold Standard in Clones", .side = .corp, .code = 35046, .card_type = "Identity", .subtypes = &.{"Division"},
        // Place 1 power counter on damage/corp-trash events (auto via event handlers)
        // Start of turn: optional spend 2 power counters to peek top 3 R&D, trash 1, draw rest
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .agenda_scored; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, self_card: ?*state.CardInstance) anyerror!void {
                // Place 1 power counter when an agenda is scored (simplified trigger)
                const card = self_card orelse return;
                card.power_counter += 1;
                g.systemMsg(.corp, 35046, "Corp places 1 power counter on AU Co.", .{});
            }
        }.handle,
    },
    .{ .title = "PT Untaian: Life's Building Blocks", .side = .corp, .code = 35047, .card_type = "Identity", .subtypes = &.{"Division"},
        // "When your discard phase ends, if HQ ≤ 3 cards, pay 1cr to place 1 advancement counter on unrezzed card."
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .corp_end_turn; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
                };
                g.decision_side = .corp;
                g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
            }
        }.handle,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                const allocator = g.arena.allocator();
                if (std.mem.eql(u8, choice_text, "No action")) {
                    g.corp_prompt_state = null;
                    return;
                }
                // Pay 1 credit and place advancement counter
                try spendCredits(g, .corp, 1);
                _ = try addAdvancementCounter(g, choice_text, 1);
                g.systemMsg(.corp, 35047, "Corp uses PT Untaian to place 1 advancement counter.", .{});
                g.corp_prompt_state = null;
                _ = allocator;
            }
        }.choice,
    },
    .{ .title = "Nebula Talent Management: Making Stars", .side = .corp, .code = 35057, .card_type = "Identity", .subtypes = &.{"Division"},
        // Flippy identity: "Making Stars" (front) / "Gemilang Arena: Burning Bright" (back)
        // Front → Back: End of turn if operation played → flip + gain 1cr
        // Back → Front: Successful run on HQ/R&D → flip
        // Back ongoing: First non-Terminal operation played → gain 1 click
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .corp_end_turn or e == .successful_run_ends or e == .operation_played; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, self_card: ?*state.CardInstance) anyerror!void {
                const card = self_card orelse return;
                // Check which event fired based on game state
                if (g.end_turn and g.active_player == .corp) {
                    // corp_end_turn: flip front→back if operation was played
                    if (!card.flipped and g.turn_events.operation_played_count > 0) {
                        card.flipped = true;
                        g.corp_credit += 1;
                    }
                } else if (g.run != null) {
                    // successful_run_ends: flip back→front on HQ/R&D run
                    if (card.flipped) {
                        const server = g.run.?.server;
                        if (server.len > 0 and (std.mem.eql(u8, server[0], "hq") or std.mem.eql(u8, server[0], "rnd"))) {
                            card.flipped = false;
                        }
                    }
                } else {
                    // operation_played: gain 1 click if flipped (back side) and first operation
                    if (card.flipped and g.turn_events.operation_played_count == 1) {
                        g.corp_click += 1;
                    }
                }
            }
        }.handle,
    },
    .{ .title = "Synapse Global: Faster than Thought", .side = .corp, .code = 35058, .card_type = "Identity", .subtypes = &.{"Division"},
        // "When the Runner removes 1+ tags, reveal and install a non-operation from HQ for free."
        // Needs runner_lose_tag event + install prompt
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .runner_lose_tag; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, self_card: ?*state.CardInstance) anyerror!void {
                const card = self_card orelse return;
                if (card.ability_used_this_turn) return;
                card.ability_used_this_turn = true;
                // Optional: auto-resolve installs first non-operation from HQ
                // Full implementation needs card selection prompt
                _ = g;
            }
        }.handle,
    },
    .{ .title = "BANGUN: When Disaster Strikes", .side = .corp, .code = 35068, .card_type = "Identity", .subtypes = &.{"Corp"},
        // "Install agendas faceup. On access of faceup agenda: 2 meat damage + 1 tag."
        // Needs faceup install mechanic + access trigger
        // Complex: modifies corp install flow + access damage
    },
    .{ .title = "The Zwicky Group: Invisible Hands", .side = .corp, .code = 35069, .card_type = "Identity", .subtypes = &.{"Unsubstantiated"},
        // "First time each turn you gain credits through an ability on an agenda or operation, you may draw 1 card."
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .operation_played; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
                if (std.mem.eql(u8, choice_text, "Yes")) {
                    try drawCards(g, .corp, 1);
                    g.systemMsg(.corp, 35069, "Corp uses The Zwicky Group to draw 1 card.", .{});
                }
                g.corp_prompt_state = null;
                g.runner_prompt_state = null;
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(g.arena.allocator(), g);
            }
        }.choice,
    },
    // --- Elevation Agendas ---
    .{ .title = "Aggressive Trendsetting", .side = .corp, .code = 35037, .card_type = "Agenda", .subtypes = &.{"Initiative"}, .agenda_points = 1, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
        // "First time Runner trashes installed Corp card each turn, they may spend [click]. If not, Corp gets +1 allotted [click] next turn."
        // Complex trigger - requires event system enhancement
    },
    .{ .title = "Project Ingatan", .side = .corp, .code = 35038, .card_type = "Agenda", .subtypes = &.{"Research"}, .agenda_points = 2, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
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
    .{ .title = "Proprionegation", .side = .corp, .code = 35048, .card_type = "Agenda", .subtypes = &.{"Security"}, .agenda_points = 2, .advancement_requirement = 4, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                // "When you score this agenda, place 1 agenda counter on it."
                if (g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = 1;
                }
            }
        }.score,
    },
    .{ .title = "Sericulture Expansion", .side = .corp, .code = 35049, .card_type = "Agenda", .subtypes = &.{"Expansion"}, .agenda_points = 2, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
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
    .{ .title = "Embedded Reporting", .side = .corp, .code = 35059, .card_type = "Agenda", .subtypes = &.{"Initiative"}, .agenda_points = 2, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
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
    .{ .title = "Next Big Thing", .side = .corp, .code = 35060, .card_type = "Agenda", .subtypes = &.{"Initiative"}, .agenda_points = 3, .advancement_requirement = 5, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
        .on_score_fn = &struct {
            fn score(g: *Game, _: state.CardInstance) anyerror!void {
                // "When scored or stolen, place 1 agenda counter on it."
                if (g.corp_scored.items.len > 0) {
                    g.corp_scored.items[g.corp_scored.items.len - 1].agenda_counter = 1;
                }
            }
        }.score,
    },
    .{ .title = "Greenmail", .side = .corp, .code = 35070, .card_type = "Agenda", .subtypes = &.{"Expansion"}, .agenda_points = 1, .advancement_requirement = 2, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only }, .on_score = .{ .kind = .gain_credits, .amount = 2 } },
    .{ .title = "Off the Books", .side = .corp, .code = 35071, .card_type = "Agenda", .subtypes = &.{"Initiative"}, .agenda_points = 2, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only },
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
    .{ .title = "Bumi 1.0", .side = .corp, .code = 35041, .card_type = "ICE", .subtypes = &.{ "AP", "Bioroid", "Destroyer", "Sentry" }, .cost = 3, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .trash_program_or_etr },
        .{ .kind = .do_brain_damage, .amount = 1 },
    }, .runner_abilities = &.{
        .{ .kind = .bioroid_break, .click_cost = 1, .break_quantity = 1 },
    },
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
                            if (hosted.installed_ability.is_trojan) {
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
                            if (hosted.installed_ability.is_trojan and trashed_title == null) {
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
    .{ .title = "Empiricist", .side = .corp, .code = 35052, .card_type = "ICE", .subtypes = &.{ "AP", "Observer", "Sentry" }, .cost = 7, .strength = 5, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
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
    .{ .title = "Mycoweb", .side = .corp, .code = 35053, .card_type = "ICE", .subtypes = &.{"Code Gate"}, .cost = 8, .strength = 5, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        // Sub 1: Install a piece of ice from Archives (paying install cost)
        // Sub 2: Rez a piece of ice, paying 2cr less
        // Sub 3: Resolve a sentry subroutine on another rezzed ice
        // Sub 4: Resolve a code gate subroutine on another rezzed ice
        // Subs 3+4 need cross-ICE subroutine resolution (most complex card in set)
        .{ .kind = .corp_install_from_hq_archives },
        .{ .kind = .none }, // rez ice -2 (needs rez prompt with discount)
        .{ .kind = .none }, // resolve sentry sub (needs cross-ICE resolution)
        .{ .kind = .none }, // resolve code gate sub (needs cross-ICE resolution)
    } },
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
    .{ .title = "Biawak", .side = .corp, .code = 35074, .card_type = "ICE", .subtypes = &.{ "Destroyer", "Sentry" }, .cost = 14, .strength = 6, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .trash_program_or_resource_or_etr, .amount = 0 }, // trash 1 program or ETR
        .{ .kind = .trash_program_or_resource_or_etr, .amount = 1 }, // trash 1 resource or ETR
        .{ .kind = .end_the_run },
    } },
    .{ .title = "Kessleroid", .side = .corp, .code = 35075, .card_type = "ICE", .subtypes = &.{"Barrier"}, .cost = 2, .strength = 1, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .end_the_run },
        .{ .kind = .end_the_run },
    } },
    .{ .title = "Syailendra", .side = .corp, .code = 35076, .card_type = "ICE", .subtypes = &.{ "AP", "Code Gate" }, .cost = 4, .strength = 5, .advanceable = true, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .place_advancement_counter, .amount = 1 },
        .{ .kind = .runner_loses_credits, .amount = 2 },
        .{ .kind = .do_net_damage, .amount = 1 },
    } },
    .{ .title = "Flyswatter", .side = .corp, .code = 35079, .card_type = "ICE", .subtypes = &.{"Code Gate"}, .cost = 2, .strength = 0, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
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
    .{ .title = "Lamplighter", .side = .corp, .code = 35080, .card_type = "ICE", .subtypes = &.{ "Observer", "Sentry" }, .cost = 2, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .tag_or_pay_credits_etr, .amount = 3 },
        .{ .kind = .none }, // ETR if tagged (custom)
    } },
    // --- Elevation Assets ---
    .{ .title = "Humanoid Resources", .side = .corp, .code = 35039, .card_type = "Asset", .cost = 1, .trash_cost = 1, .install = .{ .kind = .corp_remote_only },
        // "3 clicks + trash: Gain 9 credits." (corp click ability, handled by corp installed ability)
        .installed_ability = .{ .kind = .click_trash_for_credits, .click_cost = 3, .credit_cost = 9 },
    },
    .{ .title = "Otto Campaign", .side = .corp, .code = 35040, .card_type = "Asset", .subtypes = &.{"Advertisement"}, .cost = 2, .trash_cost = 2, .install = .{ .kind = .corp_remote_only }, .installed_ability = .{
        .kind = .start_of_turn_credits,
        .initial_credit_counters = 6,
        .take_credits_amount = 2,
        .trash_on_empty = true,
        .clicks_on_empty = 2,
    } },
    .{ .title = "Byte!", .side = .corp, .code = 35050, .card_type = "Asset", .subtypes = &.{"Ambush"}, .cost = 0, .trash_cost = 0, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Ph\xe1\xba\xadt Gioan Baotixita", .side = .corp, .code = 35051, .card_type = "Asset", .subtypes = &.{"Executive"}, .cost = 1, .trash_cost = 3, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Idiosyncresis", .side = .corp, .code = 35061, .card_type = "Asset", .subtypes = &.{"Hostile"}, .cost = 1, .trash_cost = 2, .advanceable = true, .install = .{ .kind = .corp_remote_only },
        // "When your turn begins, you may trash this asset. If you do, for each hosted advancement counter, gain 3cr and the Runner loses 2cr."
        // This is a start-of-turn optional effect - implemented as auto-trigger when advancement counters > 0
    },
    .{ .title = "Public Access Plaza", .side = .corp, .code = 35062, .card_type = "Asset", .cost = 1, .trash_cost = 2, .install = .{ .kind = .corp_remote_only },
        .installed_ability = .{ .start_of_turn_bank_credits = 1 },
    },
    .{ .title = "Anthill Excavation Contract", .side = .corp, .code = 35072, .card_type = "Asset", .subtypes = &.{"Industrial"}, .cost = 3, .trash_cost = 1, .install = .{ .kind = .corp_remote_only }, .installed_ability = .{
        .kind = .start_of_turn_credits,
        .initial_credit_counters = 8,
        .take_credits_amount = 4,
        .trash_on_empty = true,
        .draw_on_take = 1,
    } },
    .{ .title = "Plutus", .side = .corp, .code = 35073, .card_type = "Asset", .subtypes = &.{"Deep Net"}, .cost = 0, .trash_cost = 3, .install = .{ .kind = .corp_remote_only } },
    // --- Elevation Upgrades ---
    .{ .title = "Mercia B4LL4RD", .side = .corp, .code = 35045, .card_type = "Upgrade", .subtypes = &.{ "Academic", "Bioroid" }, .cost = 2, .trash_cost = 2, .install = .{ .kind = .corp_server_choice } },
    .{ .title = "Mitra Aman", .side = .corp, .code = 35056, .card_type = "Upgrade", .subtypes = &.{"Clone"}, .cost = 0, .trash_cost = 3, .install = .{ .kind = .corp_server_choice } },
    .{ .title = "Mahkota Langit Grid", .side = .corp, .code = 35082, .card_type = "Upgrade", .subtypes = &.{"Region"}, .cost = 2, .trash_cost = 2, .install = .{ .kind = .corp_server_choice },
        // "2 recurring credits for rez costs. Persistent: trash cost of assets in root +2."
        // Recurring credits handled via initial counters. Trash cost increase is static.
        .installed_ability = .{ .initial_credit_counters = 2 },
    },
    // --- Elevation Operations ---
    .{ .title = "Nanomanagement", .side = .corp, .code = 35043, .card_type = "Operation", .cost = 4, .corp_play = .{ .kind = .custom }, .on_play = &struct {
        fn play(g: *Game, _: state.CardInstance) anyerror!void {
            g.corp_click += 2;
        }
    }.play, .on_play_msg = "gain [Click][Click]." },
    .{ .title = "Top-Down Solutions", .side = .corp, .code = 35044, .card_type = "Operation", .cost = 2,
        .corp_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
                // "Draw 2 cards. Install up to 2 cards from HQ (one at a time)."
                try drawCards(g, .corp, 2);
                g.systemMsg(.corp, 35044, "Corp uses Top-Down Solutions to draw 2 cards.", .{});
                // Offer install prompt
                try showTopDownInstallChoices(g, card, 0);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                const allocator = g.arena.allocator();
                const prompt = g.corp_prompt_state orelse return error.NoPromptState;
                if (std.mem.eql(u8, prompt.prompt_type, "top-down-card")) {
                    if (std.mem.eql(u8, choice_text, "Done")) {
                        g.corp_prompt_state = null;
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                        return;
                    }
                    // Find the card in hand
                    for (prompt.choices) |ch| {
                        if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                            if (ch.card) |card_ref| {
                                const card_idx = card_ref.index orelse continue;
                                // Show server choices
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
                        try showTopDownInstallChoices(g, prompt.source_card orelse return error.NoPromptState, installs_done + 1);
                    }
                } else return error.UnsupportedChoice;
            }
        }.choice,
    },
    .{ .title = "Peer Review", .side = .corp, .code = 35055, .card_type = "Operation", .subtypes = &.{"Transaction"}, .cost = 4,
        .corp_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
                const allocator = g.arena.allocator();
                // Gain 7 credits
                g.corp_credit += 7;
                g.systemMsg(.corp, 35055, "Corp uses Peer Review to gain 7 [credits].", .{});
                // Offer to install a non-ice non-operation card from HQ into a remote
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
                if (installable.items.len > 0) {
                    try installable.append(allocator, stringChoice("Done"));
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "peer-review-install"),
                        .choices = try installable.toOwnedSlice(allocator),
                        .source_card = card,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                    return;
                }
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                const allocator = g.arena.allocator();
                const prompt = g.corp_prompt_state orelse return error.NoPromptState;
                if (std.mem.eql(u8, prompt.prompt_type, "peer-review-install")) {
                    if (std.mem.eql(u8, choice_text, "Done")) {
                        g.corp_prompt_state = null;
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                        return;
                    }
                    // Find the chosen card in hand and offer server choice
                    for (prompt.choices) |ch| {
                        if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                            if (ch.card) |card_ref| {
                                // Store the card index for the next step
                                var server_choices: std.ArrayList(state.PromptChoice) = .empty;
                                defer server_choices.deinit(allocator);
                                // Add existing remote servers
                                for (g.corp_servers.items, 0..) |_, si| {
                                    if (si < 4) continue; // skip HQ, R&D, Archives, placeholder
                                    const name = try std.fmt.allocPrint(allocator, "Server {d}", .{si - 3});
                                    try server_choices.append(allocator, stringChoice(name));
                                }
                                try server_choices.append(allocator, stringChoice("New remote"));
                                g.corp_prompt_state = .{
                                    .prompt_type = try allocator.dupe(u8, "peer-review-server"),
                                    .choices = try server_choices.toOwnedSlice(allocator),
                                    .source_card = .{
                                        .title = card_ref.title orelse "Peer Review",
                                        .side = .corp,
                                        .code = card_ref.code,
                                        .card_type = "Operation",
                                    },
                                    .min_choices = card_ref.index orelse 0,
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
        }.choice,
    },
    .{ .title = "Bigger Picture", .side = .corp, .code = 35065, .card_type = "Operation", .subtypes = &.{"Gray Ops"}, .cost = 0,
        .corp_play = .{ .kind = .custom },
        .can_play = &struct {
            fn check(g: *const Game) bool {
                // "Play only if the Runner is tagged."
                return if (g.runner_tag) |t| t.is_tagged else false;
            }
        }.check,
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
                // "Choose: Give the Runner 1 tag OR Remove any number of tags. Runner loses 5cr per tag. Gain credits equal to credits lost."
                const allocator = g.arena.allocator();
                var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                defer choices_list.deinit(allocator);
                try choices_list.append(allocator, stringChoice("Give the Runner 1 tag"));
                try choices_list.append(allocator, stringChoice("Remove tags and drain credits"));
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "bigger-picture"),
                    .choices = try choices_list.toOwnedSlice(allocator),
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
                    g.decision_side = .corp;
                    g.legal_actions = try corpOpeningActionsForState(allocator, g);
                }
            }
        }.choice,
    },
    .{ .title = "IP Enforcement", .side = .corp, .code = 35066, .card_type = "Operation", .subtypes = &.{"Gray Ops"}, .cost = 0,
        .corp_play = .{ .kind = .custom },
        .can_play = &struct {
            fn check(g: *const Game) bool {
                // Requires runner to be tagged and have stolen agendas
                const tagged = if (g.runner_tag) |t| t.is_tagged else false;
                return tagged and g.runner_scored.items.len > 0;
            }
        }.check,
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
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
                        .source_card = card,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
                g.decision_side = .corp;
                g.legal_actions = try corpOpeningActionsForState(allocator, g);
            }
        }.choice,
    },
    .{ .title = "Touch-ups", .side = .corp, .code = 35067, .card_type = "Operation", .subtypes = &.{"Double"}, .cost = 2,
        .corp_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
                // Additional cost: spend [click] (Double)
                try spendClicks(g, .corp, 1);
                // "Place 2 advancement counters on 1 installed card you can advance."
                const allocator = g.arena.allocator();
                const adv_choices = try installedCardChoices(allocator, g.corp_servers.items);
                if (adv_choices.len > 0) {
                    g.corp_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "touch-ups-advance"),
                        .choices = adv_choices,
                        .source_card = card,
                    };
                    g.decision_side = .corp;
                    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                }
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
        }.choice,
    },
    .{ .title = "Key Performance Indicators", .side = .corp, .code = 35077, .card_type = "Operation", .subtypes = &.{"Transaction"}, .cost = 1,
        .corp_play = .{ .kind = .custom },
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
                // "Resolve 2 of: Gain 2cr, Install ice ignoring costs, Place 1 advancement, Draw 1 + shuffle 1"
                try showKpiChoices(g, card, 0);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                const allocator = g.arena.allocator();
                const prompt = g.corp_prompt_state orelse return error.NoPromptState;
                if (std.mem.eql(u8, prompt.prompt_type, "kpi-choose")) {
                    const choices_made = prompt.min_choices;
                    if (std.mem.eql(u8, choice_text, "Gain 2 [Credits]")) {
                        g.corp_credit += 2;
                        g.systemMsg(.corp, 35077, "Corp uses Key Performance Indicators to gain 2 [credits].", .{});
                    } else if (std.mem.eql(u8, choice_text, "Draw 1 card")) {
                        try drawCards(g, .corp, 1);
                        g.systemMsg(.corp, 35077, "Corp uses Key Performance Indicators to draw 1 card.", .{});
                    } else if (std.mem.eql(u8, choice_text, "Done")) {
                        g.corp_prompt_state = null;
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                        return;
                    } else if (std.mem.eql(u8, choice_text, "Place 1 advancement counter")) {
                        // Need advance prompt
                        const adv_choices = try installedCardChoices(allocator, g.corp_servers.items);
                        if (adv_choices.len > 0) {
                            g.corp_prompt_state = .{
                                .prompt_type = try allocator.dupe(u8, "kpi-advance"),
                                .choices = adv_choices,
                                .source_card = prompt.source_card,
                                .min_choices = choices_made + 1,
                            };
                            g.decision_side = .corp;
                            g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                            return;
                        }
                    } else if (std.mem.eql(u8, choice_text, "Install 1 piece of ice from HQ")) {
                        // Need ice install prompt
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
                            };
                            g.decision_side = .corp;
                            g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
                            return;
                        }
                    } else return error.UnsupportedChoice;
                    // Move to next choice or finish
                    if (choices_made + 1 >= 2) {
                        g.corp_prompt_state = null;
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                    } else {
                        try showKpiChoices(g, prompt.source_card orelse return error.NoPromptState, choices_made + 1);
                    }
                } else if (std.mem.eql(u8, prompt.prompt_type, "kpi-advance")) {
                    _ = try addAdvancementCounter(g, choice_text, 1);
                    g.systemMsg(.corp, 35077, "Corp uses Key Performance Indicators to place 1 advancement counter.", .{});
                    if (prompt.min_choices >= 2) {
                        g.corp_prompt_state = null;
                        g.decision_side = .corp;
                        g.legal_actions = try corpOpeningActionsForState(allocator, g);
                    } else {
                        try showKpiChoices(g, prompt.source_card orelse return error.NoPromptState, prompt.min_choices);
                    }
                } else if (std.mem.eql(u8, prompt.prompt_type, "kpi-ice-choose")) {
                    // Find ice in hand by title
                    for (prompt.choices) |ch| {
                        if (ch.text != null and std.mem.eql(u8, ch.text.?, choice_text)) {
                            if (ch.card) |card_ref| {
                                // Show server choices for ice install
                                const server_choices = try installChoicesForCard(allocator, .corp_server_choice, g);
                                g.corp_prompt_state = .{
                                    .prompt_type = try allocator.dupe(u8, "kpi-ice-server"),
                                    .choices = server_choices,
                                    .source_card = prompt.source_card,
                                    .min_choices = @intCast((card_ref.index orelse 0) | (@as(u8, prompt.min_choices) << 4)),
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
                        try showKpiChoices(g, prompt.source_card orelse return error.NoPromptState, choices_done);
                    }
                } else return error.UnsupportedChoice;
            }
        }.choice,
    },
    .{ .title = "Measured Response", .side = .corp, .code = 35078, .card_type = "Operation", .subtypes = &.{"Black Ops"}, .cost = 5, .trash_cost = 3,
        .corp_play = .{ .kind = .custom },
        .can_play = &struct {
            fn check(g: *const Game) bool {
                // "Play only if the threat level is 4 or greater, and only if the Runner made a successful run during their last turn."
                return threatLevel(g) >= 4;
            }
        }.check,
        .on_play = &struct {
            fn play(g: *Game, card: state.CardInstance) anyerror!void {
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
                    .source_card = card,
                };
                g.corp_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "waiting"),
                    .choices = &.{},
                    .source_card = null,
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
        }.choice,
    },
    .{ .title = "Petty Cash", .side = .corp, .code = 35081, .card_type = "Operation", .subtypes = &.{"Transaction"}, .cost = 3, .corp_play = .{ .kind = .gain_credits, .gain_credits = 5 },
        .can_play = &struct {
            fn check(g: *const Game) bool {
                // "Play only if you have not finished an action yet this turn."
                return g.corp_click == g.corp_click_per_turn;
            }
        }.check,
    },
    // --- Elevation Runner Events ---
    .{ .title = "Charm Offensive", .side = .runner, .code = 35003, .card_type = "Event", .subtypes = &.{"Run"}, .cost = 0,
        .runner_play = .{ .kind = .choose_run_target, .run_target_kind = .archives_only },
    },
    .{ .title = "Scrounge", .side = .runner, .code = 35004, .card_type = "Event", .subtypes = &.{"Double"}, .cost = 1,
        .runner_play = .{ .kind = .custom, .lose_clicks = 1 },
        .on_play = &struct {
            fn play(g: *Game, _: state.CardInstance) anyerror!void {
                // Additional cost: spend [click] (Double)
                try spendClicks(g, .runner, 1);
                // "Install 1 program from your heap."
                const allocator = g.arena.allocator();
                var choices_list: std.ArrayList(state.PromptChoice) = .empty;
                defer choices_list.deinit(allocator);
                for (g.runner_discard.items, 0..) |c, idx| {
                    const ct = c.card_type orelse continue;
                    if (!std.mem.eql(u8, ct, "Program")) continue;
                    try choices_list.append(allocator, .{
                        .kind = .card,
                        .text = try std.fmt.allocPrint(allocator, "{s}", .{c.title}),
                        .card = .{ .title = c.title, .code = c.code, .side = .runner, .index = @intCast(idx) },
                    });
                }
                if (choices_list.items.len > 0) {
                    g.runner_prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "scrounge-install"),
                        .choices = try choices_list.toOwnedSlice(allocator),
                        .source_card = null,
                    };
                    g.decision_side = .runner;
                    g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
                } else {
                    g.decision_side = .runner;
                    g.legal_actions = try runnerOpeningActionsForState(allocator, g);
                }
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
                const allocator = g.arena.allocator();
                const prompt = g.runner_prompt_state orelse return error.NoPromptState;
                if (std.mem.eql(u8, prompt.prompt_type, "scrounge-install")) {
                    // Find program in heap by title
                    for (g.runner_discard.items, 0..) |c, idx| {
                        if (std.mem.eql(u8, c.title, choice_text)) {
                            const card = g.runner_discard.orderedRemove(idx);
                            const install_cost = card.cost orelse 0;
                            try spendCredits(g, .runner, install_cost);
                            try appendRunnerInstalledCard(g, card);
                            g.systemMsg(.runner, 35004, "Runner uses Scrounge to install {s} from the heap.", .{card.title});
                            break;
                        }
                    }
                    g.runner_prompt_state = null;
                    g.decision_side = .runner;
                    g.legal_actions = try runnerOpeningActionsForState(allocator, g);
                } else return error.UnsupportedChoice;
            }
        }.choice,
    },
    .{ .title = "Shred", .side = .runner, .code = 35005, .card_type = "Event", .subtypes = &.{"Run"}, .cost = 1,
        .runner_play = .{ .kind = .choose_run_target },
    },
    .{ .title = "Clean Getaway", .side = .runner, .code = 35014, .card_type = "Event", .subtypes = &.{"Run"}, .cost = 3, .runner_play = .{ .kind = .choose_run_target, .gain_credits = 6, .successful_run_effect = .draw_cards, .successful_run_draw_cards = 0 } },
    .{ .title = "Lie Low", .side = .runner, .code = 35015, .card_type = "Event", .subtypes = &.{"Double"}, .cost = 1,
        .runner_play = .{ .kind = .custom, .lose_clicks = 1 },
        .on_play = &struct {
            fn play(g: *Game, _: state.CardInstance) anyerror!void {
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
                };
                g.decision_side = .runner;
                g.legal_actions = try promptChoiceActions(allocator, .runner, g.runner_prompt_state.?);
            }
        }.play,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
                    g.decision_side = .runner;
                    g.legal_actions = try runnerOpeningActionsForState(allocator, g);
                } else return error.UnsupportedChoice;
            }
        }.choice,
    },
    .{ .title = "Maintenance Access", .side = .runner, .code = 35016, .card_type = "Event", .subtypes = &.{ "Double", "Run" }, .cost = 0,
        .runner_play = .{ .kind = .choose_run_target, .run_target_kind = .archives_only, .lose_clicks = 1 },
    },
    .{ .title = "Transfer of Wealth", .side = .runner, .code = 35017, .card_type = "Event", .subtypes = &.{"Run"}, .cost = 0,
        .runner_play = .{ .kind = .choose_run_target, .run_target_kind = .hq_only },
    },
    .{ .title = "Illumination", .side = .runner, .code = 35025, .card_type = "Event", .subtypes = &.{"Run"}, .cost = 0,
        .runner_play = .{ .kind = .choose_run_target, .run_target_kind = .rd_only },
    },
    .{ .title = "Ritual", .side = .runner, .code = 35026, .card_type = "Event", .cost = 0, .runner_play = .{ .kind = .custom },
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
        }.play, .on_play_msg = "draw cards equal to remaining clicks." },
    // --- Elevation Runner Hardware ---
    .{ .title = "Bling", .side = .runner, .code = 35006, .card_type = "Hardware", .subtypes = &.{"Console"}, .cost = 2, .runner_install = .{ .kind = .hardware, .mu_cost = 0 }, .installed_ability = .{ .is_console = true, .mu_provided = 1 },
        // "+1 MU. On free install: host top of stack faceup on Bling."
        // "Can play/install hosted cards as if in grip. End of discard phase: trash hosted."
        // Needs: free-install event trigger, hosted card management, end-of-turn cleanup.
        // Auto-declined in oracle: hosting triggers are optional.
    },
    .{ .title = "Detente", .side = .runner, .code = 35018, .card_type = "Hardware", .subtypes = &.{"Console"}, .cost = 3, .runner_install = .{ .kind = .hardware, .mu_cost = 0 }, .installed_ability = .{ .is_console = true, .mu_provided = 1 },
        // "+1 MU. First successful HQ run: host 1 random HQ card faceup on Detente."
        // "Click + return 2 hosted to HQ: access 1 random HQ card. Both sides can use."
        // Needs: successful_run_ends HQ trigger, click ability, access mechanic.
        // Auto-declined in oracle: hosting trigger is optional.
    },
    .{ .title = "Maglectric Rapid (748 Mod)", .side = .runner, .code = 35019, .card_type = "Hardware", .subtypes = &.{"Weapon"}, .cost = 1, .runner_install = .{ .kind = .hardware, .mu_cost = 0 },
        // "Whenever you make a successful run on HQ, you may trash this hardware to derez 1 installed Corp card."
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .successful_run_ends; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, _: ?*state.CardInstance) anyerror!void {
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
                                .title = ice.title, .code = ice.code, .side = .corp,
                            } }) catch continue;
                        }
                    }
                    for (srv.content.items) |c| {
                        if (c.rezzed) {
                            const is_agenda = if (c.card_type) |ct| std.mem.eql(u8, ct, "Agenda") else false;
                            if (!is_agenda) {
                                choices.append(allocator, .{ .kind = .card, .text = c.title, .card = .{
                                    .title = c.title, .code = c.code, .side = .corp,
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
                };
                g.decision_side = .runner;
                g.legal_actions = promptChoiceActions(allocator, .runner, g.runner_prompt_state.?) catch return;
            }
        }.handle,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
        }.choice,
    },
    .{ .title = "GAMEDRAGON\xe2\x84\xa2 Pro", .side = .runner, .code = 35027, .card_type = "Hardware", .subtypes = &.{"Mod"}, .cost = 2, .runner_install = .{ .kind = .hardware, .mu_cost = 0 },
        // "On install + turn begin: may host on non-AI icebreaker. Host gets +1 str.
        //  Pump abilities last for remainder of run instead of shorter duration."
    },
    .{ .title = "Madani", .side = .runner, .code = 35028, .card_type = "Hardware", .subtypes = &.{"Console"}, .cost = 2, .runner_install = .{ .kind = .hardware, .mu_cost = 0 }, .installed_ability = .{ .is_console = true },
        // "Click: Host any number of programs from grip faceup.
        //  Once per turn → 0cr: Install 1 hosted program (paying cost)."
        // Hosting ability: auto-declined in oracle auto-resolve mode.
        // Full implementation needs: click ability to host + install-from-host action.
    },
    // --- Elevation Runner Programs ---
    .{ .title = "Gourmand", .side = .runner, .code = 35007, .card_type = "Program", .cost = 0, .runner_install = .{ .kind = .program },
        .installed_ability = .{ .trash_access_self_trash = true, .trash_access_draw = 1 },
    },
    .{ .title = "Hantu", .side = .runner, .code = 35008, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer", "Virus" }, .cost = 3, .strength = 2, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .break_subroutine_count = 1,
        .credit_cost = 1,
        .initial_virus_counters = 2, // Place 2 virus counters on install
    }, .pump_ability = .{
        .kind = .pump_strength,
        .pump_strength_amount = 2,
        .pump_uses_virus_counters = true, // Hosted virus counter: +2 strength
    } },
    .{ .title = "Rising Tide", .side = .runner, .code = 35009, .card_type = "Program", .subtypes = &.{ "Fracter", "Icebreaker" }, .cost = 1, .strength = 1, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .break_subroutine_count = 1,
        .credit_cost = 1,
        .strength_per_heap_fracter = true, // +1 strength per fracter in heap
    }, .pump_ability = .{
        .kind = .pump_strength,
        .pump_strength_amount = 1,
        .credit_cost = 1,
    } },
    .{ .title = "Sang Kancil", .side = .runner, .code = 35020, .card_type = "Program", .subtypes = &.{ "Decoder", "Icebreaker" }, .cost = 3, .strength = 2, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .break_subroutine_count = 1,
        .credit_cost = 1,
    }, .pump_ability = .{
        .kind = .pump_strength,
        .pump_strength_amount = 2,
        .credit_cost = 3,
        .pump_discount_if_run_event = 2, // 2cr less if a run event is active
    } },
    .{ .title = "Azimat", .side = .runner, .code = 35029, .card_type = "Program", .cost = 1, .runner_install = .{ .kind = .program, .mu_cost = 2 },
        // "2 recurring credits. You can spend hosted credits to pay trash costs."
        .installed_ability = .{ .initial_credit_counters = 2, .recurring_credits = 2 },
    },
    .{ .title = "Chromatophores", .side = .runner, .code = 35030, .card_type = "Program", .subtypes = &.{"Trojan"}, .cost = 1, .runner_install = .{ .kind = .program }, .installed_ability = .{ .is_trojan = true, .trojan_adds_all_subtypes = true } },
    .{ .title = "Devadatta Drone", .side = .runner, .code = 35031, .card_type = "Program", .cost = 1, .runner_install = .{ .kind = .program },
        .installed_ability = .{ .initial_power_counters = 2 },
        // R&D access bonus handled via event system
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .successful_run_ends; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, self_card: ?*state.CardInstance) anyerror!void {
                if (g.run == null) return;
                const server = g.run.?.server;
                // Only trigger on R&D runs
                if (server.len == 0 or !std.mem.eql(u8, server[0], "rnd")) return;
                const card = self_card orelse return;
                if (card.power_counter == 0) return;
                card.power_counter -= 1;
                g.run.?.access_bonus += 1;
            }
        }.handle,
        .on_event_msg = "access 1 additional card from R&D.",
    },
    .{ .title = "Principia", .side = .runner, .code = 35032, .card_type = "Program", .subtypes = &.{ "Fracter", "Icebreaker" }, .cost = 4, .strength = 2, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .break_subroutine_count = 1,
        .credit_cost = 1,
        .install_cost_reduction_per_icebreaker = true, // -1 cost per other installed icebreaker
    }, .pump_ability = .{
        .kind = .pump_strength,
        .pump_strength_amount = 2,
        .credit_cost = 2,
    } },
    // --- Elevation Runner Resources ---
    .{ .title = "Cacophony", .side = .runner, .code = 35010, .card_type = "Resource", .subtypes = &.{"Virtual"}, .cost = 3, .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        // "First time each turn you steal or trash a Corp card, place 1 power counter."
        // "When your action phase ends, you may remove 2 hosted power counters to sabotage 3."
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .agenda_stolen or e == .runner_trash_corp_card; } }.m,
        .on_event = &struct {
            fn handle(_: *Game, self_card: ?*state.CardInstance) anyerror!void {
                const card = self_card orelse return;
                // First steal/trash only (once per turn via ability_used_this_turn)
                if (card.ability_used_this_turn) return;
                card.power_counter += 1;
                card.ability_used_this_turn = true;
            }
        }.handle,
        .on_event_msg = "place 1 power counter on Cacophony.",
    },
    .{ .title = "Rent Rioters", .side = .runner, .code = 35011, .card_type = "Resource", .subtypes = &.{ "Connection", "Seedy" }, .cost = 2, .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        .installed_ability = .{
            .kind = .click_trash_for_credits,
            .click_cost = 3,
            .credit_cost = 9, // gain amount (reusing credit_cost field for this)
        },
    },
    .{ .title = "Fransofia Ward", .side = .runner, .code = 35021, .card_type = "Resource", .subtypes = &.{"Connection"}, .cost = 3, .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        .installed_ability = .{ .rez_cost_increase = 1 }, // The rez cost of each piece of ice is increased by 1
        // "Whenever you encounter a piece of ice, if the Corp has 15cr or more, you may trash this resource to bypass that ice."
        // Bypass handled via encounter event check
    },
    .{ .title = "Open Market", .side = .runner, .code = 35022, .card_type = "Resource", .subtypes = &.{ "Job", "Location" }, .cost = 2, .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        .installed_ability = .{
            .kind = .start_of_turn_credits,
            .initial_credit_counters = 6,
            .take_credits_amount = 1,
            .trash_on_empty = true,
        },
    },
    .{ .title = "\"Knickknack\" O'Brian", .side = .runner, .code = 35033, .card_type = "Resource", .subtypes = &.{"Connection"}, .cost = 2, .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        // "First time each turn a run begins, you may trash 1 of your other installed cards.
        //  If you do, gain credits equal to its printed install cost and draw 1 card."
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .run_begins; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, self_card: ?*state.CardInstance) anyerror!void {
                const card = self_card orelse return;
                if (card.ability_used_this_turn) return;
                card.ability_used_this_turn = true;
                // Check if runner has other installed cards (need at least 2 total)
                const total_installed = g.runner_rig_resources.items.len + g.runner_rig_program.items.len + g.runner_rig_hardware.items.len;
                if (total_installed < 2) return; // Only Knickknack itself, nothing to trash
                // Build choices: all other installed runner cards
                const allocator = g.arena.allocator();
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                for (g.runner_rig_resources.items) |c| {
                    if (c.code != null and c.code.? == 35033) continue; // skip self
                    choices.append(allocator, .{ .kind = .card, .text = c.title, .card = .{
                        .title = c.title, .code = c.code, .side = .runner,
                    } }) catch continue;
                }
                for (g.runner_rig_program.items) |c| {
                    choices.append(allocator, .{ .kind = .card, .text = c.title, .card = .{
                        .title = c.title, .code = c.code, .side = .runner,
                    } }) catch continue;
                }
                for (g.runner_rig_hardware.items) |c| {
                    choices.append(allocator, .{ .kind = .card, .text = c.title, .card = .{
                        .title = c.title, .code = c.code, .side = .runner,
                    } }) catch continue;
                }
                choices.append(allocator, stringChoice("No action")) catch return;
                g.runner_prompt_state = .{
                    .prompt_type = allocator.dupe(u8, "knickknack-trash") catch return,
                    .choices = choices.toOwnedSlice(allocator) catch return,
                    .source_card = card.*,
                };
                g.decision_side = .runner;
                g.legal_actions = promptChoiceActions(allocator, .runner, g.runner_prompt_state.?) catch return;
            }
        }.handle,
        .on_prompt_choice = &struct {
            fn choice(g: *Game, choice_text: []const u8) anyerror!void {
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
        }.choice,
    },
    .{ .title = "Side Hustle", .side = .runner, .code = 35034, .card_type = "Resource", .subtypes = &.{"Job"}, .cost = 2, .runner_install = .{ .kind = .resource, .mu_cost = 0 },
        .installed_ability = .{
            .initial_credit_counters = 1, // 1 credit on install
            .credit_on_run_start = true, // place 1 credit when any run begins
            .auto_trash_at_credits = 6, // auto-trash when 6+ credits
            .draw_on_auto_trash = 1, // draw 1 on auto-trash
        },
        .event_match = &struct { fn m(e: state.GameEvent) bool { return e == .run_begins; } }.m,
        .on_event = &struct {
            fn handle(g: *Game, self_card: ?*state.CardInstance) anyerror!void {
                const card = self_card orelse return;
                card.credit_counter += 1;
                g.systemMsg(.runner, card.code orelse 0, "Runner places 1 [credit] on {s}.", .{card.title});
                if (card.credit_counter >= card.installed_ability.auto_trash_at_credits) {
                    g.runner_credit += card.credit_counter;
                    g.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credits] and draw {d} card{s}.", .{
                        card.title, card.credit_counter, card.installed_ability.draw_on_auto_trash,
                        if (card.installed_ability.draw_on_auto_trash != 1) @as([]const u8, "s") else "",
                    });
                    card.credit_counter = 0;
                    try drawCards(g, .runner, card.installed_ability.draw_on_auto_trash);
                    // Remove self from resources
                    if (findRunnerResourceIndex(g, card.code orelse 0)) |idx| {
                        const trashed = g.runner_rig_resources.orderedRemove(idx);
                        try appendDiscardCard(g, .runner, trashed);
                    }
                }
            }
        }.handle,
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
pub const system_gateway_tao = MatchupSpec{
    .format = "system-gateway", .agenda_point_req = 7,
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
    .format = "system-gateway", .agenda_point_req = 7,
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
    .format = "system-gateway", .agenda_point_req = 7,
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
    .format = "system-gateway", .agenda_point_req = 7,
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
    .format = "system-gateway", .agenda_point_req = 7,
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
    .format = "system-gateway", .agenda_point_req = 7,
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
    .format = "system-gateway", .agenda_point_req = 7,
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
    .format = "system-gateway", .agenda_point_req = 7,
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
    .format = "system-gateway", .agenda_point_req = 7,
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
    .format = "system-gateway", .agenda_point_req = 7,
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
    corp_phase_12: bool = false,
    cannot_score_agendas_this_turn: bool = false, // Luminal Transubstantiation
    last_scored_server_index: ?usize = null, // Server from which last agenda was scored
    tao_first_ice: ?[]const u8 = null, // Tao: first ICE selection (server_idx|ice_idx|title)
    pending_effects: std.ArrayListUnmanaged(PendingEffect) = .empty, // Async effect continuation queue
    pending_sprint_selections: std.ArrayListUnmanaged([]const u8) = .empty, // Sprint batched card selections

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

const prompt_run_central = "run-central";
const prompt_hq_access = "hq-access";
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
        .rez_ice => {
            try applyRezApproachedIce(generated);
        },
        .advance => {
            const choice = action.choice orelse return error.MissingChoice;
            const choice_text = choice.text orelse return error.MissingChoice;
            try applyAdvanceInstalledChoice(generated, choice_text);
        },
        .score => {
            const choice = action.choice orelse return error.MissingChoice;
            const choice_text = choice.text orelse return error.MissingChoice;
            try applyScoreAgendaChoice(generated, choice_text);
        },
        .use_identity_ability => {
            try applyIdentityAbility(generated, action.side);
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
                if (card.installed_ability.kind == .place_credits and card.credit_counter > 0) {
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
                    if (card.installed_ability.kind == .start_of_turn_credits and card.credit_counter > 0) {
                        const take = @min(card.credit_counter, card.installed_ability.take_credits_amount);
                        card.credit_counter -= take;
                        generated.runner_credit += take;
                        generated.systemMsg(.runner, card.code orelse 0, "Runner takes {d} [credit{s}] from {s}.", .{
                            take, if (take != 1) "s" else "", card.title,
                        });
                        if (card.installed_ability.trash_on_empty and card.credit_counter == 0) {
                            if (card.installed_ability.draw_on_empty > 0) {
                                try drawCards(generated, .runner, card.installed_ability.draw_on_empty);
                            }
                            const trashed = generated.runner_rig_resources.orderedRemove(ri);
                            try appendDiscardCard(generated, .runner, trashed);
                            continue;
                        }
                    }
                    ri += 1;
                }
            }

            // Recurring credits: refill hosted credits on programs (Azimat)
            for (generated.runner_rig_program.items) |*prog| {
                if (prog.installed_ability.recurring_credits > 0) {
                    prog.credit_counter = prog.installed_ability.recurring_credits;
                }
            }

            // Virus-on-turn-start: Fermenter (rig), Botulus/Tranquilizer (hosted on ICE)
            for (generated.runner_rig_program.items) |*prog| {
                if (prog.installed_ability.virus_on_turn_start) {
                    prog.virus_counter += 1;
                }
            }
            // Trojans hosted on ICE: increment virus counters and check Tranquilizer derez
            for (generated.corp_servers.items) |*server| {
                for (server.ices.items) |*ice| {
                    for (ice.hosted) |*hosted| {
                        if (hosted.installed_ability.virus_on_turn_start) {
                            hosted.virus_counter += 1;
                            if (hosted.installed_ability.trojan_derez_threshold > 0 and hosted.virus_counter >= hosted.installed_ability.trojan_derez_threshold) {
                                ice.rezzed = false;
                            }
                        }
                    }
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
            if (card.power_counter >= 2) {
                if (lookupCardSpecByCode(card.code orelse 0)) |spec| {
                    if (spec.event_match) |matcher| {
                        if (matcher(.agenda_stolen) or matcher(.runner_trash_corp_card)) {
                            // This is a Cacophony-like card with power counters
                            // Auto-resolve: spend counters for sabotage
                            // In oracle auto-resolve, this is optional and often declined
                            // Leave as auto-decline for now
                        }
                    }
                }
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

    // Generic source-card-based prompt dispatch: if the prompt has a source card with
    // on_prompt_choice, use it. Only for card-specific prompt types (not standard access/choice
    // prompts which have their own handlers).
    if (prompt.source_card) |sc| {
        const is_standard_prompt = std.mem.eql(u8, prompt.prompt_type, prompt_access_choice) or
            std.mem.eql(u8, prompt.prompt_type, "net-damage-on-access") or
            std.mem.eql(u8, prompt.prompt_type, prompt_discard) or
            std.mem.eql(u8, prompt.prompt_type, "mulligan") or
            std.mem.eql(u8, prompt.prompt_type, prompt_install_destination);
        if (!is_standard_prompt) {
            if (sc.code) |code| {
                if (lookupCardSpecByCode(code)) |spec| {
                    if (spec.on_prompt_choice) |handler| {
                        try handler(generated, choice_text);
                        if (spec.log_prompt_choice) {
                            generated.systemMsg(spec.side, spec.code, "{s} uses {s} to {s}.", .{ sideName(spec.side), spec.title, choice_text });
                        }
                        if (try resumePendingEffects(generated)) return;
                        // Handler is responsible for setting decision_side and legal_actions
                        return;
                    }
                }
            }
        }
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
            if (generated.runner_tag) |*tag| {
                if (tag.total > 0) {
                    tag.total -= 1;
                    tag.is_tagged = tag.total > 0;
                }
            }
            generated.systemMsg(.runner, 0, "Runner spends [click] and pays 2 [credits] to remove 1 tag.", .{});
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
    const advanced_card = try addAdvancementCounter(generated, choice_text, advancement_amount);
    if (advancement_amount == 1) {
        generated.systemMsg(.corp, advanced_card.code orelse 0, "Corp spends [click] and pays 1 [credit] to advance {s}.", .{advanced_card.title});
    } else {
        if (source_card) |card| {
            generated.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to advance {s} {d} times.", .{ card.title, advanced_card.title, advancement_amount });
        }
    }
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
    generated.systemMsg(.corp, agenda.code orelse 0, "Corp scores {s} and gains {d} agenda point{s}.", .{
        agenda.title,
        agenda_points,
        if (agenda_points != 1) "s" else "",
    });

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
    generated.systemMsg(winner, 0, "{s} wins the game.", .{sideName(winner)});
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
    if (generated.runner_tag) |*tag| {
        var remaining = count;
        while (remaining > 0 and tag.total > 0) : (remaining -= 1) {
            tag.total -= 1;
        }
        tag.is_tagged = tag.total > 0;
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
    }
}

/// Find the array index of a card in runner resources by code (for removal after event)
fn findRunnerResourceIndex(generated: *const Game, code: u32) ?usize {
    for (generated.runner_rig_resources.items, 0..) |card, i| {
        if (card.code != null and card.code.? == code) return i;
    }
    return null;
}

fn drainPendingEffects(generated: *Game) !bool {
    while (generated.pending_effects.items.len > 0) {
        const effect = generated.pending_effects.orderedRemove(0);
        switch (effect) {
            .event_handler => |src| {
                if (lookupCardSpecByCode(src.code)) |spec| {
                    if (spec.on_event) |handler| {
                        const card = findCardByEventSource(generated, src);
                        try handler(generated, card);
                        if (spec.on_event_msg) |msg| {
                            generated.systemMsg(spec.side, spec.code, "{s} uses {s} to {s}", .{ sideName(spec.side), spec.title, msg });
                        }
                        if (hasActivePrompt(generated)) return true;
                    }
                }
            },
            .on_score_gain_credits => |amount| {
                generated.corp_credit += amount;
                generated.systemMsg(.corp, 0, "Corp gains {d} [credit{s}].", .{ amount, if (amount != 1) "s" else "" });
            },
            .on_score_draw_cards => |info| {
                try drawCards(generated, .corp, info.amount);
                generated.systemMsg(.corp, info.card_code, "Corp draws {d} card{s}.", .{ info.amount, if (info.amount != 1) "s" else "" });
                // Apply hand size bonus from scored agenda (Superconducting Hub)
                if (lookupCardSpecByCode(info.card_code)) |spec| {
                    if (spec.on_score.hand_size_bonus > 0) {
                        generated.corp_hand_size.base += spec.on_score.hand_size_bonus;
                        generated.corp_hand_size.total += spec.on_score.hand_size_bonus;
                    }
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
                generated.systemMsg(.corp, 0, "Runner gains {d} tag{s}.", .{ amount, if (amount != 1) "s" else "" });
                if (amount > 0) {
                    generated.turn_events.runner_gain_tag_count += 1;
                    // Queue event handlers for runner_gain_tag (instead of calling fireEvent)
                    try collectEventHandlers(generated, .runner_gain_tag);
                }
            },
            .on_score_gain_clicks => |amount| {
                generated.corp_click += amount;
                generated.cannot_score_agendas_this_turn = true;
                generated.systemMsg(.corp, 0, "Corp gains {d} [click{s}].", .{ amount, if (amount != 1) "s" else "" });
            },
            .on_score_rez_ice_free => |scored_agenda| {
                if (try beginRezIceFreePromptForScore(generated, scored_agenda)) return true;
            },
            .on_score_fn => |scored_agenda| {
                if (lookupCardSpec(scored_agenda)) |spec| {
                    if (spec.on_score_fn) |handler| {
                        try handler(generated, scored_agenda);
                        if (spec.on_score_msg) |msg| {
                            generated.systemMsg(.corp, spec.code, "Corp uses {s} to {s}", .{ spec.title, msg });
                        }
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
                try generated.pending_effects.append(allocator, .{ .event_handler = .{
                    .code = spec.code, .side = .corp, .zone = .identity,
                } });
            }
        }
    }
    // Runner identity
    if (cardMatchesEvent(generated.runner_identity.code, event)) {
        if (lookupCardSpecByCode(generated.runner_identity.code.?)) |spec| {
            if (spec.on_event != null) {
                try generated.pending_effects.append(allocator, .{ .event_handler = .{
                    .code = spec.code, .side = .runner, .zone = .identity,
                } });
            }
        }
    }
    // Runner installed hardware
    for (generated.runner_rig_hardware.items, 0..) |hw, idx| {
        if (cardMatchesEvent(hw.code, event)) {
            if (lookupCardSpecByCode(hw.code.?)) |spec| {
                if (spec.on_event != null) {
                    try generated.pending_effects.append(allocator, .{ .event_handler = .{
                        .code = spec.code, .side = .runner, .zone = .runner_hardware, .index = @intCast(idx),
                    } });
                }
            }
        }
    }
    // Runner installed resources
    for (generated.runner_rig_resources.items, 0..) |res, idx| {
        if (cardMatchesEvent(res.code, event)) {
            if (lookupCardSpecByCode(res.code.?)) |spec| {
                if (spec.on_event != null) {
                    try generated.pending_effects.append(allocator, .{ .event_handler = .{
                        .code = spec.code, .side = .runner, .zone = .runner_resource, .index = @intCast(idx),
                    } });
                }
            }
        }
    }
    // Runner installed programs
    for (generated.runner_rig_program.items, 0..) |prog, idx| {
        if (cardMatchesEvent(prog.code, event)) {
            if (lookupCardSpecByCode(prog.code.?)) |spec| {
                if (spec.on_event != null) {
                    try generated.pending_effects.append(allocator, .{ .event_handler = .{
                        .code = spec.code, .side = .runner, .zone = .runner_program, .index = @intCast(idx),
                    } });
                }
            }
        }
    }
    // Corp installed cards in servers (upgrades/assets with event triggers)
    for (generated.corp_servers.items, 0..) |server, server_idx| {
        for (server.content.items, 0..) |card, card_idx| {
            if (!card.rezzed) continue;
            if (cardMatchesEvent(card.code, event)) {
                if (lookupCardSpecByCode(card.code.?)) |spec| {
                    if (spec.on_event != null) {
                        if (spec.on_event_server_check) {
                            if (generated.last_scored_server_index != server_idx) continue;
                        }
                        try generated.pending_effects.append(allocator, .{ .event_handler = .{
                            .code = spec.code, .side = .corp, .zone = .corp_server_content,
                            .index = @intCast(card_idx), .server_index = @intCast(server_idx),
                        } });
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

    // Click was deferred from applyInstallFromHand for trojans (Clojure spends it on resolution)
    try spendClicks(generated, .runner, 1);
    try spendCredits(generated, .runner, pending.runner_install_cost);
    var installed_card = try removeCardFromHand(generated, .runner, pending.card_index);
    installed_card.credit_counter = installed_card.installed_ability.initial_credit_counters;
    installed_card.ability_used_this_turn = false;

    // Virus-on-install
    if (installed_card.installed_ability.virus_on_install) {
        installed_card.virus_counter += 1;
        installed_card.virus_counter += @intCast(runnerCookbookBonus(generated));
    }
    // Host trojan on the ICE card (matching Clojure's model)
    const allocator = generated.arena.allocator();
    var ice = &generated.corp_servers.items[server_idx].ices.items[ice_idx];
    const new_hosted = try allocator.alloc(state.CardInstance, ice.hosted.len + 1);
    @memcpy(new_hosted[0..ice.hosted.len], ice.hosted);
    new_hosted[ice.hosted.len] = installed_card;
    ice.hosted = new_hosted;

    generated.turn_events.programs_installed_this_turn += 1;
    if (generated.runner_memory) |*mem| {
        mem.used += pending.card.runner_install.mu_cost;
        mem.available = if (mem.base > mem.used) mem.base - mem.used else 0;
    }
    // Tranquilizer: check derez threshold immediately after install
    if (installed_card.installed_ability.trojan_derez_threshold > 0 and installed_card.virus_counter >= installed_card.installed_ability.trojan_derez_threshold) {
        ice.rezzed = false;
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

fn iceHasSubtype(ice: state.CardInstance, subtype: []const u8) bool {
    if (hasSubtype(ice, subtype)) return true;
    // Chromatophores: hosted trojan adds all subtypes to host ICE
    for (ice.hosted) |hosted| {
        if (hosted.installed_ability.trojan_adds_all_subtypes) return true;
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
    installed.credit_counter = installed.installed_ability.initial_credit_counters;
    installed.ability_used_this_turn = false;
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
    // Carnivore: trash 2 from hand to trash accessed card at no cost
    if (std.mem.eql(u8, choice_text, "Trash card")) {
        try applyCarnivoreTrash(generated, accessed);
        return;
    }
    // Self-trash access ability (Gourmand): trash self to trash accessed non-agenda + draw
    if (std.mem.eql(u8, choice_text, "Use Gourmand")) {
        try applySelfTrashAccess(generated, accessed);
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

fn applyCarnivoreTrash(generated: *Game, accessed: state.CardInstance) !void {
    // Find the card with trash_access_hand_cost and use it
    var hand_cost: u8 = 2; // default
    for (generated.runner_rig_hardware.items) |*hw| {
        if (hw.installed_ability.trash_access_hand_cost > 0 and !hw.ability_used_this_turn) {
            hand_cost = hw.installed_ability.trash_access_hand_cost;
            hw.ability_used_this_turn = true;
            break;
        }
    }
    // Trash N cards from runner hand (front of hand, deterministic)
    var trashed: u8 = 0;
    while (trashed < hand_cost and generated.runner_hand.items.len > 0) : (trashed += 1) {
        const card = generated.runner_hand.orderedRemove(0);
        try generated.runner_discard.append(generated.backing_allocator, card);
    }
    // Clear access prompt before firing event
    generated.runner_prompt_state = null;
    // Trash the accessed card at no credit cost
    generated.turn_events.runner_trash_corp_card_count += 1;
    if (try fireEvent(generated, .runner_trash_corp_card)) return;
    const run = generated.run orelse return error.NoRunInProgress;
    try removeAccessedCard(generated, run);
    try appendDiscardCard(generated, .corp, accessed);
    try finishAccessCard(generated);
}

fn applySelfTrashAccess(generated: *Game, accessed: state.CardInstance) !void {
    // Find and trash the card with trash_access_self_trash from rig
    var draw_count: u8 = 0;
    var trash_title: []const u8 = "";
    var trash_code: u32 = 0;
    // Check programs first, then hardware
    for (generated.runner_rig_program.items, 0..) |prog, idx| {
        if (prog.installed_ability.trash_access_self_trash) {
            draw_count = prog.installed_ability.trash_access_draw;
            trash_title = prog.title;
            trash_code = prog.code orelse 0;
            const trashed_prog = generated.runner_rig_program.orderedRemove(idx);
            try appendDiscardCard(generated, .runner, trashed_prog);
            if (generated.runner_memory) |*mem| {
                const mu = trashed_prog.runner_install.mu_cost;
                mem.used = if (mem.used >= mu) mem.used - mu else 0;
                mem.available = mem.base - mem.used;
            }
            break;
        }
    }
    generated.systemMsg(.runner, trash_code, "Runner uses {s} to trash {s}.", .{ trash_title, accessed.title });
    // Clear access prompt before firing event
    generated.runner_prompt_state = null;
    // Trash the accessed card
    generated.turn_events.runner_trash_corp_card_count += 1;
    if (try fireEvent(generated, .runner_trash_corp_card)) return;
    const run = generated.run orelse return error.NoRunInProgress;
    try removeAccessedCard(generated, run);
    try appendDiscardCard(generated, .corp, accessed);
    // Draw cards
    if (draw_count > 0) {
        try drawCards(generated, .runner, draw_count);
    }
    try finishAccessCard(generated);
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

    const stolen_points = accessed.agenda_points orelse return error.MissingAgendaPoints;
    generated.runner_agenda_point += stolen_points;
    generated.systemMsg(.runner, accessed.code orelse 0, "Runner steals {s} and gains {d} agenda point{s}.", .{
        accessed.title, stolen_points, if (stolen_points != 1) "s" else "",
    });
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
    const cost = card.cost orelse 0;
    try spendClicks(generated, .corp, 1);
    try spendCredits(generated, .corp, cost);
    _ = try removeCardFromHand(generated, .corp, card_index);

    if (cost > 0) {
        generated.systemMsg(.corp, card.code orelse 0, "Corp spends [click] and pays {d} [credit{s}] to play {s}.", .{
            cost, if (cost != 1) "s" else "", card.title,
        });
    } else {
        generated.systemMsg(.corp, card.code orelse 0, "Corp spends [click] to play {s}.", .{card.title});
    }

    switch (card.corp_play.kind) {
        .gain_credits => {
            generated.corp_credit += card.corp_play.gain_credits;
            try drawCards(generated, .corp, card.corp_play.draw_cards);
            // Fire operation_played for Zwicky trigger (credit gain from operation)
            if (card.corp_play.gain_credits > 0) {
                generated.turn_events.operation_played_count += 1;
                if (try fireEvent(generated, .operation_played)) return;
            }
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
                if (spec.on_play_msg) |msg| {
                    generated.systemMsg(.corp, spec.code, "Corp uses {s} to {s}", .{ spec.title, msg });
                }
            } else {
                return error.UnsupportedOperation;
            }
            // If handler opened a prompt, don't override legal actions
            if (generated.corp_prompt_state != null or generated.runner_prompt_state != null) return;
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
            try handler(generated, card);
            if (spec.on_play_msg) |msg| {
                generated.systemMsg(.runner, spec.code, "Runner uses {s} to {s}", .{ spec.title, msg });
            }
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
    // Principia: -1 cost per other installed icebreaker
    if (card.installed_ability.install_cost_reduction_per_icebreaker) {
        const breaker_count = countInstalledIcebreakers(generated);
        if (breaker_count > 0) {
            install_cost = if (install_cost >= breaker_count) install_cost - breaker_count else 0;
        }
    }

    // Trojan: install on ICE — show ICE selection prompt (click deferred until host selected)
    if (card.installed_ability.is_trojan) {
        const allocator = generated.arena.allocator();
        // Build list of all installed ICE as choices
        var choices: std.ArrayList(state.PromptChoice) = .empty;
        defer choices.deinit(allocator);
        for (generated.corp_servers.items, 0..) |server, si| {
            for (server.ices.items, 0..) |ice, ii| {
                const label = try std.fmt.allocPrint(allocator, "{d}|{d}|{s}", .{ si, ii, ice.title });
                try choices.append(allocator, .{ .kind = .card, .text = label, .card = .{ .title = ice.title, .printed_title = ice.title, .code = ice.code, .side = .corp } });
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

    // For programs, check MU BEFORE spending click/credits (matches Clojure's async install flow).
    // If MU would overflow, show the trash prompt first; click and install complete after resolution.
    if (card.runner_install.kind == .program) {
        generated.pending_install = .{
            .card = card,
            .card_index = card_index,
            .runner_install_cost = install_cost,
        };
        if (try beginMuOverflowPromptWithExtra(generated, card.runner_install.mu_cost)) return;
        generated.pending_install = null;
    }

    try spendClicks(generated, .runner, 1);
    try completeRunnerInstall(generated, card_index, card, install_cost);
}

fn completeRunnerInstall(generated: *Game, card_index: u8, card: state.CardInstance, install_cost: u16) !void {
    const allocator = generated.arena.allocator();
    try spendCredits(generated, .runner, install_cost);

    var installed_card = try removeCardFromHand(generated, .runner, card_index);
    installed_card.credit_counter = installed_card.installed_ability.initial_credit_counters;
    installed_card.ability_used_this_turn = false;
    try appendRunnerInstalledCard(generated, installed_card);

    if (install_cost > 0) {
        generated.systemMsg(.runner, card.code orelse 0, "Runner spends [click] and pays {d} [credit{s}] to install {s}.", .{
            install_cost, if (install_cost != 1) "s" else "", card.title,
        });
    } else {
        generated.systemMsg(.runner, card.code orelse 0, "Runner spends [click] to install {s}.", .{card.title});
    }

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
        // Hantu: place N virus counters on install (instead of 1)
        if (installed_card.installed_ability.initial_virus_counters > 0) {
            if (generated.runner_rig_program.items.len > 0) {
                var prog = &generated.runner_rig_program.items[generated.runner_rig_program.items.len - 1];
                prog.virus_counter += installed_card.installed_ability.initial_virus_counters;
                prog.virus_counter += runnerCookbookBonus(generated);
            }
        }
        // Devadatta Drone: place N power counters on install
        if (installed_card.installed_ability.initial_power_counters > 0) {
            if (generated.runner_rig_program.items.len > 0) {
                var prog = &generated.runner_rig_program.items[generated.runner_rig_program.items.len - 1];
                prog.power_counter += installed_card.installed_ability.initial_power_counters;
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
    const play_cost = card.cost orelse 0;
    try spendClicks(generated, .runner, 1);
    try spendCredits(generated, .runner, play_cost);
    _ = try removeCardFromHand(generated, .runner, card_index);
    try appendDiscardCard(generated, .runner, card);
    try spendClicks(generated, .runner, card.runner_play.lose_clicks);
    generated.runner_credit += card.runner_play.gain_credits;
    try drawCards(generated, .runner, card.runner_play.draw_cards);

    if (play_cost > 0) {
        generated.systemMsg(.runner, card.code orelse 0, "Runner spends [click] and pays {d} [credit{s}] to play {s}.", .{
            play_cost, if (play_cost != 1) "s" else "", card.title,
        });
    } else {
        generated.systemMsg(.runner, card.code orelse 0, "Runner spends [click] to play {s}.", .{card.title});
    }

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
    const rt_cost = card.cost orelse 0;
    try spendClicks(generated, .runner, 1);
    try spendCredits(generated, .runner, rt_cost);
    _ = try removeCardFromHand(generated, .runner, card_index);
    try appendDiscardCard(generated, .runner, card);
    // Double events: spend additional clicks
    if (card.runner_play.lose_clicks > 0) {
        try spendClicks(generated, .runner, card.runner_play.lose_clicks);
    }
    if (rt_cost > 0) {
        generated.systemMsg(.runner, card.code orelse 0, "Runner spends [click] and pays {d} [credit{s}] to play {s}.", .{
            rt_cost, if (rt_cost != 1) "s" else "", card.title,
        });
    } else {
        generated.systemMsg(.runner, card.code orelse 0, "Runner spends [click] to play {s}.", .{card.title});
    }
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
    // Fire run_begins event (Side Hustle: place credit)
    if (try fireEvent(generated, .run_begins)) return;
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
    // Fire run_begins event (Side Hustle: place credit)
    if (try fireEvent(generated, .run_begins)) return;
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, generated.run, generated);
}

fn applyIdentityAbility(generated: *Game, side: state.Side) !void {
    const identity = if (side == .runner) &generated.runner_identity else &generated.corp_identity;
    const code = identity.code orelse return error.UnsupportedAction;
    const spec = lookupCardSpecByCode(code) orelse return error.UnsupportedAction;
    if (spec.identity_ability_click_cost == 0) return error.UnsupportedAction;
    if (spec.identity_ability_once_per_turn and identity.ability_used_this_turn) return error.AbilityAlreadyUsed;

    try spendClicks(generated, side, spec.identity_ability_click_cost);
    identity.ability_used_this_turn = true;

    if (spec.on_play) |handler| {
        generated.systemMsg(side, code, "{s} spends [click] to use {s}.", .{ sideName(side), identity.title });
        try handler(generated, identity.*);
    }
    if (!hasActivePrompt(generated)) {
        const allocator = generated.arena.allocator();
        generated.decision_side = side;
        if (side == .runner) {
            generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
        } else {
            generated.legal_actions = try corpOpeningActionsForState(allocator, generated);
        }
    }
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
                generated.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to give ICE -{d} strength.", .{
                    card.title, card.installed_ability.virus_ice_strength_reduction,
                });
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
                        generated.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                            card.title, total, if (total != 1) "s" else "",
                        });
                    } else {
                        const amount = @min(card.credit_counter, card.installed_ability.take_credits_amount);
                        generated.runner_credit += amount;
                        card.credit_counter -= amount;
                        generated.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                            card.title, amount, if (amount != 1) "s" else "",
                        });
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

                    // Log break action
                    generated.systemMsg(.runner, icebreaker.code orelse 0, "Runner uses {s} to break subroutine on {s}.", .{
                        icebreaker.title, ice.title,
                    });

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

                    if (icebreaker.pump_ability.pump_uses_virus_counters) {
                        // Hantu: spend 1 virus counter instead of credits
                        if (icebreaker.virus_counter == 0) return error.InsufficientCredits;
                        icebreaker.virus_counter -= 1;
                    } else {
                        // Sang Kancil: discount if run event is active
                        var pump_cost = icebreaker.pump_ability.credit_cost;
                        if (icebreaker.pump_ability.pump_discount_if_run_event > 0 and runnerHasActiveRunEvent(generated)) {
                            pump_cost = if (pump_cost >= icebreaker.pump_ability.pump_discount_if_run_event)
                                pump_cost - icebreaker.pump_ability.pump_discount_if_run_event
                            else
                                0;
                        }
                        // Spend credits for pump
                        if (generated.runner_credit < pump_cost) return error.InsufficientCredits;
                        generated.runner_credit -= pump_cost;
                    }

                    // Boost strength
                    const current = effectiveStrength(icebreaker.*);
                    const pump_amount = if (icebreaker.pump_ability.pump_is_variable)
                        // Unity: pump = number of installed icebreakers
                        @as(u8, @intCast(generated.runner_rig_program.items.len))
                    else
                        icebreaker.pump_ability.pump_strength_amount;
                    icebreaker.current_strength = current + pump_amount;

                    // Log pump action
                    generated.systemMsg(.runner, icebreaker.code orelse 0, "Runner uses {s} to increase strength to {d}.", .{
                        icebreaker.title, icebreaker.current_strength orelse 0,
                    });

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
                    generated.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                        card.title, gain, if (gain != 1) "s" else "",
                    });
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
                .click_trash_for_credits => {
                    // Rent Rioters: N clicks + trash self, gain flat credits
                    try spendClicks(generated, .runner, card.installed_ability.click_cost);
                    const gain = card.installed_ability.credit_cost;
                    generated.runner_credit += gain;
                    generated.systemMsg(.runner, card.code orelse 0, "Runner uses {s} to gain {d} [credit{s}].", .{
                        card.title, gain, if (gain != 1) "s" else "",
                    });
                    // Trash the resource
                    const trashed = generated.runner_rig_resources.orderedRemove(card_index);
                    try appendDiscardCard(generated, .runner, trashed);
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
                    generated.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to gain {d} [credit{s}].", .{
                        card.title, amount, if (amount != 1) "s" else "",
                    });

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
                .place_credits, .break_subroutine, .pump_strength, .run_central, .run_rd, .start_of_turn_credits, .trash_for_virus_credits, .click_trash_for_credits => return error.UnsupportedAbility,
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
    const run_val = generated.run orelse return error.NoRunInProgress;
    const fransofia_increase = runnerRezCostIncrease(generated);
    const adjusted_cost = rez_cost + run_val.rez_cost_bonus + fransofia_increase;
    try spendCredits(generated, .corp, adjusted_cost);
    generated.corp_servers.items[target.server_index].ices.items[target.ice_index].rezzed = true;
    if (adjusted_cost > 0) {
        generated.systemMsg(.corp, target.ice.code orelse 0, "Corp pays {d} [credit{s}] to rez {s}.", .{
            adjusted_cost, if (adjusted_cost != 1) "s" else "", target.ice.title,
        });
    } else {
        generated.systemMsg(.corp, target.ice.code orelse 0, "Corp rezzes {s}.", .{target.ice.title});
    }
    // Ping: give runner tags when rezzed during a run
    if (target.ice.tag_on_rez > 0) {
        if (try addRunnerTag(generated, target.ice.tag_on_rez)) return;
    }
    // On-rez trigger
    const ice = &generated.corp_servers.items[target.server_index].ices.items[target.ice_index];
    if (ice.code) |code| {
        if (lookupCardSpecByCode(code)) |spec| {
            if (spec.on_rez) |handler| {
                try handler(generated);
                if (spec.on_rez_msg) |msg| {
                    generated.systemMsg(.corp, spec.code, "Corp uses {s} to {s}", .{ spec.title, msg });
                }
            }
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

    // On-rez trigger (Spin Doctor: draw 2)
    if (card.code) |code| {
        if (lookupCardSpecByCode(code)) |spec| {
            if (spec.on_rez) |handler| {
                try handler(generated);
                if (spec.on_rez_msg) |msg| {
                    generated.systemMsg(.corp, spec.code, "Corp uses {s} to {s}", .{ spec.title, msg });
                }
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

            // Dynamic strength bonuses for encounter
            for (generated.runner_rig_program.items) |*prog| {
                // Echelon: +1 strength per installed icebreaker
                if (prog.installed_ability.strength_per_icebreaker) {
                    var icebreaker_count: u8 = 0;
                    for (generated.runner_rig_program.items) |p| {
                        if (isIcebreaker(p)) icebreaker_count += 1;
                    }
                    prog.current_strength = (prog.strength orelse 0) + icebreaker_count;
                }
                // Rising Tide: +1 strength per fracter in heap
                if (prog.installed_ability.strength_per_heap_fracter) {
                    prog.current_strength = (prog.strength orelse 0) + countFractersInHeap(generated);
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
    // Corp gets priority first in movement phase (matching Clojure)
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, run.*, generated);
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
        .corp_install_from_hq_archives => std.fmt.allocPrint(allocator, "Install a card from HQ or Archives", .{}),
        .prevent_steal_trash => std.fmt.allocPrint(allocator, "The Runner cannot steal or trash Corp cards for the remainder of this run", .{}),
        .conditional_net_damage_if_tagged => std.fmt.allocPrint(allocator, "Do {d} net damage if the Runner is tagged", .{sub.amount}),
        .conditional_etr_threat => std.fmt.allocPrint(allocator, "End the run if threat >= {d}", .{sub.amount}),
        .net_damage_unless_etr => std.fmt.allocPrint(allocator, "End the run unless the Runner suffers {d} net damage", .{sub.amount}),
        .trash_program_or_resource_or_etr => std.fmt.allocPrint(allocator, "Trash 1 installed card or end the run", .{}),
        .runner_loses_credits_and_net_damage => std.fmt.allocPrint(allocator, "The Runner loses {d} [Credits]", .{sub.amount}),
        .tag_or_pay_credits_etr => std.fmt.allocPrint(allocator, "Sub {d}", .{idx}),
        .place_advancement_counter => std.fmt.allocPrint(allocator, "Place {d} advancement counter{s}", .{ sub.amount, if (sub.amount != 1) "s" else "" }),
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
    // Corp gets priority first in movement phase (matching Clojure)
    generated.decision_side = .corp;
    generated.legal_actions = try continueActionsForRunWithRez(allocator, .corp, run.*, generated);
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

        // Track subroutines fired this run (Ryō: gains credits when subs fire)
        if (generated.run) |*run| {
            run.subroutines_fired += 1;
        }

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
            .corp_install_from_hq_archives => {
                // Ansel 1.0 sub 2: corp installs a card from HQ or Archives
                try beginAnselInstallPrompt(generated, server_index, ice_index, @intCast(idx));
                return;
            },
            .prevent_steal_trash => {
                // Ansel 1.0 sub 3: prevent stealing/trashing for rest of run
                if (generated.run) |*mutable_run| {
                    mutable_run.no_steal_or_trash = true;
                }
            },
            .conditional_net_damage_if_tagged => {
                // Doomscroll: do N net damage if runner has N+ tags
                const tag_count = if (generated.runner_tag) |t| t.base else 0;
                if (tag_count >= sub.amount) {
                    const damage = sub.amount;
                    try trashRandomRunnerHandCards(generated, damage);
                    updateTerminalState(generated);
                    if (generated.game_over) return;
                }
            },
            .conditional_etr_threat => {
                // N-Pot: ETR if threat level >= amount
                if (threatLevel(generated) >= sub.amount) {
                    try completeUnsuccessfulRun(generated);
                    return;
                }
            },
            .net_damage_unless_etr => {
                // Semak-samun: ETR unless runner suffers N net damage
                const run = &(generated.run orelse return error.NoRunInProgress);
                run.pending_subroutine = .{
                    .server_index = @intCast(server_index),
                    .ice_index = @intCast(ice_index),
                    .subroutine_index = @intCast(idx + 1),
                };
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                try choices.append(allocator, stringChoice("End the run"));
                const text = try std.fmt.allocPrint(allocator, "Suffer {d} net damage", .{sub.amount});
                try choices.append(allocator, stringChoice(text));
                generated.runner_prompt_state = .{
                    .prompt_type = try allocator.dupe(u8, "net-damage-or-etr"),
                    .choices = try choices.toOwnedSlice(allocator),
                    .source_card = ice,
                };
                generated.decision_side = .runner;
                generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
                return;
            },
            .trash_program_or_resource_or_etr => {
                // Biawak: trash 1 program or 1 resource, or ETR if none
                const has_programs = generated.runner_rig_program.items.len > 0;
                const has_resources = generated.runner_rig_resources.items.len > 0;
                if (!has_programs and !has_resources) {
                    try completeUnsuccessfulRun(generated);
                    return;
                }
                generated.run.?.pending_subroutine = .{
                    .server_index = @intCast(server_index),
                    .ice_index = @intCast(ice_index),
                    .subroutine_index = @intCast(idx + 1),
                };
                var choices: std.ArrayList(state.PromptChoice) = .empty;
                defer choices.deinit(allocator);
                // Use sub.amount to distinguish: 0 = programs only, 1 = resources only
                if (sub.amount == 0 or sub.amount == 2) {
                    for (generated.runner_rig_program.items, 0..) |prog, pidx| {
                        const label = try std.fmt.allocPrint(allocator, "p|{d}", .{pidx});
                        try choices.append(allocator, .{ .kind = .string, .text = label, .card = .{ .title = prog.title, .side = .runner, .index = @intCast(pidx) } });
                    }
                }
                if (sub.amount == 1 or sub.amount == 2) {
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
                return;
            },
            .runner_loses_credits_and_net_damage => {
                // Syailendra: runner loses N credits
                const loss = @min(sub.amount, @as(u8, @intCast(generated.runner_credit)));
                generated.runner_credit -= loss;
            },
            .tag_or_pay_credits_etr => {
                // Lamplighter: give 1 tag unless runner pays N; then ETR if tagged
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
            .place_advancement_counter => {
                // Syailendra: place N advancement counters on this ICE
                generated.corp_servers.items[server_index].ices.items[ice_index].advancement_counter += sub.amount;
                generated.systemMsg(.corp, ice.code orelse 0, "Corp places {d} advancement counter{s} on {s}.", .{
                    sub.amount, if (sub.amount != 1) "s" else "", ice.title,
                });
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
    if (try checkManegarmSkunkworks(generated)) {
        return;
    }

    try applySuccessfulRunEffects(generated);
    if (try prepareNextAccess(generated)) {
        run.phase = try allocator.dupe(u8, "success");
        // Clojure: approach-server → successful-run → breach-server all resolve
        // within the movement continue handler. Access begins directly.
        // Corp prompt (e.g., net-damage-on-access) gets priority if present.
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
        } else {
            generated.decision_side = .runner;
            generated.legal_actions = try continueActionsForRun(allocator, .runner, run.*);
        }
        return;
    }

    try completeRunWithoutAccess(generated);
}

fn prepareNextAccess(generated: *Game) !bool {
    const run = &generated.run.?;
    // Initialize access count only once per breach (accessed_count == 0 means first call)
    if (run.accesses_remaining == 0 and run.accessed_count == 0) {
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
    // Clear prompts before firing events so we can detect if an event sets a new one
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    try applyIdentityOnSuccessfulRun(generated);
    applyAmazeTagsOnRunEnd(generated);
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
    applyVirusCountersOnSuccessfulRun(generated);
    applyPennyshaverOnSuccessfulRun(generated);
    // Clear prompts before firing events so we can detect if an event sets a new one
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    try applyIdentityOnSuccessfulRun(generated);
    applyAmazeTagsOnRunEnd(generated);
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
    applyVirusCountersOnSuccessfulRun(generated);
    applyPennyshaverOnSuccessfulRun(generated);
    generated.corp_prompt_state = null;
    generated.runner_prompt_state = null;
    try applyIdentityOnSuccessfulRun(generated);
    applyAmazeTagsOnRunEnd(generated);
    endOfRunCleanup(generated);
    generated.run = null;
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
    const no_steal_or_trash = if (generated.run) |r| r.no_steal_or_trash else false;
    switch (accessed.access.kind) {
        .steal_agenda => {
            if (no_steal_or_trash) {
                // Ansel 1.0: can't steal — show "No action" only
                return try beginNoActionAccessPrompt(generated, accessed);
            }
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

/// Check if runner has a card with trash-from-hand access ability (Carnivore pattern)
fn hasTrashAccessFromHand(generated: *const Game) bool {
    for (generated.runner_rig_hardware.items) |hw| {
        if (hw.installed_ability.trash_access_hand_cost > 0 and !hw.ability_used_this_turn and
            generated.runner_hand.items.len >= hw.installed_ability.trash_access_hand_cost) return true;
    }
    return false;
}

/// Check if runner has a card with self-trash access ability (Gourmand pattern)
fn hasTrashAccessSelfTrash(generated: *const Game) bool {
    for (generated.runner_rig_program.items) |prog| {
        if (prog.installed_ability.trash_access_self_trash) return true;
    }
    for (generated.runner_rig_hardware.items) |hw| {
        if (hw.installed_ability.trash_access_self_trash) return true;
    }
    return false;
}

fn beginTrashAccessPrompt(generated: *Game, accessed: state.CardInstance) !bool {
    const spec = lookupCardSpec(accessed);
    const trash_cost = if (spec) |s| s.trash_cost else null;
    const allocator = generated.arena.allocator();
    const no_steal_or_trash = if (generated.run) |r| r.no_steal_or_trash else false;

    const can_afford = if (trash_cost) |tc| generated.runner_credit >= tc and !no_steal_or_trash else false;
    const has_trash_from_hand = hasTrashAccessFromHand(generated) and !no_steal_or_trash;
    const is_agenda = if (accessed.card_type) |ct| std.mem.eql(u8, ct, "Agenda") else false;
    const has_self_trash = hasTrashAccessSelfTrash(generated) and !no_steal_or_trash and !is_agenda;
    var choice_count: usize = 1; // "No action"
    if (can_afford) choice_count += 1;
    if (has_trash_from_hand) choice_count += 1;
    if (has_self_trash) choice_count += 1;
    const choices = try allocator.alloc(state.PromptChoice, choice_count);
    var idx: usize = 0;
    if (can_afford) {
        choices[idx] = stringChoice(try std.fmt.allocPrint(allocator, "Pay {d} [Credits] to trash", .{trash_cost.?}));
        idx += 1;
    }
    if (has_trash_from_hand) {
        choices[idx] = stringChoice("Trash card");
        idx += 1;
    }
    if (has_self_trash) {
        choices[idx] = stringChoice("Use Gourmand");
        idx += 1;
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
    const fransofia_increase = runnerRezCostIncrease(game);
    const adjusted_cost = rez_cost + run.rez_cost_bonus + fransofia_increase;
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
            if (card.pump_ability.pump_uses_virus_counters) {
                // Hantu: needs virus counters to pump
                if (card.virus_counter == 0) continue;
            } else {
                // Sang Kancil: discount if run event active
                var pump_cost = card.pump_ability.credit_cost;
                if (card.pump_ability.pump_discount_if_run_event > 0 and runnerHasActiveRunEvent(generated)) {
                    pump_cost = if (pump_cost >= card.pump_ability.pump_discount_if_run_event)
                        pump_cost - card.pump_ability.pump_discount_if_run_event
                    else
                        0;
                }
                if (generated.runner_credit < pump_cost) continue;
            }
            pump_count += 1;
        }
        for (generated.runner_rig_program.items) |card| {
            if (card.installed_ability.virus_ice_strength_reduction > 0 and card.virus_counter > 0) {
                leech_count += 1;
            }
        }
        // Botulus: check hosted cards on the current ICE
        if (ice.hosted.len > 0) {
            for (ice.hosted) |hosted| {
                if (hosted.installed_ability.trojan_break_any and hosted.virus_counter > 0) {
                    botulus_count += 1;
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

        // Botulus: trojan hosted on current ICE with virus counters can break any sub
        for (ice.hosted) |hosted| {
            if (!hosted.installed_ability.trojan_break_any or hosted.virus_counter == 0) continue;
            actions[next] = .{
                .kind = .use_installed_ability,
                .side = .runner,
                .card_title = try allocator.dupe(u8, hosted.title),
                .installed_ability = .break_subroutine,
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

    const installed_ability_count = countCorpInstalledAbilityActions(servers);
    const raw_advanceable = if (g.corp_click >= 1 and g.corp_credit >= 1) countAdvanceableCards(servers) else 0;
    // Don't count scoreable agendas as advanceable (score replaces advance)
    const advanceable_count = if (!g.cannot_score_agendas_this_turn) raw_advanceable -| scoreable_count else raw_advanceable;
    const rezzable_count = countRezzableNonIce(g);
    var count: usize = playable_hand_count + installed_ability_count + advanceable_count + rezzable_count;
    if (g.corp_click >= 1) count += 1; // gain credit
    if (g.corp_click >= 1 and g.corp_deck.items.len > 0) count += 1; // draw card
    if (scoreable_count > 0 and !g.cannot_score_agendas_this_turn) count += scoreable_count;
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
                    !g.cannot_score_agendas_this_turn) continue;
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
    if (scoreable_count > 0 and !g.cannot_score_agendas_this_turn) {
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
        if (isRunnerCardPlayableFromHand(g.runner_click, g.runner_credit, card, g.runner_successful_run_this_turn, runnerInstalledFirstProgramDiscount(g), runnerHasConsoleInstalled(g), corpHasInstalledIce(g))) playable_hand_count += 1;
    }
    const resource_ability_count = countRunnerInstalledAbilityActions(g.runner_rig_resources.items, g.turn_events);
    const hardware_ability_count = countRunnerInstalledAbilityActions(g.runner_rig_hardware.items, g.turn_events);
    const program_ability_count = countRunnerInstalledAbilityActions(g.runner_rig_program.items, g.turn_events);
    const installed_ability_count = resource_ability_count + hardware_ability_count + program_ability_count;

    // Identity click ability (Topan: install from grip paying 2cr less)
    const identity_ability_available = blk: {
        if (lookupCardSpecByCode(g.runner_identity.code orelse 0)) |id_spec| {
            if (id_spec.identity_ability_click_cost > 0 and
                g.runner_click >= id_spec.identity_ability_click_cost and
                (!id_spec.identity_ability_once_per_turn or !g.runner_identity.ability_used_this_turn))
                break :blk true;
        }
        break :blk false;
    };

    var count: usize = playable_hand_count + installed_ability_count;
    if (g.runner_click >= 1) count += 1; // gain credit
    if (g.runner_click >= 1 and g.runner_deck.items.len > 0) count += 1; // draw card
    if (g.runner_click >= 1) count += runnable_servers.len; // run actions
    if (g.runner_click >= 1 and g.runner_credit >= 2 and is_runner_tagged(g.runner_tag)) count += 1;
    if (identity_ability_available) count += 1;

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
    if (identity_ability_available) {
        if (lookupCardSpecByCode(g.runner_identity.code orelse 0)) |id_spec| {
            actions[next] = .{
                .kind = .use_identity_ability,
                .side = .runner,
                .card_title = try allocator.dupe(u8, g.runner_identity.title),
                .label = try allocator.dupe(u8, id_spec.identity_ability_label orelse "Use identity ability"),
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
        .click_trash_for_credits => std.fmt.allocPrint(allocator, "Gain {d} [Credits]", .{card.installed_ability.credit_cost}),
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

    // Rent Rioters: N clicks + trash for flat credits (always available)
    if (card.installed_ability.kind == .click_trash_for_credits) {
        return card.installed_ability.click_cost > 0;
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
            // Public Access Plaza: gain credits from bank each turn
            if (card.rezzed and card.installed_ability.start_of_turn_bank_credits > 0) {
                game.corp_credit += card.installed_ability.start_of_turn_bank_credits;
                game.systemMsg(.corp, card.code orelse 0, "Corp uses {s} to gain {d} [credit{s}].", .{
                    card.title, card.installed_ability.start_of_turn_bank_credits,
                    if (card.installed_ability.start_of_turn_bank_credits != 1) "s" else "",
                });
            }
            if (card.installed_ability.kind == .start_of_turn_credits and card.rezzed and card.credit_counter > 0) {
                const take = @min(card.credit_counter, card.installed_ability.take_credits_amount);
                card.credit_counter -= take;
                game.corp_credit += take;
                // Draw cards on each take (Anthill Excavation)
                if (card.installed_ability.draw_on_take > 0) {
                    try drawCards(game, .corp, card.installed_ability.draw_on_take);
                }

                if (card.installed_ability.trash_on_empty and card.credit_counter == 0) {
                    // Draw cards before trashing if draw_on_empty > 0
                    if (card.installed_ability.draw_on_empty > 0) {
                        try drawCards(game, .corp, card.installed_ability.draw_on_empty);
                    }
                    // Gain clicks on empty (Otto Campaign)
                    if (card.installed_ability.clicks_on_empty > 0) {
                        game.corp_click += card.installed_ability.clicks_on_empty;
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
    generated.systemMsg(.corp, 0, "Corp draws 1 card for their mandatory draw.", .{});
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

/// Check if runner has a run event in play area (Sang Kancil pump discount)
fn runnerHasActiveRunEvent(generated: *const Game) bool {
    // Run events are in the play area when active — check if run has a source card
    // that is a run event (subtypes include "Run")
    if (generated.run) |run| {
        if (run.source_card_code) |_| return true;
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

/// Get rez cost increase from runner installed resources (Fransofia Ward)
fn runnerRezCostIncrease(generated: *const Game) u8 {
    var increase: u8 = 0;
    for (generated.runner_rig_resources.items) |card| {
        increase += card.installed_ability.rez_cost_increase;
    }
    return increase;
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

fn threatLevel(g: *const Game) u8 {
    return g.corp_agenda_point + g.runner_agenda_point;
}

fn showTopDownInstallChoices(g: *Game, card: ?state.CardInstance, installs_done: u8) !void {
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
    };
    g.decision_side = .corp;
    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
}

fn showKpiChoices(g: *Game, card: ?state.CardInstance, choices_made: u8) !void {
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
    try choices_list.append(allocator, stringChoice("Draw 1 card"));
    if (choices_made > 0) {
        try choices_list.append(allocator, stringChoice("Done"));
    }
    g.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "kpi-choose"),
        .choices = try choices_list.toOwnedSlice(allocator),
        .source_card = card,
        .min_choices = choices_made,
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
        // Spend click now (deferred from applyInstallFromHand to match Clojure's async flow)
        try spendClicks(generated, .runner, 1);
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
    var tithe = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30073));
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
    var karuna = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30047));
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
    var whitespace = try makeCardInstance(generated.arena.allocator(), try lookupRequiredCardSpec(30074));
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

    // Verify rez cost bonus is set
    try std.testing.expectEqual(@as(u16, 3), generated.run.?.rez_cost_bonus);

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
        .access = .{ .kind = .none },
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
