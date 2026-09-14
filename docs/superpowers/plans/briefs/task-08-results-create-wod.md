# Task 8 — Views: Results + Create WOD

**Deliverable:** The history/results screen (windowed summary, per-WOD bests with Δ vs. last, best-over-time chart, share card) and the custom-WOD builder (creates `Workout` + `RoundBlock`s; custom WODs appear on Home and sync when iCloud is on).

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 11 (results/history), § 9 (views).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 9 (full `ResultsView.swift`/`CreateWODView.swift` references, now using `ResultsCardData`), `ResultsService`/`WindowSummary`, § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 8.
- **Siblings (consume exactly):**
  - `ResultsService` (Task 5): `summary(for:window:kind:)`, `history(for:window:kind:)`, `isNewPR(...)`.
  - `Workout`, `WorkoutRecord`, `RoundBlock`, `ExecutionMode`, `Movement` (§5).
  - `ResultsCardData` (results payload).

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. SwiftUI + SwiftData. **TDD:** end green, commit once, no placeholders.
- Custom WODs → `Workout` (category "Custom") with user-supplied `RoundBlock`s; appear on Home; sync when iCloud enabled.

## Files
- **Create:** `WODCounter/Views/ResultsView.swift`
- **Create:** `WODCounter/Views/CreateWODView.swift`

## Contracts
- **ResultsView:** window tabs **7d / 30d / 90d / all-time** (default 30d); summary header ("Past 30 days: X workouts, Y PRs"); per-WOD bests with Δ vs. previous attempt; a Swift Charts bar of best-over-time; tap a WOD → its attempts; a **Share card** summarizing a selected result (rendered via `ResultsCardData` + `ResultsCardView`).
- **CreateWODView:** pick movements from the catalog, set reps/weight/distance, choose mode, for-time minutes (top-time) or reps (top-time), optional rest between rounds, name it, Save → insert `Workout` + `RoundBlock` via the injected `@Environment(\.modelContext)`. Custom WODs appear on Home and sync when iCloud enabled.

## Steps
- [ ] **Step 1:** Write `ResultsView` from the handoff §9 reference. Use `ResultsService` for summary/bests and `@AppStorage("defaultWindow")` for the window. `ShareCard` / `ResultsCardData` for the share sheet.
- [ ] **Step 2:** Write `CreateWODView` from the handoff §9 reference. On Save, build the `Workout` + `RoundBlock` from the selected movements and insert into `modelContext` (`try context.save()`).
- [ ] **Step 3:** Run **all** tests (`swift test`) and a final full build; confirm custom WODs appear on Home (Query) and sync when iCloud on. Commit.

## Acceptance
- Results screen: window tabs, summary, per-WOD bests with Δ, a chart, share card. CreateWODView builds and persists a custom WOD that then appears on Home. All tests pass; full build succeeds. One commit.
