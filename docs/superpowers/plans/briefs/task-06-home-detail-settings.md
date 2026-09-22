# Task 6 — Views: Home, WOD Detail, Settings

**Deliverable:** The WOD library (grouped Girl/Hero + Custom), a WOD detail screen (Start, History), and Settings (iCloud toggle, default window).

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 4 (user flows), § 5 (screens), § 9 (views).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 9 (views reference), App bootstrap (`AppModel`, `Route`, `ServiceFactory`), § 10 (iCloud), § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 6.
- **Siblings (consume exactly):**
  - `AppModel` (Task 5) for injecting `ServiceFactory`, `results`, and `startWorkout(_:)` / `pendingStart`.
  - `ExecutionMode` (§1), `Workout` (§5), `ResultsService` (Task 4).
  - Navigation model: `Route` enum with `.detail(Workout)` and `.timer(Workout)`.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. **SwiftUI + SwiftData**. `@Query` / `@Environment` only. **TDD:** end green, commit once, no placeholders.
- `displayLabel` is shown verbatim — never reformat weight/reps/distance in the UI (handoff §5 rule).

## Files
- **Create:** `WODCounter/Views/HomeView.swift`
- **Create:** `WODCounter/Views/WODDetailView.swift`
- **Create:** `WODCounter/Views/SettingsView.swift`

## Contracts
- **HomeView:** `@Query(sort: \Workout.name)` all workouts; three sections **Girl / Hero / Custom** (`category == "Girl"/"Hero"/"Custom"`); tapping a WOD navigates to its detail; a delete swipe action for custom WODs.
- **WODDetailView:** shows name, description, mode + symbol, for-time minutes (or "race to the reps"), and the **scheme** (each `RoundBlock` with its exercises' `displayLabel`, labeled "Round N of M"). **Start** button → `model.startWorkout(workout)` and navigate to `.timer(workout)`. A **History** button → navigation to Results. Delete for non-builtin.
- **SettingsView:** **iCloud toggle** (`@AppStorage("cloudKitEnabled")`) + **default-window picker** (`@AppStorage("defaultWindow")`, values 7/30/90/all). Changing the iCloud toggle updates the stored preference (re-creating the `ModelContainer` on container restart).

## Steps
- [ ] **Step 1:** Write `HomeView` (query + grouped sections; confirm category strings match "Girl"/"Hero"/"Custom").
- [ ] **Step 2:** Write `WODDetailView` (scheme listing + Start/History/Delete). Start must set both `pendingStart` and route to `.timer`.
- [ ] **Step 3:** Write `SettingsView` with the iCloud toggle and default-window picker.
- [ ] **Step 4:** Compile + smoke navigation (launch app, see Cindy/Murph grouped; tap one to see its scheme). Commit.

## Acceptance
- Home shows Cindy/Murph in Girl/Hero groups. Detail shows mode + scheme with `displayLabel`s. Start routes to the timer; History routes to results. iCloud toggle exists and defaults to local. No reformatting of `displayLabel`. Tests green — one commit.
