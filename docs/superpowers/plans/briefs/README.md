# Per-task agent briefs — WOD Round Counter

Each file here is a **self-contained brief for one implementation task**, meant to be handed
to a single agent that works one task at a time. Read the task in order.

| # | File | Task |
|---|------|------|
| 00 | [task-00-project-scaffold.md](task-00-project-scaffold.md) | Scaffold + app entry + `ModelContainer` + seed migration |
| 01 | [task-01-models.md](task-01-models.md) | SwiftData models (the contract every other task consumes) |
| 02 | [task-02-seed.md](task-02-seed.md) | Benchmark seed data + idempotent migration |
| 03 | [task-03-simulator.md](task-03-simulator.md) | `WODSimulator` — pure progression engine (highest test value) |
| 04 | [task-04-timer-service.md](task-04-timer-service.md) | `WorkoutTimerService` — clock + pause + persist on finish |
| 05 | [task-05-results-service.md](task-05-results-service.md) | `ResultsService` — windowed stats + PR detection |
| 06 | [task-06-home-detail-settings.md](task-06-home-detail-settings.md) | Views: Home / WOD Detail / Settings (incl. iCloud toggle) |
| 07 | [task-07-timer-view.md](task-07-timer-view.md) | View: Timer |
| 08 | [task-08-results-create-wod.md](task-08-results-create-wod.md) | Views: Results + Create WOD |

## How to use
- **One brief = one agent = one task.** The agent implements the task TDD-style, ends green,
  and commits once (diffing against the previous HEAD). Then hand the next brief to a fresh agent.
- **Each brief is self-contained:** it names the files to create/modify, the exact interface
  contracts to consume from previous tasks, the steps with code, and the done criteria.
- **Three reference docs accompany every brief:**
  - **Spec** (`docs/superpowers/specs/2026-09-11-wod-counter-design.md`) — requirements/authority.
  - **Handoff** (`docs/implementation-handoff.md`) — mechanics, full source, tooling.
  - **Plan** (`docs/superpowers/plans/2026-09-11-wod-counter-implementation.md`) — task list + architecture.
- **Tooling:** use XcodeGen (`xcodegen generate`) + `xcodebuild`; run `… test` for the task's tests.
- **Global constraints apply to every task** (iOS 17.0, SwiftUI + SwiftData + Swift Concurrency,
  offline-first, opt-in iCloud, YAGNI, TDD, no placeholders) — see the plan's Global Constraints.

## Recommended execution
Tasks 0–2 build storage/data/logic and are mostly sequential (1 → 2 → 3 → 4 → 5). Tasks 3 and 4 are
independent of seed data (3 is tested against fabricated `Workout`s), so 3 and 4 can run in either order.
Tasks 6–8 are UI and build on the services above. Dispatch one brief per agent; review between tasks.

## Cross-task contracts (interface handshake)
- **Task 0** produces the container schema + idempotent `SeedMigration`.
- **Task 1** produces the `@Model` types — **exact fields are the contract** (ExecutionMode, Movement,
  Exercise, RoundBlock, Workout, WorkoutRecord). Every later task depends on these.
- **Task 3** produces `WODSimulator`/`TimerEvent`/`SessionSnapshot` (pure engine).
- **Task 4** produces `WorkoutTimerService` + `AppModel`/`ServiceFactory` (the timer + app state).
- **Task 5** produces `ResultsService` (consumes `isNewPR` for PR detection).
- **Task 6** consumes `AppModel`/`Route`; targets `ResultsView` (Task 8) for History.
- **Task 7** consumes `WorkoutTimerService` + `SessionSnapshot`.
- **Task 8** consumes `ResultsService` + `ResultsCardData`.
