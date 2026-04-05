# Zig Card Genericization Implementation Plan

This document is an execution handoff for finishing the card-logic migration in the Zig engine.

The goal is not "improve the architecture a bit". The goal is:

- all card logic is self-contained in [catalog.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/catalog.zig)
- [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig) contains only generic engine flow and generic dispatch
- [state.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/state.zig) contains only generic rule types and generic runtime state
- there are no remaining card-specific fields, card-specific enums, or card-specific runtime branches in engine code

This plan is intentionally explicit. The implementer should not improvise architecture beyond what is written here.

## Scope

- Card pool: the current Zig catalog only
- Source of truth for behavior: the Clojure engine card definitions and parity oracle
- Out of scope:
  - unrelated TUI work
  - unrelated API work
  - changing decklists or card pool scope
  - adding new cards before finishing the migration

## Hard Rules

- Do not add any new field, enum tag, or runtime flag that is specific to one card or a tiny card cluster.
- Do not move a special-case field from one struct to another and call that "migrated".
- Do not add new card-code checks or title checks to [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig).
- Do not add wrapper layers that forward new generic APIs back into legacy hook fields.
- All card handlers must stay inline on the card definition using anonymous struct functions.
- If a mechanic appears to need a new primitive, first express it as one of:
  - `AbilitySpec`
  - `EventAbility`
  - `StaticAbility`
  - `FloatingEffect`
  - typed event payload
- Keep the suite green after each migration slice. Do not do a giant unverified rewrite.

## Current Repo Truth

The repo already contains partial migration scaffolding. Do not undo it. Finish it.

Already present:

- [catalog.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/catalog.zig)
- `AbilitySpec`
- `AbilityRef`
- `PromptState.on_choice`
- `SubroutineSpec.resolve`
- `FloatingEffect` types

Not actually finished:

- `AbilityRef` is not the canonical action target yet
- `FloatingEffect` exists as a type only and is not wired into runtime state
- card prompts still mostly route through legacy `on_prompt_choice`
- legacy play/access/install/subroutine systems are still active
- multiple special card fields were moved into `CardSpec` instead of being deleted

Important current flaw:

- the repo already has `instance_id` and `AbilityRef.source_instance_id`
- that does not mean the identity migration is complete
- the real failure mode is a dual-routing implementation:
  - the type carries stable identity
  - but runtime still resolves the live card through old context such as `card_index`, `server`, copied `source_card`, `code`, or `title`
- the final implementation must make stable per-instance identity the only authoritative way to recover a live source card for card-owned ability execution and prompt continuation

## Definition Of Done

The migration is only done when all of the following are true:

- card logic exists only in [catalog.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/catalog.zig)
- runtime card execution is driven only by:
  - `abilities`
  - `event_abilities`
  - `static_abilities`
  - `subroutines`
- there is no dependency on any legacy hook surface:
  - `on_play`
  - `on_prompt_choice`
  - `can_play`
  - `on_score_fn`
  - `on_rez`
  - `on_encounter`
  - `card_subroutine_handler`
- there is no dependency on any legacy card-specific field or legacy enum listed in the acceptance section below
- every current Zig catalog card has smoke parity coverage
- every branchful card has explicit branch coverage
- `zig/src/engine/game.zig`, `zig/src/engine/state.zig`, and `zig/src/engine/catalog.zig` pass the grep gates in this document

## Phase Order

Do the work in this order. Do not reorder the phases.

### Phase 1: Stabilize Generic Identity For Ability Routing

Problem:

- having `AbilityRef.source_instance_id` in the type system is not enough if runtime ignores it
- `PromptState.source_card: ?CardInstance` copies card data and can become stale
- future floating effects and prompt continuations also need a stable identity

Required implementation:

- add a generic runtime-only instance identifier to `CardInstance`
- recommended shape:
  - `instance_id: u32`
- add a monotonic allocator to `Game`
- recommended shape:
  - `next_instance_id: u32`
- assign an `instance_id` in `makeCardInstance`
- preserve the same `instance_id` when a card moves between zones, is hosted, is rezzed, is trashed, is scored, or is returned
- do not export `instance_id` in parity snapshots unless needed for debugging

Replace `AbilityRef` with a stable per-instance target:

- required final shape:
  - `source_instance_id: u32`
  - `ability_index: u8`

Critical invariant:

- `source_instance_id` must be the authoritative runtime selector for the live source card
- once `AbilityRef` exists, no other argument may be used to choose that card
- `server_name`, `card_index`, `card_code`, `title`, and copied `source_card` may be kept only as display or validation context during transition, never as the primary selector

Prompt state must stop storing copied source cards for card-owned continuations:

- replace card-owned prompt continuation state with:
  - `ability_ref: ?AbilityRef`
  - optional generic continuation payload if needed
- keep `source_card` only for pure display if absolutely necessary, and remove it later if possible

Mandatory prompt restrictions:

- every prompt opened by a card-owned ability must store `ability_ref`
- every card-owned continuation that needs to inspect or mutate the source card must recover it from `ability_ref.source_instance_id`
- it is forbidden to recover a live source card for a card-owned continuation by:
  - `prompt.source_card`
  - `prompt.source_card.code`
  - `find*ByCode`
  - title matching
  - zone index captured before the prompt
- `source_card` may remain only for pure display text and must never be the authority for identity or mutation

Required helpers in [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig):

