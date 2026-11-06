import XCTest
import SwiftData
@testable import WODCounter

/// Mutable clock used to advance session time deterministically without
/// sleeping or bypassing the service's timeline.
private final class FakeClock: @unchecked Sendable {
    private(set) var now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_000)) {
        self.now = now
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
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

    @MainActor
    private func fetchRecords() -> [WorkoutRecord] {
        (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
    }

    /// Top-time workout with one exercise per round and a block-level rest.
    @MainActor
    private func makeRestWorkout(rest: Int, repeatTimes: Int = 2) -> Workout {
        let workout = Workout(
            name: "Rest Service \(UUID().uuidString)",
            mode: .topTime,
            isBuiltin: false
        )
        let movement = Movement(name: "Burpee-\(UUID().uuidString)")
        context.insert(movement)
        let block = RoundBlock(repeatTimes: repeatTimes, restAfterBlock: rest, sortOrder: 0)
        let exercise = Exercise(movement: movement, reps: 10, displayLabel: "10 Burpees", sortOrder: 0)
        context.insert(exercise)
        block.exercises = [exercise]
        workout.blocks = [block]
        context.insert(workout)
        return workout
    }

    // MARK: - State & Timeline Tests

    @MainActor
    func testStartPauseResumeAndFinish() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        var finishedRecord: WorkoutRecord?

        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record in
            finishedRecord = record
        }

        XCTAssertEqual(service.snapshot.phase, .idle)
        XCTAssertEqual(service.snapshot.isRunning, false)

        service.start()
        XCTAssertEqual(service.snapshot.phase, .running)
        XCTAssertEqual(service.snapshot.isRunning, true)

        clock.advance(10)
        service.refresh()
        XCTAssertEqual(service.snapshot.activeElapsed, 10)
        XCTAssertEqual(service.snapshot.wallClock, 10)

        service.pause()
        XCTAssertEqual(service.snapshot.phase, .paused)
        XCTAssertEqual(service.snapshot.isPaused, true)

        // Paused time extends wall time but not active time.
        clock.advance(5)
        service.refresh()
        XCTAssertEqual(service.snapshot.activeElapsed, 10)
        XCTAssertEqual(service.snapshot.wallClock, 15)

        service.resume()
        XCTAssertEqual(service.snapshot.phase, .running)

        clock.advance(5)
        service.refresh()
        XCTAssertEqual(service.snapshot.activeElapsed, 15)
        XCTAssertEqual(service.snapshot.wallClock, 20)

        service.finish()
        XCTAssertEqual(service.snapshot.phase, .finished)
        XCTAssertEqual(service.snapshot.isFinished, true)

        XCTAssertNotNil(finishedRecord)
        XCTAssertEqual(finishedRecord?.roundsCompleted, 0)
        XCTAssertEqual(finishedRecord?.activeTime, 15)
        XCTAssertEqual(finishedRecord?.pausedTime, 5)
        XCTAssertEqual(finishedRecord?.elapsedTime, 20)
        XCTAssertEqual(finishedRecord?.kind, "rounds")
    }

    @MainActor
    func testSnapshotReportsLivePhasesForCloseProtection() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { _ in }

        XCTAssertFalse(service.snapshot.isLive)

        service.start()
        XCTAssertTrue(service.snapshot.isLive)

        service.pause()
        XCTAssertTrue(service.snapshot.isLive)

        service.resume()
        XCTAssertTrue(service.snapshot.isLive)

        service.finish()
        XCTAssertFalse(service.snapshot.isLive)
    }

    @MainActor
    func testLongPauseIsFullyRecorded() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        var finishedRecord: WorkoutRecord?

        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record in
            finishedRecord = record
        }

        service.start()
        clock.advance(10)
        service.refresh()

        service.pause()
        clock.advance(300)
        service.refresh()
        XCTAssertEqual(service.snapshot.activeElapsed, 10)
        XCTAssertEqual(service.snapshot.wallClock, 310)

        service.resume()
        clock.advance(10)
        service.refresh()
        service.finish()

        XCTAssertEqual(finishedRecord?.elapsedTime, 320)
        XCTAssertEqual(finishedRecord?.pausedTime, 300)
        XCTAssertEqual(finishedRecord?.activeTime, 20)
    }

    @MainActor
    func testMultiplePausesAccumulate() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        var finishedRecord: WorkoutRecord?

        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record in
            finishedRecord = record
        }

        service.start()
        clock.advance(10)
        service.refresh()

        service.pause()
        clock.advance(5)
        service.resume()

        clock.advance(10)
        service.refresh()

        service.pause()
        clock.advance(20)
        service.resume()

        clock.advance(5)
        service.refresh()
        service.finish()

        XCTAssertEqual(finishedRecord?.elapsedTime, 50)
        XCTAssertEqual(finishedRecord?.pausedTime, 25)
        XCTAssertEqual(finishedRecord?.activeTime, 25)
    }

    @MainActor
    func testFinishWhilePausedRecordsPauseUpToFinish() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        var finishedRecord: WorkoutRecord?

        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record in
            finishedRecord = record
        }

        service.start()
        clock.advance(10)
        service.refresh()
        service.pause()

        clock.advance(300)
        service.finish()

        XCTAssertEqual(service.snapshot.phase, .finished)
        XCTAssertEqual(finishedRecord?.elapsedTime, 310)
        XCTAssertEqual(finishedRecord?.pausedTime, 300)
        XCTAssertEqual(finishedRecord?.activeTime, 10)
    }

    @MainActor
    func testForTimeCapUsesActiveTimeNotWallTime() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        var finishedRecords: [WorkoutRecord] = []

        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record in
            finishedRecords.append(record)
        }

        service.start()
        clock.advance(600)
        service.refresh()

        // A long pause must not consume the 20-minute active cap.
        service.pause()
        clock.advance(3_000)
        service.resume()

        clock.advance(599)
        service.refresh()
        XCTAssertEqual(service.snapshot.phase, .running)
        XCTAssertEqual(service.snapshot.activeElapsed, 1_199)

        clock.advance(1)
        service.refresh()
        XCTAssertEqual(service.snapshot.phase, .finished)
        XCTAssertEqual(finishedRecords.count, 1)

        let record = finishedRecords[0]
        XCTAssertEqual(record.activeTime, 1_200)
        XCTAssertEqual(record.pausedTime, 3_000)
        XCTAssertEqual(record.elapsedTime, 4_200)
    }

    // MARK: - Rest Semantics (WTB-005)

    @MainActor
    func testPauseAndResumeDuringRestKeepsRemainingRest() {
        let workout = makeRestWorkout(rest: 60, repeatTimes: 2)
        let clock = FakeClock()
        let service = WorkoutTimerService(workout: workout, clock: { clock.now }) { _ in }

        service.start()
        let firstRound = service.snapshot.tasks.first { !$0.isComplete }!
        XCTAssertEqual(service.logReps(taskID: firstRound.id, count: 10), .blockCompleted)
        XCTAssertEqual(service.snapshot.phase, .resting)

        clock.advance(10)
        service.refresh()
        XCTAssertEqual(service.snapshot.phase, .resting)

        // Paused time does not consume the rest.
        service.pause()
        XCTAssertEqual(service.snapshot.phase, .paused)
        clock.advance(30)
        service.refresh()
        XCTAssertEqual(service.snapshot.phase, .paused)
        XCTAssertEqual(service.snapshot.activeElapsed, 10)

        service.resume()
        XCTAssertEqual(service.snapshot.phase, .resting)

        clock.advance(49)
        service.refresh()
        XCTAssertEqual(service.snapshot.phase, .resting)
        XCTAssertEqual(service.snapshot.activeElapsed, 59)

        clock.advance(1)
        service.refresh()
        XCTAssertEqual(service.snapshot.phase, .running)
        XCTAssertEqual(service.snapshot.activeElapsed, 60)
    }

    @MainActor
    func testEndRestWhilePausedResumesTimelineAndTicker() {
        let workout = makeRestWorkout(rest: 60, repeatTimes: 2)
        let clock = FakeClock()
        let service = WorkoutTimerService(workout: workout, clock: { clock.now }) { _ in }

        service.start()
        let firstRound = service.snapshot.tasks.first { !$0.isComplete }!
        XCTAssertEqual(service.logReps(taskID: firstRound.id, count: 10), .blockCompleted)
        XCTAssertEqual(service.snapshot.phase, .resting)

        service.pause()
        clock.advance(30)
        service.refresh()
        XCTAssertEqual(service.snapshot.phase, .paused)
        XCTAssertEqual(service.snapshot.activeElapsed, 0)

        _ = service.endRest()
        XCTAssertEqual(service.snapshot.phase, .running)
        XCTAssertEqual(service.snapshot.isPaused, false)

        clock.advance(5)
        service.refresh()
        XCTAssertEqual(service.snapshot.activeElapsed, 5)
        service.finish()
    }

    @MainActor
    func testSkipRestResumesRunningAndFinalRoundHasNoRest() {
        let workout = makeRestWorkout(rest: 60, repeatTimes: 2)
        let clock = FakeClock()
        let service = WorkoutTimerService(workout: workout, clock: { clock.now }) { _ in }

        service.start()
        let firstRound = service.snapshot.tasks.first { !$0.isComplete }!
        XCTAssertEqual(service.logReps(taskID: firstRound.id, count: 10), .blockCompleted)
        XCTAssertEqual(service.snapshot.phase, .resting)

        _ = service.endRest()
        XCTAssertEqual(service.snapshot.phase, .running)

        clock.advance(5)
        service.refresh()
        let finalRound = service.snapshot.tasks.first { !$0.isComplete }!
        XCTAssertEqual(service.logReps(taskID: finalRound.id, count: 10), .finished(.goalReached))
        XCTAssertEqual(service.snapshot.phase, .finished)
    }

    // MARK: - Rest Countdown

    @MainActor
    func testRestRemainingCountsDownInServiceSnapshot() {
        let workout = makeRestWorkout(rest: 60, repeatTimes: 2)
        let clock = FakeClock()
        let service = WorkoutTimerService(workout: workout, clock: { clock.now }) { _ in }

        service.start()
        XCTAssertNil(service.snapshot.restRemaining)

        let firstRound = service.snapshot.tasks.first { !$0.isComplete }!
        XCTAssertEqual(service.logReps(taskID: firstRound.id, count: 10), .blockCompleted)
        XCTAssertEqual(service.snapshot.phase, .resting)
        XCTAssertEqual(service.snapshot.restRemaining, 60)

        clock.advance(20)
        service.refresh()
        XCTAssertEqual(service.snapshot.restRemaining, 40)

        // Paused time does not consume rest.
        service.pause()
        clock.advance(30)
        service.refresh()
        XCTAssertEqual(service.snapshot.restRemaining, 40)

        service.resume()
        clock.advance(40)
        service.refresh()
        XCTAssertEqual(service.snapshot.phase, .running)
        XCTAssertNil(service.snapshot.restRemaining)
    }

    // MARK: - Undo Rep Logging

    @MainActor
    func testUndoReversesPartialRepAddition() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { _ in }

        service.start()
        let task = service.snapshot.tasks.first { $0.quota >= 10 }!
        let initialRemaining = service.snapshot.totalRemaining
        XCTAssertFalse(service.canUndo)

        XCTAssertEqual(service.logReps(taskID: task.id, count: 5), .none)
        XCTAssertEqual(service.snapshot.totalRepsCompleted, 5)
        XCTAssertEqual(service.snapshot.totalRemaining, initialRemaining - 5)
        XCTAssertTrue(service.canUndo)

        XCTAssertEqual(service.undoLastReps(), 5)
        XCTAssertEqual(service.snapshot.totalRepsCompleted, 0)
        XCTAssertEqual(service.snapshot.totalRemaining, initialRemaining)
        XCTAssertFalse(service.canUndo)
    }

    @MainActor
    func testUndoAtZeroIsNoOp() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { _ in }

        service.start()
        XCTAssertEqual(service.undoLastReps(), 0)
        XCTAssertEqual(service.snapshot.totalRepsCompleted, 0)
        XCTAssertFalse(service.canUndo)
    }

    @MainActor
    func testUndoStackClearsAfterTaskCompletion() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { _ in }

        service.start()
        let task = service.snapshot.tasks.first { $0.quota >= 10 }!

        XCTAssertEqual(service.logReps(taskID: task.id, count: 5), .none)
        XCTAssertTrue(service.canUndo)

        // Completing the task (but not the round) must clear the stack so undo
        // cannot reopen a completed set.
        XCTAssertEqual(service.logReps(taskID: task.id, count: task.remaining - 5), .none)
        XCTAssertFalse(service.canUndo)
        XCTAssertEqual(service.undoLastReps(), 0)
        XCTAssertEqual(service.snapshot.totalRepsCompleted, task.quota)
    }

    @MainActor
    func testUndoAfterSessionCompletionIsNoOp() {
        let fran = BenchmarkSeed.fran(in: context)
        let clock = FakeClock()
        let service = WorkoutTimerService(workout: fran, clock: { clock.now }) { _ in }

        service.start()
        let thirdTask = service.snapshot.tasks[2]
        XCTAssertEqual(service.logReps(taskID: thirdTask.id, count: 5), .none)
        XCTAssertTrue(service.canUndo)

        for task in service.snapshot.tasks {
            _ = service.logReps(taskID: task.id, count: task.remaining)
        }

        XCTAssertEqual(service.snapshot.phase, .finished)
        XCTAssertFalse(service.canUndo)
        XCTAssertEqual(service.undoLastReps(), 0)
        XCTAssertEqual(service.snapshot.totalRepsCompleted, 90)
    }

    // MARK: - Idempotent Completion

    @MainActor
    func testDoubleFinishEmitsOneRecord() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        var finishedRecords: [WorkoutRecord] = []

        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record in
            finishedRecords.append(record)
        }

        service.start()
        clock.advance(10)
        service.refresh()

        service.finish()
        service.finish()

        XCTAssertEqual(finishedRecords.count, 1)
        XCTAssertEqual(finishedRecords.first?.activeTime, 10)
        XCTAssertEqual(finishedRecords.first?.pausedTime, 0)
        XCTAssertEqual(finishedRecords.first?.elapsedTime, 10)
    }

    @MainActor
    func testAutoStopThenManualFinishEmitsOneRecord() {
        let fran = BenchmarkSeed.fran(in: context)
        let clock = FakeClock()
        var finishedRecords: [WorkoutRecord] = []

        let service = WorkoutTimerService(workout: fran, clock: { clock.now }) { record in
            finishedRecords.append(record)
        }

        service.start()
        clock.advance(30)
        service.refresh()

        for task in service.snapshot.tasks {
            _ = service.logReps(taskID: task.id, count: task.remaining)
        }

        XCTAssertEqual(service.snapshot.phase, .finished)
        XCTAssertEqual(finishedRecords.count, 1)
        XCTAssertEqual(finishedRecords.first?.roundsCompleted, 3)
        XCTAssertEqual(finishedRecords.first?.totalReps, 90)
        XCTAssertEqual(finishedRecords.first?.activeTime, 30)
        XCTAssertEqual(finishedRecords.first?.pausedTime, 0)
        XCTAssertEqual(finishedRecords.first?.elapsedTime, 30)

        service.finish()
        XCTAssertEqual(finishedRecords.count, 1)
        XCTAssertEqual(finishedRecords.first?.activeTime, 30)
    }

    @MainActor
    func testClockExpiryThenManualFinishEmitsOneRecord() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        var finishedRecords: [WorkoutRecord] = []

        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record in
            finishedRecords.append(record)
        }

        service.start()
        clock.advance(1_201)
        service.refresh()

        XCTAssertEqual(service.snapshot.phase, .finished)
        XCTAssertEqual(finishedRecords.count, 1)
        XCTAssertEqual(finishedRecords.first?.activeTime, 1_201)
        XCTAssertEqual(finishedRecords.first?.pausedTime, 0)
        XCTAssertEqual(finishedRecords.first?.elapsedTime, 1_201)

        service.finish()
        XCTAssertEqual(finishedRecords.count, 1)
    }

    @MainActor
    func testFinishWhileIdleDoesNotPersist() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()
        var finishedRecords: [WorkoutRecord] = []

        let service = WorkoutTimerService(workout: cindy, clock: { clock.now }) { record in
            finishedRecords.append(record)
        }

        service.finish()

        XCTAssertEqual(service.snapshot.phase, .idle)
        XCTAssertTrue(finishedRecords.isEmpty)
    }

    // MARK: - ServiceFactory Persistence & PR Verification
    @MainActor
    func testServiceFactoryPersistsRecordWithPRStatus() {
        let fran = BenchmarkSeed.fran(in: context)
        let clock = FakeClock()

        let timerService = factory.makeTimerService(for: fran, clock: { clock.now })

        timerService.start()
        clock.advance(180)
        timerService.refresh()

        // Pause before finishing so the persisted record proves wall-clock,
        // paused, and active time are all stored correctly.
        timerService.pause()
        clock.advance(30)
        timerService.resume()

        // Log all 90 reps across the free-form task list (any order).
        for task in timerService.snapshot.tasks {
            _ = timerService.logReps(taskID: task.id, count: task.remaining)
        }

        let records = fetchRecords()
        XCTAssertEqual(records.count, 1)
        guard let savedRecord = records.first else {
            XCTFail("Expected saved record")
            return
        }

        XCTAssertEqual(savedRecord.workout?.name, "Fran")
        XCTAssertEqual(savedRecord.kind, "time")
        XCTAssertEqual(savedRecord.roundsCompleted, 3)
        XCTAssertEqual(savedRecord.totalReps, 90)
        XCTAssertEqual(savedRecord.activeTime, 180)
        XCTAssertEqual(savedRecord.pausedTime, 30)
        XCTAssertEqual(savedRecord.elapsedTime, 210)
        XCTAssertTrue(savedRecord.isPR) // First attempt is always PR
    }

    @MainActor
    func testServiceFactoryInsertsExactlyOneRecordForCompletedSession() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let clock = FakeClock()

        let timerService = factory.makeTimerService(for: cindy, clock: { clock.now })

        timerService.start()
        clock.advance(10)
        timerService.refresh()
        timerService.finish()
        timerService.finish()

        let records = fetchRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.activeTime, 10)
        XCTAssertEqual(records.first?.pausedTime, 0)
        XCTAssertEqual(records.first?.elapsedTime, 10)
    }

    @MainActor
    func testCompletedRecordIsExposedWithPRStatus() {
        let fran = BenchmarkSeed.fran(in: context)
        let clock = FakeClock()

        let timerService = factory.makeTimerService(for: fran, clock: { clock.now })

        XCTAssertNil(timerService.completedRecord)

        timerService.start()
        clock.advance(180)
        timerService.refresh()

        for task in timerService.snapshot.tasks {
            _ = timerService.logReps(taskID: task.id, count: task.remaining)
        }

        let record = timerService.completedRecord
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.workout?.name, "Fran")
        XCTAssertEqual(record?.roundsCompleted, 3)
        XCTAssertEqual(record?.totalReps, 90)
        XCTAssertEqual(record?.activeTime, 180)
        XCTAssertEqual(record?.pausedTime, 0)
        XCTAssertEqual(record?.elapsedTime, 180)
        XCTAssertTrue(record?.isPR == true)
        XCTAssertTrue(fetchRecords().contains { $0.id == record?.id })
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
