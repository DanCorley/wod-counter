import SwiftUI
import SwiftData

@main
struct WODCounterApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Movement.self, Exercise.self, RoundBlock.self, Workout.self, WorkoutRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        container = try! ModelContainer(for: schema, configurations: config)
        SeedMigration.applySeed(to: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
    }
}
