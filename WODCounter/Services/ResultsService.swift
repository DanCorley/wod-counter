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

    /// History filtered to attempts that may be ranked — see
    /// `WorkoutRecord.isRankable`. Use this for anything that compares results;
    /// use `history` for anything that merely lists them.
    func rankableHistory(for workout: Workout? = nil, window: DateInterval? = nil, kind: String? = nil) -> [WorkoutRecord] {
        history(for: workout, window: window, kind: kind).filter(\.isRankable)
    }

    /// The best ranked attempt for a workout: most rounds for for-time, lowest
    /// active time for top-time. `nil` when nothing is rankable yet.
    ///
    /// Exists so the views and the summary share one implementation. Each
    /// previously reimplemented the min/max inline, and they disagreed about
    /// whether abandoned attempts counted.
    func best(for workout: Workout, window: DateInterval? = nil) -> WorkoutRecord? {
        let records = rankableHistory(for: workout, window: window)
        if workout.mode == .forTime {
            return records.max(by: { $0.roundsCompleted < $1.roundsCompleted })
        } else {
            return records.min(by: { $0.activeTime < $1.activeTime })
        }
    }

    /// Computes summary statistics over a date window for a given workout.
    func summary(for workout: Workout? = nil, window: DateInterval? = nil, kind: String? = nil) -> WindowSummary {
        let records = history(for: workout, window: window, kind: kind)
        let prs = records.filter { $0.isPR }

        // Bests and the average describe comparable efforts only; an abandoned
        // attempt's fast time is not a result anyone achieved.
        let ranked = records.filter(\.isRankable)
        let bestRounds = ranked.max(by: { $0.roundsCompleted < $1.roundsCompleted })?.roundsCompleted ?? 0
        let bestTime = ranked.min(by: { $0.activeTime < $1.activeTime })?.activeTime ?? .greatestFiniteMagnitude
        let avg = ranked.isEmpty ? 0 : ranked.reduce(0) { $0 + $1.activeTime } / Double(ranked.count)

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
            $0.workout?.id == workout.id && $0.date < date && $0.kind == kind && $0.isRankable
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
            guard record.isRankable else {
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

    /// Whether a finish is eligible to be ranked, for a result that is not yet
    /// a `WorkoutRecord`. Mirrors `WorkoutRecord.isRankable`, which is the
    /// definition of the rule; this overload exists only because `isNewPR` is
    /// asked about a prospective result.
    ///
    /// A time is comparable only if the prescribed work was completed — "Fran
    /// 2:30" is meaningless if half the reps were skipped, and ranking a
    /// partial on time alone creates a faster-for-less-work record that can
    /// never be beaten. A round count is comparable only if the clock ran its
    /// full course: stopping at 8:00 of a 20-minute AMRAP is not the same
    /// effort. A manual stop is neither.
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
