import SwiftUI

/// The app logo with an optional live "heartbeat" — a gentle double-thump
/// scale pulse on a ~0.9 s cycle (≈66 bpm), the same rhythm the app
/// measures. Subtle: the icon feels alive without being distracting.
struct ZSLogo: View {
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 10
    var animated: Bool = true
    var glow: Bool = true

    @Environment(\.zsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = false

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: glow ? palette.accent.opacity(0.4) : .clear,
                    radius: glow ? size * 0.18 : 0,
                    y: glow ? size * 0.06 : 0)
            .scaleEffect(beat ? 1.06 : 1.0)
            .animation(beatAnimation, value: beat)
            .onAppear { if shouldAnimate { beat = true } }
            // Honour a live Reduce-Motion toggle: setting beat=false drops out
            // of the repeatForever loop (beatAnimation returns .default once
            // shouldAnimate is false), and turning it back off resumes it.
            .onChange(of: reduceMotion) { _, isOn in
                beat = isOn ? false : shouldAnimate
            }
    }

    private var shouldAnimate: Bool { animated && !reduceMotion }

    /// Asymmetric ease so the "contraction" is quick and the relaxation
    /// slow — closer to a real cardiac cycle than a plain sine.
    private var beatAnimation: Animation {
        guard shouldAnimate else { return .default }
        return .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
    }
}
