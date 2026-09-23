import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Workout.name) private var workouts: [Workout]
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingSettings = false
    @State private var isShowingCreate = false

    private var girlWorkouts: [Workout] {
        workouts.filter { $0.isGirlBenchmark }
    }

    private var heroWorkouts: [Workout] {
        workouts.filter { $0.isHeroBenchmark }
    }

    private var customWorkouts: [Workout] {
        workouts.filter { $0.isCustom }
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
                    isShowingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $isShowingCreate) {
            NavigationStack {
                CreateWODView()
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(workout.name)
                        .font(.headline)
                    Spacer()
                    WorkoutModeBadge(mode: workout.mode)
                }

                if let desc = workout.workoutDescription {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                WorkoutSchemeView(workout: workout, isCompact: true)
            }
            .padding(.vertical, 4)
        }
    }
}
