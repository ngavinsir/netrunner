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
pub const addFloatingEffect = game.addFloatingEffect;
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
pub const findRunnerResourceIndex = game.findRunnerResourceIndex;
pub const findServerByRunPath = game.findServerByRunPath;
pub const hasActivePrompt = game.hasActivePrompt;
pub const hasFloatingEffectFromSource = game.hasFloatingEffectFromSource;
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
pub const sumFloatingEffects = game.sumFloatingEffects;
pub const sumStaticEffects = game.sumStaticEffects;
pub const openBreakSubPrompt = game.openBreakSubPrompt;
pub const fireEvent = game.fireEvent;
pub const fireEventWith = game.fireEventWith;
pub const isAbilityUsedThisTurn = game.isAbilityUsedThisTurn;
pub const markAbilityUsedThisTurn = game.markAbilityUsedThisTurn;
pub const beginByteAmbushPrompt = game.beginByteAmbushPrompt;
pub const beginPhatGioanDamagePrompt = game.beginPhatGioanDamagePrompt;
pub const beginSabotagePrompt = game.beginSabotagePrompt;
pub const bypassCurrentIce = game.bypassCurrentIce;
pub const beginStartTurnSequence = game.beginStartTurnSequence;
pub const beginPeekRdTopPrompt = game.beginPeekRdTopPrompt;
pub const completeRunnerEndTurn = game.completeRunnerEndTurn;
pub const serverHasBioroidIce = game.serverHasBioroidIce;
pub const continueServerApproach = game.continueServerApproach;


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
};

pub const InstallHost = struct {
    server_index: usize,
    card_index: usize,
};

