import Foundation
import SwiftData

enum Container {
    static let schema = Schema([
        Movement.self,
        Exercise.self,
        RoundBlock.self,
        Workout.self,
        WorkoutRecord.self
    ])

    static func local() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: config)
    }

    static func inMemory() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: config)
    }
}
