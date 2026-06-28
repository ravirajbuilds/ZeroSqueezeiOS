import SwiftUI

/// First-run onboarding. A centred, immersive flow with an animated pulse-ring
/// hero, swipe-feel step transitions and bottom dot indicators — a distinct
/// look from the in-app tabs. Collects the minimum profile (age, sex, optional
/// skin tone) and a wellness-disclaimer acknowledgement.
struct OnboardingScreen: View {
    let onComplete: (UserProfile) -> Void

    @Environment(\.zsPalette) private var palette
    @State private var age: Int = 30
    @State private var gender: Gender = .other
    @State private var skinTone: Int? = nil
    @State private var step: Int = 0
    @State private var acceptedDisclaimer = false

    private let steps = 5

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            // Soft accent bloom top-centre — the new "vibe".
            palette.accentGradient
                .frame(width: 460, height: 460)
                .blur(radius: 140)
                .opacity(palette.isDark ? 0.22 : 0.14)
                .offset(y: -320)
                .ignoresSafeArea()

            VStack(spacing: ZSSpacing.xl) {
                contentForStep
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                footer
            }
            .padding(ZSSpacing.xl)
        }
    }

    // ── Steps ─────────────────────────────────────────────────────────

    @ViewBuilder
    private var contentForStep: some View {
        switch step {
        case 0: welcomeStep
        case 1: valueStep
        case 2: aboutYouStep
        case 3: skinToneStep
        default: disclaimerStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: ZSSpacing.l) {
            Spacer()
            ZSHero()
            VStack(spacing: ZSSpacing.standard) {
                Text("Your body,\nin numbers")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(palette.textPrimary)
                Text("ZeroSqueeze reads your heartbeat's vibrations from your chest and the pulse in your fingertip — heart rate, HRV, ejection time, a blood-pressure index and hemoglobin, in seconds, all on-device.")
                    .font(ZSTypography.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(palette.textSecondary)
                    .padding(.horizontal, ZSSpacing.standard)
            }
            Spacer()
        }
    }

    private var valueStep: some View {
        VStack(spacing: ZSSpacing.l) {
            heroIcon("sparkles", tint: palette.accent)
            Text("More than a scanner")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(palette.textPrimary)
            VStack(spacing: ZSSpacing.standard) {
                valueChip(icon: "gauge.with.dots.needle.67percent", tint: palette.successGreen,
                          title: "Daily readiness", subtitle: "A single score from your heart-rate & HRV trends.")
                valueChip(icon: "wind", tint: palette.hrvColor,
                          title: "Guided breathing", subtitle: "Paced sessions to settle your pulse and reset.")
                valueChip(icon: "waveform.path.ecg", tint: palette.heartRateColor,
                          title: "Camera vitals", subtitle: "Heart rate, HRV and hemoglobin — no cuff, no needle.")
            }
        }
    }

    private var aboutYouStep: some View {
        VStack(spacing: ZSSpacing.l) {
            heroIcon("person.fill", tint: palette.accent)
            Text("A little about you")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(palette.textPrimary)
            VStack(alignment: .leading, spacing: ZSSpacing.l) {
                VStack(alignment: .leading, spacing: ZSSpacing.s) {
                    Text("AGE").sectionLabel()
                    Stepper("\(age) years", value: $age, in: 5...110)
                        .tint(palette.accent)
                        .padding(ZSSpacing.standard)
                        .background(palette.surface)
                        .clipShape(ZSShapes.smallShape)
                        .overlay(ZSShapes.smallShape.stroke(palette.border, lineWidth: 0.5))
                }
                VStack(alignment: .leading, spacing: ZSSpacing.s) {
                    Text("SEX (FOR HB REFERENCE)").sectionLabel()
                    Picker("Sex", selection: $gender) {
                        ForEach(Gender.allCases, id: \.self) { g in Text(g.label).tag(g) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            Text("Used only to set your reference Hb range. Stored on your phone.")
                .font(ZSTypography.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var skinToneStep: some View {
        VStack(spacing: ZSSpacing.l) {
            heroIcon("hand.raised.fill", tint: palette.hemoglobinColor)
            Text("Your skin tone")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(palette.textPrimary)
            Text("Melanin changes how light moves through skin. Picking the closest tone sharpens your estimate. Optional.")
                .font(ZSTypography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(palette.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ZSSpacing.s), count: 5), spacing: ZSSpacing.m) {
                ForEach(MonkSkinTone.all, id: \.tone) { mst in
                    Button {
                        skinTone = mst.tone
                        ZSHaptics.selection()
                    } label: {
                        Circle()
                            .fill(Color(hex: UInt32(mst.hex.dropFirst()) ?? 0))
                            .frame(width: 46, height: 46)
                            .overlay(Circle().stroke(
                                skinTone == mst.tone ? palette.accent : Color.clear, lineWidth: 3))
                            .shadow(color: skinTone == mst.tone ? palette.accent.opacity(0.5) : .clear, radius: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Prefer not to say") {
                skinTone = nil
                ZSHaptics.selection()
            }
            .font(ZSTypography.body)
            .foregroundColor(skinTone == nil ? palette.accent : palette.textTertiary)
        }
    }

    private var disclaimerStep: some View {
        VStack(spacing: ZSSpacing.l) {
            heroIcon("heart.text.square.fill", tint: palette.cautionYellow)
            Text("Keep in mind")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(palette.textPrimary)
            Text("ZeroSqueeze gives a wellness estimate — not a diagnosis. Readings are approximate and depend on lighting, placement and skin tone. If anything looks off, or you have symptoms, see a clinician and confirm with a blood test.")
                .font(ZSTypography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(palette.textSecondary)
            Toggle(isOn: $acceptedDisclaimer) {
                Text("I understand this is not a medical device.")
                    .font(ZSTypography.body)
                    .foregroundColor(palette.textPrimary)
            }
            .tint(palette.accent)
            .padding(ZSSpacing.standard)
            .background(palette.surface)
            .clipShape(ZSShapes.smallShape)
            .overlay(ZSShapes.smallShape.stroke(palette.border, lineWidth: 0.5))
        }
    }

    // ── Reusable pieces ───────────────────────────────────────────────

    private func heroIcon(_ symbol: String, tint: Color) -> some View {
        ZStack {
            Circle().fill(tint.opacity(0.15)).frame(width: 88, height: 88)
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundColor(tint)
        }
    }

    private func valueChip(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: ZSSpacing.standard) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: icon).foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ZSTypography.bodyEmphasized)
                    .foregroundColor(palette.textPrimary)
                Text(subtitle)
                    .font(ZSTypography.caption)
                    .foregroundColor(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(ZSSpacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    // ── Footer: dots + nav ────────────────────────────────────────────

    private var footer: some View {
        VStack(spacing: ZSSpacing.l) {
            HStack(spacing: 7) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? palette.accent : palette.divider)
                        .frame(width: i == step ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.3), value: step)
                }
            }
            HStack(spacing: ZSSpacing.standard) {
                if step > 0 {
                    Button { goBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(ZSTypography.bodyEmphasized)
                            .foregroundColor(palette.textSecondary)
                            .frame(width: 52, height: 52)
                            .background(palette.surface)
                            .clipShape(ZSShapes.smallShape)
                            .overlay(ZSShapes.smallShape.stroke(palette.border, lineWidth: 0.5))
                    }
                    .accessibilityLabel("Back")
                }
                Button { advance() } label: {
                    Text(step == steps - 1 ? "Get started" : "Continue")
                }
                .buttonStyle(.zsPrimary)
                .disabled(step == steps - 1 && !acceptedDisclaimer)
            }
        }
    }

    private func advance() {
        if step < steps - 1 {
            withAnimation(.easeInOut(duration: 0.35)) { step += 1 }
            ZSHaptics.tap()
        } else {
            onComplete(UserProfile(age: age, gender: gender, skinTone: skinTone))
        }
    }

    private func goBack() {
        guard step > 0 else { return }
        withAnimation(.easeInOut(duration: 0.35)) { step -= 1 }
        ZSHaptics.tap()
    }
}

/// Animated concentric pulse rings expanding out from the app logo — the
/// welcome-screen centrepiece. Honours Reduce Motion (rings hold still).
/// Onboarding hero: a glowing, gently beating heart with an ECG sweep and
/// expanding pulse rings — a health-app hero, not the app-icon tile.
private struct ZSHero: View {
    @Environment(\.zsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rings = false
    @State private var beat = false

    var body: some View {
        ZStack {
            // Soft radial bloom behind the heart.
            Circle()
                .fill(palette.heartRateColor)
                .frame(width: 150, height: 150)
                .blur(radius: 70)
                .opacity(0.45)

            // Expanding pulse rings.
            ForEach(0..<3) { i in
                Circle()
                    .stroke(palette.heartRateColor.opacity(0.5), lineWidth: 2.5)
                    .frame(width: 132, height: 132)
                    .scaleEffect(rings ? 1.9 : 0.7)
                    .opacity(rings ? 0 : 0.7)
                    .animation(
                        reduceMotion ? nil :
                            .easeOut(duration: 2.6).repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.85),
                        value: rings
                    )
            }

            // Beating heart with the brand gradient.
            Image(systemName: "heart.fill")
                .resizable().scaledToFit()
                .frame(width: 104, height: 104)
                .foregroundStyle(palette.accentGradient)
                .shadow(color: palette.heartRateColor.opacity(0.6), radius: 26)
                .scaleEffect(beat ? 1.06 : 0.97)
                .overlay(ecgSweep.frame(width: 78).blendMode(.screen))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.62).repeatForever(autoreverses: true),
                    value: beat
                )
        }
        .frame(height: 220)
        .accessibilityHidden(true)
        .onAppear {
            if !reduceMotion { rings = true; beat = true }
        }
    }

    /// A small white ECG blip across the heart's centre.
    private var ecgSweep: some View {
        GeometryReader { geo in
            let w = geo.size.width, midY = geo.size.height / 2
            Path { p in
                p.move(to: CGPoint(x: 0, y: midY))
                p.addLine(to: CGPoint(x: w * 0.32, y: midY))
                p.addLine(to: CGPoint(x: w * 0.42, y: midY - 16))
                p.addLine(to: CGPoint(x: w * 0.52, y: midY + 20))
                p.addLine(to: CGPoint(x: w * 0.60, y: midY))
                p.addLine(to: CGPoint(x: w, y: midY))
            }
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 44)
    }
}

private extension UInt32 {
    init?(_ hex: Substring) {
        self.init(hex, radix: 16)
    }
}
