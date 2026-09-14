# Task 6 — Views: Home, WOD Detail, Settings

**Deliverable:** The WOD library (grouped Girl/Hero + Custom), a WOD detail screen (Start, History), and Settings (iCloud toggle, default window).

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 4 (user flows), § 5 (screens), § 9 (views).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 9 (full source for all three views — reference), App bootstrap (`AppModel`, `Route`, `ServiceFactory`), § 10 (iCloud), § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 6.
- **Siblings (consume exactly):**
  - `AppModel` (Task 4) for injecting `ServiceFactory`, `results`, and `startWorkout(_:)` / `pendingStart`.
  - `ExecutionMode` (§1), `Workout` (§5), `ResultsService` (§5).
  - `ResultsView` (Task 8) is the target of "History".
- Navigation model: `Route` enum with `.detail(Workout)` and `.timer(Workout)`; the `NavigationStack` (from the App) resolves these.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. **SwiftUI + SwiftData**. `@Query` / `@Environment` only. **TDD:** end green, commit once, no placeholders.
- `displayLabel` is shown verbatim — never reformat weight/reps/distance in the UI (handoff §5 rule).

## Files
- **Create:** `WODCounter/Views/HomeView.swift`
- **Create:** `WODCounter/Views/WODDetailView.swift`
- **Create:** `WODCounter/Views/SettingsView.swift`

## Contracts
- **HomeView:** `@Query(sort: \Workout.name)` all workouts; three sections **Girl / Hero / Custom** (`category == "Girl"/"Hero"/"Custom"`); tapping a WOD navigates to its detail; a delete swipe action.
- **WODDetailView:** shows name, description, mode + symbol, for-time minutes (or "race to the reps"), and the **scheme** (each `RoundBlock` with its exercises' `displayLabel`, labeled "Round N of M"). **Start** button → `model.startWorkout(workout)` and navigate to `.timer(workout)`. A **History** button → ResultsView. Delete for non-builtin.
- **SettingsView:** **iCloud toggle** (`@AppStorage("cloudKitEnabled")`) + **default-window picker** (`@AppStorage("defaultWindow")`, values 7/30/90/all). Toggling iCloud re-creates the container (CloudKit when on, local when off) — see handoff § 10.

## Steps
- [ ] **Step 1:** Write `HomeView` (query + grouped sections; note the category values must be exactly "Girl"/"Hero"/"Custom" so the sections aren't empty — confirm `BenchmarkSeed` sets `Workout.category`).
- [ ] **Step 2:** Write `WODDetailView` (scheme listing + Start/History/Delete). Start must set both `pendingStart` and route to `.timer`.
- [ ] **Step 3:** Write `SettingsView` with the iCloud toggle and default-window picker. For the container re-creation, follow handoff §10 (CloudKit `ModelConfiguration` when on; local when off). Guard the CloudKit descriptor with sane defaults so records sync without empty fields.
- [ ] **Step 4:** Compile + quick manual smoke (launch app, see Cindy/Murph grouped; tap one to see its scheme). Commit.

## Acceptance
- Home shows Cindy/Murph in Girl/Hero groups. Detail shows mode + scheme with `displayLabel`s. Start routes to the timer; History routes to results. iCloud toggle exists and defaults to local. No reformatting of `displayLabel`. Tests green (write at least one query/mock test) — one commit.
