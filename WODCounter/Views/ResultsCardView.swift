import SwiftUI

/// A self-contained card suitable for rendering via `ImageRenderer` / `ShareLink`.
/// Receives a `WorkoutRecord` + its parent `Workout` directly (no SwiftData environment needed).
struct ResultsCardView: View {
    let record: WorkoutRecord
    let workout: Workout

    private var dateText: String {
        record.date.formatted(date: .abbreviated, time: .omitted)
    }

    private var primaryMetric: String {
        if workout.mode == .forTime {
            return "\(record.roundsCompleted) Rounds"
        } else {
            return Format.duration(record.activeTime)
        }
    }

    private var primaryMetricLabel: String {
        workout.mode == .forTime ? "Rounds Completed" : "Active Time"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    WorkoutModeBadge(mode: workout.mode)
                }

                Spacer()

                if record.isPR {
                    Label("PR", systemImage: "star.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                }
            }
            .padding()

            Divider()

            // Primary metric
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryMetricLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(primaryMetric)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)

                if workout.mode == .forTime {
                    Text("Active Time: \(Format.duration(record.activeTime))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(record.roundsCompleted) rounds · \(record.totalReps) total reps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("WOD Counter")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}
