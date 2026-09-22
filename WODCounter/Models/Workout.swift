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

    // MARK: - Category Helpers
    var isGirlBenchmark: Bool {
        category == "Girl"
    }

    var isHeroBenchmark: Bool {
        category == "Hero"
    }

    var isCustom: Bool {
        category == "Custom" || (!isBuiltin && category != "Girl" && category != "Hero")
    }

    // MARK: - Scheme Display Helpers
    var modeSubtitle: String {
        if mode == .forTime, let minutes = forTimeMinutes {
            return "For Time (AMRAP) — \(Format.timer(minutes))"
        } else {
            return "Top Time — Race to complete all reps"
        }
    }

    func blockHeader(for block: RoundBlock, index: Int) -> String {
        let total = blocks.count
        if total > 1 {
            return "Block \(index + 1) of \(total)"
        } else if block.repeatTimes > 1 {
            return "Repeat \(block.repeatTimes) Rounds"
        } else if mode == .forTime && block.repeatTimes == 0 {
            return "Continuous Rounds (AMRAP)"
        } else {
            return "Round 1"
        }
    }
}
