import SwiftUI

/// The app's landing tab. Leads with today's readiness ring, a daily check-in,
/// a compact vitals snapshot, a breathing shortcut, and trend insights.
struct TodayScreen: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: MeasurementStore
    @EnvironmentObject var scgStore: SCGMeasurementStore
    @EnvironmentObject var checkInStore: CheckInStore
    @EnvironmentObject var heartCheckStore: HeartCheckStore
    @Environment(\.zsPalette) private var palette

    @State private var showFingertipCapture = false
    @State private var showChestCapture = false
    @State private var showHeartCheck = false
    @State private var showBreathing = false
    @State private var showCheckIn = false

    private var readiness: Readiness.Score {
        Readiness.compute(scg: scgStore.measurements, now: Date())
    }

    private var todayCheckIn: CheckIn? {
        checkInStore.entry(on: Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.backgroundGradient.ignoresSafeArea()
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: ZSSpacing.xl) {
                        header
                        readinessCard
                        heartHealthCard
                        checkInCard
                        vitalsCard
                        breathingCTA
                        insightsCard
                    }
                    .padding(ZSSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            .navigationTitle("Today")
            .fullScreenCover(isPresented: $showFingertipCapture) {
                NavigationStack {
                    CaptureFlow(
                        profile: appState.profile ?? .placeholder,
                        onCalibrate: { lab, raw in appState.calibrate(labHb: lab, rawEstimate: raw) },
                        onClose: { showFingertipCapture = false }
                    )
                }
            }
            .fullScreenCover(isPresented: $showChestCapture) {
                NavigationStack { SCGCaptureFlow { showChestCapture = false } }
            }
            .fullScreenCover(isPresented: $showHeartCheck) {
                NavigationStack {
                    HeartCheckFlow(profile: appState.profile ?? .placeholder) { showHeartCheck = false }
                }
            }
            .fullScreenCover(isPresented: $showBreathing) {
                BreathingScreen()
            }
            .sheet(isPresented: $showCheckIn) {
                CheckInSheet(day: Date(), existing: todayCheckIn) { checkInStore.upsert($0) }
            }
        }
    }

    // ── Heart health (fused Heart Check) ──────────────────────────────

    @ViewBuilder
    private var heartHealthCard: some View {
        if let m = heartCheckStore.latest {
            VStack(alignment: .leading, spacing: ZSSpacing.m) {
                Text("HEART HEALTH").sectionLabel()
                HStack(alignment: .center, spacing: ZSSpacing.l) {
                    ZStack {
                        Circle().stroke(palette.border, lineWidth: 8)
                        Circle().trim(from: 0, to: CGFloat(m.heartHealthScore) / 100)
                            .stroke(heartScoreColor(m.heartHealthScore),
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(m.heartHealthScore)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(palette.textPrimary)
                    }
                    .frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HeartHealthModel.band(for: m.heartHealthScore))
                            .font(ZSTypography.bodyEmphasized)
                            .foregroundColor(palette.textPrimary)
                        Text("Heart age \(m.heartAge)")
                            .font(ZSTypography.caption)
                            .foregroundColor(palette.textSecondary)
                        if let s = m.systolicMmHg, let d = m.diastolicMmHg {
                            Text("\(Int(s))/\(Int(d)) mmHg · cuffless")
                                .font(ZSTypography.captionTight)
                                .foregroundColor(palette.bpColor)
                        }
                    }
                    Spacer()
                }
                Button {
                    ZSHaptics.tap(.medium); showHeartCheck = true
                } label: {
                    Label("New Heart Check", systemImage: "heart.text.square")
                        .zsChip(palette)
                }
            }
            .padding(ZSSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .clipShape(ZSShapes.cardShape)
            .overlay(ZSShapes.cardShape.stroke(palette.bpColor.opacity(0.35), lineWidth: 0.5))
        } else {
            Button {
                ZSHaptics.tap(.medium); showHeartCheck = true
            } label: {
                HStack(spacing: ZSSpacing.m) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title2).foregroundColor(palette.bpColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Take a Heart Check")
                            .font(ZSTypography.bodyEmphasized).foregroundColor(palette.textPrimary)
                        Text("Fused SCG + PPG → cuffless BP & heart age")
                            .font(ZSTypography.caption).foregroundColor(palette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(palette.textTertiary)
                }
                .padding(ZSSpacing.l)
                .frame(maxWidth: .infinity)
                .background(palette.surface)
                .clipShape(ZSShapes.cardShape)
                .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func heartScoreColor(_ v: Int) -> Color {
        switch v {
        case ..<40: return palette.alertRed
        case ..<55: return palette.cautionYellow
        case ..<70: return palette.stressColor
        case ..<85: return palette.successGreen
        default: return palette.accent
        }
    }

    // ── Header ────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: ZSSpacing.standard) {
            VStack(alignment: .leading, spacing: ZSSpacing.xs) {
                Text(greeting.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .tracking(1.5)
                    .foregroundColor(palette.textTertiary)
                Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                    .font(ZSTypography.largeTitle)
                    .foregroundColor(palette.textPrimary)
            }
            Spacer()
            ZSLogo(size: 40, cornerRadius: 10)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // ── Readiness ─────────────────────────────────────────────────────

    private var readinessCard: some View {
        // Compute once — `readiness` runs RestingHeartRate.daily over the full
        // chest history, so referencing the property repeatedly would re-run it
        // several times per render of the landing screen.
        let r = readiness
        return HStack(alignment: .center, spacing: ZSSpacing.l) {
            ReadinessRing(score: r, diameter: 132, lineWidth: 12)
            VStack(alignment: .leading, spacing: ZSSpacing.s) {
                Text("READINESS").sectionLabel()
                Text(r.headline)
                    .font(ZSTypography.title)
                    .foregroundColor(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(r.detail)
                    .font(ZSTypography.caption)
                    .foregroundColor(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !r.hasData {
                    Button {
                        ZSHaptics.tap(.medium); showChestCapture = true
                    } label: {
                        Label("Chest scan", systemImage: "waveform.path.ecg")
                            .zsChip(palette)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(ZSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
        .shadow(color: palette.isDark ? .black.opacity(0.35) : .black.opacity(0.05), radius: 14, y: 6)
    }

    // ── Check-in ──────────────────────────────────────────────────────

    private var checkInCard: some View {
        Button {
            ZSHaptics.tap(.light); showCheckIn = true
        } label: {
            HStack(spacing: ZSSpacing.standard) {
                if let c = todayCheckIn {
                    Text(CheckIn.moodEmoji(c.mood)).font(.system(size: 32))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY'S CHECK-IN").sectionLabel()
                        Text("\(CheckIn.moodLabel(c.mood)) · energy \(CheckIn.energyLabel(c.energy).lowercased())")
                            .font(ZSTypography.bodyEmphasized)
                            .foregroundColor(palette.textPrimary)
                        if !c.symptoms.isEmpty {
                            Text(c.symptoms.joined(separator: ", "))
                                .font(ZSTypography.caption)
                                .foregroundColor(palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("Edit").zsChip(palette)
                } else {
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                        .foregroundColor(palette.accent)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("How are you feeling?")
                            .font(ZSTypography.bodyEmphasized)
                            .foregroundColor(palette.textPrimary)
                        Text("Log a 10-second daily check-in")
                            .font(ZSTypography.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(palette.textTertiary)
                }
            }
            .padding(ZSSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .clipShape(ZSShapes.cardShape)
            .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // ── Vitals snapshot ───────────────────────────────────────────────

    private var vitalsCard: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.standard) {
            Text("LATEST VITALS").sectionLabel()
            HStack(alignment: .top, spacing: ZSSpacing.standard) {
                heartRateTile
                Divider().frame(height: 92).overlay(palette.border)
                hemoglobinTile
            }
        }
        .padding(ZSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    @ViewBuilder
    private var heartRateTile: some View {
        if let latest = scgStore.latest, let bpm = latest.heartRateBpm {
            let reading = MetricInterpretation.heartRate(bpm)
            vitalTile(title: "HEART RATE", value: "\(bpm)", unit: "bpm",
                      color: palette.heartRateColor,
                      status: hrStatusLabel(reading.status),
                      statusColor: hrStatusColor(reading.status), time: latest.timestamp)
        } else {
            emptyTile(title: "HEART RATE", prompt: "Chest scan") {
                ZSHaptics.tap(.medium); showChestCapture = true
            }
        }
    }

    @ViewBuilder
    private var hemoglobinTile: some View {
        if let latest = store.latest {
            vitalTile(title: "HEMOGLOBIN", value: String(format: "%.1f", latest.hemoglobinGPerDl),
                      unit: "g/dL", color: palette.hemoglobinColor,
                      status: latest.anemia.label, statusColor: anemiaColor(latest.anemia),
                      time: latest.timestamp)
        } else {
            emptyTile(title: "HEMOGLOBIN", prompt: "Fingertip scan") {
                ZSHaptics.tap(.medium); showFingertipCapture = true
            }
        }
    }

    private func vitalTile(title: String, value: String, unit: String, color: Color,
                           status: String, statusColor: Color, time: Date) -> some View {
        VStack(alignment: .leading, spacing: ZSSpacing.xs) {
            Text(title).font(ZSTypography.metricLabel).foregroundColor(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(ZSTypography.metricValue).foregroundColor(color)
                Text(unit).font(ZSTypography.caption).foregroundColor(palette.textSecondary)
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            Text(status)
                .font(ZSTypography.chipLabel)
                .foregroundColor(statusColor)
                .padding(.horizontal, ZSSpacing.s).padding(.vertical, 2)
                .background(statusColor.opacity(0.15))
                .clipShape(ZSShapes.pill)
            Text(time.formatted(.relative(presentation: .named)))
                .font(ZSTypography.captionTight).foregroundColor(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyTile(title: String, prompt: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ZSSpacing.s) {
                Text(title).font(ZSTypography.metricLabel).foregroundColor(palette.textTertiary)
                Text("—").font(ZSTypography.metricValue).foregroundColor(palette.textDisabled)
                HStack(spacing: 3) {
                    Image(systemName: "plus.circle.fill")
                    Text(prompt)
                }
                .font(ZSTypography.chipLabel).foregroundColor(palette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // ── Breathing CTA ─────────────────────────────────────────────────

    private var breathingCTA: some View {
        Button {
            ZSHaptics.tap(.medium); showBreathing = true
        } label: {
            HStack(spacing: ZSSpacing.standard) {
                Image(systemName: "wind")
                    .font(.title3).foregroundColor(palette.hrvColor).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Breathe")
                        .font(ZSTypography.bodyEmphasized)
                        .foregroundColor(palette.textPrimary)
                    Text("A guided minute to settle your pulse")
                        .font(ZSTypography.caption)
                        .foregroundColor(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(palette.textTertiary)
            }
            .padding(ZSSpacing.l)
            .background(palette.surface)
            .clipShape(ZSShapes.cardShape)
            .overlay(ZSShapes.cardShape.stroke(palette.hrvColor.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // ── Insights ──────────────────────────────────────────────────────

    private var insights: [HealthInsights.Insight] {
        HealthInsights.build(hb: store.measurements, scg: scgStore.measurements, now: Date())
    }

    @ViewBuilder
    private var insightsCard: some View {
        let items = insights
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: ZSSpacing.m) {
                Text("INSIGHTS").sectionLabel()
                ForEach(items) { insight in
                    HStack(alignment: .top, spacing: ZSSpacing.standard) {
                        Image(systemName: insight.icon)
                            .foregroundColor(insightColor(insight.severity))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title)
                                .font(ZSTypography.bodyEmphasized)
                                .foregroundColor(palette.textPrimary)
                            Text(insight.detail)
                                .font(ZSTypography.caption)
                                .foregroundColor(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(ZSSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .clipShape(ZSShapes.cardShape)
            .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
        }
    }

    // ── Colour helpers ────────────────────────────────────────────────

    private func anemiaColor(_ status: AnemiaStatus) -> Color {
        switch status {
        case .normal: return palette.successGreen
        case .mild: return palette.cautionYellow
        case .moderate, .severe: return palette.alertRed
        }
    }

    private func hrStatusLabel(_ status: MetricStatus) -> String {
        switch status {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "Elevated"
        case .neutral: return "—"
        }
    }

    private func hrStatusColor(_ status: MetricStatus) -> Color {
        switch status {
        case .normal: return palette.successGreen
        case .low: return palette.spO2Color
        case .high: return palette.cautionYellow
        case .neutral: return palette.textTertiary
        }
    }

    private func insightColor(_ severity: HealthInsights.Severity) -> Color {
        switch severity {
        case .positive: return palette.successGreen
        case .neutral: return palette.accent
        case .caution: return palette.cautionYellow
        }
    }
}
