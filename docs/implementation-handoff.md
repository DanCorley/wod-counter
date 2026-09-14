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

    var totalRepsDone: Int { repsDonePerExercise.values.reduce(0, +) }

    func start() {
        repsDonePerExercise.removeAll(keepingCapacity: true); exerciseIndex = 0
        phase = .running
    }
    func advanceRep() -> TimerEvent {
        if phase != .running || restDeadline != nil { return .none }
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
        // Finite-target WODs: stop at the target round count.
        if let target = playTarget {
            if roundsCompleted >= target { phase = .finished; return .finished(.goalReached) }
        } else {
            // For-time AMRAP (block repeat == 0): loop the block until the clock expires.
            if isClockExpired { phase = .finished; return .finished(.clockExpired) }
            blockIndex = 0; repsDonePerExercise.removeAll(keepingCapacity: true); exerciseIndex = 0
            return .blockCompleted
        }
        // Otherwise advance to the next block.
        blockIndex += 1; repsDonePerExercise.removeAll(keepingCapacity: true); exerciseIndex = 0
        return .blockCompleted
    }

    // Total rounds a WOD plays before its goal is reached. nil = for-time AMRAP (loop until clock).
    var playTarget: Int? {
        switch workout.mode {
        case .topTime:
            return blocks.reduce(0) { $0 + ($1.repeatTimes > 0 ? $1.repeatTimes : 1) }
        case .forTime:
            if blocks.allSatisfy { $0.repeatTimes == 0 } { return nil } // loop until clock
            return blocks.first { $0.repeatTimes > 0 }?.repeatTimes ?? blocks.first?.repeatTimes
        }
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

> Note: `SessionSnapshot` (the value type `WorkoutTimerService` republishes) is fully defined in §7. The `tick(now:start:)` method shown here has been removed — the service drives time with an internal `Task` loop, so this method was not part of the final design.

---

## 7. Services

### Services/WorkoutTimerService.swift (full source)
```swift
import Foundation
import SwiftUI
import SwiftData

// MARK: - Published session state the TimerView binds to
struct SessionSnapshot: Equatable {
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

    var isRunning: Bool { phase == .running }
    var shouldShowResults: Bool { phase == .finished }
}

extension SessionSnapshot {
    static var idle: SessionSnapshot {
        let p = WODSimulator.Phase.idle
        return SessionSnapshot(phase: p, roundsCompleted: 0, blockIndex: 0, exerciseIndex: 0,
                               repsInCurrentExercise: 0, currentExerciseLabel: "—",
                               wallClock: 0, activeElapsed: 0, isPaused: false, isFinished: false)
    }
}

@MainActor
final class WorkoutTimerService: ObservableObject, Identifiable {
    struct Hook { var onFinish: (WorkoutRecord) -> Void }

    let id: UUID
    let workout: Workout
    private let simulator: WODSimulator
    private let hook: Hook
    private let clock: () -> Date

    @Published private(set) var snapshot: SessionSnapshot
    @Published private(set) var event: TimerEvent = .none
    private var ticker: Task<Void, Never>?

    init(id: UUID = UUID(), workout: Workout,
         onFinish: @escaping (WorkoutRecord) -> Void,
         clock: @escaping () -> Date = { Date() }) {
        self.id = id
        self.workout = workout
        self.hook = Hook(onFinish: onFinish)
        self.clock = clock
        self.simulator = WODSimulator(workout: workout)
        self.snapshot = WorkoutTimerService.makeSnapshot(from: simulator)
    }

    private static func makeSnapshot(from s: WODSimulator) -> SessionSnapshot {
        SessionSnapshot(
            phase: s.phase,
            roundsCompleted: s.roundsCompleted,
            blockIndex: s.blockIndex,
            exerciseIndex: s.exerciseIndex,
            repsInCurrentExercise: s.currentRepProgress ?? 0,
            currentExerciseLabel: label(from: s),
            wallClock: s.wallClock,
            activeElapsed: s.wallClock - s.pausedAccumulated,
            isPaused: s.phase == .paused,
            isFinished: s.phase == .finished)
    }

    private static func label(from s: WODSimulator) -> String {
        guard s.phase != .finished, let ex = s.currentExercise else {
            return s.currentBlock?.exercises.last?.movement?.name ?? "\u{2014}"
        }
        let base = ex.displayLabel ?? ex.movement?.name ?? "Exercise"
        if let eff = ex.effectiveReps, eff > 1 {
            return "\(base) \(ex.reps ?? eff)/\(eff)"
        }
        return base
    }

    // MARK: Control
    func start() {
        guard simulator.phase != .finished else { return }
        simulator.start()
        event = .none
        scheduleTicker()
    }

    func pause() {
        guard simulator.phase == .running else { return }
        simulator.phase = .paused
        event = .none
        stopTicker()
        publish()
    }

    func resume() {
        guard simulator.phase == .paused else { return }
        simulator.phase = .running
        event = .none
        scheduleTicker()
        publish()
    }

    func advanceRep() -> TimerEvent {
        let ev = simulator.advanceRep()
        event = ev
        publish()
        return ev
    }

    func startRest() -> TimerEvent { event = .none; publish(); return simulator.startRest() }
    func endRest()    -> TimerEvent { event = .none; publish(); return simulator.endRest() }

    // MARK: End of session — this is where a WorkoutRecord is persisted
    func finish() {
        if simulator.phase == .running { stopTicker() }
        simulator.finish()
        event = .none
        publish()
        let active = simulator.wallClock - simulator.pausedAccumulated
        let total = simulator.wallClock
        let record = WorkoutRecord(
            workout: workout,
            date: clock(),
            kind: workout.mode == .forTime ? "rounds" : "time",
            roundsCompleted: simulator.roundsCompleted,
            totalReps: simulator.totalRepsDone,
            elapsedTime: total,
            pausedTime: simulator.pausedAccumulated,
            activeTime: active,
            isPR: ResultsService.isNewPR(workout: workout, kind: record.kind,
                                         rounds: simulator.roundsCompleted,
                                         activeTime: active, before: clock())
        )
        hook.onFinish(record)
    }

    func reset() {
        simulator.reset()
        event = .none
        publish()
    }

    private func scheduleTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let phase = self.simulator.phase
                if phase == .paused || phase == .finished { return }
                try? await Task.sleep(for: .seconds(1))
                self.simulator.advanceTime(1, active: true)
                self.publish()
            }
        }
    }
    private func stopTicker() { ticker?.cancel(); ticker = nil }
    private func publish() { snapshot = WorkoutTimerService.makeSnapshot(from: simulator) }
}
```

### Support/Container.swift + WODCounterApp.swift (bootstrap)
```swift
// Container.swift
import Foundation
import SwiftData

enum Container {
    static let schemas: [any PersistentModelType] = [
        Movement.self, Exercise.self, RoundBlock.self, Workout.self, WorkoutRecord.self
    ]

    // Offline default
    static func local() -> ModelContainer {
        try! ModelConfiguration(for: schemas, inMemoryOnly: false).modelContainer()
    }

    // iCloud opt-in (public database, no account)
    static func cloud() -> ModelContainer {
        let cloud = ModelConfiguration.CloudKit(
            configuration: .init(preferenceName: "WODCounter", publicDatabaseName: "WODCounter"))
        return try! ModelConfiguration(identifier: "WODCounter", inMemory: false).modelContainer(cloud)
    }
}

// WODCounterApp.swift
import SwiftUI
import SwiftData

@main
struct WODCounterApp: App {
    @State private var model = AppModel(serviceFactory)
    @State private var serviceFactory: ServiceFactory

    init() {
        let container = Container.local()
        serviceFactory = ServiceFactory(container)
        SeedApplier(container: container).apply()   // idempotent seed
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
                    .environment(model)
                    .environment(serviceFactory)
            }
            .navigationDestination(for: Route.detail) { w in WODDetailView(workout: w) }
            .navigationDestination(for: Route.timer) { w in TimerView(workout: w) }
        }
    }
}

enum Route: Hashable {
    case detail(Workout)
    case timer(Workout)
}

// AppModel.swift
import SwiftUI
import SwiftData

@Observable
final class AppModel {
    var pendingStart: Workout?
    var results: ResultsService
    init(_ factory: ServiceFactory) { results = ResultsService(context: factory.context) }

    func startWorkout(_ w: Workout) { pendingStart = w }
}

// ServiceFactory.swift
import SwiftUI
import SwiftData

@MainActor
final class ServiceFactory {
    let context: ModelContext
    init(_ container: ModelContainer) { context = container.mainContext }

    func makeTimerService(for workout: Workout) -> WorkoutTimerService {
        WorkoutTimerService(workout: workout) { [weak self] record in
            self?.context.insert(record)
            do { try self?.context.save() } catch { /* non-fatal on save */ }
        }
    }
}
```

### Services/ResultsService.swift (full source)
```swift
import Foundation
import SwiftData

struct WindowSummary {
    var workoutsCount: Int
    var prsThisWindow: Int
    var bestRounds: Int
    var bestTime: TimeInterval   // smallest activeTime (lower is better)
    var avgActiveTime: TimeInterval
}

@MainActor
final class ResultsService {
    let context: ModelContext
    init(_ context: ModelContext) { self.context = context }

    func history(for workout: Workout?, window: DateInterval, kind: String? = nil) -> [WorkoutRecord] {
        guard let workout else { return [] }
        let predicate = #Predicate<WorkoutRecord> {
            $0.workout?.id == workout.id &&
            $0.date >= window.start && $0.date <= window.end &&
            (kind == nil || $0.kind == kind)
        }
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func summary(for workout: Workout?, window: DateInterval, kind: String?) -> WindowSummary {
        let records = history(for: workout, window: window, kind: kind)
        let prs = records.filter { $0.isPR }
        let bestTime = records.min(by: { $0.activeTime < $1.activeTime })?.activeTime ?? .greatestFiniteMagnitude
        let avg = records.isEmpty ? 0 : records.reduce(0) { $0 + $1.activeTime } / Double(records.count)
        return WindowSummary(workoutsCount: records.count, prsThisWindow: prs.count,
                             bestRounds: records.max(by: { $0.roundsCompleted < $1.roundsCompleted })?.roundsCompleted ?? 0,
                             bestTime: bestTime, avgActiveTime: avg)
    }

    func previousBest(for workout: Workout, kind: String, asOf date: Date) -> Double? {
        let candidates = history(for: workout, window: date.start ... date.end, kind: kind)
            .filter { $0.date < date }
        if kind == "rounds" {
            return candidates.max(by: { $0.roundsCompleted < $1.roundsCompleted })?.roundsCompleted
        } else {
            return candidates.min(by: { $0.activeTime < $1.activeTime })?.activeTime
        }
    }

    static func isNewPR(workout: Workout, kind: String, rounds: Int, activeTime: TimeInterval, before date: Date) -> Bool {
        guard let best = previousBest(for: workout, kind: kind, asOf: date) else { return true }
        return kind == "rounds" ? rounds > best : activeTime < best
    }
}
```


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

### Views/HomeView.swift
```swift
import SwiftUI

struct HomeView: View {
    @Query(sort: \Workout.name) private var workouts: [Workout]
    @Environment(AppModel.self) private var model
    @State private var route: Route?

    var body: some View {
        List {
            Section("Girl")      { ForEach(section(.girl))     { HomeRow(workout: $0, route: $route) } }
            Section("Hero")      { ForEach(section(.hero))     { HomeRow(workout: $0, route: $route) } }
            Section("Custom")    { ForEach(section(.custom))   { HomeRow(workout: $0, route: $route) } }
        }
        .navigationTitle("WODs")
    }

    private func section(_ filter: (Workout) -> Bool) -> [Workout] { workouts.filter(filter) }

    private func HomeRow(workout: Workout, route: Binding<Route?>) -> some View {
        Button { route.wrappedValue = .detail(workout) }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .labelValue(workout.name)
            .swipeActions {
                Button(role: .destructive) { } label: { Label("Delete", systemImage: "trash") }
            }
            .sheet(isPresented: Binding(get: { model.pendingStart == workout },
                                        set: { if $0 { model.pendingStart = workout } })) {
                if model.pendingStart == workout {
                    WODDetailView(workout: workout)
                }
            }
    }
}
```

### Views/WODDetailView.swift
```swift
import SwiftUI

struct WODDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(ServiceFactory.self) private var factory
    let workout: Workout

    private var blocks: [(id: Int, index: Int, repeatTimes: Int, exercises: [Exercise])] {
        workout.blocks.enumerated().map { (i, b) in
            (id: i, index: i, repeatTimes: b.repeatTimes, exercises: b.exercises)
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text(workout.name).font(.title.bold())
                    if let d = workout.description { Text(d).foregroundStyle(.secondary) }
                    Label(workout.mode.title, systemImage: workout.mode.symbol)
                    if workout.mode == .forTime, let m = workout.forTimeMinutes {
                        Text("For time — \(Format.timer(m))")
                    } else {
                        Text("Top time — race to the reps")
                    }
                }
            }
            Section("Scheme") {
                ForEach(blocks) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Round \(item.index + 1) of \(item.repeatTimes == 0 ? "many" : item.repeatTimes)")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(item.exercises) { Text($0.displayLabel ?? "Exercise") }
                    }
                }
            }
            Section {
                Button("Start") { model.startWorkout(workout); route = .timer(workout) }
            }
            Section {
                Button("History") { route = .results }
            }
        }
        .navigationTitle(workout.name)
        .toolbar { if !workout.isBuiltin { ToolbarItem(placement: .destructiveAction) { Button("Delete", role: .destructive) {} } } }
    }
    @State private var route: Route?.init(detail: nil)
}
```

### Views/TimerView.swift
```swift
import SwiftUI
import SwiftData
import Image

struct TimerView: View {
    @Environment(ServiceFactory.self) private var factory
    let workout: Workout
    @Environment(AppModel.self) private var model

    @State private var service: WorkoutTimerService?
    @State private var snapshot: SessionSnapshot = .idle
    @State private var shareSheet: ResultsCardData?

    var body: some View {
        VStack(spacing: 24) {
            Text(workout.name).font(.title2.bold())
            Text(Format.duration(workout.mode == .topTime ? snapshot.activeElapsed : max(0, (workout.forTimeMinutes ?? 0) * 60 - snapshot.activeElapsed)))
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())
            VStack { Text(snapshot.currentExerciseLabel).font(.headline)
                      Text("\(snapshot.repsInCurrentExercise) / \(effectiveReps(snapshot))")
                          .foregroundStyle(.secondary) }
            HStack(spacing: 16) {
                Button(action: { if snapshot.isRunning { service?.pause() } else { service?.resume() } }) {
                    Label(snapshot.isPaused ? "Resume" : "Pause", systemImage: snapshot.isPaused ? "play.fill" : "pause.fill")
                        .frame(minWidth: 110)
                }
                if workout.mode == .topTime {
                    Button(action: { service?.finish() }) { Label("Finish", systemImage: "flag.fill") }.frame(minWidth: 110)
                }
                Button(action: { service?.startRest(); service?.endRest() }) { Label("Rest", systemImage: "hourglass") }
            }
        }
        .padding()
        .onChange(of: snapshot.isFinished) { _, finished in if finished { shareSheet = ResultsCardData(workoutName: workout.name, snapshot: snapshot, reason: reason) } }
        .task { if service == nil { service = factory.makeTimerService(for: workout) } }
        .sheet(item: $shareSheet) { card in ResultsCardView(data: card) }
    }

    private var reason: FinishedReason {
        guard snapshot.shouldShowResults else { return .manual }
        return workout.mode == .forTime ? .clockExpired : .goalReached
    }
    private func effectiveReps(_ s: SessionSnapshot) -> Int {
        guard s.phase != .finished, let ex = s.currentExercise else { return 0 }
        return ex.effectiveReps
    }
}

enum Format {
    static func duration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60, sec = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }
    static func timer(_ minutes: Int) -> String { duration(Double(minutes) * 60) }
}

// The results sheet payload (holds the data).
struct ResultsCardData: Identifiable {
    let id = UUID()
    let workoutName: String
    let snapshot: SessionSnapshot
    let reason: FinishedReason
    var roundsCompleted: Int { snapshot.roundsCompleted }
}

// Renders the results sheet and offers a Share action.
struct ResultsCardView: View {
    let data: ResultsCardData

    var body: some View {
        VStack(spacing: 20) {
            Text(data.reason == .goalReached ? "Done!" : "Time's up").font(.largeTitle.bold())
            Text(resultLine(data))
                .font(.title)
                .contentTransition(.numericText())
            Text(data.workoutName).foregroundStyle(.secondary)
            ShareLink(item: shareText(for: data)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Text("Tap to dismiss")
        }
        .padding()
    }

    private func resultLine(_ d: ResultsCardData) -> String {
        switch d.reason {
        case .clockExpired:
            return "\(d.roundsCompleted) rounds"
        case .goalReached, .manual:
            return "\(Format.duration(d.snapshot.activeElapsed)) · \(d.roundsCompleted) reps"
        }
    }
    private func shareText(for d: ResultsCardData) -> String {
        "I just completed \(d.workoutName): \(resultLine(d))"
    }
}
```

### Views/ResultsView.swift
```swift
import SwiftUI
import Charts

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ServiceFactory.self) private var factory
    @State private var window: Window = .month
    @State private var selected: Workout?
    @State private var share: ShareCard?

    private var summary: WindowSummary { factory.results.summary(for: selected, window: interval(for: window), kind: selected?.mode == .forTime ? "rounds" : "time") }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Workouts", value: "\(summary.workoutsCount)")
                LabeledContent("PRs", value: "\(summary.prsThisWindow)")
                LabeledContent("Best rounds", value: "\(summary.bestRounds)")
                LabeledContent("Best time", value: "\(Format.duration(summary.bestTime))")
            }
            Section("Per-WOD bests") {
                ForEach(topWorkouts()) { w in
                    Button { selected = w } label: { Text("\(w.name)  \(bestLine(for: w))") }
                        .buttonStyle(.plain)
                }
            }
            Section("Best over time") {
                Chart { /* bar of recent per-7-day counts */ }
            }
        }
        .navigationTitle("History")
        .toolbar { Menu("Window") { ForEach(Window.allCases, id: \.self) { Button($0.title) { window = $0 } } }
        .sheet(item: $share) { ShareCard(card: $0) }
    }
}

enum Window: String, CaseIterable {
    case week = "7d", month = "30d", quarter = "90d", all = "All"
    var title: String { rawValue
    func interval() -> DateInterval { start = Calendar.current.date(byAdding: .day, value: -offset(), date: .now)!; end = .now }
    private var offset() -> Int { switch self { case .week: 7; case .month: 30; case .quarter: 90; default: .max } }
}
```

### Views/CreateWODView.swift
```swift
import SwiftUI
import SwiftData

struct CreateWODView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Movement.name) private var movements: [Movement]

    @State private var name = ""
    @State private var mode: ExecutionMode = .topTime
    @State private var minutes = 5
    @State private var block: [Exercise] = []
    @State private var restAfterBlock = 0

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Mode", selection: $mode) {
                Text("For Time").tag(ExecutionMode.forTime)
                Text("Top Time").tag(ExecutionMode.topTime)
            }
            if mode == .forTime { TextField("Minutes", value: $minutes, format: .number) }
            Section("Movements") {
                ForEach(movements) { m in
                    Toggle(m.name, isOn: Binding(get: { block.contains { $0.movement?.name == m.name } },
                                                 set: { if $0 { block.append(makeExercise(for: m)) } }))
                }
                ForEach(block) { e in TextField("Reps", value: Binding(get: { e.reps ?? 0 }, set: { e.reps = $0 }), format: .number) }
            }
            if mode == .topTime { TextField("Rest between rounds (s)", value: $restAfterBlock, format: .number) }
            Button("Save") { save() }
        }
        .navigationTitle("Create WOD")
    }
    private func makeExercise(for m: Movement) -> Exercise {
        Exercise(movement: m, reps: mode == .topTime ? block.first(where: { $0.movement?.name == m.name })?.reps ?? 1 : nil)
    }
    private func save() {
        let workout = Workout(name: name, mode: mode, isBuiltin: false)
        let blockModel = RoundBlock(repeatTimes: mode == .forTime ? 0 : 1, restAfterBlock: mode == .topTime ? restAfterBlock : nil)
        blockModel.exercises = block
        workout.blocks = [blockModel]
        context.insert(workout)
        try? context.save()
    }
}
```

### Views/SettingsView.swift
```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("cloudKitEnabled") private var cloudKitEnabled = false
    @AppStorage("defaultWindow") private var defaultWindow = "30d"

    var body: some View {
        Form {
            Section("Sync") {
                Toggle("Sync across my devices (iCloud)", isOn: $cloudKitEnabled)
                Text("A public iCloud database is used. No account, no server.")
            }
            Section("Preferences") {
                Picker("Default results window", selection: $defaultWindow) {
                    ForEach(Window.allCases, id: \.self) { Text($0.title) }
                }
            }
        }
        .navigationTitle("Settings")
    }
}
```


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
