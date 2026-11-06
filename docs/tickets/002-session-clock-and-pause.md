# WTB-002 — Session clock and pause/elapsed time

- **Priority:** P0
- **Estimate:** M
- **Depends on:** 001, 004
- **Blocks:** 005, 006, 010
- **Suggested owner:** one agent; keep in the same batch as 003

## Problem

Production pause time is never recorded. `WorkoutTimerService.pause()` cancels the only ticker, and the only code that increments `pausedAccumulated` is `simulator.advanceTime(..., active: false)`. The ticker only calls `advanceTimeStep(1, active: true)` while running, so a real pause adds nothing.

Reproduced against the actual service: start, run ~2s, pause 3s, resume ~2s, finish produced:

```text
elapsed=3.0  paused=0.0  active=3.0
```

Expected roughly `elapsed=7`, `paused=3`, `active=4`.

The same root cause means elapsed time is a count of timer ticks, not wall-clock time. Backgrounding, locking the device, or repeated pauses can all undercount.

Relevant code:

- `WODCounter/Services/WorkoutTimerService.swift:44-49` — pause cancels the ticker.
- `WODCounter/Services/WorkoutTimerService.swift:128-141` — ticker advances one second at a time.
- `WODCounter/Services/WorkoutTimerService.swift:106-126` — record uses accumulated simulator times.
- `WODCounter/Models/Sim/WODSimulator.swift:209-228` — `wallClock`/`pausedAccumulated` are incremented by deltas.

## Goal

Time is derived from a real timeline, not from the number of successful one-second sleeps.

## Scope

1. **Introduce a single session timeline.**
   - Suggested type: `SessionTimeline` or `SessionClock`, owned by `WorkoutTimerService`.
   - Store `startedAt`, `pauseStartedAt`, and `accumulatedPaused`.
   - Derive `wallElapsed`, `pausedElapsed`, and `activeElapsed` from the injected clock.
   - Use a monotonic source where possible; keep the existing injected `clock` test seam.
2. **Separate redraw from time accumulation.**
   - The one-second task should only refresh the published snapshot and check deadlines.
   - It must not be the source of truth for elapsed time.
   - On resume, recompute from timestamps rather than restarting a tick count.
3. **Handle app lifecycle explicitly.**
   - Recommended: auto-pause when the app becomes inactive/backgrounded and resume on explicit user action.
   - Document the chosen behavior in the ticket result and in code comments.
   - Do not silently lose time when the app returns to the foreground.
4. **Persist correct values.**
   - `WorkoutRecord.elapsedTime` = wall-clock elapsed.
   - `WorkoutRecord.pausedTime` = accumulated pause.
   - `WorkoutRecord.activeTime` = elapsed − paused.
5. **Keep for-time expiry based on active time.**
   - The 20:00 cap should use active elapsed time, not tick count.
   - Pausing must extend the wall-clock duration without extending the active cap.

## Acceptance criteria

- [ ] A 10s active / 5min pause / 10s active session records `elapsed ≈ 320`, `paused ≈ 300`, `active ≈ 20`.
- [ ] Pausing freezes the active clock and resumes from the same active value.
- [ ] Multiple pause/resume cycles accumulate correctly.
- [ ] Finishing while paused records the pause up to the finish moment.
- [ ] A background gap does not disappear from elapsed time; behavior is explicit.
- [ ] The for-time cap is still based on active time.
- [ ] Snapshot updates remain live at roughly one-second cadence.

## Tests

- Inject a fake clock; advance it manually instead of sleeping.
- Cover: start, active interval, pause, long pause, resume, second pause, finish.
- Cover finish while paused.
- Cover for-time expiry while active and while paused.
- Add an integration-style test that uses a short real wait only if necessary; the fake clock should be sufficient.

## Out of scope

- Rest-block selection (ticket 005).
- Duplicate-finish protection (ticket 003), although it may touch the same file.
- UI polish such as rest countdown (ticket 010).

## Result

**Status:** implemented (uncommitted, 2026-11-06).

- Added `SessionTimeline` (wall/paused/active derived from the injected clock) and moved `WorkoutTimerService` off tick-count time.
- The one-second ticker now refreshes and advances the simulator by the real active delta since the last refresh.
- Records use wall elapsed, accumulated pause, and wall-minus-paused active time; for-time expiry remains active-time based.
- `TimerView` auto-pauses when `scenePhase` leaves `.active`; resuming stays explicit.
- Tests use a mutable fake clock and cover long/multiple pauses, finish while paused, and active-time expiry.

