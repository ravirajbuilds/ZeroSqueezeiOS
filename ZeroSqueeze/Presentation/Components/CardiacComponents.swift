import SwiftUI

// ── Per-beat pulse ──────────────────────────────────────────────────

/// A heart that thumps once per detected beat. Drive `beat` from the SCG
/// view-model's strictly-increasing beat count; each increment fires a quick
/// scale-up + glow, so the capture screen visibly (and via haptics) echoes the
/// user's own heartbeat. Falls back to a steady icon under Reduce Motion.
struct BeatPulse: View {
    let beat: Int
    var active: Bool
    var size: CGFloat = 96
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: "heart.fill")
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .scaleEffect(scale)
            .shadow(color: color.opacity(active ? 0.55 : 0.2), radius: active ? 24 * scale : 8)
            .opacity(active ? 1 : 0.55)
            .onChange(of: beat) { _, _ in thump() }
            .animation(.spring(response: 0.18, dampingFraction: 0.45), value: scale)
            .accessibilityHidden(true)
    }

    private func thump() {
        guard active, !reduceMotion else { return }
        scale = 1.18
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { scale = 1.0 }
    }
}

// ── Blood-pressure gauge ────────────────────────────────────────────

/// Horizontal gauge placing a systolic/diastolic pair on a banded scale
/// (normal → elevated → stage 1 → stage 2). Two ticks ride a single track so
/// the pulse pressure (the gap) reads at a glance.
struct BPGauge: View {
    let systolic: Double
    let diastolic: Double
    @Environment(\.zsPalette) private var palette

    // Display window for the systolic scale.
    private let lo: Double = 80
    private let hi: Double = 180

    private func frac(_ v: Double) -> CGFloat {
        CGFloat((min(max(v, lo), hi) - lo) / (hi - lo))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZSSpacing.s) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // Banded track: normal/elevated/stage1/stage2.
                    LinearGradient(
                        colors: [
                            palette.successGreen, palette.successGreen,
                            palette.cautionYellow, palette.bpColor, palette.alertRed,
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 8)
                    .clipShape(Capsule())
                    .opacity(0.85)

                    // Diastolic + systolic ticks.
                    tick(at: frac(diastolic) * w, label: "DIA")
                    tick(at: frac(systolic) * w, label: "SYS")
                }
                .frame(height: geo.size.height, alignment: .center)
            }
            .frame(height: 30)
            HStack {
                Text("80").bpScaleLabel(palette)
                Spacer()
                Text("130").bpScaleLabel(palette)
                Spacer()
                Text("180").bpScaleLabel(palette)
            }
        }
    }

    private func tick(at x: CGFloat, label: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(palette.textSecondary)
            Capsule()
                .fill(palette.textPrimary)
                .frame(width: 3, height: 16)
                .overlay(Capsule().stroke(palette.background, lineWidth: 1))
        }
        .offset(x: x - 12)
        .frame(width: 24)
    }
}

private extension Text {
    func bpScaleLabel(_ palette: ZSPalette) -> some View {
        self.font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundColor(palette.textTertiary)
    }
}

// ── SCG beat morphology ─────────────────────────────────────────────

/// A stylized single-beat seismocardiogram showing the AO (aortic-valve
/// opening) and AC (aortic-valve closing) fiducials with the LVET span
/// bracketed between them — the timing the result screen reports, drawn so the
/// number has a shape behind it.
struct SCGMorphologyView: View {
    /// Ejection time in ms (AO→AC). Drives the AC marker position.
    var lvetMs: Double?
    var color: Color
    @Environment(\.zsPalette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // AO at 22% width, AC offset by LVET scaled against a ~700 ms beat.
            let aoX = w * 0.22
            let acFrac = min(max((lvetMs ?? 300) / 700.0, 0.18), 0.55)
            let acX = aoX + w * CGFloat(acFrac)
            ZStack {
                beatPath(w: w, h: h, aoX: aoX, acX: acX)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .shadow(color: color.opacity(0.4), radius: 3)

                fiducial(x: aoX, h: h, label: "AO")
                fiducial(x: acX, h: h, label: "AC")

                if lvetMs != nil {
                    // LVET bracket between AO and AC.
                    Path { p in
                        let y = h * 0.16
                        p.move(to: CGPoint(x: aoX, y: y))
                        p.addLine(to: CGPoint(x: acX, y: y))
                    }
                    .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Text("LVET")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textTertiary)
                        .position(x: (aoX + acX) / 2, y: h * 0.08)
                }
            }
        }
        .frame(height: 72)
        .accessibilityHidden(true)
    }

    /// A schematic SCG: flat, sharp AO upstroke + ringdown, smaller AC lobe,
    /// settle. Not a real recording — a recognizable icon of one.
    private func beatPath(w: CGFloat, h: CGFloat, aoX: CGFloat, acX: CGFloat) -> Path {
        let mid = h * 0.62
        return Path { p in
            p.move(to: CGPoint(x: 0, y: mid))
            p.addLine(to: CGPoint(x: aoX - w * 0.05, y: mid))
            // AO complex: tall spike + undershoot.
            p.addLine(to: CGPoint(x: aoX, y: h * 0.24))
            p.addLine(to: CGPoint(x: aoX + w * 0.04, y: h * 0.84))
            p.addQuadCurve(
                to: CGPoint(x: acX - w * 0.04, y: mid),
                control: CGPoint(x: (aoX + acX) / 2, y: mid)
            )
            // AC complex: smaller lobe.
            p.addLine(to: CGPoint(x: acX, y: h * 0.42))
            p.addLine(to: CGPoint(x: acX + w * 0.03, y: h * 0.7))
            p.addQuadCurve(
                to: CGPoint(x: w, y: mid),
                control: CGPoint(x: w * 0.9, y: mid)
            )
        }
    }

    private func fiducial(x: CGFloat, h: CGFloat, label: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Circle().fill(color).frame(width: 5, height: 5)
        }
        .position(x: x, y: h * 0.92)
    }
}
