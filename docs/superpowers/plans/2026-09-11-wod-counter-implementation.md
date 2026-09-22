# WOD Round Counter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Apple-native iOS app that runs predefined Girl/Hero WODs (or custom ones) in two modes — for-time (count rounds) and top-time (auto-stop at target) — using a per-rep cycling counter, with local SwiftData storage plus optional iCloud sync and a results/history view.

**Architecture:** SwiftUI views present state; a pure, unit-tested `WODSimulator` owns all WOD progression logic (round/block/rep transitions, descending & repeating schemes, pause/active-time); a `ResultsService` computes windowed stats and PRs; a `WorkoutTimerService` bridges the simulator to the real clock and persists results; SwiftData models a stable `Movement` catalog with per-WOD `Exercise` doses and explicit `RoundBlock`s.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Concurrency, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-11-wod-counter-design.md`

## Global Constraints

- Platform: iOS, Apple-native only (no web/Android). Deployment target **iOS 17.0**.
- Stack: **SwiftUI + SwiftData + Swift Concurrency**.
- Data: **offline-first**; workout data never leaves the device. **iCloud/CloudKit sync is opt-in** via Settings (public database, no account, no server).
- Model rule: `Movement`s are the shared catalog; `Exercise`s are per-WOD prescriptions with a **pre-rendered `displayLabel`** so synced data renders identically on every device (no re-formatting at render time).
- YAGNI: ship only what the spec requires. Streaks/goals/Apple Watch/Health/Sign-In are deferred (spec §11).
- TDD: every task ends green. Frequent commits (one per task), meaningful messages.
- Test target rule: In Xcode 16 with file-system synchronization, all test files must reside under `WODCounterTests/`.
- No placeholders. Distanced-only exercises (runs, row, bike, rope) have **no `reps`** — treat as an effective rep quota of **1** so the engine stays uniform; `displayLabel` carries the distance.
- Murph seed is **bodyweight-only** 100/200/300 (run-based variant deferred).
- Every `@Model` in `Models/`. Every service a separate file. Small, focused files.

---

## File Structure

```
WODCounter/
├── WODCounterApp.swift                 # @main, ModelContainer, SeedMigration
├── AppModel.swift                      # Observable app state & navigation coordinator
├── ServiceFactory.swift                # Factory for creating timer services with ModelContext
├── Models/
│   ├── ExecutionMode.swift
│   ├── Movement.swift
│   ├── Exercise.swift
│   ├── RoundBlock.swift
│   ├── Workout.swift
│   └── WorkoutRecord.swift
├── Support/
│   ├── BenchmarkSeed.swift             # in-memory seed data (built-in WODs)
│   ├── SeedMigration.swift             # idempotently inserts built-ins into the container
│   └── Format.swift                    # duration & timer formatting utilities
├── Models/Sim/
│   ├── TimerEvent.swift
│   ├── SessionSnapshot.swift           # published value type of current timer state
│   └── WODSimulator.swift              # pure progression engine (multi-block state machine)
├── Services/
│   ├── ResultsService.swift            # windowed aggregation, PR detection
│   └── WorkoutTimerService.swift       # simulator + real clock + persistence on finish
└── Views/
    ├── HomeView.swift
    ├── WODDetailView.swift
    ├── SettingsView.swift
    ├── TimerView.swift
    ├── ResultsCardView.swift           # shareable results card component
    ├── ResultsView.swift
    └── CreateWODView.swift
