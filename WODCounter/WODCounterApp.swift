import SwiftUI
import SwiftData

@main
struct WODCounterApp: App {
    let container: ModelContainer
    let serviceFactory: ServiceFactory
    @State private var appModel: AppModel

    init() {
        let schema = Schema([Movement.self, Exercise.self, RoundBlock.self, Workout.self, WorkoutRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container = try! ModelContainer(for: schema, configurations: config)
        self.container = container
        let factory = ServiceFactory(container)
        self.serviceFactory = factory
        self._appModel = State(initialValue: AppModel(factory: factory))
        SeedMigration.applySeed(to: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(serviceFactory)
                .modelContainer(container)
        }
    }
}
