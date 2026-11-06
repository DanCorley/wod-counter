import Testing
import SwiftData
import Foundation
@testable import WODCounter

@MainActor
struct ResultsViewTests {

    // MARK: - Helpers

    /// Inserts a WorkoutRecord for the given workout with the given parameters at the specified offset from now.
    @discardableResult
    private func insertRecord(
        workout: Workout,
        context: ModelContext,
        daysAgo: Int,
        rounds: Int,
        activeTime: TimeInterval,
        isPR: Bool = false
    ) -> WorkoutRecord {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let kind = workout.mode == .forTime ? "rounds" : "time"
        let record = WorkoutRecord(
            workout: workout,
            date: date,
            kind: kind,
            roundsCompleted: rounds,
            totalReps: rounds * 5,
            elapsedTime: activeTime + 10,
            pausedTime: 10,
            activeTime: activeTime,
            isPR: isPR
        )
        context.insert(record)
        return record
    }

    private func makeWorkout(context: ModelContext, name: String = "Test WOD", mode: ExecutionMode = .forTime) -> Workout {
        let movement = Movement(name: "Air Squat", equipment: nil, category: "Gymnastics", iconName: nil)
        context.insert(movement)
        let exercise = Exercise(movement: movement, reps: 15, displayLabel: "15 Air Squats")
        context.insert(exercise)
        let block = RoundBlock(repeatTimes: 0)
        block.exercises = [exercise]
        context.insert(block)
        let workout = Workout(
            name: name,
            workoutDescription: nil,
            category: "Girl",
            mode: mode,
            forTimeMinutes: mode == .forTime ? 20 : nil
        )
        workout.blocks = [block]
        context.insert(workout)
        return workout
    }

    // MARK: - Window Filtering

