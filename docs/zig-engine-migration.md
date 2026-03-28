# Zig Engine Migration

## Goal

Port the authoritative Netrunner game engine from Clojure to Zig first, then expose the Zig engine through a C ABI for a future OpenSpiel C++ adapter.

This document tracks scope, decisions, and migration TODOs.

## Non-Goals For Phase 1

- Do not port the existing browser UI.
- Do not port websocket/channel-socket transport.
- Do not port the full card pool first.
- Do not build the OpenSpiel wrapper first.

## Agreed Direction

- Keep the current Clojure engine as the oracle/reference implementation.
- Build the Zig engine as a transport-free core.
- Compare Zig behavior against the Clojure engine with parity tests.
- Delay the OpenSpiel C++ layer until the Zig core has a stable game API.
- Use the latest stable Zig release, pinned to an exact version.

## Toolchain Policy

- Use the latest stable Zig release, not `master`.
- Pin one exact Zig version in repo tooling and CI.
- Treat Zig upgrades as explicit maintenance tasks.
- Do not depend on `master`-only features for core engine work.
- Re-evaluate newer Zig releases later for the service/runtime layer if needed.

## Recommended Initial Scope

Start with the `system-gateway` beginner teaching decks, not the full card pool.

Why this is the right first target:

- Small fixed matchup.
- Real gameplay, not an artificial toy subset.
- Fewer unique cards than broader formats.
- Lower prompt/action surface than full `startup` or `standard`.
- Easier to generate deterministic parity fixtures.

Recommended first migration slices:

1. `system-gateway` beginner corp vs runner only.
2. Then `system-gateway` intermediate.
3. Then expand to the full System Gateway card pool.
4. Only after that consider broader formats such as `startup`.

## Current First Card Pool

Confirmed Phase 1 card pool:

- `system-gateway` beginner only
- Fixed matchup only, not the full System Gateway format
- Corp identity: `The Syndicate: Profit over Principle`
- Runner identity: `The Catalyst: Convention Breaker`

Unique cards in scope for Phase 1:

Corp:

- `The Syndicate: Profit over Principle`
- `Offworld Office`
- `Send a Message`
- `Superconducting Hub`
- `Nico Campaign`
- `Regolith Mining License`
- `Urtica Cipher`
- `Government Subsidy`
- `Hedge Fund`
- `Seamless Launch`
- `Manegarm Skunkworks`
- `Brân 1.0`
- `Palisade`
- `Diviner`
- `Whitespace`
- `Karunā`
- `Tithe`

Runner:

- `The Catalyst: Convention Breaker`
- `Creative Commission`
- `Jailbreak`
- `Overclock`
- `Sure Gamble`
- `Tread Lightly`
- `VRcation`
- `Docklands Pass`
- `Pennyshaver`
- `Red Team`
- `Smartware Distributor`
- `Telework Contract`
- `Verbal Plasticity`
- `Carmen`
- `Cleaver`
- `Mayfly`
- `Unity`

Scope count:

- 17 corp cards including identity
- 17 runner cards including identity
- 34 unique cards total including identities

Source deck definitions:

- `src/cljc/jinteki/preconstructed.cljc`

## Engine Boundary

The engine is already mostly separate from the web transport layer.

Server/web adapter today:

- `src/clj/web/game.clj`

Core engine entrypoints today:

- `src/clj/game/core/set_up.clj`
- `src/clj/game/main.clj`
- `src/clj/game/core/process_actions.clj`
- `src/clj/game/core/diffs.clj`

## Proposed Zig Core API

The Zig core should not copy the current websocket protocol directly. It should expose a transport-free engine API.

Target API shape:

- `init_game(config, seed) -> state`
- `clone_state(state) -> state`
- `current_player(state) -> player_or_chance`
- `legal_actions(state) -> []action`
- `step(state, action) -> transition`
- `is_terminal(state) -> bool`
- `returns(state) -> [2]f32`
- `observation(state, player) -> observation`

Notes:

- Keep the action representation explicit and stable.
- Avoid stringly-typed actions in the Zig API if possible.
- The OpenSpiel adapter can map OpenSpiel action ids to Zig action structs later.

## Canonical Zig State Schema

Use a gameplay-oriented canonical state schema in Zig, not a direct field-for-field copy of the current Clojure records.

The Zig schema should separate:

