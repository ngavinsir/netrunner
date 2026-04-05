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
};

pub const EventAbility = struct {
    event: GameEvent,
    handler: *const fn (*EffectContext, *CardInstance) anyerror!void,
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

pub const PromptState = struct {
    prompt_type: []const u8,
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
    hosted: []CardInstance = &.{}, // Cards hosted on this card (e.g., trojans on ICE)
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

pub const RunState = struct {
    server: []const []const u8,
    position: u8,
    phase: []const u8,
    encounter_phase: EncounterPhase = .none,
    current_ice_index: ?u8 = null,
    corp_auto_no_action: bool = false,
    no_action: ?Side = null,
    accesses_remaining: u8 = 0,
    accessed_count: u8 = 0,
    accessed_card_indexes: [4]?u8 = .{ null, null, null, null },
    access_card_index: ?u8 = null,
    jack_out_available: bool = false,
    break_subs_selected: u8 = 0,
    break_subs_max: u8 = 0,
    pending_subroutine: ?PendingSubroutine = null,
    source_instance_id: ?u32 = null,
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
    prompt_type: ?[]const u8 = null,
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
