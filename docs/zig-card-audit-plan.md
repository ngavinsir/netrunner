# Zig Card Audit Plan

This file tracks the current card-audit backlog for the Zig engine.

## Completed Audit Items

- [x] `Key Performance Indicators`
  Added the `Draw 1 card. Shuffle 1 card from HQ into R&D` branch and local branch coverage.

- [x] `Measured Response`
  `can_play` now requires both threat level 4 and a successful Runner run during the previous turn.

- [x] `Scrounge`
  Added install-from-heap, optional bottom-of-stack follow-up, and cancel-path coverage.

- [x] `Synapse Global: Faster than Thought`
  `runner_lose_tag` now routes through the shared event queue and opens the free install prompt correctly.

- [x] `BANGUN: When Disaster Strikes`
  Installed agendas enter faceup and accessing a faceup installed agenda now applies the damage/tag punishment.

- [x] `Madani`
  Added the host-from-grip branch and once-per-turn hosted-program install branch without adding card-specific engine enums.

## Completed Earlier In This Sweep

- [x] `Predictive Planogram` explicit branch parity
- [x] `Public Trail` explicit branch parity
- [x] `Wildcat Strike` explicit branch parity
- [x] `Peer Review` oracle-aligned private-card prompt flow

## Verification

- [x] `mise exec -- zig test zig/src/engine/game.zig`
- [x] `mise exec -- zig test zig/src/root.zig`
