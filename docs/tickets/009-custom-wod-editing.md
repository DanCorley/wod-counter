# WTB-009 — Custom WOD editing

- **Priority:** P2
- **Estimate:** M
- **Depends on:** 004
- **Suggested owner:** one agent; independent of results/timer work

## Problem

The spec says custom workouts are editable and savable. The implementation only supports creation and deletion.

- `CreateWODView` builds a new `Workout` and inserts it.
- `WODDetailView` offers Delete for non-builtins, but no Edit.
- `Workout.updatedAt` is never updated.
- There is no way to correct a typo, change reps/weight/distance, reorder exercises, or adjust rest after saving.

Relevant code:

- `WODCounter/Views/CreateWODView.swift`.
- `WODCounter/Views/WODDetailView.swift:61-75`.
- `WODCounter/Models/Workout.swift`.

## Goal

A user can open an existing custom WOD, edit its fields, save, and see the changes immediately on Home/Detail and in a new timer session.

## Scope

1. **Add an edit entry point.**
   - Show Edit on `WODDetailView` only for non-builtins.
   - Present `CreateWODView` in an edit mode with the existing workout loaded.
2. **Refactor the builder into a reusable editor.**
   - Suggested: add an `editingWorkout: Workout?` initializer or a small `WorkoutDraft` model that can be populated from an existing workout.
   - Keep creation behavior unchanged.
3. **Populate drafts from existing data.**
   - Name, mode, time cap, repeat count, rest, exercises, reps, weight, distance, unit, and per-exercise fields as applicable.
   - Respect ordered exercises from ticket 004.
4. **Update in place.**
   - Update the existing `Workout` rather than inserting a duplicate.
   - Update existing `Exercise` rows where possible; delete removed exercises; create new ones.
   - Update `updatedAt`.
   - Preserve `createdAt`, `isBuiltin`, and category `"Custom"`.
   - Reject editing built-ins defensively, even if the UI hides the button.
5. **Validation.**
   - Reuse the same validation as creation.
   - Prevent saving an edit that leaves the workout with no exercises.
   - Surface save errors.
6. **Ordering.**
   - Preserve current exercise/block order.
   - Add drag-to-reorder only if it fits the form; otherwise keep the existing order stable.

## Acceptance criteria

- [ ] A custom workout can be opened in edit mode from its detail screen.
- [ ] Saving edits updates the same workout, not a second copy.
- [ ] Home and Detail show the updated name/scheme immediately.
- [ ] Starting the edited workout uses the updated prescriptions.
- [ ] Removed exercises are deleted; added exercises are persisted.
- [ ] `updatedAt` changes and `createdAt` does not.
- [ ] Built-in workouts cannot be edited through the UI or model helper.
- [ ] Validation errors are shown and do not partially save.

## Tests

- Load a custom workout into draft form and assert all fields round-trip.
- Edit name/reps/weight/distance/rest and save; fetch by the same identity; assert one workout and updated values.
- Remove one exercise and add another; assert the block contains exactly the expected set.
- Attempt to edit a builtin; assert rejection.
- Invalid edit leaves the stored workout unchanged.
- Order remains stable after editing (depends on 004).

## Out of scope

- Editing built-in WODs.
- Multi-block custom builder beyond what already exists.
- CloudKit conflict resolution for concurrent edits (ticket 008).

## Result

Implemented 2026-11-06.

- `WODDetailView` shows Edit for non-builtins and presents `CreateWODView(editingWorkout:)`.
- `CreateWODView` now has an edit initializer, a `WorkoutDraft` loader that respects `sortOrder`, and `updateWorkout(_:...)` which reuses existing `Exercise` rows, deletes removed ones, inserts added ones, assigns sequential `sortOrder`, and updates `updatedAt` while preserving `createdAt`/`isBuiltin`/`Custom`.
- Validation is shared with creation and runs before any mutation; builtins are rejected defensively; save errors roll back.
- Tests cover field round-trip, in-place edits, add/remove ordering, builtin rejection, invalid-edit no-op, and simulator reading the edited scheme.
- Full suite: 62 XCTest + 50 Swift Testing tests, 0 failures.
