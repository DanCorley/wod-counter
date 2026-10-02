import Foundation
import SwiftData

@Model final class WorkoutRecord {
    @Attribute(.unique) var id: UUID
    var workout: Workout?
    var date: Date
    var kind: String
    var roundsCompleted: Int
    var totalReps: Int
    var elapsedTime: TimeInterval
    var pausedTime: TimeInterval
    var activeTime: TimeInterval
    var isPR: Bool
    var notes: String?
    /// Raw value of `FinishedReason` — how the session ended. Optional so that
    /// records written before this field existed migrate cleanly; those are
    /// treated as ineligible for PRs, since their completeness is unknown.
    var finishedReason: String?
    /// Total reps the workout prescribed, for judging partial attempts.
    var repsQuota: Int?

    /// Whether the athlete finished the prescribed work. A top-time PR requires
    /// this; otherwise a 5-second bail-out would record an unbeatable best.
    var didCompleteWork: Bool {
        finishedReason == FinishedReason.goalReached.rawValue
    }

    /// Fraction of prescribed reps completed, when the quota is known.
    var completionFraction: Double? {
        guard let repsQuota, repsQuota > 0 else { return nil }
        return min(1, Double(totalReps) / Double(repsQuota))
    }

    init(id: UUID = UUID(), workout: Workout? = nil, date: Date = Date(),
         kind: String, roundsCompleted: Int, totalReps: Int,
         elapsedTime: TimeInterval, pausedTime: TimeInterval, activeTime: TimeInterval,
         isPR: Bool, notes: String? = nil,
         finishedReason: String? = nil, repsQuota: Int? = nil) {
        self.id = id
        self.workout = workout
        self.date = date
        self.kind = kind
        self.roundsCompleted = roundsCompleted
        self.totalReps = totalReps
        self.elapsedTime = elapsedTime
        self.pausedTime = pausedTime
        self.activeTime = activeTime
        self.isPR = isPR
        self.notes = notes
        self.finishedReason = finishedReason
        self.repsQuota = repsQuota
    }
}
