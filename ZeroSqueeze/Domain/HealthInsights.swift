import Foundation

/// Turns the raw measurement history into a few plain-language insight
/// lines for the Home dashboard. Pure and deterministic — no I/O, no
/// dates beyond what's passed in — so it's fully unit-testable.
///
/// Each insight has a severity that drives its colour/icon in the UI.
/// Insights are conservative: trends need enough data and a meaningful
/// effect size before they're surfaced, so the card never over-claims
/// from one noisy reading.
enum HealthInsights {

    enum Severity: Equatable {
        case positive   // good news / improvement
        case neutral    // informational
        case caution    // worth attention
    }

    struct Insight: Equatable, Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        let severity: Severity
    }

    /// Minimum readings in each compared window before a trend is trusted.
    static let minPerWindow = 2
    /// Hb change (g/dL) below this is treated as noise, not a trend.
    static let hbNoiseFloor: Float = 0.4
    /// RHR change (bpm) below this is treated as noise.
    static let rhrNoiseFloor = 3.0

    /// Build the insight list, most important first. `now` is injected for
    /// deterministic testing.
    static func build(
        hb: [HbMeasurement],
        scg: [SCGMeasurement],
        now: Date,
        calendar: Calendar = .current
    ) -> [Insight] {
        var out: [Insight] = []
        if let i = latestAnemiaInsight(hb) { out.append(i) }
        if let i = hbTrendInsight(hb, now: now, calendar: calendar) { out.append(i) }
        if let i = rhrTrendInsight(scg, now: now, calendar: calendar) { out.append(i) }
        if let i = hrvInsight(scg) { out.append(i) }
        if out.isEmpty {
            out.append(Insight(
                id: "get-started",
                icon: "sparkles",
                title: "Take a few readings",
                detail: "Insights appear once ZeroSqueeze has enough measurements to spot a trend.",
                severity: .neutral
            ))
        }
        return out
    }

    // ── Individual insights ──────────────────────────────────────────

    private static func latestAnemiaInsight(_ hb: [HbMeasurement]) -> Insight? {
        guard let latest = hb.first else { return nil }
        switch latest.anemia {
        case .normal:
            return Insight(
                id: "anemia-normal",
                icon: "checkmark.seal.fill",
                title: "Hemoglobin in range",
                detail: "Your latest estimate sits in the normal band for your profile.",
                severity: .positive
            )
        case .mild, .moderate, .severe:
            return Insight(
                id: "anemia-low",
                icon: "exclamationmark.triangle.fill",
                title: "Estimate below normal",
                detail: "Your latest reading suggests \(latest.anemia.label.lowercased()). This is a wellness estimate — confirm with a clinician and a blood test.",
                severity: .caution
            )
        }
    }

    private static func hbTrendInsight(_ hb: [HbMeasurement], now: Date, calendar: Calendar) -> Insight? {
        guard let (this, last) = splitWeeks(hb, value: { $0.hemoglobinGPerDl }, now: now, calendar: calendar)
        else { return nil }
        let delta = this - last
        guard abs(delta) >= hbNoiseFloor else { return nil }
        let up = delta > 0
        return Insight(
            id: "hb-trend",
            icon: up ? "arrow.up.right" : "arrow.down.right",
            title: up ? "Hemoglobin trending up" : "Hemoglobin trending down",
            detail: String(format: "About %+.1f g/dL vs last week's average.", delta),
            severity: up ? .positive : .caution
        )
    }

    private static func rhrTrendInsight(_ scg: [SCGMeasurement], now: Date, calendar: Calendar) -> Insight? {
        let daily = RestingHeartRate.daily(from: scg, calendar: calendar)
        guard let (this, last) = splitWeeksDaily(daily, now: now, calendar: calendar) else { return nil }
        let delta = this - last
        guard abs(delta) >= rhrNoiseFloor else { return nil }
        // Lower resting HR is generally the healthier direction.
        let down = delta < 0
        return Insight(
            id: "rhr-trend",
            icon: down ? "arrow.down.right" : "arrow.up.right",
            title: down ? "Resting heart rate down" : "Resting heart rate up",
            detail: String(format: "About %+.0f bpm vs last week.", delta),
            severity: down ? .positive : .neutral
        )
    }

    private static func hrvInsight(_ scg: [SCGMeasurement]) -> Insight? {
        let recent = scg.prefix(5).compactMap { $0.hrvSdnnMs }
        guard recent.count >= 3 else { return nil }
        let avg = recent.reduce(0, +) / Double(recent.count)
        // Very rough wellness framing; HRV is highly individual.
        if avg < 20 {
            return Insight(
                id: "hrv-low",
                icon: "waveform.path",
                title: "Low heart-rate variability",
                detail: String(format: "Recent HRV averages %.0f ms. Low HRV can track stress or fatigue.", avg),
                severity: .neutral
            )
        }
        return Insight(
            id: "hrv-ok",
            icon: "waveform.path",
            title: "Healthy variability",
            detail: String(format: "Recent HRV averages %.0f ms.", avg),
            severity: .positive
        )
    }

    // ── Helpers ──────────────────────────────────────────────────────

    /// Mean of `value` over this-week and last-week windows. Returns nil
    /// unless both windows clear `minPerWindow`.
    private static func splitWeeks(
        _ items: [HbMeasurement],
        value: (HbMeasurement) -> Float,
        now: Date,
        calendar: Calendar
    ) -> (Float, Float)? {
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)
        else { return nil }
        let thisWeek = items.filter { $0.timestamp > weekAgo }.map(value)
        let lastWeek = items.filter { $0.timestamp > twoWeeksAgo && $0.timestamp <= weekAgo }.map(value)
        guard thisWeek.count >= minPerWindow, lastWeek.count >= minPerWindow else { return nil }
        return (thisWeek.reduce(0, +) / Float(thisWeek.count),
                lastWeek.reduce(0, +) / Float(lastWeek.count))
    }

    private static func splitWeeksDaily(
        _ daily: [RestingHeartRate.Daily],
        now: Date,
        calendar: Calendar
    ) -> (Double, Double)? {
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)
        else { return nil }
        let thisWeek = daily.filter { $0.day > weekAgo }.map(\.rhr)
        let lastWeek = daily.filter { $0.day > twoWeeksAgo && $0.day <= weekAgo }.map(\.rhr)
        guard !thisWeek.isEmpty, !lastWeek.isEmpty else { return nil }
        return (thisWeek.reduce(0, +) / Double(thisWeek.count),
                lastWeek.reduce(0, +) / Double(lastWeek.count))
    }
}
