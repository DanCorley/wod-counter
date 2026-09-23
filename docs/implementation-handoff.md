# WOD Round Counter — Implementation Handoff

> Purpose: Give an external developer everything needed to implement this iOS app from scratch.
> Read the **Spec** and this **Handoff** together. The Spec is the authority the code is argued from;
> this Handoff resolves the mechanics, file tree, tooling, and conventions.
>
> **Status:** Ready to build. All decisions below are ratified.
>
> **Design evolution (2026-09, timer rework, commit `5e2a197`):** the session engine was
> reworked from a *sequential per-rep cycling counter* to a **free-form task tracker**
> (every set is a task; any-order rep logging; per-round sets for repeats; AMRAP rounds
> regenerate; auto-stop on depletion or clock cap). `WorkoutTimerService` switched from
> `ObservableObject` to `@Observable` to fix live ticking/Pause. The docs below describe the
> *current* design; the per-task plan/briefs (`docs/superpowers/plans/`) record the earlier
> sequential plan and are historical.

---

## 0. TL;DR

Build an Apple-native iOS app (SwiftUI + SwiftData) that runs predefined **Girl/Hero WODs**
(or user-custom ones) in **two modes**:

- **For-time:** fixed active clock (e.g. Cindy = 20 min); count how many **rounds** you complete.
- **Top-time:** fixed rep target; the timer **auto-stops the instant** the final rep is hit.

A **free-form task tracker** drives both: every exercise set (exercise × round) is a
*task* with a remaining-rep count, and the athlete logs reps against **any task in any
order** using quick counters. Local SwiftData storage + **opt-in iCloud sync**.
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
- **For-time:** the clock **counts up** and the label shows the time cap (e.g. Cindy = 20:00).
  Active time = elapsed − pausedTime. Count completed rounds; **auto-stops when the cap
  expires** (or on Finish). Default Cindy `minutes = 20`. AMRAP blocks (repeat `0`) regenerate
  a fresh wave each round; the session ends at the cap.
- **Top-time:** target = the rep quotas. Clock counts up. **Auto-stops when every task is
  depleted.** Default Murph = bodyweight 100/200/300, single pass (1 "round").

### 2.3 Counting (the free-form task tracker)
At session start the workout is expanded into a flat list of **tasks** — one per exercise
set per round ("21 Thrusters (95 lb) — 21 left"). The timer screen shows the whole list with
remaining rep counts. Tap a set to select it, then log reps with the **+1/+5/+10/+25** quick
counters; reps may be logged against **any task, in any order**. No manual "complete set"
button exists:

- Depleting **every** task in a finite block = **one round** (tracked internally).
- **Repeated blocks** (Helen ×3, DT ×5) are pre-expanded into **per-round sets** — DT renders
  5 × 3 = 15 tasks, not a cycling counter.
- **AMRAP blocks** (Cindy, repeat `0`) regenerate a fresh wave whenever all their tasks are
  depleted — one regen = one round; the clock keeps counting to the cap.
- **Top-time** ends the session the instant the last task reaches zero total.
- **Rest between rounds** (Barbara-style): an optional per-block rest; continuous WODs leave it off.

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

