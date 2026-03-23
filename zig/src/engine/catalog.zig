const state = @import("state.zig");

pub const DeckLine = struct {
    qty: state.TinyCount,
    card_code: state.CardCode,
};

pub const CardSpec = struct {
    title: []const u8,
    side: state.Side,
    code: state.CardCode,
    card_type: ?[]const u8 = null,
    cost: ?state.Count = null,
    agenda_points: ?state.TinyCount = null,
    corp_play: state.CorpPlaySpec = .{},
    runner_play: state.RunnerPlaySpec = .{},
    access: state.AccessSpec = .{},
    install: state.InstallSpec = .{},
};

pub const SideSpec = struct {
    identity_code: state.CardCode,
    deck_lines: []const DeckLine,
};

pub const MatchupSpec = struct {
    format: []const u8,
    agenda_point_req: state.TinyCount,
    corp: SideSpec,
    runner: SideSpec,
};

pub const all_cards = [_]CardSpec{
    .{ .title = "The Syndicate: Profit over Principle", .side = .corp, .code = 30077, .card_type = "Identity" },
    .{ .title = "The Catalyst: Convention Breaker", .side = .runner, .code = 30076, .card_type = "Identity" },
    .{ .title = "Offworld Office", .side = .corp, .code = 30067, .card_type = "Agenda", .agenda_points = 2, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Send a Message", .side = .corp, .code = 30069, .card_type = "Agenda", .agenda_points = 3, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Superconducting Hub", .side = .corp, .code = 30070, .card_type = "Agenda", .agenda_points = 1, .access = .{ .kind = .steal_agenda }, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Nico Campaign", .side = .corp, .code = 30037, .card_type = "Asset", .cost = 2, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Regolith Mining License", .side = .corp, .code = 30071, .card_type = "Asset", .cost = 2, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Urtica Cipher", .side = .corp, .code = 30045, .card_type = "Asset", .cost = 0, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Government Subsidy", .side = .corp, .code = 30064, .card_type = "Operation", .cost = 10, .corp_play = .{ .kind = .gain_credits, .gain_credits = 15 } },
    .{ .title = "Hedge Fund", .side = .corp, .code = 30075, .card_type = "Operation", .cost = 5, .corp_play = .{ .kind = .gain_credits, .gain_credits = 9 } },
    .{ .title = "Seamless Launch", .side = .corp, .code = 30040, .card_type = "Operation", .cost = 1, .corp_play = .{ .kind = .no_op } },
    .{ .title = "Manegarm Skunkworks", .side = .corp, .code = 30042, .card_type = "Upgrade", .cost = 2, .install = .{ .kind = .corp_remote_only } },
    .{ .title = "Brân 1.0", .side = .corp, .code = 30039, .card_type = "ICE", .cost = 6, .install = .{ .kind = .corp_server_choice } },
    .{ .title = "Palisade", .side = .corp, .code = 30072, .card_type = "ICE", .cost = 3, .install = .{ .kind = .corp_server_choice } },
    .{ .title = "Diviner", .side = .corp, .code = 30046, .card_type = "ICE", .cost = 2, .install = .{ .kind = .corp_server_choice } },
    .{ .title = "Whitespace", .side = .corp, .code = 30074, .card_type = "ICE", .cost = 2, .install = .{ .kind = .corp_server_choice } },
    .{ .title = "Karunā", .side = .corp, .code = 30047, .card_type = "ICE", .cost = 4, .install = .{ .kind = .corp_server_choice } },
    .{ .title = "Tithe", .side = .corp, .code = 30073, .card_type = "ICE", .cost = 1, .install = .{ .kind = .corp_server_choice } },
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
    .{ .title = "VRcation", .side = .runner, .code = 30021, .card_type = "Event", .cost = 1, .runner_play = .{ .kind = .gain_credits, .draw_cards = 4, .lose_clicks = 1 } },
    .{ .title = "Docklands Pass", .side = .runner, .code = 30013, .card_type = "Hardware", .cost = 2 },
    .{ .title = "Pennyshaver", .side = .runner, .code = 30014, .card_type = "Hardware", .cost = 3 },
    .{ .title = "Red Team", .side = .runner, .code = 30018, .card_type = "Resource", .cost = 5 },
    .{ .title = "Smartware Distributor", .side = .runner, .code = 30033, .card_type = "Resource", .cost = 0 },
    .{ .title = "Telework Contract", .side = .runner, .code = 30027, .card_type = "Resource", .cost = 1 },
    .{ .title = "Verbal Plasticity", .side = .runner, .code = 30034, .card_type = "Resource", .cost = 3 },
    .{ .title = "Carmen", .side = .runner, .code = 30015, .card_type = "Program", .cost = 5 },
    .{ .title = "Cleaver", .side = .runner, .code = 30006, .card_type = "Program", .cost = 3 },
    .{ .title = "Mayfly", .side = .runner, .code = 30032, .card_type = "Program", .cost = 1 },
    .{ .title = "Unity", .side = .runner, .code = 30026, .card_type = "Program", .cost = 3 },
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

pub fn lookupCardSpecByCode(card_code: state.CardCode) ?CardSpec {
    for (all_cards) |spec| {
        if (spec.code == card_code) return spec;
    }
    return null;
}
