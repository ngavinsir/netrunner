const state = @import("state.zig");

pub const DeckLine = struct {
    qty: state.TinyCount,
    title: []const u8,
};

pub const CardSpec = struct {
    title: []const u8,
    side: state.Side,
    code: ?state.CardCode = null,
    card_type: ?[]const u8 = null,
};

pub const SideSpec = struct {
    identity: CardSpec,
    deck_lines: []const DeckLine,
};

pub const MatchupSpec = struct {
    format: []const u8,
    agenda_point_req: state.TinyCount,
    corp: SideSpec,
    runner: SideSpec,
};

const beginner_corp_deck_lines = [_]DeckLine{
    .{ .qty = 3, .title = "Offworld Office" },
    .{ .qty = 2, .title = "Send a Message" },
    .{ .qty = 2, .title = "Superconducting Hub" },
    .{ .qty = 2, .title = "Nico Campaign" },
    .{ .qty = 2, .title = "Regolith Mining License" },
    .{ .qty = 2, .title = "Urtica Cipher" },
    .{ .qty = 2, .title = "Government Subsidy" },
    .{ .qty = 3, .title = "Hedge Fund" },
    .{ .qty = 2, .title = "Seamless Launch" },
    .{ .qty = 1, .title = "Manegarm Skunkworks" },
    .{ .qty = 2, .title = "Brân 1.0" },
    .{ .qty = 3, .title = "Palisade" },
    .{ .qty = 2, .title = "Diviner" },
    .{ .qty = 2, .title = "Whitespace" },
    .{ .qty = 2, .title = "Karunā" },
    .{ .qty = 2, .title = "Tithe" },
};

const beginner_runner_deck_lines = [_]DeckLine{
    .{ .qty = 2, .title = "Creative Commission" },
    .{ .qty = 3, .title = "Jailbreak" },
    .{ .qty = 2, .title = "Overclock" },
    .{ .qty = 3, .title = "Sure Gamble" },
    .{ .qty = 2, .title = "Tread Lightly" },
    .{ .qty = 2, .title = "VRcation" },
    .{ .qty = 1, .title = "Docklands Pass" },
    .{ .qty = 1, .title = "Pennyshaver" },
    .{ .qty = 1, .title = "Red Team" },
    .{ .qty = 2, .title = "Smartware Distributor" },
    .{ .qty = 2, .title = "Telework Contract" },
    .{ .qty = 1, .title = "Verbal Plasticity" },
    .{ .qty = 2, .title = "Carmen" },
    .{ .qty = 2, .title = "Cleaver" },
    .{ .qty = 2, .title = "Mayfly" },
    .{ .qty = 2, .title = "Unity" },
};

pub const system_gateway_beginner = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{
        .identity = .{
            .title = "The Syndicate: Profit over Principle",
            .side = .corp,
            .code = 30077,
            .card_type = "Identity",
        },
        .deck_lines = &beginner_corp_deck_lines,
    },
    .runner = .{
        .identity = .{
            .title = "The Catalyst: Convention Breaker",
            .side = .runner,
            .code = 30076,
            .card_type = "Identity",
        },
        .deck_lines = &beginner_runner_deck_lines,
    },
};
