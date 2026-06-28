import SwiftUI

struct ResultScreen: View {
    let measurement: HbMeasurement
    let onDone: () -> Void
    /// (labHb, rawEstimate) → persist a calibration point. Passed in rather
    /// than resolving AppState from the environment, so this modal screen has
    /// no hidden environment dependency that would crash if presented detached.
    let onCalibrate: (Float, Float) -> Void

    @Environment(\.zsPalette) private var palette
    @State private var showCalibrationSheet = false
    @State private var calibrationSaved = false

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: ZSSpacing.xl) {
                    heroBlock
                    detailsBlock
                    calibrationBlock
                    disclaimerBlock
                    Button("Done", action: onDone)
                        .buttonStyle(.zsPrimary)
                }
                .padding(ZSSpacing.xl)
            }
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroBlock: some View {
        VStack(spacing: ZSSpacing.m) {
            Text("ESTIMATED HEMOGLOBIN")
                .sectionLabel()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                AnimatedNumber(
                    value: Double(measurement.hemoglobinGPerDl),
                    format: "%.1f",
                    font: ZSTypography.hero,
                    color: palette.hemoglobinColor
                )
                .heroNeonShadow(palette.hemoglobinColor)
                Text("g/dL")
                    .font(ZSTypography.title)
                    .foregroundColor(palette.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text("Likely range: \(String(format: "%.1f", measurement.hemoglobinLow))–\(String(format: "%.1f", measurement.hemoglobinHigh)) g/dL")
                .font(ZSTypography.body)
                .foregroundColor(palette.textSecondary)
            anemiaPill
        }
        .padding(ZSSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated hemoglobin")
        .accessibilityValue(String(format: "%.1f grams per deciliter, likely range %.1f to %.1f, %@",
            measurement.hemoglobinGPerDl, measurement.hemoglobinLow, measurement.hemoglobinHigh, measurement.anemia.label))
    }

    private var anemiaPill: some View {
        let color: Color = {
            switch measurement.anemia {
            case .normal: return palette.successGreen
            case .mild: return palette.cautionYellow
            case .moderate, .severe: return palette.alertRed
            }
        }()
        return Text(measurement.anemia.label)
            .font(ZSTypography.chipLabel)
            .padding(.horizontal, ZSSpacing.standard)
            .padding(.vertical, ZSSpacing.s)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(ZSShapes.pill)
    }

    private var detailsBlock: some View {
        VStack(spacing: ZSSpacing.standard) {
            MetricRow(
                label: "Heart rate",
                value: measurement.heartRateBpm.map { "\($0) bpm" } ?? "—",
                reading: measurement.heartRateBpm.map { MetricInterpretation.heartRate($0) }
            )
            MetricRow(
                label: "Perfusion index",
                value: String(format: "%.2f %%", measurement.perfusionIndex),
                reading: MetricInterpretation.perfusion(Double(measurement.perfusionIndex))
            )
            MetricRow(label: "Signal quality", value: String(format: "%.0f %%", measurement.signalQuality * 100))
            MetricRow(label: "Taken", value: measurement.timestamp.formatted(date: .abbreviated, time: .shortened))
        }
        .padding(ZSSpacing.l)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(ZSTypography.body)
                .foregroundColor(palette.textSecondary)
            Spacer()
            Text(value)
                .font(ZSTypography.bodyEmphasized)
                .foregroundColor(palette.textPrimary)
        }
    }

    private var calibrationBlock: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            Label(
                calibrationSaved ? "Calibration saved" : "Have a recent lab result?",
                systemImage: calibrationSaved ? "checkmark.seal.fill" : "scope"
            )
            .font(ZSTypography.bodyEmphasized)
            .foregroundColor(calibrationSaved ? palette.successGreen : palette.accent)
            Text(calibrationSaved
                 ? "Future estimates will be anchored to your lab value."
                 : "Enter the hemoglobin from a recent blood test and ZeroSqueeze will calibrate future estimates to you.")
                .font(ZSTypography.caption)
                .foregroundColor(palette.textSecondary)
            if !calibrationSaved {
                Button {
                    ZSHaptics.tap()
                    showCalibrationSheet = true
                } label: {
                    Text("Calibrate")
                        .font(ZSTypography.bodyEmphasized)
                        .padding(.vertical, ZSSpacing.s)
                        .padding(.horizontal, ZSSpacing.l)
                }
                .buttonStyle(.bordered)
                .tint(palette.accent)
            }
        }
        .padding(ZSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.accent.opacity(0.4), lineWidth: 0.5))
        .sheet(isPresented: $showCalibrationSheet) {
            CalibrationSheet(measured: measurement.hemoglobinGPerDl) { labHb in
                onCalibrate(labHb, measurement.rawHemoglobinGPerDl ?? measurement.hemoglobinGPerDl)
                calibrationSaved = true
                ZSHaptics.success()
            }
            .presentationDetents([.medium])
        }
    }

    private var disclaimerBlock: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            Label("Wellness estimate, not a diagnosis", systemImage: "exclamationmark.triangle.fill")
                .font(ZSTypography.bodyEmphasized)
                .foregroundColor(palette.cautionYellow)
            Text("ZeroSqueeze uses your phone's camera and flash to estimate hemoglobin from the light passing through your fingertip. The result is approximate and is not a substitute for a blood test. Confirm any concerning result with a clinician.")
                .font(ZSTypography.caption)
                .foregroundColor(palette.textSecondary)
        }
        .padding(ZSSpacing.l)
        .background(palette.cautionYellow.opacity(0.08))
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.cautionYellow.opacity(0.5), lineWidth: 0.5))
    }
}

/// Entry form for a lab-verified Hb value. Sanity-bounds input to the
/// physiological range before enabling save.
struct CalibrationSheet: View {
    let measured: Float
    let onSave: (Float) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.zsPalette) private var palette
    @State private var labText = ""

    private var labValue: Float? {
        guard let v = Float(labText.replacingOccurrences(of: ",", with: ".")),
              (4.0...20.0).contains(v) else { return nil }
        return v
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.backgroundGradient.ignoresSafeArea()
                VStack(alignment: .leading, spacing: ZSSpacing.xl) {
                    Text("Enter the hemoglobin value from your most recent blood test (CBC). ZeroSqueeze compares it to this reading (\(String(format: "%.1f", measured)) g/dL) and corrects future estimates.")
                        .font(ZSTypography.body)
                        .foregroundColor(palette.textSecondary)
                    HStack(spacing: ZSSpacing.s) {
                        TextField("e.g. 13.5", text: $labText)
                            .keyboardType(.decimalPad)
                            .font(ZSTypography.metricValue)
                            .foregroundColor(palette.textPrimary)
                            .padding(ZSSpacing.standard)
                            .background(palette.surface)
                            .clipShape(ZSShapes.smallShape)
                            .overlay(ZSShapes.smallShape.stroke(palette.border, lineWidth: 0.5))
                        Text("g/dL")
                            .font(ZSTypography.title)
                            .foregroundColor(palette.textSecondary)
                    }
                    if !labText.isEmpty && labValue == nil {
                        Text("Enter a value between 4.0 and 20.0 g/dL.")
                            .font(ZSTypography.caption)
                            .foregroundColor(palette.alertRed)
                    }
                    Spacer()
                    Button("Save calibration") {
                        if let v = labValue {
                            onSave(v)
                            dismiss()
                        }
                    }
                    .buttonStyle(.zsPrimary)
                    .disabled(labValue == nil)
                }
                .padding(ZSSpacing.xl)
            }
            .navigationTitle("Calibrate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
