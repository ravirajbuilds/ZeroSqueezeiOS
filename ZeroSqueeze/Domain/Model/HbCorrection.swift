import Foundation

/// Linear personal correction applied to the raw (population-model) Hb
/// estimate: corrected = slope * raw + intercept.
///
/// Fitted from user-entered lab values via `HbCorrection.fit`. With a
/// single point the fit collapses to a pure offset; with two or more it
/// is a ridge regression pulled toward identity (slope 1, intercept 0)
/// so a couple of noisy lab entries can't produce a wild line.
struct HbCorrection: Codable, Equatable {
    var slope: Double
    var intercept: Double

    static let identity = HbCorrection(slope: 1, intercept: 0)

    var isCalibrated: Bool { self != .identity }

    func apply(_ raw: Double) -> Double { slope * raw + intercept }

    /// One calibration sample: what the model said (raw, pre-correction)
    /// vs what the lab measured.
    struct Point: Codable, Equatable, Identifiable {
        let id: UUID
        let date: Date
        /// Raw estimate at calibration time, g/dL (before any correction).
        let rawHb: Float
        /// Lab-verified Hb, g/dL.
        let labHb: Float
    }

    /// Ridge fit toward identity. `lambda` is the prior strength in
    /// (g/dL)² units — larger means lab points must agree harder before
    /// the slope moves away from 1.
    static func fit(points: [Point], lambda: Double = 2.0) -> HbCorrection {
        guard !points.isEmpty else { return .identity }

        if points.count == 1 {
            let p = points[0]
            return HbCorrection(
                slope: 1,
                intercept: clamp(Double(p.labHb - p.rawHb), -5, 5)
            )
        }

        let xs = points.map { Double($0.rawHb) }
        let ys = points.map { Double($0.labHb) }
        let n = Double(points.count)
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n

        var sxx = 0.0
        var sxy = 0.0
        for i in 0..<points.count {
            sxx += (xs[i] - mx) * (xs[i] - mx)
            sxy += (xs[i] - mx) * (ys[i] - my)
        }

        // Ridge toward slope = 1: b = (Sxy + λ) / (Sxx + λ). As Sxx → 0
        // (all raws identical), b → 1 and the fit degrades gracefully to
        // an offset; as evidence accumulates, the data dominates.
        let slope = clamp((sxy + lambda) / (sxx + lambda), 0.5, 1.5)
        let intercept = clamp(my - slope * mx, -5, 5)
        return HbCorrection(slope: slope, intercept: intercept)
    }
}

@inline(__always)
private func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    min(max(v, lo), hi)
}
