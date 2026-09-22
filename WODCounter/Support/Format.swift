import Foundation

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    static func timer(_ minutes: Int) -> String {
        return "\(minutes):00"
    }
}