- `findCardByInstanceId`
- `findCardPtrByInstanceId`
- `findAbilitySourceByRef`
- `rebindPromptSourceAfterMove` only if the runtime truly needs it

Required implementation order for Phase 1:

1. add `instance_id` and `next_instance_id`
2. assign `instance_id` in `makeCardInstance`
3. preserve `instance_id` across move, host, unhost, trash, score, and return operations
4. implement `findCardByInstanceId` and `findCardPtrByInstanceId`
5. implement `findAbilitySourceByRef`
6. make `applyAbilityRef` resolve the source card through `findAbilitySourceByRef(ref)` first
7. convert every card-owned prompt to store `ability_ref`
8. remove every card-owned continuation that reads `prompt.source_card` as authority
9. only after the above is complete, move to Phase 2

Phase 1 is explicitly NOT complete if any of these remain true:

- `applyAbilityRef` chooses the live source card from `server_name`, `card_index`, zone traversal, or identity side selection instead of `ref.source_instance_id`
- a card-owned prompt handler contains `prompt.source_card orelse`
- a card-owned prompt handler finds the source card by `code` or `title`
- `findCardPtrByInstanceId` exists but `applyAbilityRef` does not call it, directly or through `findAbilitySourceByRef`
- `ability_ref` exists on `PromptState` or `LegalAction` but execution still ignores it

Forbidden anti-pattern examples:

- `applyAbilityRef(..., server_name, card_index_opt)` selecting the live source card from those parameters
- `.source_card = card` on a prompt that will later mutate or inspect that card
- `const source_card = prompt.source_card orelse ...` inside a card-owned continuation
- `findRunnerHardwareByCode(...)`, `findInstalled*ByCode(...)`, or equivalent code/title lookup inside a card-owned continuation when the same source should come from `ability_ref`

Exit gate for Phase 1:

- `applyAbilityRef` resolves the source card from `AbilityRef.source_instance_id`
- no runtime selection of a live ability source depends on `card_code`, `title`, `server_name`, `card_index`, or copied `source_card`
- every card-owned prompt continuation recovers the live source from stable identity rather than copied card data
- all future phases can target exact card instances safely

### Phase 2: Finish The Generic Ability Runtime

Required type changes in [state.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/state.zig):

- add `abilities: []const AbilitySpec = &.{}` to `CardInstance`
- keep `abilities: []const AbilitySpec = &.{}` on `CardSpec`
- make `LegalAction.ability_ref` the primary payload for card-defined actions

Do not keep `AbilitySpec` as unused scaffolding. The runtime must execute through it.

Required runtime helpers in [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig):

- `appendAbilityActionsForCard`
- `abilityLabelForCard`
- `canUseAbility`
- `payAbilityCost`
- `applyAbilityRef`

`applyAbilityRef` must do exactly this:

1. resolve the live source card by `AbilityRef`
2. resolve the `AbilitySpec` by `ability_index`
3. check side ownership and `allow_opponent_use`
4. check `req`
5. enforce `once_per_turn`
6. pay costs from `AbilityCost`
7. call exactly one of:
   - `choices_fn`
   - `resolve`
   - `on_use`
8. mark ability-used state if needed
9. refresh legal actions generically unless a prompt or pending effect interrupts

Additional non-negotiable rule for `applyAbilityRef`:

- `AbilityRef` is the source-of-truth input
- if the function still temporarily accepts `server_name` or `card_index`, those arguments may only validate that the caller is referring to the same card already resolved by `source_instance_id`
- they must never be used to select a different live card
- if validation fails, return an error instead of silently dispatching through the old route

Action generation must emit `ability_ref` for all card-defined actions:

- identity click abilities
- installed runner abilities
- installed corp abilities
- hosted-card abilities
- access abilities
- play abilities
- flashback abilities
- runner-usable ICE abilities

Do not keep using these action kinds as the primary selector once `ability_ref` is wired:

- `use_installed_ability`
- `use_identity_ability`
- `use_runner_ability`

Those kinds may survive temporarily for parser compatibility, but the execution path must resolve through `ability_ref`, not enum-kind switches.

Exit gate for Phase 2:

- `ability_ref` is written in action generation
- `ability_ref` is consumed in runtime execution
- card-defined actions are no longer routed by legacy enum selectors
- there is no mixed path where `ability_ref` is present but runtime still selects the live card through `card_index`, `server`, or enum-specific dispatch

### Phase 3: Remove The Prompt Compatibility Bridge

Current incorrect bridge:

- `PromptState.on_choice` exists
- many prompts still forward to `on_prompt_choice`
- helper wrappers in [catalog.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/catalog.zig) keep the old hook model alive

This entire bridge must be deleted.

Keep only core engine prompt routing in `applyPromptChoice`:

- mulligan
- trace
- run continue
- jack out
- break-sub
- MU overflow
- generic install destination prompts
- generic access infrastructure prompts

Remove card-owned prompt routing from `applyPromptChoice`.

Delete these from `CardSpec` and runtime:

- `on_prompt_choice`
- `log_prompt_choice`
- `genericSourceCardOnChoice`
- `makeOnChoice`

For every card-owned prompt:

- the ability that opened the prompt must set `PromptState.on_choice`
- the prompt continuation must resolve directly through a typed inline handler
- the continuation must recover the live source card via `AbilityRef` or `instance_id`, not `card_code`

Do not leave any card-specific `prompt_type` branches in [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig) after this phase, except pure engine prompts listed above.

