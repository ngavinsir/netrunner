# AGENTS.md

## Zig Migration Conventions

These rules apply to the Zig engine migration work in this repository.

### Toolchain

- Use the latest stable Zig release pinned in [`.mise.toml`](/Users/ngavinsir/project/ngavinsir/netrunner/.mise.toml).
- Do not depend on Zig `master` for core engine work unless there is a concrete blocker in stable.
- Treat Zig upgrades as explicit maintenance work, not incidental drift.
- To check whether Zig code compiles, run `zig build check` from the repository root.
- To run the full Zig test suite, run `zig build test-sharded` from the [`zig/`](/Users/ngavinsir/project/ngavinsir/netrunner/zig) directory.

### Type Selection

- Do not default to `i64` for game state.
- Use the smallest integer type that matches the domain and fixture values.
- Only use type aliases when the custom type has custom methods. Otherwise, use the underlying type directly for better readability.
- Keep signed integers only where the oracle actually requires signed values. Example: exported `rng-seed` can be negative, so it stays signed.
- When reading integers from fixtures, use generic range-checked conversion helpers instead of one helper per integer size.

### Enums And Naming

- Use idiomatic Zig naming for enum tags.
- Prefer `snake_case` enum tags, not kebab-case.
- If an external format uses kebab-case or another naming style, keep Zig tags idiomatic and translate at the boundary.
- Parse external action strings explicitly rather than encoding non-idiomatic spellings into Zig identifiers.

### Fixture Parsing

- Treat exported Clojure fixtures as an external wire format.
- Match the real fixture shape instead of flattening fields prematurely.
- If the oracle exposes structured fields such as `hand-size`, `memory`, `tag`, or `bad-publicity`, model them as structured Zig types.
- Use generic integer readers with overflow checks for fixture parsing.
- Fail fast on unexpected types or out-of-range values.

### Parity Work

- Keep the Clojure exporter as the oracle until Zig can reproduce the same canonical state transitions.
- Prefer typed Zig state loaded from canonical fixtures before implementing new gameplay generation logic.
- Add parity assertions incrementally:
  - top-level game fields
  - prompt state
  - legal actions
  - ordered zones
  - player scalar state
- **All migrated gameplay logic MUST have parity tests** that verify against the Clojure oracle using `zig/src/engine/parity.zig`.
- Follow the pattern: create scenario test → replay via `fixture.replayActions()` → assert with `expectSnapshotMatches()`.
- **NEVER skip tests with error.SkipZigTest**. Tests must either pass or fail deterministically.
- **If a card is not in starting hand**: Use a different seed where it is available, or structure the test to draw/play the card through normal gameplay.
- **All tests must be deterministic**: Use fixed seeds, never rely on random card availability.

### Card-Centric Design

- All card-specific logic MUST be defined in [`zig/src/engine/catalog.zig`](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/catalog.zig) via card specs, not scattered throughout the game engine.
- Do NOT check card titles in gameplay logic methods (e.g., `if (std.mem.eql(u8, card.title, "Send a Message"))`).
- Instead, add semantic fields to card specs:
  - `CorpPlaySpec.advancement_amount` for cards like `Seamless Launch`
  - `AccessSpec.on_score_effect` for agenda scoring triggers
  - `CardSpec.card_subtypes` for icebreaker detection (Fracter, Killer, Decoder)
- Game engine methods should dispatch based on spec fields, not card identity.
- This mirrors the Clojure approach where card definitions are self-contained.
