# Task 5 — `WorkoutTimerService` (clock + pause/active-time + persist on finish)

**Deliverable:** The service that bridges the pure `WODSimulator` to the real clock and persistence — drives the ticking timer, honors pause/resume, evaluates PRs via `ResultsService`, and writes a `WorkoutRecord` when the session ends.

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 7 (services), § 10 (iCloud).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 7 (full `WorkoutTimerService.swift` — reference implementation), App bootstrap (`AppModel`, `ServiceFactory`), § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 5.
- **Siblings (consume exactly):**
  - Task 3 `WODSimulator` + `TimerEvent` + `SessionSnapshot`.
  - Task 4 `ResultsService` (`isNewPR` and `summary`).
  - Task 1 models (`Workout`, `WorkoutRecord`, `ExecutionMode`).

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. **SwiftUI + SwiftData + Swift Concurrency**.
- Pause freezes the clock; paused time is subtracted from active time.
- All test files must be in `WODCounterTests/Services/`.
- **TDD:** end green, commit once, no placeholders.

## Files
- **Create:** `WODCounter/Services/WorkoutTimerService.swift`
- **Create:** `WODCounter/AppModel.swift`
- **Create:** `WODCounter/ServiceFactory.swift`
- **Create:** `WODCounterTests/Services/WorkoutTimerServiceTests.swift`

## Contract
`@MainActor final class WorkoutTimerService: ObservableObject, Identifiable`
- Holds a `WODSimulator`, republishes `snapshot: SessionSnapshot`, exposes `event: TimerEvent`.
- Published controls: `start()`, `pause()`, `resume()`, `advanceRep()`, `startRest()`, `endRest()`, `reset()`.
- `finish()` → set phase `.finished`, compute `activeTime = wallClock − pausedAccumulated`, build `WorkoutRecord` (`kind = forTime ? "rounds" : "time"`, PR via `ResultsService.isNewPR(...)`), and call the injected `onFinish: (WorkoutRecord) -> Void` hook to persist into `ModelContext`.
- Ticking: an internal `Task` loop advances time 1 s at a time; stops while `.paused`/`.finished`. Inject a `clock: () -> Date` for testability (default `Date`).

## Steps
- [ ] **Step 1:** Write `WorkoutTimerService.swift` from the handoff §7 reference (preserve the ticker, pause/resume gating, and `finish()` persistence path).
- [ ] **Step 2:** Write `AppModel` (`@Observable`, holds `ServiceFactory` + `results: ResultsService`, `startWorkout(_:)`, `pendingStart`) and `ServiceFactory` (`makeTimerService(for:)` → `WorkoutTimerService`, persisting `WorkoutRecord` to `ModelContext`).
- [ ] **Step 3:** Write `WODCounterTests/Services/WorkoutTimerServiceTests.swift`: using an injected fake `clock`, assert:
  - (a) pausing freezes `wallClock` and `activeElapsed` stops advancing,
  - (b) `activeTime` = elapsed − paused,
  - (c) `finish()` persists a `WorkoutRecord` with correct `activeTime`, `kind`, `roundsCompleted`, and `isPR`,
  - (d) auto-stop triggers finish on goal reached.
- [ ] **Step 4:** Run tests, confirm green, commit.

## Acceptance
- Timer counts, pauses, resumes, auto-stops (top-time) and expires (for-time), and `finish()` persists a correct `WorkoutRecord` with PR detection. Injectable clock; no real timers in unit tests. All tests in `WODCounterTests/Services/` pass. One commit.
