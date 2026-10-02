import Foundation
import SwiftData

@Model final class RoundBlock {
    @Relationship(deleteRule: .cascade, inverse: \Exercise.roundBlock) var exercises: [Exercise]
    var workout: Workout?
    var repeatTimes: Int
    var restAfterBlock: Int?
    /// Position within the parent workout. See `Exercise.sortIndex` — SwiftData
    /// to-many order is not guaranteed, and Fran's 21-15-9 blocks must not come
    /// back reordered.
    var sortIndex: Int = 0

    /// Exercises in their prescribed order.
    var orderedExercises: [Exercise] {
        exercises.sorted { $0.sortIndex < $1.sortIndex }
    }

    init(repeatTimes: Int, restAfterBlock: Int? = nil, sortIndex: Int = 0) {
        self.exercises = []
        self.repeatTimes = repeatTimes
        self.restAfterBlock = restAfterBlock
        self.sortIndex = sortIndex
    }
}
