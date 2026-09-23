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
