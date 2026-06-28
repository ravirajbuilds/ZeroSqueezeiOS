import Foundation
import QuartzCore

/// Drives a *fused* capture: chest SCG (CoreMotion) and finger PPG (camera +
/// torch) at the same time, on one monotonic clock, so pulse transit time can
/// be recovered (SCG AO → finger pulse). Produces a `HeartCheckMeasurement`
/// with cuffless BP, heart-health score and heart age.
///
/// Phases mirror the single-sensor flows.
@MainActor
final class HeartCheckViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case settling
        case capturing(progress: Double)
        case done(HeartCheckMeasurement)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveBpm: Int?
    @Published private(set) var liveQuality: Double = 0
    @Published private(set) var fingerCovered = false
    @Published private(set) var beatCount = 0
    @Published private(set) var waveform: [Double] = []
    private let waveformCapacity = 150

    let camera = CameraPPGService()
    let scg = SCGService()
    private let ppgProcessor = PPGProcessor()
    private let profile: UserProfile
    private let store: HeartCheckStore

    /// Fused capture needs both signals stable; 30 s gives enough paired beats
    /// for a robust median PTT.
    let captureSeconds: Double = 30

    private var ppgBuffer: [PPGSample] = []
    private var scgBuffer: [SCGSample] = []
    private var captureStartT: TimeInterval?
    private var stableSinceT: TimeInterval?
    private let coverageHysteresis: Double = 1.5

    /// Monotonic clock shared by both sensor streams (their native timestamps
    /// are on different clocks; we re-stamp at arrival).
    private func now() -> TimeInterval { CACurrentMediaTime() }

    init(profile: UserProfile, store: HeartCheckStore = .shared) {
        self.profile = profile
        self.store = store
        camera.onSample = { [weak self] s in self?.handlePPG(s) }
        scg.onSample = { [weak self] s in self?.handleSCG(s) }
    }

    func start() async {
        phase = .settling
        ppgProcessor.reset()
        ppgBuffer.removeAll(); scgBuffer.removeAll(); waveform.removeAll()
        captureStartT = nil; stableSinceT = nil; beatCount = 0
        await scg.start()
        await camera.start()
        if let err = camera.sessionError {
            phase = .failed(err)
        } else if !camera.isRunning {
            phase = .failed("Couldn't start the camera. Please try again.")
        }
    }

    func cancel() {
        camera.stop(); scg.stop()
        switch phase {
        case .done, .failed: return
        default: phase = .idle
        }
    }

    // ── Sample handling ────────────────────────────────────────────

    private func handleSCG(_ sample: SCGSample) {
        // Re-stamp on the shared clock; keep the axes.
        let s = SCGSample(t: now(), ax: sample.ax, ay: sample.ay, az: sample.az)
        if case .capturing = phase { scgBuffer.append(s) }
    }

    private func handlePPG(_ sample: PPGSample) {
        let t = now()
        let s = PPGSample(t: t, r: sample.r, g: sample.g, b: sample.b)
        fingerCovered = camera.fingerCovered
        ppgProcessor.ingest(s)
        liveBpm = ppgProcessor.heartRateBpm
        liveQuality = ppgProcessor.quality
        waveform.append(ppgProcessor.lastFilteredRed)
        if waveform.count > waveformCapacity { waveform.removeFirst(waveform.count - waveformCapacity) }

        switch phase {
        case .settling:
            if camera.fingerCovered {
                if stableSinceT == nil { stableSinceT = t }
                if let s0 = stableSinceT, t - s0 >= coverageHysteresis {
                    phase = .capturing(progress: 0); captureStartT = t
                }
            } else { stableSinceT = nil }

        case .capturing:
            guard camera.fingerCovered else {
                phase = .settling; stableSinceT = nil; captureStartT = nil
                ppgBuffer.removeAll(); scgBuffer.removeAll()
                return
            }
            ppgBuffer.append(s)
            beatCount = max(beatCount, ppgProcessor.ibis.count)
            guard let start = captureStartT else { return }
            let elapsed = t - start
            phase = .capturing(progress: min(1.0, elapsed / captureSeconds))
            if elapsed >= captureSeconds { finalize() }

        case .idle, .done, .failed:
            break
        }
    }

    private func finalize() {
        camera.stop(); scg.stop()
        let ppg = ppgBuffer, scgW = scgBuffer
        let age = profile.age
        Task { [weak self] in
            let result: HeartCheckMeasurement? = await Task.detached {
                Self.synthesize(ppg: ppg, scg: scgW, age: age)
            }.value
            if let result { self?.commit(result) }
            else { self?.phase = .failed("Couldn't pair the chest and finger pulses. Press the phone to your chest, keep a fingertip flat on the rear camera, hold still, and try again.") }
        }
    }

    /// Pure synthesis (off the main actor): HR + HRV from PPG, LVET from SCG,
    /// PTT from the fusion, BP from PTT, then the heart-health model.
    nonisolated private static func synthesize(ppg: [PPGSample], scg: [SCGSample], age: Int) -> HeartCheckMeasurement? {
        let ppgProc = PPGProcessor()
        for s in ppg { ppgProc.ingest(s) }
        let ppgF = ppgProc.features()
        let scgProc = SCGProcessor()
        for s in scg { scgProc.ingest(s) }
        let scgF = scgProc.features()

        guard let ptt = PulseTransitTime.estimate(scg: scg, ppg: ppg), ptt.confidence > 0.2 else { return nil }
        let hr = ppgF.heartRateBpm ?? scgF.heartRateBpm
        guard hr != nil else { return nil }
        let hrv: Double? = ppgF.ibiCount >= 4 ? ppgF.ibiStdMs : (scgF.ibiCount >= 4 ? scgF.ibiStdMs : nil)
        let bp = HeartHealthModel.bloodPressure(pttMs: ptt.pttMs)
        let hh = HeartHealthModel.evaluate(
            age: age, restingHR: hr, hrvSdnnMs: hrv,
            systolicMmHg: bp.systolic, lvetMs: scgF.lvetMs, respirationBpm: nil
        )
        let quality = Float(min(Double(ppgF.quality), 1.0) * 0.5 + ptt.confidence * 0.5)
        return HeartCheckMeasurement(
            id: UUID(), timestamp: Date(),
            heartRateBpm: hr, hrvSdnnMs: hrv, pttMs: ptt.pttMs,
            systolicMmHg: bp.systolic, diastolicMmHg: bp.diastolic, lvetMs: scgF.lvetMs,
            heartHealthScore: hh.score, heartAge: hh.heartAge, signalQuality: quality
        )
    }

    private func commit(_ m: HeartCheckMeasurement) {
        store.append(m)
        ZSHaptics.success()
        phase = .done(m)
    }
}
