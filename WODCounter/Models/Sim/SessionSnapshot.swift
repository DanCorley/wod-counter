import Foundation

struct SessionSnapshot: Equatable, Sendable {
    var phase: WODSimulator.Phase
    var roundsCompleted: Int
    var totalRounds: Int
    var hasLoopingRounds: Bool
    var tasks: [WODSimulator.Task]
    var totalRepsCompleted: Int
    var totalRemaining: Int
    var wallClock: TimeInterval
    var activeElapsed: TimeInterval
    var isPaused: Bool
    var isFinished: Bool

    var isRunning: Bool { phase == .running }
    var shouldShowResults: Bool { phase == .finished }
}

extension SessionSnapshot {
    static var idle: SessionSnapshot {
        SessionSnapshot(
            phase: .idle,
            roundsCompleted: 0,
            totalRounds: 0,
            hasLoopingRounds: false,
            tasks: [],
            totalRepsCompleted: 0,
            totalRemaining: 0,
            wallClock: 0,
            activeElapsed: 0,
            isPaused: false,
            isFinished: false
        )
    }
}