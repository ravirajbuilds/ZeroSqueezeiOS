import Foundation
import CoreMotion

/// Drives CoreMotion's device-motion stream and emits per-frame
/// seismocardiography samples while the phone rests on the chest.
///
/// Concurrency contract mirrors `CameraPPGService`:
///   - `@MainActor` so `@Published` UI state is safe to read from SwiftUI.
///   - `CMMotionManager` callbacks are delivered on a dedicated
///     `OperationQueue`; each frame is repackaged and hopped to the main
///     actor in submission order via `DispatchQueue.main.async`, preserving
///     the monotonic-time invariant the `SCGProcessor` depends on.
@MainActor
final class SCGService: ObservableObject {

    // ── Published UI state ─────────────────────────────────────────
    @Published private(set) var isRunning = false
    /// True once the chest contact looks stable: low broadband motion (the
    /// user is holding still) with a detectable cardiac band. Gating on this
    /// keeps the capture from starting mid-fidget.
    @Published private(set) var contactStable = false
    @Published private(set) var sessionError: String?

    // ── Configuration ──────────────────────────────────────────────
    /// 100 Hz: well above the ~0.5–40 Hz SCG band and what CoreMotion
    /// reliably sustains on every supported device.
    nonisolated static let targetHz: Double = 100
    /// Broadband acceleration (g) below which we treat the phone as "still".
    nonisolated static let stillThreshold: Double = 0.06

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "zerosqueeze.scg.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    /// Consumer callback. Set before calling `start`.
    var onSample: ((SCGSample) -> Void)?

    /// Rolling broadband magnitude used only for the contact-stability gate.
    private var recentMagnitudes: [Double] = []
    private var generation = 0

    // ── Lifecycle ──────────────────────────────────────────────────

    func start() async {
        guard !isRunning else { return }
        generation &+= 1
        sessionError = nil
        recentMagnitudes.removeAll(keepingCapacity: true)

        guard motion.isDeviceMotionAvailable else {
            sessionError = "This device has no motion sensor for chest scans."
            isRunning = false
            return
        }

        motion.deviceMotionUpdateInterval = 1.0 / Self.targetHz
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, error in
            guard let data else {
                if let error { ZSLogger.error(.ppg, "SCG motion update failed", error: error) }
                return
            }
            // userAcceleration has gravity removed by CoreMotion's fusion, so
            // what's left is body + cardiac motion in g.
            let a = data.userAcceleration
            let sample = SCGSample(t: data.timestamp, ax: a.x, ay: a.y, az: a.z)
            let broadband = sample.magnitude
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning else { return }
                self.updateContact(broadband)
                self.onSample?(sample)
            }
        }
        isRunning = true
    }

    func stop() {
        generation &+= 1
        isRunning = false
        contactStable = false
        if motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }
    }

    // ── Contact gate ───────────────────────────────────────────────

    private func updateContact(_ broadband: Double) {
        recentMagnitudes.append(broadband)
        // ~1 s of history at 100 Hz.
        if recentMagnitudes.count > 100 {
            recentMagnitudes.removeFirst(recentMagnitudes.count - 100)
        }
        guard recentMagnitudes.count >= 40 else { contactStable = false; return }
        let mean = recentMagnitudes.reduce(0, +) / Double(recentMagnitudes.count)
        let variance = recentMagnitudes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(recentMagnitudes.count)
        let rms = variance.squareRoot()
        // Still phone on a beating chest: low gross motion (mean), but a small
        // non-zero pulsatile RMS. A phone on a table reads near-zero RMS; a
        // fidgeting hand reads a large mean.
        contactStable = mean < Self.stillThreshold && rms > 0.0008
    }
}
