import XCTest
import SwiftData
@testable import WODCounter

final class WODSimulatorTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        container = Container.inMemory()
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Helpers (order-robust: SwiftData to-many ordering is not guaranteed)

    @MainActor
    private func id(in sim: WODSimulator, labeled prefix: String) -> UUID? {
        sim.liveTasks.first { $0.displayLabel.hasPrefix(prefix) }?.id
    }

    // MARK: - Cindy (AMRAP For-Time, looping round)

    @MainActor
    func testCindyAMRAPRegeneratesRoundsUntilClockExpiry() {
        let cindy = BenchmarkSeed.cindy(in: context)
        var sim = WODSimulator(workout: cindy)

        XCTAssertEqual(sim.phase, .idle)
        XCTAssertEqual(sim.totalRounds, 1)
        XCTAssertTrue(sim.hasLoopingRounds)
        XCTAssertEqual(sim.totalRemaining, 30)
        XCTAssertEqual(sim.snapshot.tasks.count, 3)

        sim.start()
        XCTAssertEqual(sim.phase, .running)

        // Free-form order: finish squats, then push-ups, then pull-ups.
        let squats = id(in: sim, labeled: "15 Air Squats")!
        let pushUps = id(in: sim, labeled: "10 Push-ups")!
        let pullUps = id(in: sim, labeled: "5 Pull-ups")!

        XCTAssertEqual(sim.completeReps(taskID: squats, count: 15), .none)
        XCTAssertEqual(sim.completeReps(taskID: pushUps, count: 10), .none)
        XCTAssertEqual(sim.totalRemaining, 5)

        // Completing the final task of the round regenerates a fresh wave.
        XCTAssertEqual(sim.completeReps(taskID: pullUps, count: 5), .blockCompleted)
        XCTAssertEqual(sim.roundsCompleted, 1)
        XCTAssertEqual(sim.totalRemaining, 30)
        XCTAssertEqual(sim.phase, .running)

        // Second round (another 30 reps, any order).
        for _ in 1...30 {
            let task = sim.liveTasks.first { !$0.isComplete }!
            _ = sim.completeReps(taskID: task.id, count: 1)
        }
        XCTAssertEqual(sim.roundsCompleted, 2)
        XCTAssertEqual(sim.phase, .running)
        XCTAssertEqual(sim.totalRemaining, 30)

        // Advance active time past the 20-minute cap (1200 seconds).
        sim.advanceTime(1201, active: true)
        XCTAssertTrue(sim.isClockExpired)
        XCTAssertEqual(sim.phase, .finished)
        XCTAssertEqual(sim.snapshot.isFinished, true)
    }

    // MARK: - Murph (Single-Block Top-Time Auto-Stop)

    @MainActor
    func testMurphTopTimeAutoStopsAfter600FreeFormReps() {
        let murph = BenchmarkSeed.murph(in: context)
        var sim = WODSimulator(workout: murph)

        XCTAssertEqual(sim.totalRounds, 1)
        XCTAssertEqual(sim.totalRemaining, 600)
        XCTAssertFalse(sim.hasLoopingRounds)

        sim.start()

        // Complete 300 air squats first (free-form, out of order).
        let squats = id(in: sim, labeled: "300 Air Squats")!
        _ = sim.completeReps(taskID: squats, count: 300)
        XCTAssertEqual(sim.totalRemaining, 300)
        XCTAssertEqual(sim.phase, .running)

        // Deplete everything one rep at a time.
        var event: TimerEvent = .none
        for _ in 1...300 {
            let task = sim.liveTasks.first { !$0.isComplete }!
            event = sim.completeReps(taskID: task.id, count: 1)
        }
        XCTAssertEqual(event, .finished(.goalReached))
        XCTAssertEqual(sim.roundsCompleted, 1)
        XCTAssertEqual(sim.phase, .finished)
        XCTAssertTrue(sim.canAutoStop)
        XCTAssertEqual(sim.totalRepsCompleted, 600)
    }

    // MARK: - Fran (Multi-Block Descending Scheme: 21-15-9)

    @MainActor
    func testFran3BlocksDescendingFreeFormAutoStops() {
        let fran = BenchmarkSeed.fran(in: context)
        var sim = WODSimulator(workout: fran)

        XCTAssertEqual(fran.orderedBlocks.count, 3)
        XCTAssertEqual(sim.totalRounds, 3)
        XCTAssertEqual(sim.totalRemaining, 90)

        sim.start()

        let t21 = id(in: sim, labeled: "21 Thrusters")!
        let p21 = id(in: sim, labeled: "21 Pull-ups")!
        let t15 = id(in: sim, labeled: "15 Thrusters")!
        let p15 = id(in: sim, labeled: "15 Pull-ups")!
        let t9 = id(in: sim, labeled: "9 Thrusters")!
        let p9 = id(in: sim, labeled: "9 Pull-ups")!

        // Scramble the completion order across blocks.
        _ = sim.completeReps(taskID: t21, count: 21)
        XCTAssertEqual(sim.completeReps(taskID: p21, count: 21), .blockCompleted)
        XCTAssertEqual(sim.roundsCompleted, 1)
        XCTAssertEqual(sim.phase, .running)

        _ = sim.completeReps(taskID: t15, count: 15)
        _ = sim.completeReps(taskID: p15, count: 15)
        XCTAssertEqual(sim.roundsCompleted, 2)

        XCTAssertEqual(sim.completeReps(taskID: t9, count: 9), .none)
        let finalEvent = sim.completeReps(taskID: p9, count: 9)
        XCTAssertEqual(finalEvent, .finished(.goalReached))
        XCTAssertEqual(sim.roundsCompleted, 3)
        XCTAssertEqual(sim.phase, .finished)
        XCTAssertEqual(sim.totalRepsCompleted, 90)
    }

    // MARK: - Multi-Block Explicit Ordering (Fran/Diane)

    @MainActor
    func testMultiBlockWorkoutsFollowExplicitOrder() {
        let cases: [(Workout, [String])] = [
            (BenchmarkSeed.fran(in: context), [
                "21 Thrusters (95 lb)", "21 Pull-ups",
                "15 Thrusters (95 lb)", "15 Pull-ups",
                "9 Thrusters (95 lb)", "9 Pull-ups",
            ]),
            (BenchmarkSeed.diane(in: context), [
                "21 Deadlifts (225 lb)", "21 Handstand Push-ups",
                "15 Deadlifts (225 lb)", "15 Handstand Push-ups",
                "9 Deadlifts (225 lb)", "9 Handstand Push-ups",
            ]),
        ]

        for (workout, expectedLabels) in cases {
            var sim = WODSimulator(workout: workout)
            XCTAssertEqual(sim.liveTasks.map(\.displayLabel), expectedLabels,
                           "\(workout.name) tasks should follow block/exercise sortOrder")
            XCTAssertEqual(sim.totalRounds, 3)

            sim.start()
            var completionOrder: [Int] = []
            for task in sim.liveTasks {
                let event = sim.completeReps(taskID: task.id, count: task.remaining)
                switch event {
                case .blockCompleted:
                    completionOrder.append(sim.roundsCompleted)
                case .finished:
                    completionOrder.append(sim.roundsCompleted)
                case .none:
                    break
                }
            }

            XCTAssertEqual(completionOrder, [1, 2, 3],
                           "\(workout.name) blocks should complete 21 -> 15 -> 9")
        }
    }

    // MARK: - DT (Single-Block Repeat: 5 Rounds, per-round sets)

    @MainActor
    func testDT5RoundsWithPerRoundSetsAutoStops() {
        let dt = BenchmarkSeed.dt(in: context)
        var sim = WODSimulator(workout: dt)

        XCTAssertEqual(sim.totalRounds, 5)
        XCTAssertEqual(sim.snapshot.tasks.count, 15) // 5 rounds x 3 sets
        XCTAssertEqual(sim.totalRemaining, 135)

        sim.start()

        var event: TimerEvent = .none
        for _ in 1...134 {
            let task = sim.liveTasks.first { !$0.isComplete }!
            _ = sim.completeReps(taskID: task.id, count: 1)
        }
        XCTAssertEqual(sim.phase, .running)
        XCTAssertEqual(sim.roundsCompleted, 4)

        let task = sim.liveTasks.first { !$0.isComplete }!
        event = sim.completeReps(taskID: task.id, count: task.remaining)
        XCTAssertEqual(event, .finished(.goalReached))
        XCTAssertEqual(sim.roundsCompleted, 5)
        XCTAssertEqual(sim.phase, .finished)
    }

    // MARK: - Helen (Distance-Only Sends Have Quota 1)

    @MainActor
    func testDistanceOnlyExerciseHasQuotaOne() {
        let helen = BenchmarkSeed.helen(in: context)
        var sim = WODSimulator(workout: helen)

        XCTAssertEqual(sim.totalRounds, 3)
        XCTAssertEqual(sim.totalRemaining, 102) // 3 x (1 + 21 + 12)

        sim.start()

        let run = sim.liveTasks.first { $0.movementName == "Run" }!
        XCTAssertEqual(run.quota, 1)
        XCTAssertEqual(sim.completeReps(taskID: run.id, count: 1), .none)
        XCTAssertEqual(sim.totalRemaining, 101)
    }

    // MARK: - Over-Logging Is Capped

    @MainActor
    func testOverLoggingIsCappedAtRemainingQuota() {
        let murph = BenchmarkSeed.murph(in: context)
        var sim = WODSimulator(workout: murph)

        sim.start()
        let pullUps = id(in: sim, labeled: "100 Pull-ups")!
        let before = sim.totalRepsCompleted

        // Logging far more than remains only completes the task.
        _ = sim.completeReps(taskID: pullUps, count: 9999)
        XCTAssertEqual(sim.totalRepsCompleted, before + 100)
        XCTAssertEqual(sim.totalRemaining, 500)
    }

    // MARK: - Logging While Idle Is Ignored

    @MainActor
    func testLoggingWhileIdleIsIgnored() {
        let fran = BenchmarkSeed.fran(in: context)
        var sim = WODSimulator(workout: fran)

        let ev = sim.completeReps(taskID: sim.liveTasks[0].id, count: 5)
        XCTAssertEqual(ev, .none)
        XCTAssertEqual(sim.totalRepsCompleted, 0)
        XCTAssertEqual(sim.totalRemaining, 90)
    }

    // MARK: - Pause & Active Time Calculation

    @MainActor
    func testPauseFreezesActiveTimeAndAccumulatesPausedTime() {
        let cindy = BenchmarkSeed.cindy(in: context)
        var sim = WODSimulator(workout: cindy)

        sim.start()
        sim.advanceTime(20, active: true)
        XCTAssertEqual(sim.resultActiveTime, 20)
        XCTAssertEqual(sim.wallClock, 20)

        sim.pause()
        XCTAssertEqual(sim.phase, .paused)
        sim.advanceTime(15, active: false)

        XCTAssertEqual(sim.resultActiveTime, 20)
        XCTAssertEqual(sim.wallClock, 35)

        sim.resume()
        XCTAssertEqual(sim.phase, .running)
        sim.advanceTime(10, active: true)

        XCTAssertEqual(sim.resultActiveTime, 30)
        XCTAssertEqual(sim.wallClock, 45)
    }

    // MARK: - Manual Finish

    @MainActor
    func testManualFinishEndsWorkout() {
        let cindy = BenchmarkSeed.cindy(in: context)
        var sim = WODSimulator(workout: cindy)

        sim.start()
        let task = sim.liveTasks[0]
        _ = sim.completeReps(taskID: task.id, count: 5)

        let event = sim.finish()
        XCTAssertEqual(event, .finished(.manual))
        XCTAssertEqual(sim.phase, .finished)
        XCTAssertEqual(sim.snapshot.isFinished, true)
    }

    // MARK: - Rest Semantics (WTB-005)

    /// Builds a top-time workout with one exercise per block. Each block's
    /// single task has quota 10, so completing it completes the round.
    @MainActor
    private func makeBlocksWorkout(_ specs: [(repeatTimes: Int, rest: Int?)]) -> Workout {
        let workout = Workout(
            name: "Rest Test \(UUID().uuidString)",
            mode: .topTime,
            isBuiltin: false
        )
        let movement = Movement(name: "Squat-\(UUID().uuidString)")
        context.insert(movement)
        workout.blocks = specs.enumerated().map { index, spec in
            let block = RoundBlock(
                repeatTimes: spec.repeatTimes,
                restAfterBlock: spec.rest,
                sortOrder: index
            )
            let exercise = Exercise(
                movement: movement,
                reps: 10,
                displayLabel: "10 Squats B\(index)",
                sortOrder: 0
            )
            context.insert(exercise)
            block.exercises = [exercise]
            return block
        }
        context.insert(workout)
        return workout
    }

    @MainActor
    @discardableResult
    private func completeFirstIncompleteRound(in sim: inout WODSimulator) -> TimerEvent {
        let task = sim.liveTasks.first { !$0.isComplete }!
        return sim.completeReps(taskID: task.id, count: task.remaining)
    }

    @MainActor
    func testRestOnFirstBlockFiresAfterThatBlock() {
        let workout = makeBlocksWorkout([(1, 60), (1, nil)])
        var sim = WODSimulator(workout: workout)
        sim.start()

        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .blockCompleted)
        XCTAssertEqual(sim.phase, .resting)
        XCTAssertEqual(sim.restDeadline, 60)

        // Reps are ignored while resting.
        let next = sim.liveTasks.first { !$0.isComplete }!
        XCTAssertEqual(sim.completeReps(taskID: next.id, count: 10), .none)

        _ = sim.endRest()
        XCTAssertEqual(sim.phase, .running)
        XCTAssertEqual(sim.completeReps(taskID: next.id, count: 10), .finished(.goalReached))
        XCTAssertEqual(sim.phase, .finished)
    }

    @MainActor
    func testRestOnSecondBlockDoesNotFireAfterFirstBlock() {
        let workout = makeBlocksWorkout([(1, nil), (1, 60)])
        var sim = WODSimulator(workout: workout)
        sim.start()

        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .blockCompleted)
        XCTAssertEqual(sim.phase, .running)
        XCTAssertNil(sim.restDeadline)

        // The final block's rest never fires because the workout finishes.
        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .finished(.goalReached))
        XCTAssertEqual(sim.phase, .finished)
        XCTAssertNil(sim.restDeadline)
    }

    @MainActor
    func testRestOnMiddleBlockFiresAfterThatBlock() {
        let workout = makeBlocksWorkout([(1, nil), (1, 45), (1, nil)])
        var sim = WODSimulator(workout: workout)
        sim.start()

        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .blockCompleted)
        XCTAssertEqual(sim.phase, .running)

        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .blockCompleted)
        XCTAssertEqual(sim.phase, .resting)
        XCTAssertEqual(sim.restDeadline, 45)

        _ = sim.endRest()
        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .finished(.goalReached))
        XCTAssertNil(sim.restDeadline)
    }

    @MainActor
    func testRepeatedBlockRestsBetweenRoundsButNotAfterFinalRound() {
        let workout = makeBlocksWorkout([(3, 180)])
        var sim = WODSimulator(workout: workout)
        sim.start()

        for _ in 1...2 {
            XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .blockCompleted)
            XCTAssertEqual(sim.phase, .resting)
            XCTAssertEqual(sim.restDeadline, sim.resultActiveTime + 180)
            _ = sim.endRest()
        }

        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .finished(.goalReached))
        XCTAssertEqual(sim.phase, .finished)
        XCTAssertNil(sim.restDeadline)
    }

    @MainActor
    func testPauseDuringRestPreservesRemainingRest() {
        let workout = makeBlocksWorkout([(2, 60)])
        var sim = WODSimulator(workout: workout)
        sim.start()

        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .blockCompleted)
        XCTAssertEqual(sim.phase, .resting)

        sim.advanceTime(20, active: true)
        XCTAssertEqual(sim.phase, .resting)
        XCTAssertEqual(sim.resultActiveTime, 20)

        sim.pause()
        sim.advanceTime(30, active: false)
        XCTAssertEqual(sim.phase, .paused)
        XCTAssertEqual(sim.resultActiveTime, 20)
        XCTAssertEqual(sim.restDeadline, 60)

        sim.resume()
        XCTAssertEqual(sim.phase, .resting)
        sim.advanceTime(39, active: true)
        XCTAssertEqual(sim.phase, .resting)
        XCTAssertEqual(sim.resultActiveTime, 59)

        sim.advanceTime(1, active: true)
        XCTAssertEqual(sim.phase, .running)
        XCTAssertNil(sim.restDeadline)
    }

    @MainActor
    func testEndRestSkipsRemainingRestAndResumesRunning() {
        let workout = makeBlocksWorkout([(2, 60)])
        var sim = WODSimulator(workout: workout)
        sim.start()

        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .blockCompleted)
        XCTAssertEqual(sim.phase, .resting)

        sim.pause()
        XCTAssertEqual(sim.phase, .paused)
        _ = sim.endRest()
        XCTAssertEqual(sim.phase, .running)
        XCTAssertNil(sim.restDeadline)
    }

    @MainActor
    func testManualStartRestUsesCompletedBlockRest() {
        let workout = makeBlocksWorkout([(1, 45), (1, nil)])
        var sim = WODSimulator(workout: workout)
        sim.start()

        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .blockCompleted)
        _ = sim.endRest()

        _ = sim.startRest()
        XCTAssertEqual(sim.phase, .resting)
        XCTAssertEqual(sim.restDeadline, sim.resultActiveTime + 45)
    }

    @MainActor
    func testRestRemainingCountsDownAndIgnoresPausedTime() {
        let workout = makeBlocksWorkout([(2, 60)])
        var sim = WODSimulator(workout: workout)
        sim.start()

        XCTAssertNil(sim.snapshot.restRemaining)

        XCTAssertEqual(completeFirstIncompleteRound(in: &sim), .blockCompleted)
        XCTAssertEqual(sim.snapshot.restRemaining, 60)

        sim.advanceTime(20, active: true)
        XCTAssertEqual(sim.snapshot.restRemaining, 40)

        // Paused time does not consume rest.
        sim.pause()
        sim.advanceTime(30, active: false)
        XCTAssertEqual(sim.snapshot.restRemaining, 40)

        sim.resume()
        sim.advanceTime(40, active: true)
        XCTAssertEqual(sim.phase, .running)
        XCTAssertNil(sim.snapshot.restRemaining)
    }

    @MainActor
    func testRemoveRepsReversesPartialAdditionOnly() {
        let workout = makeBlocksWorkout([(2, 10)])
        var sim = WODSimulator(workout: workout)
        sim.start()

        let task = sim.liveTasks.first { !$0.isComplete }!

        XCTAssertEqual(sim.completeReps(taskID: task.id, count: 5), .none)
        XCTAssertEqual(sim.totalRepsCompleted, 5)
        XCTAssertEqual(sim.totalRemaining, 15)

        XCTAssertEqual(sim.removeReps(taskID: task.id, count: 5), 5)
        XCTAssertEqual(sim.totalRepsCompleted, 0)
        XCTAssertEqual(sim.totalRemaining, 20)
    }

    // MARK: - Idle Snapshot

    @MainActor
    func testIdleSnapshotHasNoTasks() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let sim = WODSimulator(workout: cindy)
        let snap = sim.snapshot

        XCTAssertEqual(snap.phase, .idle)
        XCTAssertEqual(snap.totalRounds, 1)
        XCTAssertEqual(snap.roundsCompleted, 0)
        XCTAssertEqual(snap.totalRemaining, 30)
        XCTAssertEqual(snap.totalRepsCompleted, 0)
        XCTAssertEqual(snap.isPaused, false)
        XCTAssertEqual(snap.isFinished, false)
    }
}