import SwiftUI

struct TimerView: View {
    @Environment(ServiceFactory.self) private var serviceFactory
    @Environment(\.dismiss) private var dismiss

    let workout: Workout
    @State private var service: WorkoutTimerService?
    @State private var selectedTaskID: UUID?
    @State private var isConfirmingFinish = false

    private var snapshot: SessionSnapshot {
        service?.snapshot ?? .idle
    }

    private var isIdle: Bool { snapshot.phase == .idle }

    private var tasks: [WODSimulator.Task] { snapshot.tasks }

    /// The task the quick-count buttons act on: the user's selection if still
    /// incomplete, otherwise the first remaining task (auto-advances as sets
    /// are finished).
    private var activeTask: WODSimulator.Task? {
        if let id = selectedTaskID, let task = tasks.first(where: { $0.id == id }), !task.isComplete {
            return task
        }
        return tasks.first(where: { !$0.isComplete })
    }

    private var roundIndicatorText: String {
        if snapshot.hasLoopingRounds {
            return "AMRAP · Round \(snapshot.roundsCompleted + 1)"
        } else if snapshot.totalRounds > 1 {
            let current = min(snapshot.roundsCompleted + 1, snapshot.totalRounds)
            return "Round \(current) of \(snapshot.totalRounds)"
        } else if workout.mode == .forTime {
            return "For Time"
        } else {
            return "Top Time"
        }
    }

    private var timeCapLabel: String? {
        if workout.mode == .forTime, let minutes = workout.forTimeMinutes {
            return "Time Cap \(Format.timer(minutes))"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if isIdle {
                    idleView
                } else {
                    runningView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isIdle {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            if service == nil {
                service = serviceFactory.makeTimerService(for: workout)
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

    // MARK: - Idle (Pre-Start)

    private var idleView: some View {
        VStack(spacing: 24) {
            Text(workout.name)
                .font(.title.bold())
            Text(workout.mode == .forTime ? "For Time" : "Top Time")
                .font(.headline)
                .foregroundStyle(.tint)

            ScrollView {
                WorkoutSchemeView(workout: workout)
                    .padding(.horizontal)
            }

            Button {
                selectedTaskID = tasks.first?.id
                service?.start()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Workout")
                }
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 16) {
            header

            VStack(spacing: 2) {
                Text(Format.duration(snapshot.activeElapsed))
                    .font(.system(size: 56, weight: .heavy, design: .monospaced))
                    .contentTransition(.numericText())
                if let label = timeCapLabel {
                    Text("\(label) · Elapsed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if snapshot.phase == .resting {
                restBanner
            }

            remainingHeadline

            taskList

            if let task = activeTask {
                quickCounterBar(for: task)
            }

            controlBar
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(workout.name)
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(roundIndicatorText)
                .font(.subheadline.bold())
                .foregroundStyle(.tint)
        }
        .padding(.top, 8)
    }

    private var remainingHeadline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(snapshot.totalRemaining)")
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .contentTransition(.numericText())
            Text("reps left")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(tasks) { task in
                    taskRow(task)
                }
            }
            .padding(.horizontal)
        }
    }

    private func taskRow(_ task: WODSimulator.Task) -> some View {
        Button {
            if !task.isComplete {
                selectedTaskID = task.id
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.displayLabel)
                        .font(.body.weight(activeTask?.id == task.id ? .semibold : .regular))
                        .foregroundStyle(task.isComplete ? .secondary : .primary)
                    if task.quota > 1 {
                        Text("\(task.completed) of \(task.quota) reps")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if task.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                } else {
                    Text("\(task.remaining) left")
                        .font(.subheadline.bold())
                        .foregroundStyle(activeTask?.id == task.id ? Color.accentColor : .secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(activeTask?.id == task.id
                          ? Color.accentColor.opacity(0.12)
                          : Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(task.isComplete)
    }

    private func quickCounterBar(for task: WODSimulator.Task) -> some View {
        HStack(spacing: 12) {
            ForEach([1, 5, 10, 25], id: \.self) { count in
                Button {
                    _ = service?.logReps(taskID: task.id, count: count)
                } label: {
                    Text("+\(count)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(!snapshot.isRunning || count > task.remaining)
            }
        }
        .padding(.horizontal)
    }

    private var restBanner: some View {
        HStack {
            Image(systemName: "pause.circle.fill")
            Text("Resting...")
                .bold()
            Spacer()
            Button("Skip Rest") {
                service?.endRest()
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var controlBar: some View {
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
                .padding(.vertical, 14)
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
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(snapshot.isFinished)
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
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

                Text("\(snapshot.totalRepsCompleted) Total Reps")
                    .font(.headline)

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