import SwiftUI

/// Circular gauge for the daily readiness score. Animated sweep from 0 to the
/// score's fraction, coloured by band. Used as the Today hero and (smaller) in
/// the readiness detail.
struct ReadinessRing: View {
    let score: Readiness.Score
    var diameter: CGFloat = 168
    var lineWidth: CGFloat = 14

    @Environment(\.zsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: CGFloat = 0

    private var fraction: CGFloat {
        score.hasData ? CGFloat(score.value) / 100 : 0
    }

    private var ringColor: Color {
        switch score.band {
        case .rest:  return palette.alertRed
        case .low:   return palette.cautionYellow
        case .fair:  return palette.stressColor
        case .good:  return palette.successGreen
        case .peak:  return palette.accent
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.border, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [ringColor.opacity(0.7), ringColor]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                if score.hasData {
                    Text("\(score.value)")
                        .font(.system(size: diameter * 0.34, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                    Text(score.band.label.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(ringColor)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: diameter * 0.22))
                        .foregroundColor(palette.textTertiary)
                    Text("NO DATA")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(palette.textTertiary)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion {
                animated = fraction
            } else {
                withAnimation(.easeOut(duration: 0.9)) { animated = fraction }
            }
        }
        .onChange(of: fraction) { _, new in
            withAnimation(.easeOut(duration: 0.6)) { animated = new }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness")
        .accessibilityValue(score.hasData ? "\(score.value) out of 100, \(score.band.label)" : "No data yet")
    }
}
