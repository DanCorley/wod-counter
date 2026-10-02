import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppModel.self) private var appModel: AppModel?
    @Environment(ServiceFactory.self) private var serviceFactory: ServiceFactory?
    @State private var hasShownStoreWarning = false

    var body: some View {
        tabs
            // A failed save means the workout the athlete just finished is gone.
            // That must not pass silently.
            .alert(
                "Couldn't Save",
                isPresented: Binding(
                    get: { serviceFactory?.saveFailureMessage != nil },
                    set: { if !$0 { serviceFactory?.saveFailureMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { serviceFactory?.saveFailureMessage = nil }
            } message: {
                Text(serviceFactory?.saveFailureMessage ?? "")
            }
            .alert("Storage Unavailable", isPresented: $hasShownStoreWarning) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your saved workouts couldn't be opened, so this session won't be stored. Reinstalling the app may fix it.")
            }
            .onAppear {
                if Container.isUsingFallbackStore {
                    hasShownStoreWarning = true
                }
            }
    }

    private var tabs: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("WODs", systemImage: "dumbbell.fill")
            }

            NavigationStack {
                ResultsView()
            }
            .tabItem {
                Label("History", systemImage: "chart.bar.xaxis")
            }
        }
    }
}
