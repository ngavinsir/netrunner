# AGENTS.md

## Zig Migration Conventions

These rules apply to the Zig engine migration work in this repository.

### Toolchain

- Use the latest stable Zig release pinned in [`.mise.toml`](/Users/ngavinsir/project/ngavinsir/netrunner/.mise.toml).
- Do not depend on Zig `master` for core engine work unless there is a concrete blocker in stable.
- Treat Zig upgrades as explicit maintenance work, not incidental drift.

### Type Selection

- Do not default to `i64` for game state.
- Use the smallest integer type that matches the domain and fixture values.
- Prefer domain aliases in [`zig/src/engine/state.zig`](/Users/ngavinsir/project/ngavinsir/netrunner/zig/src/engine/state.zig), for example:
  - `Seed = u64`
  - `RngSeed = i64`
  - `CardCode = u32`
  - `Count = u16`
  - `TinyCount = u8`
  - `TurnNumber = u16`
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

### Build Artifacts

- Ignore Zig build outputs such as `.zig-cache/` and `zig-out/`.