```

## Task Right-Sizing

Each task = one focused deliverable with its own test cycle:
- Tasks 0–2: Storage & domain models.
- Task 3: Pure progression engine (`WODSimulator`).
- Task 4: `ResultsService` (pure aggregation over SwiftData records).
- Task 5: `WorkoutTimerService` & App state (clock ticker, pause handling, record persistence via PR check).
- Tasks 6–9: UI layers (Home/Detail/Settings → Timer → Results/Share Card → Custom WOD Builder).

---

### Task 0: Project scaffold, app entry, ModelContainer, seed migration

**Goal:** A compiling SwiftUI app with an empty SwiftData container ready to receive built-in WODs.

**Files:**
- Create: `WODCounter/WODCounterApp.swift`
- Create: `WODCounter/Support/SeedMigration.swift`

**Interfaces:**
- Produces: a shared `modelContainer` instance (acquired via a static + `@MainActor`) and an idempotent `applySeed(to:)` that inserts built-in workouts only if none exist.

- [x] **Step 1:** In `WODCounterApp.swift`, create `@main struct WODCounterApp: App` with a `WindowGroup { HomeView() }`. Build `modelContainer(for: [Movement.self, Exercise.self, RoundBlock.self, Workout.self, WorkoutRecord.self], isStoredInMemoryOnly: false)` wrapped in a static `@MainActor static let shared`. Add a `RootView` split: sidebar/tab showing Results entry when history exists.
- [x] **Step 2:** In `Support/SeedMigration.swift`, write `enum SeedMigration { static func applySeed(to container: ModelContainer) }` that calls `container.mainContext` to insert the built-in WODs (initially just **Cindy** and **Murph**) from `BenchmarkSeed`. Guard with a check: if any `Workout` with `isBuiltin == true` already exists, do nothing (idempotent). Use `BenchmarkSeed.cindy()` / `BenchmarkSeed.murph()` factory funcs.
- [x] **Step 3:** Build & run; confirm it launches on the simulator with no compile errors.

---

### Task 1: SwiftData models

**Goal:** All `@Model` classes matching the spec's domain model.

**Files:**
- Create: `WODCounter/Models/ExecutionMode.swift`
- Create: `WODCounter/Models/Movement.swift`
- Create: `WODCounter/Models/Exercise.swift`
- Create: `WODCounter/Models/RoundBlock.swift`
- Create: `WODCounter/Models/Workout.swift`
- Create: `WODCounter/Models/WorkoutRecord.swift`

**Interfaces:**
- Consumes: nothing external (Task 0 container already lists these types; Task 0 must match this exact list).
- Produces: these types, which Tasks 2–9 consume.

- [x] **Step 1:** Write all six model files matching the domain specifications.
- [x] **Step 2:** Add a test `WODCounterTests/Models/ModelSmokeTests.swift` asserting `Exercise.effectiveReps` = reps or 1; and that `@Model` classes conform to `@Model` (compiles against the container).
- [x] **Step 3:** Run tests; confirm pass. Commit.

---

### Task 2: Benchmark seed data + migration

**Goal:** In-memory catalog of built-in WODs and an idempotent inserter.

**Files:**
- Create: `WODCounter/Support/BenchmarkSeed.swift`
- Modify: `WODCounter/Support/SeedMigration.swift`

**Interfaces:**
- Consumes: Task 1 `Workout`, `RoundBlock`, `Exercise`, `Movement`.
- Produces: `BenchmarkSeed.cindy()`, `BenchmarkSeed.murph()`, and factory helpers for the full seed set (Fran, Angie, Grace, Diane, Helen, DT) — all return `Workout`.

- [x] **Step 1:** In `BenchmarkSeed.swift`, implement factory functions for all 8 benchmark WODs with pre-rendered `displayLabel`s and explicit `RoundBlock` structures.
- [x] **Step 2:** Modify `SeedMigration` to call these factories and insert into the container, deduping Movements by `name` (`.unique`) with an insert-or-update, and deduping `Workout`/`RoundBlock`/`Exercise` idempotently.
- [x] **Step 3:** Add `WODCounterTests/Support/BenchmarkSeedTests.swift` to verify block/rep counts and migration idempotency. Run tests and commit.

---

### Task 3: `WODSimulator` — pure progression engine

**Goal:** The fully unit-tested, deterministic WOD progression core — independent of SwiftData, clock, or UI.

**Files:**
- Create: `WODCounter/Models/Sim/TimerEvent.swift`
- Create: `WODCounter/Models/Sim/SessionSnapshot.swift`
- Create: `WODCounter/Models/Sim/WODSimulator.swift`
- Create: `WODCounterTests/Sim/WODSimulatorTests.swift`

**Interfaces:**
- Consumes: Task 1 `Workout`, `RoundBlock`, `Exercise`, `ExecutionMode`.
- Produces: `WODSimulator` (stateful struct accepting `Workout`), `TimerEvent`, and `SessionSnapshot`. Exact semantics:
  - **Round** = one play of a `RoundBlock`. **roundsCompleted** increments per play.
  - `advanceRep()` (+1 to current exercise's `repsDonePerExercise`). If that exercise reaches `effectiveReps`, advance to the next exercise in the block; when the block's last exercise is done, `completeBlock()`.
  - **completeBlock()**: `roundsCompleted += 1`; if this was the last block → `phase = .finished` (reason `.goalReached`). Else for-time: if `activeElapsed >= minutes*60` → `phase = .finished` (`.clockExpired`); else advance to next block with optional `restAfterBlock`.
  - `startRest()` / `endRest()` / `advanceTime(_ dt, active:)` / `finish()` (`.manual`).
  - Derived: `currentBlock`, `currentExercise`, `currentRepProgress`, `isClockExpired`, `canAutoStop`, `snapshot`.

- [ ] **Step 1:** Write `TimerEvent.swift`, `SessionSnapshot.swift`, and `WODSimulator.swift` adhering to the multi-block engine contract.
- [ ] **Step 2:** Write `WODCounterTests/Sim/WODSimulatorTests.swift` covering:
  - Cindy for-time: 5/10/15 reps cycling → roundsCompleted == 1; repeat cycles; loops until clock.
  - Murph top-time: 100/200/300 → `canAutoStop == true`; 1 round, active time tracks.
  - Fran top-time: 21/15/9 (3 blocks) → roundsCompleted == 3 and auto-stop.
  - DT top-time: 5 repeats of 1 block → roundsCompleted == 5 and auto-stop.
  - Helen for-time repeat=3 → 3 rounds counted.
  - Distanced-only exercise (`reps == nil`): advances with `effectiveReps == 1`.
- [ ] **Step 3:** Run tests under `WODCounterTests/Sim/`, ensure green. Commit.

---

### Task 4: `ResultsService` & Formatters — windowed stats + PR detection

**Goal:** Pure aggregation and PR detection over SwiftData records, plus shared formatting utilities.

**Files:**
- Create: `WODCounter/Support/Format.swift`
- Create: `WODCounter/Services/ResultsService.swift`
- Create: `WODCounterTests/Services/ResultsServiceTests.swift`

**Interfaces:**
- Consumes: Task 1 `WorkoutRecord`, `Workout`, `ExecutionMode`.
- Produces: `Format` (duration/timer formatters), `WindowSummary`, `history(for:window:kind:)`, `summary(for:window:kind:)`, and `isNewPR(...)`.

- [ ] **Step 1:** Write `Support/Format.swift` containing `duration(_ seconds:) -> String` and `timer(_ minutes:) -> String`.
- [ ] **Step 2:** Implement `ResultsService(context:)`. `history(for workout:window:kind:)` queries `#Predicate<WorkoutRecord>` sorted descending by date. `summary(...)` calculates total count, PR count, best rounds, best active time, and average active time. `isNewPR(...)` detects if an attempt is better than prior bests.
- [ ] **Step 3:** Write `WODCounterTests/Services/ResultsServiceTests.swift`: test window filtering (7/30/90 days), PR evaluation for both for-time and top-time records, and delta calculations. Run green. Commit.

