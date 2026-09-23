import XCTest
import SwiftData
@testable import WODCounter

final class ResultsServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var service: ResultsService!

    @MainActor
    override func setUp() {
        super.setUp()
        container = Container.inMemory()
        context = container.mainContext
        service = ResultsService(context: context)
    }

    override func tearDown() {
        container = nil
        context = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Format Tests
    func testFormatDuration() {
        XCTAssertEqual(Format.duration(0), "00:00")
        XCTAssertEqual(Format.duration(65), "01:05")
        XCTAssertEqual(Format.duration(1200), "20:00")
        XCTAssertEqual(Format.duration(3665), "61:05")
    }

    func testFormatTimer() {
        XCTAssertEqual(Format.timer(20), "20:00")
        XCTAssertEqual(Format.timer(5), "5:00")
    }

    // MARK: - PR Detection Tests
    @MainActor
    func testForTimePRDetection() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let now = Date()
        let dayAgo = now.addingTimeInterval(-86400)
        let twoDaysAgo = now.addingTimeInterval(-172800)

        // First attempt: 15 rounds -> Always PR
        let isFirstPR = ResultsService.isNewPR(
            workout: cindy,
            kind: "rounds",
            rounds: 15,
            activeTime: 1200,
            before: twoDaysAgo,
            in: context
        )
        XCTAssertTrue(isFirstPR)

        let record1 = WorkoutRecord(
            workout: cindy,
            date: twoDaysAgo,
            kind: "rounds",
            roundsCompleted: 15,
            totalReps: 450,
            elapsedTime: 1200,
            pausedTime: 0,
            activeTime: 1200,
            isPR: true
        )
        context.insert(record1)

        // Second attempt: 14 rounds -> Worse, NOT a PR
        let isSecondPR = ResultsService.isNewPR(
            workout: cindy,
            kind: "rounds",
            rounds: 14,
            activeTime: 1200,
            before: dayAgo,
            in: context
        )
        XCTAssertFalse(isSecondPR)

        let record2 = WorkoutRecord(
            workout: cindy,
            date: dayAgo,
            kind: "rounds",
            roundsCompleted: 14,
            totalReps: 420,
            elapsedTime: 1200,
            pausedTime: 0,
            activeTime: 1200,
            isPR: false
        )
        context.insert(record2)

        // Third attempt: 18 rounds -> Better, IS a PR!
        let isThirdPR = ResultsService.isNewPR(
            workout: cindy,
            kind: "rounds",
            rounds: 18,
            activeTime: 1200,
            before: now,
            in: context
        )
        XCTAssertTrue(isThirdPR)
    }

    @MainActor
    func testTopTimePRDetection() {
        let fran = BenchmarkSeed.fran(in: context)
        let now = Date()
        let dayAgo = now.addingTimeInterval(-86400)
        let twoDaysAgo = now.addingTimeInterval(-172800)

        // First attempt: 300 seconds -> PR
        let isFirstPR = ResultsService.isNewPR(
            workout: fran,
            kind: "time",
            rounds: 3,
            activeTime: 300,
            before: twoDaysAgo,
            in: context
        )
        XCTAssertTrue(isFirstPR)

        let record1 = WorkoutRecord(
            workout: fran,
            date: twoDaysAgo,
            kind: "time",
            roundsCompleted: 3,
            totalReps: 90,
            elapsedTime: 300,
            pausedTime: 0,
            activeTime: 300,
            isPR: true
        )
        context.insert(record1)

        // Second attempt: 320 seconds (slower) -> NOT a PR
        let isSecondPR = ResultsService.isNewPR(
            workout: fran,
            kind: "time",
            rounds: 3,
            activeTime: 320,
            before: dayAgo,
            in: context
        )
        XCTAssertFalse(isSecondPR)

        let record2 = WorkoutRecord(
            workout: fran,
            date: dayAgo,
            kind: "time",
            roundsCompleted: 3,
            totalReps: 90,
            elapsedTime: 320,
            pausedTime: 0,
            activeTime: 320,
            isPR: false
        )
        context.insert(record2)

        // Third attempt: 250 seconds (faster) -> IS a PR!
        let isThirdPR = ResultsService.isNewPR(
            workout: fran,
            kind: "time",
            rounds: 3,
            activeTime: 250,
            before: now,
            in: context
        )
        XCTAssertTrue(isThirdPR)
    }

    // MARK: - Window Summary & History Tests
    @MainActor
    func testWindowSummaryAndFiltering() {
        let cindy = BenchmarkSeed.cindy(in: context)
        let now = Date()
        let past3Days = now.addingTimeInterval(-3 * 86400)
        let past40Days = now.addingTimeInterval(-40 * 86400)

        let recordRecent = WorkoutRecord(
            workout: cindy,
            date: past3Days,
            kind: "rounds",
            roundsCompleted: 20,
            totalReps: 600,
            elapsedTime: 1200,
            pausedTime: 0,
            activeTime: 1200,
            isPR: true
        )
        let recordOld = WorkoutRecord(
            workout: cindy,
            date: past40Days,
            kind: "rounds",
            roundsCompleted: 15,
            totalReps: 450,
            elapsedTime: 1200,
            pausedTime: 0,
            activeTime: 1200,
            isPR: true
        )
        context.insert(recordRecent)
        context.insert(recordOld)

        // 30-day window
        let interval30Days = DateInterval(start: now.addingTimeInterval(-30 * 86400), end: now)
        let summary30 = service.summary(for: cindy, window: interval30Days)
        XCTAssertEqual(summary30.workoutsCount, 1)
        XCTAssertEqual(summary30.prsThisWindow, 1)
        XCTAssertEqual(summary30.bestRounds, 20)

        // 90-day window (includes both)
        let interval90Days = DateInterval(start: now.addingTimeInterval(-90 * 86400), end: now)
        let summary90 = service.summary(for: cindy, window: interval90Days)
        XCTAssertEqual(summary90.workoutsCount, 2)
        XCTAssertEqual(summary90.prsThisWindow, 2)
        XCTAssertEqual(summary90.bestRounds, 20)
        XCTAssertEqual(summary90.avgActiveTime, 1200)

        // All history
        let allHistory = service.history(for: cindy)
        XCTAssertEqual(allHistory.count, 2)
        XCTAssertEqual(allHistory.first?.roundsCompleted, 20) // sorted reverse chronologically
    }
}
