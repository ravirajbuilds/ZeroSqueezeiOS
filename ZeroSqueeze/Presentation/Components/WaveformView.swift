import SwiftUI

/// Scrolling PPG trace. Renders a rolling buffer of recent AC samples as a
/// normalized line — live feedback that the camera is actually seeing a
/// pulse. Auto-scales to the window's own min/max so a weak signal still
/// fills the view (the colour, not the amplitude, signals quality).
struct WaveformView: View {
    /// Most-recent-last samples (any scale; auto-normalized).
    let samples: [Double]
    var color: Color
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Baseline.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(color.opacity(0.15), lineWidth: 1)

                trace(in: geo.size)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: color.opacity(0.4), radius: 4)
            }
        }
        // Decorative live trace — the numeric stats carry the real info.
        .accessibilityHidden(true)
    }

    private func trace(in size: CGSize) -> Path {
        Path { p in
            guard samples.count >= 2 else { return }
            let lo = samples.min() ?? 0
            let hi = samples.max() ?? 1
            let span = max(hi - lo, 1e-6)
            // Inset vertically so peaks don't clip the bounds.
            let top = size.height * 0.12
            let usable = size.height * 0.76
            let dx = size.width / CGFloat(samples.count - 1)

            for (i, v) in samples.enumerated() {
                let norm = (v - lo) / span          // 0…1
                let y = top + usable * (1 - CGFloat(norm))
                let pt = CGPoint(x: CGFloat(i) * dx, y: y)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }
}
