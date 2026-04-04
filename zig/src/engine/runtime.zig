const std = @import("std");
const state = @import("state.zig");
const game = @import("game.zig");

pub const Game = game.Game;
pub const CardSpec = game.CardSpec;
pub const all_cards = game.all_cards;
pub const lookupCardSpecByCode = game.lookupCardSpecByCode;

pub const gameFromEffectContext = game.gameFromEffectContext;
pub const gameFromConstEffectContext = game.gameFromConstEffectContext;
pub const addAdvancementCounter = game.addAdvancementCounter;
pub const addRunnerTag = game.addRunnerTag;
pub const appendDiscardCard = game.appendDiscardCard;
pub const appendHostedCard = game.appendHostedCard;
pub const appendRunnerInstalledCard = game.appendRunnerInstalledCard;
pub const applyBranInstallIceChoice = game.applyBranInstallIceChoice;
pub const applyInstallFromHand = game.applyInstallFromHand;
pub const applyRunFromAbility = game.applyRunFromAbility;
pub const applyRunnerPlayFromHand = game.applyRunnerPlayFromHand;
pub const applySuccessfulRunEffects = game.applySuccessfulRunEffects;
pub const beginPeerReviewInstallPrompt = game.beginPeerReviewInstallPrompt;
pub const beginRandomHqAccess = game.beginRandomHqAccess;
pub const beginRunnerHostedCardPrompt = game.beginRunnerHostedCardPrompt;
pub const beginRunnerInstallFromHand = game.beginRunnerInstallFromHand;
pub const beginRunnerOptionalInstallConfirmPrompt = game.beginRunnerOptionalInstallConfirmPrompt;
pub const beginRunnerOptionalInstallPrompt = game.beginRunnerOptionalInstallPrompt;
pub const beginYesNoPrompt = game.beginYesNoPrompt;
pub const checkManegarmSkunkworks = game.checkManegarmSkunkworks;
pub const completeRunnerInstall = game.completeRunnerInstall;
pub const completeSuccessfulRunWithCorpPriority = game.completeSuccessfulRunWithCorpPriority;
pub const completeUnsuccessfulRun = game.completeUnsuccessfulRun;
pub const continueActionsForRun = game.continueActionsForRun;
pub const continueActionsForRunWithRez = game.continueActionsForRunWithRez;
pub const corpOpeningActionsForState = game.corpOpeningActionsForState;
pub const countFractersInHeap = game.countFractersInHeap;
pub const countInstalledIcebreakers = game.countInstalledIcebreakers;
pub const countPlayableHostedRunnerCards = game.countPlayableHostedRunnerCards;
pub const currentPendingAccessedServerCard = game.currentPendingAccessedServerCard;
pub const centralNotRunThisTurnChoices = game.centralNotRunThisTurnChoices;
pub const drawCards = game.drawCards;
pub const encounterActionsForState = game.encounterActionsForState;
pub const findCardPtrByInstanceId = game.findCardPtrByInstanceId;
pub const findRunnerHardwareByCode = game.findRunnerHardwareByCode;
pub const findRunnerResourceIndex = game.findRunnerResourceIndex;
pub const findServerByRunPath = game.findServerByRunPath;
pub const hasActivePrompt = game.hasActivePrompt;
pub const hostedChoiceIndex = game.hostedChoiceIndex;
pub const hostRandomHqCard = game.hostRandomHqCard;
pub const hostTopRunnerDeckCard = game.hostTopRunnerDeckCard;
pub const installCard = game.installCard;
pub const installChoicesForCard = game.installChoicesForCard;
pub const installCorpCardFromHand = game.installCorpCardFromHand;
pub const installedCardChoices = game.installedCardChoices;
pub const installedNotThisTurnChoices = game.installedNotThisTurnChoices;
pub const is_runner_tagged = game.is_runner_tagged;
pub const isCentralRunServer = game.isCentralRunServer;
pub const moveCorpHandCardToDeckAndShuffle = game.moveCorpHandCardToDeckAndShuffle;
pub const prepareNextAccess = game.prepareNextAccess;
pub const promptChoiceActions = game.promptChoiceActions;
pub const purgeVirusCounters = game.purgeVirusCounters;
pub const removeCardFromHand = game.removeCardFromHand;
pub const removeCardFromHandByInstanceId = game.removeCardFromHandByInstanceId;
pub const logCorpOperationPlay = game.logCorpOperationPlay;
pub const resolveCorpOperation = game.resolveCorpOperation;
pub const removeCorpInstalledFromGame = game.removeCorpInstalledFromGame;
pub const removeHostedCard = game.removeHostedCard;
pub const removeRunnerTags = game.removeRunnerTags;
pub const restorePriorityAfterPrompt = game.restorePriorityAfterPrompt;
pub const resumePendingEffects = game.resumePendingEffects;
pub const returnHostedCardsToHq = game.returnHostedCardsToHq;
pub const runnerHandInstallableByEffect = game.runnerHandInstallableByEffect;
pub const runnerHasActiveRunEvent = game.runnerHasActiveRunEvent;
pub const runnerOpeningActionsForState = game.runnerOpeningActionsForState;
pub const showKpiChoices = game.showKpiChoices;
pub const showTopDownInstallChoices = game.showTopDownInstallChoices;
pub const shuffleDeck = game.shuffleDeck;
pub const spendClicks = game.spendClicks;
pub const spendCredits = game.spendCredits;
pub const stringChoice = game.stringChoice;
pub const threatLevel = game.threatLevel;
pub const trashCorpInstalledSelf = game.trashCorpInstalledSelf;
pub const trashHostedRunnerCards = game.trashHostedRunnerCards;
pub const trashRandomRunnerHandCards = game.trashRandomRunnerHandCards;
pub const updateTerminalState = game.updateTerminalState;
pub const predictive_planogram_choices = game.predictive_planogram_choices;
pub const runner_had_successful_run_last_turn = game.runner_had_successful_run_last_turn;
pub const retribution_choices = game.retribution_choices;
pub const isIcebreaker = game.isIcebreaker;
pub const wildcat_strike_choices = game.wildcat_strike_choices;
pub const hasSubtype = game.hasSubtype;
pub const runTargetChoicesFor = game.runTargetChoicesFor;
pub const canonicalRunServer = game.canonicalRunServer;
pub const trackMadeRun = game.trackMadeRun;
pub const continueActions = game.continueActions;
pub const public_trail_choices = game.public_trail_choices;
pub const canBreakIceType = game.canBreakIceType;
pub const effectiveIceStrength = game.effectiveIceStrength;
pub const effectiveStrength = game.effectiveStrength;
pub const findMutableServerByRunPath = game.findMutableServerByRunPath;
pub const applyCostModifier = game.applyCostModifier;
pub const sumStaticEffects = game.sumStaticEffects;
pub const openBreakSubPrompt = game.openBreakSubPrompt;
pub const fireEvent = game.fireEvent;
pub const isAbilityUsedThisTurn = game.isAbilityUsedThisTurn;
pub const markAbilityUsedThisTurn = game.markAbilityUsedThisTurn;

