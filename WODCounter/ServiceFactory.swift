import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ServiceFactory {
    let context: ModelContext

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
            let isPR = ResultsService.isNewPR(
                workout: workout,
                kind: record.kind,
                rounds: record.roundsCompleted,
                activeTime: record.activeTime,
                before: record.date,
                in: self.context
            )
            record.isPR = isPR
            self.context.insert(record)
            try? self.context.save()
        }
    }
}
