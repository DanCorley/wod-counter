# WTB-001 — Make the project buildable and testable

- **Priority:** P0
- **Estimate:** M
- **Depends on:** —
- **Blocks:** all other tickets
- **Suggested owner:** one agent or human; do not parallelize

## Problem

The repository has source and tests but no reproducible Xcode project or package. `xcodebuild -list` fails with:

```text
The directory ... does not contain an Xcode project, workspace or package.
```

There is no `Project.yml`, `Package.swift`, or checked-in `.xcodeproj`. The README tells the reader to open `wod-counter.xcodeproj`, but `.gitignore` ignores `*.xcodeproj/` and `*.xcworkspace/`.

A plain typecheck also exposes two build blockers:

- `WODCounter/Support/SeedMigration.swift:6` — `ModelContainer.mainContext` is main-actor isolated but `applySeed` is nonisolated.
- `WODCounter/Models/Sim/WODSimulator.swift:51` — `WODSimulator` declares `Sendable` while storing a non-`Sendable` `Workout`; this is a warning in Swift 5 mode and an error in Swift 6 mode.

## Goal

A clean clone can generate/open the project, build the app, and run the full test suite with one documented command.

## Scope

1. **Commit a reproducible project definition.**
   - Preferred: commit `Project.yml` for XcodeGen and a generated scheme config.
   - Alternative: commit a checked-in Xcode project/workspace if the team prefers.
   - Target **iOS 17.0**, matching the spec. Do not target macOS; the current views use iOS-only APIs.
2. **Include both targets.**
   - App target: `WODCounter`.
   - Test target: `WODCounterTests`, including every existing test file.
3. **Fix the compiler blockers.**
   - Make `SeedMigration.applySeed` main-actor isolated, or obtain the context with `ModelContext(container)` instead of `mainContext`. Update callers.
   - Remove `Sendable` from `WODSimulator` (the service is already `@MainActor`) or make it genuinely value-based and sendable. Do not leave the Swift 6 error in place.
4. **Add a one-command CI path.**
   - Example: `scripts/ci.sh` that runs `xcodegen generate`, then `xcodebuild build`, then `xcodebuild test`.
   - Use a concrete simulator destination; do not rely on a developer's locally selected device.
   - If a simulator name is unavailable on CI, use `-destination 'generic/platform=iOS Simulator'` for build and a known runtime for tests.
5. **Update `README.md`.**
   - State iOS 17+, not macOS 14+.
   - Document Xcode/XcodeGen prerequisites and the actual build/test commands.
   - Remove the reference to a project file that does not exist unless the project is committed.

## Acceptance criteria

- [ ] `xcodebuild -list` sees a project/workspace and the `WODCounter` scheme.
- [ ] A clean clone can build the app after the documented setup command.
- [ ] `xcodebuild test` runs the full `WODCounterTests` suite.
- [ ] No actor-isolation or `Sendable` errors remain in the touched files.
- [ ] README platform and commands match reality.
- [ ] CI script exits non-zero on build or test failure.

## Tests and verification

- Run the full suite, not only the new ticket tests.
- Verify a clean build directory, not just an incremental build.
- Confirm the app launches in the simulator after the project is generated.

## Out of scope

- Product bugs in the timer, results, rest, sync, or custom editor.
- Changing UI behavior.
- Committing generated build artifacts or `DerivedData`.
