import Foundation

/// SCG-only blood-pressure estimation from systolic time intervals.
///
/// Computational-physiology model. Left-ventricular ejection time (LVET, the
/// AO→AC span from the SCG) co-varies with stroke volume, heart rate and
/// arterial load. Weissler's classic relation gives a rate-corrected expected
/// LVET; the *deviation* of the measured LVET from that expectation, together
/// with heart rate, maps onto blood pressure: a shorter-than-expected ejection
/// at a given rate accompanies higher afterload (higher pressure).
///
/// This is an index calibrated to population means, NOT a cuff measurement.
/// Absolute numbers are anchored to a normotensive reference and the model
/// reports a band, never a single confident value. The UI says as much.
enum BloodPressureEstimator {

    struct Estimate: Equatable {
        let systolicMmHg: Double
        let diastolicMmHg: Double
        /// Confidence in [0, 1], driven by SCG signal quality + beat count.
        let confidence: Double
    }

    /// Weissler regression: expected male LVET (ms) ≈ −1.7·HR + 413.
    /// Female intercept runs ~5 ms longer. We use a gender-agnostic mean.
    static func expectedLVET(hrBpm: Double) -> Double {
        416.0 - 1.7 * hrBpm
    }

    /// Reference normotensive anchors.
    private static let refSystolic = 118.0
    private static let refDiastolic = 76.0
    /// mmHg per ms of LVET shortening below the rate-corrected expectation.
    /// Tuned so a physiologic ±40 ms swing spans roughly ±18 mmHg systolic.
    private static let systolicGainPerMs = 0.45
    private static let diastolicGainPerMs = 0.28
    /// mmHg added per bpm above a 60 bpm resting reference (tachycardia tends
    /// to track elevated pressure in ambulatory data).
    private static let rateGain = 0.25

    /// Estimate from an LVET (ms) and heart rate (bpm). Returns nil when LVET
    /// is absent or heart rate is implausible.
    static func estimate(lvetMs: Double?, hrBpm: Int?, signalQuality: Double, beatCount: Int) -> Estimate? {
        guard let lvet = lvetMs, let hr = hrBpm, (35...200).contains(hr) else { return nil }
        let hrD = Double(hr)
        // Negative `shortfall` = ejection shorter than expected ⇒ higher load.
        let shortfall = expectedLVET(hrBpm: hrD) - lvet
        let rateTerm = rateGain * (hrD - 60)

        var sys = refSystolic + systolicGainPerMs * shortfall + rateTerm
        var dia = refDiastolic + diastolicGainPerMs * shortfall + 0.4 * rateTerm
        // Clamp to a sane physiological display range.
        sys = min(max(sys, 85), 185)
        dia = min(max(dia, 50), 120)
        // Keep a plausible pulse pressure (sys must exceed dia by ≥25).
        if sys - dia < 25 { sys = dia + 25 }

        let conf = min(1.0, max(0.0, 0.5 * signalQuality + 0.5 * min(1.0, Double(beatCount) / 8.0)))
        return Estimate(systolicMmHg: sys.rounded(), diastolicMmHg: dia.rounded(), confidence: conf)
    }

    /// Plain-language bucket for the systolic/diastolic pair (ACC/AHA-style,
    /// framed as a wellness band rather than a diagnosis).
    static func category(systolic: Double, diastolic: Double) -> String {
        switch (systolic, diastolic) {
        case let (s, d) where s < 120 && d < 80: return "Normal range"
        case let (s, d) where s < 130 && d < 80: return "Elevated"
        case let (s, d) where s < 140 || d < 90: return "Stage 1 range"
        default: return "Stage 2 range"
        }
    }
}
