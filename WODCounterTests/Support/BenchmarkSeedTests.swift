import XCTest
import SwiftData
@testable import WODCounter

@MainActor
final class BenchmarkSeedTests: XCTestCase {
    private var container: ModelContainer!

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Movement.self, Exercise.self, RoundBlock.self, Workout.self, WorkoutRecord.self,
            configurations: config
        )
        return container.mainContext
    }

    // MARK: - Cindy

    func testCindy() throws {
        let context = try makeContext()
        let workout = BenchmarkSeed.cindy(in: context)

        XCTAssertEqual(workout.name, "Cindy")
        XCTAssertEqual(workout.category, "Girl")
        XCTAssertEqual(workout.mode, .forTime)
        XCTAssertEqual(workout.forTimeMinutes, 20)
        XCTAssertTrue(workout.isBuiltin)
        XCTAssertEqual(workout.blocks.count, 1)

        let block = workout.blocks[0]
        XCTAssertEqual(block.repeatTimes, 0)
        XCTAssertEqual(block.exercises.count, 3)
        XCTAssertEqual(block.exercises.map { $0.reps }, [5, 10, 15])
        XCTAssertEqual(block.exercises.map { $0.movement?.name }, ["Pull-up", "Push-up", "Air Squat"])
        XCTAssertEqual(block.exercises.map { $0.displayLabel }, ["5 Pull-ups", "10 Push-ups", "15 Air Squats"])
    }

    // MARK: - Murph

    func testMurph() throws {
        let context = try makeContext()
        let workout = BenchmarkSeed.murph(in: context)

        XCTAssertEqual(workout.name, "Murph")
        XCTAssertEqual(workout.category, "Hero")
        XCTAssertEqual(workout.mode, .topTime)
        XCTAssertNil(workout.forTimeMinutes)
        XCTAssertTrue(workout.isBuiltin)
        XCTAssertEqual(workout.blocks.count, 1)

        let block = workout.blocks[0]
        XCTAssertEqual(block.repeatTimes, 1)
        XCTAssertEqual(block.exercises.count, 3)
        XCTAssertEqual(block.exercises.map { $0.reps }, [100, 200, 300])
        XCTAssertEqual(block.exercises.map { $0.displayLabel }, ["100 Pull-ups", "200 Push-ups", "300 Air Squats"])
    }

    // MARK: - Fran

    func testFran() throws {
        let context = try makeContext()
        let workout = BenchmarkSeed.fran(in: context)

        XCTAssertEqual(workout.name, "Fran")
        XCTAssertEqual(workout.category, "Girl")
        XCTAssertEqual(workout.mode, .topTime)
        XCTAssertEqual(workout.blocks.count, 3)

        let repsPerBlock = workout.blocks.map { $0.exercises.map { $0.reps } }
        XCTAssertEqual(repsPerBlock, [[21, 21], [15, 15], [9, 9]])

        let allLabels = workout.blocks.flatMap { $0.exercises.map { $0.displayLabel ?? "" } }
        XCTAssertTrue(allLabels.contains("21 Thrusters (95 lb)"))
        XCTAssertTrue(allLabels.contains("21 Pull-ups"))
        XCTAssertTrue(allLabels.contains("15 Thrusters (95 lb)"))
        XCTAssertTrue(allLabels.contains("9 Thrusters (95 lb)"))
    }

    // MARK: - Angie

    func testAngie() throws {
        let context = try makeContext()
        let workout = BenchmarkSeed.angie(in: context)

        XCTAssertEqual(workout.name, "Angie")
        XCTAssertEqual(workout.category, "Girl")
        XCTAssertEqual(workout.mode, .topTime)
        XCTAssertEqual(workout.blocks.count, 1)

        let block = workout.blocks[0]
        XCTAssertEqual(block.repeatTimes, 1)
        XCTAssertEqual(block.exercises.count, 4)
        XCTAssertEqual(block.exercises.map { $0.reps }, [100, 100, 100, 100])
        XCTAssertEqual(block.exercises.map { $0.movement?.name }, ["Pull-up", "Push-up", "Sit-up", "Air Squat"])
    }

    // MARK: - Grace

    func testGrace() throws {
        let context = try makeContext()
        let workout = BenchmarkSeed.grace(in: context)

        XCTAssertEqual(workout.name, "Grace")
        XCTAssertEqual(workout.category, "Girl")
        XCTAssertEqual(workout.mode, .topTime)
        XCTAssertEqual(workout.blocks.count, 1)

        let block = workout.blocks[0]
        XCTAssertEqual(block.repeatTimes, 1)
        XCTAssertEqual(block.exercises.count, 1)
        XCTAssertEqual(block.exercises[0].reps, 30)
        XCTAssertEqual(block.exercises[0].weight, "135 lb")
        XCTAssertEqual(block.exercises[0].displayLabel, "30 Clean & Jerk (135 lb)")
        XCTAssertEqual(block.exercises[0].movement?.name, "Clean & Jerk")
    }

    // MARK: - Diane

    func testDiane() throws {
        let context = try makeContext()
        let workout = BenchmarkSeed.diane(in: context)

        XCTAssertEqual(workout.name, "Diane")
        XCTAssertEqual(workout.category, "Girl")
        XCTAssertEqual(workout.mode, .topTime)
        XCTAssertEqual(workout.blocks.count, 3)

        let repsPerBlock = workout.blocks.map { $0.exercises.map { $0.reps } }
        XCTAssertEqual(repsPerBlock, [[21, 21], [15, 15], [9, 9]])

        let allLabels = workout.blocks.flatMap { $0.exercises.map { $0.displayLabel ?? "" } }
        XCTAssertTrue(allLabels.contains("21 Deadlifts (225 lb)"))
        XCTAssertTrue(allLabels.contains("21 Handstand Push-ups"))
    }

    // MARK: - Helen

    func testHelen() throws {
        let context = try makeContext()
        let workout = BenchmarkSeed.helen(in: context)

        XCTAssertEqual(workout.name, "Helen")
        XCTAssertEqual(workout.category, "Girl")
        XCTAssertEqual(workout.mode, .topTime)
        XCTAssertEqual(workout.blocks.count, 1)

        let block = workout.blocks[0]
        XCTAssertEqual(block.repeatTimes, 3)
        XCTAssertEqual(block.exercises.count, 3)

        let run = block.exercises[0]
        XCTAssertNil(run.reps)
        XCTAssertEqual(run.distance, "400 m")
        XCTAssertEqual(run.distanceUnit, "m")
        XCTAssertEqual(run.displayLabel, "400 m Run")
        XCTAssertEqual(run.movement?.name, "Run")

        XCTAssertEqual(block.exercises[1].reps, 21)
        XCTAssertEqual(block.exercises[1].weight, "53/35 lb")
        XCTAssertEqual(block.exercises[2].reps, 12)
    }

    // MARK: - DT

    func testDT() throws {
        let context = try makeContext()
        let workout = BenchmarkSeed.dt(in: context)

        XCTAssertEqual(workout.name, "DT")
        XCTAssertEqual(workout.category, "Hero")
        XCTAssertEqual(workout.mode, .topTime)
        XCTAssertEqual(workout.blocks.count, 1)

        let block = workout.blocks[0]
        XCTAssertEqual(block.repeatTimes, 5)
        XCTAssertEqual(block.exercises.count, 3)
        XCTAssertEqual(block.exercises.map { $0.reps }, [12, 9, 6])
        XCTAssertEqual(block.exercises.map { $0.weight }, ["225 lb", "155 lb", "155 lb"])
        XCTAssertEqual(block.exercises.map { $0.movement?.name }, ["Deadlift", "Hang Power Clean", "Push Jerk"])
    }

    // MARK: - Movement deduplication

    func testMovementDeduplication() throws {
        let context = try makeContext()
        _ = BenchmarkSeed.cindy(in: context)
        _ = BenchmarkSeed.murph(in: context)
        _ = BenchmarkSeed.fran(in: context)

        let descriptor = FetchDescriptor<Movement>()
        let movements = try context.fetch(descriptor)
        let names = movements.map { $0.name }

        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "Movements should be deduplicated")
        XCTAssertTrue(names.contains("Pull-up"))
        XCTAssertTrue(names.contains("Push-up"))
        XCTAssertTrue(names.contains("Air Squat"))
        XCTAssertTrue(names.contains("Thrusters"))
    }

    // MARK: - SeedMigration idempotency

    func testSeedMigrationIdempotency() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let testContainer = try ModelContainer(
            for: Movement.self, Exercise.self, RoundBlock.self, Workout.self, WorkoutRecord.self,
            configurations: config
        )

        SeedMigration.applySeed(to: testContainer)
        let context = testContainer.mainContext

        let workoutDescriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.isBuiltin == true })
        let count1 = try context.fetchCount(workoutDescriptor)
        XCTAssertEqual(count1, 8)

        SeedMigration.applySeed(to: testContainer)
        let count2 = try context.fetchCount(workoutDescriptor)
        XCTAssertEqual(count2, 8, "Running seed migration twice should not duplicate workouts")
    }
}
