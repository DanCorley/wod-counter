# Task 0 — Project scaffold, app entry, ModelContainer, seed migration

**Deliverable:** A compiling SwiftUI app with an empty (non-memory-only) SwiftData container ready to receive built-in WODs. No app screens are required beyond Home + a route to History.

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md`
- **Handoff (mechanics):** `docs/implementation-handoff.md` — read § 4 (scaffold), § 5 (data model), § 10 (iCloud/CloudKit), § 12 (constraints), § 13 (Tasks).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 0.
- **Siblings (create later, do NOT build yet):** Task 1 models, Task 2 seed. Task 0 must match the model-type list exactly so Task 1/2 can drop in.

## Global constraints (verbatim)
- iOS, Apple-native only (no web/Android). Deployment target **iOS 17.0**.
- Stack: **SwiftUI + SwiftData + Swift Concurrency**.
- Offline-first; workout data never leaves the device. iCloud/CloudKit sync is **opt-in** (Task 6/Settings).
- **TDD:** end green. **Frequent commits** (one per task). **No placeholders.**
- Every `@Model` in `Models/`. Small, focused files.

## Files
- **Create:** `WODCounter/WODCounterApp.swift`
- **Create:** `WODCounter/Support/SeedMigration.swift`

## Interfaces (what you produce)
- A shared `modelContainer` instance (acquired via a `static let` + `@MainActor`).
- An idempotent `applySeed(to container:)` that inserts built-in workouts only if none exist.

## Steps
- [ ] **Step 1** — In `WODCounterApp.swift`: create `@main struct WODCounterApp: App` with `WindowGroup { RootView() }`. Build `modelContainer(for: [Movement.self, Exercise.self, RoundBlock.self, Workout.self, WorkoutRecord.self], isStoredInMemoryOnly: false)` wrapped in a `static @MainActor let shared`. Provide a `RootView` split (tab/sidebar) with a route to the **History/Results** screen once history exists. Set the container `modelContext` into the SwiftUI `\.modelContext` environment.
- [ ] **Step 2** — In `Support/SeedMigration.swift`: write `enum SeedMigration { static func applySeed(to container: ModelContainer) }`. Insert the built-in WODs (initially **Cindy** and **Murph**) from `BenchmarkSeed`. Guard: if any `Workout` with `isBuiltin == true` already exists, do nothing (idempotent). Call `BenchmarkSeed.cindy()` / `BenchmarkSeed.murph()`. Note: `BenchmarkSeed` itself is Task 2 — for Task 0, implement a minimal inline Cindy + Murph factory **or** write `BenchmarkSeed` now and extend in Task 2 (either is fine; document your choice).
- [ ] **Step 3** — Build & run; confirm it launches on the simulator with no compile errors.

## How to work this task
- Tooling: use **XcodeGen** (`brew install xcodegen`). Create `Project.yml` (Sources + Tests), run `xcodegen generate`, then `xcodebuild -workspace WODCounter.xcworkspace -scheme WODCounter -list` to see the scheme/test targets.
- Tests: run via `xcodebuild -workspace WODCounter.xcworkspace -scheme <YourScheme> -destination 'platform=iOS Simulator,name=iPhone 16' test`. For SwiftData unit tests, an in-memory `ModelContainer(for: schema)` is fine (see the Test infra note in the plan).
- BASE commit: the first commit of this project. Every task diffs against HEAD.
- Done when: `xcodebuild … build … -skipsandboxing 1` succeeds, the app launches, and (if tests exist) `… test` is green. Commit with a meaningful message.

## Acceptance
- App builds and launches. Empty SwiftData container persists across launches (not in-memory-only). Cindy + Murph appear (seed). No compile errors, no placeholders.
