import Foundation

enum FinishedReason: String, Codable, CaseIterable, Sendable {
    case clockExpired
    case goalReached
    case manual
}

enum TimerEvent: Sendable, Equatable {
    case none
    case blockCompleted
    case finished(FinishedReason)
}