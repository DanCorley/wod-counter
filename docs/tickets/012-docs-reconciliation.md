# WTB-012 — Docs reconciliation

- **Priority:** P3
- **Estimate:** S
- **Depends on:** decisions in 002, 005, 008
- **Suggested owner:** human or docs-focused agent

## Problem

`docs/superpowers/` is internally inconsistent, and some docs contradict the code.

- The plan header and Task 3 brief describe the old sequential per-rep engine (`advanceRep`, `playTarget`, `blockIndex/exerciseIndex`).
- The spec (v1.1) and handoff describe the free-form task tracker.
- The implementation is free-form.
- Plan tasks 3–9 are unchecked even though commits exist.
- The Task 3 brief says “do NOT regress” against behavior that is no longer the design.
- The spec says Angie is Hero; the code says Girl. Angie is a Girl benchmark; the spec/brief are wrong.
- The spec’s `Workout` table duplicates `category`, `mode`, `blocks`, `isBuiltin`, and timestamps.
- The spec includes a separate `WorkoutAttempt` model that the implementation intentionally merged into `WorkoutRecord`.
- The plan/Task 7 says for-time counts down; the spec flow and handoff say count up.
- README says macOS and Xcode 15+, while the app is iOS-only and Swift Testing requires Xcode 16.
- The iCloud copy says public database in the spec but private CloudKit in Settings, and neither is implemented.
- The plan references an Xcode workspace/project that is not committed.

## Goal

One reader can tell which document is authoritative, which behavior is current, and what is deliberately deferred.

## Scope

1. **Choose an authority order.**
   - Suggested: spec + handoff = current behavior; plan/briefs = historical task record.
   - Add a banner to the top of the plan and each brief: “Historical: describes the pre-free-form engine. See handoff/spec for current design.”
2. **Update the plan status.**
   - Mark tasks 0–9 accurately, including 3–9.
   - Note the engine rework commit (`5e2a197`) and the commit that reconciled docs (`614db20`).
3. **Fix the spec.**
   - Angie → Girl.
   - Remove duplicated `Workout` rows.
   - Decide whether `WorkoutAttempt` is deferred/rejected and document why `WorkoutRecord` is the single history row.
   - Align the platform and CloudKit wording with reality.
   - Document the rest semantics chosen in ticket 005.
   - Document the time/pause behavior chosen in ticket 002.
4. **Fix briefs.**
   - Task 3 contract should either be rewritten for free-form or explicitly marked historical.
   - Task 2’s `frank()` typo note can stay, but the factory is `fran()`.
   - Task 6’s History/Edit claims should reflect what shipped or be moved to tickets.
5. **Fix README.**
   - iOS 17, not macOS.
   - Xcode 16+ if Swift Testing remains.
   - Correct build/test commands after ticket 001.
   - Link to `docs/tickets/` for outstanding work.
6. **Record decisions.**
   - Add short decision records or a `docs/decisions/` folder for:
     - free-form engine,
     - single `WorkoutRecord`,
     - sync deferral or implementation,
     - rest semantics,
     - time model.

## Acceptance criteria

- [x] A new reader can identify the current design in under two minutes.
- [x] No doc claims macOS/macOS-only build.
- [x] Plan checkboxes match reality.
- [x] Angie category and duplicated Workout rows are fixed.
- [x] `WorkoutAttempt` status is explicit.
- [ ] Rest docs match the implemented behavior; **sync docs say "not implemented / pending 008"** and the sync decision itself is still open.
- [ ] README commands work from a clean checkout — not re-run in this docs-only pass.
- [x] `docs/tickets/README.md` is linked from the main docs index or README.

## Tests

- No code tests required.
- Run the documented commands once to confirm they work.
- Check all relative links in touched docs.

## Out of scope

- Rewriting every brief.
- Marketing copy.

## Result

**Status:** implemented (uncommitted, 2026-11-06). Docs-only change; no source or test files touched.

### Decisions recorded

- **Authority order:** spec + handoff = current behavior; plan + briefs = historical task record; `docs/tickets/` = live work. Stated in the spec, README, plan/briefs banners, and this index.
- **Free-form engine is current:** Task 3's sequential `advanceRep`/`playTarget`/index contract is marked historical. The plan notes the `5e2a197` rework and `614db20` docs reconciliation.
- **One history model:** `WorkoutAttempt` was intentionally merged into `WorkoutRecord` for v1; the spec now documents the single row and its metrics.
- **Timing:** `SessionTimeline` derives wall/paused/active time from injected-clock timestamps; the ticker is not the time source.
- **Rest:** `RoundBlock.restAfterBlock` belongs to the completed block, is active-time based, and `Exercise.restSeconds` is deprecated. Barbara is the spaced example; Helen is continuous.
- **Results delta:** best vs the latest chronological attempt in the selected window; `WindowSummary.bestTime` is optional; PR flags are historical.
- **iCloud sync:** **not implemented.** The Settings toggle remains a placeholder pending ticket 008; no doc claims sync works.

### Files changed

- `README.md`
- `docs/tickets/README.md`
- `docs/tickets/012-docs-reconciliation.md`
- `docs/implementation-handoff.md`
- `docs/superpowers/specs/2026-09-11-wod-counter-design.md`
- `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md`
- `docs/superpowers/plans/briefs/README.md`
- `docs/superpowers/plans/briefs/task-02-seed.md`
- `docs/superpowers/plans/briefs/task-03-simulator.md`
- `docs/superpowers/plans/briefs/task-04-results-service.md`
- `docs/superpowers/plans/briefs/task-05-timer-service.md`
- `docs/superpowers/plans/briefs/task-06-home-detail-settings.md`
- `docs/superpowers/plans/briefs/task-07-timer-view.md`
- `docs/superpowers/plans/briefs/task-08-results-view.md`
- `docs/superpowers/plans/briefs/task-09-create-wod.md`

### Link check

Relative markdown links in the touched docs were checked against the filesystem (see final report). No dead file targets.

### Remaining pending

- **WTB-008** iCloud sync decision is still open; do not implement or remove the Settings toggle until a human decides.
- README build/test commands were not re-run in this docs-only pass.
