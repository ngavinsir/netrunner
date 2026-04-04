const std = @import("std");

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
    use_identity_ability, // Topan, AU Co.: click ability on identity card
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

pub const RunSuccessEffectKind = enum(u8) {
    none,
    draw_cards,
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


pub const SubroutineKind = enum(u8) {
    none,
    end_the_run,
    do_net_damage,
    do_brain_damage,
    tag_runner,
    trace_tag,
    give_runner_tags,
    runner_loses_credits,
    install_ice_from_hq_archives, // Install an ice from HQ or Archives behind this ice
    corp_gains_credits, // Corp gains N credits
    do_net_damage_conditional_etr, // Do N net damage; if trashed card has odd cost, ETR
    runner_loses_credits_or_etr, // Runner loses N credits (sub1); ETR if runner has ≤ amount credits (sub2)
    do_net_damage_then_jack_out, // Do N net damage, then runner may jack out
    give_tag_or_pay_credits, // Funhouse: give 1 tag unless runner pays N credits
    trash_program_or_etr, // Ballista: trash 1 program, or ETR if no programs
    corp_install_from_hq_archives, // Ansel 1.0: install a card from HQ or Archives
    prevent_steal_trash, // Ansel 1.0: prevent stealing/trashing for rest of run
    conditional_net_damage_if_tagged, // Doomscroll: do N net damage if runner has N+ tags
    conditional_etr_threat, // N-Pot: ETR if threat level >= amount
    net_damage_unless_etr, // Semak-samun: ETR unless runner suffers N net damage
    trash_program_or_resource_or_etr, // Biawak: trash 1 program (or resource) or ETR
    runner_loses_credits_and_net_damage, // Syailendra: runner loses N credits + net damage
    tag_or_pay_credits_etr, // Lamplighter: give 1 tag unless runner pays N; ETR if tagged
    place_advancement_counter, // Syailendra: place 1 advancement counter on this ICE
};

pub const SubroutineSpec = struct {
    kind: SubroutineKind = .none,
    amount: u8 = 0,
    base_trace: u8 = 0,
};

pub const AgendaEffectKind = enum(u8) {
    none,
    gain_credits,
    draw_cards,
    rez_ice_free,
    give_runner_tag, // Tomorrow's Headline: give runner 1 tag on score/steal
    gain_clicks, // Luminal Transubstantiation: gain N clicks on score
};

pub const AgendaEffectSpec = struct {
    kind: AgendaEffectKind = .none,
    amount: u8 = 0,
    hand_size_bonus: u8 = 0, // Superconducting Hub: gain N hand size on score
};



pub const InstallSpec = struct {
    kind: InstallKind = .none,
};

pub const RunnerInstallSpec = struct {
    kind: RunnerInstallKind = .none,
    install_cost_reduction_if_successful_run: u16 = 0, // Carmen: -2 if successful run this turn
    mu_cost: u8 = 1, // Memory units used (default 1 for programs, 0 for non-programs)
};

pub const EffectContext = anyopaque;

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
    // Encounter parameters (used by shared break/pump/bioroid handlers):
    credit_cost: u16 = 0,
    break_count: u8 = 1,
    pump_amount: u8 = 0,
    pump_amount_fn: ?*const fn (*const EffectContext, *const CardInstance) u8 = null,
    pump_can_use: ?*const fn (*const EffectContext, *const CardInstance) bool = null,
    on_break: ?*const fn (*EffectContext, *CardInstance) anyerror!void = null,
    on_pump: ?*const fn (*EffectContext, *CardInstance) anyerror!void = null,
    virus_strength_reduction: u8 = 0,
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
};

pub const StaticAbility = struct {
    kind: StaticAbilityKind,
    value: i8 = 1,
    req: ?*const fn (*const EffectContext, *const CardInstance, ?*const CardInstance) i16 = null,
};

pub const InstalledAbilityCallback = *const fn (*EffectContext, *CardInstance) anyerror!void;


