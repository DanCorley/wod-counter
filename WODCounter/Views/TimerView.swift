import SwiftUI

struct TimerView: View {
    @Environment(ServiceFactory.self) private var serviceFactory
    @Environment(\.dismiss) private var dismiss

    let workout: Workout
    @State private var service: WorkoutTimerService?
    @State private var isConfirmingFinish = false

    private var snapshot: SessionSnapshot {
        service?.snapshot ?? .idle
    }

    private var clockDisplay: String {
        if workout.mode == .forTime, let minutes = workout.forTimeMinutes {
            let remaining = max(0, Double(minutes * 60) - snapshot.activeElapsed)
            return Format.duration(remaining)
        } else {
            return Format.duration(snapshot.activeElapsed)
        }
    }

    private var roundIndicatorText: String {
        if workout.mode == .forTime {
            return "Round \(snapshot.roundsCompleted + 1) (AMRAP)"
        } else if workout.blocks.count > 1 {
            return "Block \(snapshot.blockIndex + 1) of \(workout.blocks.count)"
        } else {
            let repeats = workout.blocks.first?.repeatTimes ?? 1
            return repeats > 1
                ? "Round \(snapshot.roundsCompleted + 1) of \(repeats)"
                : "Round 1 of 1"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header & Round Indicator
                VStack(spacing: 4) {
                    Text(workout.name)
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                    Text(roundIndicatorText)
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
                .padding(.top, 8)

                // Large Main Clock
                Text(clockDisplay)
                    .font(.system(size: 68, weight: .heavy, design: .monospaced))
                    .contentTransition(.numericText())
                    .padding(.vertical, 8)

                // Rest Period Banner (if active)
                if snapshot.phase == .resting {
                    HStack {
                        Image(systemName: "pause.circle.fill")
                        Text("Resting...")
                            .bold()
                        Spacer()
                        Button("Skip Rest") {
                            _ = service?.endRest()
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // Primary Large Tap Area for Rep Counting
                Button {
                    _ = service?.advanceRep()
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.tint)

                        Text(snapshot.currentExerciseLabel)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text("Tap to log rep")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if snapshot.repsInCurrentExercise > 0 {
                            Text("\(snapshot.repsInCurrentExercise) reps completed")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.tintColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.tintColor.opacity(0.3), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(snapshot.phase == .paused || snapshot.phase == .resting || snapshot.isFinished)
                .padding(.horizontal)

                // Control Bar (Pause/Resume & Finish)
                HStack(spacing: 16) {
                    Button {
                        if snapshot.isPaused {
                            service?.resume()
                        } else {
                            service?.pause()
                        }
                    } label: {
                        HStack {
                            Image(systemName: snapshot.isPaused ? "play.fill" : "pause.fill")
                            Text(snapshot.isPaused ? "Resume" : "Pause")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.bordered)
                    .tint(snapshot.isPaused ? .green : .orange)
                    .disabled(snapshot.isFinished)

                    Button(role: .destructive) {
                        isConfirmingFinish = true
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Finish")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(snapshot.isFinished)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if service == nil {
                    let s = serviceFactory.makeTimerService(for: workout)
                    s.start()
                    self.service = s
                }
            }
            .confirmationDialog(
                "End Workout Early?",
                isPresented: $isConfirmingFinish,
                titleVisibility: .visible
            ) {
                Button("End Workout", role: .destructive) {
                    service?.finish()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: Binding(
                get: { snapshot.isFinished },
                set: { _ in }
            )) {
                WorkoutCompletionSheet(workout: workout, snapshot: snapshot) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Completion Sheet
struct WorkoutCompletionSheet: View {
    let workout: Workout
    let snapshot: SessionSnapshot
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
                .padding(.top, 32)

            Text("Workout Complete!")
                .font(.title.bold())

            VStack(spacing: 8) {
                Text(workout.name)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if workout.mode == .forTime {
                    Text("\(snapshot.roundsCompleted) Rounds Completed")
                        .font(.system(size: 32, weight: .bold))
                } else {
                    Text(Format.duration(snapshot.activeElapsed))
                        .font(.system(size: 40, weight: .heavy, design: .monospaced))
                }

                Text("Active Time: \(Format.duration(snapshot.activeElapsed))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private extension Color {
    static var tintColor: Color {
        Color.accentColor
    }
}
