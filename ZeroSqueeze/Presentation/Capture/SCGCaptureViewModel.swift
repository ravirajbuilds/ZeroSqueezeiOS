import Foundation

/// Drives the accelerometer + `SCGProcessor` through one guided chest
/// seismocardiography capture. Mirrors `CaptureViewModel` (fingertip) so the
/// UI patterns translate.
///
/// Phases:
///   - idle            — motion stream off.
///   - settling        — sensor running, waiting for stable chest contact.
///   - capturing       — collecting `captureSeconds` of stable signal.
///   - done            — emit `SCGMeasurement`, stop.
///   - failed          — show message; user can retry.
@MainActor
final class SCGCaptureViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case settling
        case capturing(progress: Double)
        case done(SCGMeasurement)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveBpm: Int?
    @Published private(set) var liveQuality: Double = 0
    @Published private(set) var contactStable = false
    /// Strictly-increasing detected-beat count — drives the live per-beat
    /// pulse animation + haptic on the capture screen.
    @Published private(set) var beatCount: Int = 0
    /// Rolling band-limited SCG envelope for the live waveform (newest-last).
    @Published private(set) var waveform: [Double] = []
    private let waveformCapacity = 200

    let sensor = SCGService()
    private let processor = SCGProcessor()
    private let store: SCGMeasurementStore
    /// Learned model when bundled, classic AO detector otherwise. The final HR
    /// comes from the router over the full capture buffer; the rolling
    /// processor only drives the live readout + LVET/HRV.
    private lazy var hrRouter = SCGHeartRateModelRouter.standard()
    private var sampleBuffer: [SCGSample] = []

    /// SCG needs a steady hold; 25 s gives enough beats for HRV + LVET.
    let captureSeconds: Double = 25

    private var captureStartT: TimeInterval?
    private var stableSinceT: TimeInterval?
    /// Continuous stable contact required before the timer starts.
    private let contactHysteresis: Double = 1.5

    init(store: SCGMeasurementStore = .shared) {
        self.store = store
        sensor.onSample = { [weak self] sample in
            self?.handle(sample: sample)
        }
    }

    func start() async {
        phase = .settling
        processor.reset()
        sampleBuffer.removeAll()
        waveform.removeAll()
        captureStartT = nil
        stableSinceT = nil
        await sensor.start()
        if let err = sensor.sessionError {
            phase = .failed(err)
        } else if !sensor.isRunning {
            phase = .failed("Couldn't start the motion sensor. Please try again.")
        }
    }

    func cancel() {
        sensor.stop()
        switch phase {
        case .done, .failed: return
        default: phase = .idle
        }
    }

    // ── Sample handling ────────────────────────────────────────────

    private func handle(sample: SCGSample) {
        contactStable = sensor.contactStable
        processor.ingest(sample)
        waveform.append(processor.lastEnvelope)
        if waveform.count > waveformCapacity {
            waveform.removeFirst(waveform.count - waveformCapacity)
        }
        if case .capturing = phase {
            sampleBuffer.append(sample)
        }
        liveBpm = processor.heartRateBpm
        liveQuality = processor.quality

        // Surface each newly-detected AO beat to the UI, and give a light tap
        // while capturing so the user feels their own heartbeat being read.
        if processor.beatCounter != beatCount {
            let isNewBeat = processor.beatCounter > beatCount
            beatCount = processor.beatCounter
            if isNewBeat, case .capturing = phase {
                ZSHaptics.tap(.light)
            }
        }

        switch phase {
        case .settling:
            if sensor.contactStable {
                if stableSinceT == nil { stableSinceT = sample.t }
                if let s = stableSinceT, sample.t - s >= contactHysteresis {
                    phase = .capturing(progress: 0)
                    captureStartT = sample.t
                }
            } else {
                stableSinceT = nil
            }

        case .capturing:
            guard sensor.contactStable else {
                phase = .settling
                stableSinceT = nil
                captureStartT = nil
                // Drop the partial buffer — a movement gap mid-window would
                // poison both backends with a discontinuity.
                sampleBuffer.removeAll()
                return
            }
            guard let start = captureStartT else { return }
            let elapsed = sample.t - start
            let progress = min(1.0, elapsed / captureSeconds)
            phase = .capturing(progress: progress)
            if elapsed >= captureSeconds {
                finalize()
            }

        case .idle, .done, .failed:
            break
        }
    }

    private func finalize() {
        sensor.stop()
        let features = processor.features()
        let buffer = sampleBuffer
        let router = hrRouter
        // Router inference + respiration fit are heavy (O(N) replay over a few
        // thousand samples). Run them off the main thread; results commit back
        // on the main actor (this Task inherits @MainActor isolation).
        Task { [weak self] in
            let (routed, respBpm) = await Task.detached { () -> (SCGHeartRateEstimate?, Double?) in
                let routed = router.estimate(window: buffer)
                // Reuse the PPG respiration estimator on the SCG magnitude
                // trace: the slow respiratory modulation of cardiac wall motion
                // is the same band the estimator fits.
                let asPPG = buffer.map { PPGSample(t: $0.t, r: $0.magnitude, g: 0, b: 0) }
                let resp = RespiratoryRateEstimator.estimate(window: asPPG, channel: .r)
                let respBpm = (resp?.confidence ?? 0) >= 0.4 ? resp?.breathsPerMin : nil
                return (routed, respBpm)
            }.value
            self?.commit(features: features, routed: routed, respBpm: respBpm)
        }
    }

    private func commit(features: SCGFeatures, routed: SCGHeartRateEstimate?, respBpm: Double?) {
        let confidence = routed?.confidence ?? features.quality
        let bpm = routed.map { Int($0.bpm.rounded()) } ?? features.heartRateBpm
        guard confidence > 0.2, bpm != nil else {
            phase = .failed("Couldn't read a clean heartbeat from your chest. Lie back, rest the phone flat on your breastbone, breathe normally, and try again.")
            return
        }
        let hrv: Double? = features.ibiCount >= 4 ? features.ibiStdMs : nil
        let bp = BloodPressureEstimator.estimate(
            lvetMs: features.lvetMs,
            hrBpm: bpm,
            signalQuality: Double(confidence),
            beatCount: features.ibiCount
        )
        let measurement = SCGMeasurement(
            id: UUID(),
            timestamp: Date(),
            heartRateBpm: bpm,
            hrvSdnnMs: hrv,
            respirationBpm: respBpm,
            lvetMs: features.lvetMs,
            aoAmplitudeMg: features.aoAmplitude > 0 ? features.aoAmplitude * 1000 : nil,
            estSystolicMmHg: bp?.systolicMmHg,
            estDiastolicMmHg: bp?.diastolicMmHg,
            signalQuality: Float(confidence),
            modelSource: routed?.source
        )
        store.append(measurement)
        ZSHaptics.success()
        phase = .done(measurement)
    }
}