- authoritative hidden game state
- derived legal-action / prompt state
- observation projection for a given player
- non-gameplay metadata

### EngineState

Suggested top-level shape:

- `format`
- `seed`
- `turn_number`
- `active_player`
- `phase`
- `corp: PlayerState`
- `runner: PlayerState`
- `run: ?RunState`
- `prompt_stack`
- `event_queue`
- `turn_flags`
- `per_turn_counters`
- `per_run_counters`
- `winner`
- `win_reason`
- `rng_state`

Do not include in canonical engine state unless needed for rules:

- chat log
- websocket ids
- sound effects
- UI toast payloads
- CSS / art / frontend options

### PlayerState

Shared shape for both sides where possible:

- `side`
- `identity: CardInstanceId`
- `credit`
- `click`
- `agenda_points`
- `agenda_point_requirement`
- `hand_size_base`
- `hand_size_total`
- `deck: Zone`
- `hand: Zone`
- `discard: Zone`
- `scored: Zone`
- `rfg: Zone`
- `play_area: Zone`
- `current: Zone`
- `set_aside: Zone`
- `installed_board`
- `properties`
- `counters`

Corp-specific:

- `servers`
- `bad_publicity`

Runner-specific:

- `rig`
- `memory`
- `link`
- `tags`
- `brain_damage`
- `run_credit`
- `bad_pub_credit`

### CardInstance

Each card in play or hidden zones should be represented as an instance, not just by title.

Required fields:

- `instance_id`
- `card_id`
- `owner`
- `controller`
- `zone`
- `hosted_on`
- `install_position`
- `facedown`
- `rezzed`
- `seen_by`
- `counters`
- `strength`
- `advancement`
- `temporary_modifiers`
- `flags`

Design rule:

- static card definition data belongs in immutable card defs
- runtime mutable card facts belong in `CardInstance`

### Zones

Represent zones canonically, not as mixed nested Clojure vectors/keywords/strings.

Suggested zone model:

- `deck`
- `hand`
- `discard`
- `scored`
- `rfg`
- `play_area`
- `current`
- `set_aside`
- `corp_server_content(server_id)`
- `corp_server_ice(server_id, position)`
- `runner_rig(rig_slot)`
- `hosted(card_instance_id)`

### RunState

Keep run state explicit because it is central to legality and OpenSpiel turn progression.

Suggested fields:

- `server`
- `position`
- `phase`
- `current_ice`
- `encounter_stack`
- `approached_ice_in_position`
- `cannot_jack_out`
- `corp_no_action`
- `runner_no_action`
- `bad_pub_available`

### PromptState

The current engine is prompt-driven, so prompt state is part of the engine, not just UI.

Suggested fields:

- `prompt_id`
- `owner`
- `prompt_type`
- `source`
- `choices`
- `selectable_cards`
- `constraints`
- `continuation`

Important:

- Zig should not store frontend-formatted prompt strings as the semantic source of truth.
- Prompt text can be derived separately for human-facing clients.

### ObservationState

Observation should be derived from `EngineState`, not stored as canonical engine state.

Suggested observation outputs:

- `private_observation(player)`
- `public_observation()`
- `information_state(player)` if needed for OpenSpiel

Observation must include:

- only information visible to that player
- legal actions available at that decision point
- prompt state visible to that player

### Canonicalization Rules

Parity comparisons should use a canonical gameplay projection that excludes:

- transport/session metadata
- presentation text unless semantically relevant
- replay/history-only fields
- sound/toast/ui-only fields

For Phase 1, the canonical comparison format should prioritize:

- player resources
- zone contents and ordering
- card instance state
- active prompts
- active run state
- legal actions
- terminal result

## Canonical Action Schema

Use a typed action model in Zig, not the current raw string command API as the primary engine interface.

The current engine receives commands such as:

- `play`
- `ability`
- `choice`
- `select`
- `run`
- `rez`
- `advance`
- `score`

Those are useful as a compatibility layer, but not as the canonical long-term API.

### Design Goals

- make legal actions enumerable
- make actions stable and serializable
- separate prompt resolution from UI formatting
- support OpenSpiel action ids later
- avoid free-form string parsing in the engine core

### Top-Level Action Type

Suggested Zig shape:

- `Action = union(enum) { ... }`

Suggested categories:

- `basic`
- `card`
- `ability`
- `run`
- `prompt`
- `turn`
- `admin`

### Basic Actions

Actions that are always explicit and low-parameter:

- `gain_credit`
- `draw_card`
- `purge`
- `remove_tag`
- `concede`

### Card Actions

Actions that operate on a card instance:

- `play_from_hand(card_id, optional_target)`
- `install(card_id, install_target)`
- `rez(card_id)`
- `derez(card_id)`
- `trash(card_id)`
- `advance(card_id)`
- `score(card_id)`
- `move(card_id, destination)`
- `flashback(card_id)`
- `expend(card_id)`

### Ability Actions

Actions that invoke a concrete ability index on a card instance:

- `use_ability(card_id, ability_index, optional_targets)`
- `use_corp_ability(card_id, ability_index, optional_targets)`
- `use_runner_ability(card_id, ability_index, optional_targets)`
- `use_subroutine(card_id, subroutine_index)`
- `resolve_unbroken_subroutines(card_id, subroutine_mask)`
- `use_dynamic_ability(source_id, dynamic_ability_id, optional_targets)`

Note:

- if possible, collapse corp/runner/dynamic variants into one normalized representation internally
- keep external compatibility adapters separate from the canonical core model

### Run Actions

Actions related to initiating and progressing runs:

- `initiate_run(server_id)`
- `continue_run`
- `jack_out`
- `start_next_phase`
- `toggle_auto_no_action`
- `indicate_action`

### Turn Actions

Actions that control turn structure:

- `keep_hand`
- `mulligan`
- `start_turn`
- `end_phase_12`
- `phase_12_pass_priority`
- `post_discard_pass_priority`
- `end_post_discard`
- `end_turn`

### Prompt Resolution Actions

This is the most important part for parity and OpenSpiel compatibility.

The engine is prompt-driven, so prompt resolution should be explicit in the action model.

Suggested prompt actions:

- `choose_string(prompt_id, choice_index)`
- `choose_number(prompt_id, value)`
- `choose_card(prompt_id, card_id)`
- `choose_cards(prompt_id, []card_id)`
- `choose_server(prompt_id, server_id)`
- `choose_yes_no(prompt_id, yes)`
- `select_card(prompt_id, card_id)`
- `select_player(prompt_id, player)`
- `resolve_trace(prompt_id, amount)`
- `resolve_bad_pub(prompt_id, yes)`
- `cancel_prompt(prompt_id)`

Important design rule:

- prompt actions should reference stable prompt ids and typed payloads
- they should not depend on rendered text labels

### Legal Action Enumeration

The Zig engine should expose legal actions as a list of fully-instantiated typed actions.

For example:

- not `play_from_hand(card_id=?)`
- but `play_from_hand(card_id=42, target=none)`

This is important for:

- deterministic parity testing
- OpenSpiel action indexing
- avoiding an extra target-inference layer outside the engine

### Action Identity

Each legal action should have:

- stable action kind
- stable target payload
- deterministic ordering

Recommended ordering policy:

- sort first by action category
- then by source card instance id
- then by target payload in canonical order

This makes action ids reproducible for OpenSpiel integration.

### Compatibility Adapter

Keep a thin compatibility adapter from current Clojure-style commands to the new canonical action model.

Examples:

- `"play" + {:card ...}` -> `play_from_hand`
- `"ability" + {:card ... :ability n}` -> `use_ability`
- `"choice" + {:eid ... :choice ...}` -> one of the `choose_*` prompt actions
- `"select" + {:eid ... :card ...}` -> `select_card`
- `"run" + {:server ...}` -> `initiate_run`

This adapter is useful for:

- replaying existing fixtures
- parity harnesses
- keeping the browser protocol alive temporarily if needed

### Canonical Action Coverage For Phase 1

The beginner deck migration likely needs only a subset at first.

Expected Phase 1 action families:

- `gain_credit`
- `draw_card`
- `play_from_hand`
- `install`
- `rez`
- `advance`
- `score`
- `initiate_run`
- `continue_run`
- `jack_out`
- `use_ability`
- `choose_*` prompt actions
- `end_turn`
- `keep_hand`
- `mulligan`

### Action Schema Notes For OpenSpiel

OpenSpiel will eventually want integer action ids.

Recommended approach:

- canonical typed action list is produced by Zig
- that list is deterministically ordered
- OpenSpiel integer action ids index into that ordered list