Exit gate for Phase 3:

- grep for `on_prompt_choice` returns zero matches in `zig/src/engine`
- grep for `log_prompt_choice` returns zero matches in `zig/src/engine`
- no card-specific prompt branch remains in `applyPromptChoice`
- no card-owned continuation in `catalog.zig` or `game.zig` reads `prompt.source_card` as identity authority

### Phase 4: Collapse Legacy Play, Identity, Installed, Pump, And Access Systems Into `abilities`

This is the largest phase. It must be done after Phase 2 and Phase 3.

Delete the idea that play, identity, installed use, pump, and access are separate legacy systems.

Represent them uniformly as `AbilitySpec`.

## Current Live-Tree Status

The current tree is not “partially genericized but already routing through `AbilitySpec`”.
It is still legacy-first for Phase 4 surfaces.

Live runtime blockers in [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig):

- `applyAction(...)` still dispatches by legacy action kind instead of `ability_ref` for these surfaces:
  - `.use_installed_ability` at line `5406`
  - `.use_runner_ability` at line `5422`
  - `.use_identity_ability` at line `5447`
- legacy execution paths still exist and are live:
  - `applyInstalledAbility(...)` at line `8298`
  - `applyRunnerAbility(...)` at line `7599`
  - `applyIdentityAbility(...)` at line `8273`
- legacy play/access execution still exists:
  - `resolveCorpOperation(...)` at line `7789`
  - `applyRunnerPlayFromHand(...)` at line `7839`
  - `applyCorpFlashback(...)` at line `7743`
  - `applyAccessCleanupChoice(...)` still switches on `access.kind` at line `7718`
- legacy action generation still exists:
  - `encounterActionsForState(...)` legacy break/pump/bioroid paths at line `10480`
  - `corpOpeningActionsForState(...)` legacy installed-ability and flashback generation at line `10664`
  - `runnerOpeningActionsForState(...)` legacy installed-ability and identity generation at line `10912`
  - `installedAbilityLabel(...)` at line `11057`
  - `hasRunnerInstalledAbilityAction(...)` at line `11079`
  - `hasCorpInstalledAbilityAction(...)` at line `11130`

Live legacy type blockers in [state.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/state.zig):

- `CorpPlayKind`
- `RunnerPlayKind`
- `AccessKind`
- `InstalledAbilityKind`
- `CorpPlaySpec`
- `RunnerPlaySpec`
- `AccessSpec`
- `InstalledAbilitySpec`
- `LegalAction.installed_ability`

Live legacy card-definition blockers in [catalog.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/catalog.zig):

- `runner_play` cards still present:
  - `Mutual Favor`
  - `Wildcat Strike`
  - `Charm Offensive`
  - `Scrounge`
  - `Shred`
  - `Clean Getaway`
  - `Lie Low`
  - `Maintenance Access`
  - `Transfer of Wealth`
  - `Illumination`
  - `Ritual`
- `installed_ability` cards still present:
  - `Nico Campaign`
  - `Otto Campaign`
  - `Anthill Excavation Contract`
  - `Open Market`
- `flashback_click_cost` still present:
  - `Petty Cash`
- `on_play` cards still present:
  - `Mutual Favor`
  - `Wildcat Strike`
  - `Scrounge`
  - `Lie Low`
  - `Ritual`
- `on_score_fn` cards still present:
  - `Offworld Office`
  - `Send a Message`
  - `Superconducting Hub`
  - `Orbital Superiority`
  - `Tomorrow's Headline`
  - `Above the Law`
  - `Luminal Transubstantiation`
  - `Longevity Serum`
  - `Project Ingatan`
  - `Proprionegation`
  - `Sericulture Expansion`
  - `Embedded Reporting`
  - `Next Big Thing`
  - `Greenmail`
  - `Off the Books`
- `on_rez` still present:
  - `Spin Doctor`
- `access.kind != .none` still present on multiple cards and must eventually become generic access abilities instead of `AccessSpec`.

Important consequence:

- Phase 4 is not blocked on “defining more generic types”.
- Phase 4 is blocked on deleting the live legacy runtime and migrating the remaining cards off it.

## Exact Required End-State

- playing a card from hand is a normal `AbilitySpec`
- flashback is either:
  - a second `AbilitySpec` on the same card
  - or one play ability with zone-sensitive `req` and cost logic
- identity clicks are normal `AbilitySpec` entries on the identity card
- icebreaker break and pump are normal `AbilitySpec` entries
- access options are normal `AbilitySpec` entries offered by the accessed card or relevant runner card

Do not keep dual systems alive after migration.

Delete these enums and structs only after all cards are migrated:

- `CorpPlayKind`
- `RunnerPlayKind`
- `AccessKind`
- `InstalledAbilityKind`
- `CorpPlaySpec`
- `RunnerPlaySpec`
- `AccessSpec`
- `InstalledAbilitySpec`

Important implementation rule:

- do not replace `installed_ability` with a new slightly-more-generic dedicated struct
- the final generic manual action surface is `AbilitySpec`

## Exact Implementation Order

Do these in order. Do not skip ahead.

### 4.1 Remove Legacy Manual Ability Dispatch First

- change `applyAction(...)` so card-defined actions resolve through `ability_ref` and `applyAbilityRef(...)`
- do not leave `.use_installed_ability`, `.use_runner_ability`, or `.use_identity_ability` as live behavior selectors
- allowed temporary state:
  - those action kinds may still exist as serialized labels in `LegalAction.kind`
  - but they must immediately route into `applyAbilityRef(...)`
