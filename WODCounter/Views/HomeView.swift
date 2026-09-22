import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Workout.name) private var workouts: [Workout]
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingSettings = false

    private var girlWorkouts: [Workout] {
        workouts.filter { $0.category == "Girl" }
    }

    private var heroWorkouts: [Workout] {
        workouts.filter { $0.category == "Hero" }
    }

    private var customWorkouts: [Workout] {
        workouts.filter { $0.category == "Custom" || (!$0.isBuiltin && $0.category != "Girl" && $0.category != "Hero") }
    }

    var body: some View {
        List {
            if !girlWorkouts.isEmpty {
                Section("Girl Benchmarks") {
                    ForEach(girlWorkouts) { workout in
                        WorkoutRow(workout: workout)
                    }
                }
            }

            if !heroWorkouts.isEmpty {
                Section("Hero Benchmarks") {
                    ForEach(heroWorkouts) { workout in
                        WorkoutRow(workout: workout)
                    }
                }
            }

            if !customWorkouts.isEmpty {
                Section("Custom Workouts") {
                    ForEach(customWorkouts) { workout in
                        WorkoutRow(workout: workout)
                    }
                    .onDelete(perform: deleteCustomWorkouts)
                }
            }
        }
        .navigationTitle("WODs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
    }

    private func deleteCustomWorkouts(at offsets: IndexSet) {
        for index in offsets {
            let workout = customWorkouts[index]
            modelContext.delete(workout)
        }
        try? modelContext.save()
    }
}

struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        NavigationLink(destination: WODDetailView(workout: workout)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(workout.name)
                        .font(.headline)
                    Spacer()
                    Label(workout.mode.title, systemImage: workout.mode.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let desc = workout.workoutDescription {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