This avoids:

- brittle hard-coded global action enums
- sparse gigantic action spaces for prompt-heavy gameplay
- UI-driven action encoding leaking into the engine

## Parity Testing Strategy

The Clojure engine remains the source of truth during migration.

We need a parity harness that compares:

- initial setup state
- legal actions
- state transitions after each action
- terminal result
- winner / loser
- public observations
- private side-specific observations when needed

Recommended approach:

1. Build deterministic scenario fixtures from the Clojure engine.
2. Replay the same scenarios in Zig.
3. Compare canonicalized outputs after every action.

Fixture types:

- game initialization fixture
- single-action transition fixture
- full-game replay fixture
- prompt-resolution fixture
- randomness-sensitive fixture

Canonicalization rules:

- Ignore transport-only fields.
- Ignore presentation-only text when it is not semantically relevant.
- Compare game facts, not UI formatting.

## Phase 1 Parity Whitelist

For `system-gateway` beginner parity, compare a canonical gameplay projection rather than raw `@state`.

### Compare

Top-level game facts:

- active player
- turn number
- turn phase / step
- terminal status
- winner and win reason
- seeded RNG state

Per-side scalar state:

- credits
- clicks and click-per-turn
- agenda points and agenda-point requirement
- hand size base and total
- bad publicity
- runner tags, link, memory, run credits, brain damage

Run state:

- attacked server
- run phase
- position and current ICE
- jack-out restrictions
- bad publicity availability
- access modifiers that affect legal actions

Zone contents and ordering:

- Corp: deck, hand, discard, scored, rfg, current, set-aside, server roots, server ICE
- Runner: deck, hand, discard, scored, rfg, current, set-aside, rig, hosted cards
- ordered zones must preserve order in the canonical export

Card-instance gameplay fields:

- printed card identity (`card code` or stable title fallback)
- owner and controller
- current zone and positional slot
- hosted-on relationship
- rezzed / unrezzed
- faceup / facedown
- seen / hidden state where rules-relevant
- counters and advancement counters
- strength and temporary strength modifications when rules-relevant
- disabled state or rule flags that affect legal actions

Prompt state:

- prompted side
- prompt semantic type
- source card or source ability
- minimum / maximum selections
- available semantic choices after canonicalization
- selectable cards / servers / numbers

Legal actions:

- canonical typed action list
- deterministic action ordering
- prompt-resolution actions included

### Ignore

Transport and session metadata:

- websocket or channel-socket ids
- lobby ids
- user names and client metadata

Presentation-only fields:

- chat log
- replay history
- sound effect payloads
- toast payloads
- quotes
- rendered prompt strings when only cosmetic

Generated ids and unstable handles:

- raw `:cid`
- raw `:eid`
- prompt UUIDs
- effect UUIDs
- event UUIDs
- toast UUIDs

Analytics or bookkeeping fields unless they affect rules:

- stats tallies
- shuffle counters
- bug-report metadata
- admin-command traces

Derived UI hints already implied elsewhere:

- client convenience flags used only for rendering
- diff transport shape
- preformatted labels when the semantic choice payload is already compared

### Canonicalization Notes

- Never compare raw UUIDs or engine-generated ids directly.
- Prompt messages should be reduced to semantic choice data, not compared as text.
- Card comparisons should use stable printed identity plus canonical zone and position information, not transient `:cid`.
- If a field only affects presentation and not legal actions or state evolution, exclude it.
- If a field affects hidden information, compare it only from the appropriate side-specific observation projection.

## Randomness And Seeding

Yes, we should use a seeding mechanism to control randomness.

However, the current Clojure engine is not externally seedable in a clean way yet.

Important detail:

- `src/clj/game/core/shuffling.clj` uses a process-global `SecureRandom` for deck shuffles.
- Other parts of the engine still use direct randomness via `rand-int`, `rand-nth`, `shuffle`, and `random-uuid` in multiple namespaces.

That means deterministic parity testing will require an RNG abstraction, not just a shuffle seed.

### RNG Work Required

Introduce a single engine-owned RNG source and route all gameplay randomness through it.

Requirements:

- seed supplied at game creation
- deterministic replay given identical seed and actions
- no direct use of host-global randomness in gameplay code
- separate non-gameplay ids from gameplay randomness if needed

Recommended policy:

- Gameplay randomness must come from `state.rng`.
- Logging ids / toast ids / transport ids should not affect gameplay state evolution.

### First Clojure RNG Cut

Implemented in the current repo state:

- added `src/clj/game/core/rng.clj`
- added deterministic seeded shuffle helpers
- seeded initial deck construction when a game is created with `:seed`
- seeded deck reshuffles through `game.core.shuffling`
- routed beginner-relevant engine randomness through `game.core.rng` in:
  - `game.core.damage`
  - `game.core.access`
  - `game.core.moving`
  - `game.core.commands`

Current behavior:

- if a game has no `:seed`, existing nondeterministic behavior is preserved
- if a game has a `:seed`, initial deck order and subsequent deck shuffles are deterministic
- seeded games now also deterministically resolve random damage discards, random HQ/Archives access ordering, random hand discards, and debug die rolls / random discard commands

### Remaining Randomness Hotspots

Still unswept for full deterministic parity:

- direct `rand-int` uses outside the Phase 1 beginner path
- direct `rand-nth` uses outside the Phase 1 beginner path
- direct raw `shuffle` uses in broader card definitions and non-beginner mechanics
- mark selection
- quote selection at game setup
- prompt choice UUID generation
- quick-draft / deck-generation randomness that is not part of beginner-matchup parity

### Untouched RNG Backlog Outside Beginner Scope

Keep these on the backlog for later card-pool expansion.

Shared gameplay engine namespaces:

- `src/clj/game/core/mark.clj`
  - random mark selection
- `src/clj/game/core/prompts.clj`
  - prompt helper dice rolls
- `src/clj/game/core/costs.clj`
  - random hand trash / discard costs
- `src/clj/game/core/turmoil.clj`
  - random card selection and replacement logic for that format

Presentation or non-gameplay namespaces:

- `src/clj/game/quotes.clj`
  - random quote selection
- `src/clj/game/core/toasts.clj`
  - random toast ids via `random-uuid`
- `src/clj/game/core/prompts.clj`
  - prompt choice UUIDs
- `src/clj/game/core/effects.clj`
  - effect registration UUIDs
- `src/clj/game/core/engine.clj`
  - event / suppression UUIDs

Mode or generation helpers not needed for Phase 1 parity:

- `src/clj/game/core/quick_draft.clj`
  - randomized draft choices and deck shuffles
- `src/cljc/jinteki/chimera.cljc`
  - randomized deck construction helpers

Broader card-definition namespaces with unswept random gameplay behavior:

- `src/clj/game/cards/assets.clj`
- `src/clj/game/cards/events.clj`
- `src/clj/game/cards/hardware.clj`
- `src/clj/game/cards/ice.clj`
- `src/clj/game/cards/identities.clj`
- `src/clj/game/cards/operations.clj`
- `src/clj/game/cards/resources.clj`

Typical unswept patterns in those card namespaces:

- random card selection from HQ or Grip
- random access or reveal choices
- random trashing from hand
- random server or pile assignment
- randomized pile ordering when cards are returned or revealed

Later migration policy:

- when a card enters scope, sweep only the randomness sites required by that card and its dependent shared mechanics
- keep presentation-only UUIDs and quote randomness out of gameplay parity comparisons

Important:

- prompt UUIDs and presentation-only randomness should be excluded from parity comparisons, or replaced with deterministic ids later
- gameplay-affecting randomness still needs to be routed through the engine RNG abstraction namespace

## Immediate TODOs

- [x] Confirm the initial migration target as `system-gateway` beginner only.
- [x] Enumerate the exact unique cards in that beginner matchup.
- [x] Define a canonical Zig-side state schema for gameplay facts.
- [x] Decide on Zig toolchain policy.
- [x] Define a canonical action schema for prompts and normal actions.
- [x] Add a Clojure-side deterministic RNG abstraction for parity testing.
- [x] Route System Gateway beginner-critical engine randomness through the RNG wrappers.
- [ ] Replace remaining direct gameplay uses of `rand-int`, `rand-nth`, and raw `shuffle` with engine RNG wrappers.
- [x] Decide which fields belong in parity comparisons and which should be ignored.
- [x] Build a Clojure fixture exporter for initial states, legal actions, and transitions.
- [x] Create a Zig test runner that consumes those fixtures.
- [x] Port setup + turn framework before card-specific abilities.
- [x] Port the beginner card definitions and their required engine mechanics.
- [x] Run parity tests on the beginner matchup until stable.
- [ ] Expand from beginner to intermediate after parity is green.

