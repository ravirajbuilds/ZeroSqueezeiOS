import SwiftUI

/// Shared capture flows reused by the Today and Scan tabs. Each wraps a
/// capture view-model and swaps to the matching result screen when the
/// capture finishes.

/// Fingertip capture → Hb result.
struct CaptureFlow: View {
    let profile: UserProfile
    let onCalibrate: (Float, Float) -> Void
    let onClose: () -> Void

    @StateObject private var viewModel: CaptureViewModel

    init(
        profile: UserProfile,
        onCalibrate: @escaping (Float, Float) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.profile = profile
        self.onCalibrate = onCalibrate
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: CaptureViewModel(profile: profile))
    }

    var body: some View {
        Group {
            if case .done(let m) = viewModel.phase {
                ResultScreen(measurement: m, onDone: onClose, onCalibrate: onCalibrate)
            } else {
                CaptureScreen(viewModel: viewModel)
            }
        }
    }
}

/// Chest capture → HR / HRV result.
struct SCGCaptureFlow: View {
    let onClose: () -> Void

    @StateObject private var viewModel = SCGCaptureViewModel()

    var body: some View {
        Group {
            if case .done(let m) = viewModel.phase {
                SCGResultScreen(measurement: m, onDone: onClose)
            } else {
                SCGCaptureScreen(viewModel: viewModel)
            }
        }
    }
}
