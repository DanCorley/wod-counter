import SwiftUI
import SwiftData

struct WODDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel: AppModel?

    let workout: Workout
    @State private var isStartingWorkout = false
    @State private var isShowingEdit = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(workout.name)
                        .font(.title2.bold())

                    if let desc = workout.workoutDescription {
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        WorkoutModeBadge(mode: workout.mode, isProminent: true)

                        if let category = workout.category {
                            Text(category)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(workout.modeSubtitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(.tint)
                }
                .padding(.vertical, 4)
            }

            Section("Scheme") {
                WorkoutSchemeView(workout: workout, isCompact: false)
            }

            if !workout.records.isEmpty {
                Section("History") {
                    NavigationLink {
                        WODAttemptsView(workout: workout, window: .allTime)
                    } label: {
                        HStack {
                            Label("View Results", systemImage: "chart.bar.xaxis")
                            Spacer()
                            Text("\(workout.records.count) attempt\(workout.records.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button {
                    appModel?.startWorkout(workout)
                    isStartingWorkout = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Start Workout", systemImage: "play.fill")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if !workout.isBuiltin {
                Section {
                    Button(role: .destructive) {
                        modelContext.delete(workout)
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Workout", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !workout.isBuiltin {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        isShowingEdit = true
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            NavigationStack {
                CreateWODView(editingWorkout: workout)
            }
        }
        .fullScreenCover(isPresented: $isStartingWorkout) {
            TimerView(workout: workout)
        }
    }
}

