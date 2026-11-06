import Foundation

/// Wall-clock timeline for a single workout session.
///
/// Time is derived from timestamps supplied by the owning service's injected
/// clock, so a delayed or suspended ticker can never lose elapsed time. Paused
/// intervals are accumulated separately and subtracted from wall time to get
/// active time.
struct SessionTimeline: Equatable, Sendable {
    private(set) var startedAt: Date?
    private(set) var pauseStartedAt: Date?
    private(set) var accumulatedPaused: TimeInterval = 0
    private(set) var finishedAt: Date?

    var hasStarted: Bool { startedAt != nil }
    var isFinished: Bool { finishedAt != nil }
    var isPaused: Bool { pauseStartedAt != nil }
    var isActive: Bool { startedAt != nil && pauseStartedAt == nil && finishedAt == nil }

    mutating func start(at date: Date) {
        guard startedAt == nil else { return }
        startedAt = date
        pauseStartedAt = nil
        accumulatedPaused = 0
        finishedAt = nil
    }

    mutating func pause(at date: Date) {
        guard isActive else { return }
        pauseStartedAt = date
    }

    mutating func resume(at date: Date) {
        guard let pauseStartedAt else { return }
        accumulatedPaused += max(0, date.timeIntervalSince(pauseStartedAt))
        self.pauseStartedAt = nil
    }

    /// Freezes the timeline at the finish moment, folding any open pause into
    /// the accumulated total.
    mutating func finish(at date: Date) {
        guard startedAt != nil, finishedAt == nil else { return }
        if let pauseStartedAt {
            accumulatedPaused += max(0, date.timeIntervalSince(pauseStartedAt))
            self.pauseStartedAt = nil
        }
        finishedAt = date
    }

    func wallElapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let end = finishedAt ?? now
        return max(0, end.timeIntervalSince(startedAt))
    }

    func pausedElapsed(at now: Date) -> TimeInterval {
        var paused = accumulatedPaused
        if let pauseStartedAt {
            let end = finishedAt ?? now
            paused += max(0, end.timeIntervalSince(pauseStartedAt))
        }
        return paused
    }

    func activeElapsed(at now: Date) -> TimeInterval {
        max(0, wallElapsed(at: now) - pausedElapsed(at: now))
    }
}
