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
                        Label(workout.mode.title, systemImage: workout.mode.symbol)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())

                        if let category = workout.category {
                            Text(category)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if workout.mode == .forTime, let minutes = workout.forTimeMinutes {
                        Text("For Time (AMRAP) — \(Format.timer(minutes))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.tint)
                    } else if workout.mode == .topTime {
                        Text("Top Time — Race to complete all reps")
                            .font(.subheadline.bold())
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Scheme") {
                if workout.blocks.isEmpty {
                    Text("No exercises specified.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(workout.blocks.enumerated()), id: \.offset) { index, block in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(blockHeader(for: block, index: index, total: workout.blocks.count))
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let rest = block.restAfterBlock, rest > 0 {
                                    Text("Rest: \(rest)s")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            ForEach(block.exercises) { exercise in
                                HStack {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(.secondary)
                                    Text(exercise.displayLabel ?? exercise.movement?.name ?? "Exercise")
                                        .font(.body)
                                }
                                .padding(.leading, 4)
                            }
                        }
                        .padding(.vertical, 4)
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
    }

    private func blockHeader(for block: RoundBlock, index: Int, total: Int) -> String {
        if total > 1 {
            return "Block \(index + 1) of \(total)"
        } else if block.repeatTimes > 1 {
            return "Repeat \(block.repeatTimes) Rounds"
        } else if workout.mode == .forTime && block.repeatTimes == 0 {
            return "Continuous Rounds (AMRAP)"
        } else {
            return "Round 1"
        }
    }
}
