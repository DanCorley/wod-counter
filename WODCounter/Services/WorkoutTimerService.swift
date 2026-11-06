import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class WorkoutTimerService: Identifiable {
    struct Hook: Sendable {
        var onFinish: @MainActor @Sendable (WorkoutRecord) -> Void
    }

    let id: UUID
    let workout: Workout
    private var simulator: WODSimulator
    private let hook: Hook
    private let clock: @Sendable () -> Date

    private struct UndoEntry {
        let taskID: UUID
        let count: Int
    }

    private(set) var snapshot: SessionSnapshot
    /// The record created when the session finished, exposed for the
    /// completion sheet (PR badge + share card). `nil` until completion.
    private(set) var completedRecord: WorkoutRecord?
    private var undoStack: [UndoEntry] = []
    private var ticker: Task<Void, Never>?
    private var timeline = SessionTimeline()
    /// Clock reading of the last time the simulator was advanced. `nil` while
    /// idle or paused, so only real active intervals are fed to the engine.
    private var lastRefreshAt: Date?
    private var hasPersisted = false

    var canUndo: Bool { !undoStack.isEmpty }

    init(
        id: UUID = UUID(),
        workout: Workout,
        clock: @escaping @Sendable () -> Date = { Date() },
        onFinish: @escaping @MainActor @Sendable (WorkoutRecord) -> Void
    ) {
        self.id = id
        self.workout = workout
        self.hook = Hook(onFinish: onFinish)
        self.clock = clock
        let sim = WODSimulator(workout: workout)
        self.simulator = sim
        self.snapshot = sim.snapshot
    }

    // MARK: - Controls
    func start() {
        guard simulator.phase == .idle else { return }
        let now = clock()
        timeline.start(at: now)
        lastRefreshAt = now
        simulator.start()
        publish()
        scheduleTicker()
    }

    func pause() {
        guard simulator.phase == .running || simulator.phase == .resting else { return }
        // Bring the engine to the exact pause moment before freezing the clock.
        let now = syncToNow()
        guard simulator.phase == .running || simulator.phase == .resting else {
            publish()
            return
        }
        simulator.pause()
        timeline.pause(at: now)
        lastRefreshAt = nil
        stopTicker()
        publish()
    }

    func resume() {
        guard simulator.phase == .paused else { return }
        let now = clock()
        timeline.resume(at: now)
        lastRefreshAt = now
        simulator.resume()
        publish()
        scheduleTicker()
    }

    /// Logs completed reps against any pending task. Returns the resulting event.
    /// Partial additions are remembered so they can be undone; completing a
    /// task or round clears that history to keep round/AMRAP state consistent.
    @discardableResult
    func logReps(taskID: UUID, count: Int) -> TimerEvent {
        let now = syncToNow()
        let beforeReps = simulator.totalRepsCompleted
        let ev = simulator.completeReps(taskID: taskID, count: count)
        let added = simulator.totalRepsCompleted - beforeReps

        if ev != .none {
            undoStack.removeAll()
        } else if added > 0 {
            let taskCompleted = simulator.liveTasks
                .first(where: { $0.id == taskID })?.isComplete ?? true
            if taskCompleted {
                undoStack.removeAll()
            } else {
                undoStack.append(UndoEntry(taskID: taskID, count: added))
            }
        }

        if case .finished = ev {
            handleFinishedSession(at: now)
        }
        publish()
        return ev
    }

    /// Reverses the most recent partial rep addition. No-op when there is
    /// nothing safe to undo (for example after a task or round completed).
    @discardableResult
    func undoLastReps() -> Int {
        guard let entry = undoStack.last else { return 0 }
        _ = syncToNow()
        let removed = simulator.removeReps(taskID: entry.taskID, count: entry.count)
        if removed > 0 {
            undoStack.removeLast()
        }
        publish()
        return removed
    }

    func startRest(duration: TimeInterval? = nil) -> TimerEvent {
        _ = syncToNow()
        let ev = simulator.startRest(duration: duration)
        publish()
        return ev
    }

    func endRest() -> TimerEvent {
        _ = syncToNow()
        let wasPausedDuringRest = simulator.phase == .paused && simulator.restDeadline != nil
        let ev = simulator.endRest()
        if wasPausedDuringRest {
            let now = clock()
            timeline.resume(at: now)
            lastRefreshAt = now
            scheduleTicker()
        }
        publish()
        return ev
    }

    func finish() {
        guard simulator.phase != .finished, simulator.phase != .idle else { return }
        let now = syncToNow()
        // A deadline may have fired while catching up; completion is already
        // handled in that case.
        guard simulator.phase != .finished else {
            publish()
            return
        }
        _ = simulator.finish()
        handleFinishedSession(at: now)
        publish()
    }

    func reset() {
        stopTicker()
        simulator.reset()
        timeline = SessionTimeline()
        lastRefreshAt = nil
        hasPersisted = false
        completedRecord = nil
        undoStack.removeAll()
        publish()
    }

    /// Abandons a live session without persisting a record (used by the close
    /// confirmation's Discard action).
    func discard() {
        stopTicker()
        lastRefreshAt = nil
        timeline = SessionTimeline()
        undoStack.removeAll()
        completedRecord = nil
    }

    /// Refreshes the published snapshot and advances the engine by the real
    /// active time elapsed since the last refresh. Not a source of time itself.
    func refresh() {
        _ = syncToNow()
        publish()
    }

    // MARK: - Internal Session Handling

    /// Advances the simulator to `clock()`'s current reading by the active
    /// interval since the previous refresh. Returns that reading.
    @discardableResult
    private func syncToNow() -> Date {
        let now = clock()
        guard let anchor = lastRefreshAt else { return now }
        lastRefreshAt = now
        let delta = now.timeIntervalSince(anchor)
        guard delta > 0 else { return now }

        let wasFinished = simulator.phase == .finished
        simulator.advanceTime(delta, active: true)
        if simulator.phase == .finished && !wasFinished {
            handleFinishedSession(at: now)
        }
        return now
    }

    private func handleFinishedSession(at finishDate: Date) {
        guard !hasPersisted, timeline.hasStarted else { return }
        hasPersisted = true
        stopTicker()
        lastRefreshAt = nil
        undoStack.removeAll()
        timeline.finish(at: finishDate)

        let totalElapsed = timeline.wallElapsed(at: finishDate)
        let pausedTime = timeline.pausedElapsed(at: finishDate)
        let activeTime = max(0, totalElapsed - pausedTime)
        let kind = workout.mode == .forTime ? "rounds" : "time"

        let record = WorkoutRecord(
            workout: workout,
            date: finishDate,
            kind: kind,
            roundsCompleted: simulator.roundsCompleted,
            totalReps: simulator.totalRepsCompleted,
            elapsedTime: totalElapsed,
            pausedTime: pausedTime,
            activeTime: activeTime,
            isPR: false
        )
        completedRecord = record
        hook.onFinish(record)
    }

    private func scheduleTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self = self else { return }
                let phase = self.simulator.phase
                if phase == .paused || phase == .finished || phase == .idle {
                    return
                }
                self.refresh()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func publish() {
        let now = clock()
        var snap = simulator.snapshot
        // The simulator only tracks active intervals; wall time and pause time
        // come from the session timeline.
        snap.wallClock = timeline.wallElapsed(at: now)
        snap.activeElapsed = timeline.activeElapsed(at: now)
        snapshot = snap
    }
}