---

### Task 5: `WorkoutTimerService` — clock + persistence + app model

**Goal:** Bridge the pure simulator to the real clock and SwiftData, persisting a `WorkoutRecord` on finish using `ResultsService` for PR evaluation.

**Files:**
- Create: `WODCounter/Services/WorkoutTimerService.swift`
- Create: `WODCounter/AppModel.swift`
- Create: `WODCounter/ServiceFactory.swift`
- Create: `WODCounterTests/Services/WorkoutTimerServiceTests.swift`

**Interfaces:**
- Consumes: Task 3 `WODSimulator`, `TimerEvent`, `SessionSnapshot`; Task 4 `ResultsService`; Task 1 models.
- Produces: `WorkoutTimerService: ObservableObject`, `AppModel`, and `ServiceFactory`.

- [ ] **Step 1:** Create `WorkoutTimerService` holding a `WODSimulator` and a `Task`-based 1-second ticker that advances time and republishes `SessionSnapshot`. Injectable clock for testability.
- [ ] **Step 2:** On `finish()`: compute active vs paused time, evaluate PR with `ResultsService.isNewPR(...)`, construct `WorkoutRecord`, and persist via the injected completion hook.
- [ ] **Step 3:** Write `AppModel` (`@Observable`, navigation state, `ResultsService` reference) and `ServiceFactory` (`makeTimerService(for:)` saving to `ModelContext`).
- [ ] **Step 4:** Write `WODCounterTests/Services/WorkoutTimerServiceTests.swift` with fake clock: test ticking, pause accumulating, and record persistence. Run green. Commit.

