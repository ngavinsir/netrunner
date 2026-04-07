const std = @import("std");
const engine = @import("game.zig");

pub const Side = enum {
    corp,
    runner,
};

pub const KeepState = enum {
    undecided,
    keep,
    mulligan,
};

pub const ChoiceKind = enum {
    string,
    number,
    keyword,
    card,
    value,
};

pub const ActionKind = enum {
    prompt_choice,
    @"continue",
    start_turn,
    end_turn,
    install_from_hand,
    play_from_hand,
    flashback,
    use_ability,
    use_installed_ability,
    use_corp_ability,
    use_runner_ability,
    use_subroutine,
    jack_out,
    run,
    rez_non_ice,
    rez_ice,
    advance,
    score,
    use_identity_ability,
};

pub const BasicAction = enum(u8) {
    gain_credit,
    draw_card,
    install_from_grip,
    advance_installed,
    score_agenda,
    purge_viruses,
    run_any_server,
    remove_tag,
};

pub const RunTargetKind = enum(u8) {
    any_runnable,
    hq_and_rnd_only,
    central_only,
    archives_only,
    hq_only,
    rd_only,
};

pub const InstallKind = enum(u8) {
    none,
    corp_remote_only,
    corp_server_choice,
};

pub const RunnerInstallKind = enum(u8) {
    none,
    hardware,
    resource,
    program,
};

pub const SubroutineContext = struct {
    server_index: u8,
    ice_index: u8,
    subroutine_index: u8,
    amount: u8 = 0,
    base_trace: u8 = 0,
};

pub const SubroutineSpec = struct {
    resolve: *const fn (*engine.Game, SubroutineContext) anyerror!bool,
    amount: u8 = 0,
    base_trace: u8 = 0,
    label: ?[]const u8 = null,
};

pub const InstallSpec = struct {
    kind: InstallKind = .none,
};

pub const RunnerInstallSpec = struct {
    kind: RunnerInstallKind = .none,
    install_cost_reduction_if_successful_run: u16 = 0,
    mu_cost: u8 = 1, // Memory units used (default 1 for programs, 0 for non-programs)
};

pub const EffectContext = struct {
    game_ptr: *engine.Game,
    event: ?EventPayload = null,

    pub const EventPayload = struct {
        kind: GameEvent,
        source_code: ?u32 = null,
        source_instance_id: ?u32 = null,
        target_instance_id: ?u32 = null,
        server_index: ?u8 = null,
        amount: u16 = 0,
        is_central: bool = false,
    };
};

pub const AbilityRef = struct {
    source_instance_id: u32,
    ability_index: u8 = 0,
};

pub const AbilityCost = struct {
    clicks: u8 = 0,
    credits: u16 = 0,
};

pub const AbilitySpec = struct {
    req: ?*const fn (*const EffectContext, *const CardInstance) bool = null,
    on_use: ?*const fn (*EffectContext, *CardInstance) anyerror!void = null,
    choices_fn: ?*const fn (*EffectContext, *CardInstance) anyerror!void = null,
    cost: ?AbilityCost = null,
    label: ?[]const u8 = null,
    side: ?Side = null,
    allow_opponent_use: bool = false,
    once_per_turn: bool = false,
    is_play: bool = false, // play-from-hand ability (operation/event effect)
    is_flashback: bool = false, // can be played from archives for extra click cost
    // Encounter parameters (used by shared break/pump/bioroid handlers):
    credit_cost: u16 = 0,
    break_count: u8 = 1,
    pump_amount: u8 = 0,
    pump_amount_fn: ?*const fn (*const EffectContext, *const CardInstance) u8 = null,
    pump_can_use: ?*const fn (*const EffectContext, *const CardInstance) bool = null,
    on_break: ?*const fn (*EffectContext, *CardInstance) anyerror!void = null,
    on_pump: ?*const fn (*EffectContext, *CardInstance) anyerror!void = null,
    is_access_ability: bool = false,
};

pub const PayCreditsContext = enum(u8) {
    runner_install, // Can spend when runner installs a card
    runner_trash_corp, // Can spend when runner trashes a corp card
    corp_rez, // Can spend when corp rezzes
};

pub const PayCreditsSpec = struct {
    context: PayCreditsContext,
    /// Optional requirement: checks if this card's credits can be used for this specific payment.
    /// Receives the EffectContext, the pay-credits source card, and optionally the target card.
    /// Returns true if credits can be spent.
    req: ?*const fn (*const EffectContext, *const CardInstance, ?*const CardInstance) bool = null,
};

