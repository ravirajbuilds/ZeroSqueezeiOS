import Foundation

/// A single fingertip-PPG capture result.
///
/// Named `HbMeasurement` to avoid clashing with `Foundation.Measurement<UnitType>`.
struct HbMeasurement: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date

    /// Heart rate, beats per minute. Nil if peak detection failed.
    let heartRateBpm: Int?

    /// Estimated hemoglobin point value, g/dL (personal correction applied).
    let hemoglobinGPerDl: Float

    /// Pre-correction estimate, g/dL. Optional so records saved before
    /// multi-point calibration shipped still decode; fall back to the
    /// corrected value when absent.
    var rawHemoglobinGPerDl: Float? = nil

    /// 95% confidence band half-width, g/dL. Total range = point ± band.
    let hemoglobinBand: Float

    /// Perfusion index (AC/DC × 100) from the red channel.
    let perfusionIndex: Float

    /// Signal quality in [0, 1]. Anything below ~0.4 should be treated as suspect.
    let signalQuality: Float

    /// Anemia bucket derived from the point estimate + user's gender *at
    /// capture time*. Stored, so it stays historically accurate even if the
    /// user later edits their profile gender.
    let anemia: AnemiaStatus

    /// The gender used to derive `anemia`, recorded so the classification is
    /// self-describing and any later re-derivation uses the right reference
    /// band. Optional: records saved before this field decode with `nil`.
    var genderAtCapture: Gender? = nil

    var hemoglobinLow: Float { hemoglobinGPerDl - hemoglobinBand }
    var hemoglobinHigh: Float { hemoglobinGPerDl + hemoglobinBand }

    static let placeholder = HbMeasurement(
        id: UUID(),
        timestamp: Date(),
        heartRateBpm: 72,
        hemoglobinGPerDl: 13.4,
        hemoglobinBand: 1.2,
        perfusionIndex: 2.1,
        signalQuality: 0.82,
        anemia: .normal
    )
}
