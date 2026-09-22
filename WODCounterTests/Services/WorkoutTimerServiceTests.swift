import XCTest
import SwiftData
@testable import WODCounter

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
        let cindy = BenchmarkSeed.cindy(context: context)
        var finishedRecord: WorkoutRecord?

        let service = WorkoutTimerService(workout: cindy) { record in
            finishedRecord = record
        }

        XCTAssertEqual(service.snapshot.phase, .idle)
        XCTAssertEqual(service.snapshot.isRunning, false)

        // Start
        service.start()
        XCTAssertEqual(service.snapshot.phase, .running)
        XCTAssertEqual(service.snapshot.isRunning, true)

        // Advance 10 active seconds
        service.advanceTimeStep(10, active: true)
        XCTAssertEqual(service.snapshot.activeElapsed, 10)
        XCTAssertEqual(service.snapshot.wallClock, 10)

        // Pause
        service.pause()
        XCTAssertEqual(service.snapshot.phase, .paused)
        XCTAssertEqual(service.snapshot.isPaused, true)

        // Advance 5 paused seconds
        service.advanceTimeStep(5, active: false)
        XCTAssertEqual(service.snapshot.activeElapsed, 10) // Frozen
        XCTAssertEqual(service.snapshot.wallClock, 15)

        // Resume
        service.resume()
        XCTAssertEqual(service.snapshot.phase, .running)

        // Advance 5 active seconds
        service.advanceTimeStep(5, active: true)
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
    }

    // MARK: - ServiceFactory Persistence & PR Verification
    @MainActor
    func testServiceFactoryPersistsRecordWithPRStatus() {
        let fran = BenchmarkSeed.fran(context: context)
        let fixedDate = Date()

        let timerService = factory.makeTimerService(for: fran, clock: { fixedDate })

        timerService.start()

        // Advance through all 3 blocks (90 reps total)
        for _ in 1...90 {
            _ = timerService.advanceRep()
        }

        // Advance 180 seconds active time
        timerService.advanceTimeStep(180, active: true)

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

    // MARK: - AppModel Initialization
    @MainActor
    func testAppModelInitializationAndState() {
        let appModel = AppModel(factory: factory)
        let cindy = BenchmarkSeed.cindy(context: context)

        XCTAssertNil(appModel.pendingStart)
        appModel.startWorkout(cindy)
        XCTAssertEqual(appModel.pendingStart?.name, "Cindy")
    }
}
