import Foundation

/// Builds a shareable plain-text wellness summary from the user's history —
/// the "Share report" action in Insights. Plain text (not CSV) so it reads
/// well pasted into Messages, Notes, or an email to a clinician.
///
/// Pure and deterministic (`now` injected) for unit testing.
enum ReportBuilder {

    static func text(
        profile: UserProfile,
        hb: [HbMeasurement],
        scg: [SCGMeasurement],
        checkIns: [CheckIn],
        readiness: Readiness.Score,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let df = DateFormatter()
        df.calendar = calendar
        df.dateStyle = .medium
        df.timeStyle = .short

        var lines: [String] = []
        lines.append("ZeroSqueeze — Wellness Report")
        lines.append("Generated \(df.string(from: now))")
        lines.append("Profile: \(profile.age)y · \(profile.gender.label)")
        lines.append("")

        // Readiness
        if readiness.hasData {
            lines.append("TODAY'S READINESS")
            lines.append("  \(readiness.value)/100 — \(readiness.band.label)")
            lines.append("  \(readiness.headline)")
            lines.append("")
        }

        // Latest vitals
        lines.append("LATEST VITALS")
        var printedVital = false
        if let h = hb.first {
            lines.append("  Hemoglobin: \(fmt(h.hemoglobinGPerDl, "%.1f")) g/dL (\(h.anemia.label)) — \(df.string(from: h.timestamp))")
            printedVital = true
        }
        // Newest scan can have nil bpm (peak detection failed); fall back to the
        // most recent scan that actually produced a heart rate.
        if let f = scg.first(where: { $0.heartRateBpm != nil }), let bpm = f.heartRateBpm {
            var hr = "  Heart rate: \(bpm) bpm"
            if let hrv = f.hrvSdnnMs { hr += " · HRV \(Int(hrv.rounded())) ms" }
            hr += " — \(df.string(from: f.timestamp))"
            lines.append(hr)
            printedVital = true
        }
        if !printedVital {
            lines.append("  No readings yet.")
        }
        lines.append("")

        // 7-day averages
        if let cutoff = calendar.date(byAdding: .day, value: -7, to: now) {
            let recentHb = hb.filter { $0.timestamp > cutoff }.map { Double($0.hemoglobinGPerDl) }
            let recentHr = scg.compactMap { $0.timestamp > cutoff ? $0.heartRateBpm : nil }
            if !recentHb.isEmpty || !recentHr.isEmpty {
                lines.append("LAST 7 DAYS")
                if !recentHb.isEmpty {
                    let avg = recentHb.reduce(0, +) / Double(recentHb.count)
                    lines.append(String(format: "  Avg hemoglobin: %.1f g/dL (%d readings)", avg, recentHb.count))
                }
                if !recentHr.isEmpty {
                    let avg = Double(recentHr.reduce(0, +)) / Double(recentHr.count)
                    lines.append(String(format: "  Avg heart rate: %.0f bpm (%d scans)", avg, recentHr.count))
                }
                lines.append("")
            }
        }

        // Recent check-ins
        let recentCheckIns = Array(checkIns.prefix(5))
        if !recentCheckIns.isEmpty {
            let dayFmt = DateFormatter()
            dayFmt.calendar = calendar
            dayFmt.dateStyle = .medium
            lines.append("RECENT CHECK-INS")
            for c in recentCheckIns {
                var line = "  \(dayFmt.string(from: c.day)): mood \(CheckIn.moodLabel(c.mood)), energy \(CheckIn.energyLabel(c.energy))"
                if !c.symptoms.isEmpty { line += " · \(c.symptoms.joined(separator: ", "))" }
                lines.append(line)
                if !c.note.isEmpty { lines.append("    “\(c.note)”") }
            }
            lines.append("")
        }

        lines.append("—")
        lines.append("ZeroSqueeze estimates are camera-based wellness indicators, not a medical diagnosis. Confirm anything concerning with a clinician.")
        return lines.joined(separator: "\n")
    }

    private static func fmt(_ v: Float, _ f: String) -> String {
        String(format: f, v)
    }
}
