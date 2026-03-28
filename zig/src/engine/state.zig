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
};

pub const BasicAction = enum(u8) {
    gain_credit,
    draw_card,
    install_from_grip,
    advance_installed,
    score_agenda,
    purge_viruses,
    run_any_server,
};

pub const CorpPlayKind = enum(u8) {
    none,
    gain_credits,
    advance_installed,
    custom,
    no_op,
};

pub const RunTargetKind = enum(u8) {
    any_runnable,
    hq_and_rnd_only,
    central_only,
};

pub const RunSuccessEffectKind = enum(u8) {
    none,
    draw_cards,
};

pub const RunnerPlayKind = enum(u8) {
    none,
    gain_credits,
    choose_run_target,
    custom,
};

pub const AccessKind = enum(u8) {
    none,
    steal_agenda,
    net_damage_on_access,
    tax_or_etr,
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

pub const InstalledAbilityKind = enum(u8) {
    none,
    take_credits,
    place_credits,
    break_subroutine,
    pump_strength,
    run_central,
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
};

pub const AgendaEffectSpec = struct {
    kind: AgendaEffectKind = .none,
    amount: u8 = 0,
};

// Runner abilities printed on ICE cards (e.g., bioroid break)
pub const RunnerAbilityKind = enum(u8) {
    none,
    bioroid_break, // Lose X clicks to break Y subroutines (e.g., Brân 1.0)
};

pub const RunnerAbilitySpec = struct {
    kind: RunnerAbilityKind = .none,
    click_cost: u8 = 0, // Number of clicks to lose
    break_quantity: u8 = 0, // Number of subroutines to break
};

pub const CorpPlaySpec = struct {
    kind: CorpPlayKind = .none,
    gain_credits: u16 = 0,
    draw_cards: u8 = 0,
    advancement_amount: u8 = 1,
};

pub const RunnerPlaySpec = struct {
    kind: RunnerPlayKind = .none,
    gain_credits: u16 = 0,
    run_credits: u16 = 0,
    draw_cards: u8 = 0,
    lose_clicks: u8 = 0,
    run_target_kind: RunTargetKind = .any_runnable,
    run_rez_cost_bonus: u16 = 0,
    successful_run_effect: RunSuccessEffectKind = .none,
    successful_run_draw_cards: u8 = 0,
    successful_run_access_bonus: u8 = 0,
};

pub const AccessSpec = struct {
    kind: AccessKind = .none,
    corp_credit_cost: u16 = 0,
    base_damage: u8 = 0,
    adds_advancement: bool = false,
    click_cost: u8 = 0,
    credit_cost: u16 = 0,
};

pub const InstallSpec = struct {
    kind: InstallKind = .none,
};

pub const RunnerInstallSpec = struct {
    kind: RunnerInstallKind = .none,
};

pub const InstalledAbilitySpec = struct {
    kind: InstalledAbilityKind = .none,
    click_cost: u8 = 0,
    credit_cost: u16 = 0,
    initial_credit_counters: u16 = 0,
    place_credits_amount: u16 = 0,
    take_credits_amount: u16 = 0,
    break_subroutine_count: u8 = 0,
    pump_strength_amount: u8 = 0,
    trash_on_empty: bool = false,
    once_per_turn: bool = false,
    trashes_after_break: bool = false,
    click_draw_bonus: u8 = 0,
    hq_access_bonus: u8 = 0,
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
    min_choices: u8 = 0,
};

pub const CardInstance = struct {
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
    corp_play: CorpPlaySpec = .{},
    runner_play: RunnerPlaySpec = .{},
    access: AccessSpec = .{},
    install: InstallSpec = .{},
    runner_install: RunnerInstallSpec = .{},
    installed_ability: InstalledAbilitySpec = .{},
    subroutines: []const SubroutineSpec = &.{},
    runner_abilities: []const RunnerAbilitySpec = &.{}, // Runner abilities printed on ICE cards
    rezzed: bool = false,
    advancement_counter: u8 = 0,
    credit_counter: u16 = 0,
    ability_used_this_turn: bool = false,
    broken_subroutines: u16 = 0, // bitmask of broken subroutines
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
    pending_subroutine: ?PendingSubroutine = null,
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
    installed_ability: ?InstalledAbilityKind = null,
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
