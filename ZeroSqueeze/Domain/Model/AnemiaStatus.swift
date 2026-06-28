import Foundation

/// Anemia severity classification from estimated hemoglobin (Hb) in g/dL.
///
/// WHO-style thresholds (adults, sea level):
/// - Normal: men ≥ 13 g/dL, women ≥ 12 g/dL
/// - Mild: men 11–12.9 g/dL, women 11–11.9 g/dL
/// - Moderate: 8–10.9 g/dL
/// - Severe: < 8 g/dL
enum AnemiaStatus: String, CaseIterable, Codable {
    case normal
    case mild
    case moderate
    case severe

    /// Decode an unknown raw value (e.g. a case added by a newer build, read
    /// back by an older one) as `.normal` rather than throwing — a single
    /// unrecognised value would otherwise fail the whole `[HbMeasurement]`
    /// decode and, combined with the overwrite-on-load behaviour, wipe history.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AnemiaStatus(rawValue: raw) ?? .normal
    }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .mild: return "Mild Anemia"
        case .moderate: return "Moderate Anemia"
        case .severe: return "Severe Anemia"
        }
    }

    var shortLabel: String {
        switch self {
        case .normal: return "Normal"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }

    static func fromHemoglobin(_ hb: Float, gender: Gender) -> AnemiaStatus {
        // NaN/inf would silently fall through every comparison and return
        // `.mild` (a plausible-looking lie). Bail to `.normal` and log so a
        // bug upstream in the estimator surfaces instead of mis-classifying.
        guard hb.isFinite else {
            ZSLogger.warn(.data, "AnemiaStatus received non-finite hb")
            return .normal
        }
        if hb < 8 { return .severe }
        if hb <= 10.9 { return .moderate }
        switch gender {
        case .male:
            if hb >= 13 { return .normal }
            return .mild
        case .female:
            if hb >= 12 { return .normal }
            return .mild
        case .other:
            if hb >= 12.5 { return .normal }
            return .mild
        }
    }
}
