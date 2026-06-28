import SwiftUI

/// A result-detail row that can carry interpretation: a label + value, an
/// optional status dot, and an optional one-line plain-language takeaway and
/// reference range underneath. Falls back to a plain label/value row when no
/// `reading` is supplied.
struct MetricRow: View {
    let label: String
    let value: String
    var reading: MetricReading? = nil

    @Environment(\.zsPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.xs) {
            HStack(spacing: ZSSpacing.s) {
                if let reading, reading.status != .neutral {
                    Circle()
                        .fill(statusColor(reading.status))
                        .frame(width: 7, height: 7)
                }
                Text(label)
                    .font(ZSTypography.body)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Text(value)
                    .font(ZSTypography.bodyEmphasized)
                    .foregroundColor(palette.textPrimary)
            }
            if let reading {
                Text(reading.takeaway)
                    .font(ZSTypography.caption)
                    .foregroundColor(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(reading.map { "\(value). \($0.takeaway)" } ?? value)
    }

    private func statusColor(_ status: MetricStatus) -> Color {
        switch status {
        case .normal: return palette.successGreen
        case .low: return palette.spO2Color
        case .high: return palette.cautionYellow
        case .neutral: return palette.textTertiary
        }
    }
}
