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
    start_turn,
    play_from_hand,
    flashback,
    use_ability,
    use_corp_ability,
    use_runner_ability,
    use_subroutine,
    run,
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
};

pub const CardInstance = struct {
    title: []const u8,
    printed_title: ?[]const u8 = null,
    code: ?CardCode = null,
    side: Side,
    card_type: ?[]const u8 = null,
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
};

pub const LegalAction = struct {
    kind: ActionKind,
    side: Side,
    prompt_type: ?[]const u8 = null,
    choice: ?PromptChoice = null,
    server: ?[]const u8 = null,
    ability_index: ?TinyCount = null,
    label: ?[]const u8 = null,
};

pub const GameState = struct {
    format: []const u8,
    seed: Seed,
    rng_seed: ?RngSeed = null,
    active_player: Side,
    turn: TurnNumber,
    end_turn: bool,
    corp: PlayerState,
    runner: PlayerState,
};

pub const SetupSnapshot = struct {
    state: GameState,
    decision_side: Side,
    legal_actions: []const LegalAction,
};