pub const StaticAbilityKind = enum(u8) {
    mu,
    hand_size,
    rez_cost,
    install_cost,
    break_cost,
    pump_cost,
    self_strength,
    ice_strength,
    hq_access,
    rd_access,
    virus_install_bonus,
    can_advance,
    gain_subtype,
    faceup_agenda_install,
    trash_cost,
};

pub const StaticAbility = struct {
    kind: StaticAbilityKind,
    value: i8 = 1,
    req: ?*const fn (*const EffectContext, *const CardInstance, ?*const CardInstance) i16 = null,
};

pub const GameEvent = enum(u8) {
    agenda_scored,
    agenda_stolen,
    access,
    runner_gain_tag,
    advance,
    runner_trash_corp_card,
    successful_run,
    successful_run_ends,
    run_ends,
    corp_turn_begins,
    corp_end_turn,
    corp_rez_ice,
    operation_played,
    runner_turn_begins,
    run_begins,
    runner_lose_tag,
    corp_install,
    runner_end_turn,
    ice_encountered,
    server_approached,
    card_installed,
    corp_card_runner_trashed, // fires before a corp card is removed; payload.target_instance_id = trashed card
    runner_discarded_to_hand_size, // fires after runner discards the last card to hand size
    corp_dealt_damage, // fires after corp deals damage (net/meat/brain) to runner
    corp_trash_from_hand, // fires when a corp card is trashed from HQ by an effect (not voluntary discard)
};

pub const Priority = struct {
    pub const pre_bypass: u16 = 1;
    pub const corp_damage: u16 = 1;
    pub const force_discard: u16 = 1;
    pub const lose_clicks: u16 = 1;
    pub const gain_clicks: u16 = 2;
    pub const drain_credits: u16 = 4;
    pub const bypass: u16 = 4;
    pub const lose_credits: u16 = 4;
    pub const pre_gain_credits: u16 = 5;
    pub const gain_credits: u16 = 6;
    pub const pre_draw_cards: u16 = 7;
    pub const draw_cards: u16 = 8;
    pub const post_draw_cards: u16 = 9;
    pub const pre_breach: u16 = 9;
    pub const default_priority: u16 = 10;
    pub const trace: u16 = 11;
    pub const corp_lose_tag: u16 = 11;
    pub const last: u16 = 999;
};

pub const EventAbility = struct {
    event: GameEvent,
    handler: *const fn (*EffectContext, *CardInstance) anyerror!void,
    automatic_priority: u16 = 10,
};

pub const CardReference = struct {
    title: ?[]const u8 = null,
    printed_title: ?[]const u8 = null,
    code: ?u32 = null,
    side: ?Side = null,
    index: ?u8 = null,
};

pub const PromptChoice = struct {
    kind: ChoiceKind,
    text: ?[]const u8 = null,
    number: ?u16 = null,
    card: ?CardReference = null,
};

