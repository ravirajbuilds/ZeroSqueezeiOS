import Foundation

/// Persists the user's Hb calibration points (lab value vs raw estimate)
/// to `Documents/calibration.json` and publishes the fitted correction.
///
/// Also migrates the v1 single-offset calibration (stored on
/// `UserProfile.hbCalibrationOffset`) into an equivalent intercept-only
/// correction so users who calibrated before multi-point fitting shipped
/// keep their anchor.
@MainActor
final class CalibrationStore: ObservableObject {
    static let shared = CalibrationStore()

    @Published private(set) var points: [HbCorrection.Point] = []
    @Published private(set) var correction: HbCorrection = .identity

    /// Carried over from the v1 offset-only calibration. Used only while
    /// `points` is empty; the first real point supersedes it.
    private var legacyOffset: Float?

    private let fileURL: URL
    private let queue = DispatchQueue(label: "zerosqueeze.calibration-store", qos: .utility)

    private struct Snapshot: Codable {
        var points: [HbCorrection.Point]
        var legacyOffset: Float?
    }

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultURL()
        self.fileURL = url
        let snapshot = Self.loadFromDisk(url: url)
        self.points = snapshot?.points ?? []
        self.legacyOffset = snapshot?.legacyOffset
        refit()
    }

    func add(labHb: Float, rawHb: Float) {
        points.append(HbCorrection.Point(id: UUID(), date: Date(), rawHb: rawHb, labHb: labHb))
        refit()
        persist()
    }

    func clear() {
        points.removeAll()
        legacyOffset = nil
        refit()
        persist()
    }

    /// One-time import of the v1 profile offset. No-op once any real
    /// point exists or a legacy offset was already imported.
    func migrateLegacyOffset(_ offset: Float) {
        guard points.isEmpty, legacyOffset == nil else { return }
        legacyOffset = offset
        refit()
        persist()
    }

    private func refit() {
        if points.isEmpty {
            correction = legacyOffset.map {
                HbCorrection(slope: 1, intercept: Double($0))
            } ?? .identity
        } else {
            correction = HbCorrection.fit(points: points)
        }
    }

    // ── persistence ──────────────────────────────────────────────────

    private func persist() {
        let snapshot = Snapshot(points: points, legacyOffset: legacyOffset)
        let url = fileURL
        queue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                ZSLogger.error(.data, "CalibrationStore persist failed", error: error)
            }
        }
    }

    private static func loadFromDisk(url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static func defaultURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("calibration.json")
    }
}
