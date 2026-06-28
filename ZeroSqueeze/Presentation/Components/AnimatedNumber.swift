import SwiftUI

/// A number that rolls up from zero to its value on appear, using
/// `numericText` content transitions so each digit animates. Used for hero
/// metrics (Hb, HR) so a fresh result lands with a little life instead of
/// snapping in. Respects Reduce Motion — shows the final value immediately.
struct AnimatedNumber: View {
    let value: Double
    /// e.g. "%.1f" for Hb, "%.0f" for bpm.
    let format: String
    var font: Font
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        Text(String(format: format, shown))
            .font(font)
            .foregroundColor(color)
            // Only attach the numeric transition when motion is allowed —
            // otherwise the value still cross-fades under Reduce Motion.
            .contentTransition(reduceMotion ? .identity : .numericText(value: shown))
            .onAppear {
                guard !reduceMotion else { shown = value; return }
                withAnimation(.easeOut(duration: 0.7)) { shown = value }
            }
            .onChange(of: value) { _, newValue in
                // Respect Reduce Motion on later updates too.
                guard !reduceMotion else { shown = newValue; return }
                withAnimation(.easeOut(duration: 0.4)) { shown = newValue }
            }
    }
}
