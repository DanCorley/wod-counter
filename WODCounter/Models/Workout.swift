import Foundation
import SwiftData

@Model final class Workout {
    var name: String
    var workoutDescription: String?
    var category: String?
    var mode: ExecutionMode
    @Relationship(deleteRule: .cascade, inverse: \WorkoutRecord.workout) var records: [WorkoutRecord]
    @Relationship(deleteRule: .cascade, inverse: \RoundBlock.workout) var blocks: [RoundBlock]
    var isBuiltin: Bool
    var forTimeMinutes: Int?
    var createdAt: Date
    var updatedAt: Date

    init(name: String, workoutDescription: String? = nil, category: String? = nil,
         mode: ExecutionMode, isBuiltin: Bool = false, forTimeMinutes: Int? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.name = name
        self.workoutDescription = workoutDescription
        self.category = category
        self.mode = mode
        self.records = []
        self.blocks = []
        self.isBuiltin = isBuiltin
        self.forTimeMinutes = forTimeMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
