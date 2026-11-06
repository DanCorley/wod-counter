import Foundation
import SwiftData

struct WindowSummary: Sendable, Equatable {
    var workoutsCount: Int
    var prsThisWindow: Int
    var bestRounds: Int
    /// Lowest active time for top-time records, or `nil` when the window has no records.
    var bestTime: TimeInterval?
    var avgActiveTime: TimeInterval
}

/// One point in a best-over-time series.
struct BestSeriesPoint: Identifiable, Equatable, Sendable {
    let recordID: UUID
    let date: Date
    let value: Double

    var id: UUID { recordID }
}

/// Best attempt and latest attempt for one workout within a window.
///
/// The delta is always relative to the latest chronological attempt:
/// a positive regression means fewer rounds (`.forTime`) or more seconds
/// (`.topTime`) than the best attempt. A latest attempt that equals the best
/// produces `.equal`; a single attempt produces no delta at all.
struct WorkoutBestSummary: Identifiable, Equatable {
    enum Delta: Equatable {
        case equal
        case regressed(amount: Double)

        func text(for mode: ExecutionMode) -> String {
            switch self {
            case .equal:
                return "="
            case .regressed(let amount):
                switch mode {
                case .forTime:
                    return "−\(Int(amount.rounded())) rds"
                case .topTime:
                    return "+\(Format.duration(amount))"
                }
            }
        }
    }

    let workoutID: PersistentIdentifier
    let workoutName: String
    let mode: ExecutionMode
    let attemptCount: Int
    let bestValue: Double
    let latestValue: Double
    let bestDate: Date
    let latestDate: Date
    let hasPR: Bool

    var id: PersistentIdentifier { workoutID }

    var bestMetricText: String {
        switch mode {
        case .forTime:
            return "\(Int(bestValue)) rds"
        case .topTime:
            return Format.duration(bestValue)
        }
    }

    /// Reported only when there is more than one attempt.
    var delta: Delta? {
        guard attemptCount > 1 else { return nil }

        let regression: Double
        switch mode {
        case .forTime:
            regression = bestValue - latestValue
        case .topTime:
            regression = latestValue - bestValue
        }

        // Sub-second differences are noise for time-based workouts; round differences are exact.
        if abs(regression) < 1 { return .equal }
        return .regressed(amount: abs(regression))
    }

    var deltaText: String? {
        delta?.text(for: mode)
    }
}

@MainActor
final class ResultsService {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Filtering

    /// Filters an already-fetched record set without touching the context.
    /// Views use this so one `@Query` fetch can serve a whole render.
    static func filter(
        _ records: [WorkoutRecord],
        workout: Workout? = nil,
        window: DateInterval? = nil,
        kind: String? = nil
    ) -> [WorkoutRecord] {
        records.filter { record in
            if let workout, record.workout?.persistentModelID != workout.persistentModelID {
                return false
            }
            if let window, !window.contains(record.date) {
                return false
            }
            if let kind, record.kind != kind {
                return false
            }
            return true
        }
    }

    /// Fetches history for a specific workout (or all workouts if nil) optionally filtered by date window and kind.
    func history(for workout: Workout? = nil, window: DateInterval? = nil, kind: String? = nil) -> [WorkoutRecord] {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        guard let allRecords = try? context.fetch(descriptor) else { return [] }
        return Self.filter(allRecords, workout: workout, window: window, kind: kind)
    }

    // MARK: - Metrics

    /// The metric that ranks a record for its workout mode.
    static func metric(for record: WorkoutRecord, mode: ExecutionMode) -> Double {
        switch mode {
        case .forTime:
            return Double(record.roundsCompleted)
        case .topTime:
            return record.activeTime
        }
    }

    /// Whether `lhs` is a better metric than `rhs` for the given mode.
    static func isBetter(_ lhs: Double, than rhs: Double, mode: ExecutionMode) -> Bool {
        switch mode {
        case .forTime:
            return lhs > rhs
        case .topTime:
            return lhs < rhs
        }
    }

    // MARK: - Bests

    /// Groups records by workout and returns one best/latest summary per workout.
    /// Records are expected to have already been filtered to the desired window.
    static func bestSummaries(from records: [WorkoutRecord]) -> [WorkoutBestSummary] {
        var groups: [PersistentIdentifier: [WorkoutRecord]] = [:]
        for record in records {
            guard let workout = record.workout else { continue }
            groups[workout.persistentModelID, default: []].append(record)
        }

        return groups.compactMap { _, group -> WorkoutBestSummary? in
            guard let workout = group.first?.workout else { return nil }
            let mode = workout.mode
            let chronological = group.sorted { $0.date < $1.date }
            guard let latest = chronological.last else { return nil }

            let best = chronological.max { lhs, rhs in
                isBetter(metric(for: rhs, mode: mode), than: metric(for: lhs, mode: mode), mode: mode)
            } ?? latest

            return WorkoutBestSummary(
                workoutID: workout.persistentModelID,
                workoutName: workout.name,
                mode: mode,
                attemptCount: group.count,
                bestValue: metric(for: best, mode: mode),
                latestValue: metric(for: latest, mode: mode),
                bestDate: best.date,
                latestDate: latest.date,
                hasPR: group.contains { $0.isPR }
            )
        }
        .sorted { $0.workoutName.localizedStandardCompare($1.workoutName) == .orderedAscending }
    }

    /// Builds a best-over-time series. A point is emitted only when an attempt
    /// improves on the best seen so far, so the chart reflects progression.
    static func bestSeries(from records: [WorkoutRecord], mode: ExecutionMode) -> [BestSeriesPoint] {
        let chronological = records.sorted { $0.date < $1.date }
        var currentBest: Double?
        var points: [BestSeriesPoint] = []

        for record in chronological {
            let value = metric(for: record, mode: mode)
            let improved = currentBest.map { isBetter(value, than: $0, mode: mode) } ?? true
            guard improved else { continue }
            currentBest = value
            points.append(BestSeriesPoint(recordID: record.id, date: record.date, value: value))
        }

        return points
    }

    // MARK: - Summary

    /// Computes summary statistics over a date window for a given workout.
    func summary(for workout: Workout? = nil, window: DateInterval? = nil, kind: String? = nil) -> WindowSummary {
        Self.summary(from: history(for: workout, window: window, kind: kind))
    }

    /// Computes summary statistics from an already-fetched record set.
    static func summary(from records: [WorkoutRecord]) -> WindowSummary {
        let prs = records.filter { $0.isPR }
        let bestRounds = records.max(by: { $0.roundsCompleted < $1.roundsCompleted })?.roundsCompleted ?? 0
        let bestTime = records.min(by: { $0.activeTime < $1.activeTime })?.activeTime
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
            $0.workout?.persistentModelID == workout.persistentModelID && $0.date < date && $0.kind == kind
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