- forbidden temporary state:
  - any switch branch that still chooses behavior by `InstalledAbilityKind`
  - any call to `applyInstalledAbility(...)`, `applyRunnerAbility(...)`, or `applyIdentityAbility(...)`

This sub-step is complete only when:

- `applyInstalledAbility(...)` is deleted
- `applyRunnerAbility(...)` is deleted
- `applyIdentityAbility(...)` is deleted
- `applyAction(...)` no longer dispatches card behavior through those functions

### 4.2 Remove Legacy Encounter Break/Pump/Bioroid Generation

- rewrite `encounterActionsForState(...)` to emit only `AbilitySpec`-backed actions
- all encounter labels must come from `abilityLabelForCard(...)`
- move any remaining break quantity logic onto generic fields already allowed by the plan or onto the `AbilitySpec` itself
- remove use of:
  - `installed_ability.kind == .break_subroutine`
  - `pump_ability.kind == .pump_strength`
  - `runner_abilities`
  - `InstalledAbilityKind.none` as a fake “Leech action selector”

This sub-step is complete only when:

- `encounterActionsForState(...)` has no `installed_ability.kind` or `pump_ability.kind` checks
- encounter action emission writes `ability_ref`
- there is no special bioroid branch outside `AbilitySpec`

### 4.3 Migrate Runner Manual Abilities Off `runner_play`, `on_play`, And `installed_ability`

Cards to migrate first because they are the smallest live group:

- `Mutual Favor`
- `Wildcat Strike`
- `Charm Offensive`
- `Scrounge`
- `Shred`
- `Clean Getaway`
- `Lie Low`
- `Maintenance Access`
- `Transfer of Wealth`
- `Illumination`
- `Ritual`
- `Nico Campaign`
- `Otto Campaign`
- `Anthill Excavation Contract`
- `Open Market`
- `Petty Cash`

Required mapping:

- `runner_play` → one or more `AbilitySpec`
- `on_play` → `AbilitySpec.on_use`, `AbilitySpec.resolve`, or `AbilitySpec.choices_fn`
- `installed_ability` manual actions → `AbilitySpec`
- `flashback_click_cost` / `flashback_gain_clicks` → flashback `AbilitySpec`

Delete the legacy field from the card definition in the same slice that adds the replacement `AbilitySpec`.

### 4.4 Remove Legacy Play Executors

- delete `resolveCorpOperation(...)`
- delete `applyRunnerPlayFromHand(...)`
- delete `applyCorpFlashback(...)`
- replace them with generic play ability resolution driven by `ability_ref`
- `play_from_hand` and `flashback` may remain as engine-level action kinds temporarily, but they must only:
  - resolve the live source by instance id
  - call the appropriate `AbilitySpec`
  - never switch on `corp_play.kind` or `runner_play.kind`

This sub-step is complete only when:

- `corp_play.kind` is not switched on anywhere
- `runner_play.kind` is not switched on anywhere
- `flashback_click_cost` is not read anywhere

### 4.5 Migrate Identity Clicks To `abilities`

- move the remaining identity click behavior onto identity-card `abilities`
- remove reads of:
  - `identity_ability_click_cost`
  - `identity_ability_once_per_turn`
  - `identity_ability_label`
- delete `applyIdentityAbility(...)` if it somehow survived 4.1

This sub-step is complete only when:

- `runnerOpeningActionsForState(...)` and `corpOpeningActionsForState(...)` discover identity actions through `countCardAbilities(...)` / `appendAbilityActionsForCard(...)`
- there is no identity-specific action availability logic using legacy identity fields

### 4.6 Migrate Access Selection Off `AccessSpec`

Move access behavior from `AccessSpec` into generic abilities for:

- agendas with score/steal behavior that still depend on `access.kind`
- upgrades that alter access flow
- runner access-interaction cards

Current access cards in `catalog.zig` include:

- `Offworld Office`
- `Send a Message`
- `Superconducting Hub`
- `Orbital Superiority`
- `Urtica Cipher`
- `Manegarm Skunkworks`
- `Tomorrow's Headline`
- `Above the Law`
- `Luminal Transubstantiation`
- `Longevity Serum`
- `Anoetic Void`
- `Aggressive Trendsetting`
- `Project Ingatan`
- `Proprionegation`
- `Sericulture Expansion`
- `Embedded Reporting`
- `Next Big Thing`
- `Greenmail`
- `Off the Books`

Required result:

- `applyAccessCleanupChoice(...)` must no longer switch on `access.kind`
- access prompts and follow-up behavior must be card-defined via generic prompt handlers and abilities

### 4.7 Delete Legacy Types And Fields Only After Runtime Is Clean

Delete from `CardSpec`, `CardInstance`, `LegalAction`, and `state.zig` only after the runtime no longer reads them:

- `corp_play`
- `runner_play`
- `installed_ability`
- `pump_ability`
- `flashback_click_cost`
- `flashback_gain_clicks`
- `identity_ability_click_cost`
- `identity_ability_label`
- `CorpPlayKind`
- `RunnerPlayKind`
- `AccessKind`
- `InstalledAbilityKind`
- `CorpPlaySpec`
- `RunnerPlaySpec`
- `AccessSpec`
- `InstalledAbilitySpec`
- `LegalAction.installed_ability`

