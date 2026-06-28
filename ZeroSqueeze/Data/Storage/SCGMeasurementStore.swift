import Foundation

/// Persists the rolling list of `SCGMeasurement` records as JSON in the
/// app's documents directory. Mirrors `MeasurementStore` for fingertip Hb
/// readings; kept separate so the two histories don't have to share a schema.
@MainActor
final class SCGMeasurementStore: ObservableObject {
    static let shared = SCGMeasurementStore()

    @Published private(set) var measurements: [SCGMeasurement] = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "zerosqueeze.scg-store", qos: .utility)

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultURL()
        self.fileURL = url
        self.measurements = Self.loadFromDisk(url: url)
    }

    func append(_ measurement: SCGMeasurement) {
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

    var latest: SCGMeasurement? { measurements.first }

    private func persist() {
        let snapshot = measurements
        let url = fileURL
        queue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                ZSLogger.error(.data, "SCGMeasurementStore persist failed", error: error)
            }
        }
    }

    private static func loadFromDisk(url: URL) -> [SCGMeasurement] {
        StoreDecoding.loadArray(SCGMeasurement.self, from: url)
    }

    private static func defaultURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("scg_measurements.json")
    }
}
