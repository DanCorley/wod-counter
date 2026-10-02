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
            // `workout` is a live model object; its blocks can be edited or
            // deleted while a session holds this round, so never subscript blind.
            let blocks = workout.orderedBlocks
            guard blocks.indices.contains(blockIndex) else { return }
            tasks = WODSimulator.freshTasks(for: blocks[blockIndex], blockIndex: blockIndex)
        }
    }

    let workout: Workout

    /// Total reps prescribed by the workout as first built. Meaningful for
    /// finite (top-time) workouts; AMRAP rounds regenerate, so for those this is
    /// only the first wave and completion is decided by the clock instead.
    let initialQuota: Int

    // MARK: - Progress State
    private var rounds: [Round]
    private(set) var phase: Phase = .idle
    private(set) var roundsCompleted: Int = 0
    private(set) var totalRepsCompleted: Int = 0
    /// Total time since the session started, including paused stretches.
    private(set) var wallClock: TimeInterval = 0
    /// Time the athlete was actually working: wall clock minus paused stretches.
    /// Both values are supplied by the owning service from a real clock — the
    /// simulator never accumulates time itself, so a missed or late tick cannot
    /// cost the session any elapsed time.
    private(set) var activeElapsed: TimeInterval = 0
    /// Rest expiry expressed in *active* time, so pausing cannot consume a rest.
    private(set) var restEndsAtActive: TimeInterval? = nil

    var pausedAccumulated: TimeInterval { max(0, wallClock - activeElapsed) }

    /// Seconds left in the current rest, if resting.
    var restRemaining: TimeInterval? {
        guard let endsAt = restEndsAtActive else { return nil }
        return max(0, endsAt - activeElapsed)
    }

    init(workout: Workout) {
        self.workout = workout
        let built = Self.buildRounds(for: workout)
        self.rounds = built
        self.initialQuota = built.reduce(0) { $0 + $1.tasks.reduce(0) { $0 + $1.quota } }
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
        max(0, activeElapsed)
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
        block.orderedExercises.map { exercise in
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
        phase = (restEndsAtActive != nil) ? .resting : .running
    }

    /// Logs completed reps against a specific pending task. The athlete may
    /// target any task (any exercise, any round) — reps are capped at the
    /// task's remaining quota.
    @discardableResult
    mutating func completeReps(taskID: UUID, count: Int) -> TimerEvent {
        guard phase == .running, restEndsAtActive == nil else { return .none }
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
        restEndsAtActive = activeElapsed + rest
        phase = .resting
        return .none
    }

    mutating func endRest() -> TimerEvent {
        guard phase == .resting else { return .none }
        restEndsAtActive = nil
        phase = .running
        return .none
    }

    mutating func finish() -> TimerEvent {
        phase = .finished
        return .finished(.manual)
    }

    /// Sets the session's elapsed time from the owning service's real clock and
    /// re-evaluates anything time-dependent. Idempotent: calling it twice with
    /// the same values changes nothing, so refresh frequency is free to vary.
    mutating func updateTime(active: TimeInterval, wall: TimeInterval) {
        guard phase != .idle && phase != .finished else { return }

        activeElapsed = max(activeElapsed, active)
        wallClock = max(wallClock, wall)

        // Rest expires on active time, so a pause mid-rest preserves it.
        if phase == .resting, let endsAt = restEndsAtActive, activeElapsed >= endsAt {
            restEndsAtActive = nil
            phase = .running
        }

        // The cap applies in every live phase — a rest must not outrun it.
        if workout.mode == .forTime, isClockExpired {
            restEndsAtActive = nil
            phase = .finished
        }
    }

    mutating func reset() {
        phase = .idle
        roundsCompleted = 0
        totalRepsCompleted = 0
        wallClock = 0
        activeElapsed = 0
        restEndsAtActive = nil
        rounds = Self.buildRounds(for: workout)
    }

    // MARK: - Internal

    private var currentBlock: RoundBlock? {
        guard let firstIncomplete = rounds.first(where: { !$0.isComplete }) else { return nil }
        let blocks = workout.orderedBlocks
        return blocks.indices.contains(firstIncomplete.blockIndex)
            ? blocks[firstIncomplete.blockIndex]
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
            restEndsAtActive = activeElapsed + Double(rest)
            phase = .resting
        }

        return result
    }
}