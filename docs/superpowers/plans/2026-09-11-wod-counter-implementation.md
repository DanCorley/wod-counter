# WOD Round Counter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Apple-native iOS app that runs predefined Girl/Hero WODs (or custom ones) in two modes — for-time (count rounds) and top-time (auto-stop at target) — using a per-rep cycling counter, with local SwiftData storage plus optional iCloud sync and a results/history view.

**Architecture:** SwiftUI views present state; a pure, unit-tested `WorkoutSimulator` owns all WOD progression logic (round/block/rep transitions, descending & repeating schemes, pause/active-time); a `WorkoutTimerService` bridges the simulator to the real clock and persists results; a `ResultsService` computes windowed stats and PRs. SwiftData models a stable `Movement` catalog with per-WOD `Exercise` doses and explicit `RoundBlock`s.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Concurrency, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-11-wod-counter-design.md`

## Global Constraints

- Platform: iOS, Apple-native only (no web/Android). Deployment target **iOS 17.0**.
- Stack: **SwiftUI + SwiftData + Swift Concurrency**.
- Data: **offline-first**; workout data never leaves the device. **iCloud/CloudKit sync is opt-in** via Settings (public database, no account, no server).
- Model rule: `Movement`s are the shared catalog; `Exercise`s are per-WOD prescriptions with a **pre-rendered `displayLabel`** so synced data renders identically on every device (no re-formatting at render time).
- YAGNI: ship only what the spec requires. Streaks/goals/Apple Watch/Health/Sign-In are deferred (spec §11).
- TDD: every task ends green. Frequent commits (one per task), meaningful messages.
- No placeholders. Distanced-only exercises (runs, row, bike, rope) have **no `reps`** — treat as an effective rep quota of **1** so the engine stays uniform; `displayLabel` carries the distance.
- Murph seed is **bodyweight-only** 100/200/300 (run-based variant deferred).
- Every `@Model` in `Models/`. Every service a separate file. Small, focused files.

---

## File Structure

```
WODCounter/
├── WODCounterApp.swift                 # @main, ModelContainer, SeedMigration
├── Models/
│   ├── ExecutionMode.swift
│   ├── Movement.swift
│   ├── Exercise.swift
│   ├── RoundBlock.swift
│   ├── Workout.swift
│   └── WorkoutRecord.swift
├── Support/
│   ├── BenchmarkSeed.swift             # in-memory seed data (built-in WODs)
│   └── SeedMigration.swift             # idempotently inserts built-ins into the container
├── Models/Sim/
│   ├── TimerEvent.swift
│   └── WODSimulator.swift              # pure progression engine (no SwiftData)
├── Services/
│   ├── WorkoutTimerService.swift       # simulator + real clock + persistence on finish
│   └── ResultsService.swift            # windowed aggregation, PR detection
└── Views/
    ├── HomeView.swift
    ├── WODDetailView.swift
    ├── TimerView.swift
    ├── ResultsView.swift
    ├── CreateWODView.swift
    └── SettingsView.swift