The simulator **pre-expands** this structure at session start into per-round tasks
(`repeatTimes` > 0 → one fresh `Task` per exercise per play; `repeatTimes` == 0 → one looping
round whose tasks regenerate on completion). Reps are logged against a `Task` by ID, so the
model is a list of remaining sets, not an index pointer. A "round" is a full depletion of
one `Round`'s tasks — recorded once, or triggering a regeneration for loops.

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
    var roundBlock: RoundBlock?        // inverse of RoundBlock.exercises
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
    @Relationship(deleteRule: .cascade, inverse: \Exercise.roundBlock) var exercises: [Exercise]
    var workout: Workout?               // inverse of Workout.blocks
    var repeatTimes: Int                 // 0 = loop until clock (for-time); N = play N (top-time); 1 = single pass
    var restAfterBlock: Int?             // seconds to rest after this block; nil = continuous
    init(repeatTimes: Int, restAfterBlock: Int? = nil) {...}
}
```

### Workout
```swift
@Model final class Workout {
    var name: String
    var workoutDescription: String?    // renamed from "description" — Swift reserves that name
    var category: String?              // "Girl" | "Hero" | "Custom"
    var mode: ExecutionMode
    @Relationship(deleteRule: .cascade, inverse: \WorkoutRecord.workout) var records: [WorkoutRecord]
    @Relationship(deleteRule: .cascade, inverse: \RoundBlock.workout) var blocks: [RoundBlock]
    var isBuiltin: Bool
    var forTimeMinutes: Int?           // nil = unlimited (Murph); e.g. 20 (Cindy)
    var createdAt: Date
    var updatedAt: Date
    init(name:, workoutDescription:, mode:, isBuiltin:, forTimeMinutes: = nil, createdAt: = Date(), updatedAt: = Date()) {...}
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
/// Free-form workout engine: the session is modeled as a list of pending
/// "tasks" (each exercise set in the workout). The athlete may complete reps
/// against any task in any order; the workout ends when every finite task is
/// depleted (top-time), or when the For-Time clock cap expires (AMRAP rounds
/// regenerate forever).
struct WODSimulator: Sendable {
    enum Phase: String, Sendable, Equatable {
        case idle, running, paused, resting, finished
    }

    /// A single pending set of reps (one exercise at one round).
    struct Task: Identifiable, Sendable, Equatable {
        let id: UUID
        let blockIndex: Int
        let movementName: String
        let displayLabel: String
        let quota: Int                 // exercise.effectiveReps (distance = 1)
        private(set) var completed: Int = 0

        var remaining: Int { max(0, quota - completed) }
        var isComplete: Bool { remaining == 0 }

        mutating func addReps(_ count: Int) { completed = min(quota, completed + max(0, count)) }
    }

    /// One round's worth of tasks. Finite rounds complete once; looping rounds
    /// (AMRAP, repeatTimes == 0) regenerate a fresh wave whenever completed.
    struct Round: Identifiable, Sendable, Equatable {
        let id: UUID
        let number: Int
        let blockIndex: Int
        let isLooping: Bool
        var tasks: [Task]
        var completionRecorded: Bool = false

        var isComplete: Bool { !tasks.isEmpty && tasks.allSatisfy(\.isComplete) }

        mutating func regenerateTasks(with workout: Workout) {
            tasks = WODSimulator.freshTasks(for: workout.blocks[blockIndex], blockIndex: blockIndex)
        }
    }

    let workout: Workout

    // MARK: - Progress State
    private var rounds: [Round]
    private(set) var phase: Phase = .idle
    private(set) var roundsCompleted: Int = 0
    private(set) var totalRepsCompleted: Int = 0
    private(set) var wallClock: TimeInterval = 0
    private(set) var pausedAccumulated: TimeInterval = 0
    private(set) var restDeadline: TimeInterval? = nil

    init(workout: Workout) {
        self.workout = workout
        self.rounds = Self.buildRounds(for: workout)   // pre-expands repeats into per-round tasks
    }

    // MARK: - Derived Properties
    var liveTasks: [Task] { rounds.flatMap(\.tasks) }
    var totalRemaining: Int { liveTasks.reduce(0) { $0 + $1.remaining } }
    var totalRounds: Int { rounds.count }
    var hasLoopingRounds: Bool { rounds.contains(where: \.isLooping) }
    /// True when every finite task is depleted AND no AMRAP round remains open.
    var isWorkoutComplete: Bool { rounds.allSatisfy(\.isComplete) && !hasLoopingRounds }
    var resultActiveTime: TimeInterval { max(0, wallClock - pausedAccumulated) }
    var forTimeMinutes: Int? { workout.mode == .forTime ? workout.forTimeMinutes : nil }
    var isClockExpired: Bool {
        guard let minutes = forTimeMinutes else { return false }
        return resultActiveTime >= Double(minutes) * 60
    }
    var canAutoStop: Bool { phase == .finished }
    var snapshot: SessionSnapshot { /* defined in §7 */ }

