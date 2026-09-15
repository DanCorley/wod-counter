import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                WODListView()
            }
            .tabItem {
                Label("WODs", systemImage: "dumbbell")
            }

            NavigationStack {
                Text("History coming in Task 5")
            }
            .tabItem {
                Label("History", systemImage: "chart.bar")
            }
        }
        .navigationTitle("WOD Counter")
    }
}

struct WODListView: View {
    @Query(sort: \Workout.name) private var workouts: [Workout]

    var body: some View {
        List {
            ForEach(workouts) { workout in
                VStack(alignment: .leading) {
                    Text(workout.name).font(.headline)
                    if let desc = workout.workoutDescription {
                        Text(desc).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Label(workout.mode.title, systemImage: workout.mode.symbol)
                            .font(.caption)
                        if let cat = workout.category {
                            Text(cat).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("WODs")
    }
}
