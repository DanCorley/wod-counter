import Foundation
import SwiftData

@Model final class Exercise {
    @Relationship var movement: Movement?
    var roundBlock: RoundBlock?
    var reps: Int?
    var weight: String?
    var distance: String?
    var distanceUnit: String?
    var restSeconds: Int?
    var displayLabel: String?

    var effectiveReps: Int { reps ?? 1 }

    init(movement: Movement? = nil, roundBlock: RoundBlock? = nil, reps: Int? = nil,
         weight: String? = nil, distance: String? = nil, distanceUnit: String? = nil,
         restSeconds: Int? = nil, displayLabel: String? = nil) {
        self.movement = movement
        self.roundBlock = roundBlock
        self.reps = reps
        self.weight = weight
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.restSeconds = restSeconds
        self.displayLabel = displayLabel
    }
}
