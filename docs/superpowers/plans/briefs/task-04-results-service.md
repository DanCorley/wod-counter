# Task 4 — `ResultsService` & Formatters (windowed stats + PR detection)

**Deliverable:** Pure functions over SwiftData to compute per-workout history, PRs, and window summaries, plus shared duration and timer formatters.

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 7 (services), § 11 (results/history).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 7 (full `ResultsService.swift` reference), § 9 (formatters).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 4.
- **Siblings (consume exactly):**
  - Task 1 models (`WorkoutRecord`, `Workout`, `ExecutionMode`).
  - Task 5 `WorkoutTimerService` consumes `ResultsService.isNewPR(...)`.
  - Tasks 7–8 consume `Format.duration` and `Format.timer`.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. **SwiftData + Swift Concurrency**.
- All tests placed in `WODCounterTests/Services/`.
- **TDD:** end green, commit once, no placeholders.

## Files
- **Create:** `WODCounter/Support/Format.swift`
- **Create:** `WODCounter/Services/ResultsService.swift`
- **Create:** `WODCounterTests/Services/ResultsServiceTests.swift`

## Contracts

### `Support/Format.swift`
```swift
import Foundation

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    static func timer(_ minutes: Int) -> String {
        return "\(minutes):00"
    }
}
```

### `Services/ResultsService.swift`
```swift
struct WindowSummary {
    var workoutsCount: Int
    var prsThisWindow: Int
    var bestRounds: Int
    var bestTime: TimeInterval   // lowest activeTime for topTime
    var avgActiveTime: TimeInterval
}

@MainActor
final class ResultsService {
    let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func history(for workout: Workout?, window: DateInterval, kind: String? = nil) -> [WorkoutRecord]
    func summary(for workout: Workout?, window: DateInterval, kind: String? = nil) -> WindowSummary
    func previousBest(for workout: Workout, kind: String, asOf date: Date) -> Double?
    static func isNewPR(workout: Workout, kind: String, rounds: Int, activeTime: TimeInterval, before date: Date, in context: ModelContext) -> Bool
}
```

## Steps
- [ ] **Step 1:** Implement `Support/Format.swift` with standard duration and timer string formatters.
- [ ] **Step 2:** Implement `ResultsService(context:)`. `history(for:window:kind:)` uses `#Predicate<WorkoutRecord>` on workout ID and date window sorted descending. `summary(...)` calculates record counts, PR counts, best rounds, best time, and average active time. `isNewPR(...)` compares against existing records prior to `date`.
- [ ] **Step 3:** Write `WODCounterTests/Services/ResultsServiceTests.swift`: with an in-memory `ModelContainer`, insert multiple `WorkoutRecord`s; verify window summaries (7/30/90 days), PR evaluation (for-time higher rounds is PR; top-time lower activeTime is PR), and empty window handling.
- [ ] **Step 4:** Run tests, confirm green, commit.

## Acceptance
- `ResultsService` calculates correct summaries, histories, and PR determinations. Formatters format cleanly. All tests in `WODCounterTests/Services/ResultsServiceTests.swift` pass. One commit.
