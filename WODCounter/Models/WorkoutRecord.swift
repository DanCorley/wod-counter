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

    init(id: UUID = UUID(), workout: Workout? = nil, date: Date = Date(),
         kind: String, roundsCompleted: Int, totalReps: Int,
         elapsedTime: TimeInterval, pausedTime: TimeInterval, activeTime: TimeInterval,
         isPR: Bool, notes: String? = nil) {
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
    }
}
