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
    corp_pay_etr, // Anoetic Void: corp pays credits + trashes from HQ → ETR
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
    run_rd, // Conduit: click to run R&D
    start_of_turn_credits, // Nico Campaign: auto-take credits at start of corp turn
    trash_for_virus_credits, // Fermenter: click + trash to gain N credits per virus counter
    trash_for_damage, // Clearinghouse: click + trash to do 1 meat damage per advancement counter
    remove_from_game_shuffle, // Spin Doctor: remove from game, shuffle up to 2 from Archives into R&D
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
    not_installed_this_turn: bool = false, // Seamless Launch: exclude cards installed this turn
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
    install_cost_reduction_if_successful_run: u16 = 0, // Carmen: -2 if successful run this turn
    mu_cost: u8 = 1, // Memory units used (default 1 for programs, 0 for non-programs)
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
    pump_is_variable: bool = false, // Unity: pump = number of installed icebreakers
    trash_on_empty: bool = false,
    once_per_turn: bool = false,
    trashes_after_break: bool = false, // Mayfly: trash self at end of run (not immediately)
    click_draw_bonus: u8 = 0,
    hq_access_bonus: u8 = 0,
    draw_on_empty: u8 = 0, // Nico Campaign: draw N cards when trashed due to empty
    on_successful_run_place_credits: u8 = 0, // Pennyshaver: place N credits on successful run
    takes_all_credits: bool = false, // Pennyshaver: click ability takes all hosted credits + 1
    mu_provided: u8 = 0, // DZMZ Optimizer: provides extra MU
    first_program_install_discount: u16 = 0, // DZMZ Optimizer: first program install each turn costs N less
    virus_on_successful_central: bool = false, // Leech: place virus counter on successful central run
    virus_on_successful_rd: bool = false, // Conduit: place virus counter on successful R&D run
    rd_access_bonus_per_virus: bool = false, // Conduit: RD access bonus = virus counters
    virus_ice_strength_reduction: u8 = 0, // Leech: spend 1 virus for -N ICE strength
    tags_on_agenda_steal_from_server: u8 = 0, // AMAZE Amusements: give N tags if agenda stolen from server
    strength_per_icebreaker: bool = false, // Echelon: +1 strength per installed icebreaker
    break_cost_reduction_if_successful_run: u16 = 0, // Marjanah: -1 break cost if successful run this turn
    hand_size_bonus: u8 = 0, // T400 Memory Diamond: +N max hand size
    virus_on_install: bool = false, // Fermenter, Botulus, Tranquilizer: place 1 virus on install
    virus_on_turn_start: bool = false, // Fermenter, Botulus, Tranquilizer: place 1 virus at start of turn
    trash_for_virus_credits: u8 = 0, // Fermenter: gain N credits per virus counter on click+trash
    bonus_virus_on_install: u8 = 0, // Cookbook: place N extra virus counters when installing virus programs
    is_console: bool = false, // Console hardware: only one allowed
    is_trojan: bool = false, // Botulus, Tranquilizer: install on ICE
    trojan_break_any: bool = false, // Botulus: spend virus counter to break any subroutine
    trojan_derez_threshold: u8 = 0, // Tranquilizer: derez host ICE at N+ virus counters
};

pub const GameEvent = enum(u8) {
    agenda_scored,
    agenda_stolen,
    runner_gain_tag,
    advance,
    runner_trash_corp_card, // Loup: first trash-on-access
    successful_run_ends, // Zahya: gain credits on HQ/R&D run end
    corp_end_turn, // Jinteki: Restoring Humanity
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
    remote_strength_bonus: u8 = 0, // Palisade: +N strength when protecting a remote
    agenda_points: ?u8 = null,
    advancement_requirement: ?u8 = null,
    corp_play: CorpPlaySpec = .{},
    runner_play: RunnerPlaySpec = .{},
    access: AccessSpec = .{},
    install: InstallSpec = .{},
    runner_install: RunnerInstallSpec = .{},
    installed_ability: InstalledAbilitySpec = .{},
    pump_ability: InstalledAbilitySpec = .{},
    subroutines: []const SubroutineSpec = &.{},
    runner_abilities: []const RunnerAbilitySpec = &.{}, // Runner abilities printed on ICE cards
    rezzed: bool = false,
    current_strength: ?u8 = null, // Boosted strength during encounter
    advancement_counter: u8 = 0,
    credit_counter: u16 = 0,
    virus_counter: u16 = 0,
    ability_used_this_turn: bool = false,
    installed_this_turn: bool = false, // Seamless Launch: cannot target cards installed this turn
    used_break_this_run: bool = false, // Mayfly: did this icebreaker break anything this run?
    broken_subroutines: u16 = 0, // bitmask of broken subroutines
    tag_on_rez: u8 = 0, // Ping: give runner N tags when rezzed during a run
    advanceable: bool = false, // Pharos, Clearinghouse: can be advanced (beyond agendas/Urtica)
    advancement_strength_threshold: u8 = 0, // Pharos: str bonus starts at this many counters
    advancement_strength_bonus: u8 = 0, // Pharos: str bonus amount
    hosted_on_ice_server: ?u8 = null, // Trojan: server index of host ICE
    hosted_on_ice_index: ?u8 = null, // Trojan: ice index within server (from outermost)
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
