import Foundation

/// Wellness-grade hemoglobin estimator.
///
/// This is **not** a medical device. It maps a few smartphone-PPG features
/// plus user demographics into a plausible Hb range. The model is a
/// hand-tuned linear regression intended to:
///
///   - centre on the demographic baseline (men ~15.0, women ~13.5 g/dL)
///   - bend downward when perfusion is low or the R-ratio drifts in the
///     direction associated with anaemia
///   - widen the confidence band when signal quality is poor or skin
///     melanin attenuates the signal
///
/// The exact coefficients here are intentionally conservative — until the
/// app is trained against ground-truth CBC data, we keep the output close
/// to the demographic mean and warn loudly. Users see a *range*, not a
/// single number.
enum HemoglobinEstimator {

    /// Compute an Hb point estimate (g/dL) and confidence band half-width
    /// (g/dL) from a single capture. `correction` is the user's personal
    /// calibration line (identity when never calibrated).
    static func estimate(
        features: PPGFeatures,
        profile: UserProfile,
        correction: HbCorrection = .identity
    ) -> Estimate {
        let baseline = demographicBaseline(profile: profile)

        // Perfusion adjustment: low PI → lower Hb (poor blood flow).
        // Centre adjustment at PI ≈ 2 (typical fingertip).
        let pi = features.perfusionIndex
        let piAdj = clamp((pi - 2.0) * 0.15, -1.5, 1.0)

        // R-ratio adjustment: anaemic blood has different red:green AC ratio.
        // Calibration TBD — until we have data, keep weight small.
        // `rRatio == 0` is a sentinel for "unmeasurable" (no pulsatile green
        // channel — common with deep skin tone or weak signal). Treating it
        // as a literal zero ratio would bias Hb downward by ~0.4 g/dL for
        // people who simply lack a clean green PPG; skip the term instead.
        let rRatio = features.rRatio
        let rAdj: Double = rRatio > 0 ? clamp((rRatio - 1.0) * 0.4, -1.0, 1.0) : 0

        // Skin tone correction: deeper Monk tones attenuate the green path
        // more, biasing R-ratio upward. Compensate.
        let toneAdj: Double
        if let tone = profile.monkSkinTone {
            // Linear: MST 1 → +0.0, MST 10 → -0.6
            toneAdj = -0.067 * Double(tone.tone - 1)
        } else {
            toneAdj = 0
        }

        let raw = clamp(baseline + piAdj + rAdj + toneAdj, 4.0, 20.0)

        // Personal calibration: linear correction fitted from user-entered
        // lab values. Applied to the raw population estimate, then
        // re-clamped so a calibrated user near the bounds saturates sanely.
        let point = clamp(correction.apply(raw), 4.0, 20.0)

        // Confidence band: starts at ±1.5 g/dL, widens as quality drops,
        // perfusion is weak, or skin tone is deep (more optical noise).
        // A personal calibration anchors the estimate to ground truth, so
        // it narrows the floor instead of widening it.
        var band = correction.isCalibrated ? 1.2 : 1.5
        band += (1.0 - features.quality) * 1.2
        if pi < 1.0 { band += 0.5 }
        if let tone = profile.monkSkinTone, tone.tone >= 7 { band += 0.4 }
        band = clamp(band, 0.8, 4.0)

        let anemia = AnemiaStatus.fromHemoglobin(Float(point), gender: profile.gender)

        return Estimate(
            hemoglobinGPerDl: Float(point),
            rawHemoglobinGPerDl: Float(raw),
            band: Float(band),
            perfusionIndex: Float(pi),
            quality: Float(features.quality),
            anemia: anemia,
            usedRRatio: features.rRatio > 0
        )
    }

    /// Population Hb means used as a soft prior.
    private static func demographicBaseline(profile: UserProfile) -> Double {
        // WHO mid-range adult means.
        let adultMale = 15.0
        let adultFemale = 13.5
        let child = 12.5
        let senior = 14.0

        switch profile.ageType {
        case .child: return child
        case .senior: return senior
        case .adult:
            switch profile.gender {
            case .male: return adultMale
            case .female: return adultFemale
            case .other: return (adultMale + adultFemale) / 2
            }
        }
    }

    struct Estimate {
        let hemoglobinGPerDl: Float
        /// Pre-correction estimate — pair this with a lab value when the
        /// user calibrates, so refits don't compound earlier corrections.
        let rawHemoglobinGPerDl: Float
        /// 95% band half-width.
        let band: Float
        let perfusionIndex: Float
        let quality: Float
        let anemia: AnemiaStatus
        let usedRRatio: Bool

        var low: Float { hemoglobinGPerDl - band }
        var high: Float { hemoglobinGPerDl + band }
    }
}

@inline(__always)
private func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    min(max(v, lo), hi)
}
