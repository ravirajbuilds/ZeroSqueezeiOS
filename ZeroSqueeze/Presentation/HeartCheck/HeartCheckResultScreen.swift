import SwiftUI

struct HeartCheckResultScreen: View {
    let measurement: HeartCheckMeasurement
    let onDone: () -> Void

    @Environment(\.zsPalette) private var palette

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: ZSSpacing.xl) {
                    scoreHero
                    if hasBP { bpBlock }
                    metricsBlock
                    disclaimer
                    Button("Done", action: onDone).buttonStyle(.zsPrimary)
                }
                .padding(ZSSpacing.xl)
            }
        }
        .navigationTitle("Heart Check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scoreColor: Color {
        switch measurement.heartHealthScore {
        case ..<40: return palette.alertRed
        case ..<55: return palette.cautionYellow
        case ..<70: return palette.stressColor
        case ..<85: return palette.successGreen
        default: return palette.accent
        }
    }

    private var scoreHero: some View {
        VStack(spacing: ZSSpacing.m) {
            Text("HEART HEALTH").sectionLabel()
            ScoreRing(score: measurement.heartHealthScore,
                      color: scoreColor,
                      label: HeartHealthModel.band(for: measurement.heartHealthScore),
                      diameter: 188, lineWidth: 14)
            HStack(spacing: ZSSpacing.xs) {
                Image(systemName: "heart.fill").foregroundColor(palette.heartRateColor)
                Text("Heart age \(measurement.heartAge)")
                    .font(ZSTypography.bodyEmphasized).foregroundColor(palette.textPrimary)
            }
        }
        .padding(ZSSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    private var hasBP: Bool { measurement.systolicMmHg != nil && measurement.diastolicMmHg != nil }

    private var bpBlock: some View {
        VStack(spacing: ZSSpacing.s) {
            Text("CUFFLESS BLOOD PRESSURE").sectionLabel()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(measurement.systolicMmHg ?? 0))/\(Int(measurement.diastolicMmHg ?? 0))")
                    .font(ZSTypography.metricValue).foregroundColor(palette.bpColor)
                Text("mmHg").font(ZSTypography.caption).foregroundColor(palette.textSecondary)
            }
            BPGauge(systolic: measurement.systolicMmHg ?? 0, diastolic: measurement.diastolicMmHg ?? 0)
            Text("From pulse transit time (chest → finger). An index, not a cuff reading.")
                .font(ZSTypography.captionTight).foregroundColor(palette.textTertiary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZSSpacing.l).frame(maxWidth: .infinity)
        .background(palette.surface).clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.bpColor.opacity(0.4), lineWidth: 0.5))
    }

    private var metricsBlock: some View {
        VStack(spacing: ZSSpacing.standard) {
            MetricRow(label: "Heart rate",
                      value: measurement.heartRateBpm.map { "\($0) bpm" } ?? "—",
                      reading: measurement.heartRateBpm.map { MetricInterpretation.heartRate($0) })
            MetricRow(label: "HRV (SDNN)",
                      value: measurement.hrvSdnnMs.map { String(format: "%.0f ms", $0) } ?? "—",
                      reading: measurement.hrvSdnnMs.map { MetricInterpretation.hrv($0) })
            MetricRow(label: "Pulse transit time",
                      value: measurement.pttMs.map { String(format: "%.0f ms", $0) } ?? "—")
            MetricRow(label: "Ejection time (LVET)",
                      value: measurement.lvetMs.map { String(format: "%.0f ms", $0) } ?? "—")
            MetricRow(label: "Signal quality", value: String(format: "%.0f %%", measurement.signalQuality * 100))
            MetricRow(label: "Taken", value: measurement.timestamp.formatted(date: .abbreviated, time: .shortened))
        }
        .padding(ZSSpacing.l).background(palette.surface).clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            Label("Wellness estimate, not a diagnosis", systemImage: "exclamationmark.triangle.fill")
                .font(ZSTypography.bodyEmphasized).foregroundColor(palette.cautionYellow)
            Text("Heart Check fuses chest seismocardiography with fingertip PPG to estimate pulse transit time, a cuffless blood-pressure index, and a heart-health score. All values are approximate, uncalibrated, and affected by posture, placement and movement. Not a substitute for medical-grade monitoring.")
                .font(ZSTypography.caption).foregroundColor(palette.textSecondary)
        }
        .padding(ZSSpacing.l).background(palette.cautionYellow.opacity(0.08))
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.cautionYellow.opacity(0.5), lineWidth: 0.5))
    }
}
