import Foundation

enum ExecutionMode: String, Codable, CaseIterable, Sendable {
    case forTime
    case topTime

    var title: String { self == .forTime ? "For Time" : "Top Time" }
    var symbol: String { self == .forTime ? "timer" : "flag.checkered" }
}