```

## Task Right-Sizing

Each task = one focused deliverable with its own test cycle. Tasks 0–2 build storage + data. Task 3 is the pure engine (the highest-value test surface). Task 4 wires the clock/persistence. Task 5 does results. Tasks 6–8 are UI, layered by feature.

---

### Task 0: Project scaffold, app entry, ModelContainer, seed migration

**Goal:** A compiling SwiftUI app with an empty SwiftData container ready to receive built-in WODs.

**Files:**
- Create: `WODCounter/WODCounterApp.swift`
- Create: `WODCounter/Support/SeedMigration.swift`

**Interfaces:**
- Produces: a shared `modelContainer` instance (acquired via a static + `@MainActor`) and an idempotent `applySeed(to:)` that inserts built-in workouts only if none exist.

- [ ] **Step 1:** In `WODCounterApp.swift`, create `@main struct WODCounterApp: App` with a `WindowGroup { HomeView() }`. Build `modelContainer(for: [Movement.self, Exercise.self, RoundBlock.self, Workout.self, WorkoutRecord.self], isStoredInMemoryOnly: false)` wrapped in a static `@MainActor static let shared`. Add a `RootView` split: sidebar/tab showing Results entry when history exists.
- [ ] **Step 2:** In `Support/SeedMigration.swift`, write `enum SeedMigration { static func applySeed(to container: ModelContainer) }` that calls `container.mainContext` to insert the built-in WODs (initially just **Cindy** and **Murph**) from `BenchmarkSeed`. Guard with a check: if any `Workout` with `isBuiltin == true` already exists, do nothing (idempotent). Use `BenchmarkSeed.cindy()` / `BenchmarkSeed.murph()` factory funcs.
- [ ] **Step 3:** Build & run; confirm it launches on the simulator with no compile errors.

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
- Produces: these types, which Tasks 2, 3, 4, 6 consume. Exact fields below are the contract.

`ExecutionMode`
```swift
enum ExecutionMode: String, Codable, CaseIterable, Sendable {
    case forTime, topTime
    var title: String { self == .forTime ? "For Time" : "Top Time" }
    var symbol: String { self == .forTime ? "timer" : "flag.checkered" }
}
```

`Movement`
```swift
@Model
final class Movement {
    @Attribute(.unique) var name: String
    var equipment: String?
    var category: String?
    var iconName: String?
    init(name: String, equipment: String? = nil, category: String? = nil, iconName: String? = nil) {
        self.name = name; self.equipment = equipment; self.category = category; self.iconName = iconName
    }
}
```

`Exercise`
```swift
@Model
final class Exercise {
    @Relationship var movement: Movement?
    var reps: Int?                       // nil = distanced-only (effective quota 1)
    var weight: String?
    var distance: String?
    var distanceUnit: String?
    var restSeconds: Int?                // inter-set/rest within the scheme (optional)
    var displayLabel: String?            // pre-rendered "21 Thrusters (95 lb)"
    init(movement: Movement? = nil, reps: Int? = nil, weight: String? = nil,
         distance: String? = nil, distanceUnit: String? = nil, restSeconds: Int? = nil, displayLabel: String? = nil) {
        self.movement = movement; self.reps = reps; self.weight = weight; self.distance = distance
        self.distanceUnit = distanceUnit; self.restSeconds = restSeconds; self.displayLabel = displayLabel
    }
    var effectiveReps: Int { reps ?? 1 }
}
```

`RoundBlock`
```swift
@Model
final class RoundBlock {
    @Relationship(deleteRule: .cascade, inverse: \Workout.blocks) var exercises: [Exercise]
    var repeatTimes: Int                 // 0 = loop until clock (for-time); N = play N (top-time); 1 = single pass
    var restAfterBlock: Int?             // seconds to rest after this block (Barbara-style); nil = continuous
    init(repeatTimes: Int, restAfterBlock: Int? = nil) { self.repeatTimes = repeatTimes; self.restAfterBlock = restAfterBlock }
}
```

`Workout`
```swift
@Model
final class Workout {
    var name: String
    var description: String?
    var category: String?                // "Girl" | "Hero" | "Custom"
    var mode: ExecutionMode
    @Relationship(deleteRule: .cascade, inverse: \WorkoutRecord.workout) var records: [WorkoutRecord]
    @Relationship(deleteRule: .cascade, inverse: \Workout.blocks) var blocks: [RoundBlock]
    var isBuiltin: Bool
    var forTimeMinutes: Int?             // nil = unlimited (Murph); e.g. 20 (Cindy)
    var createdAt: Date
    var updatedAt: Date
    init(name: String, mode: ExecutionMode, isBuiltin: Bool, forTimeMinutes: Int? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.name = name; self.mode = mode; self.isBuiltin = isBuiltin; self.forTimeMinutes = forTimeMinutes
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}
```

`WorkoutRecord`
```swift
@Model
final class WorkoutRecord {
    @Attribute(.unique) var id: UUID
    var workout: Workout?
    var date: Date
    var kind: String                     // "rounds" | "time"
    var roundsCompleted: Int
    var totalReps: Int
    var elapsedTime: TimeInterval
    var pausedTime: TimeInterval
    var activeTime: TimeInterval        // elapsedTime - pausedTime
    var isPR: Bool
    var notes: String?
    init(id: UUID = UUID(), workout: Workout?, date: Date = Date(), kind: String,
         roundsCompleted: Int, totalReps: Int, elapsedTime: TimeInterval,
         pausedTime: TimeInterval, activeTime: TimeInterval, isPR: Bool, notes: String? = nil) {
        self.id = id; self.workout = workout; self.date = date; self.kind = kind
        self.roundsCompleted = roundsCompleted; self.totalReps = totalReps
        self.elapsedTime = elapsedTime; self.pausedTime = pausedTime; self.activeTime = activeTime
        self.isPR = isPR; self.notes = notes
    }
}
```

- [ ] **Step 1:** Write all six model files exactly above.
- [ ] **Step 2:** Add a test `Tests/Models/ModelSmokeTests.swift` asserting `Exercise.effectiveReps` = reps or 1; and that `@Model` classes conform to `@Model` (compiles against the container).
- [ ] **Step 3:** Run `swift test` (via `xcodebuild test` or a testable ShellTarget) — confirm pass. Commit.

> **Test infra note:** SwiftData models need an in-memory `ModelContainer` for unit tests. Either (a) configure Xcode to build tests with a `#if DEBUG` container, or (b) build a small `#testable` target exposing models/services. Prefer option (b) if the project is already a shell; otherwise option (a). Whatever you choose, the same code runs in the app.

---

### Task 2: Benchmark seed data + migration

**Goal:** In-memory catalog of built-in WODs and an idempotent inserter.

**Files:**
- Create: `WODCounter/Support/BenchmarkSeed.swift`
- Create: `WODCounter/Support/SeedMigration.swift` (from Task 0) — modify to use `BenchmarkSeed`.

**Interfaces:**
- Consumes: Task 1 `Workout`, `RoundBlock`, `Exercise`, `Movement`.
- Produces: `BenchmarkSeed.cindy()`, `BenchmarkSeed.murph()`, and factory helpers for the full seed set (Fran, Angie, Grace, Diane, Helen, DT) — all return `Workout`.

- [ ] **Step 1:** In `BenchmarkSeed.swift`, create helper funcs. Movement names reference the Movement catalog (seeds create movements + exercises together; `Movement` rows may be re-created without duplication — keep a tiny cache keyed by `name` within a seed call, or rely on Task 0/2 to dedupe via unique constraint). Implement:
  - `cindy()`: Girl, forTime, forTimeMinutes=20, one block: [Exercise(5 Pull-ups), (10 Push-ups), (15 Air Squats)] as Movement rows: Pull-ups (Bodyweight), Push-ups (Bodyweight), Air Squats (Bodyweight).
  - `murph()`: Hero, topTime, nil minutes, one block repeat=1: [100 Pull-ups, 200 Push-ups, 300 Air Squats].
  - `frank()`/`frank`: Hero→ topTime, 3 blocks: {21 Thrusters(95 lb)+21 Pull-ups}, {15…}, {9…}. Thrusters equipment Barbell weight "95 lb", category Power.
  - `angie()`: topTime, 1 block single pass: [100 Pull-ups, 100 Push-ups, 100 Sit-ups, 100 Air Squats].
  - `grace()`: topTime, 1 block: [30 Clean & Jerk (135 lb)] category Strength.
  - `diane()`: topTime, 3 blocks: {21 Deadlifts(225)+21 HSPU},{15…},{9…}.
  - `helen()`: topTime, 1 block repeat=3: [400m Run, 21 KB Swings (53/35 lb), 12 Pull-ups]. Run: distance "400 m", distanceUnit "m".
  - `dt()` (Dan Turek): topTime, 1 block repeat=5: [12 Deadlifts(225), 9 Hang Power Cleans(155 lb), 6 Push Jerks(155 lb)].
- [ ] **Step 2:** Modify `SeedMigration` to call these factories and insert into the container, deduping Movements by `name` (`.unique`) with an insert-or-update, and deduping `Workout`/`RoundBlock`/`Exercise` by a derived identity (name + mode + serialized exercises/blocks) so re-running the seed is idempotent and doesn't duplicate.
- [ ] **Step 3:** Test `BenchmarkSeed` produces correct block/rep counts (a pure-data test, no SwiftData needed) — e.g. `assert(cindy().blocks.count == 1 && cindy().blocks[0].exercises.map { $0.reps } == [5,10,15])`. Commit.

---

### Task 3: `WODSimulator` — pure progression engine

**Goal:** The fully unit-tested, deterministic WOD progression core — independent of SwiftData, clock, or UI.

**Files:**
- Create: `WODCounter/Models/Sim/TimerEvent.swift`
- Create: `WODCounter/Models/Sim/WODSimulator.swift`

**Interfaces:**
- Consumes: Task 1 `Workout`, `RoundBlock`, `Exercise`.
- Produces: `WODSimulator` (stateful), `TimerEvent`, and a `SessionSnapshot` value type (consumed by Task 4). Exact semantics:
  - **Round** = one play of a `RoundBlock`. **roundsCompleted** increments per play.
  - `advanceRep()` (+1 to current exercise's `repsDonePerExercise`). If that exercise reaches `effectiveReps`, advance to the next exercise in the block; when the block's last exercise is done, `completeBlock()`.
  - **completeBlock()**: `roundsCompleted += 1`; if this was the last block → `phase = .finished` (reason `.goalReached`). Else for-time: if `activeElapsed >= minutes*60` → `phase = .finished` (`.clockExpired`); else advance to next block with optional `restAfterBlock`.
  - `startRest()` sets `restDeadline = wallClock + restAfterBlock` and `phase = .resting`. `endRest()` clears it. During resting, `advanceRep` returns `.none` (ignored) — or better, refuse via `startRest` gating; keep it lenient (advanceRep ignores reps while resting).
  - `advanceTime(_ dt, active:)`: if active && running → `wallClock += dt`; else `pausedAccumulated += dt`.
  - `finish()` → `phase = .finished` (`.manual`).
  - Derived: `currentBlock`, `currentExercise`, `currentRepProgress` (reps done in current exercise), `isClockExpired`, `canAutoStop` (top-time last exercise quota met), `snapshot`.

- [ ] **Step 1:** Write `TimerEvent` (`case none, blockCompleted, finished(FinishedReason: String)`) and the `WODSimulator` exactly per the interface.
- [ ] **Step 2:** Write `Tests/Sim/WODSimulatorTests.swift` covering:
  - Cindy for-time: after 5+10+15 reps → roundsCompleted == 1; repeat cycles; many cycles → rounds increment.
  - Murph top-time: advancing 100/200/300 → `canAutoStop == true`; `snapshot.resultRounds == 1`, `activeElapsed` tracks wallClock.
  - Fran top-time: 21/15/9 pass → roundsCompleted == 3 and auto-stop.
  - DT top-time: 5 plays of the block → roundsCompleted == 5, auto-stop.
  - Helen for-time repeat=3 → 3 rounds counted.
  - Distanced-only exercise (reps nil): advances as effectiveReps == 1.
- [ ] **Step 3:** Run tests, ensure green. Commit.

---

### Task 4: `WorkoutTimerService` — clock + persistence

**Goal:** Bridge the pure simulator to the real clock and SwiftData, persisting a `WorkoutRecord` on finish.

**Files:**
- Create: `WODCounter/Services/WorkoutTimerService.swift`

**Interfaces:**
- Consumes: Task 3 `WODSimulator`, `TimerEvent`; Task 1 models; `modelContainer`.
- Produces: `WorkoutTimerService: ObservableObject` with `@Published var session: SessionSnapshot`-equivalent fields, and start/pause/resume/finish methods. On finish it writes a `WorkoutRecord` (kind, rounds, active/elapsed/paused, isPR) via `ResultsService` for PR detection.

- [ ] **Step 1:** Create the service holding a `WODSimulator` and a `Task`-based 1-second ticker that calls `sim.advanceTime(...)` (computing active vs paused from a stored `pausedAt`) and republishes the snapshot. Methods: `start()`, `pause()`, `resume()`, `advanceRep()` (calls `sim.advanceRep()`, publishes event), `startRest()`, `endRest()`, `finish()` (writes record).
- [ ] **Step 2:** On `finish()`: compute `activeTime = wallClock - pausedAccumulated`, build `WorkoutRecord` with `isPR = ResultsService.isNewPR(...)`, insert via the app's `ModelContext`, and `sim.reset()`.
- [ ] **Step 3:** Write `Tests/Services/WorkoutTimerServiceTests.swift` using an injected fake `TimeProvider` (so no real timers): assert pause accumulates and active time subtracts it; assert finish persists a `WorkoutRecord` with correct `activeTime`.
- [ ] **Step 4:** Compile the service against the app target; quick UI smoke (navigable into TimerView is Task 7 — here just ensure it compiles and imports resolve). Commit.

---

### Task 5: `ResultsService` — windowed stats + PR detection

**Goal:** Pure functions over SwiftData to compute per-workout history, PRs, and window summaries.

**Files:**
- Create: `WODCounter/Services/ResultsService.swift`

**Interfaces:**
- Consumes: Task 1 `WorkoutRecord`, `Workout`, `ExecutionMode`; Task 4 (PR contract).
- Produces: `WindowSummary`, `recordHistory(for:window:)`, and `previousBest(for:mode:asOf:) -> Double?`.

- [ ] **Step 1:** Implement `ResultsService(context:)`. `recordHistory(for workout:window:)` uses `#Predicate<WorkoutRecord>` on `workout` + `date` range → sorted descending by date. `windowSummary(for:window:)` → workoutsCount, prsThisWindow (count where isPR), bestRounds (max roundsCompleted), bestTime (min activeTime), avgActiveTime. `previousBest(for:asOf:)` → best value before `asOf` by mode (forTime→max rounds; topTime→min activeTime).
- [ ] **Step 2:** Write `Tests/Services/ResultsServiceTests.swift`: insert several `WorkoutRecord`s for two workouts (one for-time, one top-time); assert window counts, PR detection (first is PR, subsequent improve/non-improve handled), and delta computation used by ResultsView.
- [ ] **Step 3:** Run green. Commit.

---

### Task 6: Home, WOD Detail, Settings views

**Goal:** WOD library (grouped Girl/Hero + Custom), detail screen, settings (iCloud toggle, window default).

**Files:**
- Create: `WODCounter/Views/HomeView.swift`
- Create: `WODCounter/Views/WODDetailView.swift`
- Create: `WODCounter/Views/SettingsView.swift`

**Interfaces:**
- Consumes: Task 1 models, Task 5 `ResultsService`, app `modelContainer`.
- Produces: navigable library → detail → Start (to Task 7 TimerView) and → History (Task 8).

- [ ] **Step 1:** `HomeView`: `@Query` all `Workout`; sort builtins first, then Custom; `@Namespace`-free simple list grouped by category; tap → `WODDetailView(workout:)`.
- [ ] **Step 2:** `WODDetailView`: show name, description, category, mode, block scheme (render each `RoundBlock.exercises` with `displayLabel`), for-time minutes or "races reps"; a **Start** button (navigates to `TimerView` initialized with the `Workout`); edit/delete; "History" button.
- [ ] **Step 3:** `SettingsView`: **iCloud sync toggle** (enables/disables CloudKit via container re-creation), time-window default (7/30/90/all). Implement the CloudKit opt-in: when enabled, use a `ModelConfiguration(identifier:inMemory:)` with a CloudKit description; when disabled, in-memory+persistent. Keep reversible.
- [ ] **Step 4:** Build; smoke-navigate Home→Detail→Start. Commit.

---

### Task 7: TimerView — the core screen

**Goal:** Live timer with the per-rep cycling counter, pause/resume, rest indicator, and results overlay.

**Files:**
- Create: `WODCounter/Views/TimerView.swift`

**Interfaces:**
- Consumes: Task 4 `WorkoutTimerService`, Task 1 models; the `Workout` from Task 6 detail.
- Produces: the interactive timer screen.

- [ ] **Step 1:** `TimerView(service:)`: big countdown clock (for-time) or elapsed clock (top-time); **cycling counter** showing current `RoundBlock.exercises[currentExerciseIndex]` with `currentRepProgress`/effectiveReps; **Pause/Resume**, **Finish**, **Start next block / Rest** controls; live-updating round indicator (for-time) or "finish" callout (top-time).
- [ ] **Step 2:** Results overlay: on auto-stop/clock-expiry, show result (rounds or time), **Share** (UIImage/screenshot via ImageRenderer) and dismiss.
- [ ] **Step 3:** Test the view's pure bindings minimally (e.g., that pausing stops the ticker via injected fake timer) or at least verify against the simulator in Task 3. Build and smoke-test the full Cindy run in the simulator path. Commit.

---

### Task 8: Results + Create WOD

**Goal:** History view with windowed summary, per-WOD bests/PRs/chart, and custom WOD creation.

**Files:**
- Create: `WODCounter/Views/ResultsView.swift`
- Create: `WODCounter/Views/CreateWODView.swift`

**Interfaces:**
- Consumes: Task 5 `ResultsService`; Task 1 models.
- Produces: results screen and custom WOD builder (custom WODs → `Workout` with user `RoundBlock`s).

- [ ] **Step 1:** `ResultsView`: time-window tabs (7/30/90/all); summary header ("Past 30 days: X workouts, Y PRs"); per-WOD bests list with Δ vs. previous attempt; a simple bar chart of best-over-time (Swift Charts, iOS 17); tap a WOD → its attempts; a **Share card** summarizing a selected result.
- [ ] **Step 2:** `CreateWODView`: pick movements from the catalog, set reps/weight/distance, choose mode, set for-time minutes (top-time) or reps (top-time), optional rest between rounds, name it, Save (insert `Workout` + `RoundBlock`s). Custom WODs appear on Home and sync if iCloud enabled.
- [ ] **Step 3:** Run all tests (`swift test`); final full build. Commit.

---

## Self-Review

1. **Spec coverage:** Timer modes (T3/T4/T7), per-rep cycling counter (T3/T7), pause + active-time (T3/T4), blocks/repeats/descending (T3), Girl/Hero seed incl. weights/distances (T2), local-first + opt-in iCloud (T0/T6), results/PRs/window (T5/T8), custom WODs (T8), share (T7/T8). ✓ No unimplemented spec requirement identified.
2. **Placeholder scan:** No "TBD"/"TODO"/"fill in"; all code blocks concrete; no "write tests for above".
3. **Type consistency:** `Workout.mode: ExecutionMode` (T1) used as `workout.mode == .forTime` in T3/T5; `effectiveReps` defined T1, used T3; `WorkoutRecord.activeTime` T1 used T4/T5/T7; `RoundBlock.repeatTimes` T1 used T3; `forTimeMinutes` T1 used T3; `restAfterBlock` T1 used T3/T4. Signatures match across tasks.
