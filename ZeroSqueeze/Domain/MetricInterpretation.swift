import Foundation

/// Plain-language interpretation of a single vital, so results explain what a
/// number *means* rather than just printing it. Pure domain logic — the
/// presentation layer maps `MetricStatus` to palette colours.
///
/// Reference bands are wellness-grade rules of thumb for a resting adult, not
/// diagnostic thresholds. They exist to orient the user ("is this roughly
/// where it should be?"), always alongside the not-a-diagnosis disclaimer.
enum MetricStatus: Equatable {
    /// Below the typical band (not necessarily bad — e.g. an athlete's low HR).
    case low
    /// Within the typical resting band.
    case normal
    /// Above the typical band.
    case high
    /// No band to compare against (e.g. signal-strength metrics).
    case neutral
}

struct MetricReading: Equatable {
    let status: MetricStatus
    /// Human reference range, e.g. "60–100 bpm". Empty when not applicable.
    let range: String
    /// One-line plain-language takeaway.
    let takeaway: String
}

enum MetricInterpretation {

    /// Resting heart rate. Typical adult resting band is 60–100 bpm; trained
    /// individuals often sit lower.
    static func heartRate(_ bpm: Int) -> MetricReading {
        let range = "Typical resting 60–100 bpm"
        switch bpm {
        case ..<60:
            return MetricReading(status: .low, range: range,
                takeaway: "Below the typical resting range — common in fit people, but worth noting if you feel faint.")
        case 60...100:
            return MetricReading(status: .normal, range: range,
                takeaway: "Within the typical resting range.")
        default:
            return MetricReading(status: .high, range: range,
                takeaway: "Above the typical resting range — recent activity, caffeine or stress can raise it.")
        }
    }

    /// HRV (SDNN). Highly individual; track your own trend rather than an
    /// absolute target. These bands are deliberately wide.
    static func hrv(_ ms: Double) -> MetricReading {
        let range = "Higher is generally better"
        switch ms {
        case ..<20:
            return MetricReading(status: .low, range: range,
                takeaway: "On the lower side. HRV is very personal — your own trend matters more than one reading.")
        case 20..<60:
            return MetricReading(status: .normal, range: range,
                takeaway: "A typical range. Compare against your own baseline over time.")
        default:
            return MetricReading(status: .high, range: range,
                takeaway: "Strong variability, often a sign of good recovery.")
        }
    }

    /// Respiration rate. Typical resting adult band is 12–20 breaths/min.
    static func respiration(_ bpm: Double) -> MetricReading {
        let range = "Typical resting 12–20 /min"
        switch bpm {
        case ..<12:
            return MetricReading(status: .low, range: range,
                takeaway: "Below the typical resting range.")
        case 12...20:
            return MetricReading(status: .normal, range: range,
                takeaway: "Within the typical resting range.")
        default:
            return MetricReading(status: .high, range: range,
                takeaway: "Above the typical resting range — recent exertion can raise it.")
        }
    }

    /// Perfusion index is a signal-strength measure (how strongly blood pulses
    /// through the fingertip), not a health band — so it's always `.neutral`.
    static func perfusion(_ pi: Double) -> MetricReading {
        let takeaway: String
        switch pi {
        case ..<0.4: takeaway = "Weak pulse signal — press a little firmer next time for a cleaner reading."
        case 0.4..<2: takeaway = "Healthy pulse signal strength."
        default: takeaway = "Strong pulse signal."
        }
        return MetricReading(status: .neutral, range: "Signal strength", takeaway: takeaway)
    }
}
