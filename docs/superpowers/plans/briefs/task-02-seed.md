# Task 2 — Benchmark seed data + migration

**Deliverable:** In-memory catalog of built-in WODs (factory functions) and an idempotent inserter that drops them into the container.

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 8 (seed set).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 8 (full seed list + exact prescriptions), § 5 (models).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 2.
- **Siblings:** Task 1 produced the models — consume them exactly. Task 0 produced `SeedMigration.applySeed` (refactor it to call the factories here). Task 3 (simulator) is independent.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. **SwiftUI + SwiftData**. YAGNI — seed exactly the listed WODs.
- **TDD:** end green, commit once, no placeholders.

## Files
- **Create:** `WODCounter/Support/BenchmarkSeed.swift`
- **Modify:** `WODCounter/Support/SeedMigration.swift` (from Task 0) — call the factories here.

## Interfaces (produces)
- Factory funcs, each returning a `Workout`: `cindy()`, `murph()`, and the full set: `frank()`, `angie()`, `grace()`, `diane()`, `helen()`, `dt()`.
- (SeedMigration now produces the idempotent insert from these.)

## Workouts to build (exact prescriptions)
| Func | Category | Mode | Minutes | Blocks / reps |
|---|---|---|---|---|
| `cindy()` | Girl | forTime | 20 | 1 block: [5 Pull-ups, 10 Push-ups, 15 Air Squats] (all Bodyweight) |
| `murph()` | Hero | topTime | nil (unlimited) | 1 block, repeat=1: [100 Pull-ups, 200 Push-ups, 300 Air Squats] (Bodyweight) |
| `frank()` | Hero | topTime | — | 3 blocks: {21 Thrusters(Barbell,"95 lb")+21 Pull-ups}, {15…}, {9…}. Thrusters category Power. |
| `angie()` | Hero | topTime | — | 1 block single pass: [100 Pull-ups, 100 Push-ups, 100 Sit-ups, 100 Air Squats] |
| `grace()` | Girl | topTime | — | 1 block: [30 Clean & Jerk (Barbell,"135 lb")] category Strength |
| `diane()` | Girl | topTime | — | 3 blocks: {21 Deadlifts(225)+21 HSPU},{15…},{9…}. Deadlift category Strength. |
| `helen()` | Girl | topTime | — | 1 block, repeat=3: [400m Run, 21 KB Swings(Kettlebell,"53/35 lb"), 12 Pull-ups]. Run: distance "400 m", distanceUnit "m". |
| `dt()` (Dan Turek) | Hero | topTime | — | 1 block, repeat=5: [12 Deadlifts(225), 9 Hang Power Cleans(155 lb), 6 Push Jerks(155 lb)] |

- Movement rows share the `Movement` catalog (Task 1). Dedup Movements by `name` (`.unique`) — reuse or insert-or-update, don't create duplicates across WODs (e.g. "Pull-ups" once).
- `displayLabel` is **pre-rendered** per `Exercise` (e.g. "21 Thrusters (95 lb)"). Do not reformat in the UI later — this task's labels must already be correct.
- `category`: WOD category is "Girl"/"Hero"; each Movement may also carry a category (e.g. Thrusters → "Power"). Set both.

## Steps
- [ ] **Step 1:** Write `BenchmarkSeed.swift` with all eight factories returning fully-formed `Workout` objects (movements + exercises + blocks, with `weight`/`distance`/`displayLabel` filled).
- [ ] **Step 2:** Modify `SeedMigration.applySeed(to:)` to call these factories and insert into `container.mainContext`, deduping Movements by `name` and `Workout`/`RoundBlock`/`Exercise` by derived identity so re-running is idempotent (no duplicates).
- [ ] **Step 3:** Write `Tests/Support/BenchmarkSeedTests.swift` asserting correct block/rep counts — e.g. `assert(cindy().blocks.count == 1 && cindy().blocks[0].exercises.map { $0.reps } == [5,10,15])`; `dt().playTarget == 5` (or equivalent); `helen()` run exercise has `distance == "400 m"` and `reps == nil`. Commit.

> Note: the plan has a typo `frank()`/`frank` — the WOD is **Fran** (`frank()` factory).

## Acceptance
- All eight WODs build correctly (counts/reps/block-structure) per the table. `displayLabel`s are pre-rendered. `SeedMigration` is idempotent (running twice inserts once). Tests green. One commit.
