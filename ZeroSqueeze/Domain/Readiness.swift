import Foundation

/// Daily "readiness" score — a single 0–100 number summarising how rested vs.
/// strained the body looks today, derived from scg-scan resting heart rate
/// and heart-rate variability against the user's own recent baseline.
///
/// Pure and deterministic (no I/O, `now` injected) so it's fully unit-testable.
/// This is a wellness heuristic, not a medical readiness metric — the copy in
/// the UI says as much.
enum Readiness {

    enum Band: String, Equatable {
        case rest   // run-down / recovering
        case low
        case fair
        case good
        case peak

        var label: String {
            switch self {
            case .rest: return "Take it easy"
            case .low:  return "Low"
            case .fair: return "Fair"
            case .good: return "Good"
            case .peak: return "Peak"
            }
        }
    }

    struct Score: Equatable {
        /// 0…100. Meaningful only when `hasData` is true.
        let value: Int
        let band: Band
        let headline: String
        let detail: String
        /// False until there's at least one gated chest scan to score from.
        let hasData: Bool

        static let empty = Score(
            value: 0,
            band: .fair,
            headline: "No readiness yet",
            detail: "Take a chest scan to unlock your daily readiness score.",
            hasData: false
        )
    }

    /// Look back this many days when building the personal baseline.
    static let baselineDays = 30
    /// A reading older than this many days can't anchor "today".
    static let freshnessDays = 2

    static func compute(
        scg: [SCGMeasurement],
        now: Date,
        calendar: Calendar = .current
    ) -> Score {
        let daily = RestingHeartRate.daily(from: scg, calendar: calendar)
        guard let latest = daily.last,
              let windowStart = calendar.date(byAdding: .day, value: -baselineDays, to: now),
              let freshCutoff = calendar.date(byAdding: .day, value: -freshnessDays, to: now),
              latest.day >= calendar.startOfDay(for: freshCutoff)
        else {
            return .empty
        }

        // Personal RHR baseline: mean of prior days inside the window.
        let priorRHR = daily
            .dropLast()
            .filter { $0.day >= windowStart }
            .map(\.rhr)

        // Start neutral and adjust. 75 reads as "fine" before any signal.
        var score = 75.0

        if priorRHR.count >= 2 {
            let baseline = priorRHR.reduce(0, +) / Double(priorRHR.count)
            // Elevated RHR vs baseline lowers readiness; a lower-than-usual
            // resting rate nudges it up. Clamp so one outlier can't swing it.
            let delta = latest.rhr - baseline          // +ve = elevated today
            score += clamp(-delta * 3.0, lower: -32, upper: 18)
        }

        // HRV component. Higher recent HRV than usual = better recovery.
        // Use only quality-gated readings inside the window (same gate the RHR
        // path applies via RestingHeartRate.daily), so a noisy low-quality scan
        // can't perturb readiness. Compare the most-recent few against the
        // OLDER rest — the baseline must exclude the readings being scored, or
        // it dilutes itself and flattens a genuinely high/low recovery day.
        let gatedHRV = scg
            .filter {
                $0.signalQuality >= RestingHeartRate.minQuality
                    && $0.timestamp >= windowStart
                    && $0.hrvSdnnMs != nil
            }
            .compactMap(\.hrvSdnnMs)          // newest-first (store order)
        if gatedHRV.count >= 4 {
            let recentHRV = Array(gatedHRV.prefix(3))
            let priorHRV = Array(gatedHRV.dropFirst(3))
            let recent = recentHRV.reduce(0, +) / Double(recentHRV.count)
            let baseHRV = priorHRV.reduce(0, +) / Double(priorHRV.count)
            score += clamp((recent - baseHRV) * 0.6, lower: -16, upper: 16)
            if recent < 20 { score -= 5 }   // absolute low-HRV floor penalty
        }

        let value = Int(clamp(score, lower: 0, upper: 100).rounded())
        let band = band(for: value)
        return Score(
            value: value,
            band: band,
            headline: headline(for: band),
            detail: detail(for: band, rhr: latest.rhr),
            hasData: true
        )
    }

    // ── Bands & copy ─────────────────────────────────────────────────

    static func band(for value: Int) -> Band {
        switch value {
        case ..<40: return .rest
        case ..<55: return .low
        case ..<70: return .fair
        case ..<85: return .good
        default:    return .peak
        }
    }

    private static func headline(for band: Band) -> String {
        switch band {
        case .rest: return "Your body's asking for rest"
        case .low:  return "Running a little low"
        case .fair: return "Steady today"
        case .good: return "You're well recovered"
        case .peak: return "Firing on all cylinders"
        }
    }

    private static func detail(for band: Band, rhr: Double) -> String {
        let rounded = Int(rhr.rounded())
        switch band {
        case .rest, .low:
            return "Resting heart rate around \(rounded) bpm is up versus your baseline. Favour lighter activity, hydration and sleep."
        case .fair:
            return "Resting heart rate around \(rounded) bpm sits near your usual range. A normal day."
        case .good, .peak:
            return "Resting heart rate around \(rounded) bpm and steady variability — a good day to push if you want to."
        }
    }

    private static func clamp(_ x: Double, lower: Double, upper: Double) -> Double {
        min(max(x, lower), upper)
    }
}