    // MARK: - Round Building
    private static func buildRounds(for workout: Workout) -> [Round] {
        // repeatTimes == 0  → one isLooping round (regenerates forever)
        // repeatTimes == N  → N finite rounds, tasks duplicated per round (per-round sets)
        // returns rounds in block order, numbered sequentially
    }
    fileprivate static func freshTasks(for block: RoundBlock, blockIndex: Int) -> [Task] {
        block.exercises.map { exercise in
            Task(id: UUID(), blockIndex: blockIndex,
                 movementName: exercise.movement?.name ?? "Exercise",
                 displayLabel: exercise.displayLabel ?? exercise.movement?.name ?? "Exercise",
                 quota: exercise.effectiveReps)
        }
    }

    // MARK: - Actions
    func start()   { if phase != .finished { phase = .running } }
    func pause()   { if phase == .running || phase == .resting { phase = .paused } }
    func resume()  { if phase == .paused { phase = (restDeadline != nil) ? .resting : .running } }

    /// Logs completed reps against a specific pending task (any exercise, any
    /// round). Reps are capped at the task's remaining quota.
    @discardableResult
    mutating func completeReps(taskID: UUID, count: Int) -> TimerEvent {
        guard phase == .running, restDeadline == nil else { return .none }
        guard let (roundIndex, taskIndex) = locate(taskID) else { return .none }
        let added = min(max(0, count), rounds[roundIndex].tasks[taskIndex].remaining)
        guard added > 0 else { return .none }
        rounds[roundIndex].tasks[taskIndex].addReps(added)
        totalRepsCompleted += added
        return reconcileAfterWork()                   // may finish round / regen / stop workout
    }

    mutating func startRest(duration: TimeInterval? = nil) -> TimerEvent { /* .resting + restDeadline */ }
    mutating func endRest() -> TimerEvent             { /* clear deadline, back to .running */ }
    mutating func finish() -> TimerEvent             { phase = .finished; return .finished(.manual) }

    mutating func advanceTime(_ dt: TimeInterval, active: Bool) {
        guard phase != .idle && phase != .finished else { return }
        if active && phase == .running {
            wallClock += dt
            if workout.mode == .forTime, isClockExpired { phase = .finished }   // clock-cap stop
        } else if active && phase == .resting {
            wallClock += dt
            if let deadline = restDeadline, wallClock >= deadline { restDeadline = nil; phase = .running }
        } else {                                      // paused / non-active
            pausedAccumulated += dt
            wallClock += dt
        }
    }

    mutating func reset() { /* idle, zero counters, rebuild rounds */ }

    // MARK: - Internal
    private mutating func reconcileAfterWork() -> TimerEvent {
        // For every completed round: increment roundsCompleted; AMRAP rounds
        // regenerate tasks (event = .blockCompleted); finite rounds record once.
        // If a block defines restAfterBlock, enter .resting until the deadline.
        // If isWorkoutComplete → phase = .finished, return .finished(.goalReached).
    }
    private func locate(_ id: UUID) -> (round: Int, task: Int)? { /* linear search over rounds' tasks */ }
}
```

> **Design rules.** `reconcileAfterWork()` is the single reconcile point: it emits
> `.blockCompleted` once per finished round (regenerating AMRAP tasks), auto-enters rest, and
> emits `.finished(.goalReached)` when `isWorkoutComplete`. `completeReps` is no-op unless
> `phase == .running` and no rest is due, and **caps** logged reps at the task's remaining
> quota (over-logging is clamped, never negative). "Round completed & rest between rounds" —
> see §2.3. `SessionSnapshot` (the value type the service republishes) is fully defined in §7.

---

## 7. Services

### Services/WorkoutTimerService.swift (full source)
```swift
import Foundation
import SwiftData
import Observation

// MARK: - Immutable session state the TimerView observes
struct SessionSnapshot: Equatable, Sendable {
    var phase: WODSimulator.Phase
    var roundsCompleted: Int
    var totalRounds: Int
    var hasLoopingRounds: Bool
    var tasks: [WODSimulator.Task]      // the live remaining-set list, per-task counts
    var totalRepsCompleted: Int
    var totalRemaining: Int
    var wallClock: TimeInterval
    var activeElapsed: TimeInterval
    var isPaused: Bool
    var isFinished: Bool

