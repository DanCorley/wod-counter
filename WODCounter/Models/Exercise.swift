import Foundation
import SwiftData

@Model final class Exercise {
    @Relationship var movement: Movement?
    var roundBlock: RoundBlock?
    var reps: Int?
    var weight: String?
    var distance: String?
    var distanceUnit: String?
    var displayLabel: String?
    /// Position within the parent block. SwiftData does not guarantee the order
    /// of a to-many relationship across fetches, and order is load-bearing here
    /// (21-15-9 is not 9-15-21), so it is stored explicitly rather than trusted
    /// from the array.
    var sortIndex: Int = 0

    var effectiveReps: Int { reps ?? 1 }

    init(movement: Movement? = nil, roundBlock: RoundBlock? = nil, reps: Int? = nil,
         weight: String? = nil, distance: String? = nil, distanceUnit: String? = nil,
         displayLabel: String? = nil, sortIndex: Int = 0) {
        self.movement = movement
        self.roundBlock = roundBlock
        self.reps = reps
        self.weight = weight
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.displayLabel = displayLabel
        self.sortIndex = sortIndex
    }
}
