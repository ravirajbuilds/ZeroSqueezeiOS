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
    /// Synthetic-signal timer used on the simulator (no accelerometer there).
    private var synthTimer: DispatchSourceTimer?
    private var synthT: TimeInterval = 0
    private let synthQueue = DispatchQueue(label: "zerosqueeze.scg.synth")

    // ── Lifecycle ──────────────────────────────────────────────────

    func start() async {
        guard !isRunning else { return }
        generation &+= 1
        sessionError = nil
        recentMagnitudes.removeAll(keepingCapacity: true)

        // The iOS Simulator has no accelerometer. Rather than dead-end the
        // whole chest-scan flow there, drive it from a synthetic SCG generator
        // so the capture → result UI can be exercised without hardware. On a
        // real device this branch is compiled out and the sensor is required.
        #if targetEnvironment(simulator)
        startSynthetic()
        isRunning = true
        return
        #endif

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
        synthTimer?.cancel()
        synthTimer = nil
        if motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }
    }

    // ── Synthetic signal (simulator only) ──────────────────────────

    /// Emits a physiologically-shaped SCG trace at `targetHz`: a per-beat AO
    /// complex, an AC lobe one ejection-time later, respiration modulation and
    /// a little noise — enough for the processor to recover HR, HRV, LVET and a
    /// BP index so the full flow is demoable on the simulator.
    private func startSynthetic() {
        synthT = 0
        let dt = 1.0 / Self.targetHz
        let timer = DispatchSource.makeTimerSource(queue: synthQueue)
        timer.schedule(deadline: .now(), repeating: dt)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let t = self.synthT
            self.synthT += dt
            let az = Self.syntheticSCG(at: t)
            let sample = SCGSample(t: t, ax: 0, ay: 0, az: az)
            let broadband = sample.magnitude
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning else { return }
                self.updateContact(broadband)
                self.onSample?(sample)
            }
        }
        synthTimer = timer
        timer.resume()
    }

    /// One sample of a synthetic SCG magnitude trace at ~66 bpm with a ~300 ms
    /// ejection time (AO→AC).
    private nonisolated static func syntheticSCG(at t: TimeInterval) -> Double {
        let bpm = 66.0
        let period = 60.0 / bpm
        let phase = t.truncatingRemainder(dividingBy: period)
        var a = 0.0
        // AO complex: 60 ms damped 30 Hz burst at the start of each beat.
        if phase < 0.06 {
            a += 0.03 * exp(-phase / 0.012) * sin(2 * .pi * 30 * phase)
        }
        // AC complex: smaller lobe ~300 ms later (drives LVET).
        let acPhase = phase - 0.30
        if acPhase >= 0, acPhase < 0.05 {
            a += 0.013 * exp(-acPhase / 0.012) * sin(2 * .pi * 26 * acPhase)
        }
        // Respiration AM (~0.25 Hz) + small noise.
        a *= 1.0 + 0.15 * sin(2 * .pi * 0.25 * t)
        a += Double.random(in: -0.0015...0.0015)
        return a
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
