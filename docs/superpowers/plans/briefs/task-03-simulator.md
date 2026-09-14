# Task 3 — `WODSimulator` (pure progression engine)

**Deliverable:** A pure, dependency-free, deterministic WOD progression engine — independent of SwiftData, the clock, and UI. This is the highest-value, most-tested part of the app.

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 3 (scheme model), § 6 (round structure).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 6 (full `WODSimulator.swift` — this is the reference implementation), § 7 (service contract), § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 3.
- **Siblings:** Task 1 produced the models — consume `Workout`, `RoundBlock`, `Exercise`, `ExecutionMode` exactly. Task 4 consumes this engine.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. **TDD: end green, commit once, no placeholders.**
- Distanced-only exercises (runs, row, bike, rope) have **no `reps`** → effective rep quota **1**; `displayLabel` carries the distance.

## Files
- **Create:** `WODCounter/Models/Sim/TimerEvent.swift`
- **Create:** `WODCounter/Models/Sim/WODSimulator.swift`

## Engine contract (the engine's own API)
`struct WODSimulator { let workout: Workout; enum Phase: Equatable { case idle, running, paused, resting, finished } … }`
- State: `phase`, `roundsCompleted`, `blockIndex`, `exerciseIndex`, `repsDonePerExercise: [UUID: Int]`, `wallClock`, `pausedAccumulated`, `isPaused`, `restDeadline`.
- Derived: `currentBlock`, `currentExercise`, `currentRepProgress`, `resultRounds`, `resultActiveTime`, `isClockExpired`, `topTimeBlockCompleted`, `canAutoStop`, `totalRepsDone`, `playTarget`.
- Methods: `start()`, `advanceRep()`, `startRest()`, `endRest()`, `finish()`, `advanceTime(_ dt: TimeInterval, active: Bool)`, `reset()`.
- `TimerEvent`: `case none | blockCompleted | finished(FinishedReason)` where `FinishedReason: clockExpired | goalReached | manual`.

## CORRECT semantics (critical — do NOT regress)
A `round` = one full play of a `RoundBlock`. `playTarget` = total rounds before the goal:
- **topTime:** `blocks.reduce(0){ $0 + ($1.repeatTimes > 0 ? $1.repeatTimes : 1) }`.
- **forTime:** `nil` when every block has `repeatTimes == 0` (AMRAP — loop until clock); else the first non-zero `repeatTimes`.
`completeBlock()` logic (reference, keep this exact behavior):
```swift
roundsCompleted += 1
if let target = playTarget {
    if roundsCompleted >= target { phase = .finished; return .finished(.goalReached) }
} else {
    if isClockExpired { phase = .finished; return .finished(.clockExpired) }
    blockIndex = 0; repsDonePerExercise.removeAll(keepingCapacity: true); exerciseIndex = 0
    return .blockCompleted   // loop the AMRAP block
}
blockIndex += 1; repsDonePerExercise.removeAll(keepingCapacity: true); exerciseIndex = 0
return .blockCompleted
```
Key correctness (regression guards):
- **For-time AMRAP (Cindy, block repeat=0):** loops the block until `isClockExpired` → `.clockExpired`. Must NOT finish after 1 round.
- **Repeating blocks (DT ×5):** finishes after `playTarget` (5) plays, not 1.
- **Multi-block top-time (Fran):** plays each block once; finishes at the last block.
- `advanceRep()`: if not `.running` or `restDeadline != nil` → `.none`; otherwise increment current exercise, cycle on quota, complete block.
- `advanceTime(_ dt, active:)`: adds `dt` to `wallClock` only while `.running`; adds to `pausedAccumulated` otherwise; when `.resting` and `wallClock >= restDeadline` → resume.
- **Pause semantics:** pausing freezes `wallClock` (ticker stops), so `activeTime = wallClock − pausedAccumulated` stays correct even though `pausedAccumulated` isn't incremented here. (See handoff §7 — do not "fix" by inventing a new paused-time mechanism unless asked.)

## Steps
- [ ] **Step 1:** Write `TimerEvent.swift` (`FinishedReason` + `TimerEvent`) and `WODSimulator.swift` matching the engine contract and correct semantics above. Use a `struct` (value type), NOT a class, NOT `@Model`.
- [ ] **Step 2:** Write `Tests/Sim/WODSimulatorTests.swift` covering:
  - Cindy for-time: 5/10/15 → round 1, cycles, repeats until `isClockExpired`.
  - Murph top-time: 100/200/300 → `canAutoStop == true`, rounds=1.
  - Fran: 21/15/9 → 3 rounds, auto-stop.
  - DT: ×5 → 5 rounds, auto-stop.
  - Helen: ×3 → 3 rounds.
  - Distanced-only exercise (`reps == nil`) → `effectiveReps == 1`, advances as quota 1.
- [ ] **Step 3:** Run tests, confirm green, commit.

## How to work this task
- The simulator must import **only** Foundation + the models (Task 1). It must NOT import SwiftData/SwiftUI/clock. Keep it pure so it's trivially unit-testable.
- Build a `ModelContainer(for: [schema])` (in-memory for tests is fine) to construct real `Workout` objects, OR build lightweight structs — but the engine takes a `Workout`, so construct real ones from `BenchmarkSeed` (Task 2) or hand-crafted fixtures.
- BASE commit: HEAD. Diff against it. Done when tests green and the engine compiles against the real models. One commit.

## Acceptance
- All tests pass: AMRAP loops to clock, repeating blocks finish at target, multi-block top-time auto-stops, distanced exercises count as quota 1. Pure type, no forbidden imports. One commit.
