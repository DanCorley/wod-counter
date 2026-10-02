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

    private(set) var snapshot: SessionSnapshot
    private var ticker: Task<Void, Never>?

    /// When the session started, per the injected clock. Elapsed time is always
    /// derived from this against the current clock reading — never accumulated
    /// per tick — so a late, missed, or suspended tick costs nothing but a
    /// momentarily stale label.
    private var startedAt: Date?
    /// When the current pause began, if paused.
    private var pausedAt: Date?
    /// Total time spent paused across all completed pauses.
    private var pausedTotal: TimeInterval = 0
    /// Set once the finish record has been handed off, so it can only happen once.
    private var didReportFinish = false
    /// Whether this session is currently holding the screen awake.
    ///
    /// `nonisolated(unsafe)` because `deinit` is nonisolated and needs to read
    /// it to decide whether to balance the hold. That is safe here: a
    /// deallocating object has no other live references, so nothing can race
    /// the read. Every other access is on the main actor.
    private nonisolated(unsafe) var isHoldingScreen = false

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

    deinit {
        // A session can be torn down without any of the normal exit paths
        // running — a navigation pop, say. Releasing here is what guarantees
        // the hold is always balanced. `deinit` is not guaranteed to run on the
        // main actor, hence the hop; nothing captures `self`.
        if isHoldingScreen {
            Task { @MainActor in ScreenSleep.release() }
        }
    }

    // MARK: - Screen

    /// Holds or releases the screen-awake lock, idempotently — so repeated
    /// calls from overlapping lifecycle events cannot unbalance the count.
    private func holdScreen(_ wanted: Bool) {
        guard wanted != isHoldingScreen else { return }
        isHoldingScreen = wanted
        if wanted {
            ScreenSleep.hold()
        } else {
            ScreenSleep.release()
        }
    }

    // MARK: - Derived Time

    /// Wall time since start, including paused stretches.
    private var wallElapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, clock().timeIntervalSince(startedAt))
    }

    /// Paused time so far, including an in-progress pause.
    private var pausedElapsed: TimeInterval {
        guard let pausedAt else { return pausedTotal }
        return pausedTotal + max(0, clock().timeIntervalSince(pausedAt))
    }

    // MARK: - Controls

    func start() {
        guard simulator.phase == .idle else { return }
        startedAt = clock()
        pausedAt = nil
        pausedTotal = 0
        simulator.start()
        holdScreen(true)
        refresh()
        scheduleTicker()
    }

    func pause() {
        guard simulator.phase == .running || simulator.phase == .resting else { return }
        // Bank the time worked up to this instant before the clock freezes,
        // so pausing between ticks cannot shave off the partial second.
        simulator.updateTime(active: wallElapsed - pausedElapsed, wall: wallElapsed)
        pausedAt = clock()
        simulator.pause()
        stopTicker()
        // Paused means the athlete has stepped away; let the screen sleep.
        holdScreen(false)
        publish()
    }

    func resume() {
        guard simulator.phase == .paused else { return }
        if let pausedAt {
            pausedTotal += max(0, clock().timeIntervalSince(pausedAt))
        }
        pausedAt = nil
        simulator.resume()
        holdScreen(true)
        refresh()
        scheduleTicker()
    }

    /// Logs completed reps against any pending task. Returns the resulting event.
    @discardableResult
    func logReps(taskID: UUID, count: Int) -> TimerEvent {
        let ev = simulator.completeReps(taskID: taskID, count: count)
        refresh()
        if case .finished(let reason) = ev {
            handleFinishedSession(reason: reason)
        }
        return ev
    }

    @discardableResult
    func startRest(duration: TimeInterval? = nil) -> TimerEvent {
        let ev = simulator.startRest(duration: duration)
        refresh()
        return ev
    }

    @discardableResult
    func endRest() -> TimerEvent {
        let ev = simulator.endRest()
        refresh()
        return ev
    }

    func finish() {
        guard simulator.phase != .finished else { return }
        stopTicker()

        // Settle the clock first so the recorded time is current rather than
        // whatever the last tick happened to leave behind.
        if simulator.phase != .idle {
            simulator.updateTime(active: wallElapsed - pausedElapsed, wall: wallElapsed)
        }

        // Settling may itself have tripped the time cap, which is a different
        // outcome from the athlete choosing to stop.
        let reason: FinishedReason = simulator.phase == .finished ? .clockExpired : .manual
        if simulator.phase != .finished {
            _ = simulator.finish()
        }

        publish()
        handleFinishedSession(reason: reason)
    }

    func reset() {
        stopTicker()
        holdScreen(false)
        simulator.reset()
        startedAt = nil
        pausedAt = nil
        pausedTotal = 0
        didReportFinish = false
        publish()
    }

    /// Recomputes elapsed time from the clock and republishes. Safe and cheap to
    /// call at any time — on a tick, on returning to the foreground, or on a
    /// view appearing. Idempotent.
    func refresh() {
        guard simulator.phase != .idle, simulator.phase != .finished else {
            publish()
            return
        }
        // The guard above means the session was live coming in, so a .finished
        // phase here is newly reached — only the time cap can do that.
        simulator.updateTime(active: wallElapsed - pausedElapsed, wall: wallElapsed)
        publish()
        if simulator.phase == .finished {
            stopTicker()
            handleFinishedSession(reason: .clockExpired)
        }
    }

    // MARK: - Internal Session Handling

    private func handleFinishedSession(reason: FinishedReason) {
        guard !didReportFinish else { return }
        didReportFinish = true
        stopTicker()
        holdScreen(false)

        let record = WorkoutRecord(
            workout: workout,
            date: clock(),
            kind: workout.mode == .forTime ? "rounds" : "time",
            roundsCompleted: simulator.roundsCompleted,
            totalReps: simulator.totalRepsCompleted,
            elapsedTime: simulator.wallClock,
            pausedTime: simulator.pausedAccumulated,
            activeTime: simulator.resultActiveTime,
            isPR: false,
            finishedReason: reason.rawValue,
            repsQuota: simulator.initialQuota
        )
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
        snapshot = simulator.snapshot
    }
}
