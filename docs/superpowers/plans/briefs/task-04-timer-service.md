# Task 4 — `WorkoutTimerService` (clock + pause/active-time + persist on finish)

**Deliverable:** The service that bridges the pure `WODSimulator` to the real clock and persistence — drives the ticking timer, honors pause/resume, and writes a `WorkoutRecord` when the session ends.

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 7 (services), § 10 (iCloud).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 7 (full `WorkoutTimerService.swift` — reference implementation), App bootstrap (`AppModel`, `ServiceFactory`), § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 4.
- **Siblings (consume exactly):**
  - Task 3 `WODSimulator` + `TimerEvent` + `SessionSnapshot` (value type the service republishes).
  - Task 1 models (`Workout`, `WorkoutRecord`, `ExecutionMode`).
  - **PR detection:** `ResultsService.isNewPR(workout:kind:rounds:activeTime:before:)` (defined Task 5) is called from `finish()`.
  - §7 `SessionSnapshot` is the published view state (`phase`, `roundsCompleted`, `blockIndex`, `exerciseIndex`, `repsInCurrentExercise`, `currentExerciseLabel`, `wallClock`, `activeElapsed`, `isPaused`, `isFinished`).

> **Ordering note:** the timer persists a `WorkoutRecord` with PR detection at `finish()`, so it needs `ResultsService`. That service is listed as Task 5 (after Task 4). To keep the build honest, **build `ResultsService` as part of Task 4** (it's small and pure over the records the timer just wrote), rather than a later task — or expose the PR-check contract early. Either way, make `AppModel.results` exist before the timer's `finish()` runs.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. **SwiftUI + SwiftData + Swift Concurrency**.
- Pause freezes the clock; paused time is subtracted from active time. (See handoff §7 re `pausedAccumulated`.)
- **TDD:** end green, commit once, no placeholders.

## Files
- **Create:** `WODCounter/Services/WorkoutTimerService.swift`
- **Create:** `WODCounter/AppModel.swift`
- **Create:** `WODCounter/ServiceFactory.swift`

## Contract
`@MainActor final class WorkoutTimerService: ObservableObject, Identifiable`
- Holds a `WODSimulator`, republishes `snapshot: SessionSnapshot`, exposes `event: TimerEvent`.
- Published controls: `start()`, `pause()`, `resume()`, `advanceRep()`, `startRest()`, `endRest()`, `reset()`.
- `finish()` → set phase `.finished`, compute `activeTime = wallClock − pausedAccumulated`, build `WorkoutRecord` (`kind = forTime ? "rounds" : "time"`, PR via `ResultsService`), and call the injected `onFinish: (WorkoutRecord) -> Void` hook to persist.
- Ticking: an internal `Task` loop advances time 1 s at a time; stops while `.paused`/`.finished`. Inject a `clock: () -> Date` for testability (default `Date`).

## Steps
- [ ] **Step 1:** Write `WorkoutTimerService.swift` from the handoff §7 reference (preserve the ticker, pause/resume gating, and `finish()` persistence path exactly).
- [ ] **Step 2:** Write `AppModel` (`@Observable`, holds `ServiceFactory` + `results: ResultsService`, `startWorkout(_:)`, `pendingStart`) and `ServiceFactory` (`makeTimerService(for:)` → `WorkoutTimerService`, and persists the `WorkoutRecord` via the injected `ModelContext`). Wire the `AppModel` init to take the `ServiceFactory` (its context feeds `ResultsService`).
- [ ] **Step 3:** Write `Tests/Services/WorkoutTimerServiceTests.swift`: with an injected fake `clock`, assert (a) pausing freezes `wallClock` and `activeElapsed` stops growing, (b) `activeTime` = elapsed − paused, (c) `finish()` persists a `WorkoutRecord` with the correct `activeTime`, `kind`, and `roundsCompleted`, and (d) an auto-stop records `goalReached`. Commit.

## Acceptance
- Timer counts, pauses, resumes, auto-stops (top-time) and expires (for-time), and `finish()` persists a correct `WorkoutRecord` with PR detection. Injectable clock; no real timers in unit tests. Tests green. One commit.