pub const CardZone = enum(u8) {
    identity,
    runner_resource,
    runner_program,
    runner_hardware,
    corp_server_content,
    corp_ice_hosted,
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
};

pub const PendingEffect = union(enum) {
    event_handler: EventSource,
    on_score_gain_credits: u16,
    on_score_draw_cards: struct { amount: u8, card_code: u32 },
    on_score_give_runner_tag: u8,
    on_score_gain_clicks: u8,
    on_score_rez_ice_free: state.CardInstance,
    on_score_fn: state.CardInstance,
    finish_score: void,
    on_steal_rez_ice_free: state.CardInstance,
    on_steal_give_runner_tag: u8,
    finish_steal: struct { accessed: state.CardInstance, is_central: bool },
    runner_discard_to_deck_prompt: state.CardInstance,
};

const PendingAccessZone = enum(u8) {
    corp_hand,
    corp_deck,
    corp_discard,
    corp_server_content,
};

pub const PendingAccess = struct {
    zone: PendingAccessZone,
    card_index: u8,
    server_index: usize = 0,
};

pub const RunnerInstallContext = struct {
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

pub const DeckLine = struct {
    qty: u8,
    card_code: u32,
};

pub const MutableServer = struct {
    name: []const u8,
    ices: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    content: std.ArrayListUnmanaged(state.CardInstance) = .empty,
    hosted: std.ArrayListUnmanaged(state.CardInstance) = .empty,
};

pub const LogEntry = struct {
    side: state.Side,
    text: []const u8,
    card_code: u32,
};

pub const InstallParams = struct {
    host: ?InstallHost = null,
    facedown: bool = false,
    advanceable: bool = false,
};

pub const InstallHost = struct {
    server_index: usize,
    card_index: usize,
};

pub const EffectContext = anyopaque;

pub const CardSubroutineHandler = *const fn (
    ctx: *EffectContext,
    ice: *state.CardInstance,
    subroutine_index: u8,
) anyerror!void;

pub const Interface = *const struct {
    spendClicks: *const fn (ctx: *EffectContext, side: state.Side, count: u8) anyerror!void,
    spendCredits: *const fn (ctx: *EffectContext, side: state.Side, amount: u16) anyerror!void,
    drawCards: *const fn (ctx: *EffectContext, side: state.Side, amount: u8) anyerror!void,
    addAdvancementCounter: *const fn (ctx: *EffectContext, card: *state.CardInstance, amount: u8) anyerror!void,
    addRunnerTag: *const fn (ctx: *EffectContext, amount: u8) anyerror!void,
    appendDiscardCard: *const fn (ctx: *EffectContext, side: state.Side, card: state.CardInstance) anyerror!void,
    appendHostedCard: *const fn (ctx: *EffectContext, host: *state.CardInstance, card: state.CardInstance) anyerror!void,
    appendRunnerInstalledCard: *const fn (ctx: *EffectContext, card: state.CardInstance) anyerror!void,
    applyInstallFromHand: *const fn (ctx: *EffectContext, card_index: u8, target_server: []const u8, facedown: bool) anyerror!void,
    beginYesNoPrompt: *const fn (ctx: *EffectContext, card: *state.CardInstance, prompt_text: []const u8, on_yes: *const fn (*EffectContext) anyerror!void, on_no: *const fn (*EffectContext) anyerror!void) anyerror!void,
    corpOpeningActionsForState: *const fn (ctx: *EffectContext) anyerror!void,
    encounterActionsForState: *const fn (ctx: *EffectContext, ice: *state.CardInstance) anyerror!void,
    findCardPtrByInstanceId: *const fn (ctx: *EffectContext, instance_id: u32) ?*state.CardInstance,
    fireEvent: *const fn (ctx: *EffectContext, event: state.GameEvent) anyerror!bool,
    getGame: *const fn (ctx: *EffectContext) *anyopaque,
    hasActivePrompt: *const fn (ctx: *EffectContext) bool,
    installCard: *const fn (ctx: *EffectContext, card: state.CardInstance, server_name: []const u8) anyerror!void,
    isCentralRunServer: *const fn (ctx: *EffectContext, server: []const u8) bool,
    isIcebreaker: *const fn (card: *const state.CardInstance) bool,
    is_runner_tagged: *const fn (ctx: *EffectContext) bool,
    promptChoiceActions: *const fn (ctx: *EffectContext, side: state.Side, prompt: state.PromptState) anyerror!void,
    purgeVirusCounters: *const fn (ctx: *EffectContext) anyerror!void,
    removeCardFromHandByInstanceId: *const fn (ctx: *EffectContext, instance_id: u32) anyerror!void,
    resolveCorpOperation: *const fn (ctx: *EffectContext, card_index: u8) anyerror!void,
    restorePriorityAfterPrompt: *const fn (ctx: *EffectContext) anyerror!void,
    runnerOpeningActionsForState: *const fn (ctx: *EffectContext) anyerror!void,
    shuffleDeck: *const fn (ctx: *EffectContext, side: state.Side) anyerror!void,
    stringChoice: *const fn (ctx: *EffectContext, side: state.Side, prompt_text: []const u8, choices: []const []const u8, on_select: *const fn (*EffectContext, []const u8) anyerror!void) anyerror!void,
    trashCorpInstalledSelf: *const fn (ctx: *EffectContext, card_code: u32) anyerror!void,
    trashRandomRunnerHandCards: *const fn (ctx: *EffectContext, count: u8) anyerror!void,
    updateTerminalState: *const fn (ctx: *EffectContext) anyerror!void,
    canBreakIceType: *const fn (card: *const state.CardInstance, ice: *const state.CardInstance) bool,
    effectiveIceStrength: *const fn (ctx: *EffectContext, ice: *state.CardInstance, server: []const u8, modifier: i32) u8,
    effectiveStrength: *const fn (card: *const state.CardInstance) u8,
    findMutableServerByRunPath: *const fn (ctx: *EffectContext, servers: []MutableServer, path: []const u8) anyerror!usize,
    findServerByRunPath: *const fn (servers: []const MutableServer, path: []const u8) anyerror!usize,
    openBreakSubPrompt: *const fn (ctx: *EffectContext, ice: *state.CardInstance, card: state.CardInstance, start_subroutine: u8) anyerror!void,
    sumStaticEffects: *const fn (ctx: *EffectContext, side: state.Side, kind: state.StaticEffectKind, card: *const state.CardInstance) i32,
    applyCostModifier: *const fn (ctx: *EffectContext, base_cost: u16, modifiers: i32) u16,
    lookupCardSpecByCode: *const fn (code: u32) callconv(.Unspecified) ?*anyopaque,
};
