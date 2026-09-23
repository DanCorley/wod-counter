import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppModel.self) private var appModel: AppModel?

    var body: some View {
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
