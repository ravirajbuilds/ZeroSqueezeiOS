import SwiftUI

/// The "Scan" tab — a single hub for starting any capture: scg (HR/HRV),
/// fingertip (hemoglobin), or a guided breathing session. Pulls the launch
/// affordances out of the dashboard so each is a deliberate, equal choice.
struct ScanScreen: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.zsPalette) private var palette

    @State private var showFingertipCapture = false
    @State private var showChestCapture = false
    @State private var showHeartCheck = false
    @State private var showBreathing = false

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: ZSSpacing.l) {
                    card(
                        title: "Heart Check (SCG + PPG)",
                        subtitle: "The full picture: press the phone to your chest and a fingertip on the rear camera. Fuses both pulses for cuffless blood pressure, a heart-health score & heart age. ~30 seconds.",
                        icon: "heart.text.square.fill",
                        accent: palette.bpColor
                    ) { ZSHaptics.tap(.medium); showHeartCheck = true }

                    card(
                        title: "Chest scan (SCG)",
                        subtitle: "Lie back, rest the phone on your breastbone. Heart rate, HRV, ejection time & a blood-pressure index from cardiac vibrations. ~25 seconds.",
                        icon: "waveform.path.ecg",
                        accent: palette.heartRateColor
                    ) { ZSHaptics.tap(.medium); showChestCapture = true }

                    card(
                        title: "Fingertip hemoglobin",
                        subtitle: "Cover the rear camera and flash with a fingertip to estimate hemoglobin.",
                        icon: "hand.point.up.left.fill",
                        accent: palette.hemoglobinColor
                    ) { ZSHaptics.tap(.medium); showFingertipCapture = true }

                    card(
                        title: "Guided breathing",
                        subtitle: "A calm, paced session to lower your pulse and reset.",
                        icon: "wind",
                        accent: palette.hrvColor
                    ) { ZSHaptics.tap(.medium); showBreathing = true }
                }
                .padding(ZSSpacing.xl)
            }
        }
        .navigationTitle("Scan")
        .fullScreenCover(isPresented: $showFingertipCapture) {
            NavigationStack {
                CaptureFlow(
                    profile: appState.profile ?? .placeholder,
                    onCalibrate: { lab, raw in appState.calibrate(labHb: lab, rawEstimate: raw) },
                    onClose: { showFingertipCapture = false }
                )
            }
        }
        .fullScreenCover(isPresented: $showChestCapture) {
            NavigationStack { SCGCaptureFlow { showChestCapture = false } }
        }
        .fullScreenCover(isPresented: $showHeartCheck) {
            NavigationStack {
                HeartCheckFlow(profile: appState.profile ?? .placeholder) { showHeartCheck = false }
            }
        }
        .fullScreenCover(isPresented: $showBreathing) {
            BreathingScreen()
        }
    }

    private func card(title: String, subtitle: String, icon: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: ZSSpacing.l) {
                ZStack {
                    Circle().fill(accent.opacity(0.15)).frame(width: 56, height: 56)
                    Image(systemName: icon).font(.title2).foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(ZSTypography.title)
                        .foregroundColor(palette.textPrimary)
                    Text(subtitle)
                        .font(ZSTypography.caption)
                        .foregroundColor(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(ZSSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .clipShape(ZSShapes.cardShape)
            .overlay(ZSShapes.cardShape.stroke(accent.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
