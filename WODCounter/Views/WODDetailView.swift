import SwiftUI
import SwiftData

struct WODDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel: AppModel?

    let workout: Workout
    @State private var isStartingWorkout = false

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
    }
}
