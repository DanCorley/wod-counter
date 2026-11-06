# Work-to-be-done tickets — WOD Counter

Created: 2026-11-06
Source: review of `docs/superpowers/` against the implementation.

Status: **implemented** — tickets 001–012 are complete (see each ticket's Result section). iCloud sync is deliberately deferred to v1.1.

## Authority order

- **Current behavior:** the [design spec](../superpowers/specs/2026-09-11-wod-counter-design.md) and [implementation handoff](../implementation-handoff.md). If they disagree with code, fix the docs or file a ticket.
- **Historical task record:** the [implementation plan](../superpowers/plans/2026-09-11-wod-counter-implementation.md) and [task briefs](../superpowers/plans/briefs/). These describe the original sequential per-rep plan; the shipped engine is a free-form task tracker.
- **Live work items:** this ticket index and the individual ticket files.
- **Deliberately deferred:** iCloud sync ([008](008-cloudkit-sync-decision.md)) is deferred to v1.1. The settings toggle has been removed; the app is local-only.

## How to use these tickets

- One ticket = one branch / worktree / reviewable PR.
- Start a ticket only after its dependencies are merged.
- Keep the change scoped to the ticket. No opportunistic refactors.
- Every ticket ends with tests green and the acceptance checklist complete.
- Update the status here and append a short `Result` section to the ticket when done.
- If a ticket contains a product decision, record the decision in the ticket before implementing.

## Ticket index

| ID | Ticket | Priority | Depends on | Good subagent task? |
|---|---|---|---|---|
| [001](001-buildable-project-and-ci.md) | Make the project buildable and testable | P0 | — | No — foundation/setup, do first with one owner |
| [002](002-session-clock-and-pause.md) | Session clock and pause/elapsed time | P0 | 001, 004 | Yes, after 004 |
| [003](003-idempotent-session-completion.md) | Idempotent session completion | P1 | 002 | Yes |
| [004](004-explicit-ordering.md) | Explicit block/exercise ordering | P1 | 001 | Yes |
| [005](005-rest-semantics.md) | Correct rest semantics | P1 | 002, 004 | Yes, after 002/004 |
| [006](006-results-correctness.md) | Results correctness and performance | P1 | 002, 003 | Yes |
| [007](007-settings-window-wiring.md) | Settings window wiring | P2 | 006 | Yes, small |
| [008](008-cloudkit-sync-decision.md) | iCloud sync decision | P2 | 001, 004 | Human decision first |
| [009](009-custom-wod-editing.md) | Custom WOD editing | P2 | 004 | Yes |
| [010](010-timer-ux-and-completion.md) | Timer UX and completion flow | P2 | 002, 003, 005 | Yes, after core |
| [011](011-test-hardening.md) | Test hardening | P2 | 001–010 | Yes, final pass |
| [012](012-docs-reconciliation.md) | Docs reconciliation | P3 | decisions in 002, 005, 008 | Human or docs agent |

## Execution waves

### Wave 0 — foundation
1. **001** — buildable project, CI, compiler fixes.
2. **004** — explicit ordering. Do this before the engine/time work because later tickets depend on stable block order.

### Wave 1 — core correctness
3. **002** — session clock and pause.
4. **003** — idempotent completion. Same service area as 002; best done immediately after it.
5. **006** — results correctness. Can start once 002/003 are in place.

### Wave 2 — behavior and UI
6. **005** — rest semantics. Needs 002 and 004.
7. **009** — custom WOD editing. Independent of the timer work.
8. **007** — settings window wiring. Do after 006 because both touch `ResultsView`.
9. **008** — sync decision. Can run in parallel, but needs a human decision before implementation.

### Wave 3 — finish
10. **010** — timer UX and completion flow. Needs the core timer/rest behavior settled.
11. **011** — test hardening. Final sweep across the feature tickets.
12. **012** — docs reconciliation. Do after decisions and behavior are final.

## Suggested subagent batching

The work is not all parallel-safe. The main conflict points are:

- `WODSimulator.swift`: tickets 002, 004, and 005.
- `WorkoutTimerService.swift`: tickets 002 and 003.
- `ResultsView.swift` / `ResultsService.swift`: tickets 006 and 007.
- `TimerView.swift`: tickets 002, 005, and 010.
- `CreateWODView.swift`: tickets 004 and 009.

Recommended batches:

1. **Single agent:** 001. Do not parallelize project setup/CI.
2. **Single agent:** 004, then 002, then 003. These touch the same engine/service files and are easier to review as one sequence.
3. **Two or three parallel agents after that:**
   - Agent A: 005 (engine rest semantics).
   - Agent B: 006 (results service/view) — then 007.
   - Agent C: 009 (custom editor).
4. **Final pass:** 010, then 011, then 012. These are review-heavy and should not race with the core tickets.

## Definition of done for every ticket

- [ ] Implementation matches the ticket scope.
- [ ] New/updated tests cover the reported failure and the fixed behavior.
- [ ] Full test suite green (`xcodebuild test` once 001 exists).
- [ ] No new compiler warnings in the touched area.
- [ ] Docs/comments updated where behavior or semantics changed.
- [ ] No unrelated files or refactors included.