pub const PromptType = enum {
    access_choice,
    access_cleanup,
    advance_installed,
    aggressive_trendsetting,
    anoetic_void,
    ansel_install,
    au_co_peek,
    above_the_law_trash,
    ballista_trash,
    bangun_bluff,
    bangun_faceup,
    barry_install,
    bigger_picture,
    bigger_picture_tags,
    bling_host,
    break_sub,
    byte_ambush,
    cacophony_sabotage,
    clearinghouse_trash,
    corp_free_install_card,
    corp_free_install_server,
    discard,
    fransofia_bypass,
    funhouse_encounter,
    gamedragon_host,
    hansei_trash,
    hq_access,
    humanoid_install_card,
    humanoid_install_server,
    humanoid_operation,
    idiosyncresis_trash,
    install_destination,
    ip_enforcement_tags,
    jack_out,
    knickknack_trash,
    kpi_advance,
    kpi_choose,
    kpi_ice_choose,
    kpi_ice_server,
    kpi_shuffle,
    lie_low,
    lie_low_tags,
    longevity_serum_shuffle,
    longevity_serum_trash,
    maglectric_derez,
    magdalene_install,
    malapert_search,
    manegarm_tax,
    mercia_install_ice,
    mercia_install_server,
    mitra_ice_swap,
    mitra_swap,
    mu_overflow,
    mulligan,
    muslihat_reveal,
    net_damage_on_access,
    net_damage_or_etr,
    other,
    peek_rd_trash_one,
    peer_review_install,
    peer_review_private,
    peer_review_server,
    phat_net_damage,
    plutus_rez_cost,
    plutus_transaction,
    plutus_trash_hq,
    poetri_install,
    poetri_rd_install,
    poetri_server,
    precision_design_archive,
    pt_untaian_advance,
    reality_plus,
    retribution_trash,
    run,
    run_central,
    run_target,
    runner_bonus_install,
    runner_bonus_install_confirm,
    runner_discard_to_deck,
    runner_host_confirm,
    runner_host_from_grip,
    runner_host_mode,
    runner_hosted_card,
    runner_hosted_install,
    sabotage,
    score_agenda,
    scrounge_install,
    seamless_advance,
    send_message_rez,
    send_message_rez_score,
    spin_doctor_shuffle,
    sprint_shuffle,
    tao_swap_ice,
    topan_install,
    top_down_card,
    top_down_server,
    touch_ups_advance,
    touch_ups_shuffle,
    touch_ups_type,
    trace,
    trojan_host,
    waiting,
    zahya_gain,
    zwicky_draw,

    pub fn toStr(self: PromptType) []const u8 {
        return @tagName(self);
    }

    pub fn fromStr(s: []const u8) ?PromptType {
        // Map kebab-case strings from oracle/JSON to enum values
        const map = .{
            .{ "access-choice", .access_choice },
            .{ "access-cleanup", .access_cleanup },
            .{ "advance-installed", .advance_installed },
            .{ "aggressive-trendsetting", .aggressive_trendsetting },
            .{ "anoetic-void", .anoetic_void },
            .{ "ansel-install", .ansel_install },
            .{ "au-co-peek", .au_co_peek },
            .{ "above-the-law-trash", .above_the_law_trash },
            .{ "ballista-trash", .ballista_trash },
            .{ "bangun-bluff", .bangun_bluff },
            .{ "bangun-faceup", .bangun_faceup },
            .{ "barry-install", .barry_install },
            .{ "bigger-picture", .bigger_picture },
            .{ "bigger-picture-tags", .bigger_picture_tags },
            .{ "bling-host", .bling_host },
            .{ "break-sub", .break_sub },
            .{ "byte-ambush", .byte_ambush },
            .{ "cacophony-sabotage", .cacophony_sabotage },
            .{ "clearinghouse-trash", .clearinghouse_trash },
            .{ "corp-free-install-card", .corp_free_install_card },
            .{ "corp-free-install-server", .corp_free_install_server },
            .{ "discard", .discard },
            .{ "fransofia-bypass", .fransofia_bypass },
            .{ "funhouse-encounter", .funhouse_encounter },
            .{ "gamedragon-host", .gamedragon_host },
            .{ "hansei-trash", .hansei_trash },
            .{ "hq-access", .hq_access },
            .{ "humanoid-install-card", .humanoid_install_card },
            .{ "humanoid-install-server", .humanoid_install_server },
            .{ "humanoid-operation", .humanoid_operation },
            .{ "idiosyncresis-trash", .idiosyncresis_trash },
            .{ "install-destination", .install_destination },
            .{ "ip-enforcement-tags", .ip_enforcement_tags },
            .{ "jack-out", .jack_out },
            .{ "knickknack-trash", .knickknack_trash },
            .{ "kpi-advance", .kpi_advance },
            .{ "kpi-choose", .kpi_choose },
            .{ "kpi-ice-choose", .kpi_ice_choose },
            .{ "kpi-ice-server", .kpi_ice_server },
            .{ "kpi-shuffle", .kpi_shuffle },
            .{ "lie-low", .lie_low },
            .{ "lie-low-tags", .lie_low_tags },
            .{ "longevity-serum-shuffle", .longevity_serum_shuffle },
            .{ "longevity-serum-trash", .longevity_serum_trash },
            .{ "maglectric-derez", .maglectric_derez },
            .{ "magdalene-install", .magdalene_install },
            .{ "malapert-search", .malapert_search },
            .{ "manegarm-tax", .manegarm_tax },
            .{ "mercia-install-ice", .mercia_install_ice },
            .{ "mercia-install-server", .mercia_install_server },
            .{ "mitra-ice-swap", .mitra_ice_swap },
            .{ "mitra-swap", .mitra_swap },
            .{ "mu-overflow", .mu_overflow },
            .{ "mulligan", .mulligan },
            .{ "muslihat-reveal", .muslihat_reveal },
            .{ "net-damage-on-access", .net_damage_on_access },
            .{ "net-damage-or-etr", .net_damage_or_etr },
            .{ "other", .other },
            .{ "peek-rd-trash-one", .peek_rd_trash_one },
            .{ "peer-review-install", .peer_review_install },
            .{ "peer-review-private", .peer_review_private },
            .{ "peer-review-server", .peer_review_server },
            .{ "phat-net-damage", .phat_net_damage },
            .{ "plutus-rez-cost", .plutus_rez_cost },
            .{ "plutus-transaction", .plutus_transaction },
            .{ "plutus-trash-hq", .plutus_trash_hq },
            .{ "poetri-install", .poetri_install },
            .{ "poetri-rd-install", .poetri_rd_install },
            .{ "poetri-server", .poetri_server },
            .{ "precision-design-archive", .precision_design_archive },
            .{ "pt-untaian-advance", .pt_untaian_advance },
            .{ "reality-plus", .reality_plus },
            .{ "retribution-trash", .retribution_trash },
            .{ "run", .run },
            .{ "run-central", .run_central },
            .{ "run-target", .run_target },
            .{ "runner-bonus-install", .runner_bonus_install },
            .{ "runner-bonus-install-confirm", .runner_bonus_install_confirm },
            .{ "runner-discard-to-deck", .runner_discard_to_deck },
            .{ "runner-host-confirm", .runner_host_confirm },
            .{ "runner-host-from-grip", .runner_host_from_grip },
            .{ "runner-host-mode", .runner_host_mode },
            .{ "runner-hosted-card", .runner_hosted_card },
            .{ "runner-hosted-install", .runner_hosted_install },
            .{ "sabotage", .sabotage },
            .{ "score-agenda", .score_agenda },
            .{ "scrounge-install", .scrounge_install },
            .{ "seamless-advance", .seamless_advance },
            .{ "send-message-rez", .send_message_rez },
            .{ "send-message-rez-score", .send_message_rez_score },
            .{ "spin-doctor-shuffle", .spin_doctor_shuffle },
            .{ "sprint-shuffle", .sprint_shuffle },
            .{ "tao-swap-ice", .tao_swap_ice },
            .{ "topan-install", .topan_install },
            .{ "top-down-card", .top_down_card },
            .{ "top-down-server", .top_down_server },
            .{ "touch-ups-advance", .touch_ups_advance },
            .{ "touch-ups-shuffle", .touch_ups_shuffle },
            .{ "touch-ups-type", .touch_ups_type },
            .{ "trace", .trace },
            .{ "trojan-host", .trojan_host },
            .{ "waiting", .waiting },
            .{ "zahya-gain", .zahya_gain },
            .{ "zwicky-draw", .zwicky_draw },
        };
        inline for (map) |entry| {
            if (std.mem.eql(u8, s, entry[0])) return entry[1];
        }
        return null;
    }
};

