import SwiftUI

/// Guided breathing coach. An expanding/contracting circle paces inhale →
/// hold → exhale → hold over a chosen pattern, for a fixed number of cycles.
/// Fully on-device, records nothing — it's a calm-down tool, not a measurement.
struct BreathingScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Phase: Equatable {
        case inhale, holdIn, exhale, holdOut
        var label: String {
            switch self {
            case .inhale: return "Breathe in"
            case .holdIn, .holdOut: return "Hold"
            case .exhale: return "Breathe out"
            }
        }
        var targetScale: CGFloat {
            switch self {
            case .inhale, .holdIn: return 1.0
            case .exhale, .holdOut: return 0.5
            }
        }
    }

    enum Pattern: String, CaseIterable, Identifiable {
        case box = "Box"
        case relax = "4-7-8"
        case calm = "Calm"
        var id: String { rawValue }

        /// (phase, seconds) in order. Zero-length phases are skipped.
        var steps: [(Phase, Int)] {
            switch self {
            case .box:   return [(.inhale, 4), (.holdIn, 4), (.exhale, 4), (.holdOut, 4)]
            case .relax: return [(.inhale, 4), (.holdIn, 7), (.exhale, 8), (.holdOut, 0)]
            case .calm:  return [(.inhale, 4), (.holdIn, 0), (.exhale, 6), (.holdOut, 0)]
            }
        }
        var subtitle: String {
            switch self {
            case .box:   return "Even 4-4-4-4 — focus & balance"
            case .relax: return "4-7-8 — wind down for sleep"
            case .calm:  return "Long exhale — quick calm"
            }
        }
    }

    private let totalCycles = 6
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var pattern: Pattern = .box
    @State private var running = false
    @State private var finished = false
    @State private var phaseIndex = 0
    @State private var secondsLeft = 0
    @State private var cyclesDone = 0
    @State private var scale: CGFloat = 0.5
    /// Wall-clock end of the current phase. The tick publisher free-runs on
    /// second boundaries from view-appear, so we time phases against this
    /// instead of counting raw ticks — otherwise the first phase's countdown
    /// could fire up to a second early and desync from the circle animation.
    @State private var phaseEndsAt: Date?

    private var activeSteps: [(Phase, Int)] { pattern.steps.filter { $0.1 > 0 } }
    private var currentPhase: Phase { activeSteps.isEmpty ? .inhale : activeSteps[phaseIndex].0 }

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            VStack(spacing: ZSSpacing.xl) {
                topBar
                Spacer()
                if finished {
                    completeView
                } else {
                    circle
                    statusText
                }
                Spacer()
                controls
            }
            .padding(ZSSpacing.xl)
        }
        .onReceive(tick) { _ in onTick() }
    }

    // ── Pieces ────────────────────────────────────────────────────────

    private var topBar: some View {
        HStack {
            Text("Breathe")
                .font(ZSTypography.largeTitle)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Button {
                ZSHaptics.tap(.light); dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(palette.textTertiary)
            }
        }
    }

    private var circle: some View {
        ZStack {
            Circle()
                .fill(palette.hrvColor.opacity(0.12))
            Circle()
                .stroke(palette.hrvColor.opacity(0.5), lineWidth: 2)
            VStack(spacing: 4) {
                Text(running ? currentPhase.label : "Ready")
                    .font(ZSTypography.title)
                    .foregroundColor(palette.textPrimary)
                if running {
                    Text("\(secondsLeft)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(palette.hrvColor)
                        .contentTransition(.numericText())
                }
            }
        }
        .frame(width: 260, height: 260)
        .scaleEffect(scale)
        .animation(.easeInOut(duration: 0.3), value: running)
    }

    private var statusText: some View {
        VStack(spacing: 4) {
            if running {
                Text("Cycle \(min(cyclesDone + 1, totalCycles)) of \(totalCycles)")
                    .font(ZSTypography.body)
                    .foregroundColor(palette.textSecondary)
            } else {
                Picker("Pattern", selection: $pattern) {
                    ForEach(Pattern.allCases) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)
                .disabled(running)
                Text(pattern.subtitle)
                    .font(ZSTypography.caption)
                    .foregroundColor(palette.textSecondary)
                    .padding(.top, ZSSpacing.s)
            }
        }
    }

    private var completeView: some View {
        VStack(spacing: ZSSpacing.standard) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(palette.successGreen)
            Text("Session complete")
                .font(ZSTypography.largeTitle)
                .foregroundColor(palette.textPrimary)
            Text("Nicely done. Notice how your breath feels now.")
                .font(ZSTypography.body)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if finished {
            Button("Done") { dismiss() }
                .buttonStyle(.zsPrimary)
            Button("Go again") { reset(); start() }
                .font(ZSTypography.bodyEmphasized)
                .foregroundColor(palette.accent)
        } else if running {
            Button("Stop") { stop() }
                .buttonStyle(.zsPrimary)
        } else {
            Button("Start") { start() }
                .buttonStyle(.zsPrimary)
        }
    }

    // ── State machine ─────────────────────────────────────────────────

    private func start() {
        guard !activeSteps.isEmpty else { return }
        finished = false
        running = true
        cyclesDone = 0
        phaseIndex = 0
        beginPhase()
    }

    private func stop() {
        running = false
        ZSHaptics.tap(.light)
        withAnimation(.easeInOut(duration: 0.4)) { scale = 0.5 }
    }

    private func reset() {
        finished = false
        running = false
        cyclesDone = 0
        phaseIndex = 0
        scale = 0.5
        phaseEndsAt = nil
    }

    private func beginPhase() {
        let (phase, dur) = activeSteps[phaseIndex]
        secondsLeft = dur
        phaseEndsAt = Date().addingTimeInterval(Double(dur))
        ZSHaptics.tap(phase == .inhale ? .medium : .light)
        let target = phase.targetScale
        if reduceMotion {
            scale = target
        } else {
            withAnimation(.easeInOut(duration: Double(dur))) { scale = target }
        }
    }

    private func onTick() {
        guard running, let ends = phaseEndsAt else { return }
        let remaining = ends.timeIntervalSinceNow
        // Display the ceil so a 3.7s remainder still reads "4". Advance only
        // once the phase's wall-clock duration has truly elapsed — never early.
        secondsLeft = max(0, Int(remaining.rounded(.up)))
        if remaining <= 0 { advance() }
    }

    private func advance() {
        phaseIndex += 1
        if phaseIndex >= activeSteps.count {
            phaseIndex = 0
            cyclesDone += 1
            if cyclesDone >= totalCycles {
                finish()
                return
            }
        }
        beginPhase()
    }

    private func finish() {
        running = false
        finished = true
        ZSHaptics.success()
        withAnimation(.easeInOut(duration: 0.6)) { scale = 0.7 }
    }
}
