# Task 5 — `ResultsService` (windowed stats + PR detection)

**Deliverable:** A `ResultsService` that reads `WorkoutRecord`s over a time window and computes per-WOD bests, windowed summaries, PR detection, and "Δ vs. last" deltas.

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 11 (results/history).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 7 (full `ResultsService.swift` — reference implementation), § 11 (testing).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 5.
- **Siblings (consume exactly):** Task 1 models (`WorkoutRecord`, `Workout`, `ExecutionMode`). Task 4 uses `ResultsService.isNewPR(...)`. Task 6/8 (ResultsView) consume this service.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. **SwiftUI + SwiftData**. **TDD:** end green, commit once, no placeholders.
- Distanced-only exercises count as quota 1 (relevant when filtering/sorting).

## Files
- **Create:** `WODCounter/Services/ResultsService.swift`

## Contract
`@MainActor final class ResultsService` with `context: ModelContext`.
- `history(for workout:window:kind:) -> [WorkoutRecord]` — `#Predicate<WorkoutRecord>` on `workout` + date range, sorted descending by date. `kind` optional ("rounds"/"time").
- `summary(for workout:window:kind:) -> WindowSummary` — `workoutsCount`, `prsThisWindow`, `bestRounds` (max `roundsCompleted`), `bestTime` (min `activeTime`), `avgActiveTime`.
- `previousBest(for:kind:asOf:) -> Double?` — best before a date; for-time → max `roundsCompleted`, top-time → min `activeTime`.
- `static isNewPR(workout:kind:rounds:activeTime:before:) -> Bool` — first attempt is a PR; else better-than-prior (for-time higher rounds, top-time lower time).
- Time windows: **7d / 30d / 90d / all-time**. The 30-day window is the default.

## Steps
- [ ] **Step 1:** Write `ResultsService.swift` from the handoff §7 reference (the three methods + `isNewPR` + `WindowSummary`). Use `#Predicate<WorkoutRecord>` on `workout` + date range.
- [ ] **Step 2:** Write `Tests/Services/ResultsServiceTests.swift`: insert several `WorkoutRecord`s for two workouts (one for-time, one top-time); assert (a) window counts, (b) `bestRounds`/`bestTime`, (c) PR detection (first attempt = PR, later improve/non-improve handled), (d) delta computation used by the results UI.
- [ ] **Step 3:** Run tests, confirm green, commit.

## Acceptance
- History fetches correctly by window. Windowed summary computes bests/counts/PRs. PR detection: first = PR, improvement stays PR, regression clears it. Tests green. One commit.
