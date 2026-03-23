pub const Seed = u64;
pub const RngSeed = i64;
pub const CardCode = u32;
pub const Count = u16;
pub const TinyCount = u8;
pub const TurnNumber = u16;

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
    play_from_hand,
    flashback,
    use_ability,
    use_corp_ability,
    use_runner_ability,
    use_subroutine,
    run,
};

pub const BasicAction = enum(u8) {
    gain_credit,
    draw_card,
    advance_installed,
    purge_viruses,
    run_any_server,
};

pub const CorpPlayKind = enum(u8) {
    none,
    gain_credits,
    no_op,
};

pub const RunTargetKind = enum(u8) {
    any_runnable,
    hq_and_rnd_only,
};

pub const RunSuccessEffectKind = enum(u8) {
    none,
    draw_cards,
};

pub const RunnerPlayKind = enum(u8) {
    none,
    gain_credits,
    choose_run_target,
};

pub const AccessKind = enum(u8) {
    none,
    steal_agenda,
};

pub const InstallKind = enum(u8) {
    none,
    corp_remote_only,
    corp_server_choice,
};

pub const CorpPlaySpec = struct {
    kind: CorpPlayKind = .none,
    gain_credits: Count = 0,
    draw_cards: TinyCount = 0,
};

pub const RunnerPlaySpec = struct {
    kind: RunnerPlayKind = .none,
    gain_credits: Count = 0,
    run_credits: Count = 0,
    draw_cards: TinyCount = 0,
    lose_clicks: TinyCount = 0,
    run_target_kind: RunTargetKind = .any_runnable,
    run_rez_cost_bonus: Count = 0,
    successful_run_effect: RunSuccessEffectKind = .none,
    successful_run_draw_cards: TinyCount = 0,
    successful_run_access_bonus: TinyCount = 0,
};

pub const AccessSpec = struct {
    kind: AccessKind = .none,
};

pub const InstallSpec = struct {
    kind: InstallKind = .none,
};

pub const CardReference = struct {
    title: ?[]const u8 = null,
    printed_title: ?[]const u8 = null,
    code: ?CardCode = null,
    side: ?Side = null,
};

pub const PromptChoice = struct {
    kind: ChoiceKind,
    text: ?[]const u8 = null,
    number: ?Count = null,
    card: ?CardReference = null,
};

pub const PromptState = struct {
    prompt_type: []const u8,
    choices: []const PromptChoice,
    source_card: ?CardInstance = null,
};

pub const CardInstance = struct {
    title: []const u8,
    printed_title: ?[]const u8 = null,
    code: ?CardCode = null,
    side: Side,
    card_type: ?[]const u8 = null,
    cost: ?Count = null,
    agenda_points: ?TinyCount = null,
    corp_play: CorpPlaySpec = .{},
    runner_play: RunnerPlaySpec = .{},
    access: AccessSpec = .{},
    install: InstallSpec = .{},
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
    card_index: TinyCount,
};

pub const RunState = struct {
    server: []const []const u8,
    position: TinyCount,
    phase: []const u8,
    corp_auto_no_action: bool = false,
    no_action: ?Side = null,
    temporary_run_credits: Count = 0,
    accesses_remaining: TinyCount = 0,
    accessed_count: TinyCount = 0,
    accessed_card_indexes: [4]?TinyCount = .{ null, null, null, null },
    access_card_index: ?TinyCount = null,
    rez_cost_bonus: Count = 0,
    successful_run_effect: RunSuccessEffectKind = .none,
    successful_run_draw_cards: TinyCount = 0,
    access_bonus: TinyCount = 0,
};

pub const HandSize = struct {
    base: TinyCount,
    total: TinyCount,
};

pub const BadPublicity = struct {
    base: TinyCount,
    additional: TinyCount,
};

pub const TagState = struct {
    base: TinyCount,
    total: TinyCount,
    is_tagged: bool,
};

pub const MemoryState = struct {
    base: TinyCount,
    available: TinyCount,
    used: TinyCount,
    caissa_available: TinyCount = 0,
    caissa_used: TinyCount = 0,
    virus_available: TinyCount = 0,
    virus_used: TinyCount = 0,
};

pub const PlayerState = struct {
    identity: CardInstance,
    basic_action_card: CardInstance,
    click: TinyCount,
    click_per_turn: TinyCount,
    credit: Count,
    agenda_point: TinyCount,
    agenda_point_req: TinyCount,
    hand_size: HandSize,
    bad_publicity: ?BadPublicity = null,
    run_credit: Count = 0,
    link: TinyCount = 0,
    tag: ?TagState = null,
    memory: ?MemoryState = null,
    brain_damage: TinyCount = 0,
    keep: KeepState,
    prompt_state: ?PromptState,
    deck: []const CardInstance,
    hand: []const CardInstance,
    discard: []const CardInstance,
    servers: []const ServerSlot = &.{},
};

pub const LegalAction = struct {
    kind: ActionKind,
    side: Side,
    prompt_type: ?[]const u8 = null,
    choice: ?PromptChoice = null,
    server: ?[]const u8 = null,
    card_index: ?TinyCount = null,
    card_title: ?[]const u8 = null,
    basic_action: ?BasicAction = null,
    label: ?[]const u8 = null,
};

pub const GameState = struct {
    format: []const u8,
    seed: Seed,
    rng_seed: ?RngSeed = null,
    active_player: Side,
    turn: TurnNumber,
    end_turn: bool,
    run: ?RunState = null,
    pending_install: ?PendingInstall = null,
    corp: PlayerState,
    runner: PlayerState,
};

pub const GameSnapshot = struct {
    state: GameState,
    decision_side: Side,
    legal_actions: []const LegalAction,
};
