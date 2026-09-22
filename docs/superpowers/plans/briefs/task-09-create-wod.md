# Task 9 — View: Create WOD (Custom Workout Builder)

**Deliverable:** An interactive builder form allowing users to compose, configure, and persist custom workouts from the movement catalog.

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 4 (Flow D: Custom WOD), § 5 (screens).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 9 (`CreateWODView.swift` reference), § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 9.
- **Siblings (consume exactly):**
  - Models (Task 1): `Movement`, `Exercise`, `RoundBlock`, `Workout`, `ExecutionMode`.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. SwiftUI + SwiftData. **TDD:** end green, commit once, no placeholders.
- Custom WODs → `Workout` (category "Custom", `isBuiltin == false`) with user-supplied `RoundBlock`s; pre-rendered `displayLabel` for each exercise; appears immediately on `HomeView`; syncs when iCloud is enabled.

## Files
- **Create:** `WODCounter/Views/CreateWODView.swift`

## Contracts
- **CreateWODView:** Multi-step or grouped form:
  - Select movements from the existing `Movement` catalog (or add a new movement name).
  - Prescribe reps, weight (e.g. "95 lb"), distance (e.g. "400 m"), distanceUnit, and rest seconds.
  - Choose execution mode (`.forTime` or `.topTime`), time caps, repeat counts per block.
  - Generates pre-rendered `displayLabel` strings for each exercise.
  - On Save: builds `RoundBlock`s and `Workout`, and inserts into `@Environment(\.modelContext)`.

## Steps
- [ ] **Step 1:** Write `CreateWODView` adhering to the pre-rendered `displayLabel` rule and SwiftData relationship structure.
- [ ] **Step 2:** Wire Save button to persist the workout to `modelContext` and dismiss.
- [ ] **Step 3:** Run all unit tests across the app (`xcodebuild test`); verify that custom WODs appear in `HomeView` and can be selected for a live timer session. Commit.

## Acceptance
- `CreateWODView` successfully validates, pre-renders exercise labels, and inserts custom WODs into SwiftData. Custom workouts appear under the "Custom" section on Home and run properly in `TimerView`. Full test suite passes. One commit.
