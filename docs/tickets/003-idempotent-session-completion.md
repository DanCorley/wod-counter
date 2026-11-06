# WTB-003 — Idempotent session completion

- **Priority:** P1
- **Estimate:** S
- **Depends on:** 002
- **Suggested owner:** same agent as 002

## Problem

`WorkoutTimerService.finish()` has no “already finished” guard, and `handleFinishedSession()` has no “already persisted” guard. Calling `finish()` twice invokes `onFinish` twice; with `ServiceFactory`, that inserts and saves two `WorkoutRecord`s.

Reproduced: `onFinish calls after double finish = 2`.

Relevant code:

- `WODCounter/Services/WorkoutTimerService.swift:81-88` — finish always calls `handleFinishedSession()`.
- `WODCounter/Services/WorkoutTimerService.swift:106-126` — builds and emits a record on every call.
- `WODCounter/Services/WorkoutTimerService.swift:59-67` — auto-stop also calls `handleFinishedSession()`.

## Goal

One workout session produces exactly one persisted record, regardless of how many completion paths fire.

## Scope

1. Add an internal `hasPersisted` / `didFinish` flag to `WorkoutTimerService`.
2. Make `finish()` return early when the simulator is already `.finished`.
3. Make `handleFinishedSession()` return early after the first successful emission.
4. Do not persist a record when `finish()` is called while `.idle`.
5. Decide and document behavior for finish while `.paused` and `.resting`; both should produce exactly one record.
6. Consider surfacing a save failure instead of silently swallowing it in `ServiceFactory`; at minimum log/assert in debug.

## Acceptance criteria

- [ ] Double `finish()` emits one `onFinish` call.
- [ ] Auto-stop followed by manual finish emits one record.
- [ ] Finish while idle does not persist a zero-length workout.
- [ ] Finish while paused/resting still produces the correct active/paused values.
- [ ] `ServiceFactory` inserts exactly one record for a completed session.
- [ ] Tests assert record count, not only `isPR` or last record.

## Tests

- Double finish.
- Auto-stop via final rep, then `finish()`.
- Auto-stop via clock expiry, then `finish()`.
- Finish while idle.
- Finish while paused.
- Full `ServiceFactory` path with an in-memory `ModelContext`.

## Out of scope

- Time calculation (ticket 002).
- Sync or cross-device deduplication (ticket 008).
- Retry/offline queue for failed saves.

## Result

**Status:** implemented (uncommitted, 2026-11-06).

- `finish()` returns early when already finished or idle.
- `handleFinishedSession()` emits/persists at most once per session; `reset()` clears the flag.
- Tests cover double finish, auto-stop then manual finish, clock expiry then finish, idle finish, finish while paused, and a `ServiceFactory` record count of exactly one.