Do not delete the type first and then recreate another dedicated replacement.

## Mandatory Migration Discipline For Phase 4

- migrate one legacy surface at a time and delete the old execution path immediately after its replacement is verified
- do not leave a card in a mixed state where:
  - `abilities` exists
  - but runtime still executes the same behavior through `corp_play`, `runner_play`, `installed_ability`, `pump_ability`, `can_play`, `on_play`, or enum-kind switches
- if a card has been migrated to `AbilitySpec`, the legacy field for that same behavior must be removed in the same slice

Phase 4 is explicitly NOT complete if any of these remain true:

- a migrated card still has both `abilities` and one of `corp_play`, `runner_play`, `installed_ability`, or `pump_ability` describing the same action
- runtime branches on `use_installed_ability`, `use_identity_ability`, or `use_runner_ability` to decide card behavior instead of resolving the `AbilitySpec`
- a play action still depends on `can_play` or `on_play` after an equivalent `AbilitySpec` exists
- access behavior is still selected through `AccessKind` after an equivalent `AbilitySpec` exists

Forbidden anti-pattern examples for Phase 4:

- adding a new dedicated “almost generic” action struct instead of using `AbilitySpec`
- generating `ability_ref` in legal actions but still dispatching the action through legacy enum-specific handlers
- keeping `corp_play` or `runner_play` as hidden fallback “just in case” after the card has an `AbilitySpec`

## Exit Gate For Phase 4

- `CardSpec` no longer contains the legacy play/install/access hook fields listed above
- `CardInstance` no longer contains the legacy play/install/access hook fields listed above
- `LegalAction.installed_ability` is gone
- runtime execution for those surfaces happens only through `AbilitySpec`
- grep returns zero matches:
  - `CorpPlayKind`
  - `RunnerPlayKind`
  - `AccessKind`
  - `InstalledAbilityKind`
  - `CorpPlaySpec`
  - `RunnerPlaySpec`
  - `AccessSpec`
  - `InstalledAbilitySpec`
  - `corp_play.kind`
  - `runner_play.kind`
  - `flashback_click_cost`
  - `identity_ability_click_cost`
  - `applyInstalledAbility`
  - `applyRunnerAbility`
  - `applyIdentityAbility`
  - `installedAbilityLabel`
  - `hasRunnerInstalledAbilityAction`
  - `hasCorpInstalledAbilityAction`

### Phase 5: Replace `EffectContext = anyopaque` With Typed Event Payload Dispatch

Current problem:

- `EffectContext` is opaque
- event handlers reach back into `Game` and infer missing facts from mutable state
- specialized pending effects exist because event payload is too weak

Required replacement:

- make `EffectContext` a real struct
- it must contain a `game` pointer plus typed current-event payload

Recommended shape:

```zig
pub const EffectContext = struct {
    game: *Game,
    event: ?EventContext = null,
    ability_ref: ?AbilityRef = null,
};

pub const EventContext = struct {
    kind: GameEvent,
    acting_side: state.Side,
    source_instance_id: ?u32 = null,
    target_instance_id: ?u32 = null,
    host_instance_id: ?u32 = null,
    server_index: ?u8 = null,
    server_path: ?[]const []const u8 = null,
    amount_i16: i16 = 0,
    amount_u16: u16 = 0,
    did_steal: bool = false,
    did_score: bool = false,
    was_successful: bool = false,
    was_central: bool = false,
};
```

Exact field names can differ, but the event payload must be typed and complete enough that handlers do not need bespoke runtime side channels.

Update `fireEvent` and `collectEventHandlers`:

- accept a payload struct, not just `GameEvent`
- queue that payload with the event source

Migrate these legacy hook surfaces to event handlers or normal abilities:

- `on_score_fn`
- `on_rez`
- `on_encounter`
- agenda score and steal effect structs
- runner-facing ICE abilities

Remove specialized `PendingEffect` entries that exist only because event payload is missing.

Keep only generic pending-effect categories.

Mandatory migration discipline for Phase 5:

- do not leave event handlers in a mixed state where the typed payload exists but handlers still infer critical facts from unrelated mutable game state
- if an event handler needs a source, target, host, server, or amount, that fact must be carried by the event payload rather than reconstructed through card-code checks or zone scans
- delete each legacy hook in the same slice that migrates its behavior to typed event abilities

Phase 5 is explicitly NOT complete if any of these remain true:

- `EffectContext` is typed but handlers still rely on `anyopaque` casts or implicit global state for essential event facts
- `on_score_fn`, `on_rez`, or `on_encounter` still exist as active execution surfaces
- `PendingEffect` variants still encode card-specific behavior that should be represented as generic payload plus generic continuation
- event dispatch still passes only `GameEvent` where the handler needs richer typed context

Forbidden anti-pattern examples for Phase 5:

- adding a new `PendingEffect` tag for one card because the event payload is missing data
- carrying the event type generically but recovering the target card later by title or code
- leaving the old hook field in place as a hidden fallback after the event ability exists

Exit gate for Phase 5:

- `EffectContext` is typed, not `anyopaque`
- event handlers no longer depend on legacy hook fields
- `on_score_fn`, `on_rez`, and `on_encounter` are gone

### Phase 6: Wire Floating Effects Into Runtime And Use Them For Temporary Rules

Current problem:

- `FloatingEffect` exists as a type only
- temporary rules still rely on card-specific runtime flags or one-off branches