    var isRunning: Bool { phase == .running }
    var shouldShowResults: Bool { phase == .finished }
}

extension SessionSnapshot {
    static var idle: SessionSnapshot {
        SessionSnapshot(phase: .idle, roundsCompleted: 0, totalRounds: 0,
                        hasLoopingRounds: false, tasks: [], totalRepsCompleted: 0,
                        totalRemaining: 0, wallClock: 0, activeElapsed: 0,
                        isPaused: false, isFinished: false)
    }
}

@Observable
@MainActor
final class WorkoutTimerService: Identifiable {
    struct Hook { var onFinish: @MainActor @Sendable (WorkoutRecord) -> Void }

    let id: UUID
    let workout: Workout
    private var simulator: WODSimulator
    private let hook: Hook
    private let clock: () -> Date

    private(set) var snapshot: SessionSnapshot
    private var ticker: Task<Void, Never>?

    init(id: UUID = UUID(), workout: Workout,
         clock: @escaping () -> Date = { Date() },
         onFinish: @escaping (WorkoutRecord) -> Void) {
        id, workout, hook, clock, simulator, snapshot = sim.snapshot … // standard init
    }

    // MARK: - Controls
    func start()  { guard phase != .finished; simulator.start(); publish(); scheduleTicker() }
    func pause()  { guard .running/.resting; simulator.pause(); stopTicker(); publish() }
    func resume() { guard .paused; simulator.resume(); publish(); scheduleTicker() }

    /// The only way to count reps: log `count` against one pending task by ID.
    @discardableResult
    func logReps(taskID: UUID, count: Int) -> TimerEvent {
        let ev = simulator.completeReps(taskID: taskID, count: count)
        publish()
        if case .finished = ev { handleFinishedSession() }   // auto-stop: persist record
        return ev
    }

    func startRest(duration: TimeInterval? = nil) -> TimerEvent { … }
    func endRest() -> TimerEvent { … }

    func finish() {            // manual Finish → persist record
        if phase is .running/.resting { stopTicker() }
        _ = simulator.finish()
        publish()
        handleFinishedSession()
    }

    func reset() { stopTicker(); simulator.reset(); publish() }

    func advanceTimeStep(_ dt: TimeInterval, active: Bool) {
        let wasFinished = simulator.phase == .finished
        simulator.advanceTime(dt, active: active)
        if simulator.phase == .finished && !wasFinished { handleFinishedSession() }
        publish()
    }

    // MARK: - End of session — persist a WorkoutRecord
    private func handleFinishedSession() {
        stopTicker()
        let activeTime = simulator.resultActiveTime
        let record = WorkoutRecord(
            workout: workout, date: clock(),
            kind: workout.mode == .forTime ? "rounds" : "time",
            roundsCompleted: simulator.roundsCompleted,
            totalReps: simulator.totalRepsCompleted,
            elapsedTime: simulator.wallClock,
            pausedTime: simulator.wallClock - activeTime,
            activeTime: activeTime, isPR: false)
        hook.onFinish(record)    // ServiceFactory inserts it and marks isPR
    }

