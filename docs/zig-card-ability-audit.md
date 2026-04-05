# Comprehensive Card Ability Audit: Zig vs Clojure

## Context

The Zig engine has 159 cards in `catalog.zig`, but many cards have abilities that exist in the Clojure reference implementation but are **missing or incomplete** in Zig. The parity test coverage manifest (147/159 cards "covered") only means those cards **appear in test games** -- it does NOT mean all their abilities are exercised. Many cards are "covered" but have unimplemented abilities.

---

## Severity Tiers

### Tier 1: CRITICAL -- Entire ability systems missing from the Zig engine

These are systemic gaps where a whole *category* of ability doesn't exist in Zig yet.

| # | Gap | Cards Affected | Description |
|---|-----|----------------|-------------|
| 1 | **`pay-credits` / `interactions` system** | Open Market, Azimat, Mahkota Langit Grid, Carnivore, Gourmand + any future cards | Clojure has `interactions: {:pay-credits ...}` letting hosted/recurring credits be spent for specific purposes (installing Jobs/Connections, trashing corp cards, etc.). Zig has NO equivalent -- credits can only be dripped, not spent contextually. |
| 2 | **`access-ability` / trash-on-access system** | Carnivore (30003), Gourmand (35007) | Clojure has `interactions: {:access-ability ...}` letting cards provide alternative trash methods during access. Zig has no equivalent. |
| 3 | **Ice bypass mechanic** | Fransofia Ward (35021) | No `bypass-ice` function exists in Zig. The encounter-ice event with optional bypass is completely missing. |

### Tier 2: HIGH -- Individual cards with major missing abilities

| # | Card (Code) | Missing Ability | Clojure Reference |
|---|-------------|----------------|-------------------|
| 4 | **Fransofia Ward (35021)** | Encounter-ice bypass event: trash self to bypass ice when corp has 15+ credits | Only has `static_abilities = rez_cost +1`, bypass is completely absent |
| 5 | **Open Market (35022)** | `pay-credits` for installing Job/Connection cards using hosted credits | Only has drip economy (`auto_take_credits`), no contextual spending |
| 6 | **Cacophony (35010)** | End-of-turn sabotage: spend 2 power counters to sabotage 3 | Only has the trigger events (agenda_stolen, runner_trash_corp_card), missing the payoff ability |
| 7 | **Humanoid Resources (35039)** | Full ability: gain 4cr, draw 3, install up to 2 cards, play an operation | Zig only does "gain 9cr, trash" which is wrong -- should be 4cr + draw 3 + install 2 + play op |
| 8 | **Byte! (35050)** | On-access ambush: pay 4cr to give 1 tag + 3 net damage | Zig has NONE -- completely empty card |
| 9 | **Phat Gioan Baotixita (35051)** | Place power counters end of turn; on agenda scored/stolen: choose 1-3 net damage spending power counters | Zig has NONE -- completely empty card |
| 10 | **Plutus (35073)** | Rez cost (forfeit agenda or trash 3 from HQ); start-of-turn: play Transaction from Archives (RFG instead of trash) | Zig has NONE -- completely empty card |
| 11 | **Mercia B4LL4RD (35045)** | End of action phase: install ice from HQ at -1cr, move self to that server | Zig has NONE -- completely empty card |
| 12 | **Mitra Aman (35056)** | On approach ice: trash self to gain 3cr + swap approached ice with ice from HQ/Archives | Zig has NONE -- completely empty card |
| 13 | **Mahkota Langit Grid (35082)** | Recurring credits for rezzing ice/assets in same server; +2 trash cost for assets in same server; lingering effect on trash | Zig only has 2 initial credit counters, missing all abilities |
| 14 | **Idiosyncresis (35061)** | Start-of-turn optional: trash self to drain runner credits (2x advancement) and gain corp credits (3x advancement) | Zig only has `can_advance` flag, missing the actual ability |
| 15 | **GAMEDRAGON Pro (35027)** | Host on icebreaker, +1 strength to host, extend pump duration to end-of-run, re-host at start of turn | Zig has NONE -- only `runner_install` |
| 16 | **Magdalene Keino-Chemutai (35024)** | On discard-to-hand-size: may install discarded program/hardware | Zig has NONE |
| 17 | **LEO Construction (35035)** | Once/turn: end the run (cost: bioroid-run-server) | Zig has NONE |
| 18 | **AU Co. (35046)** | Place power counters on corp damage/corp trash from hand; spend 2 power to look at top 3 R&D, trash 1, draw rest | Zig only places 1 power counter on agenda_scored -- missing damage/trash triggers and the top-3 ability |
| 19 | **Aggressive Trendsetting (35037)** | Complex click-interactive first-time trash event | Zig has NONE |
| 20 | **Public Access Plaza (35062)** | On-trash by runner at threat >= 2: give runner 1 tag | Zig only has start-of-turn 1cr drip, missing the on-trash tag |
| 21 | **Azimat (35029)** | 2 recurring credits restricted to trashing corp cards | Zig has 2 initial credits + reset-to-2 event but no spending restriction |