Add live floating effect storage to `Game`.

Required runtime support:

- register floating effect
- evaluate floating effect
- expire floating effect on:
  - end of encounter
  - end of run
  - end of turn
  - next turn window

Make these systems consult floating effects:

- `sumStaticEffects`
- encounter ICE strength logic
- access prevention logic
- temporary run credit / access bonus logic

Use floating effects to replace one-off temporary rules such as:

- temporary ICE strength reduction
- prevent steal / prevent trash during a run
- temporary access bonuses
- temporary run credits

Do not leave duplicated legacy state once a floating effect can represent the rule.

Mandatory migration discipline for Phase 6:

- introduce floating effects only when the runtime also evaluates and expires them
- do not add floating-effect registration while keeping the old temporary-rule branch alive in parallel
- each temporary rule moved to floating effects must delete the previous dedicated flag or one-off branch in the same slice

Phase 6 is explicitly NOT complete if any of these remain true:

- `FloatingEffect` values are created but no runtime pass evaluates them
- duration cleanup exists but rule checks still ignore active floating effects
- a temporary rule is represented both as a floating effect and as a dedicated card-specific field or branch
- effect expiration depends on card title or card code checks

Forbidden anti-pattern examples for Phase 6:

- registering `FloatingEffectKind.ice_strength_modifier` while still reading `virus_ice_strength_reduction`
- keeping `prevent steal/trash` as a dedicated run flag after the same rule is expressed as a floating effect
- adding a new floating-effect kind that only names one card instead of a reusable rule concept

Exit gate for Phase 6:

- `FloatingEffect` is live runtime state
- runtime cleanup by duration works
- temporary rule changes no longer require bespoke card fields if a floating effect fits

### Phase 7: Delete Special Static, Access, Host, And Trojan Fields Instead Of Relocating Them

These fields must be fully removed from `CardSpec` and runtime logic:

- `virus_ice_strength_reduction`
- `tags_on_agenda_steal_from_server`
- `trash_access_hand_cost`
- `trash_access_self_trash`
- `trash_access_draw`
- `trojan_break_any`
- `trojan_derez_threshold`
- `trojan_adds_all_subtypes`
- `remote_strength_bonus`
- `tag_on_rez`
- `advanceable`
- `advancement_strength_threshold`
- `advancement_strength_bonus`
- `installs_agendas_faceup`

Allowed replacements only:

- `StaticAbility`
- `EventAbility`
- `AbilitySpec`
- `FloatingEffect`
- host-aware `req` logic

If a new static ability kind is required, it must be truly reusable. Expected generic additions:

- `can_advance`
- `gain_subtype`
- faceup install / install visibility rule if needed

Do not replace a deleted field with another narrow field on a different struct.

Required migration cluster for host/access logic:

- `Carnivore`
- `Gourmand`
- `AMAZE Amusements`
- `Botulus`
- `Tranquilizer`
- `Chromatophores`
- `Leech`

These cards must be migrated together because they share the host-aware and access-aware rule surface.

Mandatory migration discipline for Phase 7:

- remove the field from `CardSpec` when the last consumer is removed
- do not relocate these fields to another struct, pending-effect payload, or runtime scratch field
- host-aware behavior must use generic host identity and generic req logic, not new card-specific booleans or enums

Phase 7 is explicitly NOT complete if any of these remain true:

- any field listed for deletion still exists on `CardSpec`, `CardInstance`, or another replacement struct
- runtime still reads one of those fields directly, even if a generic replacement also exists
- a migrated card still depends on `find*ByCode` or title matching to discover its host/access behavior
- a new narrow field has been introduced to replace one removed field one-for-one

Forbidden anti-pattern examples for Phase 7:

- moving `trash_access_draw` into a new prompt payload field instead of expressing it as an ability effect
- replacing `trojan_adds_all_subtypes` with a new card-only boolean somewhere else
- encoding one host card relationship through a new enum tag that only one card uses

Exit gate for Phase 7:

- [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig) contains no direct read of any field listed above
- [catalog.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/catalog.zig) no longer declares those fields

### Phase 8: Complete Subroutine Migration And Remove Runner ICE Ability Sidecars

Current partial state:

- `SubroutineSpec.resolve` exists
- `SubroutineKind` still drives execution
- `RunnerAbilitySpec` still exists for bioroid-style abilities
- `card_subroutine_handler` still exists

Required end state:

- every ICE subroutine is defined inline on the card in `SubroutineSpec`
- runtime executes `SubroutineSpec.resolve` as the primary path
- `SubroutineSpec` gains `req` and dynamic label support if needed
- runner-facing ICE abilities such as bioroid click-break are normal `AbilitySpec` entries on the ICE

Delete:

- `SubroutineKind`
- `RunnerAbilitySpec`
- `card_subroutine_handler`

Mandatory migration discipline for Phase 8:

- migrate each ICE card fully, not half-way
- once a subroutine on a card is expressed in `SubroutineSpec.resolve`, that same subroutine must not still be reachable through `SubroutineKind`
- runner-facing ICE abilities must be normal `AbilitySpec` entries and must not remain duplicated in `runner_abilities`

Phase 8 is explicitly NOT complete if any of these remain true:

- runtime still switches on `SubroutineKind` for any supported ICE
- `RunnerAbilitySpec` is still used as an active execution surface
- `card_subroutine_handler` still selects behavior for any supported card
- the same printed subroutine or runner-facing ICE ability exists in both the new and old systems

