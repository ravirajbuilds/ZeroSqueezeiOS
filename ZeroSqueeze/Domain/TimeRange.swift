import Foundation

/// Trends time-range filter. `all` keeps everything; the others cut off at
/// a fixed number of days before `now`. Cutoff logic is pure so it can be
/// unit-tested without a view.
enum TimeRange: String, CaseIterable, Identifiable {
    case week = "7D"
    case month = "30D"
    case all = "All"

    var id: String { rawValue }

    /// Days retained, or nil for "all".
    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .all: return nil
        }
    }

    /// Earliest timestamp included, or nil when unbounded.
    func cutoff(now: Date, calendar: Calendar = .current) -> Date? {
        guard let days else { return nil }
        return calendar.date(byAdding: .day, value: -days, to: now)
    }

    /// Filter timestamped items to this range.
    func filter<T>(_ items: [T], now: Date, timestamp: (T) -> Date, calendar: Calendar = .current) -> [T] {
        guard let cutoff = cutoff(now: now, calendar: calendar) else { return items }
        return items.filter { timestamp($0) >= cutoff }
    }
}