    private func scheduleTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.simulator.phase == .paused || self.simulator.phase == .finished { return }
                self.advanceTimeStep(1, active: true)   // clock keeps running through rest too
            }
        }
    }
    private func stopTicker() { ticker?.cancel(); ticker = nil }
    private func publish() { snapshot = simulator.snapshot }
}
```

> **Why `@Observable`, not `ObservableObject`?** The view stores the service in `@State` and
> must re-render on every 1-second tick and on logReps/pause. An unsubscribed
> `ObservableObject`/`@Published` object never fans out changes — that exact bug froze the
> clock and made Pause appear dead. `@Observable` (Observation, iOS 17) lets `@State` tracking
> pick up buried mutations, so live ticking and Pause work with zero extra wiring.

### Support/Container.swift + WODCounterApp.swift (bootstrap)
```swift
// Container.swift — offline-first, plus an in-memory variant for tests
import Foundation
import SwiftData

enum Container {
    static let schema = Schema([
        Movement.self, Exercise.self, RoundBlock.self, Workout.self, WorkoutRecord.self
    ])

    static func local() -> ModelContainer {          // app runtime (persistent)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: config)
    }

    static func inMemory() -> ModelContainer {       // unit tests
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }
}

// WODCounterApp.swift
@main
struct WODCounterApp: App {
    let container: ModelContainer
    let serviceFactory: ServiceFactory
    @State private var appModel: AppModel

    init() {
        let container = Container.local()
        self.container = container
        let factory = ServiceFactory(container)
        self.serviceFactory = factory
        self._appModel = State(initialValue: AppModel(factory: factory))
        SeedMigration.applySeed(to: container)          // idempotent seed
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(serviceFactory)
                .modelContainer(container)
        }
    }
}

// AppModel.swift — @Observable, holds pending workout + results
@Observable
final class AppModel {
    var pendingStart: Workout?
    var results: ResultsService
    @MainActor init(factory: ServiceFactory) { results = ResultsService(context: factory.context) }
    func startWorkout(_ w: Workout) { pendingStart = w }
}

// ServiceFactory.swift — creates timer services wired to the model context
@Observable
@MainActor
final class ServiceFactory {
    let context: ModelContext
    init(_ container: ModelContainer)   { context = container.mainContext }
    init(context: ModelContext)         { self.context = context }   // tests

