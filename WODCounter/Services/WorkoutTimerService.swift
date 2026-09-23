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
        guard simulator.phase != .finished else { return }
        simulator.start()
        publish()
        scheduleTicker()
    }

    func pause() {
        guard simulator.phase == .running || simulator.phase == .resting else { return }
        simulator.pause()
        stopTicker()
        publish()
    }

    func resume() {
        guard simulator.phase == .paused else { return }
        simulator.resume()
        publish()
        scheduleTicker()
    }

    /// Logs completed reps against any pending task. Returns the resulting event.
    @discardableResult
    func logReps(taskID: UUID, count: Int) -> TimerEvent {
        let ev = simulator.completeReps(taskID: taskID, count: count)
        publish()
        if case .finished = ev {
            handleFinishedSession()
        }
        return ev
    }

    func startRest(duration: TimeInterval? = nil) -> TimerEvent {
        let ev = simulator.startRest(duration: duration)
        publish()
        return ev
    }

    func endRest() -> TimerEvent {
        let ev = simulator.endRest()
        publish()
        return ev
    }

    func finish() {
        if simulator.phase == .running || simulator.phase == .resting {
            stopTicker()
        }
        _ = simulator.finish()
        publish()
        handleFinishedSession()
    }

    func reset() {
        stopTicker()
        simulator.reset()
        publish()
    }

    func advanceTimeStep(_ dt: TimeInterval, active: Bool) {
        let wasFinished = simulator.phase == .finished
        simulator.advanceTime(dt, active: active)
        if simulator.phase == .finished && !wasFinished {
            handleFinishedSession()
        }
        publish()
    }

    // MARK: - Internal Session Handling
    private func handleFinishedSession() {
        stopTicker()
        let activeTime = simulator.resultActiveTime
        let totalElapsed = simulator.wallClock
        let pausedTime = totalElapsed - activeTime
        let kind = workout.mode == .forTime ? "rounds" : "time"
        let currentDate = clock()

        let record = WorkoutRecord(
            workout: workout,
            date: currentDate,
            kind: kind,
            roundsCompleted: simulator.roundsCompleted,
            totalReps: simulator.totalRepsCompleted,
            elapsedTime: totalElapsed,
            pausedTime: pausedTime,
            activeTime: activeTime,
            isPR: false
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
                self.advanceTimeStep(1, active: true)
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