# WOD Round Counter — Implementation Handoff

> Purpose: Give an external developer everything needed to implement this iOS app from scratch.
> Read the **Spec** and this **Handoff** together. The Spec is the authority the code is argued from;
> this Handoff resolves the mechanics, file tree, tooling, and conventions.
>
> **Status:** Ready to build. All decisions below are ratified.

---

## 0. TL;DR

Build an Apple-native iOS app (SwiftUI + SwiftData) that runs predefined **Girl/Hero WODs**
(or user-custom ones) in **two modes**:

- **For-time:** fixed active clock (e.g. Cindy = 20 min); count how many **rounds** you complete.
- **Top-time:** fixed rep target; the timer **auto-stops the instant** the final rep is hit.

A **per-rep cycling counter** drives both. Local SwiftData storage + **opt-in iCloud sync**.
A results/history view shows windowed stats, per-WOD PRs, progress, and a share card.

Two requirements for the app to meet to be "done":
1. You can run **Cindy** (for-time) and **Murph** (top-time) and see correct round/time results.
2. You can build a custom WOD with weights/distance + start it + see it in history.

---

## 1. Where to start

1. Read `docs/superpowers/specs/2026-09-11-wod-counter-design.md` (the spec/requirements).
2. Read this Handoff.
3. Create the Xcode project scaffold (`ScaffoldSwiftUIApp` script, see § 4).
4. Implement tasks in order (the plan's task order). Each task ends green and committed.

---

## 2. Feature behavior (spec, in plain language)

### 2.1 Workouts
- **Predefined library** (Girl / Hero benchmarks): Cindy, Murph, Fran, Angie, Grace, Diane,
  Helen, Dan Tromeau (DT). Expandable — add more by adding seed rows (§ 8).
- **Custom WODs:** build from a movement catalog; set reps / weight / distance / equipment;
  choose mode; optional rest between rounds; name it; save (syncs if iCloud on).
- Murph is seeded **bodyweight-only** (100/200/300). Run-based Murph is supported but deferred.

### 2.2 Modes
- **For-time:** clock counts down from `minutes`. Active time = elapsed − pausedTime.
  Count completed rounds; **never auto-stops** — ends on clock expiry or Finish.
  Default Cindy `minutes = 20`.
- **Top-time:** target = the rep quotas. Clock counts up. **Auto-stops at the final rep.**
  Default Murph = bodyweight 100/200/300, single pass (1 "round").

### 2.3 Counting (the cycling rep counter)
The timer shows the **current exercise** and **reps completed for it this pass**. Tapping
**once** = one rep → counter ticks (+1). When an exercise reaches its quota, the counter
**cycles to the next exercise**. Completing every exercise in a block = **one round**
(tracked internally, no separate "round +1" button). This single mechanism serves both modes.

- A **round** = one full play of a `RoundBlock`.
- **Descending schemes** (Fran 21-15-9, Diane): each descending pass is a round → rounds = 3.
- **Repeating schemes** (Helen ×3, DT ×5): the block repeats N times → rounds = N.
- **Rest between rounds** (Barbara-style): an optional per-workout rest; continuous WODs leave it off.

### 2.4 Pause
- **Pause/Resume** freezes the clock. Paused time is tracked and **subtracted from active time**.
- **Top-time** pauses stop the active clock (reps are the driver, not time); paused time is
  still logged in history but does not reset the rep target.

### 2.5 Data
- **SwiftData**, local-first. **iCloud/CloudKit sync is opt-in** via Settings (public database,
  no account, no server). Pre-rendered `Exercise.displayLabel` ensures identical rendering on
  every device.
- History: time-window summary (default **1 month**, selectable 7/30/90/all), per-WOD bests,
  PRs, Δ vs. last attempt, a progress chart, and a share card.
- Out of scope (deferred, do NOT build now): streaks, goals, Apple Watch, Apple Health,
  Apple Sign-In, Android, web.

---

## 3. Architecture

```
SwiftUI Views (presentational)
        │  @Query / bindings / Published
        ▼
SwiftData @Model classes   (Movement, Exercise, RoundBlock, Workout, WorkoutRecord, ExecutionMode)
        │
        ▼
Services
   • WorkoutTimerService  — simulator + real clock + pause/active-time + persists WorkoutRecord on finish
   • ResultsService       — windowed aggregation, bests, PR detection
   • SeedMigration        — idempotently inserts built-in WODs
```

**Key design rule:** `WorkoutSimulator` (in `Models/Sim`) is a **pure, dependency-free,
unit-tested engine** that owns ALL WOD progression logic. It does not import SwiftData, the
clock, or SwiftUI. `WorkoutTimerService` wires the simulator to the real clock and persistence;
`TimerView` just displays what the service reports. This makes the hard logic fully testable
without a device.

**Round structure is EXPLICIT** (a `Workout` is an ordered list of `RoundBlock`s), NOT derived:
- `RoundBlock.exercises`: ordered movements in the block.
- `RoundBlock.repeatTimes`: `0` = loop until clock (for-time); `N` = play N (top-time); `1` = single pass.
- `RoundBlock.restAfterBlock`: seconds to rest after the block (nil = continuous).
- Fran: 3 blocks {thrusters+pull-ups @21}, {…@15}, {…@9}; top-time plays each once → 3 rounds, auto-stop.
- Cindy: 1 block {5/10/15 bodyweight}, for-time repeat=0 until 20 min.
- DT: 1 block {12 deadlifts, 9 cleans, 6 push jerks}, repeat=5.
- Helen: 1 block {400m run, 21 KB swings, 12 pull-ups}, repeat=3.

**Distanced-only exercises** (runs, row, bike, rope) have **no `reps`** → treat as an effective
rep quota of **1** so the engine stays uniform; `displayLabel` carries the distance.

---

## 4. Project scaffold

There is **no existing Xcode project**. Create one:

**Option A (preferred, clean):** use **XcodeGen** (`brew install xcodegen`). Create
`Project.yml` pointing at a `Sources`/`Tests` layout, and run `xcodegen generate &&
xcodebuild -workspace WODCounter.xcworkspace -scheme WODCounter`.

**Option B:** generate an Xcode project via a `Package` + `@main App` + manual `.xcodeproj`
using `xcodegen`-style config. **Option A is recommended.**

Create these top-level folders in the project:
`WODCounter/`, `Tests/`, `docs/superpowers/specs/`, `docs/superpowers/plans/`.

Deploy target: **iOS 17.0** (required for SwiftData `@Query`, `ModelContainer`, Swift Charts, `#Predicate`).

---

## 5. Data model (SwiftData)

### ExecutionMode
```swift
enum ExecutionMode: String, Codable, CaseIterable, Sendable {
    case forTime, topTime
    var title: String { self == .forTime ? "For Time" : "Top Time" }
    var symbol: String { self == .forTime ? "timer" : "flag.checkered" }
}
```

### Movement (stable catalog)
```swift
@Model final class Movement {
    @Attribute(.unique) var name: String
    var equipment: String?       // Barbell / Kettlebell / Rope / Rowing Machine / Box / Track / Power Rack / Bodyweight
    var category: String?        // Strength / Gymnastics / Power / Cardio / Sprint / Skill
    var iconName: String?
    init(name: String, equipment: String? = nil, category: String? = nil, iconName: String? = nil) {...}
}
```

### Exercise (per-WOD dose of a movement)
```swift
@Model final class Exercise {
    @Relationship var movement: Movement?
    var reps: Int?               // nil = distanced-only (effective quota 1)
    var weight: String?          // e.g. "95 lb", "225 lb", "53/35 lb"
    var distance: String?        // e.g. "1 mi", "400 m"
    var distanceUnit: String?    // "mi" / "m"
    var restSeconds: Int?        // inter-set/rest within the scheme (optional)
    var displayLabel: String?    // PRE-RENDERED "21 Thrusters (95 lb)" — the UI shows this verbatim
    init(...) {...}
    var effectiveReps: Int { reps ?? 1 }
}
```
> **Rule:** `displayLabel` is pre-rendered. The UI must never reformat weight/reps/distance at
> render time — always show the stored `displayLabel`. This is required for identical sync rendering.

### RoundBlock
```swift
@Model final class RoundBlock {
    @Relationship(deleteRule: .cascade, inverse: \Workout.blocks) var exercises: [Exercise]
    var repeatTimes: Int                 // 0 = loop until clock (for-time); N = play N (top-time); 1 = single pass
    var restAfterBlock: Int?             // seconds to rest after this block; nil = continuous
    init(repeatTimes: Int, restAfterBlock: Int? = nil) {...}
}
```

### Workout
```swift
@Model final class Workout {
    var name: String
    var description: String?
    var category: String?              // "Girl" | "Hero" | "Custom"
    var mode: ExecutionMode
    @Relationship(deleteRule: .cascade, inverse: \WorkoutRecord.workout) var records: [WorkoutRecord]
    @Relationship(deleteRule: .cascade, inverse: \Workout.blocks) var blocks: [RoundBlock]
    var isBuiltin: Bool
    var forTimeMinutes: Int?           // nil = unlimited (Murph); e.g. 20 (Cindy)
    var createdAt: Date
    var updatedAt: Date
    init(name:, mode:, isBuiltin:, forTimeMinutes: = nil, createdAt: = Date(), updatedAt: = Date()) {...}
}
```

### WorkoutRecord (history)
```swift
@Model final class WorkoutRecord {
    @Attribute(.unique) var id: UUID
    var workout: Workout?
    var date: Date
    var kind: String                   // "rounds" | "time"
    var roundsCompleted: Int
    var totalReps: Int
    var elapsedTime: TimeInterval
    var pausedTime: TimeInterval
    var activeTime: TimeInterval      // elapsedTime - pausedTime
    var isPR: Bool
    var notes: String?
    init(id: UUID = UUID(), workout:, date: = Date(), kind:, roundsCompleted:, totalReps:,
         elapsedTime:, pausedTime:, activeTime:, isPR:, notes: = nil) {...}
}
```

**Container schema (WODCounterApp):**
```swift
modelContainer(for: [Movement.self, Exercise.self, RoundBlock.self, Workout.self, WorkoutRecord.self])
```

---

## 6. Pure engine: WorkoutSimulator (do this first — highest test value)

File `Models/Sim/TimerEvent.swift`:
```swift
enum FinishedReason: String { case clockExpired, goalReached, manual }
enum TimerEvent {
    case none
    case blockCompleted
    case finished(FinishedReason)
}
```

File `Models/Sim/WODSimulator.swift` — a stateful struct (NOT a class, NOT SwiftData):
```swift
struct WODSimulator {
    let workout: Workout
    enum Phase: Equatable { case idle, running, paused, resting, finished }

    // progress state
    private(set) var phase: Phase = .idle
    private(set) var roundsCompleted: Int = 0
    private(set) var blockIndex: Int = 0
    private(set) var exerciseIndex: Int = 0
    private(set) var repsDonePerExercise: [UUID: Int] = [:]
    private(set) var wallClock: TimeInterval = 0
    private(set) var pausedAccumulated: TimeInterval = 0
    private(set) var isPaused: Bool = false
    private(set) var restDeadline: TimeInterval? = nil

    private var forTimeMinutes: Int? { workout.mode == .forTime ? workout.forTimeMinutes : nil }

    var currentBlock: RoundBlock? { workout.blocks[blockIndex] }
    var currentExercise: Exercise? { currentBlock?.exercises[exerciseIndex] }

    // derived
    var currentRepProgress: Int? { currentExercise?.id.map { repsDonePerExercise[$0] ?? 0 } }
    var resultRounds: Int { roundsCompleted }
    var resultActiveTime: TimeInterval { wallClock - pausedAccumulated }
    var isClockExpired: Bool {
        guard let m = forTimeMinutes else { return false }
        return (wallClock - pausedAccumulated) >= Double(m) * 60
    }
    // top-time: finished when last exercise of last block reaches quota
    var topTimeBlockCompleted: Bool {
        guard workout.mode == .topTime, let block = currentBlock else { return false }
        let last = block.exercises.count - 1
        guard exerciseIndex == last else { return false }
        let ex = block.exercises[last]
        return (repsDonePerExercise[ex.id] ?? 0) >= ex.effectiveReps
    }
    var canAutoStop: Bool { phase == .finished || topTimeBlockCompleted }

    func start() {
        repsDonePerExercise.removeAll(keepingCapacity: true); exerciseIndex = 0
        phase = .running
    }
    func advanceRep() -> TimerEvent {
        precondition(phase == .running && restDeadline == nil, "cannot advance during rest")
        guard let ex = currentExercise, let block = currentBlock else { return .none }
        repsDonePerExercise[ex.id, default: 0] += 1
        if repsDonePerExercise[ex.id] ?? 0 >= ex.effectiveReps {
            if exerciseIndex < block.exercises.count - 1 {
                exerciseIndex += 1
                return .none
            } else {
                return completeBlock()
            }
        }
        return .none
    }
    private func completeBlock() -> TimerEvent {
        guard let block = currentBlock else { return .none }
        roundsCompleted += 1
        if blockIndex + 1 >= workout.blocks.count {
            phase = .finished; return .finished(.goalReached)
        }
        if isClockExpired {
            phase = .finished; return .finished(.clockExpired)
        }
        if blockIndex + 1 < workout.blocks.count, let next = workout.blocks[blockIndex + 1], let rest = next.restAfterBlock {
            restDeadline = wallClock + rest; phase = .resting; return .blockCompleted
        }
        blockIndex += 1; repsDonePerExercise.removeAll(keepingCapacity: true); exerciseIndex = 0
        return .blockCompleted
    }
    func startRest() -> TimerEvent {
        guard phase == .running else { return .none }
        guard let next = workout.blocks[blockIndex + 1], next.restAfterBlock != nil else { return .none }
        restDeadline = wallClock + (next.restAfterBlock ?? 0); phase = .resting; return .none
    }
    func endRest() -> TimerEvent {
        if phase == .resting { phase = .running }; return .none
    }
    func finish() -> TimerEvent { phase = .finished; return .finished(.manual) }
    func advanceTime(_ dt: TimeInterval, active: Bool) {
        if active, phase == .running { wallClock += dt }
        if !active { pausedAccumulated += dt }
        if phase == .resting, let d = restDeadline, wallClock >= d { restDeadline = nil; phase = .running }
    }
    func reset() {
        phase = .idle; roundsCompleted = 0; blockIndex = 0; exerciseIndex = 0
        repsDonePerExercise.removeAll(); wallClock = 0; pausedAccumulated = 0; isPaused = false; restDeadline = nil
    }
}
```

### SessionSnapshot (value type the service publishes)
```swift
struct SessionSnapshot {
    var phase: WODSimulator.Phase
    var roundsCompleted: Int
    var blockIndex: Int
    var exerciseIndex: Int
    var repsInCurrentExercise: Int
    var currentExerciseLabel: String
    var wallClock: TimeInterval
    var activeElapsed: TimeInterval
    var isPaused: Bool
    var isFinished: Bool
    func tick(now: Date, start: Date?) -> SessionSnapshot  // advances 1s from last tick (or start)
}
```

---

## 7. Services

### WorkoutTimerService (bridge simulator → clock → persistence)
`Services/WorkoutTimerService.swift`, `ObservableObject`:
- Holds a `WODSimulator` + a 1-second `Task` ticker that:
  - advances the clock (computes active vs paused from a stored `pausedAt`),
  - republishes the snapshot.
- Methods: `start()`, `pause()`, `resume()`, `advanceRep()` (calls `sim.advanceRep()`, publishes `TimerEvent`), `startRest()`, `endRest()`, `finish()`.
- On **finish()**: compute `activeTime = wallClock - pausedAccumulated`, `elapsedTime = wallClock`; detect PR via `ResultsService`; insert a `WorkoutRecord`; `sim.reset()`.
- Must be **testable** with an injected `TimeProvider`/clock so no real timers are needed in unit tests.

### ResultsService (pure over SwiftData)
`Services/ResultsService.swift`:
- `recordHistory(for workout:window:) -> [WorkoutRecord]` (sorted desc by date).
- `windowSummary(for:window:) -> Summary` (workoutsCount, prsThisWindow, bestRounds, bestTime, avgActiveTime).
- `previousBest(for:mode:asOf:) -> Double?` (for-time → max rounds; top-time → min activeTime).
- Uses `#Predicate<WorkoutRecord>` on `workout` + date range.

---

## 8. Seed data (built-in WODs)

`Support/BenchmarkSeed.swift` — factory funcs returning `Workout`:
- **Cindy** (Girl, forTime, 20 min, 1 block [5/10/15 bodyweight]).
- **Murph** (Hero, topTime, nil minutes, 1 block repeat=1 [100/200/300 bodyweight]).
- **Fran** (topTime, 3 blocks: {21 Thrusters(95 lb)+21 Pull-ups},{15…},{9…}). Thrusters: Barbell,"95 lb",Power.
- **Angie** (topTime, 1 block single pass [100/100/100/100]).
- **Grace** (topTime, 1 block [30 Clean & Jerk (135 lb)] Strength).
- **Diane** (topTime, 3 blocks: {21 Deadlifts(225)+21 HSPU},{15…},{9…}).
- **Helen** (topTime, 1 block repeat=3 [400m Run, 21 KB Swings(53/35 lb), 12 Pull-ups]). Run: distance "400 m", unit "m".
- **DT** (topTime, 1 block repeat=5 [12 Deadlifts(225), 9 Hang Power Cleans(155 lb), 6 Push Jerks(155 lb)]).
- Movements are created with `.unique` name; dedupe on insert. `displayLabel` pre-rendered for each `Exercise`.

**SeedMigration** (`Support/SeedMigration.swift`): idempotent — if any built-in `Workout` exists, do nothing. Dedupe Movements by `name`, and Workouts/Blocks/Exercises by (name + mode + serialized structure) so re-running never duplicates.

---

## 9. Views

- **HomeView** — `@Query` all `Workout`; builtins first (grouped Girl/Hero) then Custom; tap → WODDetailView.
- **WODDetailView** — name, description, category, mode, block scheme (render each `displayLabel`), for-time minutes or "races reps"; **Start** → TimerView; History; edit/delete.
- **TimerView** — big clock (countdown for-time / up for top-time); per-exercise cycling counter (`label`, `repsInCurrentExercise`/effectiveReps); Pause/Resume, Finish, Rest; live round indicator (for-time) or "finished" callout (top-time). On auto-stop/expiry: results overlay with **Share** (ImageRenderer screenshot).
- **ResultsView** — window tabs (7/30/90/all); summary header ("Past 30 days: X workouts, Y PRs"); per-WOD bests with Δ vs. last; Swift Charts bar of best-over-time; attempts drill-down; share card.
- **CreateWODView** — pick movements; set reps/weight/distance; mode; for-time minutes (top-time) or reps (top-time); optional rest between rounds; name; Save → insert `Workout` + `RoundBlock`s (custom → syncs if iCloud on).
- **SettingsView** — **iCloud toggle** (re-create container: CloudKit when on, in-memory+persistent when off), time-window default (7/30/90/all).

---

## 10. iCloud / CloudKit (opt-in)

- v1 default container: in-memory + persistent (no server).
- Settings toggle enables/disables CloudKit:
  - **On:** build `ModelConfiguration(identifier:inMemory:)` with a `ModelConfiguration.CloudKit(configuration:)` using a **public** database; sync without a user account.
  - **Off:** `ModelConfiguration(for: schemas, isStoredInMemoryOnly: false)`.
- CloudKit descriptor must set sensible **default values** so records sync without fields being empty.
- No accounts, no server, no third-party SDKs.
- `displayLabel` pre-rendering is what keeps rendered UI identical across synced devices.

---

## 11. Testing

- **XCTest** via a testable target. For SwiftData unit tests, use an **in-memory `ModelContainer(for: schema)`** (option: Xcode `Configuration'`/`#if DEBUG` container, or a small `#testable` target — whatever fits the project; keep the SAME code in the app).
- **Required tests:**
  - `WODSimulatorTests`: Cindy (5/10/15 → round 1, cycles); Murph top-time (100/200/300 → auto-stop, rounds=1); Fran (21/15/9 → 3 rounds, auto-stop); DT (×5 → 5 rounds); Helen (×3 → 3 rounds); distanced-only (reps nil → effectiveReps 1).
  - `WorkoutTimerServiceTests`: pause accumulates and active time subtracts it; finish persists a `WorkoutRecord` with correct activeTime (fake clock/time provider).
  - `ResultsServiceTests`: window counts; PR detection (first attempt = PR, later improve/non-improve handled); delta computation.
  - `BenchmarkSeedTests`: correct block/rep counts and pre-rendered labels.
- Every task ends green and committed. **No placeholders.** All steps carry real code.

---

## 12. Constraints (verbatim from plan)

- Apple-native iOS only; **iOS 17.0** minimum.
- **SwiftUI + SwiftData + Swift Concurrency**.
- Offline-first; workout data never leaves device. **iCloud opt-in** (public CloudKit DB, no account/server).
- Pre-rendered `displayLabel`; UI never reformats weight/reps/distance.
- Distanced-only exercises (no `reps`) → effective rep quota **1**; `displayLabel` carries distance.
- Murph seed = bodyweight-only 100/200/300.
- YAGNI: no streaks, no goals, no Apple Watch, no Health, no Sign-In, no Android/web in v1.

---

## 13. Tasks (order, from plan)

1. Scaffold + app entry + `ModelContainer` + idempotent seed migration (Cindy + Murph).
2. All SwiftData models (ExecutionMode, Movement, Exercise, RoundBlock, Workout, WorkoutRecord).
3. `BenchmarkSeed` + `SeedMigration` (Cindy, Murph, Fran, Angie, Grace, Diane, Helen, DT).
4. `WODSimulator` (pure engine) — fully unit tested.
5. `WorkoutTimerService` (clock + pause/active-time + persist on finish).
6. `ResultsService` (windowed stats + PR detection).
7. Views: Home / WOD Detail / Settings.
8. View: Timer.
9. Views: Results / Create WOD; final build.

---

## 14. Definitions / glossary

- **WOD** = Work Out Done. **Girl** = named benchmarks (e.g. Cindy); **Hero** = honors military personnel (e.g. Murph, DT).
- **Round** = one full pass of a `RoundBlock` (every exercise in the block at its quota).
- **Top-time** = race to a fixed rep target; record = your elapsed **active** time.
- **For-time** = fixed clock; record = **rounds** completed.
- **Active time** = wall-clock elapsed minus paused time (what "counts" for for-time).