    func makeTimerService(for workout: Workout,
                          clock: @escaping @Sendable () -> Date = { Date() }) -> WorkoutTimerService {
        WorkoutTimerService(workout: workout, clock: clock) { [weak self] record in
            guard let self else { return }
            record.isPR = ResultsService.isNewPR(workout: workout, kind: record.kind,
                                                 rounds: record.roundsCompleted,
                                                 activeTime: record.activeTime,
                                                 before: record.date, in: self.context)
            self.context.insert(record)
            try? self.context.save()
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

### Views/TimerView.swift (shape — see the real file for full styles)
```swift
import SwiftUI

struct TimerView: View {
    @Environment(ServiceFactory.self) private var serviceFactory
    @Environment(\.dismiss) private var dismiss
    let workout: Workout

    @State private var service: WorkoutTimerService?   // created once in .onAppear, @Observable
    @State private var selectedTaskID: UUID?          // tap-to-select; auto-advances
    @State private var isConfirmingFinish = false

    private var snapshot: SessionSnapshot { service?.snapshot ?? .idle }
    private var isIdle: Bool { snapshot.phase == .idle }
    private var tasks: [WODSimulator.Task] { snapshot.tasks }

    /// The set the quick counters act on: the selection if still incomplete,
    /// otherwise the first remaining task (auto-advances as sets complete).
    private var activeTask: WODSimulator.Task? {
        if let id = selectedTaskID,
           let task = tasks.first(where: { $0.id == id }), !task.isComplete { return task }
        return tasks.first(where: { !$0.isComplete })
    }

    var body: some View {
        NavigationStack {
            Group {
                if isIdle { idleView } else { runningView }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { /* Cancel (idle) / Close (running) */ }
        }
        .onAppear { if service == nil { service = serviceFactory.makeTimerService(for: workout) } }
        .confirmationDialog("End Workout Early?", isPresented: $isConfirmingFinish) {
            Button("End Workout", role: .destructive) { service?.finish() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: .init(get: { snapshot.isFinished }, set: { _ in })) {
            WorkoutCompletionSheet(workout: workout, snapshot: snapshot) { dismiss() }
        }
    }

    // MARK: Idle (pre-start) — scheme preview + explicit Start gate
    private var idleView: some View {
        VStack(spacing: 24) {
            Text(workout.name).font(.title.bold())
            Text(workout.mode == .forTime ? "For Time" : "Top Time").font(.headline).foregroundStyle(.tint)
            ScrollView { WorkoutSchemeView(workout: workout).padding(.horizontal) }
            Button { selectedTaskID = tasks.first?.id; service?.start() } label: {
                Label("Start Workout", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent).tint(.green)
        }
    }

    // MARK: Running
    private var runningView: some View {
        VStack(spacing: 16) {
            header                                    // name + "AMRAP · Round N" / "Round N of M"
            VStack(spacing: 2) {
                Text(Format.duration(snapshot.activeElapsed))   // live count-up clock
                    .font(.system(size: 56, weight: .heavy, design: .monospaced))
                if workout.mode == .forTime { Text("Time Cap 20:00 · Elapsed").foregroundStyle(.tertiary) }
            }
            if snapshot.phase == .resting { restBanner }        // "Resting…" + Skip Rest → endRest()

            HStack(alignment: .firstTextBaseline) {
                Text("\(snapshot.totalRemaining)").font(.system(size: 54, weight: .heavy))
                Text("reps left").foregroundStyle(.secondary)
            }

            ScrollView {                                    // every set as a selectable row
                ForEach(tasks) { task in
                    Button { selectedTaskID = task.id } label: {
                        HStack {
                            Text(task.displayLabel)
                            Spacer()
                            if task.isComplete { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            else { Text("\(task.remaining) left") }
                        }
                    }
                    .disabled(task.isComplete)
                }
            }

            if let task = activeTask {                      // quick counters
                HStack {
                    ForEach([1, 5, 10, 25], id: \.self) { count in
                        Button("+\(count)") { _ = service?.logReps(taskID: task.id, count: count) }
                            .disabled(!snapshot.isRunning || count > task.remaining)
                    }
                }
            }

            controlBar                                     // Pause/Resume + Finish (with confirm)
        }
    }
}

// Completion sheet: trophy icon, "Workout Complete!", rounds (for-time) or time
// (top-time), "N Total Reps", active time, Done → dismiss.
```

> **Auto-start removed.** The previous build auto-called `s.start()` in `.onAppear`; the rework
> intentionally gates the session behind the Start screen so the clock begins only when the
> athlete is ready. `WorkoutCompletionSheet` replaces the old share-card sheet.

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

- **XCTest** via a testable target. For SwiftData unit tests, construct `ModelContext(Container.inMemory())`
  — **do not** use `Container.inMemory().mainContext` inside Swift Testing suites (it caused a
  test-runner hang / cascade failures). Order-robust lookups are mandatory: SwiftData `@Relationship`
  to-many arrays are **unordered**, so tests find tasks by `displayLabel`/`movementName`, never by index.
- **Required tests:**
  - `WODSimulatorTests`: Cindy (3 tasks 5/10/15, AMRAP regenerates a fresh wave each round until
    `advanceTime(1201)` clock-cap expiry → finished); Murph top-time (600 reps, free-form/any order →
    auto-stop `.finished(.goalReached)`, rounds=1); Fran (6 tasks 21/21/15/15/9/9 in scrambled order →
    3 rounds, auto-stop, 90 total reps); DT (repeat=5 → **15 per-round sets**, 135 reps → 5 rounds);
    Helen (9 tasks, Run quota **1** → 102 total); over-logging is capped at remaining; logging while
    idle is ignored; pause freezes active time; manual finish.
  - `WorkoutTimerServiceTests`: pause accumulates and active time subtracts it; finishing persists a
    `WorkoutRecord` with correct activeTime (fake clock); completing every task via `logReps(taskID:count:)`
    auto-persists the record (Fran → 3 rounds, PR on first attempt).
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