pub const PromptState = struct {
    prompt_type: PromptType,
    choices: []const PromptChoice,
    source_card: ?CardInstance = null,
    ability_ref: ?AbilityRef = null,
    on_choice: ?*const fn (*EffectContext, []const u8) anyerror!void = null,
    min_choices: u8 = 0,
};

pub const CardInstance = struct {
    instance_id: u32 = 0,
    title: []const u8,
    printed_title: ?[]const u8 = null,
    code: ?u32 = null,
    side: Side,
    card_type: ?[]const u8 = null,
    subtypes: []const []const u8 = &.{},
    cost: ?u16 = null,
    strength: ?u8 = null,
    agenda_points: ?u8 = null,
    advancement_requirement: ?u8 = null,
    install: InstallSpec = .{},
    runner_install: RunnerInstallSpec = .{},
    abilities: []const AbilitySpec = &.{},
    static_abilities: []const StaticAbility = &.{},
    event_abilities: []const EventAbility = &.{},
    pay_credits: ?PayCreditsSpec = null,
    // Installed ability data
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
    subroutines: []const SubroutineSpec = &.{},
    rezzed: bool = false,
    current_strength: ?u8 = null, // Boosted strength during encounter
    advancement_counter: u8 = 0,
    credit_counter: u16 = 0,
    virus_counter: u16 = 0,
    power_counter: u16 = 0,
    agenda_counter: u8 = 0,
    abilities_used_this_turn: u16 = 0,
    installed_this_turn: bool = false,
    broken_subroutines: u16 = 0, // bitmask of broken subroutines
    hosted: std.ArrayListUnmanaged(CardInstance) = .empty, // Cards hosted on this card (e.g., trojans on ICE)
    flipped: bool = false,
    seen: bool = false,
};

