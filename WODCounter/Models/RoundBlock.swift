import Foundation
import SwiftData

@Model final class RoundBlock {
    @Relationship(deleteRule: .cascade, inverse: \Exercise.roundBlock) var exercises: [Exercise]
    var workout: Workout?
    var repeatTimes: Int
    var restAfterBlock: Int?

    init(repeatTimes: Int, restAfterBlock: Int? = nil) {
        self.exercises = []
        self.repeatTimes = repeatTimes
        self.restAfterBlock = restAfterBlock
    }
}
