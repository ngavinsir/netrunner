const std = @import("std");
const state = @import("state.zig");
const catalog = @import("catalog.zig");

pub const DeckLine = struct {
    qty: u8,
    card_code: u32,
};

pub const CardSpec = catalog.CardSpec;

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
    corp_scored,
};

pub const EventSource = struct {
    code: u32,
    event: state.GameEvent,
    side: state.Side,
    zone: CardZone,
    ability_index: u8 = 0,
    index: u16 = 0,
    server_index: u16 = 0,
    parent_index: u16 = 0,
    payload: ?state.EffectContext.EventPayload = null,
};

pub const PendingEffect = union(enum) {
    event_handler: EventSource,
    card_effect: struct { card: state.CardInstance, event: state.GameEvent, ability_index: u8, payload: ?state.EffectContext.EventPayload = null },
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

pub const all_cards = catalog.all_cards;

/// Find the play ability in a card's abilities array
fn findPlayAbility(abilities: []const state.AbilitySpec) ?*const state.AbilitySpec {
    for (abilities) |*ability| {
        if (ability.is_play) return ability;
    }
    return null;
}

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

// Matchup for uncovered Tier 4 cards (runner events + corp cards not in other matchups)
const elevation_uncovered_runner_deck = [_]DeckLine{
    .{ .qty = 3, .card_code = 30030 }, // Sure Gamble (3)
    .{ .qty = 3, .card_code = 30028 }, // Jailbreak (6)
    .{ .qty = 1, .card_code = 35004 }, // Scrounge (7)
    .{ .qty = 1, .card_code = 35005 }, // Shred (8)
    .{ .qty = 1, .card_code = 35015 }, // Lie Low (9)
    .{ .qty = 1, .card_code = 35016 }, // Maintenance Access (10)
    .{ .qty = 1, .card_code = 35017 }, // Transfer of Wealth (11)
    .{ .qty = 1, .card_code = 35025 }, // Illumination (12)
    .{ .qty = 2, .card_code = 30005 }, // Buzzsaw (14)
    .{ .qty = 2, .card_code = 30006 }, // Cleaver (16)
    .{ .qty = 2, .card_code = 30025 }, // Echelon (18)
    .{ .qty = 2, .card_code = 30026 }, // Unity (20)
    .{ .qty = 2, .card_code = 30024 }, // Conduit (22)
    .{ .qty = 2, .card_code = 30008 }, // Leech (24)
    .{ .qty = 2, .card_code = 30033 }, // Smartware Distributor (26)
    .{ .qty = 2, .card_code = 30027 }, // Telework Contract (28)
    .{ .qty = 1, .card_code = 30031 }, // T400 Memory Diamond (29)
    .{ .qty = 1, .card_code = 30021 }, // VRcation (30)
};
const elevation_uncovered_corp_deck = [_]DeckLine{
    .{ .qty = 3, .card_code = 30067 }, // Offworld Office
    .{ .qty = 2, .card_code = 30069 }, // Send a Message
    .{ .qty = 2, .card_code = 30070 }, // Superconducting Hub
    .{ .qty = 1, .card_code = 35053 }, // Mycoweb
    .{ .qty = 1, .card_code = 35066 }, // IP Enforcement
    .{ .qty = 2, .card_code = 30037 }, // Nico Campaign
    .{ .qty = 2, .card_code = 30071 }, // Regolith Mining License
    .{ .qty = 2, .card_code = 30045 }, // Urtica Cipher
    .{ .qty = 3, .card_code = 30075 }, // Hedge Fund
    .{ .qty = 2, .card_code = 30040 }, // Seamless Launch
    .{ .qty = 3, .card_code = 30072 }, // Palisade
    .{ .qty = 2, .card_code = 30046 }, // Diviner
    .{ .qty = 2, .card_code = 30074 }, // Whitespace
    .{ .qty = 2, .card_code = 30047 }, // Karunā
    .{ .qty = 2, .card_code = 30073 }, // Tithe
};
pub const elevation_uncovered = MatchupSpec{
    .format = "system-gateway",
    .agenda_point_req = 7,
    .corp = .{ .identity_code = 30059, .deck_lines = &elevation_uncovered_corp_deck }, // BTL
    .runner = .{ .identity_code = 30076, .deck_lines = &elevation_uncovered_runner_deck }, // Catalyst
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
    corp_extra_clicks_next_turn: u8 = 0, // bonus clicks for corp next turn (e.g. Aggressive Trendsetting)
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

pub fn isAbilityUsedThisTurn(card: *const state.CardInstance, ability_index: u4) bool {
    return (card.abilities_used_this_turn & (@as(u16, 1) << ability_index)) != 0;
}

pub fn markAbilityUsedThisTurn(card: *state.CardInstance, ability_index: u4) void {
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

pub const prompt_run_central = "run-central";
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

pub fn gameFromEffectContext(ctx: *state.EffectContext) *Game {
    return ctx.game_ptr;
}

pub fn gameFromConstEffectContext(ctx: *const state.EffectContext) *const Game {
    return ctx.game_ptr;
}

/// Check if a card has GAMEDRAGON Pro hosted on it (extends pump duration to end-of-run).
fn hasGamedragonHosted(card: state.CardInstance) bool {
    for (card.hosted) |h| {
        if (h.code != null and h.code.? == 35027) return true;
    }
    return false;
}

/// Reset encounter strength boosts, preserving pumps on GAMEDRAGON-hosted icebreakers.
fn resetEncounterStrength(game: *Game) void {
    for (game.runner_rig_program.items) |*card| {
        if (!hasGamedragonHosted(card.*)) {
            card.current_strength = null;
        }
    }
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

pub fn applyCostModifier(base: u16, modifier: i16) u16 {
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

pub fn sumStaticEffectsInCards(
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

pub fn sumStaticEffects(
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
        .use_corp_ability => {
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
                            if (card.draw_on_empty > 0) try drawCards(generated, .runner, card.draw_on_empty);
                            if (card.clicks_on_empty > 0) generated.runner_click += card.clicks_on_empty;
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

    // Fire runner_discarded_to_hand_size for identity abilities (e.g., Magdalene)
    if (side == .runner) {
        _ = try fireEvent(generated, .runner_discarded_to_hand_size);
        if (generated.runner_prompt_state) |ps| {
            const allocator = generated.arena.allocator();
            generated.decision_side = .runner;
            generated.legal_actions = try promptChoiceActions(allocator, .runner, ps);
            return;
        }
    }

    try finishEndTurn(generated, side);
}

/// Called from on_choice handlers (e.g., Magdalene) that trigger during runner end-of-turn
/// discard phase. Resumes the normal end-of-turn flow.
pub fn completeRunnerEndTurn(g: *Game) !void {
    try finishEndTurn(g, .runner);
}

fn finishEndTurn(generated: *Game, side: state.Side) !void {
    generated.systemMsg(side, 0, "{s} ends their turn.", .{sideName(side)});
    const next_side = otherSide(side);
    generated.end_turn = true;
    const allocator = generated.arena.allocator();
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
        // If runner_end_turn triggered a runner optional prompt (e.g., Cacophony sabotage),
        // present it before transitioning to the corp's turn.
        if (generated.runner_prompt_state) |ps| {
            generated.decision_side = .runner;
            generated.legal_actions = try promptChoiceActions(allocator, .runner, ps);
            return;
        }
    }
    generated.decision_side = next_side;
    generated.legal_actions = try startTurnActions(allocator, next_side);
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

    if (side == .corp and std.mem.eql(u8, prompt.prompt_type, "byte-ambush")) {
        try applyByteAmbushChoice(generated, choice_text);
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

    if (side == .runner and std.mem.eql(u8, prompt.prompt_type, prompt_run_target) and prompt.source_card != null and prompt.on_choice == null) {
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
        const decision_before = generated.decision_side;
        try handler(effectContext(generated), choice_text);
        if (hasActivePrompt(generated)) return;
        if (try resumePendingEffects(generated)) return;
        // Only auto-update opening actions if the handler didn't change decision_side
        // AND there's no active run (run prompts must handle their own continuation).
        if (generated.decision_side == decision_before and generated.run == null) {
            const allocator = generated.arena.allocator();
            if (side == .corp) {
                generated.decision_side = .corp;
                generated.legal_actions = try corpOpeningActionsForState(allocator, generated);
            } else {
                generated.decision_side = .runner;
                generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
            }
        }
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
        // Queue agenda's own event_abilities for .agenda_scored
        for (spec.event_abilities, 0..) |ea, ea_idx| {
            if (ea.event == .agenda_scored) {
                try generated.pending_effects.append(allocator, .{ .card_effect = .{
                    .card = scored_agenda,
                    .event = .agenda_scored,
                    .ability_index = @intCast(ea_idx),
                    .payload = .{ .kind = .agenda_scored, .source_code = scored_agenda.code, .server_index = @intCast(target.server_index) },
                } });
            }
        }
    }

    // Collect event handlers (appends to pending_effects without draining)
    try collectEventHandlers(generated, .{ .kind = .agenda_scored, .source_code = scored_agenda.code, .server_index = @intCast(target.server_index) });

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

pub fn installedCardChoices(
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

pub fn installedNotThisTurnChoices(
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

pub fn addAdvancementCounter(
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
        if (was_zero) {
            try collectEventHandlers(generated, .{ .kind = .advance });
            if (try drainPendingEffects(generated)) {}
        }
        return card.*;
    }
    if (target.card_index >= server.content.items.len) return error.UnsupportedChoice;
    var card = &server.content.items[target.card_index];
    const was_zero = card.advancement_counter == 0;
    card.advancement_counter += amount;
    if (was_zero) {
        try collectEventHandlers(generated, .{ .kind = .advance });
        if (try drainPendingEffects(generated)) {}
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

pub fn updateTerminalState(generated: *Game) void {
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

pub fn is_runner_tagged(tag: ?state.TagState) bool {
    if (tag) |tag_state| return tag_state.is_tagged or tag_state.total > 0;
    return false;
}

/// Give the runner tags and fire the runner_gain_tag event.
/// Returns true if an event handler opened a prompt (caller should return).
pub fn purgeVirusCounters(generated: *Game) void {
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

pub fn removeRunnerTags(generated: *Game, count: u8) !void {
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
        try collectEventHandlers(generated, .{ .kind = .runner_lose_tag });
    }
}

pub fn addRunnerTag(generated: *Game, count: u8) !bool {
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
        .corp_scored => {
            if (src.index < generated.corp_scored.items.len) {
                const card = &generated.corp_scored.items[src.index];
                if (card.code != null and card.code.? == src.code) return card;
            }
            for (generated.corp_scored.items) |*card| {
                if (card.code != null and card.code.? == src.code) return card;
            }
            return null;
        },
    }
}

/// Find the array index of a card in runner resources by code (for removal after event)
pub fn findRunnerResourceIndex(generated: *const Game, code: u32) ?usize {
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
    payload: state.EffectContext.EventPayload,
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
            .payload = payload,
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
                const ctx = if (src.payload) |p| effectContextWithEvent(generated, p) else effectContext(generated);
                try ability.handler(ctx, card);
                if (hasActivePrompt(generated)) return true;
            },
            .card_effect => |ce| {
                if (ce.event == .agenda_scored or ce.event == .agenda_stolen) {
                    if (lookupCardSpecByCode(ce.card.code orelse continue)) |spec| {
                        if (ce.ability_index >= spec.event_abilities.len) continue;
                        const ea = spec.event_abilities[ce.ability_index];
                        if (ea.event != ce.event) continue;
                        // Get a mutable pointer to the agenda in scored area
                        var mutable_card: *state.CardInstance = undefined;
                        var temp_card = ce.card;
                        if (ce.event == .agenda_scored) {
                            if (generated.corp_scored.items.len > 0) {
                                mutable_card = &generated.corp_scored.items[generated.corp_scored.items.len - 1];
                            } else continue;
                        } else {
                            // Stolen agendas may not be in runner_scored yet; use a temp copy
                            mutable_card = &temp_card;
                        }
                        const old_corp_prompt = generated.corp_prompt_state;
                        const old_runner_prompt = generated.runner_prompt_state;
                        const ce_ctx = if (ce.payload) |p| effectContextWithEvent(generated, p) else effectContext(generated);
                        try ea.handler(ce_ctx, mutable_card);
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
pub fn resumePendingEffects(generated: *Game) anyerror!bool {
    if (generated.pending_effects.items.len > 0) {
        return try drainPendingEffects(generated);
    }
    return false;
}

pub fn hasActivePrompt(generated: *const Game) bool {
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
pub fn collectEventHandlers(generated: *Game, payload: state.EffectContext.EventPayload) !void {
    const allocator = generated.backing_allocator;
    const event = payload.kind;

    try appendEventHandlersForCard(generated, allocator, generated.corp_identity, .corp, .identity, 0, 0, 0, event, payload);
    try appendEventHandlersForCard(generated, allocator, generated.runner_identity, .runner, .identity, 0, 0, 0, event, payload);

    for (generated.runner_rig_hardware.items, 0..) |hw, idx| {
        try appendEventHandlersForCard(generated, allocator, hw, .runner, .runner_hardware, @intCast(idx), 0, 0, event, payload);
    }
    for (generated.runner_rig_resources.items, 0..) |res, idx| {
        try appendEventHandlersForCard(generated, allocator, res, .runner, .runner_resource, @intCast(idx), 0, 0, event, payload);
    }
    for (generated.runner_rig_program.items, 0..) |prog, idx| {
        try appendEventHandlersForCard(generated, allocator, prog, .runner, .runner_program, @intCast(idx), 0, 0, event, payload);
    }
    for (generated.corp_servers.items, 0..) |server, server_idx| {
        for (server.content.items, 0..) |card, card_idx| {
            if (!card.rezzed) continue;
            try appendEventHandlersForCard(generated, allocator, card, .corp, .corp_server_content, @intCast(card_idx), @intCast(server_idx), 0, event, payload);
        }
        for (server.ices.items, 0..) |ice, ice_idx| {
            // Rezzed ice can have event abilities (e.g., Funhouse on-encounter)
            if (ice.rezzed) {
                try appendEventHandlersForCard(generated, allocator, ice, .corp, .corp_server_content, @intCast(ice_idx), @intCast(server_idx), 0, event, payload);
            }
            for (ice.hosted, 0..) |hosted, hosted_idx| {
                try appendEventHandlersForCard(generated, allocator, hosted, .runner, .corp_ice_hosted, @intCast(hosted_idx), @intCast(server_idx), @intCast(ice_idx), event, payload);
            }
        }
    }
    // Corp scored agendas — skip agenda_scored/agenda_stolen (those fire through card_effect separately)
    if (event != .agenda_scored and event != .agenda_stolen) {
        for (generated.corp_scored.items, 0..) |card, idx| {
            try appendEventHandlersForCard(generated, allocator, card, .corp, .corp_scored, @intCast(idx), 0, 0, event, payload);
        }
    }
}

/// Collect event handlers and immediately drain.
pub fn fireEvent(generated: *Game, event: state.GameEvent) anyerror!bool {
    try collectEventHandlers(generated, .{ .kind = event });
    return try drainPendingEffects(generated);
}

/// Fire an event with a full typed payload (e.g. carrying target_instance_id).
pub fn fireEventWith(generated: *Game, payload: state.EffectContext.EventPayload) anyerror!bool {
    try collectEventHandlers(generated, payload);
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
    generated.pending_install = null;
    generated.runner_prompt_state = null;
    if (try resumePendingEffects(generated)) return;
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(generated.arena.allocator(), generated);
}

pub fn runner_had_successful_run_last_turn(generated: *const Game) bool {
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

pub fn predictive_planogram_choices(
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

pub fn public_trail_choices(
    allocator: std.mem.Allocator,
    runner_credit: u16,
) ![]const state.PromptChoice {
    const count: usize = if (runner_credit >= 8) 2 else 1;
    const choices = try allocator.alloc(state.PromptChoice, count);
    choices[0] = stringChoice("Take 1 tag");
    if (runner_credit >= 8) choices[1] = stringChoice("Pay 8 [Credits]");
    return choices;
}

pub fn retribution_choices(
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

pub fn hasSubtype(card: state.CardInstance, subtype: []const u8) bool {
    for (card.subtypes) |s| {
        if (std.mem.eql(u8, s, subtype)) return true;
    }
    return false;
}

pub fn isIcebreaker(card: state.CardInstance) bool {
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

pub fn canBreakIceType(breaker: state.CardInstance, ice: state.CardInstance) bool {
    if (hasSubtype(breaker, "AI")) return true;
    if (hasSubtype(breaker, "Fracter") and iceHasSubtype(ice, "Barrier")) return true;
    if (hasSubtype(breaker, "Killer") and iceHasSubtype(ice, "Sentry")) return true;
    if (hasSubtype(breaker, "Decoder") and iceHasSubtype(ice, "Code Gate")) return true;
    return false;
}

pub fn effectiveStrength(card: state.CardInstance) u8 {
    var base: i16 = @intCast(card.current_strength orelse card.strength orelse 0);
    // Add unconditional strength bonuses from hosted items (e.g., GAMEDRAGON Pro)
    for (card.hosted) |hosted| {
        for (hosted.static_abilities) |sa| {
            if (sa.kind == .self_strength and sa.req == null) {
                base += sa.value;
            }
        }
    }
    return if (base > 0) @intCast(base) else 0;
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

pub fn wildcat_strike_choices(allocator: std.mem.Allocator) ![]const state.PromptChoice {
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
    const base_trash_cost = spec.trash_cost orelse return error.UnsupportedAccessTarget;
    const bonus = sumStaticEffects(generated, .corp, .trash_cost, &accessed);
    const trash_cost: u16 = @intCast(@max(0, @as(i32, base_trash_cost) + bonus));
    // Auto-spend eligible pay-credits for trashing corp cards
    const actual_cost = spendPayCredits(generated, trash_cost, .runner_trash_corp, &accessed);
    try spendCredits(generated, .runner, actual_cost);
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
    // Fire corp_card_runner_trashed before removing (so the card's own handlers can fire)
    if (try fireEventWith(generated, .{
        .kind = .corp_card_runner_trashed,
        .target_instance_id = accessed.instance_id,
    })) return;
    if (generated.game_over) return;
    // Fire runner_trash_corp_card event (Loup/Cacophony trigger)
    generated.turn_events.runner_trash_corp_card_count += 1;
    if (try fireEvent(generated, .runner_trash_corp_card)) return;
    try removeCurrentAccessedCard(generated);
    // Move to corp discard
    try appendDiscardCard(generated, .corp, accessed);
    try finishAccessCard(generated);
}

pub fn finishAccessCard(generated: *Game) !void {
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
    try collectEventHandlers(generated, .{ .kind = .agenda_stolen, .source_code = accessed.code });

    // Queue stolen agenda's own event_abilities for .agenda_stolen
    const pending_allocator = generated.backing_allocator;
    if (lookupCardSpec(accessed)) |spec| {
        for (spec.event_abilities, 0..) |ea, ea_idx| {
            if (ea.event == .agenda_stolen) {
                try generated.pending_effects.append(pending_allocator, .{ .card_effect = .{
                    .card = accessed,
                    .event = .agenda_stolen,
                    .ability_index = @intCast(ea_idx),
                    .payload = .{ .kind = .agenda_stolen, .source_code = accessed.code },
                } });
            }
        }
    }
    try generated.pending_effects.append(pending_allocator, .{ .finish_steal = .{
        .accessed = accessed,
        .is_central = is_central,
    } });
    if (try drainPendingEffects(generated)) return;
}

pub fn beginRezIceFreePrompt(
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

pub fn beginRezIceFreePromptForScore(
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

/// Wrapper for deferred_prompt: open runner discard-program-to-deck prompt
pub fn openRunnerDiscardToDeckPrompt(g: *Game, card: state.CardInstance, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) anyerror!bool {
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

pub fn removeCurrentAccessedCard(generated: *Game) !void {
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

    _ = generated.corp_discard.orderedRemove(card_index);
    try spendClicks(generated, .corp, 1); // flashback extra click cost
    try spendCredits(generated, .corp, card.cost orelse 0);
    try logCorpOperationPlay(generated, card, true);
    try resolveCorpOperation(generated, card);
    // Flashback always gains 1 click (only Petty Cash uses flashback)
    generated.corp_click += 1;
    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
}

pub fn logCorpOperationPlay(generated: *Game, card: state.CardInstance, from_archives: bool) !void {
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

pub fn resolveCorpOperation(generated: *Game, card: state.CardInstance) !void {
    const spec = lookupCardSpec(card) orelse return error.UnsupportedOperation;
    const play_ability = findPlayAbility(spec.abilities) orelse return error.UnsupportedOperation;
    const handler = play_ability.on_use orelse return error.UnsupportedOperation;
    var mutable_card = card;
    try handler(effectContext(generated), &mutable_card);
    if (generated.corp_prompt_state != null or generated.runner_prompt_state != null) return;
    generated.decision_side = .corp;
    generated.legal_actions = try corpOpeningActionsForState(generated.arena.allocator(), generated);
}

pub fn applyRunnerPlayFromHand(
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
}

pub fn applyInstallFromHand(
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

pub fn runnerHandInstallableByEffect(generated: *const Game, card: state.CardInstance) bool {
    if (card.runner_install.kind == .none) return false;
    const cost = runnerInstallCostForCard(generated, &card);
    const pc = availablePayCredits(generated, .runner_install, &card);
    if (generated.runner_credit + pc < cost) return false;
    if (hasSubtype(card, "Trojan") and !hasInstalledIce(generated)) return false;
    return true;
}

pub fn beginRunnerOptionalInstallConfirmPrompt(generated: *Game, source_instance_id: u32, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
    const allocator = generated.arena.allocator();
    generated.runner_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "runner-bonus-install-confirm"),
        .choices = try allocator.dupe(state.PromptChoice, &.{ stringChoice("Yes"), stringChoice("No") }),
        .ability_ref = .{ .source_instance_id = source_instance_id },
        .on_choice = on_choice,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
}

pub fn beginRunnerOptionalInstallPrompt(generated: *Game, source_instance_id: u32, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
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
        .ability_ref = .{ .source_instance_id = source_instance_id },
        .on_choice = on_choice,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
}

pub fn beginRunnerInstallFromHand(generated: *Game, card_index: u8, spend_click: bool) !void {
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

pub fn completeRunnerInstall(generated: *Game, card_index: u8, _: state.CardInstance, install_cost: u16, spend_click: bool) !void {
    const allocator = generated.arena.allocator();
    // Auto-spend eligible pay-credits for runner install
    const target_card = if (card_index < generated.runner_hand.items.len) &generated.runner_hand.items[card_index] else null;
    const actual_cost = spendPayCredits(generated, install_cost, .runner_install, target_card);
    try spendCredits(generated, .runner, actual_cost);

    var installed_card = try removeCardFromHand(generated, .runner, card_index);
    installed_card.credit_counter = installed_card.initial_credit_counters;
    clearAbilityUsage(&installed_card);
    try appendRunnerInstalledCard(generated, installed_card);
    generated.runner_install_context = .{ .install_cost = install_cost };
    defer generated.runner_install_context = null;
    // Dispatch card_installed event abilities for non-program installs (Bling, etc.)
    switch (installed_card.runner_install.kind) {
        .hardware => {
            if (generated.runner_rig_hardware.items.len > 0) {
                const card_ptr = &generated.runner_rig_hardware.items[generated.runner_rig_hardware.items.len - 1];
                for (card_ptr.event_abilities) |ea| {
                    if (ea.event == .card_installed) {
                        try ea.handler(effectContext(generated), card_ptr);
                    }
                }
            }
        },
        .resource => {
            if (generated.runner_rig_resources.items.len > 0) {
                const card_ptr = &generated.runner_rig_resources.items[generated.runner_rig_resources.items.len - 1];
                for (card_ptr.event_abilities) |ea| {
                    if (ea.event == .card_installed) {
                        try ea.handler(effectContext(generated), card_ptr);
                    }
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
    choice_text: []const u8,
) !void {
    generated.runner_prompt_state = null;
    try applyRunFromAbility(generated, choice_text, null);
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

pub fn applyRunFromAbility(
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
    // Auto-spend eligible pay-credits for rezzing
    const actual_cost = spendPayCredits(generated, adjusted_cost, .corp_rez, &target.ice);
    try spendCredits(generated, .corp, actual_cost);
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

    const rez_cost: u16 = card.cost orelse return error.InvalidCost;
    // Auto-spend eligible pay-credits for rezzing
    const actual_cost = spendPayCredits(generated, rez_cost, .corp_rez, card);
    if (generated.corp_credit < actual_cost) return error.InsufficientCredits;

    // Pay rez cost and set rezzed
    generated.corp_credit -= actual_cost;
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
pub fn findMutableServerByRunPath(
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

            // Fire ice_encountered event (triggers both ice abilities like Funhouse
            // and runner card abilities like Fransofia Ward)
            const ice = &generated.corp_servers.items[target.server_index].ices.items[target.ice_index];
            if (try fireEvent(generated, .ice_encountered)) return; // Event opened a prompt
            // Check if bypass was triggered by an event handler
            if (generated.run != null and generated.run.?.bypass) {
                try bypassCurrentIce(generated);
                return;
            }
            if (generated.run == null) return; // Run ended during event

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

pub fn openBreakSubPrompt(
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

    // Both sides passed during encounter — check bypass or fire unbroken subroutines
    if (generated.run.?.bypass) {
        try bypassCurrentIce(generated);
        return;
    }
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

    // Clear temporary strength boosts (GAMEDRAGON-hosted icebreakers keep pumps until end-of-run)
    resetEncounterStrength(generated);

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

/// Bypass the currently encountered ice: skip subroutines, clean up encounter, move to movement.
pub fn bypassCurrentIce(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    var run = &(generated.run orelse return);
    run.bypass = true;

    // Clear temporary strength boosts (GAMEDRAGON-hosted icebreakers keep pumps until end-of-run)
    resetEncounterStrength(generated);

    // Log bypass
    if (run.current_ice_index) |_| {
        generated.systemMsg(.runner, 0, "Runner bypasses ice.", .{});
    }

    // Move to movement phase (skip subroutine resolution)
    if (run.position > 0) run.position -= 1;
    run.phase = try allocator.dupe(u8, "movement");
    run.encounter_phase = .none;
    run.current_ice_index = null;
    run.bypass = false;
    run.jack_out_available = true;
    run.no_action = null;
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

pub fn checkServerApproachAbilities(generated: *Game) !bool {
    const run = generated.run orelse return false;
    if (run.position != 0) return false;

    const target_server = try findServerByRunPath(generated.corp_servers.items, run.server);
    const server = target_server.slot;

    for (server.content.items) |*card| {
        if (card.code) |code| {
            if (lookupCardSpecByCode(code)) |spec| {
                for (spec.event_abilities) |ea| {
                    if (ea.event == .server_approached) {
                        try ea.handler(effectContext(generated), card);
                        if (generated.corp_prompt_state != null or generated.runner_prompt_state != null) return true;
                    }
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

pub fn applyBranInstallIceChoice(
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
    resetEncounterStrength(generated);
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

/// Continue a run after a server-approach prompt was resolved (e.g. Mitra Aman declined).
/// Mirrors the flow that follows checkServerApproachAbilities returning false.
pub fn continueServerApproach(generated: *Game) !void {
    const allocator = generated.arena.allocator();
    const run = &(generated.run orelse return);
    try applySuccessfulRunEffects(generated);
    run.phase = try allocator.dupe(u8, "success");
    if (try fireEvent(generated, .successful_run)) return;
    try enterSuccessAccessPhase(generated);
}

pub fn prepareNextAccess(generated: *Game) !bool {
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

pub fn applySuccessfulRunEffects(generated: *Game) !void {
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
    // If an event handler (e.g., Conduit) set a prompt, present it
    if (generated.runner_prompt_state) |ps| {
        generated.decision_side = .runner;
        generated.legal_actions = try promptChoiceActions(allocator, .runner, ps);
        return;
    }
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
    // If an event handler (e.g., Conduit) set a prompt, present it
    if (generated.runner_prompt_state) |ps| {
        generated.decision_side = .runner;
        generated.legal_actions = try promptChoiceActions(allocator, .runner, ps);
        return;
    }
    generated.decision_side = .runner;
    generated.legal_actions = try runnerOpeningActionsForState(allocator, generated);
}

pub fn completeSuccessfulRunWithCorpPriority(generated: *Game) !void {
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
    // If an event handler (e.g., Conduit) set a prompt, preserve it
    if (generated.runner_prompt_state) |ps| {
        generated.decision_side = .runner;
        generated.legal_actions = try promptChoiceActions(allocator, .runner, ps);
        return;
    }
    generated.decision_side = .corp;
    generated.legal_actions = try continueActions(allocator, .corp);
}

pub fn completeUnsuccessfulRun(generated: *Game) !void {
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
    // Card-specific access handler (Urtica Cipher net damage, AMAZE Amusements, etc.)
    if (lookupCardSpec(accessed)) |spec| {
        for (spec.event_abilities) |ea| {
            if (ea.event == .access) {
                var mutable_accessed = accessed;
                try ea.handler(effectContext(generated), &mutable_accessed);
                if (generated.runner_prompt_state != null or generated.corp_prompt_state != null) return true;
                if (generated.game_over) return true;
            }
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
    const base_trash_cost = if (spec) |s| s.trash_cost else null;
    // Apply trash_cost static bonus (e.g. Mahkota Langit Grid: +2 for assets in same server)
    // Also check floating trash_cost effects (e.g. Mahkota lingering effect after trashed)
    const trash_cost: ?u16 = if (base_trash_cost) |tc| blk: {
        var bonus = sumStaticEffects(generated, .corp, .trash_cost, &accessed);
        // Add floating trash_cost effects (server-scoped lingering effects)
        const accessed_server_idx: ?usize = if (generated.run) |r| srv_blk: {
            const lookup = findServerByRunPath(generated.corp_servers.items, r.server) catch break :srv_blk null;
            break :srv_blk lookup.index;
        } else null;
        for (generated.floating_effects.items) |fe| {
            if (fe.kind == .trash_cost) {
                if (fe.target_server) |ts| {
                    if (accessed_server_idx != null and ts == accessed_server_idx.?) {
                        bonus += fe.value;
                    }
                } else {
                    bonus += fe.value;
                }
            }
        }
        break :blk @intCast(@max(0, @as(i32, tc) + bonus));
    } else null;
    const allocator = generated.arena.allocator();
    const no_steal_or_trash = hasFloatingEffect(generated, .prevent_steal_or_trash);
    const is_agenda = if (accessed.card_type) |ct| std.mem.eql(u8, ct, "Agenda") else false;

    const can_afford = if (trash_cost) |tc| blk2: {
        const pc = availablePayCredits(generated, .runner_trash_corp, &accessed);
        break :blk2 (generated.runner_credit + pc >= tc) and !no_steal_or_trash;
    } else false;
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

pub fn beginNetDamageOnAccessPrompt(
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

/// Byte! (35050): Corp may pay 4cr on access to give runner 1 tag + 3 net damage.
pub fn beginByteAmbushPrompt(generated: *Game, accessed: state.CardInstance) !bool {
    const allocator = generated.arena.allocator();
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    if (generated.corp_credit >= 4) {
        try choices.append(allocator, stringChoice("Pay 4 [Credits] to give 1 tag and do 3 net damage"));
    }
    try choices.append(allocator, stringChoice("No action"));
    generated.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "byte-ambush"),
        .choices = try choices.toOwnedSlice(allocator),
        .source_card = accessed,
    };
    return true;
}

fn applyByteAmbushChoice(generated: *Game, choice_text: []const u8) !void {
    const accessed = (if (generated.corp_prompt_state) |ps| ps.source_card else null) orelse return error.MissingSourceCard;
    generated.corp_prompt_state = null;

    if (std.mem.startsWith(u8, choice_text, "Pay ")) {
        try spendCredits(generated, .corp, 4);
        _ = try addRunnerTag(generated, 1);
        if (generated.game_over) return;
        try trashRandomRunnerHandCards(generated, 3);
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
    try finishAccessCard(generated);
}

/// Transition to the next side's start-turn sequence.
/// Call this from on_choice handlers triggered at end-of-turn to continue the game.
pub fn beginStartTurnSequence(g: *Game, side: state.Side) !void {
    const allocator = g.arena.allocator();
    g.decision_side = side;
    g.legal_actions = try startTurnActions(allocator, side);
}

/// Generic: show corp the top `count` cards of R&D and let them pick one to trash; rest are drawn.
/// `source_iid` is stored in ability_ref so the handler can log with the correct card.
pub fn beginPeekRdTopPrompt(g: *Game, count: u8, source_iid: u32) !void {
    const allocator = g.arena.allocator();
    const deck = g.corp_deck.items;
    const actual: u8 = @intCast(@min(count, deck.len));
    if (actual == 0) return; // nothing to peek
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    for (0..actual) |i| {
        try choices.append(allocator, stringChoice(
            try std.fmt.allocPrint(allocator, "peek|{d}|{s}", .{ i, deck[i].title }),
        ));
    }
    g.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "peek-rd-trash-one"),
        .choices = try choices.toOwnedSlice(allocator),
        .ability_ref = .{ .source_instance_id = source_iid, .ability_index = actual },
        .on_choice = &struct {
            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const cg = gameFromEffectContext(cctx);
                const ref = (cg.corp_prompt_state orelse return).ability_ref orelse return;
                const peek_count = ref.ability_index;
                cg.corp_prompt_state = null;
                // Parse "peek|index|title"
                var parts = std.mem.splitScalar(u8, choice_text, '|');
                _ = parts.next(); // "peek"
                const idx_text = parts.next() orelse return;
                const chosen_idx = std.fmt.parseInt(usize, idx_text, 10) catch return;
                if (chosen_idx >= cg.corp_deck.items.len) return;
                // Trash the chosen card
                const trashed = cg.corp_deck.orderedRemove(chosen_idx);
                try appendDiscardCard(cg, .corp, trashed);
                cg.systemMsg(.corp, 0, "Corp trashes {s} from top of R&D.", .{trashed.title});
                // Draw the remaining peeked cards (indices shifted after removal)
                const draw_count: u8 = if (peek_count > 1) peek_count - 1 else 0;
                if (draw_count > 0) {
                    try drawCards(cg, .corp, draw_count);
                }
            }
        }.choice,
    };
    g.decision_side = .corp;
    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
}

/// Sabotage N: Corp chooses N cards to trash from HQ and/or top of R&D.
/// After completion, transitions to corp start of turn.
pub fn beginSabotagePrompt(g: *Game, count: u8) !void {
    const allocator = g.arena.allocator();
    if (count == 0) {
        try beginStartTurnSequence(g, .corp);
        return;
    }
    const hq_count: u8 = @intCast(g.corp_hand.items.len);
    const rd_count: u8 = @intCast(@min(count, g.corp_deck.items.len));
    if (hq_count == 0 and rd_count == 0) {
        try beginStartTurnSequence(g, .corp);
        return;
    }
    // If no HQ cards, just trash from R&D automatically
    if (hq_count == 0) {
        var i: u8 = 0;
        while (i < rd_count) : (i += 1) {
            if (g.corp_deck.items.len == 0) break;
            const trashed = g.corp_deck.orderedRemove(0);
            try appendDiscardCard(g, .corp, trashed);
        }
        g.systemMsg(.corp, 0, "Corp trashes top {d} card(s) of R&D to sabotage.", .{rd_count});
        try beginStartTurnSequence(g, .corp);
        return;
    }
    // Build choices: HQ cards + "Top card of R&D" (if R&D has cards)
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);
    for (g.corp_hand.items) |card| {
        try choices.append(allocator, stringChoice(
            try std.fmt.allocPrint(allocator, "{s}", .{card.title}),
        ));
    }
    if (g.corp_deck.items.len > 0) {
        try choices.append(allocator, stringChoice(
            try allocator.dupe(u8, "Top card of R&D"),
        ));
    }
    // Store remaining count in ability_ref.ability_index
    g.corp_prompt_state = .{
        .prompt_type = try allocator.dupe(u8, "sabotage"),
        .choices = try choices.toOwnedSlice(allocator),
        .ability_ref = .{ .source_instance_id = 0, .ability_index = count },
        .on_choice = &struct {
            fn choice(cctx: *state.EffectContext, choice_text: []const u8) anyerror!void {
                const cg = gameFromEffectContext(cctx);
                const ref = (cg.corp_prompt_state orelse return).ability_ref orelse return;
                const remaining: u8 = ref.ability_index;
                cg.corp_prompt_state = null;
                if (std.mem.eql(u8, choice_text, "Top card of R&D")) {
                    if (cg.corp_deck.items.len > 0) {
                        const trashed = cg.corp_deck.orderedRemove(0);
                        try appendDiscardCard(cg, .corp, trashed);
                        cg.systemMsg(.corp, 0, "Corp trashes top card of R&D to sabotage.", .{});
                    }
                } else {
                    for (cg.corp_hand.items, 0..) |card, idx| {
                        if (std.mem.eql(u8, card.title, choice_text)) {
                            const trashed = cg.corp_hand.orderedRemove(idx);
                            try appendDiscardCard(cg, .corp, trashed);
                            cg.systemMsg(.corp, 0, "Corp trashes {s} from HQ to sabotage.", .{trashed.title});
                            _ = try fireEvent(cg, .corp_trash_from_hand);
                            break;
                        }
                    }
                }
                const new_remaining = remaining - 1;
                if (new_remaining > 0 and (cg.corp_hand.items.len > 0 or cg.corp_deck.items.len > 0)) {
                    try beginSabotagePrompt(cg, new_remaining);
                } else {
                    try beginStartTurnSequence(cg, .corp);
                }
            }
        }.choice,
    };
    g.decision_side = .corp;
    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
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

pub fn continueActions(
    allocator: std.mem.Allocator,
    side: state.Side,
) ![]const state.LegalAction {
    return switch (side) {
        .corp => &corp_continue_actions,
        .runner => runnerContinueActions(allocator, false), // Will be updated by caller if needed
    };
}

pub fn continueActionsForRun(
    allocator: std.mem.Allocator,
    side: state.Side,
    run: ?state.RunState,
) ![]const state.LegalAction {
    return continueActionsForRunWithRez(allocator, side, run, null);
}

pub fn continueActionsForRunWithRez(
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
            // Check corp identity for usable abilities during a run (e.g., LEO Construction)
            var identity_ability_count: usize = 0;
            if (game) |g| {
                const id = &g.corp_identity;
                for (id.abilities, 0..) |ability, idx| {
                    if (ability.once_per_turn and isAbilityUsedThisTurn(id, @intCast(idx))) continue;
                    if (ability.req) |req| {
                        if (!req(effectContextConst(g), id)) continue;
                    }
                    identity_ability_count += 1;
                }
            }
            const extra = rez_actions.len + @as(usize, if (has_ice_rez) 1 else 0) + identity_ability_count;
            if (extra == 0) break :blk &corp_continue_actions;
            // Combine continue + rez actions + identity abilities
            var combined = try allocator.alloc(state.LegalAction, 1 + extra);
            combined[0] = corp_continue_actions[0]; // continue action
            @memcpy(combined[1 .. 1 + rez_actions.len], rez_actions);
            var out_idx: usize = 1 + rez_actions.len;
            if (has_ice_rez) {
                combined[out_idx] = .{ .kind = .rez_ice, .side = .corp };
                out_idx += 1;
            }
            if (game) |g| {
                const id = &g.corp_identity;
                for (id.abilities, 0..) |ability, idx| {
                    if (ability.once_per_turn and isAbilityUsedThisTurn(id, @intCast(idx))) continue;
                    if (ability.req) |req| {
                        if (!req(effectContextConst(g), id)) continue;
                    }
                    combined[out_idx] = .{
                        .kind = .use_corp_ability,
                        .side = .corp,
                        .ability_ref = .{ .source_instance_id = id.instance_id, .ability_index = @intCast(idx) },
                        .label = ability.label,
                    };
                    out_idx += 1;
                }
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
    const pay_credits = availablePayCredits(game, .corp_rez, &target.ice);
    return game.corp_credit + pay_credits >= adjusted_cost;
}

fn corpRezNonIceActions(allocator: std.mem.Allocator, game: *const Game) ![]const state.LegalAction {
    const run = game.run orelse return &[_]state.LegalAction{};
    const target_server = findServerByRunPath(game.corp_servers.items, run.server) catch return &[_]state.LegalAction{};
    const server = target_server.slot;
    var count: usize = 0;
    for (server.content.items) |*card| {
        if (!card.rezzed and card.cost != null) {
            const pc = availablePayCredits(game, .corp_rez, card);
            if (game.corp_credit + pc >= card.cost.?) count += 1;
        }
    }
    if (count == 0) return &[_]state.LegalAction{};

    const actions = try allocator.alloc(state.LegalAction, count);
    var idx: usize = 0;
    for (server.content.items, 0..) |*card, card_idx| {
        if (!card.rezzed and card.cost != null and (game.corp_credit + availablePayCredits(game, .corp_rez, card) >= card.cost.?)) {
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

pub fn isInEncounter(ctx: *const state.EffectContext, _: *const state.CardInstance) bool {
    const g = gameFromConstEffectContext(ctx);
    const run = g.run orelse return false;
    return std.mem.eql(u8, run.phase, "encounter-ice");
}

pub fn encounterBreakHandler(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
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

pub fn encounterPumpHandler(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
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

pub fn encounterLeechHandler(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
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

pub fn encounterBotulusHandler(ctx: *state.EffectContext, card: *state.CardInstance) anyerror!void {
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

pub fn encounterBioroidHandler(ctx: *state.EffectContext, _: *state.CardInstance) anyerror!void {
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

pub fn encounterActionsForState(
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

    // Only offer pump/non-icebreaker abilities/bioroid/botulus if there are unbroken subroutines remaining
    var bioroid_ability_count: usize = 0;
    var pump_count: usize = 0;
    var non_icebreaker_ability_count: usize = 0;
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
        // Non-icebreaker programs with encounter abilities (e.g. Leech)
        for (generated.runner_rig_program.items) |card| {
            if (isIcebreaker(card)) continue;
            non_icebreaker_ability_count += countCardAbilityActions(generated, .runner, card);
        }
        // Botulus: hosted cards on ICE with abilities
        for (ice.hosted) |hosted| {
            if (hosted.abilities.len > 0 and hosted.virus_counter > 0) {
                botulus_count += 1;
            }
        }
    }

    const total_actions = 1 + breaker_count + bioroid_ability_count + pump_count + non_icebreaker_ability_count + botulus_count;
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

        // Non-icebreaker programs with encounter abilities (e.g. Leech)
        for (generated.runner_rig_program.items) |card| {
            if (isIcebreaker(card)) continue;
            next = try emitCardAbilityActions(allocator, generated, .runner, card, actions, next);
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

pub fn corpOpeningActionsForState(
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
    // - Cards with can_advance static ability can be advanced
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
        for (server.content.items, 0..) |*card, card_idx| {
            if (!card.rezzed and card.cost != null and (g.corp_credit + availablePayCredits(g, .corp_rez, card) >= card.cost.?)) {
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
        for (server.content.items) |*card| {
            if (!card.rezzed and card.cost != null) {
                const pc = availablePayCredits(g, .corp_rez, card);
                if (g.corp_credit + pc >= card.cost.?) count += 1;
            }
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

pub fn runnerOpeningActionsForState(
    allocator: std.mem.Allocator,
    g: *const Game,
) ![]const state.LegalAction {
    if (g.runner_click == 0) return endTurnActions(allocator, .runner);

    const runnable_servers = try runnableServers(allocator, g.corp_servers.items);

    var playable_hand_count: usize = 0;
    for (g.runner_hand.items) |*card| {
        const first_program_discount = if (card.runner_install.kind == .program) runnerInstalledFirstProgramDiscount(g, card) else 0;
        // Include eligible pay-credits for install affordability
        const pc = if (card.runner_install.kind != .none) availablePayCredits(g, .runner_install, card) else 0;
        if (isRunnerCardPlayableFromHand(g.runner_click, g.runner_credit + pc, card.*, g.runner_successful_run_this_turn, first_program_discount, runnerHasConsoleInstalled(g), corpHasInstalledIce(g))) playable_hand_count += 1;
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

pub fn stringChoice(text: []const u8) state.PromptChoice {
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

pub fn appendHostedCard(
    allocator: std.mem.Allocator,
    host: *state.CardInstance,
    card: state.CardInstance,
) !void {
    const hosted = try allocator.alloc(state.CardInstance, host.hosted.len + 1);
    @memcpy(hosted[0..host.hosted.len], host.hosted);
    hosted[host.hosted.len] = card;
    host.hosted = hosted;
}

pub fn removeHostedCard(
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

pub fn hostedChoiceIndex(prompt: state.PromptState, choice_text: []const u8) ?usize {
    for (prompt.choices) |choice| {
        if (choice.text == null or !std.mem.eql(u8, choice.text.?, choice_text)) continue;
        if (choice.card) |card_ref| {
            if (card_ref.index) |index| return index;
        }
    }
    return null;
}

pub fn restorePriorityAfterPrompt(generated: *Game) !void {
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

pub fn beginYesNoPrompt(
    generated: *Game,
    side: state.Side,
    prompt_type: []const u8,
    source_instance_id: u32,
    on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void,
) !void {
    const allocator = generated.arena.allocator();
    const prompt_state: state.PromptState = .{
        .prompt_type = try allocator.dupe(u8, prompt_type),
        .choices = try allocator.dupe(state.PromptChoice, &.{ stringChoice("Yes"), stringChoice("No") }),
        .ability_ref = .{ .source_instance_id = source_instance_id },
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

pub fn findCardPtrByInstanceId(generated: *Game, instance_id: u32) ?*state.CardInstance {
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

pub fn trashRunnerRigCardByInstanceId(generated: *Game, instance_id: u32) !void {
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

pub fn trashCorpServerCardByInstanceId(generated: *Game, instance_id: u32) !void {
    const ref = findCorpServerCardByInstanceId(generated, instance_id) orelse return error.CardNotFound;
    const trashed = generated.corp_servers.items[ref.server_index].content.orderedRemove(ref.content_index);
    try appendDiscardCard(generated, .corp, trashed);
    try removeServerIfEmpty(generated, ref.server_index);
}

/// Remove a corp installed card from the game (not to discard — removed from game / RFG).
pub fn removeCorpInstalledFromGame(generated: *Game, instance_id: u32) !void {
    const ref = findCorpServerCardByInstanceId(generated, instance_id) orelse return error.CardNotFound;
    _ = generated.corp_servers.items[ref.server_index].content.orderedRemove(ref.content_index);
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

            const decision_before = generated.decision_side;
            if (ability.on_use) |handler| {
                try handler(effectContext(generated), card);
            }
            // Only auto-update opening actions if:
            // - no active prompt
            // - no pending access
            // - run has ended (run == null)
            // - the handler didn't already change decision_side (e.g., completeUnsuccessfulRun)
            if (!hasActivePrompt(generated) and generated.pending_access == null and generated.run == null
                and generated.decision_side == decision_before) {
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

pub fn countPlayableHostedRunnerCards(generated: *const Game, host: state.CardInstance) usize {
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

pub fn beginRunnerHostedCardPrompt(generated: *Game, source_instance_id: u32, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
    const allocator = generated.arena.allocator();
    const source_card_ptr = findCardPtrByInstanceId(generated, source_instance_id) orelse return error.CardNotFound;
    var choices: std.ArrayList(state.PromptChoice) = .empty;
    defer choices.deinit(allocator);

    const has_console = runnerHasConsoleInstalled(generated);
    const has_ice = corpHasInstalledIce(generated);
    for (source_card_ptr.hosted, 0..) |card, idx| {
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
        .ability_ref = .{ .source_instance_id = source_instance_id },
        .on_choice = on_choice,
    };
    generated.decision_side = .runner;
    generated.legal_actions = try promptChoiceActions(allocator, .runner, generated.runner_prompt_state.?);
}

pub fn hostTopRunnerDeckCard(generated: *Game, host: *state.CardInstance) !void {
    if (generated.runner_deck.items.len == 0) return;
    const card = generated.runner_deck.orderedRemove(0);
    try appendHostedCard(generated.arena.allocator(), host, card);
}

pub fn trashHostedRunnerCards(generated: *Game, host: *state.CardInstance) !void {
    while (host.hosted.len > 0) {
        const trashed = try removeHostedCard(generated.arena.allocator(), host, 0);
        try appendDiscardCard(generated, .runner, trashed);
    }
}

pub fn returnHostedCardsToHq(generated: *Game, host: *state.CardInstance, count: usize) !void {
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

pub fn hostRandomHqCard(generated: *Game, host: *state.CardInstance) !void {
    const chosen = try peekShuffledCorpHandIndex(generated) orelse return;
    var card = generated.corp_hand.orderedRemove(chosen);
    card.seen = true;
    try appendHostedCard(generated.arena.allocator(), host, card);
}

pub fn beginRandomHqAccess(generated: *Game) !void {
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
        .pay_credits = spec.pay_credits,
        .initial_credit_counters = spec.initial_credit_counters,
        .take_credits_amount = spec.take_credits_amount,
        .trash_on_empty = spec.trash_on_empty,
        .initial_virus_counters = spec.initial_virus_counters,
        .initial_power_counters = spec.initial_power_counters,
        .draw_on_take = spec.draw_on_take,
        .draw_on_empty = spec.draw_on_empty,
        .clicks_on_empty = spec.clicks_on_empty,
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

pub fn appendRunnerInstalledCard(
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
                if (card.draw_on_take > 0) {
                    try drawCards(game, .corp, card.draw_on_take);
                }

                if (card.trash_on_empty and card.credit_counter == 0) {
                    if (card.draw_on_empty > 0) try drawCards(game, .corp, card.draw_on_empty);
                    if (card.clicks_on_empty > 0) game.corp_click += card.clicks_on_empty;
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
    generated.corp_click = generated.corp_click_per_turn + generated.corp_extra_clicks_next_turn;
    generated.corp_extra_clicks_next_turn = 0;
    generated.runner_successful_run_last_turn = generated.runner_successful_run_this_turn;
    generated.runner_successful_run_this_turn = false;

    // Clear installed_this_turn flags for all corp cards
    clearInstalledThisTurnFlags(generated);

    _ = try fireEvent(generated, .corp_turn_begins);
    if (generated.game_over) return;

    // Auto-trigger start-of-turn abilities (Nico Campaign)
    try applyCorpStartOfTurnAbilities(generated);
    if (generated.game_over) return;

    // If a corp prompt was opened during start-of-turn events (e.g., AU Co. peek, Plutus auto-play),
    // present it instead of jumping directly to opening actions.
    if (generated.corp_prompt_state != null) {
        generated.decision_side = .corp;
        generated.legal_actions = try promptChoiceActions(allocator, .corp, generated.corp_prompt_state.?);
        return;
    }

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
    // Apply initial counters from data fields
    card.virus_counter += card.initial_virus_counters;
    card.power_counter += card.initial_power_counters;
    if (card.virus_counter > 0 or hasSubtype(card.*, "Virus")) {
        card.virus_counter += runnerCookbookBonus(generated, card);
    }
}

/// Check if runner has a run event in play area (Sang Kancil pump discount)
pub fn runnerHasActiveRunEvent(generated: *const Game) bool {
    // Run events are in the play area when active — check if run has a source card
    // that is a run event (subtypes include "Run")
    if (generated.run) |run| {
        if (run.source_instance_id) |_| return true;
    }
    return false;
}

/// Count fracters in runner's heap (Rising Tide strength bonus)
pub fn countFractersInHeap(generated: *const Game) u8 {
    var count: u8 = 0;
    for (generated.runner_discard.items) |card| {
        if (hasSubtype(card, "Fracter")) count += 1;
    }
    return count;
}

/// Count installed icebreakers (Principia install cost reduction)
/// Returns true if the server currently being run has at least one rezzed bioroid ICE.
pub fn serverHasBioroidIce(g: *const Game) bool {
    const run = g.run orelse return false;
    const target = findServerByRunPath(@constCast(g).corp_servers.items, run.server) catch return false;
    for (target.slot.ices.items) |ice| {
        if (ice.rezzed and hasSubtype(ice, "Bioroid")) return true;
    }
    return false;
}

pub fn countInstalledIcebreakers(generated: *const Game) u16 {
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
    // At end of run, ALL strength boosts expire (including GAMEDRAGON-extended ones)
    for (game.runner_rig_program.items) |*card| {
        card.current_strength = null;
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

pub fn drawCards(game: *Game, side: state.Side, amount: u8) !void {
    var remaining = amount;
    while (remaining > 0) : (remaining -= 1) {
        try drawCard(game, side);
    }
}

pub fn trashRandomRunnerHandCards(
    game: *Game,
    amount: u8,
) !void {
    // Trash from front of hand (index 0). Clojure uses Java's rand-nth which is
    // separate from the game RNG, so we must NOT consume the game RNG here.
    // Both engines agree on the number of cards trashed; specific cards may differ
    // but parity comparison checks hand titles as a set, not order.
    var actual_trashed: u8 = 0;
    var remaining = amount;
    while (remaining > 0 and game.runner_hand.items.len > 0) : (remaining -= 1) {
        const trashed = game.runner_hand.orderedRemove(0);
        try game.runner_discard.append(game.backing_allocator, trashed);
        actual_trashed += 1;
    }
    // Fire corp_dealt_damage event so identities like AU Co. can react
    if (actual_trashed > 0 and !game.game_over) {
        _ = try fireEvent(game, .corp_dealt_damage);
    }
}

pub fn shuffleDeck(game: *Game, side: state.Side) !void {
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

pub fn removeCardFromHand(
    game: *Game,
    side: state.Side,
    index: u8,
) !state.CardInstance {
    const hand = handList(game, side);
    if (index >= hand.items.len) return error.InvalidCardIndex;
    const removed = hand.orderedRemove(index);
    return removed;
}

pub fn appendDiscardCard(
    game: *Game,
    side: state.Side,
    card: state.CardInstance,
) !void {
    try discardList(game, side).append(game.backing_allocator, card);
}

pub fn moveCorpHandCardToDeckAndShuffle(game: *Game, card_index: u8) !void {
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

pub fn spendClicks(
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

pub fn spendCredits(
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

/// Count available hosted credits from cards with matching pay_credits spec.
/// `target` is the card being paid for (e.g., the card being installed, or null).
pub fn availablePayCredits(game: *const Game, context: state.PayCreditsContext, target: ?*const state.CardInstance) u16 {
    var total: u16 = 0;
    const ctx = effectContextConst(game);
    // Scan runner installed cards
    for (game.runner_rig_resources.items) |*card| {
        total += checkPayCredits(ctx, card, context, target);
    }
    for (game.runner_rig_program.items) |*card| {
        total += checkPayCredits(ctx, card, context, target);
    }
    for (game.runner_rig_hardware.items) |*card| {
        total += checkPayCredits(ctx, card, context, target);
    }
    // Scan corp installed cards (for corp_rez context)
    for (game.corp_servers.items) |server| {
        for (server.content.items) |*card| {
            if (!card.rezzed) continue;
            total += checkPayCredits(ctx, card, context, target);
        }
    }
    return total;
}

fn checkPayCredits(ctx: *const state.EffectContext, card: *const state.CardInstance, context: state.PayCreditsContext, target: ?*const state.CardInstance) u16 {
    const spec = card.pay_credits orelse return 0;
    if (spec.context != context) return 0;
    if (card.credit_counter == 0) return 0;
    if (spec.req) |req| {
        if (!req(ctx, card, target)) return 0;
    }
    return card.credit_counter;
}

/// Auto-spend hosted credits from cards with matching pay_credits spec.
/// Returns the remaining amount that must be paid from the credit pool.
/// `target` is the card being paid for (e.g., the card being installed, or null).
pub fn spendPayCredits(game: *Game, amount: u16, context: state.PayCreditsContext, target: ?*const state.CardInstance) u16 {
    var remaining = amount;
    const ctx = effectContextConst(game);
    // Helper to try spending from a card slice
    const zones = [_]struct { items: []state.CardInstance }{
        .{ .items = game.runner_rig_resources.items },
        .{ .items = game.runner_rig_program.items },
        .{ .items = game.runner_rig_hardware.items },
    };
    for (&zones) |zone| {
        for (zone.items) |*card| {
            if (remaining == 0) break;
            if (trySpendFromCard(game, &ctx, card, context, target, &remaining)) {}
        }
    }
    // Corp installed cards (for corp_rez context)
    for (game.corp_servers.items) |*server| {
        for (server.content.items) |*card| {
            if (remaining == 0) break;
            if (!card.rezzed) continue;
            if (trySpendFromCard(game, &ctx, card, context, target, &remaining)) {}
        }
    }
    return remaining;
}

fn trySpendFromCard(game: *Game, ctx: *const *const state.EffectContext, card: *state.CardInstance, context: state.PayCreditsContext, target: ?*const state.CardInstance, remaining: *u16) bool {
    const spec = card.pay_credits orelse return false;
    if (spec.context != context) return false;
    if (card.credit_counter == 0) return false;
    if (spec.req) |req| {
        if (!req(ctx.*, card, target)) return false;
    }
    const spend: u16 = @min(card.credit_counter, remaining.*);
    card.credit_counter -= spend;
    remaining.* -= spend;
    game.systemMsg(card.side, card.code orelse 0, "Spends {d} [credit{s}] from {s}.", .{
        spend, if (spend != 1) @as([]const u8, "s") else @as([]const u8, ""), card.title,
    });
    return true;
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
    if (!play_ability.is_flashback) return false;
    if (g.corp_click < 2) return false; // 1 base click + 1 extra for flashback
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

pub fn installChoicesForCard(
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

pub fn promptChoiceActions(
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

pub fn runTargetChoicesFor(
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

pub fn trackMadeRun(generated: *Game, run_server: []const []const u8) void {
    if (run_server.len == 0) return;
    if (std.mem.eql(u8, run_server[0], "hq")) {
        generated.turn_events.made_run_on_hq = true;
    } else if (std.mem.eql(u8, run_server[0], "rnd")) {
        generated.turn_events.made_run_on_rnd = true;
    } else if (std.mem.eql(u8, run_server[0], "archives")) {
        generated.turn_events.made_run_on_archives = true;
    }
}

pub fn centralNotRunThisTurnChoices(
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

pub fn installCard(
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
pub fn installCorpCardFromHand(game: *Game, card_index: u8, server_choice: []const u8) !void {
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

pub fn findServerByRunPath(
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

pub fn canonicalRunServer(
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

pub fn isCentralRunServer(run_server: []const []const u8) bool {
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

pub fn threatLevel(g: *const Game) u8 {
    return g.corp_agenda_point + g.runner_agenda_point;
}

fn corpIdentityInstallsAgendasFaceup(g: *const Game) bool {
    for (g.corp_identity.static_abilities) |sa| {
        if (sa.kind == .faceup_agenda_install) return true;
    }
    return false;
}

pub fn currentPendingAccessedServerCard(g: *Game) ?*state.CardInstance {
    const pending = g.pending_access orelse return null;
    if (pending.zone != .corp_server_content) return null;
    if (pending.server_index >= g.corp_servers.items.len) return null;
    const server = &g.corp_servers.items[pending.server_index];
    if (pending.card_index >= server.content.items.len) return null;
    return &server.content.items[pending.card_index];
}

pub fn showTopDownInstallChoices(g: *Game, source_instance_id: u32, installs_done: u8, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
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
        .ability_ref = .{ .source_instance_id = source_instance_id },
        .min_choices = installs_done,
        .on_choice = on_choice,
    };
    g.decision_side = .corp;
    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
}

pub fn beginPeerReviewInstallPrompt(g: *Game, source_instance_id: u32, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
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
        .ability_ref = .{ .source_instance_id = source_instance_id },
        .on_choice = on_choice,
    };
    g.decision_side = .corp;
    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
}

pub fn showKpiChoices(g: *Game, source_instance_id: u32, choices_made: u8, on_choice: ?*const fn (*state.EffectContext, []const u8) anyerror!void) !void {
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
        .ability_ref = .{ .source_instance_id = source_instance_id },
        .min_choices = choices_made,
        .on_choice = on_choice,
    };
    g.decision_side = .corp;
    g.legal_actions = try promptChoiceActions(allocator, .corp, g.corp_prompt_state.?);
}

pub fn sideName(side: state.Side) []const u8 {
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
    // Bling hosting is now optional — resolve the prompt
    if (generated.runner_prompt_state) |ps| {
        if (std.mem.eql(u8, ps.prompt_type, "bling-host")) {
            try applyAction(&generated, .{ .kind = .prompt_choice, .side = .runner, .prompt_type = "bling-host", .choice = stringChoice("Host the top card of your stack on Bling") });
        }
    }
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
