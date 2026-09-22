import Foundation
import SwiftData

struct WindowSummary: Sendable, Equatable {
    var workoutsCount: Int
    var prsThisWindow: Int
    var bestRounds: Int
    var bestTime: TimeInterval   // lowest activeTime for topTime (seconds)
    var avgActiveTime: TimeInterval
}

@MainActor
final class ResultsService {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Fetches history for a specific workout (or all workouts if nil) optionally filtered by date window and kind.
    func history(for workout: Workout? = nil, window: DateInterval? = nil, kind: String? = nil) -> [WorkoutRecord] {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        guard let allRecords = try? context.fetch(descriptor) else { return [] }

        return allRecords.filter { record in
            if let workout = workout, record.workout?.id != workout.id {
                return false
            }
            if let window = window, !window.contains(record.date) {
                return false
            }
            if let kind = kind, record.kind != kind {
                return false
            }
            return true
        }
    }

    /// Computes summary statistics over a date window for a given workout.
    func summary(for workout: Workout? = nil, window: DateInterval? = nil, kind: String? = nil) -> WindowSummary {
        let records = history(for: workout, window: window, kind: kind)
        let prs = records.filter { $0.isPR }
        let bestRounds = records.max(by: { $0.roundsCompleted < $1.roundsCompleted })?.roundsCompleted ?? 0
        let bestTime = records.min(by: { $0.activeTime < $1.activeTime })?.activeTime ?? .greatestFiniteMagnitude
        let avg = records.isEmpty ? 0 : records.reduce(0) { $0 + $1.activeTime } / Double(records.count)

        return WindowSummary(
            workoutsCount: records.count,
            prsThisWindow: prs.count,
            bestRounds: bestRounds,
            bestTime: bestTime,
            avgActiveTime: avg
        )
    }

    /// Returns the best previous performance for a workout before a specific date.
    /// For "rounds", returns highest rounds completed. For "time", returns lowest activeTime.
    func previousBest(for workout: Workout, kind: String, asOf date: Date) -> Double? {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let allRecords = try? context.fetch(descriptor) else { return nil }

        let candidates = allRecords.filter {
            $0.workout?.id == workout.id && $0.date < date && $0.kind == kind
        }

        if kind == "rounds" {
            guard let maxRounds = candidates.max(by: { $0.roundsCompleted < $1.roundsCompleted })?.roundsCompleted else {
                return nil
            }
            return Double(maxRounds)
        } else {
            return candidates.min(by: { $0.activeTime < $1.activeTime })?.activeTime
        }
    }

    /// Determines if a completed workout performance is a new PR.
    static func isNewPR(workout: Workout, kind: String, rounds: Int, activeTime: TimeInterval, before date: Date, in context: ModelContext) -> Bool {
        let service = ResultsService(context: context)
        guard let best = service.previousBest(for: workout, kind: kind, asOf: date) else {
            return true // First attempt is always a PR
        }

        if kind == "rounds" {
            return Double(rounds) > best
        } else {
            return activeTime < best
        }
    }
}