Forbidden anti-pattern examples for Phase 8:

- adding `resolve` to a subroutine but still keeping kind-based execution “for compatibility”
- leaving bioroid click-break in `runner_abilities` after equivalent `AbilitySpec` entries exist
- adding a new subroutine enum tag during migration

After this phase:

- [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig) must not switch on subroutine kind
- [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig) must not scan `runner_abilities`

### Phase 9: Remove Remaining Card-Shaped Runtime Scratch State

After Phases 5-8 are finished, replace and delete these transient fields if they still exist:

- `used_break_this_run`
- `source_card_code`
- `ice_strength_modifier`
- `did_steal_this_run`
- `tags_pending_on_steal`
- `no_steal_or_trash`
- `subroutines_fired`
- `agenda_points_scored_this_turn`
- any other field in `CardInstance`, `RunState`, or `TurnEvents` whose comment references a specific card or tiny card cluster

Allowed replacements:

- typed event payload
- generic event counters
- floating effects
- generic prompt continuation state

Do not keep a card-specific scratch field if a generic payload or effect can carry the same rule.

Mandatory migration discipline for Phase 9:

- delete each scratch field as soon as its meaning has a generic home
- do not preserve obsolete scratch state “for debugging” or “just in case”
- if a field comment mentions a specific card or tiny card cluster, assume it is migration debt unless proven otherwise

Phase 9 is explicitly NOT complete if any of these remain true:

- any listed scratch field still participates in gameplay logic after an equivalent generic payload/effect/counter exists
- a deleted scratch field has been replaced by another field with the same single-card meaning
- a run, access, or turn rule still depends on remembering a specific card title in transient state

Forbidden anti-pattern examples for Phase 9:

- replacing `used_break_this_run` with another break-specific flag instead of a generic event count or effect
- keeping `source_card_code` in a prompt or pending effect once `AbilityRef` exists
- introducing a new `did_x_this_turn` field for one card rather than using generic event counters

### Phase 10: Delete The Dead Compatibility Layer

After all migration phases above are complete:

- delete all unused compatibility helpers
- delete legacy structs and enums
- delete remaining bridge code from [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig), [state.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/state.zig), and [catalog.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/catalog.zig)

Final runtime must discover card behavior only through:

- `abilities`
- `event_abilities`
- `static_abilities`
- `subroutines`

Mandatory migration discipline for Phase 10:

- Phase 10 is a deletion phase, not a “leave harmless compatibility wrappers” phase
- anything still needed by runtime is not compatibility code and must be justified as part of the final generic architecture

Phase 10 is explicitly NOT complete if any of these remain true:

- a legacy type, enum, field, or helper remains in the runtime “because it might still be useful”
- a compatibility wrapper forwards a generic path into an old hook field
- dead legacy code remains compile-reachable even if tests do not hit it

Forbidden anti-pattern examples for Phase 10:

- leaving `makeOnChoice` or similar helpers because deleting them is inconvenient
- keeping old enums only for “readability” after the generic surface exists
- keeping a legacy struct with zero current users as future-proofing

## Files To Edit

Primary files:

- [catalog.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/catalog.zig)
- [game.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/game.zig)
- [state.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/state.zig)
- [parity.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/parity.zig)

Do not touch unrelated files unless a test or compile error forces it:

- `zig/src/api.zig`
- `zig/src/tui.zig`
- `zig/src/parity/oracle.zig`
- `zig/src/data/cards.json`

## Required Audit And Test Work

This migration is not complete without an explicit coverage audit.

### Card Coverage Manifest

Add a compile-time coverage manifest in [parity.zig](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/parity.zig) keyed by card code for the current Zig catalog.

For each card, track:

- smoke parity test exists
- branch coverage complete
- legacy surfaces remaining

Do not mark a card complete until it has:

- zero legacy surface usage
- one smoke parity test
- explicit branch coverage if it has multiple legal paths

### Branch Coverage Rules

For every card with branching behavior, add one parity test per branch:

- each prompt choice
- each yes/no optional trigger path
- each cancel or no-action decline path
- each alternate cost path
- each server branch when behavior differs
- each target-class branch when behavior differs
- each host branch when behavior differs
- flashback vs normal play when applicable
- opponent-use branch when applicable

For every migrated ability, add local negative tests for:

- req false
- insufficient clicks
- insufficient credits
- insufficient counters
- wrong timing window
- wrong host
- wrong server
- once-per-turn exhaustion

Keep all tests deterministic:

- fixed seed
- fixed matchup
- no random hand fishing
- build deterministic decks or scenarios when needed

### Verification Commands

Run at minimum:

- `mise exec -- zig test zig/src/engine/game.zig`
- `mise exec -- zig test zig/src/root.zig`
- `mise exec -- zig build test-sharded`

Use targeted filters while iterating, but do not consider the work complete until the full suite passes.

### Required Phase Signoff Format

Do not mark any phase complete with a vague statement such as "implemented" or "migrated".

For every phase, the implementer must record all of the following:

1. what new generic path now exists
2. what exact old path was deleted in the same slice
3. what grep or code inspection proves the old path is no longer active
4. what parity tests cover the migrated cards and branches
5. what negative tests prove the old fallback route is gone

Minimum proof standard by phase:

