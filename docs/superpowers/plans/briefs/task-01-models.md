# Task 1 — SwiftData models

**Deliverable:** All six `@Model` classes matching the spec's domain model, exact fields (the fields below are the contract every other task consumes).

## Pointers
- **Spec (requirements):** `docs/superpowers/specs/2026-09-11-wod-counter-design.md` § 5 (data model), § 3 (architecture).
- **Handoff (mechanics):** `docs/implementation-handoff.md` § 5 (full model source), § 6 (simulator engine), § 12 (constraints).
- **Plan (this task):** `docs/superpowers/plans/2026-09-11-wod-counter-implementation.md` → Task 1.
- **Siblings:** Task 0 produced the container schema — Task 0 must list exactly these types. Task 2 (seed), Task 3 (simulator), Task 4 (service) consume these models. Task 3 is tested against fabricated `Workout`s, so it doesn't depend on seeds.

## Global constraints (verbatim)
- iOS, Apple-native, **iOS 17.0**. **SwiftUI + SwiftData + Swift Concurrency**.
- `Movement`s are the shared catalog; `Exercise`s are per-WOD prescriptions with a **pre-rendered `displayLabel`** (no reformatting at render time).
- Distanced-only exercises (runs, row, bike, rope) have **no `reps`** → treat as effective rep quota **1** so the engine stays uniform.
- **TDD:** end green, commit once per task, no placeholders.

## Files
- **Create:** `WODCounter/Models/ExecutionMode.swift`
- **Create:** `WODCounter/Models/Movement.swift`
- **Create:** `WODCounter/Models/Exercise.swift`
- **Create:** `WODCounter/Models/RoundBlock.swift`
- **Create:** `WODCounter/Models/Workout.swift`
- **Create:** `WODCounter/Models/WorkoutRecord.swift`

## Contracts (exact)
`ExecutionMode`: `String, Codable, CaseIterable, Sendable` cases `forTime`, `topTime`; `title` ("For Time"/"Top Time"); `symbol` ("timer"/"flag.checkered").
`Movement`: `@Attribute(.unique) name`, optional `equipment` (Barbell/Kettlebell/Rope/Rowing Machine/Box/Track/Power Rack/Bodyweight), optional `category` (Strength/Gymnastics/Power/Cardio/Sprint/Skill), optional `iconName`. `init(name:equipment:category:iconName:)`.
`Exercise`: relationship `movement`; `reps: Int?` (nil = distanced-only → effective 1); `weight: String?`; `distance: String?`; `distanceUnit: String?`; `restSeconds: Int?`; **pre-rendered `displayLabel: String?`**. `var effectiveReps: Int { reps ?? 1 }`. `init(...)` with all-defaulted params.
`RoundBlock`: relationship `exercises: [Exercise]` (cascade, inverse `Workout.blocks`); `repeatTimes: Int` (0 = loop until clock; N = play N; 1 = single pass); `restAfterBlock: Int?` (seconds to rest after block, nil = continuous). `init(repeatTimes:restAfterBlock:)`.
`Workout`: `name`, `description: String?`, `category: String?` ("Girl"/"Hero"/"Custom"), `mode: ExecutionMode`, relationships `records: [WorkoutRecord]` (inverse `WorkoutRecord.workout`) and `blocks: [RoundBlock]` (inverse `RoundBlock`→`Workout`); `isBuiltin: Bool`; `forTimeMinutes: Int?` (nil = unlimited, e.g. Murph; e.g. 20 Cindy); `createdAt`/`updatedAt: Date`. `init(name:mode:isBuiltin:forTimeMinutes:createdAt:updatedAt:)`.
`WorkoutRecord`: `@Attribute(.unique) id: UUID`; `workout: Workout?`; `date: Date`; `kind: String` ("rounds"/"time"); `roundsCompleted: Int`; `totalReps: Int`; `elapsedTime`/`pausedTime`/`activeTime: TimeInterval` (activeTime = elapsedTime − pausedTime); `isPR: Bool`; `notes: String?`. `init(id:workout:date:kind:roundsCompleted:totalReps:elapsedTime:pausedTime:activeTime:isPR:notes:)` with defaulted params.

**Relationship inverses matter** for SwiftData graph integrity — set each `inverse:` correctly.

## Steps
- [ ] **Step 1:** Write all six model files exactly per the contracts above. Preserve every field, type, default, and relationship inverse.
- [ ] **Step 2:** Add `Tests/Models/ModelSmokeTests.swift`: assert `Exercise.effectiveReps` = `reps ?? 1` (including a `reps == nil` distanced case → 1); assert each `@Model` class can be instantiated and conforms (compiles against the container).
- [ ] **Step 3:** Run tests (`xcodebuild … test`), confirm pass, commit.

## Test infra note
SwiftData needs an in-memory `ModelContainer` for unit tests. Prefer option (b): a small `#testable` target exposing the models/services — reuse it in the app. Otherwise option (a): build tests with a `#if DEBUG` in-memory container. The SAME code runs in the app; don't branch production logic on test/production.

## Acceptance
- All six models compile, instantiate, and round-trip. `effectiveReps` correct for nil and set `reps`. Relationships have correct inverse/delete rules. Tests green. One commit.
