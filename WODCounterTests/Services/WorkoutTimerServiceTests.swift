import XCTest
import SwiftData
@testable import WODCounter

/// A clock the test drives by hand, standing in for `Date()`. Lets a test
/// simulate real elapsed time — including a gap where the app was suspended and
/// no tick ran at all — without waiting.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date()) {
        self.current = start
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current += seconds
    }
}

final class WorkoutTimerServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var factory: ServiceFactory!

    @MainActor
    override func setUp() {
        super.setUp()
        container = Container.inMemory()
        context = container.mainContext
        factory = ServiceFactory(context: context)
    }

    override func tearDown() {
        container = nil
        context = nil
        factory = nil
        super.tearDown()
    }

    // MARK: - State & Controls Tests
    @MainActor
    func testStartPauseResumeAndTicking() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = TestClock()
        var finishedRecord: WorkoutRecord?

        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record in
            finishedRecord = record
        }

        XCTAssertEqual(service.snapshot.phase, .idle)
        XCTAssertEqual(service.snapshot.isRunning, false)

        // Start
        service.start()
        XCTAssertEqual(service.snapshot.phase, .running)
        XCTAssertEqual(service.snapshot.isRunning, true)

        // 10 seconds of real time pass
        clock.advance(10)
        service.refresh()
        XCTAssertEqual(service.snapshot.activeElapsed, 10)
        XCTAssertEqual(service.snapshot.wallClock, 10)

        // Pause
        service.pause()
        XCTAssertEqual(service.snapshot.phase, .paused)
        XCTAssertEqual(service.snapshot.isPaused, true)

        // 5 seconds pass while paused
        clock.advance(5)
        service.refresh()
        XCTAssertEqual(service.snapshot.activeElapsed, 10) // Frozen
        XCTAssertEqual(service.snapshot.wallClock, 15)

        // Resume
        service.resume()
        XCTAssertEqual(service.snapshot.phase, .running)

        // 5 more active seconds
        clock.advance(5)
        service.refresh()
        XCTAssertEqual(service.snapshot.activeElapsed, 15)
        XCTAssertEqual(service.snapshot.wallClock, 20)

        // Finish manually
        service.finish()
        XCTAssertEqual(service.snapshot.phase, .finished)
        XCTAssertEqual(service.snapshot.isFinished, true)

        XCTAssertNotNil(finishedRecord)
        XCTAssertEqual(finishedRecord?.roundsCompleted, 0)
        XCTAssertEqual(finishedRecord?.activeTime, 15)
        XCTAssertEqual(finishedRecord?.pausedTime, 5)
        XCTAssertEqual(finishedRecord?.elapsedTime, 20)
        XCTAssertEqual(finishedRecord?.kind, "rounds")
        XCTAssertEqual(finishedRecord?.finishedReason, FinishedReason.manual.rawValue)
    }

    // MARK: - Clock Accuracy

    /// The defect this guards: elapsed time used to be a count of 1-second
    /// ticks, so any stretch where no tick ran — the screen locking, the app
    /// being suspended — was simply lost from the result.
    @MainActor
    func testElapsedSurvivesASuspensionWithNoTicks() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = TestClock()
        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { _ in }

        service.start()

        // Five minutes pass with the app suspended: no refresh happens at all.
        clock.advance(300)
        service.refresh()

        XCTAssertEqual(service.snapshot.activeElapsed, 300,
                       "Elapsed time must come from the clock, not from tick count")
    }

    @MainActor
    func testPausedTimeIsRecordedFromRealElapsedTime() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = TestClock()
        var record: WorkoutRecord?
        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record = $0 }

        service.start()
        clock.advance(60)
        service.pause()
        // A long pause, with no ticks while paused.
        clock.advance(120)
        service.resume()
        clock.advance(30)
        service.finish()

        XCTAssertEqual(record?.activeTime, 90)
        XCTAssertEqual(record?.pausedTime, 120, "Paused time must be real, not always zero")
        XCTAssertEqual(record?.elapsedTime, 210)
    }

    @MainActor
    func testForTimeCapFinishesSessionFromTheClock() {
        let cindy = BenchmarkSeed.cindy(in: context)  // for-time, 20 min
        let clock = TestClock()
        var record: WorkoutRecord?
        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record = $0 }

        service.start()
        clock.advance(1201)
        service.refresh()

        XCTAssertEqual(service.snapshot.phase, .finished)
        XCTAssertEqual(record?.finishedReason, FinishedReason.clockExpired.rawValue)
    }

    // MARK: - Finish Idempotency

    @MainActor
    func testFinishAfterAutoStopDoesNotRecordTwice() {
        let fran = BenchmarkSeed.fran(in: context)
        let clock = TestClock()
        let service = factory.makeTimerService(for: fran, clock: { clock.now })

        service.start()
        clock.advance(120)

        // Log all 90 reps so the session auto-stops on goal reached.
        for _ in 1...90 {
            guard let task = service.snapshot.tasks.first(where: { !$0.isComplete }) else { break }
            _ = service.logReps(taskID: task.id, count: 1)
        }
        XCTAssertEqual(service.snapshot.phase, .finished)

        // A Finish tap racing the auto-stop must not write a second record.
        service.finish()
        service.finish()

        let records = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        XCTAssertEqual(records.count, 1, "Auto-stop plus a Finish tap must save one record")
    }

    // MARK: - ServiceFactory Persistence & PR Verification
    @MainActor
    func testServiceFactoryPersistsRecordWithPRStatus() {
        let fran = BenchmarkSeed.fran(in: context)
        let clock = TestClock()

        let timerService = factory.makeTimerService(for: fran, clock: { clock.now })

        timerService.start()
        clock.advance(180)
        timerService.refresh()

        // Log all 90 reps across the free-form task list (any order).
        for _ in 1...90 {
            guard let task = timerService.snapshot.tasks.first(where: { !$0.isComplete }) else { break }
            _ = timerService.logReps(taskID: task.id, count: 1)
        }

        // Verify that record is automatically inserted into ModelContext
        let descriptor = FetchDescriptor<WorkoutRecord>()
        let records = (try? context.fetch(descriptor)) ?? []

        XCTAssertEqual(records.count, 1)
        guard let savedRecord = records.first else {
            XCTFail("Expected saved record")
            return
        }

        XCTAssertEqual(savedRecord.workout?.name, "Fran")
        XCTAssertEqual(savedRecord.kind, "time")
        XCTAssertEqual(savedRecord.roundsCompleted, 3)
        XCTAssertTrue(savedRecord.isPR) // First attempt is always PR
    }

    // MARK: - PR Eligibility

    /// The defect this guards: a bail-out recorded a time PR, so abandoning
    /// Fran after a few seconds set an unbeatable record.
    @MainActor
    func testAbandonedTopTimeAttemptIsNotAPR() {
        let fran = BenchmarkSeed.fran(in: context)
        let clock = TestClock()
        let service = factory.makeTimerService(for: fran, clock: { clock.now })

        service.start()
        clock.advance(5)
        // Only 2 of 90 reps, then give up.
        if let task = service.snapshot.tasks.first {
            _ = service.logReps(taskID: task.id, count: 2)
        }
        service.finish()

        let records = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(records[0].isPR, "An abandoned attempt must never be a PR")
        XCTAssertEqual(records[0].finishedReason, FinishedReason.manual.rawValue)
        XCTAssertEqual(records[0].repsQuota, 90)
        XCTAssertEqual(records[0].completionFraction, 2.0 / 90.0)
    }

    @MainActor
    func testCompletedTopTimeAttemptIsAPRAndSetsTheBar() {
        let fran = BenchmarkSeed.fran(in: context)
        let clock = TestClock()
        let service = factory.makeTimerService(for: fran, clock: { clock.now })

        service.start()
        clock.advance(200)
        for _ in 1...90 {
            guard let task = service.snapshot.tasks.first(where: { !$0.isComplete }) else { break }
            _ = service.logReps(taskID: task.id, count: 1)
        }

        let records = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isPR)
        XCTAssertTrue(records[0].didCompleteWork)
        XCTAssertEqual(records[0].finishedReason, FinishedReason.goalReached.rawValue)
    }

    /// An earlier partial attempt must not become the time to beat.
    @MainActor
    func testPartialAttemptDoesNotPoisonTheBaseline() {
        let fran = BenchmarkSeed.fran(in: context)
        let now = Date()

        // A bogus 5-second partial, recorded yesterday.
        let partial = WorkoutRecord(
            workout: fran, date: now.addingTimeInterval(-86_400), kind: "time",
            roundsCompleted: 0, totalReps: 2, elapsedTime: 5, pausedTime: 0,
            activeTime: 5, isPR: false,
            finishedReason: FinishedReason.manual.rawValue, repsQuota: 90
        )
        context.insert(partial)
        try? context.save()

        // A genuine, complete 4-minute Fran should still count as a PR.
        let isPR = ResultsService.isNewPR(
            workout: fran, kind: "time", rounds: 3, activeTime: 240,
            before: now, finishedReason: FinishedReason.goalReached.rawValue,
            in: context
        )
        XCTAssertTrue(isPR, "A complete effort must not be measured against a partial")
    }

    @MainActor
    func testManualStopOfAnAMRAPIsNotARoundsPR() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let isPR = ResultsService.isNewPR(
            workout: cindy, kind: "rounds", rounds: 12, activeTime: 480,
            before: Date(), finishedReason: FinishedReason.manual.rawValue,
            in: context
        )
        XCTAssertFalse(isPR, "Stopping an AMRAP early is not a comparable effort")
    }

    // MARK: - PR Recomputation After Deletion

    @MainActor
    func testDeletingThePRPromotesTheNextBest() {
        let fran = BenchmarkSeed.fran(in: context)
        let now = Date()

        func makeRecord(activeTime: TimeInterval, daysAgo: Int, isPR: Bool) -> WorkoutRecord {
            WorkoutRecord(
                workout: fran, date: now.addingTimeInterval(Double(-86_400 * daysAgo)),
                kind: "time", roundsCompleted: 3, totalReps: 90,
                elapsedTime: activeTime, pausedTime: 0, activeTime: activeTime,
                isPR: isPR, finishedReason: FinishedReason.goalReached.rawValue,
                repsQuota: 90
            )
        }

        let slow = makeRecord(activeTime: 300, daysAgo: 3, isPR: true)
        let fast = makeRecord(activeTime: 200, daysAgo: 2, isPR: true)
        context.insert(slow)
        context.insert(fast)
        try? context.save()

        // Delete the standing PR; the earlier slower attempt should regain it.
        context.delete(fast)
        try? context.save()

        let service = ResultsService(context: context)
        service.recomputePRs(for: fran)
        try? context.save()

        XCTAssertTrue(slow.isPR, "Deleting the best attempt must promote the next best")
    }

    // MARK: - Screen Awake

    /// `isIdleTimerDisabled` is global app state, so an unbalanced hold means
    /// the screen never sleeps again for the rest of the app's lifetime. These
    /// cover every way a session can end.

    @MainActor
    func testScreenIsHeldWhileRunningAndReleasedOnFinish() {
        ScreenSleep.releaseAll()
        let cindy = BenchmarkSeed.cindy(in: context)
        let service = WorkoutTimerService(workout: cindy) { _ in }

        XCTAssertFalse(ScreenSleep.isHeld)
        service.start()
        XCTAssertTrue(ScreenSleep.isHeld, "Screen should stay awake during a workout")

        service.finish()
        XCTAssertFalse(ScreenSleep.isHeld, "Finishing must release the screen")
    }

    @MainActor
    func testPauseReleasesTheScreenAndResumeReclaimsIt() {
        ScreenSleep.releaseAll()
        let cindy = BenchmarkSeed.cindy(in: context)
        let service = WorkoutTimerService(workout: cindy) { _ in }

        service.start()
        service.pause()
        XCTAssertFalse(ScreenSleep.isHeld, "A paused athlete has stepped away")

        service.resume()
        XCTAssertTrue(ScreenSleep.isHeld)

        service.finish()
        XCTAssertFalse(ScreenSleep.isHeld)
    }

    @MainActor
    func testResetReleasesTheScreen() {
        ScreenSleep.releaseAll()
        let cindy = BenchmarkSeed.cindy(in: context)
        let service = WorkoutTimerService(workout: cindy) { _ in }

        service.start()
        // Discarding a workout goes through reset().
        service.reset()
        XCTAssertFalse(ScreenSleep.isHeld, "Discarding must release the screen")
    }

    @MainActor
    func testAutoStopReleasesTheScreen() {
        let fran = BenchmarkSeed.fran(in: context)
        ScreenSleep.releaseAll()
        let service = factory.makeTimerService(for: fran)

        service.start()
        XCTAssertTrue(ScreenSleep.isHeld)

        for _ in 1...90 {
            guard let task = service.snapshot.tasks.first(where: { !$0.isComplete }) else { break }
            _ = service.logReps(taskID: task.id, count: 1)
        }

        XCTAssertEqual(service.snapshot.phase, .finished)
        XCTAssertFalse(ScreenSleep.isHeld, "Auto-stop must release the screen")
    }

    @MainActor
    func testRepeatedLifecycleCallsKeepTheHoldBalanced() {
        ScreenSleep.releaseAll()
        let cindy = BenchmarkSeed.cindy(in: context)
        let service = WorkoutTimerService(workout: cindy) { _ in }

        // Redundant calls must not stack holds, or one release won't clear them.
        service.start()
        service.start()
        service.resume()
        XCTAssertTrue(ScreenSleep.isHeld)

        service.finish()
        service.finish()
        XCTAssertFalse(ScreenSleep.isHeld, "Holds must not accumulate")
    }

    // MARK: - AppModel Initialization
    @MainActor
    func testAppModelInitializationAndState() {
        let appModel = AppModel(factory: factory)
        let cindy = BenchmarkSeed.cindy(in: context)

        XCTAssertNil(appModel.pendingStart)
        appModel.startWorkout(cindy)
        XCTAssertEqual(appModel.pendingStart?.name, "Cindy")
    }
}
