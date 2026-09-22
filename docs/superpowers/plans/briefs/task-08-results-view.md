# Task 8 — View: Results & Share Card

**Deliverable:** The history/results screen (windowed summary, per-WOD bests with Δ vs. last, best-over-time chart) and a shareable results card (`ResultsCardView`).

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 11 (results/history), § 9 (views).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 9 (`ResultsView.swift` & `ResultsCardView.swift` references), `ResultsService`/`WindowSummary`, § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 8.
- **Siblings (consume exactly):**
  - `ResultsService` (Task 4): `summary(for:window:kind:)`, `history(for:window:kind:)`, `isNewPR(...)`.
  - `Format` (Task 4): `Format.duration` / `Format.timer`.
  - Task 1 models: `Workout`, `WorkoutRecord`, `ExecutionMode`.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. SwiftUI + SwiftData + Swift Charts. **TDD:** end green, commit once, no placeholders.

## Files
- **Create:** `WODCounter/Views/ResultsCardView.swift`
- **Create:** `WODCounter/Views/ResultsView.swift`

## Contracts
- **ResultsCardView:** Visual card component displaying workout title, active time / rounds, PR badge, date, and share sheet trigger.
- **ResultsView:** Window tabs **7d / 30d / 90d / all-time** (default 30d via `@AppStorage`); summary header ("Past 30 days: X workouts, Y PRs"); per-WOD bests list with Δ vs. previous attempt; a Swift Charts bar of best-over-time; tap a WOD → drill down into its recorded attempts.

## Steps
- [ ] **Step 1:** Write `ResultsCardView` for displaying a snapshot of a completed attempt suitable for exporting/sharing via `ImageRenderer` or ShareSheet.
- [ ] **Step 2:** Write `ResultsView` using `ResultsService` for summary and bests querying, and Swift Charts for history progression.
- [ ] **Step 3:** Test results filtering and verify chart rendering against in-memory record fixtures. Commit.

## Acceptance
- Results screen: window tabs, summary banner, per-WOD bests with Δ, progression chart, share card. Builds cleanly and passes tests. One commit.
