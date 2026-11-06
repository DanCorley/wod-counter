import SwiftUI

struct TimerView: View {
    @Environment(ServiceFactory.self) private var serviceFactory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let workout: Workout
    @State private var service: WorkoutTimerService?
    @State private var selectedTaskID: UUID?
    @State private var isConfirmingFinish = false
    @State private var isConfirmingClose = false

    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 56
    @ScaledMetric(relativeTo: .largeTitle) private var remainingSize: CGFloat = 54

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

    private struct TaskGroup: Identifiable {
        let id: String
        let title: String
        let tasks: [WODSimulator.Task]
    }

    private var needsGrouping: Bool {
        snapshot.totalRounds > 1 || workout.orderedBlocks.count > 1
    }

    /// Consecutive tasks sharing a block/round, labelled for multi-round or
    /// multi-block workouts. Single-round workouts keep the flat list.
    private var groupedTasks: [TaskGroup] {
        guard needsGrouping else {
            return [TaskGroup(id: "all", title: "", tasks: tasks)]
        }

        var groups: [TaskGroup] = []
        for task in tasks {
            let id = "\(task.blockIndex)-\(task.roundNumber)"
            if let last = groups.last, last.id == id {
                groups[groups.count - 1] = TaskGroup(
                    id: last.id,
                    title: last.title,
                    tasks: last.tasks + [task]
                )
            } else {
                groups.append(TaskGroup(id: id, title: groupTitle(for: task), tasks: [task]))
            }
        }
        return groups
    }

    private func groupTitle(for task: WODSimulator.Task) -> String {
        let blocks = workout.orderedBlocks
        if blocks.count > 1, blocks.indices.contains(task.blockIndex) {
            return workout.blockHeader(for: blocks[task.blockIndex], index: task.blockIndex)
        }
        return "Round \(task.roundNumber)"
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
                        Button("Close") {
                            if snapshot.isLive {
                                isConfirmingClose = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if service == nil {
                service = serviceFactory.makeTimerService(for: workout)
            }
        }
        // Auto-pause when the app leaves the foreground so background time is
        // recorded as pause rather than silently lost. Resuming is always an
        // explicit athlete action.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                service?.pause()
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
        .confirmationDialog(
            "Discard This Session?",
            isPresented: $isConfirmingClose,
            titleVisibility: .visible
        ) {
            Button("Discard Session", role: .destructive) {
                service?.discard()
                dismiss()
            }
            Button("Keep Working", role: .cancel) {}
        } message: {
            Text("Your workout is still in progress. Discarding will not save a result.")
        }
        .sheet(isPresented: Binding(
            get: { snapshot.isFinished },
            set: { _ in }
        )) {
            WorkoutCompletionSheet(
                workout: workout,
                snapshot: snapshot,
                record: service?.completedRecord
            ) {
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
                    .font(.system(size: clockSize, weight: .heavy, design: .monospaced))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(Format.duration(snapshot.activeElapsed))
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
                .font(.system(size: remainingSize, weight: .heavy, design: .rounded))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("reps left")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remaining reps")
        .accessibilityValue("\(snapshot.totalRemaining)")
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(groupedTasks) { group in
                    if !group.title.isEmpty {
                        Text(group.title)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                    }
                    ForEach(group.tasks) { task in
                        taskRow(task)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func taskRow(_ task: WODSimulator.Task) -> some View {
        let isActive = activeTask?.id == task.id
        return Button {
            if !task.isComplete {
                selectedTaskID = task.id
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.displayLabel)
                        .font(.body.weight(isActive ? .semibold : .regular))
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
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive
                          ? Color.accentColor.opacity(0.12)
                          : Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(task.isComplete)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.displayLabel)\(isActive ? ", active task" : "")")
        .accessibilityValue(task.isComplete ? "Complete" : "\(task.remaining) reps remaining")
    }

    private func quickCounterBar(for task: WODSimulator.Task) -> some View {
        VStack(spacing: 8) {
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
                    .accessibilityLabel("Add \(count) reps to \(task.displayLabel)")
                }
            }

            Button {
                _ = service?.undoLastReps()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .disabled(!snapshot.isRunning || !(service?.canUndo ?? false))
            .accessibilityHint("Reverses the most recent partial rep addition")
        }
        .padding(.horizontal)
    }

    private var restBanner: some View {
        HStack {
            Image(systemName: "pause.circle.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Resting")
                    .bold()
                if let remaining = snapshot.restRemaining {
                    Text(Format.duration(remaining))
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .contentTransition(.numericText())
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Resting")
            .accessibilityValue(snapshot.restRemaining.map { "\(Int($0)) seconds remaining" } ?? "")
            .accessibilityAddTraits(.updatesFrequently)
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
    let record: WorkoutRecord?
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.yellow)
                    .padding(.top, 24)

                Text("Workout Complete!")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                if let record {
                    if record.isPR {
                        Label("New Personal Record", systemImage: "star.fill")
                            .font(.headline)
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.yellow.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    ResultsCardView(record: record, workout: workout)
                        .padding(.horizontal)

                    ShareLink(
                        item: renderedCard(record),
                        preview: SharePreview(
                            "\(workout.name) — \(record.date.formatted(date: .abbreviated, time: .omitted))",
                            image: renderedCard(record)
                        )
                    ) {
                        Label("Share Result", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                } else {
                    summaryFallback
                }

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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var summaryFallback: some View {
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
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    @MainActor
    private func renderedCard(_ record: WorkoutRecord) -> Image {
        let renderer = ImageRenderer(
            content: ResultsCardView(record: record, workout: workout)
                .frame(width: 320)
                .padding()
                .background(Color(.systemBackground))
        )
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}