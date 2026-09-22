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
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("History & Stats")
                        .font(.title2.bold())
                    Text("Complete workout sessions to view trends and personal records.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .navigationTitle("History")
            }
            .tabItem {
                Label("History", systemImage: "chart.bar.xaxis")
            }
        }
    }
}
