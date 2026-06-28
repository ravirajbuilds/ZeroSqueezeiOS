import SwiftUI

struct SCGCaptureScreen: View {
    @ObservedObject var viewModel: SCGCaptureViewModel
    @Environment(\.zsPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmCancel = false
    @State private var wasInterrupted = false

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            GeometryReader { geo in
                let markerSize = min(geo.size.height * 0.32, 260)
                VStack(spacing: ZSSpacing.l) {
                    header
                    if wasInterrupted { interruptedBanner }
                    Spacer(minLength: ZSSpacing.m)
                    chestMarker(size: markerSize)
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
        // Stop the motion stream on background so the capture loop doesn't run
        // while the user is elsewhere in iOS; tell them the scan needs restarting.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                if case .capturing = viewModel.phase { wasInterrupted = true }
                viewModel.cancel()
            }
        }
    }

    private var header: some View {
        VStack(spacing: ZSSpacing.s) {
            Text("CHEST SCG SCAN")
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
        case .idle, .settling:
            return "Lie back. Rest the phone flat on your breastbone, screen up."
        case .capturing:
            return "Hold still, breathe normally…"
        case .done:
            return "Done"
        case .failed(let msg):
            return msg
        }
    }

    private func chestMarker(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(ringFill)
                .frame(width: size, height: size)
                .shadow(color: palette.heartRateColor.opacity(0.4), radius: 30)

            if contactStable {
                BeatPulse(
                    beat: viewModel.beatCount,
                    active: true,
                    size: size * 0.34,
                    color: palette.heartRateColor
                )
            } else {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .resizable().scaledToFit()
                    .frame(width: size * 0.32, height: size * 0.32)
                    .foregroundColor(palette.textSecondary)
                    .symbolEffect(.pulse, options: .repeating, value: contactStable)
            }

            Circle()
                .stroke(contactStable ? palette.successGreen : palette.border, lineWidth: 2)
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
        .accessibilityLabel(contactStable ? "Chest contact stable, capturing" : "Settle the phone on your chest")
    }

    private var contactStable: Bool { viewModel.contactStable }

    private var ringFill: Color {
        switch viewModel.phase {
        case .failed: return palette.alertRed.opacity(0.15)
        case .done: return palette.successGreen.opacity(0.15)
        case .capturing: return palette.heartRateColor.opacity(0.18)
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
            Text(hint)
                .font(ZSTypography.caption)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(ZSSpacing.l)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    private var hint: String {
        if contactStable { return "Contact locked. Keep still and breathe slowly." }
        return "Quietest readings come lying down, phone flat on the sternum."
    }

    private var waveformColor: Color {
        if viewModel.liveQuality >= 0.6 { return palette.successGreen }
        if viewModel.liveQuality >= 0.3 { return palette.heartRateColor }
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
            Button("Try again") {
                wasInterrupted = false
                Task { await viewModel.start() }
            }
            .buttonStyle(.zsPrimary)
        case .idle, .settling:
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
}