pub const ServerState = struct {
    ices: []const CardInstance = &.{},
    content: []const CardInstance = &.{},
};

pub const ServerSlot = struct {
    name: []const u8,
    state: ServerState,
};

pub const PendingInstall = struct {
    card: CardInstance,
    card_index: u8,
    runner_install_cost: u16 = 0,
    runner_spend_click: bool = true,
};

pub const FloatingEffectKind = enum(u8) {
    ice_strength_modifier,
    prevent_steal_or_trash,
    run_credits,
    access_bonus,
    rez_cost_bonus,
    successful_run_draw,
    prevent_score,
    tags_on_steal,
    icebreaker_broke,
    subroutine_resolved,
    agenda_points_scored,
    trash_cost,
};

pub const FloatingEffectDuration = enum(u8) {
    end_of_encounter,
    end_of_run,
    end_of_turn,
};

pub const FloatingEffect = struct {
    kind: FloatingEffectKind,
    duration: FloatingEffectDuration,
    value: i16 = 0,
    source_code: ?u32 = null,
    target_server: ?u8 = null, // Server index for server-scoped effects (e.g. Mahkota lingering trash cost)
};

pub const EncounterPhase = enum(u8) {
    none,
    approach,
    encounter,
    movement,
};

pub const PendingSubroutine = struct {
    server_index: u8,
    ice_index: u8,
    subroutine_index: u8,
};

pub const RunPhase = enum {
    initiation,
    approach_ice,
    encounter_ice,
    movement,
    success,

    pub fn toStr(self: RunPhase) []const u8 {
        return switch (self) {
            .initiation => "initiation",
            .approach_ice => "approach-ice",
            .encounter_ice => "encounter-ice",
            .movement => "movement",
            .success => "success",
        };
    }

    pub fn fromStr(s: []const u8) ?RunPhase {
        if (std.mem.eql(u8, s, "initiation")) return .initiation;
        if (std.mem.eql(u8, s, "approach-ice")) return .approach_ice;
        if (std.mem.eql(u8, s, "encounter-ice")) return .encounter_ice;
        if (std.mem.eql(u8, s, "movement")) return .movement;
        if (std.mem.eql(u8, s, "success")) return .success;
        return null;
    }
};

pub const ServerPath = union(enum) {
    hq,
    rnd,
    archives,
    remote: u8,

    pub fn matchesName(self: ServerPath, name: []const u8) bool {
        return switch (self) {
            .hq => std.mem.eql(u8, name, "hq"),
            .rnd => std.mem.eql(u8, name, "rnd"),
            .archives => std.mem.eql(u8, name, "archives"),
            .remote => |n| blk: {
                if (!std.mem.startsWith(u8, name, "remote")) break :blk false;
                const num = std.fmt.parseInt(u8, name["remote".len..], 10) catch break :blk false;
                break :blk num == n;
            },
        };
    }

    pub fn fromDisplayName(name: []const u8) !ServerPath {
        if (std.mem.eql(u8, name, "Archives")) return .archives;
        if (std.mem.eql(u8, name, "HQ")) return .hq;
        if (std.mem.eql(u8, name, "R&D")) return .rnd;
        if (std.mem.startsWith(u8, name, "Server ")) {
            const num = std.fmt.parseInt(u8, name["Server ".len..], 10) catch return error.UnsupportedServer;
            return .{ .remote = num };
        }
        return error.UnsupportedServer;
    }

    pub fn fromInternalName(name: []const u8) !ServerPath {
        if (std.mem.eql(u8, name, "hq")) return .hq;
        if (std.mem.eql(u8, name, "rnd")) return .rnd;
        if (std.mem.eql(u8, name, "archives")) return .archives;
        if (std.mem.startsWith(u8, name, "remote")) {
            const num = std.fmt.parseInt(u8, name["remote".len..], 10) catch return error.UnsupportedServer;
            return .{ .remote = num };
        }
        return error.UnsupportedServer;
    }

    pub fn isCentral(self: ServerPath) bool {
        return switch (self) {
            .hq, .rnd, .archives => true,
            .remote => false,
        };
    }

    pub fn eql(self: ServerPath, other: ServerPath) bool {
        return switch (self) {
            .hq => other == .hq,
            .rnd => other == .rnd,
            .archives => other == .archives,
            .remote => |n| switch (other) {
                .remote => |m| n == m,
                else => false,
            },
        };
    }
};

