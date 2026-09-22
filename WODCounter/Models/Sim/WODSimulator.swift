import Foundation

struct WODSimulator: Sendable {
    enum Phase: String, Sendable, Equatable {
        case idle
        case running
        case paused
        case resting
        case finished
    }

    let workout: Workout

    // MARK: - Progress State
    private(set) var phase: Phase = .idle
    private(set) var roundsCompleted: Int = 0
    private(set) var blockIndex: Int = 0
    private(set) var exerciseIndex: Int = 0
    private(set) var repsCompletedInCurrentExercise: Int = 0
    private(set) var totalRepsCompleted: Int = 0
    private(set) var wallClock: TimeInterval = 0
    private(set) var pausedAccumulated: TimeInterval = 0
    private(set) var restDeadline: TimeInterval? = nil

    init(workout: Workout) {
        self.workout = workout
    }

    // MARK: - Derived Properties
    var currentBlock: RoundBlock? {
        guard blockIndex < workout.blocks.count else { return nil }
        return workout.blocks[blockIndex]
    }

    var currentExercise: Exercise? {
        guard let block = currentBlock, exerciseIndex < block.exercises.count else { return nil }
        return block.exercises[exerciseIndex]
    }

    var currentRepProgress: Int {
        repsCompletedInCurrentExercise
    }

    var currentEffectiveReps: Int {
        currentExercise?.effectiveReps ?? 1
    }

    var resultRounds: Int {
        roundsCompleted
    }

    var resultActiveTime: TimeInterval {
        max(0, wallClock - pausedAccumulated)
    }

    var forTimeMinutes: Int? {
        workout.mode == .forTime ? workout.forTimeMinutes : nil
    }

    var isClockExpired: Bool {
        guard let minutes = forTimeMinutes else { return false }
        return resultActiveTime >= Double(minutes) * 60
    }

    var playTarget: Int? {
        switch workout.mode {
        case .topTime:
            let total = workout.blocks.reduce(0) { $0 + ($1.repeatTimes > 0 ? $1.repeatTimes : 1) }
            return total > 0 ? total : 1
        case .forTime:
            if workout.blocks.allSatisfy({ $0.repeatTimes == 0 }) {
                return nil // Continuous AMRAP until clock expires
            }
            let firstNonZero = workout.blocks.first(where: { $0.repeatTimes > 0 })?.repeatTimes
            return firstNonZero ?? workout.blocks.first?.repeatTimes
        }
    }

    var canAutoStop: Bool {
        phase == .finished
    }

    var currentExerciseLabel: String {
        guard phase != .finished, let ex = currentExercise else {
            return workout.blocks.last?.exercises.last?.displayLabel
                ?? workout.blocks.last?.exercises.last?.movement?.name
                ?? "—"
        }
        return ex.displayLabel ?? ex.movement?.name ?? "Exercise"
    }

    var snapshot: SessionSnapshot {
        SessionSnapshot(
            phase: phase,
            roundsCompleted: roundsCompleted,
            blockIndex: blockIndex,
            exerciseIndex: exerciseIndex,
            repsInCurrentExercise: repsCompletedInCurrentExercise,
            currentExerciseLabel: currentExerciseLabel,
            wallClock: wallClock,
            activeElapsed: resultActiveTime,
            isPaused: phase == .paused,
            isFinished: phase == .finished
        )
    }

    // MARK: - Actions
    mutating func start() {
        guard phase != .finished else { return }
        phase = .running
    }

    mutating func pause() {
        guard phase == .running || phase == .resting else { return }
        phase = .paused
    }

    mutating func resume() {
        guard phase == .paused else { return }
        phase = (restDeadline != nil) ? .resting : .running
    }

    mutating func advanceRep() -> TimerEvent {
        guard phase == .running, restDeadline == nil else { return .none }
        guard let ex = currentExercise, let block = currentBlock else { return .none }

        repsCompletedInCurrentExercise += 1
        totalRepsCompleted += 1

        let quota = ex.effectiveReps
        if repsCompletedInCurrentExercise < quota {
            return .none
        }

        // Exercise completed
        repsCompletedInCurrentExercise = 0
        if exerciseIndex < block.exercises.count - 1 {
            exerciseIndex += 1
            return .none
        }

        // Block completed
        return completeBlock()
    }

    private mutating func completeBlock() -> TimerEvent {
        guard let block = currentBlock else { return .none }
        roundsCompleted += 1
        exerciseIndex = 0
        repsCompletedInCurrentExercise = 0

        // Check if finite target reached
        if let target = playTarget {
            if roundsCompleted >= target {
                phase = .finished
                return .finished(.goalReached)
            }
        } else {
            // For-time AMRAP (repeatTimes == 0)
            if isClockExpired {
                phase = .finished
                return .finished(.clockExpired)
            }
        }

        // Handle inter-block rest if defined
        let restSecs = block.restAfterBlock
        if let rest = restSecs, rest > 0 {
            restDeadline = wallClock + Double(rest)
            phase = .resting
        }

        // Advance to next block or loop block
        if block.repeatTimes > 0 {
            // Repeating block: if repeatTimes not exhausted, stay on block
            let currentBlockPlays = roundsCompleted
            if currentBlockPlays < block.repeatTimes {
                // Stay on current block
                return .blockCompleted
            }
        }

        if blockIndex < workout.blocks.count - 1 {
            blockIndex += 1
        } else {
            // Loop back to first block for AMRAP
            blockIndex = 0
        }

        return .blockCompleted
    }

    mutating func startRest(duration: TimeInterval? = nil) -> TimerEvent {
        guard phase == .running else { return .none }
        let rest = duration ?? Double(currentBlock?.restAfterBlock ?? 0)
        guard rest > 0 else { return .none }
        restDeadline = wallClock + rest
        phase = .resting
        return .none
    }

    mutating func endRest() -> TimerEvent {
        guard phase == .resting else { return .none }
        restDeadline = nil
        phase = .running
        return .none
    }

    mutating func finish() -> TimerEvent {
        phase = .finished
        return .finished(.manual)
    }

    mutating func advanceTime(_ dt: TimeInterval, active: Bool) {
        guard phase != .idle && phase != .finished else { return }

        if active && phase == .running {
            wallClock += dt
            if workout.mode == .forTime, isClockExpired {
                phase = .finished
            }
        } else if active && phase == .resting {
            wallClock += dt
            if let deadline = restDeadline, wallClock >= deadline {
                restDeadline = nil
                phase = .running
            }
        } else {
            // Paused or non-active time
            pausedAccumulated += dt
            wallClock += dt
        }
    }

    mutating func reset() {
        phase = .idle
        roundsCompleted = 0
        blockIndex = 0
        exerciseIndex = 0
        repsCompletedInCurrentExercise = 0
        totalRepsCompleted = 0
        wallClock = 0
        pausedAccumulated = 0
        restDeadline = nil
    }
}