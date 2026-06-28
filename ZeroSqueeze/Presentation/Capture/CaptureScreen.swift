import SwiftUI
import AVFoundation

struct CaptureScreen: View {
    /// Owned by `CaptureFlow` (which holds the @StateObject). Observed here
    /// because a child view must never re-wrap the parent's StateObject.
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.zsPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmCancel = false
    @State private var wasInterrupted = false

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            GeometryReader { geo in
                let markerSize = min(geo.size.height * 0.34, 260)
                VStack(spacing: ZSSpacing.l) {
                    header
                    if wasInterrupted { interruptedBanner }
                    Spacer(minLength: ZSSpacing.m)
                    fingerPrintView(size: markerSize)
                    Spacer(minLength: ZSSpacing.m)
                    statusBlock
                    actionButton
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(ZSSpacing.xl)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    // Guard only an in-progress capture — losing a 20 s hold
                    // by a stray tap is the annoying case. Idle/done just exit.
                    if case .capturing = viewModel.phase {
                        confirmCancel = true
                    } else {
                        viewModel.cancel()
                        dismiss()
                    }
                }
                .tint(palette.accent)
            }
        }
        .confirmationDialog("Stop this scan?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Stop scan", role: .destructive) {
                viewModel.cancel()
                dismiss()
            }
            Button("Keep scanning", role: .cancel) {}
        } message: {
            Text("Your progress so far will be discarded.")
        }
        .task { await viewModel.start() }
        .onDisappear { viewModel.cancel() }
        // When the app backgrounds mid-capture, AVCaptureSession is suspended
        // by iOS but our torch + state machine keep going. Force-cancel so
        // torch turns off, no battery drain, no half-finished measurement —
        // and surface a banner so the user knows the scan needs restarting.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                if case .capturing = viewModel.phase { wasInterrupted = true }
                viewModel.cancel()
            }
        }
    }

    private var header: some View {
        VStack(spacing: ZSSpacing.s) {
            Text("FINGERTIP CAPTURE")
                .sectionLabel()
            Text(headlineForPhase)
                .font(ZSTypography.title)
                .foregroundColor(palette.textPrimary)
                .multilineTextAlignment(.center)
        }
    }

    private var interruptedBanner: some View {
        Label("Scan interrupted — tap Restart below to try again.", systemImage: "exclamationmark.triangle.fill")
            .font(ZSTypography.caption)
            .foregroundColor(palette.cautionYellow)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ZSSpacing.m)
            .background(palette.cautionYellow.opacity(0.12))
            .clipShape(ZSShapes.smallShape)
    }

    private var headlineForPhase: String {
        switch viewModel.phase {
        case .idle, .coverWaiting:
            return "Cover the rear camera and flash with your fingertip"
        case .capturing:
            return "Hold still…"
        case .done:
            return "Done"
        case .failed(let msg):
            return msg
        }
    }

    private func fingerPrintView(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(ringFill)
                .frame(width: size, height: size)
                .shadow(color: palette.hemoglobinColor.opacity(0.4), radius: 30)

            // Live rear-camera feed (not mirrored). Once the finger covers the
            // lens this fills with the torch-lit red field — direct visual
            // confirmation that coverage is good.
            if viewModel.camera.isRunning {
                CameraPreviewView(session: viewModel.camera.captureSession)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(systemName: "hand.point.up.left")
                    .resizable().scaledToFit()
                    .frame(width: size * 0.3, height: size * 0.3)
                    .foregroundColor(palette.textSecondary)
            }

            Circle()
                .stroke(viewModel.fingerCovered ? palette.successGreen : palette.border, lineWidth: 2)
                .frame(width: size, height: size)

            if case .capturing(let progress) = viewModel.phase {
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(palette.accentGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(viewModel.fingerCovered ? "Fingertip detected, capturing" : "Waiting for fingertip coverage")
    }

    private var ringFill: Color {
        switch viewModel.phase {
        case .failed: return palette.alertRed.opacity(0.15)
        case .done: return palette.successGreen.opacity(0.15)
        case .capturing: return palette.hemoglobinColor.opacity(0.18)
        default: return palette.surface
        }
    }

    private var statusBlock: some View {
        VStack(spacing: ZSSpacing.m) {
            WaveformView(samples: viewModel.waveform, color: waveformColor)
                .frame(height: 56)
                .opacity(viewModel.waveform.count >= 2 ? 1 : 0.3)
            HStack(spacing: ZSSpacing.xl) {
                stat(label: "HEART RATE", value: viewModel.liveBpm.map { "\($0)" } ?? "—", unit: "bpm")
                stat(label: "SIGNAL", value: String(format: "%.0f", viewModel.liveQuality * 100), unit: "%")
            }
            Text(coverageHint)
                .font(ZSTypography.caption)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(ZSSpacing.l)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    private var coverageHint: String {
        if viewModel.fingerCovered { return "Good coverage. Keep holding." }
        return "Place your fingertip flat over the camera and torch."
    }

    private var waveformColor: Color {
        if viewModel.liveQuality >= 0.6 { return palette.successGreen }
        if viewModel.liveQuality >= 0.35 { return palette.hemoglobinColor }
        return palette.cautionYellow
    }

    private func stat(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(ZSTypography.metricLabel)
                .foregroundColor(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(ZSTypography.metricValueSmall)
                    .foregroundColor(palette.textPrimary)
                Text(unit)
                    .font(ZSTypography.captionTight)
                    .foregroundColor(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch viewModel.phase {
        case .failed:
            if cameraDenied {
                Button("Open Settings") { openSettings() }
                    .buttonStyle(.zsPrimary)
            } else {
                Button("Try again") {
                    wasInterrupted = false
                    Task { await viewModel.start() }
                }
                .buttonStyle(.zsPrimary)
            }
        case .idle, .coverWaiting:
            // After a background interruption `cancel()` leaves the VM `.idle`
            // with the camera stopped and `.task` won't refire — surface an
            // explicit Restart so the banner's instruction is actionable.
            if wasInterrupted {
                Button("Restart scan") {
                    wasInterrupted = false
                    Task { await viewModel.start() }
                }
                .buttonStyle(.zsPrimary)
            }
        default:
            EmptyView()
        }
    }

    /// True when the camera failure is a permanent permission denial — only an
    /// Open-Settings round-trip can fix it, so "Try again" would be a dead end.
    private var cameraDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
