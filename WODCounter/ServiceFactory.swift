import Foundation
import SwiftData
import SwiftUI

import Observation

@Observable
@MainActor
final class ServiceFactory {
    let context: ModelContext

    /// Set when a finished workout could not be persisted, so the UI can tell
    /// the athlete instead of silently losing the session they just did.
    var saveFailureMessage: String?

    init(_ container: ModelContainer) {
        self.context = container.mainContext
    }

    init(context: ModelContext) {
        self.context = context
    }

    func makeTimerService(
        for workout: Workout,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) -> WorkoutTimerService {
        WorkoutTimerService(workout: workout, clock: clock) { [weak self] record in
            guard let self = self else { return }
            record.isPR = ResultsService.isNewPR(
                workout: workout,
                kind: record.kind,
                rounds: record.roundsCompleted,
                activeTime: record.activeTime,
                before: record.date,
                finishedReason: record.finishedReason,
                in: self.context
            )
            self.context.insert(record)
            do {
                try self.context.save()
            } catch {
                // Losing a finished workout silently is the worst outcome here:
                // the result is the whole point of the session.
                self.context.rollback()
                self.saveFailureMessage = "Couldn't save your workout result: \(error.localizedDescription)"
            }
        }
    }
}