    @Test func sevenDayWindowFiltersOldRecords() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context)

        insertRecord(workout: workout, context: context, daysAgo: 3, rounds: 10, activeTime: 600)
        insertRecord(workout: workout, context: context, daysAgo: 10, rounds: 12, activeTime: 500) // outside 7d

        let window = ResultsWindow.sevenDays.dateInterval
        let records = service.history(for: workout, window: window)

        #expect(records.count == 1)
        #expect(records.first?.roundsCompleted == 10)
    }

    @Test func thirtyDayWindowIncludesRecentRecords() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context)

        insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 10, activeTime: 600)
        insertRecord(workout: workout, context: context, daysAgo: 25, rounds: 12, activeTime: 500)
        insertRecord(workout: workout, context: context, daysAgo: 35, rounds: 8, activeTime: 700) // outside 30d

        let window = ResultsWindow.thirtyDays.dateInterval
        let records = service.history(for: workout, window: window)

        #expect(records.count == 2)
    }

    @Test func allTimeWindowReturnsAllRecords() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context)

        insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 10, activeTime: 600)
        insertRecord(workout: workout, context: context, daysAgo: 100, rounds: 8, activeTime: 700)
        insertRecord(workout: workout, context: context, daysAgo: 365, rounds: 6, activeTime: 900)

        let records = service.history(for: workout, window: nil)

        #expect(records.count == 3)
    }

    // MARK: - Summary Counts

    @Test func summaryCounts() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context)

        insertRecord(workout: workout, context: context, daysAgo: 3, rounds: 10, activeTime: 600, isPR: true)
        insertRecord(workout: workout, context: context, daysAgo: 6, rounds: 8, activeTime: 700, isPR: false)
        insertRecord(workout: workout, context: context, daysAgo: 40, rounds: 5, activeTime: 900, isPR: false) // outside 30d

        let window = ResultsWindow.thirtyDays.dateInterval
        let summary = service.summary(window: window)

        #expect(summary.workoutsCount == 2)
        #expect(summary.prsThisWindow == 1)
    }

    @Test func summaryEmptyReturnsZeroes() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)

        let summary = service.summary(window: ResultsWindow.thirtyDays.dateInterval)

        #expect(summary.workoutsCount == 0)
        #expect(summary.prsThisWindow == 0)
        #expect(summary.bestRounds == 0)
    }

    // MARK: - Best Record

    @Test func bestForTimeIsHighestRounds() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .forTime)

        insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 10, activeTime: 600)
        insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 15, activeTime: 700)
        insertRecord(workout: workout, context: context, daysAgo: 10, rounds: 8, activeTime: 500)

        let records = service.history(for: workout, window: nil)
        let best = records.max(by: { $0.roundsCompleted < $1.roundsCompleted })

        #expect(best?.roundsCompleted == 15)
    }

    @Test func bestTopTimeIsLowestActiveTime() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .topTime)

        insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 1, activeTime: 600)
        insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 1, activeTime: 450)
        insertRecord(workout: workout, context: context, daysAgo: 10, rounds: 1, activeTime: 720)

        let records = service.history(for: workout, window: nil)
        let best = records.min(by: { $0.activeTime < $1.activeTime })

        #expect(best?.activeTime == 450)
    }

    // MARK: - Delta Computation (best vs latest attempt)

    @Test func forTimeLatestWorseThanBestShowsRegression() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .forTime)

        insertRecord(workout: workout, context: context, daysAgo: 10, rounds: 15, activeTime: 600)
        insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 18, activeTime: 580) // best
        insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 14, activeTime: 590) // latest, worse

        let records = service.history(for: workout, window: nil)
        let summary = try #require(ResultsService.bestSummaries(from: records).first)

        #expect(summary.bestValue == 18)
        #expect(summary.latestValue == 14)
        #expect(summary.delta == .regressed(amount: 4))
        #expect(summary.deltaText == "−4 rds")
    }

    @Test func topTimeLatestWorseThanBestShowsRegression() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .topTime)

        insertRecord(workout: workout, context: context, daysAgo: 10, rounds: 1, activeTime: 400)
        insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 1, activeTime: 300) // best
        insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 1, activeTime: 350) // latest, slower

        let records = service.history(for: workout, window: nil)
        let summary = try #require(ResultsService.bestSummaries(from: records).first)

        #expect(summary.bestValue == 300)
        #expect(summary.latestValue == 350)
        #expect(summary.delta == .regressed(amount: 50))
        #expect(summary.deltaText == "+00:50")
    }

    @Test func latestAttemptEqualToBestShowsEquals() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .forTime)

        insertRecord(workout: workout, context: context, daysAgo: 10, rounds: 10, activeTime: 600)
        insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 12, activeTime: 590)
        insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 12, activeTime: 580) // ties best

        let records = service.history(for: workout, window: nil)
        let summary = try #require(ResultsService.bestSummaries(from: records).first)

        #expect(summary.bestValue == 12)
        #expect(summary.latestValue == 12)
        #expect(summary.delta == .equal)
        #expect(summary.deltaText == "=")
    }

    @Test func singleAttemptHasNoDelta() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .topTime)

        insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 1, activeTime: 400)

        let records = service.history(for: workout, window: nil)
        let summary = try #require(ResultsService.bestSummaries(from: records).first)

        #expect(summary.attemptCount == 1)
        #expect(summary.delta == nil)
        #expect(summary.deltaText == nil)
    }

    // MARK: - Grouping and Refresh

    @Test func multipleWorkoutsAreGroupedIntoOneSummaryEach() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let cindy = makeWorkout(context: context, name: "Cindy", mode: .forTime)
        let fran = makeWorkout(context: context, name: "Fran", mode: .topTime)

        insertRecord(workout: cindy, context: context, daysAgo: 10, rounds: 12, activeTime: 600)
        insertRecord(workout: cindy, context: context, daysAgo: 5, rounds: 15, activeTime: 590)
        insertRecord(workout: fran, context: context, daysAgo: 4, rounds: 1, activeTime: 300)
        insertRecord(workout: fran, context: context, daysAgo: 2, rounds: 1, activeTime: 320)
        insertRecord(workout: fran, context: context, daysAgo: 1, rounds: 1, activeTime: 330)

        let records = service.history(for: nil, window: nil)
        let summaries = ResultsService.bestSummaries(from: records)

        #expect(summaries.count == 2)
        #expect(summaries.map(\.workoutName) == ["Cindy", "Fran"])

        let cindySummary = try #require(summaries.first { $0.workoutName == "Cindy" })
        #expect(cindySummary.attemptCount == 2)
        #expect(cindySummary.bestValue == 15)
        #expect(cindySummary.delta == .equal) // latest is also the best

        let franSummary = try #require(summaries.first { $0.workoutName == "Fran" })
        #expect(franSummary.attemptCount == 3)
        #expect(franSummary.bestValue == 300)
        #expect(franSummary.delta == .regressed(amount: 30))
    }

    @Test func newRecordIsVisibleAfterRefetch() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let workout = makeWorkout(context: context, mode: .forTime)

        insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 10, activeTime: 600)
        try context.save()

        // Simulates the initial @Query fetch.
        let initial = try context.fetch(FetchDescriptor<WorkoutRecord>())
        #expect(ResultsService.bestSummaries(from: initial).first?.attemptCount == 1)

        insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 12, activeTime: 580)
        try context.save()

        // Simulates the next @Query update after the insert.
        let refreshed = try context.fetch(FetchDescriptor<WorkoutRecord>())
        let summary = try #require(ResultsService.bestSummaries(from: refreshed).first)

        #expect(summary.attemptCount == 2)
        #expect(summary.bestValue == 12)
        #expect(summary.latestValue == 12)
        #expect(summary.delta == .equal)
    }

    // MARK: - Best-over-time Chart Data

    @Test func bestSeriesOnlyIncludesNewBests() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .forTime)

        insertRecord(workout: workout, context: context, daysAgo: 10, rounds: 10, activeTime: 600)
        insertRecord(workout: workout, context: context, daysAgo: 8, rounds: 12, activeTime: 590)
        insertRecord(workout: workout, context: context, daysAgo: 6, rounds: 11, activeTime: 580) // not a best
        insertRecord(workout: workout, context: context, daysAgo: 4, rounds: 14, activeTime: 570)
        insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 9, activeTime: 560) // not a best

        let records = service.history(for: workout, window: nil)
        let points = ResultsService.bestSeries(from: records, mode: workout.mode)

        #expect(points.map(\.value) == [10, 12, 14])
        #expect(points.map(\.date) == points.map(\.date).sorted())
    }

    // MARK: - Empty Window and PR History

    @Test func emptyWindowHasNoBestTimeSentinel() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)

        let summary = service.summary(window: ResultsWindow.thirtyDays.dateInterval)

        #expect(summary.workoutsCount == 0)
        #expect(summary.bestTime == nil)
    }

    @Test func deletingPRRecordDoesNotPromoteHistoricalFlag() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .forTime)

        insertRecord(workout: workout, context: context, daysAgo: 10, rounds: 10, activeTime: 600, isPR: true)
        insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 8, activeTime: 580, isPR: false)
        try context.save()

        let allRecords = service.history(for: workout, window: nil)
        let prRecord = try #require(allRecords.first { $0.isPR })
        context.delete(prRecord)
        try context.save()

        let remaining = service.history(for: workout, window: nil)
        #expect(remaining.count == 1)
        #expect(remaining[0].isPR == false)
        #expect(ResultsService.summary(from: remaining).prsThisWindow == 0)
    }

    // MARK: - ResultsWindow

    @Test func windowRawValueRoundTrips() {
        for w in ResultsWindow.allCases {
            #expect(ResultsWindow(rawValue: w.rawValue) == w)
        }
    }

    @Test func allTimeDateIntervalIsNil() {
        #expect(ResultsWindow.allTime.dateInterval == nil)
    }

    @Test func sevenDayIntervalIsApproxCorrect() {
        let interval = ResultsWindow.sevenDays.dateInterval
        #expect(interval != nil)
        let days = interval!.duration / 86400
        #expect(days >= 6.9 && days <= 7.1)
    }

    // MARK: - Shared Default Window

    @Test func sharedStorageKeyAndDefaultAreStable() {
        #expect(ResultsWindow.storageKey == "defaultResultsWindow")
        #expect(ResultsWindow.defaultValue == .thirtyDays)
    }

    @Test func allWindowsRoundTripThroughSharedStorageKey() throws {
        let suiteName = "ResultsWindowTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ResultsWindow.allCases.count == 4)

        for window in ResultsWindow.allCases {
            defaults.set(window.rawValue, forKey: ResultsWindow.storageKey)
            let stored = defaults.string(forKey: ResultsWindow.storageKey)
            #expect(ResultsWindow(storedValue: stored) == window)
        }
    }

    @Test func invalidStoredWindowFallsBackToThirtyDays() throws {
        let suiteName = "ResultsWindowTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ResultsWindow(storedValue: nil) == .thirtyDays)

        defaults.set("not-a-window", forKey: ResultsWindow.storageKey)
        #expect(ResultsWindow(storedValue: defaults.string(forKey: ResultsWindow.storageKey)) == .thirtyDays)

        defaults.removeObject(forKey: ResultsWindow.storageKey)
        #expect(ResultsWindow(storedValue: defaults.string(forKey: ResultsWindow.storageKey)) == .thirtyDays)
    }
}
