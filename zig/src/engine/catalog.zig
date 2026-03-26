const state = @import("state.zig");

pub const DeckLine = struct {
    qty: u8,
    card_code: u32,
};

// Handler type for card-specific subroutine resolution
// Allows cards like Brân 1.0 to have custom logic without bloating the SubroutineKind enum
pub const CardSubroutineHandler = *const fn (
    generated: *anyopaque, // *Game - using anyopaque to avoid circular import
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
    agenda_points: ?u8 = null,
    advancement_requirement: ?u8 = null,
    corp_play: state.CorpPlaySpec = .{},
    runner_play: state.RunnerPlaySpec = .{},
    access: state.AccessSpec = .{},
    install: state.InstallSpec = .{},
    runner_install: state.RunnerInstallSpec = .{},
    installed_ability: state.InstalledAbilitySpec = .{},
    subroutines: []const state.SubroutineSpec = &.{},
    runner_abilities: []const state.RunnerAbilitySpec = &.{}, // Runner abilities printed on ICE cards
    // Card-specific subroutine handler - for complex subroutines that need custom logic
    // Set this instead of/in addition to subroutines for cards like Brân 1.0
    card_subroutine_handler: ?CardSubroutineHandler = null,
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
    .{ .title = "Offworld Office", .side = .corp, .code = 30067, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Send a Message", .side = .corp, .code = 30069, .card_type = "Agenda", .agenda_points = 3, .advancement_requirement = 4, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Superconducting Hub", .side = .corp, .code = 30070, .card_type = "Agenda", .agenda_points = 1, .advancement_requirement = 2, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Orbital Superiority", .side = .corp, .code = 30068, .card_type = "Agenda", .agenda_points = 2, .advancement_requirement = 4, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Nico Campaign", .side = .corp, .code = 30037, .card_type = "Asset", .cost = 2, .install = .{ .kind = .corp_remote_only }, .installed_ability = .{
        .kind = .take_credits,
        .click_cost = 1,
        .initial_credit_counters = 9,
        .take_credits_amount = 3,
        .trash_on_empty = true,
    } },
    .{ .title = "Regolith Mining License", .side = .corp, .code = 30071, .card_type = "Asset", .cost = 2, .install = .{ .kind = .corp_remote_only }, .installed_ability = .{
        .kind = .take_credits,
        .click_cost = 1,
        .initial_credit_counters = 15,
        .take_credits_amount = 3,
        .trash_on_empty = true,
    } },
    .{ .title = "Urtica Cipher", .side = .corp, .code = 30045, .card_type = "Asset", .cost = 0, .access = .{ .kind = .urtica_cipher }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Government Subsidy", .side = .corp, .code = 30064, .card_type = "Operation", .cost = 10, .corp_play = .{ .kind = .gain_credits, .gain_credits = 15 } },
    .{ .title = "Hedge Fund", .side = .corp, .code = 30075, .card_type = "Operation", .cost = 5, .corp_play = .{ .kind = .gain_credits, .gain_credits = 9 } },
    .{ .title = "Seamless Launch", .side = .corp, .code = 30040, .card_type = "Operation", .cost = 1, .corp_play = .{ .kind = .advance_installed, .advancement_amount = 2 } },
    .{ .title = "Predictive Planogram", .side = .corp, .code = 30056, .card_type = "Operation", .cost = 0, .corp_play = .{ .kind = .predictive_planogram } },
    .{ .title = "Public Trail", .side = .corp, .code = 30057, .card_type = "Operation", .cost = 4, .corp_play = .{ .kind = .public_trail } },
    .{ .title = "Retribution", .side = .corp, .code = 30065, .card_type = "Operation", .cost = 1, .corp_play = .{ .kind = .retribution } },
    .{ .title = "Manegarm Skunkworks", .side = .corp, .code = 30042, .card_type = "Upgrade", .cost = 2, .access = .{ .kind = .manegarm_skunkworks }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "AMAZE Amusements", .side = .corp, .code = 30058, .card_type = "Upgrade", .cost = 1, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Brân 1.0", .side = .corp, .code = 30039, .card_type = "ICE", .cost = 6, .strength = 6, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .install_ice_from_hq_archives },
        .{ .kind = .end_the_run },
        .{ .kind = .end_the_run },
    }, .runner_abilities = &.{
        .{ .kind = .bioroid_break, .click_cost = 1, .break_quantity = 1 },
    } },
    .{ .title = "Palisade", .side = .corp, .code = 30072, .card_type = "ICE", .cost = 3, .strength = 2, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .end_the_run },
    } },
    .{ .title = "Diviner", .side = .corp, .code = 30046, .card_type = "ICE", .cost = 2, .strength = 2, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .do_net_damage, .amount = 1 },
        .{ .kind = .end_the_run },
    } },
    .{ .title = "Whitespace", .side = .corp, .code = 30074, .card_type = "ICE", .cost = 2, .strength = 1, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .runner_loses_credits, .amount = 2 },
        .{ .kind = .runner_loses_credits, .amount = 2 },
    } },
    .{ .title = "Karunā", .side = .corp, .code = 30047, .card_type = "ICE", .cost = 4, .strength = 3, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .do_net_damage, .amount = 2 },
        .{ .kind = .do_net_damage, .amount = 2 },
    } },
    .{ .title = "Tithe", .side = .corp, .code = 30073, .card_type = "ICE", .cost = 1, .strength = 1, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .do_net_damage, .amount = 1 },
        .{ .kind = .end_the_run },
    } },
    .{ .title = "Funhouse", .side = .corp, .code = 30054, .card_type = "ICE", .cost = 5, .strength = 4, .install = .{ .kind = .corp_server_choice }, .subroutines = &.{
        .{ .kind = .trace_tag, .base_trace = 4 },
        .{ .kind = .end_the_run },
    } },
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
    .{ .title = "Mutual Favor", .side = .runner, .code = 30011, .card_type = "Event", .cost = 0, .runner_play = .{ .kind = .mutual_favor } },
    .{ .title = "Wildcat Strike", .side = .runner, .code = 30002, .card_type = "Event", .cost = 2, .runner_play = .{ .kind = .wildcat_strike } },
    .{ .title = "VRcation", .side = .runner, .code = 30021, .card_type = "Event", .cost = 1, .runner_play = .{ .kind = .gain_credits, .draw_cards = 4, .lose_clicks = 1 } },
    .{ .title = "Docklands Pass", .side = .runner, .code = 30013, .card_type = "Hardware", .cost = 2, .runner_install = .{ .kind = .hardware } },
    .{ .title = "Pennyshaver", .side = .runner, .code = 30014, .card_type = "Hardware", .cost = 3, .runner_install = .{ .kind = .hardware }, .installed_ability = .{
        .kind = .take_credits,
        .click_cost = 1,
        .initial_credit_counters = 0,
        .take_credits_amount = 0,
        .trash_on_empty = false,
        .once_per_turn = true,
    } },
    .{ .title = "DZMZ Optimizer", .side = .runner, .code = 30022, .card_type = "Hardware", .cost = 2, .runner_install = .{ .kind = .hardware } },
    .{ .title = "Red Team", .side = .runner, .code = 30018, .card_type = "Resource", .cost = 5, .runner_install = .{ .kind = .resource }, .installed_ability = .{
        .kind = .run_central,
        .click_cost = 1,
        .initial_credit_counters = 12,
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
    .{ .title = "Verbal Plasticity", .side = .runner, .code = 30034, .card_type = "Resource", .cost = 3, .runner_install = .{ .kind = .resource } },
    .{ .title = "Carmen", .side = .runner, .code = 30015, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Killer" }, .cost = 5, .strength = 2, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 1,
        .break_subroutine_count = 1,
    } },
    .{ .title = "Cleaver", .side = .runner, .code = 30006, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Fracter" }, .cost = 3, .strength = 3, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 1,
        .break_subroutine_count = 2,
    } },
    .{ .title = "Mayfly", .side = .runner, .code = 30032, .card_type = "Program", .subtypes = &.{ "Icebreaker", "AI" }, .cost = 1, .strength = 1, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 1,
        .break_subroutine_count = 1,
        .trashes_after_break = true,
    } },
    .{ .title = "Unity", .side = .runner, .code = 30026, .card_type = "Program", .subtypes = &.{ "Icebreaker", "Decoder" }, .cost = 3, .strength = 1, .runner_install = .{ .kind = .program }, .installed_ability = .{
        .kind = .break_subroutine,
        .credit_cost = 1,
        .break_subroutine_count = 2,
    } },
    .{ .title = "Conduit", .side = .runner, .code = 30024, .card_type = "Program", .cost = 4, .runner_install = .{ .kind = .program } },
    .{ .title = "Leech", .side = .runner, .code = 30008, .card_type = "Program", .cost = 1, .runner_install = .{ .kind = .program } },
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

pub fn lookupCardSpecByCode(card_code: u32) ?CardSpec {
    for (all_cards) |spec| {
        if (spec.code == card_code) return spec;
    }
    return null;
}
