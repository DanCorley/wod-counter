# WODCounter

An iOS CrossFit Workout of the Day (WOD) counter and timer built with SwiftUI and SwiftData.

Track benchmark WODs, build custom workouts, run live timed sessions, and review your results — all on device.

## Features

- **Built-in benchmark library** — Seeds 8 classic WODs (Cindy, Murph, Fran, Angie, Grace, Diane, Helen, DT) across the Girl and Hero categories.
- **Custom WOD builder** — Create your own workouts with configurable blocks, rounds, reps, and per-movement labels.
- **Live workout timer** — Run sessions with an elapsed clock, free-form task timing, quick counters, and per-block progression while you work.
- **Top Time & For Time modes** — Race to completion (Top Time) or run continuous AMRAP-style rounds (For Time).
- **Results & sharing** — Review past results and generate shareable result cards.
- **Pure logic core** — A deterministic `WODSimulator` progression engine powers timing and round tracking, fully unit-tested.
- **Offline-first** — All data persists locally via SwiftData. iCloud sync is **deferred to v1.1**; see [ticket 008](docs/tickets/008-cloudkit-sync-decision.md).

## Documentation

Use these in this order:

- **Current behavior:** [design spec](docs/superpowers/specs/2026-09-11-wod-counter-design.md) and [implementation handoff](docs/implementation-handoff.md).
- **Live work items:** [docs/tickets/](docs/tickets/) — the work tracker.
- **Historical task record:** [implementation plan](docs/superpowers/plans/2026-09-11-wod-counter-implementation.md) and [task briefs](docs/superpowers/plans/briefs/) (the original per-rep plan; the app now uses a free-form task tracker).
- **iCloud sync:** not available in v1. The app is local-only; sync is deferred to v1.1 and tracked in [WTB-008](docs/tickets/008-cloudkit-sync-decision.md).

## Tech Stack

- Swift 5.9+ / SwiftUI
- SwiftData (iOS 17+)
- XCTest and Swift Testing for unit and smoke tests (mixed intentionally; see below)
- Xcode project generated from `Project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)

> **Test framework decision:** the suite intentionally mixes XCTest (service,
> simulator, model, and seed tests) with Swift Testing (the SwiftUI-facing
> `CreateWODViewTests` and `ResultsViewTests`). Both run in the same test target.
> We keep the split rather than rewriting working tests for consistency: XCTest
> covers `@MainActor` service lifecycle and SwiftData fixtures, while Swift
> Testing's `#expect`/`#require` reads well for value-style view-model tests.
> This requires **Xcode 16 or later**, which ships the Swift Testing runtime.

## Requirements

- macOS with **Xcode 16 or later** (Swift Testing is used by the test target)
- **iOS 17.0+** deployment target
- **XcodeGen** (`brew install xcodegen`)

The generated `WODCounter.xcodeproj` is not committed; it is recreated from `Project.yml`.

## Getting Started

1. Clone the repository.
2. Install XcodeGen:

   ```sh
   brew install xcodegen
   ```

3. Generate the project:

   ```sh
   xcodegen generate --spec Project.yml
   ```

4. Open `WODCounter.xcodeproj` in Xcode, select the `WODCounter` scheme, and run on an iOS 17+ simulator or device.

## Build and Test

Build the app from the command line:

```sh
xcodebuild -project WODCounter.xcodeproj -scheme WODCounter \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Run the full test suite on a simulator:

```sh
xcodebuild -project WODCounter.xcodeproj -scheme WODCounter \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

Simulator names depend on the installed Xcode/runtime. If that device is not
available, list one with `xcrun simctl list devices available` and substitute
the name (for example `iPhone 16` on older Xcode versions). CI defaults to
`iPhone 16`; override it with `TEST_DESTINATION` as shown below.

Tests require an installed iOS Simulator runtime. Build with `generic/platform=iOS` if none is available.

### One command (CI)

`scripts/ci.sh` generates the project, builds, and tests. The XcodeGen binary and
destinations are configurable by environment variable:

```sh
XCODEGEN=/path/to/xcodegen \
BUILD_DESTINATION='generic/platform=iOS' \
TEST_DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro' \
./scripts/ci.sh
```

On this machine the working invocation is:

```sh
XCODEGEN=/private/var/folders/wx/kwqbqyyj18g_02xtzxvpy0fw0000gp/T/opencode/tools/xcodegen/bin/xcodegen \
TEST_DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro' \
./scripts/ci.sh
```

It exits non-zero on the first failure.

## Project Layout

```
Project.yml               # XcodeGen project definition (source of truth)
scripts/ci.sh             # Generate + build + test
WODCounter/
  AppModel.swift          # App-level state and orchestration
  Models/                 # SwiftData models (Workout, RoundBlock, Exercise, ...)
  Models/Sim/             # WODSimulator + TimerEvent + SessionSnapshot
  Services/               # WorkoutTimerService, ResultsService
  Support/                # BenchmarkSeed, Format, Container, SeedMigration
  Views/                  # SwiftUI screens (Home, Timer, Results, Settings, ...)
WODCounterTests/          # XCTest + Swift Testing suite mirroring the source layout
```

## License

[MIT](LICENSE)