- Phase 1:
  - show where `applyAbilityRef` resolves by `AbilityRef.source_instance_id`
  - show zero remaining card-owned continuations using `prompt.source_card` as authority
- Phase 2:
  - show action generation writing `ability_ref`
  - show execution reading `ability_ref`
  - show the equivalent enum-dispatch branch deleted
- Phase 3:
  - show `on_prompt_choice`, `log_prompt_choice`, `genericSourceCardOnChoice`, and `makeOnChoice` deleted
  - show prompt continuations using direct inline handlers
- Phase 4:
  - show each migrated card no longer carries legacy play/install/access fields for that behavior
  - show runtime no longer dispatches that behavior through legacy enums
- Phase 5:
  - show typed event payload flowing into handlers
  - show corresponding legacy hook field deleted
- Phase 6:
  - show floating-effect registration, evaluation, and expiration
  - show the old temporary-rule field or branch deleted
- Phase 7:
  - show each removed field no longer exists anywhere in runtime types
  - show migrated cards expressing the same behavior through generic abilities/effects
- Phase 8:
  - show `SubroutineSpec.resolve` handling the supported ICE
  - show kind-based dispatch removed for that behavior
- Phase 9:
  - show deleted scratch fields no longer influence gameplay
  - show their generic replacement
- Phase 10:
  - show remaining grep gates passing
  - show no compatibility wrappers remain

## Grep Gates

These grep gates are part of the definition of done.

The following commands must return zero matches in runtime files after the migration:

```sh
rg -n 'on_play|on_prompt_choice|can_play|on_score_fn|on_rez|on_encounter|card_subroutine_handler' zig/src/engine/game.zig zig/src/engine/state.zig zig/src/engine/catalog.zig
```

```sh
rg -n 'virus_ice_strength_reduction|tags_on_agenda_steal_from_server|trash_access_hand_cost|trash_access_self_trash|trash_access_draw|trojan_break_any|trojan_derez_threshold|trojan_adds_all_subtypes|remote_strength_bonus|tag_on_rez|advanceable|advancement_strength_threshold|advancement_strength_bonus|flashback_click_cost|flashback_gain_clicks|installs_agendas_faceup|identity_ability_click_cost|identity_ability_label' zig/src/engine/game.zig zig/src/engine/state.zig zig/src/engine/catalog.zig
```

```sh
rg -n 'CorpPlayKind|RunnerPlayKind|AccessKind|InstalledAbilityKind|SubroutineKind|RunnerAbilitySpec|CorpPlaySpec|RunnerPlaySpec|AccessSpec|InstalledAbilitySpec' zig/src/engine/game.zig zig/src/engine/state.zig zig/src/engine/catalog.zig
```

```sh
rg -n 'lookupCardSpecByCode\([0-9]+' zig/src/engine/game.zig
```

The last command matters because the engine runtime must not have literal card-code special cases.

Before moving past Phase 1, these additional checks must also be true:

```sh
rg -n 'prompt\.source_card orelse' zig/src/engine/game.zig zig/src/engine/catalog.zig
```

```sh
rg -n 'find[A-Za-z0-9_]*ByCode\(' zig/src/engine/game.zig zig/src/engine/catalog.zig
```

```sh
rg -n 'applyAbilityRef' -A30 zig/src/engine/game.zig
```

Interpretation rules for the Phase 1 checks:

- the first command must return zero matches for card-owned prompt continuations
- the second command must return zero matches inside card-owned continuations that are trying to recover the source card
- the third command is a manual inspection gate:
  - `applyAbilityRef` must resolve the live source through `AbilityRef.source_instance_id`
  - it must not select the live source from `card_index`, `server`, side-only identity fallback, or other legacy context
- if these checks fail, Phase 1 is not done even if `instance_id` and `AbilityRef` exist as types

## Acceptance Checklist

Do not consider the work complete until every item below is true:

- `catalog.zig` is the only home for card logic
- `CardSpec` uses `abilities`, `event_abilities`, `static_abilities`, and `subroutines` only
- `CardInstance` has stable `instance_id`
- `AbilityRef` identifies exact card instances, not card codes
- `PromptState` continuations do not depend on copied card instances or legacy prompt hooks
- `ability_ref` is the canonical runtime target for card-defined actions
- `applyAbilityRef` resolves the live source from `AbilityRef.source_instance_id`, not from legacy positional context
- `FloatingEffect` is live runtime state with duration cleanup
- `EffectContext` is typed and carries event payload
- there are no legacy hook fields left
- there are no special-case card scalar fields left
- there are no legacy play/access/install/subroutine structs or enums left
- there are no literal card-code special cases in `game.zig`
- every current Zig catalog card has smoke parity coverage
- every branchful card has explicit branch coverage
- full engine tests and full root parity tests pass
- every phase signoff includes proof that the replacement path exists and the legacy path for the same behavior is gone

## Notes For The Implementer

- Do not trust the current partial generic layer. It is incomplete by design.
- Do not extend the bridge. Delete it once the generic replacement is ready.
- If a step looks like it can be "mostly finished" by keeping one or two legacy fields, it is not finished.
- Presence of a new type is not evidence of completion. The runtime call site must use it as the sole authority.
- A phase is not complete if the new identity or prompt field exists but the old route still works in parallel.
- If a card seems impossible to migrate without adding a new field, stop and find the generic rule it really belongs to.
- The current partial migration already proves the direction. The remaining work is deletion of legacy structure, not invention of another intermediate architecture.
