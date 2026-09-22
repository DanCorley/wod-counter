# Per-task agent briefs — WOD Round Counter

Each file here is a **self-contained brief for one implementation task**, meant to be handed
to a single agent that works one task at a time. Read the tasks in order.

| # | File | Task |
|---|------|------|
| 00 | [task-00-project-scaffold.md](task-00-project-scaffold.md) | Scaffold + app entry + `ModelContainer` + seed migration |
| 01 | [task-01-models.md](task-01-models.md) | SwiftData models (the contract every other task consumes) |
| 02 | [task-02-seed.md](task-02-seed.md) | Benchmark seed data + idempotent migration |
| 03 | [task-03-simulator.md](task-03-simulator.md) | `WODSimulator` — pure progression engine (multi-block state machine) |
| 04 | [task-04-results-service.md](task-04-results-service.md) | `ResultsService` & `Format` — windowed stats + PR detection |
| 05 | [task-05-timer-service.md](task-05-timer-service.md) | `WorkoutTimerService` — clock + pause + persist on finish + `AppModel` |
| 06 | [task-06-home-detail-settings.md](task-06-home-detail-settings.md) | Views: Home / WOD Detail / Settings (incl. iCloud toggle) |
| 07 | [task-07-timer-view.md](task-07-timer-view.md) | View: Timer (interactive workout runner) |
| 08 | [task-08-results-view.md](task-08-results-view.md) | View: Results & Share Card (`ResultsCardView`) |
| 09 | [task-09-create-wod.md](task-09-create-wod.md) | View: Create WOD (custom workout builder) |

## How to use
- **One brief = one agent = one task.** The agent implements the task TDD-style, ends green,
  and commits once (diffing against the previous HEAD). Then hand the next brief to a fresh agent.
- **Each brief is self-contained:** it names the files to create/modify, the exact interface
  contracts to consume from previous tasks, the steps with code, and the done criteria.
- **Three reference docs accompany every brief:**
  - **Spec** (`docs/superpowers/specs/2026-09-11-wod-counter-design.md`) — requirements/authority.
  - **Handoff** (`docs/implementation-handoff.md`) — mechanics, full source, tooling.
  - **Plan** (`docs/superpowers/plans/2026-09-11-wod-counter-implementation.md`) — task list + architecture.
- **Tooling:** use Xcode 16 with file-system synchronization (`WODCounter/` and `WODCounterTests/`); run `xcodebuild test` for unit tests.
- **Global constraints apply to every task** (iOS 17.0, SwiftUI + SwiftData + Swift Concurrency,
  offline-first, opt-in iCloud, YAGNI, TDD, no placeholders) — see the plan's Global Constraints.

## Recommended execution
Tasks 0–2 build storage/data/models sequentially (0 → 1 → 2).
Task 3 implements the pure simulator engine (tested in `WODCounterTests/Sim/`).
Task 4 provides `ResultsService` and formatters.
Task 5 bridges the simulator to the real clock and persistence, utilizing `ResultsService` for PR evaluation.
Tasks 6–9 are UI layers built on the established service foundation.

## Cross-task contracts (interface handshake)
- **Task 0** produces the container schema + idempotent `SeedMigration`.
- **Task 1** produces the `@Model` types — **exact fields are the contract** (`ExecutionMode`, `Movement`,
  `Exercise`, `RoundBlock`, `Workout`, `WorkoutRecord`).
- **Task 2** produces `BenchmarkSeed` with pre-rendered `displayLabel`s.
- **Task 3** produces `WODSimulator`/`TimerEvent`/`SessionSnapshot` (pure engine).
- **Task 4** produces `ResultsService` (`summary`, `history`, `isNewPR`) + `Format` (duration/timer formatters).
- **Task 5** produces `WorkoutTimerService` + `AppModel`/`ServiceFactory` (clock ticker, pause/active time, record persistence).
- **Task 6** consumes `AppModel`/`Route` for Home, Detail, and Settings navigation.
- **Task 7** consumes `WorkoutTimerService` + `SessionSnapshot` for the interactive timer.
- **Task 8** consumes `ResultsService` + `Format` for the results dashboard and share card.
- **Task 9** consumes models and context to build and save custom WODs.
