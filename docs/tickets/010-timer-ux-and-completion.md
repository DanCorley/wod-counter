# WTB-010 — Timer UX and completion flow

- **Priority:** P2
- **Estimate:** M
- **Depends on:** 002, 003, 005
- **Suggested owner:** one agent after core timer behavior is stable

## Problem

The timer works, but several user-facing gaps make accidental data loss and missed context likely:

- The Close button dismisses a live session without confirmation or saving (`TimerView.swift:61-67`).
- The rest banner says only “Resting...” and gives no remaining time (`TimerView.swift:256-272`).
- A mis-tapped +1/+5 cannot be undone.
- The completion sheet has no Share action or PR indicator (`TimerView.swift:313-370`).
- The scheme/detail screen has no History shortcut, despite the plan.
- The flat task list does not group repeated blocks/rounds, which becomes long for DT (15 tasks) or high-repeat custom WODs.
- Accessibility labels for the live clock, remaining reps, and rest state are mostly default-only.

## Goal

The timer is safe to use mid-workout, communicates rest/round context, and lets the athlete share a completed result.

## Scope

1. **Close/discard protection.**
   - If the session is running/paused/resting, show a confirmation sheet: Keep Working / Discard Session.
   - Do not persist a record for a discarded session unless the user explicitly chooses Finish.
   - If the session is idle or finished, Close can dismiss directly.
2. **Rest countdown.**
   - Show remaining rest time based on the session timeline.
   - Keep Skip Rest.
   - Announce rest start/end accessibly.
3. **Undo rep logging.**
   - Add a decrement/undo action for the active task or the last logged action.
   - Recommended: maintain a small stack of `(taskID, count)` and let Undo reverse the latest addition.
   - Clamp at zero; do not let undo cross into another task accidentally.
4. **Completion flow.**
   - Show PR status and share action in the completion sheet.
   - Reuse `ResultsCardView` / the existing share image path.
   - Keep Done → dismiss.
5. **Navigation gaps.**
   - Add a History button on `WODDetailView` for completed custom/builtin workouts.
   - Ensure it routes to the Results tab or a results screen without breaking the existing tab structure.
6. **Task presentation.**
   - Group tasks by round/block when `totalRounds > 1` or multiple blocks exist.
   - Keep the flat quick-counter behavior; the active task should remain obvious.
7. **Accessibility.**
   - Add labels/values for the clock, remaining reps, selected task, and rest state.
   - Respect Dynamic Type; avoid fixed heights that truncate.

## Acceptance criteria

- [ ] Closing a live session requires confirmation and does not silently lose it.
- [ ] Rest shows remaining time and can be skipped.
- [ ] Undo reverses the latest rep addition for the intended task.
- [ ] Completion sheet shows PR/share and shares a correct card.
- [ ] Detail screen offers History for a workout with records.
- [ ] Multi-round task lists are grouped or otherwise clearly labeled.
- [ ] VoiceOver can identify the clock, remaining reps, active task, and rest state.
- [ ] No duplicate records from closing/finishing paths (covered with 003).

## Tests

- Timer service test for undo: add 5, undo, assert remaining/progress restored.
- Undo at zero is a no-op.
- Completion/share card renders the correct record and PR badge.
- Close confirmation logic is testable at the view-model/service level where possible.
- Manual simulator smoke test for VoiceOver and Dynamic Type.

## Out of scope

- Apple Watch/Health integration.
- New workout modes.
- Engine rest semantics (ticket 005).

## Result

Implemented (2026-11-06):

- Live sessions require a Keep Working / Discard Session confirmation; discard dismisses without persisting a record.
- `SessionSnapshot.restRemaining` exposes the active-time rest countdown; the timer banner shows it and keeps Skip Rest.
- `WorkoutTimerService` keeps a partial-rep undo stack backed by `WODSimulator.removeReps`. Undo is cleared when a task or round completes.
- `WorkoutTimerService.completedRecord` exposes the saved record; the completion sheet shows the existing results card, PR badge, and a rendered-card ShareLink.
- `WODDetailView` shows a History section linking to the existing `WODAttemptsView` drill-down when records exist.
- Task lists group by block/round for multi-round or multi-block workouts.
- Clock, remaining reps, active task, and rest state have accessibility labels/values; key timer text scales with Dynamic Type.
