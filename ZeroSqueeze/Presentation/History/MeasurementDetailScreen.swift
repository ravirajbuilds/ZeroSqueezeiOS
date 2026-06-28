import SwiftUI

/// Full breakdown of a single fingertip Hb reading, with single-record
/// delete. Pushed from the Trends readings list.
struct HbDetailScreen: View {
    let measurement: HbMeasurement

    @EnvironmentObject private var store: MeasurementStore
    @Environment(\.zsPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        DetailScaffold(
            hero: AnyView(hero),
            rows: [
                DetailRow(label: "Likely range", value: String(format: "%.1f–%.1f g/dL", measurement.hemoglobinLow, measurement.hemoglobinHigh)),
                DetailRow(label: "Status", value: measurement.anemia.label),
                DetailRow(label: "Heart rate",
                          value: measurement.heartRateBpm.map { "\($0) bpm" } ?? "—",
                          reading: measurement.heartRateBpm.map { MetricInterpretation.heartRate($0) }),
                DetailRow(label: "Perfusion index",
                          value: String(format: "%.2f %%", measurement.perfusionIndex),
                          reading: MetricInterpretation.perfusion(Double(measurement.perfusionIndex))),
                DetailRow(label: "Signal quality", value: String(format: "%.0f %%", measurement.signalQuality * 100)),
                DetailRow(label: "Taken", value: measurement.timestamp.formatted(date: .abbreviated, time: .shortened)),
            ],
            onDelete: { confirmDelete = true }
        )
        .navigationTitle("Hb reading")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this reading?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.remove(id: measurement.id)
                ZSHaptics.warning()
                dismiss()
            }
        }
    }

    private var hero: some View {
        VStack(spacing: ZSSpacing.s) {
            Text("ESTIMATED HEMOGLOBIN").sectionLabel()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", measurement.hemoglobinGPerDl))
                    .font(ZSTypography.hero)
                    .foregroundColor(palette.hemoglobinColor)
                    .heroNeonShadow(palette.hemoglobinColor)
                Text("g/dL")
                    .font(ZSTypography.title)
                    .foregroundColor(palette.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

/// Full breakdown of a single chest scan, with single-record delete.
struct SCGDetailScreen: View {
    let measurement: SCGMeasurement

    @EnvironmentObject private var scgStore: SCGMeasurementStore
    @Environment(\.zsPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        DetailScaffold(
            hero: AnyView(hero),
            rows: [
                DetailRow(label: "HRV (SDNN)",
                          value: measurement.hrvSdnnMs.map { String(format: "%.0f ms", $0) } ?? "—",
                          reading: measurement.hrvSdnnMs.map { MetricInterpretation.hrv($0) }),
                DetailRow(label: "Respiration",
                          value: measurement.respirationBpm.map { String(format: "%.0f /min", $0) } ?? "—",
                          reading: measurement.respirationBpm.map { MetricInterpretation.respiration($0) }),
                DetailRow(label: "Signal quality", value: String(format: "%.0f %%", measurement.signalQuality * 100)),
                DetailRow(label: "Model", value: measurement.modelSource ?? "—"),
                DetailRow(label: "Taken", value: measurement.timestamp.formatted(date: .abbreviated, time: .shortened)),
            ],
            onDelete: { confirmDelete = true }
        )
        .navigationTitle("Chest scan")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this reading?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                scgStore.remove(id: measurement.id)
                ZSHaptics.warning()
                dismiss()
            }
        }
    }

    private var hero: some View {
        VStack(spacing: ZSSpacing.s) {
            Text("HEART RATE").sectionLabel()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(measurement.heartRateBpm.map { "\($0)" } ?? "—")
                    .font(ZSTypography.hero)
                    .foregroundColor(palette.heartRateColor)
                    .heroNeonShadow(palette.heartRateColor)
                Text("bpm")
                    .font(ZSTypography.title)
                    .foregroundColor(palette.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

/// One detail row, optionally carrying a plain-language interpretation.
struct DetailRow: Identifiable {
    let label: String
    let value: String
    var reading: MetricReading? = nil
    var id: String { label }
}

/// Shared layout: hero card, a labelled detail grid, and a delete button.
private struct DetailScaffold: View {
    let hero: AnyView
    let rows: [DetailRow]
    let onDelete: () -> Void

    @Environment(\.zsPalette) private var palette

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: ZSSpacing.xl) {
                    hero
                        .padding(ZSSpacing.xl)
                        .frame(maxWidth: .infinity)
                        .background(palette.surface)
                        .clipShape(ZSShapes.cardShape)
                        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))

                    VStack(spacing: ZSSpacing.standard) {
                        ForEach(rows) { row in
                            MetricRow(label: row.label, value: row.value, reading: row.reading)
                        }
                    }
                    .padding(ZSSpacing.l)
                    .background(palette.surface)
                    .clipShape(ZSShapes.cardShape)
                    .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete reading", systemImage: "trash")
                            .font(ZSTypography.bodyEmphasized)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, ZSSpacing.standard)
                    }
                    .buttonStyle(.bordered)
                    .tint(palette.alertRed)
                }
                .padding(ZSSpacing.xl)
            }
        }
    }
}
