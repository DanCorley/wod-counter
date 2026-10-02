import Testing
import SwiftData
import Foundation
@testable import WODCounter

@MainActor
struct ResultsViewTests {

    // MARK: - Stored Window Preference

    /// The defect this guards: Settings wrote key "defaultWindow" with tags
    /// "7d"/"30d"/"90d"/"all" while History read "defaultResultsWindow" and
    /// parsed cases "7d"/"30d"/"90d"/"All" — so the preference did nothing, and
    /// even with a matching key "all" would have fallen back to 30 days. Both
    /// screens now tag with `rawValue` and share `ResultsWindow.defaultsKey`.
    @Test func everyWindowRoundTripsThroughItsStoredValue() {
        for window in ResultsWindow.allCases {
            #expect(ResultsWindow(stored: window.rawValue) == window,
                    "\(window.rawValue) must survive a round trip through storage")
        }
    }

    @Test func allTimeIsReachableFromItsStoredValue() {
        // The specific case that used to break: a lowercase "all" tag.
        #expect(ResultsWindow(stored: "All") == .allTime)
        #expect(ResultsWindow(stored: "all") == .thirtyDays, "unknown values fall back")
    }

    @Test func unknownStoredValueFallsBackToTheDefault() {
        #expect(ResultsWindow(stored: "") == ResultsWindow.fallback)
        #expect(ResultsWindow(stored: "nonsense") == ResultsWindow.fallback)
        #expect(ResultsWindow.fallback == .thirtyDays)
    }

    @Test func everyWindowHasADistinctLabelAndTag() {
        let tags = Set(ResultsWindow.allCases.map(\.rawValue))
        let labels = Set(ResultsWindow.allCases.map(\.label))
        #expect(tags.count == ResultsWindow.allCases.count)
        #expect(labels.count == ResultsWindow.allCases.count)
    }

    // MARK: - Helpers

    /// Inserts a WorkoutRecord for the given workout with the given parameters at the specified offset from now.
    @discardableResult
    private func insertRecord(
        workout: Workout,
        context: ModelContext,
        daysAgo: Int,
        rounds: Int,
        activeTime: TimeInterval,
        isPR: Bool = false,
        /// Defaults to a complete effort for the workout's mode, so existing
        /// expectations stay meaningful; pass `.manual` for an abandoned one.
        finishedReason: FinishedReason? = nil
    ) -> WorkoutRecord {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let kind = workout.mode == .forTime ? "rounds" : "time"
        let reason = finishedReason ?? (workout.mode == .forTime ? .clockExpired : .goalReached)
        let record = WorkoutRecord(
            workout: workout,
            date: date,
            kind: kind,
            roundsCompleted: rounds,
            totalReps: rounds * 5,
            elapsedTime: activeTime + 10,
            pausedTime: 10,
            activeTime: activeTime,
            isPR: isPR,
            finishedReason: reason.rawValue
        )
        context.insert(record)
        return record
    }

    private func makeWorkout(context: ModelContext, mode: ExecutionMode = .forTime) -> Workout {
        let movement = Movement(name: "Air Squat", equipment: nil, category: "Gymnastics", iconName: nil)
        context.insert(movement)
        let exercise = Exercise(movement: movement, reps: 15, displayLabel: "15 Air Squats")
        context.insert(exercise)
        let block = RoundBlock(repeatTimes: 0)
        block.exercises = [exercise]
        context.insert(block)
        let workout = Workout(
            name: "Test WOD",
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

    // MARK: - Abandoned attempts must not become the best

    /// Found by manual testing: PR *detection* was gated on completing the
    /// work, but the displayed "best" still took min(activeTime) over every
    /// record — so an abandoned 5-second attempt showed as the best time on
    /// the history screen while the PR flag correctly sat on the completed
    /// attempt. Same rule, two code paths, only one was fixed.
    @Test func abandonedAttemptIsNotTheBestTime() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .topTime)

        insertRecord(workout: workout, context: context, daysAgo: 5,
                     rounds: 3, activeTime: 240, isPR: true)
        // Gave up after 5 seconds: faster, but not a comparable effort.
        insertRecord(workout: workout, context: context, daysAgo: 1,
                     rounds: 0, activeTime: 5, finishedReason: .manual)

        let best = service.best(for: workout, window: nil)
        #expect(best?.activeTime == 240, "An abandoned attempt must not be the best")

        let summary = service.summary(for: workout)
        #expect(summary.bestTime == 240, "The summary banner must agree")
    }

    @Test func manuallyStoppedAMRAPIsNotTheBestRounds() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .forTime)

        insertRecord(workout: workout, context: context, daysAgo: 5,
                     rounds: 12, activeTime: 1200, isPR: true)
        // Stopped early, so fewer rounds — but also not comparable even if more.
        insertRecord(workout: workout, context: context, daysAgo: 1,
                     rounds: 20, activeTime: 400, finishedReason: .manual)

        let best = service.best(for: workout, window: nil)
        #expect(best?.roundsCompleted == 12, "An early stop must not be the best rounds")
        #expect(service.summary(for: workout).bestRounds == 12)
    }

    @Test func aWorkoutWithOnlyAbandonedAttemptsHasNoBest() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .topTime)

        insertRecord(workout: workout, context: context, daysAgo: 1,
                     rounds: 0, activeTime: 5, finishedReason: .manual)

        #expect(service.best(for: workout, window: nil) == nil)
        // History still lists the attempt — it happened, it just isn't ranked.
        #expect(service.history(for: workout).count == 1)
    }

    // MARK: - Incomplete attempt labelling

    @Test func manuallyStoppedAttemptIsLabelledIncomplete() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let workout = makeWorkout(context: context, mode: .topTime)

        let record = insertRecord(workout: workout, context: context, daysAgo: 1,
                                  rounds: 0, activeTime: 5, finishedReason: .manual)
        record.totalReps = 2
        record.repsQuota = 90

        #expect(record.wasStoppedEarly)
        #expect(record.completionSummary == "2 of 90 reps")
        #expect(record.completionFraction == 2.0 / 90.0)
    }

    @Test func completedAttemptsAreNotLabelledIncomplete() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let topTime = makeWorkout(context: context, mode: .topTime)
        let forTime = makeWorkout(context: context, mode: .forTime)

        let finished = insertRecord(workout: topTime, context: context, daysAgo: 1,
                                    rounds: 3, activeTime: 240, finishedReason: .goalReached)
        let capped = insertRecord(workout: forTime, context: context, daysAgo: 1,
                                  rounds: 12, activeTime: 1200, finishedReason: .clockExpired)

        #expect(finished.wasStoppedEarly == false)
        #expect(capped.wasStoppedEarly == false)
    }

    /// A record written before finishedReason existed has unknown provenance.
    /// It must not be ranked, but it must also not be asserted as incomplete.
    @Test func legacyRecordIsNeitherRankableNorLabelledIncomplete() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let workout = makeWorkout(context: context, mode: .topTime)

        let legacy = WorkoutRecord(
            workout: workout, date: Date(), kind: "time",
            roundsCompleted: 3, totalReps: 90, elapsedTime: 300,
            pausedTime: 0, activeTime: 300, isPR: false
        )
        context.insert(legacy)

        #expect(legacy.finishedReason == nil)
        #expect(legacy.isRankable == false)
        #expect(legacy.wasStoppedEarly == false, "Unknown is not the same as incomplete")
        #expect(legacy.completionSummary == nil)
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

        // Calls the production selection rather than reimplementing max() here,
        // which is what let the "best" bug through in the first place.
        #expect(service.best(for: workout, window: nil)?.roundsCompleted == 15)
    }

    @Test func bestTopTimeIsLowestActiveTime() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .topTime)

        insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 1, activeTime: 600)
        insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 1, activeTime: 450)
        insertRecord(workout: workout, context: context, daysAgo: 10, rounds: 1, activeTime: 720)

        #expect(service.best(for: workout, window: nil)?.activeTime == 450)
    }

    // MARK: - Delta Computation

    @Test func deltaForTimePositive() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .forTime)

        let r1 = insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 10, activeTime: 600)
        let r2 = insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 13, activeTime: 580)

        let records = service.history(for: workout, window: nil)
        let best = records.max(by: { $0.roundsCompleted < $1.roundsCompleted })
        let others = records.filter { $0.id != best?.id }
        let prevBest = others.max(by: { $0.roundsCompleted < $1.roundsCompleted })

        #expect(best?.id == r2.id)
        #expect(prevBest?.id == r1.id)
        #expect((best?.roundsCompleted ?? 0) - (prevBest?.roundsCompleted ?? 0) == 3)
    }

    @Test func deltaTopTimeNegativeIsImprovement() throws {
        let container = Container.inMemory()
        let context = ModelContext(container)
        let service = ResultsService(context: context)
        let workout = makeWorkout(context: context, mode: .topTime)

        let r1 = insertRecord(workout: workout, context: context, daysAgo: 5, rounds: 1, activeTime: 700)
        let r2 = insertRecord(workout: workout, context: context, daysAgo: 1, rounds: 1, activeTime: 550)

        let records = service.history(for: workout, window: nil)
        let best = records.min(by: { $0.activeTime < $1.activeTime })
        let others = records.filter { $0.id != best?.id }
        let prevBest = others.min(by: { $0.activeTime < $1.activeTime })

        #expect(best?.id == r2.id)
        #expect(prevBest?.id == r1.id)
        // Δ = prevBest.activeTime - best.activeTime (positive means improvement)
        let delta = (prevBest?.activeTime ?? 0) - (best?.activeTime ?? 0)
        #expect(delta == 150)
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
}
