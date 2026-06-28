import Foundation

/// Persists daily `CheckIn` entries as JSON in the app's documents directory.
/// Mirrors `SCGMeasurementStore`, but enforces one entry per calendar day:
/// `upsert` replaces an existing same-day entry rather than appending.
@MainActor
final class CheckInStore: ObservableObject {
    static let shared = CheckInStore()

    /// Newest first.
    @Published private(set) var entries: [CheckIn] = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "zerosqueeze.checkin-store", qos: .utility)
    private let calendar: Calendar

    init(fileURL: URL? = nil, calendar: Calendar = .current) {
        let url = fileURL ?? Self.defaultURL()
        self.fileURL = url
        self.calendar = calendar
        self.entries = Self.loadFromDisk(url: url)
    }

    /// Insert or replace the entry for its calendar day, then sort newest-first.
    func upsert(_ entry: CheckIn) {
        let day = calendar.startOfDay(for: entry.day)
        entries.removeAll { calendar.startOfDay(for: $0.day) == day }
        entries.append(entry)
        entries.sort { $0.day > $1.day }
        persist()
    }

    /// The entry describing `date`'s calendar day, if any.
    func entry(on date: Date) -> CheckIn? {
        let day = calendar.startOfDay(for: date)
        return entries.first { calendar.startOfDay(for: $0.day) == day }
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        let snapshot = entries
        let url = fileURL
        queue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                ZSLogger.error(.data, "CheckInStore persist failed", error: error)
            }
        }
    }

    private static func loadFromDisk(url: URL) -> [CheckIn] {
        StoreDecoding.loadArray(CheckIn.self, from: url)
    }

    private static func defaultURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("check_ins.json")
    }
}