### Tier 3: MEDIUM -- Cards with partial/subtle ability gaps

| # | Card (Code) | Gap | Details |
|---|-------------|-----|---------|
| 22 | **Spin Doctor (30053)** | Verify: does it implement the remove-from-game shuffle-into-R&D ability? | Clojure: cost = remove-from-game, effect = shuffle up to 2 from Archives into R&D |
| 23 | **Knickknack O'Brian (35033)** | Ability marked used before player declines -- if player says "No action", once-per-turn is consumed | Clojure uses `:skippable true` + `:first-event?` which doesn't consume on decline |
| 24 | **Nebula Talent Management (35057)** | Verify: does back-face gain-click on first non-Terminal operation work? Does successful HQ/RD run flip back? | Complex flip identity with multiple event triggers |
| 25 | **Synapse Global (35058)** | Verify: does the activated ability (click + remove tag = gain 2cr) exist in Zig? | Clojure has both the event and the click ability |
| 26 | **BANGUN (35068)** | Verify: corp-install event with faceup agenda prompt + bluff "Nothing to see here" prompt for non-agendas | Complex multi-event identity |
| 27 | **Poetri Luxury Brands (35036)** | Verify: agenda-scored looks at top 3 R&D and can install non-op/non-agenda. Agenda-stolen installs from HQ. | Two distinct events with different behaviors |
| 28 | **Dewi Subrotoputri (35023)** | Verify: flip conditions are correct (front + 0 MU = flip to back + gain 1cr; back + MU available = flip to front + draw 1) | Complex conditional flip |
| 29 | **Hantu (35008)** | Verify: pump cost is 1 virus counter + 3 credits (not just 3cr or just virus) | Dual-cost pump |
| 30 | **Conduit (30024)** | Verify: virus counter placement is optional (player can decline) | Clojure has `:optional` with yes/no abilities |
| 31 | **Clearinghouse (30061)** | Verify: start-of-turn optional trash + meat damage (not just click ability) | Should fire automatically at start of turn |
| 32 | **Otto Campaign (35040)** | Verify: on empty, gives 2 clicks (not just trash) | Clojure: trash self AND gain 2 clicks |
| 33 | **Anthill Excavation Contract (35072)** | Verify: draws 1 card in addition to taking credits each turn | Clojure: draw 1 + take up to 4cr per turn |
| 34 | **Carmen (30015)** | Install cost bonus: -2 if successful run this turn | Verify this is implemented in Zig |
| 35 | **Bling (35006)** | Verify: can-play-as-if-in-hand for hosted cards; end-of-turn trash all hosted | Complex hosting mechanic |

### Tier 4: Cards in the 12 uncovered list (already known)

These are already tracked in the coverage manifest as `covered = false`:

| # | Card (Code) | Reason |
|---|-------------|--------|
| 36 | Scrounge (35004) | Needs program in heap |
| 37 | Shred (35005) | Not in any matchup deck |
| 38 | Lie Low (35015) | Not in any matchup deck |
| 39 | Maintenance Access (35016) | Not in any matchup deck |
| 40 | Transfer of Wealth (35017) | Not in any matchup deck |
| 41 | Illumination (35025) | Not in any matchup deck |
| 42 | Mycoweb (35053) | Not in any matchup deck |
| 43 | Bigger Picture (35065) | Requires runner tagged |
| 44 | IP Enforcement (35066) | Requires runner tagged + stolen agendas |
| 45 | Touch-ups (35067) | Incomplete (missing reveal grip + shuffle) |
| 46 | Key Performance Indicators (35077) | Needs oracle action mapping |
| 47 | Measured Response (35078) | Requires threat >= 4 + successful run last turn |

---

## Implementation Plan