### Core Flow Implementation Queue

Execution order for remaining core engine work:

- [x] Implement corp scoring pipeline:
- [x] choose advancement target
- [x] apply advancement counters
- [x] score-eligible agenda action
- [x] move agenda to scored area
- [x] agenda-point progression + terminal check hook
- [x] Reuse the same `Send a Message` rez trigger path for `on-score`.
- [x] Implement runner `run_any_server` basic-action behavior.
- [x] Replace placeholder card behavior:
  - [x] `Seamless Launch`
  - [x] `Predictive Planogram`
  - [x] `Public Trail`
  - [x] `Retribution`
  - [x] `Mutual Favor`
  - [x] `Wildcat Strike`
- [x] Expand run/ICE core flow beyond the current continue/access skeleton:
  - [x] corp rez window on encountered ice
  - [x] minimal subroutine resolution framework
  - [x] run interruption/continuation alignment for replay parity
- [x] Continue beginner card-mechanic coverage:
  - [x] Offworld Office on-score credit gain
  - [x] Corp installed `take_credits` economy-asset path (`Regolith Mining License`, `Nico Campaign` specs)
  - [x] `Urtica Cipher` ambush access damage path (seeded RNG hand damage)
  - [x] Basic ICE encounter parity tests (encounter subroutines, unrezzed ice passthrough)
  - [x] Corp rez window during ICE encounter
  - [x] Icebreaker break subroutine parity

### Remaining Core Flow TODOs

- [x] Implement full ICE encounter framework (subroutines, break windows, `use_subroutine` execution).
- [x] Add complete run timing support:
  - [x] jack-out window/path (implemented, parity test framework in place)
  - [x] apply run rez-cost modifiers (`run.rez_cost_bonus`) to corp rez costs
- [x] Migrate beginner ICE card behaviors:
  - [x] `Brân 1.0`:
    - [x] Basic subroutines (bioroid break, end the run)
    - [x] "Install ice from HQ/Archives" subroutine (prompt-based with pause/resume via `pending_subroutine`)
  - [x] `Palisade`
  - [x] `Diviner`
  - [x] `Whitespace`
  - [x] `Karunā`
  - [x] `Tithe`
  - [x] replace `Funhouse` placeholder with real behavior
- [x] Migrate remaining access-time upgrade/asset behaviors:
  - [x] `Manegarm Skunkworks`
- [x] Migrate runner installed-card gameplay (breaker/resource/hardware active + passive abilities).
- [x] Add non-agenda terminal conditions:
  - [x] flatline loss
  - [x] deck-out loss

## Suggested Milestones

### M0: Deterministic Oracle

- Clojure engine can run seeded games deterministically.
- Fixture exporter exists.
  Current first cut: `src/clj/game/parity/export.clj` writes `test/resources/parity/system-gateway-beginner-init.json` with canonical oracle state, per-side observations, decision side, and deterministically ordered legal actions for the seeded beginner matchup.
- Generic replay oracle exists.
  Current first cut: `lein run -m game.parity.oracle <request.json>` accepts `{:seed <int> :actions [<canonical-action> ...]}` and prints the canonical bundle after replaying that action sequence, so Zig can request arbitrary oracle documents without adding new baked scenarios to the exporter.
  Current Zig integration: `zig/src/parity/oracle.zig` has `replayActions(...)`, which writes a request JSON, invokes that Lein entrypoint, and parses the returned canonical bundle for live parity checks.

### M1: Core Skeleton In Zig [COMPLETE]

**Status:** All 57 tests passing under `zig build test`. M1 is complete.

**Achievements:**
- Zig state model exists.
- Zig action model exists.
- Basic game lifecycle exists.
- Deterministic seeded RNG for shuffling and damage.
- Full ICE encounter framework with subroutines and break windows.
- Non-agenda terminal conditions (flatline, deck-out).
- All beginner ICE card behaviors implemented.
- Access-time upgrade/asset behaviors migrated.
- Runner installed-card gameplay (breakers/resources/hardware).