---

### Task 6: Home, WOD Detail, Settings views

**Goal:** WOD library (grouped Girl/Hero + Custom), detail screen, settings (iCloud toggle, window default).

**Files:**
- Create: `WODCounter/Views/HomeView.swift`
- Create: `WODCounter/Views/WODDetailView.swift`
- Create: `WODCounter/Views/SettingsView.swift`

**Interfaces:**
- Consumes: Task 1 models, Task 4 `ResultsService`, Task 5 `AppModel` / `ServiceFactory`.
- Produces: library navigation → detail → Start (routes to `TimerView`) and History (routes to `ResultsView`).

- [ ] **Step 1:** `HomeView`: `@Query` all `Workout`; sort builtins first, then Custom; grouped by category ("Girl", "Hero", "Custom"); tap navigates to `WODDetailView(workout:)`.
- [ ] **Step 2:** `WODDetailView`: shows name, description, category, mode symbol, scheme breakdown (each `RoundBlock` with `displayLabel`s), **Start** button, and **History** button.
- [ ] **Step 3:** `SettingsView`: iCloud sync toggle (`@AppStorage`) with clean container reload semantics and time-window default selector.
- [ ] **Step 4:** Build and test view navigation. Commit.

---

### Task 7: `TimerView` — the core screen

**Goal:** Live timer with the per-rep cycling counter, pause/resume, rest indicator, and completion trigger.

**Files:**
- Create: `WODCounter/Views/TimerView.swift`

**Interfaces:**
- Consumes: Task 5 `WorkoutTimerService`, `SessionSnapshot`; Task 4 `Format`.
- Produces: interactive full-screen workout timer.

- [ ] **Step 1:** Implement `TimerView` displaying prominent clock (countdown for for-time, count-up for top-time), current exercise `displayLabel`, and rep quota progress.
- [ ] **Step 2:** Wire tap-to-advance rep button, Pause/Resume, and Finish controls.
- [ ] **Step 3:** On finish/completion, present results sheet overlay. Test and smoke-run Cindy and Murph flows. Commit.

---

### Task 8: `ResultsView` & Share Card

**Goal:** History view with windowed summary, per-WOD bests/PRs/chart, and shareable results card.

**Files:**
- Create: `WODCounter/Views/ResultsCardView.swift`
- Create: `WODCounter/Views/ResultsView.swift`

**Interfaces:**
- Consumes: Task 4 `ResultsService`, `Format`; Task 1 models.
- Produces: results dashboard and shareable image card.

- [ ] **Step 1:** Create `ResultsCardView` displaying workout badge, completed rounds or time, PR tag, and date.
- [ ] **Step 2:** Create `ResultsView` with 7d/30d/90d/all window tabs, summary banner, per-WOD bests with Δ vs previous attempt, and Swift Charts progression graph.
- [ ] **Step 3:** Test results filtering and share sheet integration. Commit.

---

### Task 9: `CreateWODView` — custom workout builder

**Goal:** Interactive builder for creating, configuring, and saving custom WODs.

**Files:**
- Create: `WODCounter/Views/CreateWODView.swift`

**Interfaces:**
- Consumes: Task 1 models (`Movement`, `Exercise`, `RoundBlock`, `Workout`, `ExecutionMode`).
- Produces: custom `Workout` stored in SwiftData.

- [ ] **Step 1:** Build `CreateWODView`: select movements from catalog, set reps/weight/distance/units, set execution mode and time caps, configure repeat counts and rest intervals.
- [ ] **Step 2:** Pre-render `Exercise.displayLabel` for every exercise, assemble `RoundBlock`s and `Workout`, and insert into `@Environment(\.modelContext)`.
- [ ] **Step 3:** Verify that newly created WODs immediately appear under "Custom" on `HomeView` and can be run via `TimerView`. Run full test suite (`swift test`). Commit.

---

## Self-Review

1. **Dependency order:** Models (T1) → Seed (T2) → Pure Engine (T3) → Results Service & Format (T4) → Timer Service & App Model (T5) → Nav & Detail Views (T6) → Timer View (T7) → Results & Share Card (T8) → Custom Builder (T9). No forward references or circular dependencies.
2. **Xcode 16 compliance:** All test paths mapped directly to `WODCounterTests/`.
3. **No placeholders:** Full signatures, structs, and contracts explicitly defined across tasks.
