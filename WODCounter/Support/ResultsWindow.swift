import Foundation

/// The time window used by the History screen.
///
/// This is the single source of truth for both the stored default in Settings
/// and the window selected in Results. Persist it through `storageKey` so both
/// screens read and write the same preference.
enum ResultsWindow: String, CaseIterable, Identifiable {
    case sevenDays  = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case allTime    = "All"

    /// Shared `@AppStorage` key for the default results window.
    static let storageKey = "defaultResultsWindow"

    /// Fallback used when nothing is stored or the stored value is invalid.
    static let defaultValue: ResultsWindow = .thirtyDays

    var id: String { rawValue }

    /// Resolves a stored raw value, falling back safely to `.thirtyDays`.
    init(storedValue: String?) {
        if let storedValue, let window = ResultsWindow(rawValue: storedValue) {
            self = window
        } else {
            self = .defaultValue
        }
    }

    var dateInterval: DateInterval? {
        let now = Date()
        switch self {
        case .sevenDays:  return DateInterval(start: Calendar.current.date(byAdding: .day, value: -7, to: now)!, end: now)
        case .thirtyDays: return DateInterval(start: Calendar.current.date(byAdding: .day, value: -30, to: now)!, end: now)
        case .ninetyDays: return DateInterval(start: Calendar.current.date(byAdding: .day, value: -90, to: now)!, end: now)
        case .allTime:    return nil
        }
    }

    var label: String {
        switch self {
        case .sevenDays:  return "Past 7 days"
        case .thirtyDays: return "Past 30 days"
        case .ninetyDays: return "Past 90 days"
        case .allTime:    return "All time"
        }
    }

    /// Labels used by the Settings picker.
    var settingsLabel: String {
        switch self {
        case .sevenDays:  return "Past 7 Days"
        case .thirtyDays: return "Past 30 Days"
        case .ninetyDays: return "Past 90 Days"
        case .allTime:    return "All Time"
        }
    }
}
