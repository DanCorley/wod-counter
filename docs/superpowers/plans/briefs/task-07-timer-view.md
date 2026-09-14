# Task 7 — View: Timer

**Deliverable:** The live timer screen — big clock, per-exercise cycling counter, Pause/Resume, Finish (top-time), and a results/share overlay on completion.

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 4 (timer flow), § 5 (TimerView).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 9 (full `TimerView.swift` reference — now using `ResultsCardData`/`ResultsCardView`; `Format.duration`/`Format.timer` helpers), `SessionSnapshot` fields, § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 7.
- **Siblings (consume exactly):**
  - `WorkoutTimerService` (Task 4) — `@Environment(ServiceFactory.self)` → `makeTimerService(for:)`.
  - `SessionSnapshot` value type: `phase`, `roundsCompleted`, `blockIndex`, `exerciseIndex`, `repsInCurrentExercise`, `currentExerciseLabel`, `wallClock`, `activeElapsed`, `isPaused`, `isFinished`.
  - `ResultsCardData` + `ResultsCardView` for the results sheet. `Format.duration`/`Format.timer` for clock formatting.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. SwiftUI only. **TDD:** end green, commit once, no placeholders.
- For-time: clock counts **down** from minutes; record = **rounds**. Top-time: clock counts **up** (active time); **Finish** button; record = elapsed active time.

## Files
- **Create:** `WODCounter/Views/TimerView.swift`

## Contract
- Holds the service lazily (`@State var service = factory.makeTimerService(for: workout)`).
- Publishes `snapshot: SessionSnapshot`; big clock (`Format.duration`), cycling counter (`currentExerciseLabel` + `repsInCurrentExercise`/effectiveReps), controls (Pause/Resume, Finish for top-time, Rest), and a results sheet that appears on `isFinished` via `ResultsCardView`.
- `Reason`: for-time → `clockExpired`; top-time/manual → `goalReached`/`manual`.

## Steps
- [ ] **Step 1:** Write `TimerView` from the handoff §9 reference, using the corrected types (`ResultsCardData`/`ResultsCardView`, not the old `ResultsCard`). Keep `Format.duration`/`Format.timer` helpers.
- [ ] **Step 2:** Wire start/pause/resume/finish/rest to the service; show results overlay via `.sheet(item:)` on `isFinished`; call `service.finish()` to persist.
- [ ] **Step 3:** For testable progress, assert (via a lightweight test or a preview) that pausing freezes the displayed time and resuming resumes; that the counter reflects `session.snapshot`. Confirm the full Cindy for-time and Murph top-time paths drive correctly in the simulator path. Commit.

## Acceptance
- For-time shows countdown + live round count; top-time shows active time + Finish + auto-stop. Pause freezes the clock; results share card appears on completion. `displayLabel`s render verbatim. One commit.
