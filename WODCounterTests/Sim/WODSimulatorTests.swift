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

        XCTAssertEqual(fran.blocks.count, 3)
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