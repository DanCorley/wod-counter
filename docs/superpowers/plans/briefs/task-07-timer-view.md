# Task 7 — View: Timer

**Deliverable:** The live timer screen — big clock, per-exercise cycling counter, Pause/Resume, Finish (top-time), and a results overlay on completion.

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 4 (timer flow), § 5 (TimerView).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 9 (`TimerView.swift` reference), `SessionSnapshot` fields, § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 7.
- **Siblings (consume exactly):**
  - `WorkoutTimerService` (Task 5) — `@Environment(ServiceFactory.self)` → `makeTimerService(for:)`.
  - `SessionSnapshot` (Task 3/5): `phase`, `roundsCompleted`, `blockIndex`, `exerciseIndex`, `repsInCurrentExercise`, `currentExerciseLabel`, `wallClock`, `activeElapsed`, `isPaused`, `isFinished`.
  - `Format.duration` / `Format.timer` (Task 4) for clock formatting.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. SwiftUI only. **TDD:** end green, commit once, no placeholders.
- For-time: clock counts **down** from minutes; record = **rounds**. Top-time: clock counts **up** (active time); **Finish** button; record = elapsed active time.

## Files
- **Create:** `WODCounter/Views/TimerView.swift`

## Contract
- Holds the service lazily (`@State var service = factory.makeTimerService(for: workout)`).
- Publishes `snapshot: SessionSnapshot`; big clock (`Format.duration`), cycling counter (`currentExerciseLabel` + `repsInCurrentExercise`/effectiveReps), controls (Pause/Resume, Finish for top-time, Rest), and an auto-completion overlay that appears when `isFinished`.

## Steps
- [ ] **Step 1:** Write `TimerView` using `Format.duration` and `Format.timer` helpers.
- [ ] **Step 2:** Wire start/pause/resume/finish/rest to the service; trigger `service.finish()` on completion.
- [ ] **Step 3:** Smoke-test Cindy for-time and Murph top-time flows in the simulator to verify time formatting and rep advancing. Commit.

## Acceptance
- For-time shows countdown + live round count; top-time shows active time + Finish + auto-stop. Pause freezes the clock; results overlay triggers on completion. `displayLabel`s render verbatim. One commit.
