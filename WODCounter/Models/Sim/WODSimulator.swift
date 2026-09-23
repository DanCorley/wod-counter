import Foundation

/// Free-form workout engine: the session is modeled as a list of pending
/// "tasks" (each exercise set in the workout). The athlete may complete reps
/// against any task in any order; the workout ends when every finite task is
/// depleted (top-time), or when the For-Time clock cap expires (AMRAP rounds
/// regenerate forever).
struct WODSimulator: Sendable {
    enum Phase: String, Sendable, Equatable {
        case idle
        case running
        case paused
        case resting
        case finished
    }

    /// A single pending set of reps (one exercise at one round).
    struct Task: Identifiable, Sendable, Equatable {
        let id: UUID
        let blockIndex: Int
        let movementName: String
        let displayLabel: String
        let quota: Int
        private(set) var completed: Int = 0

        var remaining: Int { max(0, quota - completed) }
        var isComplete: Bool { remaining == 0 }

        mutating func addReps(_ count: Int) {
            completed = min(quota, completed + max(0, count))
        }
    }

    /// One round's worth of tasks. Finite rounds complete once; looping rounds
    /// (AMRAP, repeatTimes == 0) regenerate a fresh wave whenever completed.
    struct Round: Identifiable, Sendable, Equatable {
        let id: UUID
        let number: Int
        let blockIndex: Int
        let isLooping: Bool
        var tasks: [Task]
        var completionRecorded: Bool = false

        var isComplete: Bool { !tasks.isEmpty && tasks.allSatisfy(\.isComplete) }

        mutating func regenerateTasks(with workout: Workout) {
            tasks = WODSimulator.freshTasks(for: workout.blocks[blockIndex], blockIndex: blockIndex)
        }
    }

    let workout: Workout

    // MARK: - Progress State
    private var rounds: [Round]
    private(set) var phase: Phase = .idle
    private(set) var roundsCompleted: Int = 0
    private(set) var totalRepsCompleted: Int = 0
    private(set) var wallClock: TimeInterval = 0
    private(set) var pausedAccumulated: TimeInterval = 0
    private(set) var restDeadline: TimeInterval? = nil

    init(workout: Workout) {
        self.workout = workout
        self.rounds = Self.buildRounds(for: workout)
    }

    // MARK: - Derived Properties

    var liveTasks: [Task] { rounds.flatMap(\.tasks) }

    var totalRemaining: Int { liveTasks.reduce(0) { $0 + $1.remaining } }

    var totalRounds: Int { rounds.count }

    var hasLoopingRounds: Bool { rounds.contains(where: \.isLooping) }

    /// True when every finite task is depleted AND no AMRAP round remains open.
    var isWorkoutComplete: Bool {
        rounds.allSatisfy(\.isComplete) && !hasLoopingRounds
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

    var canAutoStop: Bool { phase == .finished }

    var snapshot: SessionSnapshot {
        SessionSnapshot(
            phase: phase,
            roundsCompleted: roundsCompleted,
            totalRounds: totalRounds,
            hasLoopingRounds: hasLoopingRounds,
            tasks: liveTasks,
            totalRepsCompleted: totalRepsCompleted,
            totalRemaining: totalRemaining,
            wallClock: wallClock,
            activeElapsed: resultActiveTime,
            isPaused: phase == .paused,
            isFinished: phase == .finished
        )
    }

    // MARK: - Round Building

    private static func buildRounds(for workout: Workout) -> [Round] {
        var result: [Round] = []
        var number = 0
        for (blockIndex, block) in workout.blocks.enumerated() {
            let repeats = max(0, block.repeatTimes)
            if repeats == 0 {
                number += 1
                result.append(Round(
                    id: UUID(),
                    number: number,
                    blockIndex: blockIndex,
                    isLooping: true,
                    tasks: freshTasks(for: block, blockIndex: blockIndex)
                ))
            } else {
                for _ in 0..<repeats {
                    number += 1
                    result.append(Round(
                        id: UUID(),
                        number: number,
                        blockIndex: blockIndex,
                        isLooping: false,
                        tasks: freshTasks(for: block, blockIndex: blockIndex)
                    ))
                }
            }
        }
        return result
    }

    fileprivate static func freshTasks(for block: RoundBlock, blockIndex: Int) -> [Task] {
        block.exercises.map { exercise in
            Task(
                id: UUID(),
                blockIndex: blockIndex,
                movementName: exercise.movement?.name ?? "Exercise",
                displayLabel: exercise.displayLabel ?? exercise.movement?.name ?? "Exercise",
                quota: exercise.effectiveReps
            )
        }
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

    /// Logs completed reps against a specific pending task. The athlete may
    /// target any task (any exercise, any round) — reps are capped at the
    /// task's remaining quota.
    @discardableResult
    mutating func completeReps(taskID: UUID, count: Int) -> TimerEvent {
        guard phase == .running, restDeadline == nil else { return .none }
        guard let (roundIndex, taskIndex) = locate(taskID) else { return .none }
        let added = min(max(0, count), rounds[roundIndex].tasks[taskIndex].remaining)
        guard added > 0 else { return .none }
        rounds[roundIndex].tasks[taskIndex].addReps(added)
        totalRepsCompleted += added
        return reconcileAfterWork()
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
        totalRepsCompleted = 0
        wallClock = 0
        pausedAccumulated = 0
        restDeadline = nil
        rounds = Self.buildRounds(for: workout)
    }

    // MARK: - Internal

    private var currentBlock: RoundBlock? {
        guard let firstIncomplete = rounds.first(where: { !$0.isComplete }) else { return nil }
        return workout.blocks.indices.contains(firstIncomplete.blockIndex)
            ? workout.blocks[firstIncomplete.blockIndex]
            : nil
    }

    private func locate(_ id: UUID) -> (round: Int, task: Int)? {
        for (roundIndex, round) in rounds.enumerated() {
            if let taskIndex = round.tasks.firstIndex(where: { $0.id == id }) {
                return (roundIndex, taskIndex)
            }
        }
        return nil
    }

    private mutating func reconcileAfterWork() -> TimerEvent {
        var result: TimerEvent = .none
        for index in rounds.indices where rounds[index].isComplete {
            if rounds[index].isLooping {
                roundsCompleted += 1
                rounds[index].regenerateTasks(with: workout)
                result = .blockCompleted
            } else if !rounds[index].completionRecorded {
                roundsCompleted += 1
                rounds[index].completionRecorded = true
                result = .blockCompleted
            }
        }

        if isWorkoutComplete {
            phase = .finished
            return .finished(.goalReached)
        }

        // Rest after a completed round, if the block defines one.
        if result != .none, let rest = currentBlock?.restAfterBlock, rest > 0 {
            restDeadline = wallClock + Double(rest)
            phase = .resting
        }

        return result
    }
}