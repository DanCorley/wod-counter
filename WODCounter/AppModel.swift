import Foundation
import SwiftUI
import SwiftData

@Observable
final class AppModel {
    var pendingStart: Workout?
    var results: ResultsService

    @MainActor
    init(factory: ServiceFactory) {
        self.results = ResultsService(context: factory.context)
    }

    @MainActor
    init(context: ModelContext) {
        self.results = ResultsService(context: context)
    }

    func startWorkout(_ workout: Workout) {
        self.pendingStart = workout
    }
}
