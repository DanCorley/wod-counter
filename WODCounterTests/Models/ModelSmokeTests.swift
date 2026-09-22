import XCTest
import SwiftData
@testable import WODCounter

@MainActor
final class ModelSmokeTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        Container.inMemory()
    }

    func testEffectiveRepsReturnsRepsOrDefaultsToOne() throws {
        let exercise = Exercise(reps: 15)
        XCTAssertEqual(exercise.effectiveReps, 15)

        let distancedExercise = Exercise(reps: nil)
        XCTAssertEqual(distancedExercise.effectiveReps, 1)
    }

    func testMovementInsertion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let movement = Movement(name: "Back Squat", equipment: "Barbell", category: "Strength")
        context.insert(movement)
        try context.save()

        let descriptor = FetchDescriptor<Movement>(predicate: #Predicate { $0.name == "Back Squat" })
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.equipment, "Barbell")
    }

    func testExerciseInsertion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let movement = Movement(name: "Thrusters")
        context.insert(movement)
        let exercise = Exercise(movement: movement, reps: 21, weight: "95 lb", displayLabel: "21 Thrusters (95 lb)")
        context.insert(exercise)
        try context.save()

        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.reps == 21 })
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.movement?.name, "Thrusters")
    }

    func testRoundBlockInsertion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let block = RoundBlock(repeatTimes: 3, restAfterBlock: 60)
        context.insert(block)
        try context.save()

        let descriptor = FetchDescriptor<RoundBlock>(predicate: #Predicate { $0.repeatTimes == 3 })
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.restAfterBlock, 60)
    }

    func testWorkoutInsertion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Cindy", workoutDescription: "20-min AMRAP", category: "Girl",
                              mode: .forTime, isBuiltin: true, forTimeMinutes: 20)
        context.insert(workout)
        try context.save()

        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.name == "Cindy" })
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.forTimeMinutes, 20)
        XCTAssertEqual(results.first?.mode, .forTime)
    }

    func testWorkoutRecordInsertion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let record = WorkoutRecord(kind: "rounds", roundsCompleted: 5, totalReps: 100,
                                   elapsedTime: 1200, pausedTime: 60, activeTime: 1140, isPR: true)
        context.insert(record)
        try context.save()

        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.roundsCompleted == 5 })
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.activeTime, 1140)
        XCTAssertTrue(results.first?.isPR ?? false)
    }

    func testExecutionModeProperties() {
        XCTAssertEqual(ExecutionMode.forTime.title, "For Time")
        XCTAssertEqual(ExecutionMode.topTime.title, "Top Time")
        XCTAssertEqual(ExecutionMode.forTime.symbol, "timer")
        XCTAssertEqual(ExecutionMode.topTime.symbol, "flag.checkered")
    }

    func testWorkoutUniqueID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let id1 = UUID()
        let id2 = UUID()
        let record1 = WorkoutRecord(id: id1, kind: "rounds", roundsCompleted: 1, totalReps: 10,
                                    elapsedTime: 60, pausedTime: 0, activeTime: 60, isPR: false)
        let record2 = WorkoutRecord(id: id2, kind: "time", roundsCompleted: 2, totalReps: 20,
                                    elapsedTime: 120, pausedTime: 10, activeTime: 110, isPR: true)
        context.insert(record1)
        context.insert(record2)
        try context.save()

        let descriptor = FetchDescriptor<WorkoutRecord>()
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 2)
        XCTAssertNotEqual(results[0].id, results[1].id)
    }
}
