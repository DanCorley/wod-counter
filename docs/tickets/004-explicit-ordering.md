# WTB-004 — Explicit block and exercise ordering

- **Priority:** P1
- **Estimate:** M
- **Depends on:** 001
- **Blocks:** 005, 009
- **Suggested owner:** one agent; do before 002 because both touch `WODSimulator`

## Problem

`Workout.blocks` and `RoundBlock.exercises` are SwiftData to-many relationships with no explicit order field. SwiftData does not guarantee relationship array order. The tests already acknowledge this:

> “SwiftData to-many ordering is not guaranteed” — `WODCounterTests/Sim/WODSimulatorTests.swift:23`

Yet the app depends on order everywhere:

- `WODSimulator.buildRounds` iterates `workout.blocks` directly.
- `WODSimulator.freshTasks` iterates `block.exercises` directly.
- `WorkoutSchemeView` renders blocks/exercises in array order.
- `BenchmarkSeedTests` asserts exact array order, which is brittle.
- Fran (21-15-9) and Diane depend on multi-block order being correct.

## Goal

Block and exercise order is explicit, persisted, sorted, and stable across reloads and sync.

## Scope

1. Add `sortOrder: Int` (or `order: Int`) to `RoundBlock` and `Exercise`.
   - Give it a default so existing stores can open.
   - Seed factories assign sequential values per workout/block.
   - `CreateWODView` assigns values in draft order.
2. Add ordered accessors.
   - Suggested: `Workout.orderedBlocks` and `RoundBlock.orderedExercises`.
   - Sort by `sortOrder`, with a deterministic tie-breaker for legacy rows.
3. Use ordered accessors in:
   - `WODSimulator.buildRounds` / `freshTasks`.
   - `WorkoutSchemeView`.
   - `WODDetailView`.
   - Any editor or results display that lists the scheme.
4. Backfill existing data.
   - If the app has no shipped stores, document that and assign values at creation.
   - If it does, add a one-time backfill based on the current relationship order or another stable rule, and test it.
5. Update tests to assert logical order rather than raw relationship array order.

## Result

Implemented 2026-11-06.

- Added defaulted `sortOrder: Int` to `RoundBlock` and `Exercise`; existing stores open via SwiftData lightweight migration.
- Added `Workout.orderedBlocks` and `RoundBlock.orderedExercises`. Ties fall back to the relationship array order, documented on both accessors.
- Seed factories assign sequential block/exercise `sortOrder`; `CreateWODView.makeWorkout` assigns draft order.
- `WODSimulator`, `WorkoutSchemeView`, and `WODDetailView` paths now use ordered accessors.
- Added tests for seeded/custom save+reload order, sequential seed values, Fran/Diane task and block completion order, and legacy equal-`sortOrder` fallback.
- No one-time backfill was added: legacy rows read `0` and use the array-order fallback. Rewriting them based on the same untrusted array would add risk without improving determinism.

## Acceptance criteria

- [x] Fran always renders/runs as 21 → 15 → 9 after save and reload.
- [x] Diane always renders/runs as 21 → 15 → 9.
- [x] Custom workouts preserve draft order after save and reload.
- [x] Seeded workouts have deterministic `sortOrder` values.
- [x] Tests no longer fail if SwiftData returns relationship arrays in a different order internally.
- [x] No view or engine path reads raw `workout.blocks` / `block.exercises` when order matters.

## Tests

- Save a custom workout with three exercises, reload it, assert ordered labels.
- Save/reload a multi-block workout, assert block order.
- Run a Fran/Diane-style simulation and assert block completion order.
- Add a legacy-row test with equal/default `sortOrder` values and define the expected fallback.

## Out of scope

- Drag-to-reorder UI (add it in ticket 009 if needed).
- CloudKit schema changes beyond adding a defaulted field (ticket 008).