pub const RunState = struct {
    server: ServerPath,
    position: u8,
    phase: RunPhase,
    encounter_phase: EncounterPhase = .none,
    current_ice_index: ?u8 = null,
    corp_auto_no_action: bool = false,
    no_action: ?Side = null,
    accesses_remaining: u8 = 0,
    accessed_count: u8 = 0,
    accessed_card_indexes: [4]?u8 = .{ null, null, null, null },
    access_card_index: ?u8 = null,
    bypass: bool = false,
    jack_out_available: bool = false,
    break_subs_selected: u8 = 0,
    break_subs_max: u8 = 0,
    pending_subroutine: ?PendingSubroutine = null,
    source_instance_id: ?u32 = null,
    source_event_abilities: []const EventAbility = &.{},
};

pub const HandSize = struct {
    base: u8,
    total: u8,
};

pub const BadPublicity = struct {
    base: u8,
    additional: u8,
};

pub const TagState = struct {
    base: u8,
    total: u8,
    is_tagged: bool,
};

pub const MemoryState = struct {
    base: u8,
    available: u8,
    used: u8,
    caissa_available: u8 = 0,
    caissa_used: u8 = 0,
    virus_available: u8 = 0,
    virus_used: u8 = 0,
};

pub const PlayerState = struct {
    identity: CardInstance,
    basic_action_card: CardInstance,
    click: u8,
    click_per_turn: u8,
    credit: u16,
    agenda_point: u8,
    agenda_point_req: u8,
    hand_size: HandSize,
    bad_publicity: ?BadPublicity = null,
    run_credit: u16 = 0,
    link: u8 = 0,
    tag: ?TagState = null,
    memory: ?MemoryState = null,
    brain_damage: u8 = 0,
    keep: KeepState,
    prompt_state: ?PromptState,
    deck: []const CardInstance,
    hand: []const CardInstance,
    discard: []const CardInstance,
    scored: []const CardInstance = &.{},
    rig_hardware: []const CardInstance = &.{},
    rig_program: []const CardInstance = &.{},
    rig_resources: []const CardInstance = &.{},
    servers: []const ServerSlot = &.{},
};

pub const TurnEvents = struct {
    runner_click_draws: u8 = 0,
    runner_hq_breaches: u8 = 0,
    made_run_on_hq: bool = false,
    made_run_on_rnd: bool = false,
    made_run_on_archives: bool = false,
    programs_installed_this_turn: u8 = 0,
    // Generic event counters
    runner_gain_tag_count: u8 = 0, // How many times runner gained tags this turn
    runner_trash_corp_card_count: u8 = 0, // How many times runner trashed corp cards on access this turn
    successful_run_ends_count: u8 = 0, // How many successful runs ended this turn (for HQ/R&D)
    operation_played_count: u8 = 0,
};

pub const LegalAction = struct {
    kind: ActionKind,
    side: Side,
    prompt_type: ?PromptType = null,
    choice: ?PromptChoice = null,
    server: ?[]const u8 = null,
    card_index: ?u8 = null,
    card_title: ?[]const u8 = null,
    basic_action: ?BasicAction = null,
    ability_ref: ?AbilityRef = null,
    label: ?[]const u8 = null,
};

pub const GameState = struct {
    format: []const u8,
    seed: u64,
    rng_seed: ?i64 = null,
    active_player: Side,
    turn: u16,
    end_turn: bool,
    run: ?RunState = null,
    runner_successful_run_last_turn: bool = false,
    runner_successful_run_this_turn: bool = false,
    turn_events: TurnEvents = .{},
    game_over: bool = false,
    winner: ?Side = null,
    pending_install: ?PendingInstall = null,
    corp: PlayerState,
    runner: PlayerState,
};

pub const GameSnapshot = struct {
    state: GameState,
    decision_side: Side,
    legal_actions: []const LegalAction,
};
