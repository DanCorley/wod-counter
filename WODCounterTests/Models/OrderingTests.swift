import XCTest
import SwiftData
@testable import WODCounter

@MainActor
final class OrderingTests: XCTestCase {

    private func movement(_ name: String, in context: ModelContext) -> Movement {
        let movement = Movement(name: name)
        context.insert(movement)
        return movement
    }

    private func exercise(_ name: String, sortOrder: Int = 0, in context: ModelContext) -> Exercise {
        let exercise = Exercise(
            movement: movement(name, in: context),
            reps: 10,
            displayLabel: name,
            sortOrder: sortOrder
        )
        context.insert(exercise)
        return exercise
    }

    /// Legacy rows all have the default `sortOrder == 0`. The documented
    /// fallback preserves the relationship's current array order rather than
    /// inventing a new one. Assert that relationship-derived result instead of
    /// hard-coding a raw SwiftData order, which SwiftData does not guarantee.
    func testLegacyRowsWithDefaultSortOrderKeepRelationshipOrder() {
        let container = Container.inMemory()
        let context = container.mainContext

        let a = exercise("A", in: context)
        let b = exercise("B", in: context)
        let c = exercise("C", in: context)

        let block0 = RoundBlock(repeatTimes: 1)
        block0.exercises = [a, b, c]
        let block1 = RoundBlock(repeatTimes: 1)
        block1.exercises = [exercise("D", in: context)]

        let workout = Workout(name: "Legacy", mode: .topTime)
        workout.blocks = [block0, block1]

        XCTAssertEqual(Set(block0.orderedExercises.map(\.displayLabel)), ["A", "B", "C"])
        XCTAssertEqual(
            block0.orderedExercises.map(\.displayLabel),
            block0.exercises.map(\.displayLabel),
            "Ties fall back to the relationship's current array order"
        )
        XCTAssertTrue(workout.orderedBlocks.contains { $0 === block0 })
        XCTAssertTrue(workout.orderedBlocks.contains { $0 === block1 })
    }

    func testExplicitSortOrderOverridesRelationshipArrayOrder() {
        let container = Container.inMemory()
        let context = container.mainContext

        let a = exercise("A", sortOrder: 2, in: context)
        let b = exercise("B", sortOrder: 0, in: context)
        let c = exercise("C", sortOrder: 1, in: context)

        let block0 = RoundBlock(repeatTimes: 1, sortOrder: 1)
        block0.exercises = [a, b, c]
        let block1 = RoundBlock(repeatTimes: 1, sortOrder: 0)
        block1.exercises = [exercise("D", in: context)]

        let workout = Workout(name: "Ordered", mode: .topTime)
        workout.blocks = [block0, block1]

        XCTAssertEqual(block0.orderedExercises.map(\.displayLabel), ["B", "C", "A"])
        XCTAssertTrue(workout.orderedBlocks[0] === block1)
        XCTAssertTrue(workout.orderedBlocks[1] === block0)
    }
}
