import Foundation

/// PHRM-style daily resting-heart-rate aggregation over scg-scan
/// measurements: confidence-gate individual readings, group by calendar
/// day, then take the mean of the lowest quartile as that day's RHR —
/// robust to post-exercise spikes without collapsing to a single noisy
/// minimum.
enum RestingHeartRate {

    struct Daily: Identifiable, Equatable {
        /// Start of day.
        let day: Date
        /// Resting heart rate estimate, bpm.
        let rhr: Double
        /// Number of gated readings that contributed.
        let readingCount: Int

        var id: Date { day }
    }

    /// Readings below this quality are excluded entirely.
    static let minQuality: Float = 0.4

    /// Daily RHR series, oldest first.
    static func daily(
        from measurements: [SCGMeasurement],
        minQuality: Float = RestingHeartRate.minQuality,
        calendar: Calendar = .current
    ) -> [Daily] {
        let gated = measurements.filter {
            $0.signalQuality >= minQuality && $0.heartRateBpm != nil
        }
        let byDay = Dictionary(grouping: gated) {
            calendar.startOfDay(for: $0.timestamp)
        }
        return byDay.map { day, readings in
            let bpms = readings.compactMap { $0.heartRateBpm.map(Double.init) }.sorted()
            // Mean of the lowest quartile, but never fewer than 2 readings when
            // ≥2 exist — a single-element "quartile" just re-exposes the noisy
            // minimum the quartile rule is meant to suppress.
            let quartileCount = min(bpms.count, max(bpms.count >= 2 ? 2 : 1, bpms.count / 4))
            let lowest = bpms.prefix(quartileCount)
            let rhr = lowest.reduce(0, +) / Double(lowest.count)
            return Daily(day: day, rhr: rhr, readingCount: bpms.count)
        }
        .sorted { $0.day < $1.day }
    }

    /// Most recent day's RHR, if any reading survived gating.
    static func latest(
        from measurements: [SCGMeasurement],
        calendar: Calendar = .current
    ) -> Daily? {
        daily(from: measurements, calendar: calendar).last
    }
}
