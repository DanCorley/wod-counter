import SwiftUI

struct WorkoutSchemeView: View {
    let workout: Workout
    var isCompact: Bool = false

    var body: some View {
        if workout.blocks.isEmpty {
            Text("No exercises specified.")
                .foregroundStyle(.secondary)
        } else if isCompact {
            compactView
        } else {
            expandedView
        }
    }

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(workout.blocks.flatMap { $0.exercises }.prefix(3)) { exercise in
                Text(exercise.displayLabel ?? exercise.movement?.name ?? "Exercise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if workout.blocks.flatMap({ $0.exercises }).count > 3 {
                Text("+ more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var expandedView: some View {
        ForEach(Array(workout.blocks.enumerated()), id: \.offset) { index, block in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(workout.blockHeader(for: block, index: index))
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
                    HStack(spacing: 8) {
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
