# WTB-005 — Correct rest semantics

- **Priority:** P1
- **Estimate:** M
- **Depends on:** 002, 004
- **Blocks:** 010
- **Suggested owner:** one agent; keep separate from results work

## Problem

Rest is applied from the wrong block, and per-exercise rest is dead configuration.

`reconcileAfterWork()` uses `currentBlock`, defined as the first incomplete round’s block, to choose `restAfterBlock`. That is not necessarily the block that just completed. Reproduced with a two-block workout:

```text
Block A rest=60, Block B rest=nil -> after completing A: phase=running, no rest
Block A rest=nil, Block B rest=60 -> after completing A: phase=resting, restDeadline=60
```

The second case starts rest after A even though the rest belongs to B.

Also, `Exercise.restSeconds` is stored and exposed in the custom builder, but the simulator never reads it. Users can configure per-exercise rest and it silently does nothing.

Relevant code:

- `WODCounter/Models/Sim/WODSimulator.swift:242-247` — `currentBlock` is first incomplete.
- `WODCounter/Models/Sim/WODSimulator.swift:258-283` — rest chosen from `currentBlock`.
- `WODCounter/Models/Exercise.swift:11` — `restSeconds`.
- `WODCounter/Views/CreateWODView.swift:162`, `:299` — per-exercise rest is written but unused.

## Goal

Rest is tied to the round/block that just completed, and there is no silently ignored rest setting.

## Scope

1. **Define the semantics.**
   - Recommended: `restAfterBlock` means “rest after each completed play of this block”; for `repeatTimes > 1` that is between rounds. Barbara-style rest works this way.
   - Document the definition in the model and handoff/spec.
2. **Fix selection.**
   - Refactor `reconcileAfterWork()` to track which round(s) actually completed during that call.
   - Use the completed round’s `blockIndex` to read that block’s rest.
   - Do not use the next block’s rest.
   - Do not enter rest after the final round of the workout.
   - Handle multiple completed rounds deterministically, even if it should normally be one.
3. **Handle repeated blocks.**
   - A block with `repeatTimes = 5` and `restAfterBlock = 180` rests after each of the first four rounds, not after the fifth.
   - Confirm whether the final round of a multi-block workout should rest before the next block; the rest belongs to the completed block, so yes if that block defines one.
4. **Resolve per-exercise rest.**
   - Recommended for v1: remove the per-exercise “Rest After (s)” input and stop writing `Exercise.restSeconds`; block-level rest covers the supported use case.
   - If the product wants per-set rest, implement it in the engine and add tests. Do not leave the field writable but ignored.
   - Update the spec/model docs to match the decision.
5. **Keep manual rest API consistent.**
   - `startRest(duration:)` may remain, but it should use a clearly defined target block.
   - `endRest()` should always resume the running phase and clear the deadline.

## Acceptance criteria

- [ ] A rest defined on block A fires after block A completes.
- [ ] A rest defined on block B does not fire after block A completes.
- [ ] No rest is entered after the final round of the workout.
- [ ] Repeated blocks rest between rounds, not after the final repetition.
- [ ] Pausing during rest preserves the remaining rest correctly once time handling from 002 is in place.
- [ ] Per-exercise rest is either implemented with tests or removed from the UI/model contract.
- [ ] Rest behavior is documented in the model and user-facing scheme copy.

## Tests

- Two-block workout with rest on A only.
- Two-block workout with rest on B only.
- Repeated block with rest.
- Final-round no-rest case.
- Pause/skip during rest.
- Custom workout with block rest.
- If per-exercise rest is implemented, assert it overrides or combines with block rest according to the documented rule.

## Out of scope

- Rest countdown UI and “skip rest” polish (ticket 010).
- Time accounting (ticket 002).

## Result

Implemented.

- **Semantics:** `RoundBlock.restAfterBlock` is rest after each completed play of that block. With `repeatTimes > 1` it is rest between rounds, never after the workout's final round. Rest belongs to the block that just completed, is measured in active time (pausing does not consume it), and multiple completions in one reconcile use the furthest completed round.
- **Engine:** `reconcileAfterWork()` tracks completed block indices and reads rest from the completed round's block, not the next/current block. Finishing the workout takes precedence over rest.
- **Manual rest:** `startRest(duration:)` targets the most recently completed block (falling back to the first incomplete block before any completion); explicit duration still wins. `endRest()` clears the deadline and resumes running from either resting or paused-mid-rest.
- **Per-exercise rest:** the “Rest After (s)” input and draft field were removed; `CreateWODView` no longer writes `Exercise.restSeconds`. The model field is retained with a deprecation comment for store compatibility only.
- **Tests:** added simulator coverage for rest on A only, rest on B only, rest on a middle block, repeated blocks, pause during rest, skip/end rest, and manual rest; added service-level pause/resume/skip-during-rest tests; added a custom-workout block-rest test.
- **Verification:** full suite green — 59 XCTest + 33 Swift Testing (92 total), 0 failures.
