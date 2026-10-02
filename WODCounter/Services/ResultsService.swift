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

        // Only complete efforts set the bar — otherwise a partial attempt's
        // fast-but-unearned time becomes the record to beat.
        let candidates = allRecords.filter {
            $0.workout?.id == workout.id && $0.date < date && $0.kind == kind
                && Self.isPREligible(kind: $0.kind, finishedReason: $0.finishedReason)
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

    /// Re-marks `isPR` across a workout's whole history.
    ///
    /// Needed after a deletion: removing the record that held the PR would
    /// otherwise leave the workout with nothing starred, and removing an early
    /// weak attempt can make a later one newly best. Walks the records oldest
    /// first and stars each one that beat everything eligible before it, which
    /// reproduces what the live PR check would have decided at the time.
    func recomputePRs(for workout: Workout) {
        let ordered = history(for: workout).sorted { $0.date < $1.date }

        var bestRounds: Int?
        var bestTime: TimeInterval?

        for record in ordered {
            guard Self.isPREligible(kind: record.kind, finishedReason: record.finishedReason) else {
                record.isPR = false
                continue
            }

            if record.kind == "rounds" {
                let isBest = bestRounds.map { record.roundsCompleted > $0 } ?? true
                record.isPR = isBest
                if isBest { bestRounds = record.roundsCompleted }
            } else {
                let isBest = bestTime.map { record.activeTime < $0 } ?? true
                record.isPR = isBest
                if isBest { bestTime = record.activeTime }
            }
        }
    }

    /// Whether a finish is eligible to be ranked as a PR at all.
    ///
    /// A time PR means the athlete did the prescribed work — "Fran 2:30" is
    /// meaningless if only half the reps were logged, and ranking a partial on
    /// time alone produces a faster-for-less-work record that can never be
    /// beaten. A rounds PR requires the clock to have run its full course, for
    /// the same reason: stopping at 8:00 of a 20-minute AMRAP is not a
    /// comparable effort. Manual finishes are never PRs.
    static func isPREligible(kind: String, finishedReason: String?) -> Bool {
        switch kind {
        case "time":   return finishedReason == FinishedReason.goalReached.rawValue
        case "rounds": return finishedReason == FinishedReason.clockExpired.rawValue
        default:       return false
        }
    }

    /// Determines if a completed workout performance is a new PR.
    static func isNewPR(workout: Workout, kind: String, rounds: Int, activeTime: TimeInterval,
                        before date: Date, finishedReason: String?, in context: ModelContext) -> Bool {
        guard isPREligible(kind: kind, finishedReason: finishedReason) else { return false }

        let service = ResultsService(context: context)
        guard let best = service.previousBest(for: workout, kind: kind, asOf: date) else {
            return true // First complete attempt sets the bar.
        }

        if kind == "rounds" {
            return Double(rounds) > best
        } else {
            return activeTime < best
        }
    }
}
