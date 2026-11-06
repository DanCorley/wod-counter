# WTB-006 — Results correctness and performance

- **Priority:** P1
- **Estimate:** M
- **Depends on:** 002, 003
- **Blocks:** 007
- **Suggested owner:** one agent

## Problem

The results screen does not match the stated “Δ vs last attempt” behavior and has scaling/refresh issues.

1. `WODBestRow.deltaText` compares the best record with the **second-best** record, not the previous chronological attempt (`ResultsView.swift:182-200`). A regression since the last attempt is hidden if the last attempt is still above the second-best ever.
2. `ResultsView` has `@Query` for `Workout`, not `WorkoutRecord`. Newly inserted records may not refresh the visible list reliably.
3. `workoutsWithHistory` calls `history(for:)` once per workout, and `history` fetches **all** records then filters in memory. This is O(workouts × records) per render.
4. `WindowSummary.bestTime` uses `.greatestFiniteMagnitude` for no records. `Format.duration` converts to `Int`, which traps for that value. It is latent today but the plan/handoff display “Best time.”
5. The chart shows every attempt, not “best over time,” and only appears in the drill-down.

Relevant code:

- `WODCounter/Services/ResultsService.swift:21-40` — fetch all, filter in memory.
- `WODCounter/Services/ResultsService.swift:43-57` — summary and sentinel.
- `WODCounter/Views/ResultsView.swift:40-58` — window/key and per-workout queries.
- `WODCounter/Views/ResultsView.swift:158-250` — best row and delta.
- `WODCounter/Views/ResultsView.swift:291-325` — attempts chart.

## Goal

Results are computed once from a single coherent fetch, with clearly labeled delta semantics and correct empty states.

## Scope

1. **Decide delta semantics.**
   - Recommended: “Δ vs last attempt” = current best vs the immediately previous chronological attempt for that workout.
   - If the product prefers “vs previous best,” keep that and label it “vs best.”
   - Put the calculation in `ResultsService` or a domain type, not duplicated in the view and tests.
2. **Fix the service API.**
   - Fetch records once for the selected window (and optional workout filter).
   - Group by workout for the bests list.
   - Add explicit helpers such as `bestRecord(for:)`, `previousRecord(before:)`, `delta(for:)`.
   - Make `WindowSummary.bestTime` optional or use a valid “no data” representation. Remove the `.greatestFiniteMagnitude` sentinel.
3. **Fix refresh behavior.**
   - Observe `WorkoutRecord` with `@Query` or an equivalent refresh trigger.
   - Ensure a newly completed workout appears without requiring an unrelated state change.
4. **Fix the chart.**
   - Show a best-over-time series for the selected workout, or clearly label the existing chart as “All attempts.”
   - Keep the drill-down attempt cards.
5. **Keep PR flags honest.**
   - Decide whether `isPR` is historical or recomputed after deletes.
   - If historical, document that deleting a record does not promote a new PR.
6. **Avoid duplicate view/service logic.**
   - Move best/delta/chart data preparation into testable helpers.

## Acceptance criteria

- [ ] Delta is computed against the documented comparison record and labeled accordingly.
- [ ] A latest worse attempt produces a visible regression where expected.
- [ ] Empty window shows a valid empty state, not a sentinel duration.
- [ ] A newly saved record appears in History without restarting the app.
- [ ] Per-workout history is fetched once per render, not once per workout.
- [ ] Chart content matches its title.
- [ ] PR behavior after deletion is documented and tested.

## Tests

- Best vs last attempt, for-time and top-time.
- Last attempt worse than best.
- Only one attempt.
- Empty window.
- Multiple workouts and multiple records in one window.
- New record inserted after initial render (view-model/service test).
- No `.greatestFiniteMagnitude` reaches `Format.duration`.

## Out of scope

- CloudKit sync (ticket 008).
- Visual redesign of the results screen.
- Custom workout editing (ticket 009).

## Result

**Status:** implemented (uncommitted, 2026-11-06).

### Decision: delta semantics

The delta is **best vs the latest chronological attempt in the selected window**.

- If the latest attempt equals the best, the row shows `=` with the label “vs last”.
- If the latest attempt is worse, the row shows the regression: rounds lost for for-time, extra time for top-time.
- A single attempt shows no delta.
- Best/latest selection, delta formatting, grouping, and chart series live in `ResultsService` value helpers (`WorkoutBestSummary`, `BestSeriesPoint`) so the view and tests share one implementation.

### Changes

- `WindowSummary.bestTime` is now `TimeInterval?`; the `.greatestFiniteMagnitude` sentinel is gone.
- `ResultsView` observes `WorkoutRecord` with `@Query` and filters/groups that one fetch per render instead of calling `history(for:)` per workout. `WODAttemptsView` also observes records directly.
- Drill-down chart is now a best-over-time series (`Best Progression`) while keeping the attempt cards.
- `WorkoutRecord.isPR` is documented as historical: deleting a record does not promote or recompute PR flags. Covered by a test.
- Added tests for best-vs-latest regressions (for-time and top-time), latest-equals-best, single attempt, empty-window `bestTime`, grouping multiple workouts, refresh-after-refetch, best-over-time series, and PR deletion behavior.
