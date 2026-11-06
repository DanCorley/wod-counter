import Foundation
import SwiftData

@Model final class RoundBlock {
    @Relationship(deleteRule: .cascade, inverse: \Exercise.roundBlock) var exercises: [Exercise]
    var workout: Workout?
    var repeatTimes: Int
    /// Seconds to rest after each completed play of this block.
    ///
    /// The rest belongs to the block that just completed and is measured in
    /// active time (pauses do not consume it). With `repeatTimes > 1` this
    /// means rest *between* rounds; it is never applied after the final round
    /// of the workout. `nil` (or 0) means continuous.
    var restAfterBlock: Int?
    /// Explicit position of this block within its workout. Defaulted so stores
    /// created before this field existed still open via lightweight migration.
    var sortOrder: Int = 0

    init(repeatTimes: Int, restAfterBlock: Int? = nil, sortOrder: Int = 0) {
        self.exercises = []
        self.repeatTimes = repeatTimes
        self.restAfterBlock = restAfterBlock
        self.sortOrder = sortOrder
    }

    /// Exercises in explicit `sortOrder` order.
    ///
    /// Legacy rows (and any rows whose `sortOrder` ties) fall back to the
    /// to-many relationship's current array order. That is the only ordering
    /// hint those rows have, and it keeps pre-migration behavior unchanged.
    var orderedExercises: [Exercise] {
        exercises.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.sortOrder != rhs.element.sortOrder {
                    return lhs.element.sortOrder < rhs.element.sortOrder
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
