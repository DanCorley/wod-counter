import Foundation

struct SessionSnapshot: Equatable, Sendable {
    var phase: WODSimulator.Phase
    var roundsCompleted: Int
    var blockIndex: Int
    var exerciseIndex: Int
    var repsInCurrentExercise: Int
    var currentExerciseLabel: String
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
            blockIndex: 0,
            exerciseIndex: 0,
            repsInCurrentExercise: 0,
            currentExerciseLabel: "—",
            wallClock: 0,
            activeElapsed: 0,
            isPaused: false,
            isFinished: false
        )
    }
}
