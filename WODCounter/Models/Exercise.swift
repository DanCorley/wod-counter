import Foundation
import SwiftData

@Model final class Exercise {
    @Relationship var movement: Movement?
    var roundBlock: RoundBlock?
    var reps: Int?
    var weight: String?
    var distance: String?
    var distanceUnit: String?
    /// Deprecated: per-exercise rest is not part of the supported v1 contract.
    /// Rest is configured per block via `RoundBlock.restAfterBlock`. The field
    /// is retained only so existing stores keep opening; nothing writes or
    /// reads it for engine behavior.
    var restSeconds: Int?
    var displayLabel: String?
    /// Explicit position of this exercise within its block. Defaulted so stores
    /// created before this field existed still open via lightweight migration.
    var sortOrder: Int = 0

    var effectiveReps: Int { reps ?? 1 }

    init(movement: Movement? = nil, roundBlock: RoundBlock? = nil, reps: Int? = nil,
         weight: String? = nil, distance: String? = nil, distanceUnit: String? = nil,
         restSeconds: Int? = nil, displayLabel: String? = nil, sortOrder: Int = 0) {
        self.movement = movement
        self.roundBlock = roundBlock
        self.reps = reps
        self.weight = weight
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.restSeconds = restSeconds
        self.displayLabel = displayLabel
        self.sortOrder = sortOrder
    }
}
