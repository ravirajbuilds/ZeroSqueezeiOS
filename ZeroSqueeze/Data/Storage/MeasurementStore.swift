import Foundation

/// Persists the rolling list of `Measurement` records as JSON in the
/// app's documents directory.
///
/// `@MainActor`-isolated: it publishes `@Published measurements`, and SwiftUI
/// observation requires those mutations on the main thread. Disk I/O is hopped
/// off-main onto `queue`; only the in-memory array + publish stay on main.
@MainActor
final class MeasurementStore: ObservableObject {
    static let shared = MeasurementStore()

    @Published private(set) var measurements: [HbMeasurement] = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "zerosqueeze.measurement-store", qos: .utility)

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultURL()
        self.fileURL = url
        self.measurements = Self.loadFromDisk(url: url)
    }

    func append(_ measurement: HbMeasurement) {
        measurements.insert(measurement, at: 0)
        persist()
    }

    func remove(id: UUID) {
        measurements.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        measurements.removeAll()
        persist()
    }

    var latest: HbMeasurement? { measurements.first }

    // ── persistence ──────────────────────────────────────────────────

    private func persist() {
        let snapshot = measurements
        let url = fileURL
        queue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                // .completeFileProtection: health data is unreadable while the
                // device is locked. Writes only happen in the foreground (the
                // capture flow cancels on background), so this never blocks us.
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                ZSLogger.error(.data, "MeasurementStore persist failed", error: error)
            }
        }
    }

    private static func loadFromDisk(url: URL) -> [HbMeasurement] {
        StoreDecoding.loadArray(HbMeasurement.self, from: url)
    }

    private static func defaultURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("measurements.json")
    }
}