**Current Coverage:**
- Both players' mulligans and turn starts.
- Corp basic actions: `Hedge Fund`, `Seamless Launch`, install prompts for agendas/assets/ICE.
- Runner basic actions, run initiation.
- Runner `play-from-hand`: `Sure Gamble`, `Tread Lightly` (with server-choice prompt), `Jailbreak` (with central-server prompt).
- Deterministic run phases: initiation, approach-ice, movement, success/access.
- Agenda access and steal: `Send a Message` through `Steal` and Corp `Done` cleanup.
- Corp scoring pipeline: advancement, score-eligible agenda, move to scored.
- ICE encounter: unrezzed passthrough, rezzed encounter with subroutine resolution.
- Beginner ICE: `Brân 1.0`, `Palisade`, `Diviner`, `Whitespace`, `Karunā`, `Tithe`.
- Upgrades: `Manegarm Skunkworks`.
- Terminal conditions: flatline loss, deck-out loss.

**Deferred to M2:**
- Icebreaker break subroutine parity.
- Intermediate deck mechanics parity.

**Key Files:**
- `build.zig` - Build configuration
- `zig/src/engine/state.zig` - State model
- `zig/src/engine/catalog.zig` - Card definitions
- `zig/src/engine/game.zig` - Core game logic
- `zig/src/parity/oracle.zig` - Clojure oracle integration
- `zig/src/engine/parity.zig` - Parity tests

### M2: Beginner Matchup Parity [COMPLETE]

**Status:** All 71 tests passing. M2 is complete.

- Beginner decks initialize correctly.
- A constrained set of games can be replayed end to end.
- Terminal results match Clojure.
- [x] Removed `run_ice_windows_enabled` flag — corp rez window is always active during runs.
- [x] Fixed `advanceApproachIcePhase` early-return bug (stale "run" prompt state was blocking position advance after subroutine resolution).
- [x] `Brân 1.0` fully implemented:
  - [x] on-encounter: lose 1 click to break 1 subroutine (bioroid break)
  - [x] Subroutine 0: "Install an ice from HQ/Archives" (prompt-based with pause/resume via `pending_subroutine`)
  - [x] Subroutines 1-2: End the run
- [x] Review other M1 cards for missing partial implementations
- [x] Implement missing card abilities and mechanics
- [x] Icebreaker break subroutine parity

**Card fixes applied:**
- Fixed agenda advancement requirements: Offworld Office 3→4, Send a Message 4→5, Superconducting Hub 2→3
- Fixed ICE strengths: Diviner 2→3, Whitespace 1→0
- Fixed subroutines: Tithe sub2 ETR→corp gains 1 credit, Whitespace sub1 2cr→3cr, Whitespace sub2→conditional ETR if runner ≤6 credits, Diviner→single sub with conditional ETR on odd-cost trash, Karunā sub1→net damage then jack-out offer
- Added missing subtypes: AP on Diviner/Karunā/Tithe
- Fixed Unity break count 2→1
- Added Mayfly pump ability (1 credit: +1 strength)
- Implemented Unity variable pump (+X where X = installed icebreaker count)
- Added Palisade +2 strength on remote servers
- Superconducting Hub +2 corp hand size on score
- Pennyshaver: place 1 credit on successful run, click ability gains 1 + all hosted credits
- Mayfly end-of-run trash (trashes_after_break)
- Advance prompt only shows advanceable cards (agendas, advanceable assets)

**Known deferred items (not blocking M2):**
- Nico Campaign auto-trigger at start of turn (currently click action; needs corp phase 12 timing)
- Nico Campaign draw 1 on empty
- Red Team credits on successful run (currently taken before run)
- Red Team server-not-run-this-turn restriction
- Seamless Launch not-installed-this-turn restriction
- Verbal Plasticity first-per-turn restriction
- Carmen install cost reduction
- HQ multi-access flow (Jailbreak + Docklands Pass combo)

### M3: Intermediate Matchup Parity

- Intermediate decks supported.
- Broader card/mechanic coverage.

### M4: OpenSpiel Adapter

- Stable C ABI from Zig.
- C++ OpenSpiel wrapper.

## Open Questions

- Should the first deterministic harness compare full hidden state, or only side observations plus terminal outcomes?
- Do we want a human-readable fixture format first, or a compact binary format from the start?
- Should chance events be represented as explicit OpenSpiel-style chance nodes in Zig, or sampled internally with a seeded RNG and exported as sampled outcomes?
