import SwiftUI
import SwiftData

@main
struct WODCounterApp: App {
    let container: ModelContainer
    let serviceFactory: ServiceFactory
    @State private var appModel: AppModel

    init() {
        let container = Container.local()
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
