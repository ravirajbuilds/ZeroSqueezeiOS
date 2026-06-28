import SwiftUI
import AVFoundation

struct HeartCheckScreen: View {
    @ObservedObject var viewModel: HeartCheckViewModel
    @Environment(\.zsPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmCancel = false

    var body: some View {
        ZStack {
            palette.backgroundGradient.ignoresSafeArea()
            GeometryReader { geo in
                let markerSize = min(geo.size.height * 0.30, 240)
                VStack(spacing: ZSSpacing.l) {
                    header
                    Spacer(minLength: ZSSpacing.m)
                    marker(size: markerSize)
                    Spacer(minLength: ZSSpacing.m)
                    statusBlock
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(ZSSpacing.xl)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    if case .capturing = viewModel.phase { confirmCancel = true }
                    else { viewModel.cancel(); dismiss() }
                }
                .tint(palette.accent)
            }
        }
        .confirmationDialog("Stop this Heart Check?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { viewModel.cancel(); dismiss() }
            Button("Keep going", role: .cancel) {}
        } message: { Text("Your progress so far will be discarded.") }
        .task { await viewModel.start() }
        .onDisappear { viewModel.cancel() }
        .onChange(of: scenePhase) { _, p in if p != .active { viewModel.cancel() } }
    }

    private var header: some View {
        VStack(spacing: ZSSpacing.s) {
            Text("HEART CHECK · SCG + PPG").sectionLabel()
            Text(headline)
                .font(ZSTypography.title)
                .foregroundColor(palette.textPrimary)
                .multilineTextAlignment(.center)
        }
    }

    private var headline: String {
        switch viewModel.phase {
        case .idle, .settling:
            return "Press the phone to your chest, and rest a fingertip flat over the rear camera."
        case .capturing: return "Hold both still, breathe normally…"
        case .done: return "Done"
        case .failed(let m): return m
        }
    }

    private func marker(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(ringFill).frame(width: size, height: size)
                .shadow(color: palette.bpColor.opacity(0.4), radius: 30)
            if viewModel.fingerCovered {
                BeatPulse(beat: viewModel.beatCount, active: true, size: size * 0.34, color: palette.heartRateColor)
            } else {
                Image(systemName: "heart.text.square")
                    .resizable().scaledToFit().frame(width: size * 0.32, height: size * 0.32)
                    .foregroundColor(palette.textSecondary)
            }
            Circle().stroke(viewModel.fingerCovered ? palette.successGreen : palette.border, lineWidth: 2)
                .frame(width: size, height: size)
            if case .capturing(let progress) = viewModel.phase {
                Circle().trim(from: 0, to: CGFloat(progress))
                    .stroke(palette.accentGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: size, height: size)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
    }

    private var ringFill: Color {
        switch viewModel.phase {
        case .failed: return palette.alertRed.opacity(0.15)
        case .done: return palette.successGreen.opacity(0.15)
        case .capturing: return palette.bpColor.opacity(0.18)
        default: return palette.surface
        }
    }

    private var statusBlock: some View {
        VStack(spacing: ZSSpacing.m) {
            WaveformView(samples: viewModel.waveform, color: waveColor)
                .frame(height: 52)
                .opacity(viewModel.waveform.count >= 2 ? 1 : 0.3)
            HStack(spacing: ZSSpacing.xl) {
                stat("HEART RATE", viewModel.liveBpm.map { "\($0)" } ?? "—", "bpm")
                stat("FINGER", viewModel.fingerCovered ? "OK" : "—", "")
                stat("SIGNAL", String(format: "%.0f", viewModel.liveQuality * 100), "%")
            }
            Text(viewModel.fingerCovered
                 ? "Good. Keep the phone pressed to your chest."
                 : "Cover the rear camera + torch with a fingertip while the phone rests on your chest.")
                .font(ZSTypography.caption).foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
            if case .failed = viewModel.phase {
                Button("Try again") { Task { await viewModel.start() } }
                    .buttonStyle(.zsPrimary)
            }
        }
        .padding(ZSSpacing.l)
        .background(palette.surface)
        .clipShape(ZSShapes.cardShape)
        .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
    }

    private var waveColor: Color {
        if viewModel.liveQuality >= 0.6 { return palette.successGreen }
        if viewModel.liveQuality >= 0.3 { return palette.heartRateColor }
        return palette.cautionYellow
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(ZSTypography.metricLabel).foregroundColor(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(ZSTypography.metricValueSmall).foregroundColor(palette.textPrimary)
                if !unit.isEmpty { Text(unit).font(ZSTypography.captionTight).foregroundColor(palette.textSecondary) }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
