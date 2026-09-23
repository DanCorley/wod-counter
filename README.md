# WODCounter

A macOS CrossFit Workout of the Day (WOD) counter and timer built with SwiftUI and SwiftData.

Track benchmark WODs, build custom workouts, run live timed sessions, and review your results — all on device.

## Features

- **Built-in benchmark library** — Seeds 8 classic WODs (Cindy, Murph, Fran, Angie, Grace, Diane, Helen, DT) across the Girl and Hero categories.
- **Custom WOD builder** — Create your own workouts with configurable blocks, rounds, reps, and per-movement labels.
- **Live workout timer** — Run sessions with an elapsed clock, free-form task timing, quick counters, and per-block progression while you work.
- **Top Time & For Time modes** — Race to completion (Top Time) or run continuous AMRAP-style rounds (For Time).
- **Results & sharing** — Review past results and generate shareable result cards.
- **Pure logic core** — A deterministic `WODSimulator` progression engine powers timing and round tracking, fully unit-tested.
- **Offline-first** — All data persists locally via SwiftData; no network or cloud dependencies.

## Tech Stack

- Swift 5.9+ / SwiftUI
- SwiftData (macOS 14+)
- XCTest for unit and smoke tests
- Xcode project built with XcodeGen-friendly layout (`WODCounter/`, `WODCounterTests/`)

## Getting Started

Requirements: macOS 14+, Xcode 15+.

1. Clone the repository.
2. Open `wod-counter.xcodeproj` in Xcode.
3. Select the `WODCounter` scheme and run.

## Tests

Run the test suite from the command line:

```sh
xcodebuild test -project wod-counter.xcodeproj -scheme WODCounter -destination 'platform=macOS'
```

Coverage includes the simulator engine, timer service, results service, benchmark seeding, and view smoke tests.

## Project Layout

```
WODCounter/
  AppModel.swift          # App-level state and orchestration
  Models/                 # SwiftData models (Workout, RoundBlock, Exercise, ...)
  Models/Sim/             # WODSimulator + TimerEvent + SessionSnapshot
  Services/               # WorkoutTimerService, ResultsService
  Support/                # BenchmarkSeed, Format, Container, SeedMigration
  Views/                  # SwiftUI screens (Home, Timer, Results, Settings, ...)
WODCounterTests/          # XCTest suite mirroring the source layout
```

## License

[MIT](LICENSE)