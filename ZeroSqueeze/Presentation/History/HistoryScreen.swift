import SwiftUI
import Charts

struct HistoryScreen: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: MeasurementStore
    @EnvironmentObject var scgStore: SCGMeasurementStore
    @EnvironmentObject var checkInStore: CheckInStore
    @EnvironmentObject var heartCheckStore: HeartCheckStore
    @Environment(\.zsPalette) private var palette

    @State private var range: TimeRange = .month
    @State private var editCheckIn: CheckIn?

    /// Hb / scg / heart-check measurements within the selected range.
    private var hb: [HbMeasurement] {
        range.filter(store.measurements, now: Date(), timestamp: \.timestamp)
    }
    private var scg: [SCGMeasurement] {
        range.filter(scgStore.measurements, now: Date(), timestamp: \.timestamp)
    }
    private var heartChecks: [HeartCheckMeasurement] {
        range.filter(heartCheckStore.measurements, now: Date(), timestamp: \.timestamp)
    }

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            if store.measurements.isEmpty && scgStore.measurements.isEmpty && heartCheckStore.measurements.isEmpty && checkInStore.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: ZSSpacing.xl) {
                        rangePicker
                        if !store.measurements.isEmpty { weeklySummaryCard }
                        if hb.isEmpty && scg.isEmpty && heartChecks.isEmpty {
                            rangeEmptyState
                        } else {
                            if !hb.isEmpty { hbChartCard }
                            if !scg.isEmpty { hrChartCard }
                            if heartChecks.count >= 2 { heartHealthChartCard }
                            rhrChartCard
                            listSection
                        }
                        journalSection
                    }
                    .padding(ZSSpacing.xl)
                }
            }
        }
        .navigationTitle("Insights")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(
                        item: reportText,
                        preview: SharePreview("ZeroSqueeze wellness report")
                    ) {
                        Label("Share report", systemImage: "doc.text")
                    }
                    if !hb.isEmpty {
                        ShareLink(
                            item: csvExport,
                            preview: SharePreview("ZeroSqueeze hemoglobin readings")
                        ) {
                            Label("Export Hb CSV", systemImage: "tablecells")
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .tint(palette.accent)
            }
        }
        .sheet(item: $editCheckIn) { entry in
            CheckInSheet(day: entry.day, existing: entry) { checkInStore.upsert($0) }
        }
    }

    /// A full plain-text wellness summary for sharing with a clinician.
    private var reportText: String {
        ReportBuilder.text(
            profile: appState.profile ?? .placeholder,
            hb: store.measurements,
            scg: scgStore.measurements,
            checkIns: checkInStore.entries,
            readiness: Readiness.compute(scg: scgStore.measurements, now: Date()),
            now: Date()
        )
    }

    // ── Journal ───────────────────────────────────────────────────────

    @ViewBuilder
    private var journalSection: some View {
        let entries = checkInStore.entries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: ZSSpacing.m) {
                Text("JOURNAL").sectionLabel()
                VStack(spacing: ZSSpacing.s) {
                    ForEach(entries.prefix(14)) { c in
                        Button {
                            ZSHaptics.tap(.light); editCheckIn = c
                        } label: {
                            journalRow(c)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func journalRow(_ c: CheckIn) -> some View {
        HStack(spacing: ZSSpacing.standard) {
            Text(CheckIn.moodEmoji(c.mood)).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.day.formatted(date: .abbreviated, time: .omitted))
                    .font(ZSTypography.body)
                    .foregroundColor(palette.textPrimary)
                Text(journalSubtitle(c))
                    .font(ZSTypography.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
        }
        .padding(ZSSpacing.standard)
        .background(palette.surface)
        .clipShape(ZSShapes.smallShape)
        .overlay(ZSShapes.smallShape.stroke(palette.border, lineWidth: 0.5))
    }

    private func journalSubtitle(_ c: CheckIn) -> String {
        var parts = ["\(CheckIn.moodLabel(c.mood)) · energy \(CheckIn.energyLabel(c.energy).lowercased())"]
        if !c.symptoms.isEmpty { parts.append(c.symptoms.joined(separator: ", ")) }
        else if !c.note.isEmpty { parts.append(c.note) }
        return parts.joined(separator: " — ")
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(TimeRange.allCases) { r in
                Text(r.rawValue).tag(r)
            }
        }
        .pickerStyle(.segmented)
    }

    private var rangeEmptyState: some View {
        VStack(spacing: ZSSpacing.s) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundColor(palette.textTertiary)
            Text("No readings in this range")
                .font(ZSTypography.body)
                .foregroundColor(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(ZSSpacing.xl)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    /// Hb readings in the selected range as CSV, newest first — for sharing
    /// with a clinician or spreadsheet.
    private var csvExport: String {
        let formatter = ISO8601DateFormatter()
        let header = "timestamp,hemoglobin_g_dl,band_g_dl,heart_rate_bpm,perfusion_index,signal_quality,status"
        let rows = hb.map { m in
            [
                formatter.string(from: m.timestamp),
                String(format: "%.1f", m.hemoglobinGPerDl),
                String(format: "%.1f", m.hemoglobinBand),
                m.heartRateBpm.map(String.init) ?? "",
                String(format: "%.2f", m.perfusionIndex),
                String(format: "%.2f", m.signalQuality),
                m.anemia.shortLabel
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    // ── Weekly summary ────────────────────────────────────────────────

    private struct WeekStats {
        let average: Float
        let count: Int
        /// Change vs the prior 7-day window; nil when that window is empty.
        let delta: Float?
    }

    private var weekStats: WeekStats? {
        let now = Date()
        guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now),
              let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)
        else { return nil }

        let thisWeek = store.measurements.filter { $0.timestamp > weekAgo }
        guard !thisWeek.isEmpty else { return nil }
        let avg = thisWeek.map(\.hemoglobinGPerDl).reduce(0, +) / Float(thisWeek.count)

        let lastWeek = store.measurements.filter {
            $0.timestamp > twoWeeksAgo && $0.timestamp <= weekAgo
        }
        let delta: Float? = lastWeek.isEmpty
            ? nil
            : avg - lastWeek.map(\.hemoglobinGPerDl).reduce(0, +) / Float(lastWeek.count)

        return WeekStats(average: avg, count: thisWeek.count, delta: delta)
    }

    @ViewBuilder
    private var weeklySummaryCard: some View {
        if let stats = weekStats {
            HStack(spacing: ZSSpacing.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("7-DAY AVERAGE").sectionLabel()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", stats.average))
                            .font(ZSTypography.metricValue)
                            .foregroundColor(palette.hemoglobinColor)
                        Text("g/dL")
                            .font(ZSTypography.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("VS LAST WEEK").sectionLabel()
                    if let delta = stats.delta {
                        Text(String(format: "%+.1f", delta))
                            .font(ZSTypography.metricValueSmall)
                            .foregroundColor(
                                abs(delta) < 0.5 ? palette.textSecondary :
                                delta > 0 ? palette.successGreen : palette.cautionYellow
                            )
                    } else {
                        Text("—")
                            .font(ZSTypography.metricValueSmall)
                            .foregroundColor(palette.textTertiary)
                    }
                    Text("\(stats.count) reading\(stats.count == 1 ? "" : "s")")
                        .font(ZSTypography.caption)
                        .foregroundColor(palette.textTertiary)
                }
            }
            .padding(ZSSpacing.l)
            .background(palette.surface)
            .clipShape(ZSShapes.cardShape)
            .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
        }
    }

    private var emptyState: some View {
        VStack(spacing: ZSSpacing.standard) {
            Image(systemName: "waveform.path.ecg")
                .resizable().scaledToFit().frame(width: 60, height: 60)
                .foregroundColor(palette.textTertiary)
            Text("No measurements yet")
                .font(ZSTypography.title)
                .foregroundColor(palette.textSecondary)
            Text("Take your first reading to see trends over time.")
                .font(ZSTypography.body)
                .foregroundColor(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(ZSSpacing.xxl)
    }

    /// Hb plot range: [4, 20] envelope, widened to contain any band extremes.
    private var hbDomain: ClosedRange<Double> {
        let lows = hb.map { Double($0.hemoglobinLow) }
        let highs = hb.map { Double($0.hemoglobinHigh) }
        let lo = min(4.0, lows.min() ?? 4.0)
        let hi = max(20.0, highs.max() ?? 20.0)
        return lo...hi
    }

    /// HR plot range: floor 40, ceiling 180 unless a reading exceeds it.
    private var hrDomain: ClosedRange<Double> {
        let maxHR = scg.compactMap { $0.heartRateBpm }.max().map(Double.init) ?? 180
        return 40.0...max(180.0, maxHR + 10)
    }

    private var hbChartCard: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            Text("HEMOGLOBIN TREND").sectionLabel()
            Chart(hb.reversed()) { m in
                LineMark(
                    x: .value("Date", m.timestamp),
                    y: .value("Hb", m.hemoglobinGPerDl)
                )
                .foregroundStyle(palette.hemoglobinColor)
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Date", m.timestamp),
                    y: .value("Hb", m.hemoglobinGPerDl)
                )
                .foregroundStyle(palette.hemoglobinColor)
                AreaMark(
                    x: .value("Date", m.timestamp),
                    yStart: .value("Low", m.hemoglobinLow),
                    yEnd: .value("High", m.hemoglobinHigh)
                )
                .foregroundStyle(palette.hemoglobinColor.opacity(0.15))
            }
            .frame(height: 180)
            // Anchor to [4, 20] but expand to fully contain the confidence
            // band (which can widen past 20 / below 4) so a real reading or
            // its band is never silently pinned to the axis edge.
            .chartYScale(domain: hbDomain)
        }
        .padding(ZSSpacing.l)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    private var hrChartCard: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            Text("HEART RATE TREND").sectionLabel()
            Chart(scg.reversed()) { m in
                if let bpm = m.heartRateBpm {
                    LineMark(
                        x: .value("Date", m.timestamp),
                        y: .value("HR", bpm)
                    )
                    .foregroundStyle(palette.heartRateColor)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Date", m.timestamp),
                        y: .value("HR", bpm)
                    )
                    .foregroundStyle(palette.heartRateColor)
                }
            }
            .frame(height: 160)
            // Open the ceiling when a reading runs higher than 180 so a real
            // tachycardia spike isn't cropped off the trend. Floor stays at 40.
            .chartYScale(domain: hrDomain)
        }
        .padding(ZSSpacing.l)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    private var heartHealthChartCard: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            Text("HEART HEALTH TREND").sectionLabel()
            Chart(heartChecks.reversed()) { m in
                LineMark(x: .value("Date", m.timestamp), y: .value("Score", m.heartHealthScore))
                    .foregroundStyle(palette.bpColor)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", m.timestamp), y: .value("Score", m.heartHealthScore))
                    .foregroundStyle(palette.bpColor)
            }
            .frame(height: 160)
            .chartYScale(domain: 0...100)
        }
        .padding(ZSSpacing.l)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    /// Daily resting heart rate — confidence-gated, lowest-quartile
    /// aggregation per day (see `RestingHeartRate`). Hidden until two
    /// days survive gating; a single point isn't a trend.
    @ViewBuilder
    private var rhrChartCard: some View {
        let series = RestingHeartRate.daily(from: scg)
        if series.count >= 2 {
            VStack(alignment: .leading, spacing: ZSSpacing.s) {
                Text("RESTING HEART RATE · DAILY").sectionLabel()
                Chart(series) { d in
                    LineMark(
                        x: .value("Day", d.day),
                        y: .value("RHR", d.rhr)
                    )
                    .foregroundStyle(palette.heartRateColor)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Day", d.day),
                        y: .value("RHR", d.rhr)
                    )
                    .foregroundStyle(palette.heartRateColor)
                }
                .frame(height: 140)
                // Open the top of the domain when someone's RHR runs high —
                // a fixed 100 ceiling would clip exactly the readings worth
                // seeing. Floor stays at 40 (below = sensor junk).
                .chartYScale(domain: 40.0...max(100.0, (series.map(\.rhr).max() ?? 100) + 10))
                Text("Lowest-quartile average of confident readings per day.")
                    .font(ZSTypography.captionTight)
                    .foregroundColor(palette.textTertiary)
            }
            .padding(ZSSpacing.l)
            .background(palette.surface)
            .clipShape(ZSShapes.cardShape)
            .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
        }
    }

    /// Sum type used only to render a single merged chronological list.
    private enum Row: Identifiable {
        case hb(HbMeasurement)
        case scg(SCGMeasurement)
        case heartCheck(HeartCheckMeasurement)

        var id: String {
            switch self {
            case .hb(let m): return "hb-\(m.id.uuidString)"
            case .scg(let m): return "scg-\(m.id.uuidString)"
            case .heartCheck(let m): return "hc-\(m.id.uuidString)"
            }
        }
        var timestamp: Date {
            switch self {
            case .hb(let m): return m.timestamp
            case .scg(let m): return m.timestamp
            case .heartCheck(let m): return m.timestamp
            }
        }
    }

    private var listSection: some View {
        let rows: [Row] = (
            hb.map { Row.hb($0) } +
            scg.map { Row.scg($0) } +
            heartChecks.map { Row.heartCheck($0) }
        ).sorted { $0.timestamp > $1.timestamp }

        return VStack(alignment: .leading, spacing: ZSSpacing.m) {
            Text("ALL READINGS").sectionLabel()
            VStack(spacing: ZSSpacing.s) {
                ForEach(rows) { row in
                    NavigationLink {
                        switch row {
                        case .hb(let m): HbDetailScreen(measurement: m)
                        case .scg(let m): SCGDetailScreen(measurement: m)
                        case .heartCheck(let m): HeartCheckDetailScreen(measurement: m)
                        }
                    } label: {
                        rowView(row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        let (icon, valueText, valueColor): (String, String, Color) = {
            switch row {
            case .hb(let m):
                return ("hand.point.up.left.fill",
                        String(format: "%.1f g/dL", m.hemoglobinGPerDl),
                        palette.hemoglobinColor)
            case .scg(let m):
                let v = m.heartRateBpm.map { "\($0) bpm" } ?? "—"
                return ("waveform.path.ecg", v, palette.heartRateColor)
            case .heartCheck(let m):
                return ("heart.text.square.fill", "\(m.heartHealthScore)", palette.bpColor)
            }
        }()
        return HStack(spacing: ZSSpacing.standard) {
            Image(systemName: icon)
                .foregroundColor(valueColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(ZSTypography.body)
                    .foregroundColor(palette.textPrimary)
                Text(subtitle(for: row))
                    .font(ZSTypography.caption)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
            Text(valueText)
                .font(ZSTypography.bodyEmphasized)
                .foregroundColor(valueColor)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
        }
        .padding(ZSSpacing.standard)
        .background(palette.surface)
        .clipShape(ZSShapes.smallShape)
        .overlay(ZSShapes.smallShape.stroke(palette.border, lineWidth: 0.5))
    }

    private func subtitle(for row: Row) -> String {
        switch row {
        case .hb(let m): return m.anemia.shortLabel
        case .scg(let m):
            if let hrv = m.hrvSdnnMs { return "HRV \(Int(hrv)) ms" }
            return "Chest scan"
        case .heartCheck(let m):
            if let s = m.systolicMmHg, let d = m.diastolicMmHg {
                return "Heart Check · \(Int(s))/\(Int(d)) mmHg"
            }
            return "Heart Check · age \(m.heartAge)"
        }
    }
}
