import Foundation

/// Free-form workout engine: the session is modeled as a list of pending
/// "tasks" (each exercise set in the workout). The athlete may complete reps
/// against any task in any order; the workout ends when every finite task is
/// depleted (top-time), or when the For-Time clock cap expires (AMRAP rounds
/// regenerate forever).
struct WODSimulator {
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
        /// One-based round number this task belongs to. Used only for grouping
        /// the live task list; looping rounds keep the same number.
        let roundNumber: Int
        let movementName: String
        let displayLabel: String
        let quota: Int
        private(set) var completed: Int = 0

        var remaining: Int { max(0, quota - completed) }
        var isComplete: Bool { remaining == 0 }

        mutating func addReps(_ count: Int) {
            completed = min(quota, completed + max(0, count))
        }

        mutating func removeReps(_ count: Int) {
            completed = max(0, completed - max(0, count))
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
            tasks = WODSimulator.freshTasks(
                for: workout.orderedBlocks[blockIndex],
                blockIndex: blockIndex,
                roundNumber: number
            )
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
    /// Active elapsed time at which the current rest ends. Measured against
    /// `resultActiveTime`, so paused time never consumes rest.
    private(set) var restDeadline: TimeInterval? = nil
    /// Block of the most recently completed round, used to resolve manual rest
    /// and to document which block owns the automatic rest.
    private(set) var lastCompletedBlockIndex: Int? = nil

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

    /// Seconds left in the current rest, or `nil` when no rest is pending.
    var restRemaining: TimeInterval? {
        guard let restDeadline else { return nil }
        return max(0, restDeadline - resultActiveTime)
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
            restRemaining: restRemaining,
            isPaused: phase == .paused,
            isFinished: phase == .finished
        )
    }

    // MARK: - Round Building

    private static func buildRounds(for workout: Workout) -> [Round] {
        var result: [Round] = []
        var number = 0
        for (blockIndex, block) in workout.orderedBlocks.enumerated() {
            let repeats = max(0, block.repeatTimes)
            if repeats == 0 {
                number += 1
                result.append(Round(
                    id: UUID(),
                    number: number,
                    blockIndex: blockIndex,
                    isLooping: true,
                    tasks: freshTasks(for: block, blockIndex: blockIndex, roundNumber: number)
                ))
            } else {
                for _ in 0..<repeats {
                    number += 1
                    result.append(Round(
                        id: UUID(),
                        number: number,
                        blockIndex: blockIndex,
                        isLooping: false,
                        tasks: freshTasks(for: block, blockIndex: blockIndex, roundNumber: number)
                    ))
                }
            }
        }
        return result
    }

    fileprivate static func freshTasks(for block: RoundBlock, blockIndex: Int, roundNumber: Int) -> [Task] {
        block.orderedExercises.map { exercise in
            Task(
                id: UUID(),
                blockIndex: blockIndex,
                roundNumber: roundNumber,
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

    /// Reverses a previous partial rep addition. Only incomplete tasks can be
    /// reduced so a completed round is never partially un-completed.
    /// Returns the number of reps actually removed.
    @discardableResult
    mutating func removeReps(taskID: UUID, count: Int) -> Int {
        guard phase == .running, restDeadline == nil else { return 0 }
        guard let (roundIndex, taskIndex) = locate(taskID) else { return 0 }
        guard !rounds[roundIndex].tasks[taskIndex].isComplete else { return 0 }
        let removed = min(max(0, count), rounds[roundIndex].tasks[taskIndex].completed)
        guard removed > 0 else { return 0 }
        rounds[roundIndex].tasks[taskIndex].removeReps(removed)
        totalRepsCompleted = max(0, totalRepsCompleted - removed)
        return removed
    }

    /// Starts a rest. An explicit `duration` always wins; otherwise the rest
    /// configured on the most recently completed round's block is used (the
    /// same block automatic rest would target). Before any round completes,
    /// the first incomplete round's block is the fallback target.
    mutating func startRest(duration: TimeInterval? = nil) -> TimerEvent {
        guard phase == .running else { return .none }
        let rest = duration ?? restDuration(forBlockAt: manualRestBlockIndex)
        guard let rest, rest > 0 else { return .none }
        restDeadline = resultActiveTime + rest
        phase = .resting
        return .none
    }

    /// Ends any rest, whether currently resting or paused mid-rest, and resumes
    /// the running phase with no deadline.
    mutating func endRest() -> TimerEvent {
        guard restDeadline != nil, phase == .resting || phase == .paused else { return .none }
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
            if let deadline = restDeadline, resultActiveTime >= deadline {
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
        lastCompletedBlockIndex = nil
        rounds = Self.buildRounds(for: workout)
    }

    // MARK: - Internal

    /// Block targeted by manual rest when no round has completed yet.
    private var manualRestBlockIndex: Int? {
        if let lastCompletedBlockIndex { return lastCompletedBlockIndex }
        return rounds.first(where: { !$0.isComplete })?.blockIndex
    }

    /// `restAfterBlock` semantics: rest after each completed play of the block.
    /// With `repeatTimes > 1` that is rest between rounds, not after the final
    /// repetition (the workout is already finished by then).
    private func restDuration(forBlockAt index: Int?) -> TimeInterval? {
        guard let index else { return nil }
        let blocks = workout.orderedBlocks
        guard blocks.indices.contains(index),
              let rest = blocks[index].restAfterBlock,
              rest > 0 else { return nil }
        return Double(rest)
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
        var completedBlockIndices: [Int] = []

        for index in rounds.indices where rounds[index].isComplete {
            if rounds[index].isLooping {
                completedBlockIndices.append(rounds[index].blockIndex)
                roundsCompleted += 1
                rounds[index].regenerateTasks(with: workout)
                result = .blockCompleted
            } else if !rounds[index].completionRecorded {
                completedBlockIndices.append(rounds[index].blockIndex)
                roundsCompleted += 1
                rounds[index].completionRecorded = true
                result = .blockCompleted
            }
        }

        if isWorkoutComplete {
            phase = .finished
            return .finished(.goalReached)
        }

        // Rest belongs to the block that just completed, not to the next block.
        // When several rounds complete in one reconcile, use the furthest one.
        if let blockIndex = completedBlockIndices.last {
            lastCompletedBlockIndex = blockIndex
            if let rest = restDuration(forBlockAt: blockIndex) {
                restDeadline = resultActiveTime + rest
                phase = .resting
            }
        }

        return result
    }
}