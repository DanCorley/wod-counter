# WTB-011 — Test hardening

- **Priority:** P2
- **Estimate:** M
- **Depends on:** 001–010
- **Suggested owner:** one agent as a final pass, or continuous per ticket

## Problem

The existing tests cover the happy paths but encode some of the bugs and miss the highest-risk behavior.

Specific issues:

1. **The pause test hides the production pause bug.**
   `WorkoutTimerServiceTests.testStartPauseResumeAndTicking` calls `advanceTimeStep(5, active: false)` while paused. The real app never does that; the ticker is stopped. The test passes while production records zero paused time.

2. **The auto-stop persistence test does not assert time.**
   `testServiceFactoryPersistsRecordWithPRStatus` logs all 90 reps, which finishes the session, then calls `advanceTimeStep(180, active: true)`. That call is ignored because the session is already finished. The test never asserts `activeTime`, `pausedTime`, or `elapsedTime`.

3. **Order assumptions are brittle.**
   `BenchmarkSeedTests` asserts raw relationship array order while the tests elsewhere acknowledge SwiftData ordering is not guaranteed.

4. **Missing coverage.**
   - No real/fake-clock pause timeline test.
   - No double-finish or idle-finish test.
   - No multi-block rest test.
   - No Settings window round-trip test.
   - No test that the results list refreshes after a new record.
   - No compile/CI smoke check.
   - No test for `WindowSummary` empty `bestTime`.

5. **Mixed test frameworks.**
   Most tests use XCTest; `CreateWODViewTests` and `ResultsViewTests` use Swift Testing. That is acceptable on Xcode 16+, but the README still claims Xcode 15.

## Goal

The test suite catches the bugs the review found and does not mask them with unrealistic manual calls.

## Scope

1. **Fix misleading tests.**
   - Rewrite the pause test around an injected clock/timeline.
   - Remove the meaningless 180s call after finish or restructure it before completion.
   - Assert exact `elapsedTime`, `pausedTime`, `activeTime`, `roundsCompleted`, `totalReps`, `kind`, and record count.
2. **Add regression tests.**
   - Double finish.
   - Auto-stop + manual finish.
   - Finish while idle.
   - Multi-block rest on A only / B only / final round.
   - Per-exercise rest behavior (implemented or removed).
   - Settings window round-trip and invalid fallback.
   - Results delta vs the documented comparison.
   - Empty `bestTime`.
   - New record appears in results.
3. **Make order tests robust.**
   - Assert sorted/ordered accessors from ticket 004.
   - Do not assert raw relationship array order.
4. **Standardize the test framework.**
   - Prefer one framework per target. If keeping Swift Testing, update README/Xcode requirements and CI.
   - Keep test helpers in a shared file if useful.
5. **Add a smoke test command.**
   - Ensure `scripts/ci.sh` or equivalent runs every test.
   - Optionally add a cheap “app launches” UI smoke test, but do not block the suite on flaky UI timing.

## Acceptance criteria

- [x] The pause regression test uses an injected clock/timeline (see Result for
      the caveat that it was not re-run against the old tick implementation).
- [x] No service test frantically advances inactive time to simulate a pause.
- [x] Every persisted record test checks record count and time fields.
- [x] Rest, settings, results-delta, and duplicate-finish regressions have tests.
- [x] Seed/order tests do not depend on raw SwiftData array order.
- [x] Full suite is green after regenerating from `Project.yml`.
- [x] README/test docs describe the actual framework and Xcode version.

## Result

**Status:** implemented (uncommitted, 2026-11-06).

### Audit findings

- **Pause:** `WorkoutTimerServiceTests` uses an injected `FakeClock` only; no
  service test calls `advanceTime(..., active: false)` to fake a production
  pause. The direct `WODSimulator` pause test still calls it, but that exercises
  the simulator's own inactive-time accounting, not the service's pause path.
- **Persisted records:** all three factory/DB persistence tests now assert
  record count plus `activeTime`, `pausedTime`, and `elapsedTime`. The PR test
  also pauses once so the stored pause is non-zero.
- **Idempotent completion:** double finish, auto-stop + manual finish, clock
  expiry + manual finish, and idle finish are covered, with time assertions
  added.
- **Rest:** A-only, B-only, middling, final-round, and repeated-block cases are
  covered, plus rest countdown and pause-during-rest.
- **Settings/deltas:** all four window values round-trip through the shared
  key; invalid values fall back to `.thirtyDays`. Delta tests cover for-time and
  top-time regressions, ties, and single attempts.
- **Ordering:** seed tests use `orderedBlocks`/`orderedExercises`. The legacy
  tie-break test no longer hard-codes a raw SwiftData array order; it compares
  against the relationship order captured at runtime and asserts membership.
- **Undo:** partial-rep undo, no-op at zero, clearing after task completion, and
  a new no-op-after-session-finish regression are covered.

### Changes

- `WODCounterTests/Services/WorkoutTimerServiceTests.swift`: stronger time
  assertions; pause in the factory persistence test;
  `testUndoAfterSessionCompletionIsNoOp`.
- `WODCounterTests/Models/OrderingTests.swift`: removed the hard-coded raw
  relationship order assumption.
- `WODCounterTests/Sim/WODSimulatorTests.swift`,
  `WODCounterTests/Views/CreateWODViewTests.swift`,
  `WODCounterTests/Views/ResultsViewTests.swift`: cleared the remaining
  unused-result/unused-value compiler warnings exposed by a clean build.
- `README.md`: documented the intentional XCTest + Swift Testing split, Xcode
  16+ requirement, and a working simulator/`XCODEGEN` command.
- `scripts/ci.sh`: comment updated with runtime-dependent destination guidance.

### Test framework decision

Keep the mixed suite. XCTest holds the `@MainActor`/SwiftData service and engine
tests; Swift Testing holds the two value-oriented view-model test files. Both
run in one target. Rewriting ~70 passing XCTest cases for cosmetic consistency
was explicitly out of scope. Xcode 16+ is required.

### Verification

```sh
xcodebuild -project WODCounter.xcodeproj -scheme WODCounter \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

- Result: **121 tests, 0 failures** — 71 XCTest + 50 Swift Testing.
- Test build: no compiler warnings after the unused-result fixes (the only
  remaining warning is the toolchain's benign
  `appintentsmetadataprocessor` AppIntents note).
- `scripts/ci.sh` verified with the staged XcodeGen 2.46.0 binary and the iOS
  27.2 `iPhone 18 Pro` simulator.

### Acceptance criteria

- [x] Pause tests use an injected clock and no service test advances inactive
      time to simulate a pause.
- [x] Every persisted record test checks record count and time fields.
- [x] Rest, settings, results-delta, and duplicate-finish regressions have tests.
- [x] Seed/order tests do not depend on a hard-coded raw SwiftData array order.
- [x] Full suite is green after regenerating the project from `Project.yml`.
- [x] README/test docs describe the actual mixed framework and Xcode 16+.
- [ ] The pause test was not re-run against the pre-002 tick implementation;
      the old code is not present in the working tree. Confidence comes from the
      fake-clock timeline assertions, not a red/green comparison.

## Out of scope

- Product features not covered by tickets 001–010.
- Performance benchmarking.
- CloudKit cross-device automation (manual test only).
