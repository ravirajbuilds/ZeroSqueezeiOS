import Foundation

/// Computational-cardiology synthesis of one fused chest-SCG + finger-PPG
/// reading into a heart-health picture: a cuffless blood pressure from pulse
/// transit time, a 0–100 cardiovascular wellness score, and an estimated
/// "heart age" relative to the user's chronological age.
///
/// All population-anchored heuristics — a wellness index, not a diagnosis. Pure
/// and deterministic so it's fully unit-testable.
enum HeartHealthModel {

    // ── PTT → blood pressure ───────────────────────────────────────

    /// Cuffless BP from PTT. Pulse pressure and arterial stiffness make BP fall
    /// roughly linearly as PTT lengthens. We anchor a normotensive 118/76 at a
    /// reference PTT and move from there; `--calibrate` against a cuff would set
    /// the intercept per user (future work).
    struct BP: Equatable {
        let systolic: Double
        let diastolic: Double
    }

    static let refPTTMs = 250.0
    static let refSystolic = 118.0
    static let refDiastolic = 76.0
    /// mmHg per ms of PTT shortening below reference.
    static let systolicSlope = 0.42
    static let diastolicSlope = 0.26

    static func bloodPressure(pttMs: Double) -> BP {
        let d = refPTTMs - pttMs                     // +ve = shorter PTT ⇒ higher BP
        var sys = refSystolic + systolicSlope * d
        var dia = refDiastolic + diastolicSlope * d
        sys = min(max(sys, 85), 190)
        dia = min(max(dia, 50), 120)
        if sys - dia < 25 { sys = dia + 25 }
        return BP(systolic: sys.rounded(), diastolic: dia.rounded())
    }

    // ── Heart-health score + heart age ─────────────────────────────

    struct Result: Equatable {
        /// 0–100 cardiovascular wellness score.
        let score: Int
        /// Plain-language band.
        let band: String
        /// Estimated heart age, years.
        let heartAge: Int
        /// Headline takeaway.
        let headline: String
    }

    /// Combine the fused metrics into a score + heart age. Any input may be nil;
    /// the score uses whatever is present, weighting the components it has.
    static func evaluate(
        age: Int,
        restingHR: Int?,
        hrvSdnnMs: Double?,
        systolicMmHg: Double?,
        lvetMs: Double?,
        respirationBpm: Double?
    ) -> Result {
        var score = 75.0
        var weightSum = 0.0
        var yearsDelta = 0.0   // +ve = older heart than chronological

        // Resting HR: lower is better (down to ~50). Each bpm over 65 costs.
        if let hr = restingHR {
            let d = Double(hr) - 62
            score += clamp(-d * 0.6, -22, 12); weightSum += 1
            yearsDelta += clamp(d * 0.25, -8, 12)
        }
        // HRV: higher is better; very low flags strain/ageing.
        if let hrv = hrvSdnnMs {
            let d = hrv - 45
            score += clamp(d * 0.35, -18, 16); weightSum += 1
            yearsDelta += clamp(-d * 0.18, -10, 12)
        }
        // Systolic BP: best near 115; penalty grows with elevation.
        if let sys = systolicMmHg {
            let d = sys - 115
            score += clamp(-abs(d) * 0.35 - max(0, d) * 0.15, -26, 4); weightSum += 1
            yearsDelta += clamp(max(0, d) * 0.3, 0, 16)
        }
        // LVET: extreme ejection times (very short/long for rate) hint at
        // contractility issues; mild effect.
        if let lvet = lvetMs {
            let d = abs(lvet - 300)
            score += clamp(-d * 0.04, -8, 2); weightSum += 1
        }
        // Respiration: outside 10–20 /min nudges down.
        if let resp = respirationBpm {
            let d = abs(resp - 14)
            score += clamp(-d * 0.4, -6, 1)
        }

        let value = Int(clamp(score, 0, 100).rounded())
        let heartAge = max(18, Int((Double(age) + yearsDelta).rounded()))
        let band = self.band(for: value)
        return Result(
            score: value,
            band: band,
            heartAge: heartAge,
            headline: headline(band: band, heartAge: heartAge, age: age, hasData: weightSum >= 1)
        )
    }

    static func band(for value: Int) -> String {
        switch value {
        case ..<40: return "Needs attention"
        case ..<55: return "Below average"
        case ..<70: return "Fair"
        case ..<85: return "Good"
        default:    return "Excellent"
        }
    }

    private static func headline(band: String, heartAge: Int, age: Int, hasData: Bool) -> String {
        guard hasData else { return "Take a Heart Check to see your score." }
        let delta = heartAge - age
        if delta <= -3 { return "Heart age \(heartAge) — younger than your \(age) years. \(band)." }
        if delta >= 3 { return "Heart age \(heartAge) — older than your \(age) years. \(band)." }
        return "Heart age \(heartAge), in line with your \(age) years. \(band)."
    }

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }
}
