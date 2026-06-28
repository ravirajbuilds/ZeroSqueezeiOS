import SwiftUI

struct SCGResultScreen: View {
    let measurement: SCGMeasurement
    let onDone: () -> Void

    @Environment(\.zsPalette) private var palette

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: ZSSpacing.xl) {
                    heroBlock
                    if hasBP { bloodPressureBlock }
                    detailsBlock
                    disclaimerBlock
                    Button("Done", action: onDone)
                        .buttonStyle(.zsPrimary)
                }
                .padding(ZSSpacing.xl)
            }
        }
        .navigationTitle("Chest scan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroBlock: some View {
        VStack(spacing: ZSSpacing.m) {
            Text("HEART RATE")
                .sectionLabel()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let bpm = measurement.heartRateBpm {
                    AnimatedNumber(
                        value: Double(bpm),
                        format: "%.0f",
                        font: ZSTypography.hero,
                        color: palette.heartRateColor
                    )
                    .heroNeonShadow(palette.heartRateColor)
                } else {
                    Text("—")
                        .font(ZSTypography.hero)
                        .foregroundColor(palette.heartRateColor)
                }
                Text("bpm")
                    .font(ZSTypography.title)
                    .foregroundColor(palette.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if let bpm = measurement.heartRateBpm {
                let reading = MetricInterpretation.heartRate(bpm)
                Text(reading.takeaway)
                    .font(ZSTypography.caption)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ZSSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    private var hasBP: Bool {
        measurement.estSystolicMmHg != nil && measurement.estDiastolicMmHg != nil
    }

    private var bloodPressureBlock: some View {
        VStack(spacing: ZSSpacing.s) {
            Text("ESTIMATED BLOOD PRESSURE")
                .sectionLabel()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", measurement.estSystolicMmHg ?? 0))
                    .font(ZSTypography.metricValue)
                    .foregroundColor(palette.bpColor)
                Text("/")
                    .font(ZSTypography.title)
                    .foregroundColor(palette.textSecondary)
                Text(String(format: "%.0f", measurement.estDiastolicMmHg ?? 0))
                    .font(ZSTypography.metricValue)
                    .foregroundColor(palette.bpColor)
                Text("mmHg")
                    .font(ZSTypography.caption)
                    .foregroundColor(palette.textSecondary)
            }
            Text(BloodPressureEstimator.category(
                systolic: measurement.estSystolicMmHg ?? 0,
                diastolic: measurement.estDiastolicMmHg ?? 0
            ))
            .font(ZSTypography.caption)
            .foregroundColor(palette.textSecondary)
            Text("Modelled from your ejection time and heart rate — an index, not a cuff reading.")
                .font(ZSTypography.captionTight)
                .foregroundColor(palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZSSpacing.l)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.bpColor.opacity(0.4), lineWidth: 0.5))
    }

    private var detailsBlock: some View {
        VStack(spacing: ZSSpacing.standard) {
            MetricRow(
                label: "HRV (SDNN)",
                value: measurement.hrvSdnnMs.map { String(format: "%.0f ms", $0) } ?? "—",
                reading: measurement.hrvSdnnMs.map { MetricInterpretation.hrv($0) }
            )
            MetricRow(
                label: "Respiration",
                value: measurement.respirationBpm.map { String(format: "%.0f /min", $0) } ?? "—",
                reading: measurement.respirationBpm.map { MetricInterpretation.respiration($0) }
            )
            MetricRow(
                label: "Ejection time (LVET)",
                value: measurement.lvetMs.map { String(format: "%.0f ms", $0) } ?? "—"
            )
            MetricRow(
                label: "Contraction strength",
                value: measurement.aoAmplitudeMg.map { String(format: "%.0f mg", $0) } ?? "—"
            )
            MetricRow(label: "Signal quality", value: String(format: "%.0f %%", measurement.signalQuality * 100))
            if let src = measurement.modelSource {
                MetricRow(label: "Model", value: src == "coreml-scg" ? "Learned (Core ML)" : "Classic DSP")
            }
            MetricRow(label: "Taken", value: measurement.timestamp.formatted(date: .abbreviated, time: .shortened))
        }
        .padding(ZSSpacing.l)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    private var disclaimerBlock: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            Label("Wellness estimate, not a diagnosis", systemImage: "exclamationmark.triangle.fill")
                .font(ZSTypography.bodyEmphasized)
                .foregroundColor(palette.cautionYellow)
            Text("Chest scans read the micro-vibrations your heartbeat sends into your breastbone (seismocardiography) using the phone's motion sensor. Heart rate, variability, ejection time and the modelled blood-pressure index are approximate and affected by movement, posture and where the phone rests. They are not a substitute for medical-grade monitoring.")
                .font(ZSTypography.caption)
                .foregroundColor(palette.textSecondary)
        }
        .padding(ZSSpacing.l)
        .background(palette.cautionYellow.opacity(0.08))
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.cautionYellow.opacity(0.5), lineWidth: 0.5))
    }
}
