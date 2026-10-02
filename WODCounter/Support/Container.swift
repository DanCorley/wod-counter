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

    /// Whether `local()` had to fall back to a throwaway in-memory store,
    /// meaning this launch will not persist anything.
    private(set) static var isUsingFallbackStore = false

    static func local() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // A corrupt or unmigratable store must not brick the app. Fall back
            // to an in-memory container so the athlete can still run a workout;
            // the flag lets the UI warn that nothing will be saved.
            isUsingFallbackStore = true
            return inMemory()
        }
    }

    static func inMemory() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // An in-memory container failing means the schema itself is invalid
            // — a programming error with no sane recovery.
            fatalError("Invalid SwiftData schema: \(error)")
        }
    }
}