### Phase 1: Implement missing card abilities (Tier 2 cards)

Work through each card with completely missing or majorly wrong abilities. For each card:
1. Read the Clojure definition as the spec
2. Implement the ability in `catalog.zig` (and `runtime.zig`/`game.zig` if new helpers are needed)
3. Add or update a parity test in `parity.zig` that exercises the ability

**Order by dependency** (implement foundational mechanics first):

#### 1a. Empty cards first (completely unimplemented)
- **Byte! (35050)** -- on-access ambush (pay 4cr for 1 tag + 3 net damage)
- **Phat Gioan Baotixita (35051)** -- power counters + agenda scored/stolen net damage
- **Plutus (35073)** -- additional rez cost + play Transaction from Archives
- **Mercia B4LL4RD (35045)** -- end-of-action-phase ice install + self-move
- **Mitra Aman (35056)** -- approach-ice trash self + gain 3cr + swap ice
- **GAMEDRAGON Pro (35027)** -- host on icebreaker + strength bonus + pump duration extension
- **Magdalene Keino-Chemutai (35024)** -- discard-to-hand-size install trigger
- **LEO Construction (35035)** -- bioroid-run-server end-the-run
- **Aggressive Trendsetting (35037)** -- interactive trash ability

#### 1b. Cards with wrong/incomplete abilities
- ~~**Humanoid Resources (35039)** -- confirmed already correct~~
- ~~**Idiosyncresis (35061)** -- add trash-self drain/gain ability~~ ✅
- ~~**AU Co. (35046)** -- add damage/trash triggers + optional start-of-turn peek~~ ✅
- ~~**Public Access Plaza (35062)** -- already complete (has on-trash tag at threat >= 2)~~ ✅
- ~~**Mahkota Langit Grid (35082)** -- recurring credit reset + on-trash lingering trash cost~~ ✅
- ~~**Cacophony (35010)** -- proper sabotage mechanic (corp chooses from HQ/R&D)~~ ✅

### Phase 2: Implement systemic ability gaps (Tier 1)

These require new engine infrastructure:

#### 2a. `pay-credits` interaction system ✅
- ~~Design a mechanism in the engine for "these credits can be spent for X purpose"~~
- ~~Implement for: Open Market (install Job/Connection), Azimat (trash corp cards), Mahkota Langit Grid (rez ice/assets in same server)~~
- Implemented `PayCreditsContext` enum + `spendPayCredits`/`availablePayCredits` helpers in game.zig
- Auto-spends hosted credits at install/trash/rez call sites; affordability checks updated

#### 2b. `access-ability` system ✅
- ~~Implement alternative trash-on-access for: Carnivore (trash 2 from hand to trash accessed free), Gourmand (trash self to trash accessed + draw 1)~~
- Already implemented: `is_access_ability` flag, `countAccessAbilities`, `appendAccessAbilityChoices`, `applyAccessAbilityChoice`

#### 2c. Ice bypass mechanic ✅
- ~~Implement `bypass-ice` in the encounter system~~
- ~~Wire up Fransofia Ward's encounter-ice event~~
- Added `bypass` flag to RunState, `bypassCurrentIce` helper, ice_encountered global event via fireEvent
- Fransofia Ward: ice_encountered handler offers trash-to-bypass when corp has 15+ credits

### Phase 3: Verify and fix Tier 3 cards

For each card listed in Tier 3, read the Zig implementation carefully and compare to Clojure. Fix any discrepancies found.

### Phase 4: Create targeted parity tests

For every card touched in Phases 1-3, create a parity test that specifically exercises the ability in question. Update the coverage manifest.

For the 12 uncovered cards (Tier 4), create new matchup decks or game states that allow testing them.

---

## Files to Modify

- `zig/src/engine/catalog.zig` -- Card definitions (primary)
- `zig/src/engine/runtime.zig` -- New helper functions for new mechanics
- `zig/src/engine/game.zig` -- Game engine changes for bypass, access-ability, pay-credits
- `zig/src/engine/state.zig` -- New types/fields if needed (e.g., interaction specs)
- `zig/src/engine/parity.zig` -- Parity tests + coverage manifest updates

## Verification

For each card fix:
1. Run `zig build test --test-filter "smoke_<card_name>"` for the specific parity test
2. Run full parity suite to ensure no regressions: `zig build test --test-filter "parity"`
3. For systemic changes (pay-credits, bypass), run all tests to check nothing breaks