pub const GameEvent = enum(u8) {
    agenda_scored,
    agenda_stolen,
    access,
    runner_gain_tag,
    advance,
    runner_trash_corp_card, // Loup: first trash-on-access
    successful_run, // In-run successful run window before access begins
    successful_run_ends, // Zahya: gain credits on HQ/R&D run end
    run_ends,
    corp_turn_begins,
    corp_end_turn, // Jinteki: Restoring Humanity
    corp_rez_ice, // Barry: install on rez
    operation_played, // Nebula, Zwicky: operation triggers
    runner_turn_begins, // MuslihaT: top-of-deck peek
    run_begins, // Side Hustle, Knickknack: triggers when any run begins
    runner_lose_tag, // Synapse Global: corp installs on tag removal
    corp_install, // BANGUN: faceup install option
    runner_end_turn, // Bling: discard-phase cleanup and similar effects
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
    remote_strength_bonus: u8 = 0, // Palisade: +N strength when protecting a remote
    agenda_points: ?u8 = null,
    advancement_requirement: ?u8 = null,
    install: InstallSpec = .{},
    runner_install: RunnerInstallSpec = .{},
    abilities: []const AbilitySpec = &.{},
    static_abilities: []const StaticAbility = &.{},
    event_abilities: []const EventAbility = &.{},
    // Installed ability data (flattened from InstalledAbilitySpec)
    initial_credit_counters: u16 = 0,
    take_credits_amount: u16 = 0,
    trash_on_empty: bool = false,
    on_install: ?InstalledAbilityCallback = null,
    on_take: ?InstalledAbilityCallback = null,
    on_empty: ?InstalledAbilityCallback = null,
    click_draw_bonus: u8 = 0,
    tags_on_agenda_steal_from_server: u8 = 0, // AMAZE Amusements
    trojan_break_any: bool = false, // Botulus
    trojan_derez_threshold: u8 = 0, // Tranquilizer
    trojan_adds_all_subtypes: bool = false, // Chromatophores
    auto_trash_at_credits: u8 = 0, // Side Hustle
    draw_on_auto_trash: u8 = 0, // Side Hustle
    trash_access_hand_cost: u8 = 0, // Carnivore
    trash_access_self_trash: bool = false, // Gourmand
    trash_access_draw: u8 = 0, // Gourmand
    place_credits_per_turn: bool = false, // Smartware Distributor
    auto_take_credits: bool = false, // Nico Campaign: start of corp turn
    subroutines: []const SubroutineSpec = &.{},
    rezzed: bool = false,
    current_strength: ?u8 = null, // Boosted strength during encounter
    advancement_counter: u8 = 0,
    credit_counter: u16 = 0,
    virus_counter: u16 = 0,
    power_counter: u16 = 0,
    agenda_counter: u8 = 0,
    abilities_used_this_turn: u16 = 0,
    installed_this_turn: bool = false, // Seamless Launch: cannot target cards installed this turn
    used_break_this_run: bool = false, // Mayfly: did this icebreaker break anything this run?
    broken_subroutines: u16 = 0, // bitmask of broken subroutines
    tag_on_rez: u8 = 0, // Ping: give runner N tags when rezzed during a run
    advanceable: bool = false, // Pharos, Clearinghouse: can be advanced (beyond agendas/Urtica)
    advancement_strength_threshold: u8 = 0, // Pharos: str bonus starts at this many counters
    advancement_strength_bonus: u8 = 0, // Pharos: str bonus amount
    hosted: []CardInstance = &.{}, // Cards hosted on this card (e.g., trojans on ICE)
    flipped: bool = false, // Dewi, Nebula: dual-face identity flip state
    seen: bool = false, // BANGUN: faceup-installed agenda
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
    temporary_run_credits: u16 = 0,
    accesses_remaining: u8 = 0,
    accessed_count: u8 = 0,
    accessed_card_indexes: [4]?u8 = .{ null, null, null, null },
    access_card_index: ?u8 = null,
    rez_cost_bonus: u16 = 0,
    successful_run_effect: RunSuccessEffectKind = .none,
    successful_run_draw_cards: u8 = 0,
    access_bonus: u8 = 0,
    jack_out_available: bool = false,
    break_subs_selected: u8 = 0,
    break_subs_max: u8 = 0,
    pending_subroutine: ?PendingSubroutine = null,
    source_card_code: ?u32 = null, // Red Team: track which card initiated the run
    ice_strength_modifier: i8 = 0, // Leech: temporary ICE strength reduction
    did_steal_this_run: bool = false, // AMAZE: track if agenda was stolen during run
    tags_pending_on_steal: u8 = 0, // AMAZE: tags to give if agenda stolen (survives card trash)
    no_steal_or_trash: bool = false, // Ansel 1.0: prevent stealing/trashing for rest of run
    subroutines_fired: u8 = 0, // Ryō: count subroutines that resolved this run
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
    agenda_points_scored_this_turn: u8 = 0, // Neurospike: track AP scored this turn
    // Generic event counters (replaces card-specific flags)
    runner_gain_tag_count: u8 = 0, // How many times runner gained tags this turn
    runner_trash_corp_card_count: u8 = 0, // How many times runner trashed corp cards on access this turn
    successful_run_ends_count: u8 = 0, // How many successful runs ended this turn (for HQ/R&D)
    operation_played_count: u8 = 0, // How many operations played this turn (Zwicky)
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
