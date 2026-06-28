import Foundation

/// Persists fused Heart Check readings as JSON in the documents directory.
/// Mirrors `SCGMeasurementStore`.
@MainActor
final class HeartCheckStore: ObservableObject {
    static let shared = HeartCheckStore()

    @Published private(set) var measurements: [HeartCheckMeasurement] = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "zerosqueeze.heartcheck-store", qos: .utility)

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultURL()
        self.fileURL = url
        self.measurements = Self.loadFromDisk(url: url)
    }

    func append(_ measurement: HeartCheckMeasurement) {
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

    var latest: HeartCheckMeasurement? { measurements.first }

    private func persist() {
        let snapshot = measurements
        let url = fileURL
        queue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                ZSLogger.error(.data, "HeartCheckStore persist failed", error: error)
            }
        }
    }

    private static func loadFromDisk(url: URL) -> [HeartCheckMeasurement] {
        StoreDecoding.loadArray(HeartCheckMeasurement.self, from: url)
    }

    private static func defaultURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("heart_checks.json")
    }
}
