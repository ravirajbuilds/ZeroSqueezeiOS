import Foundation

/// Drives the camera + processor through a single guided capture.
///
/// Phases:
///   - idle          — torch off, awaiting tap.
///   - coverWaiting  — torch on, asking the user to cover lens with finger.
///   - capturing     — collecting `captureSeconds` of stable signal.
///   - done          — emit final `HbMeasurement`, stop.
///   - failed        — show message; user can retry.
@MainActor
final class CaptureViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case coverWaiting
        case capturing(progress: Double)
        case done(HbMeasurement)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveBpm: Int?
    @Published private(set) var liveQuality: Double = 0
    @Published private(set) var liveRed: Double = 0
    @Published private(set) var fingerCovered = false
    /// Rolling AC trace for the live waveform (most-recent-last).
    @Published private(set) var waveform: [Double] = []
    private let waveformCapacity = 150

    let camera = CameraPPGService()
    private let processor = PPGProcessor()
    private let profile: UserProfile
    private let store: MeasurementStore
    private let calibrationStore: CalibrationStore

    /// Seconds of stable signal we collect before producing a result.
    let captureSeconds: Double = 20

    private var captureStartT: TimeInterval?
    private var stableSinceT: TimeInterval?
    /// Need 1.5 s of continuous coverage before starting the timer.
    private let coverageHysteresis: Double = 1.5

    init(
        profile: UserProfile,
        store: MeasurementStore = .shared,
        calibrationStore: CalibrationStore = .shared
    ) {
        self.profile = profile
        self.store = store
        self.calibrationStore = calibrationStore
        camera.onSample = { [weak self] sample in
            self?.handle(sample: sample)
        }
    }

    private func appendWaveform(_ value: Double) {
        waveform.append(value)
        if waveform.count > waveformCapacity {
            waveform.removeFirst(waveform.count - waveformCapacity)
        }
    }

    func start() async {
        phase = .coverWaiting
        processor.reset()
        waveform.removeAll()
        captureStartT = nil
        stableSinceT = nil
        await camera.start()
        // Surface camera startup failures as a terminal phase so the user
        // sees the error and the "Try again" button instead of an idle screen.
        if let err = camera.sessionError {
            phase = .failed(err)
        } else if !camera.isRunning {
            phase = .failed("Couldn't start the camera. Please try again.")
        }
    }

    /// Stops the camera. Preserves `.done` / `.failed` phases so an
    /// `.onDisappear` after the result screen takes over doesn't wipe the
    /// terminal state and bounce the user back to the capture screen.
    func cancel() {
        camera.stop()
        switch phase {
        case .done, .failed: return
        default: phase = .idle
        }
    }

    // ── Sample handling ────────────────────────────────────────────

    private func handle(sample: PPGSample) {
        liveRed = sample.r
        fingerCovered = camera.fingerCovered

        processor.ingest(sample)
        liveBpm = processor.heartRateBpm
        liveQuality = processor.quality
        appendWaveform(processor.lastFilteredRed)

        switch phase {
        case .coverWaiting:
            if camera.fingerCovered {
                if stableSinceT == nil { stableSinceT = sample.t }
                if let s = stableSinceT, sample.t - s >= coverageHysteresis {
                    phase = .capturing(progress: 0)
                    captureStartT = sample.t
                }
            } else {
                stableSinceT = nil
            }

        case .capturing:
            guard camera.fingerCovered else {
                phase = .coverWaiting
                stableSinceT = nil
                captureStartT = nil
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
        camera.stop()
        let features = processor.features()
        guard features.quality > 0.2 else {
            phase = .failed("Signal too weak. Press your fingertip flat over both the camera and flash, hold still.")
            return
        }
        let estimate = HemoglobinEstimator.estimate(
            features: features,
            profile: profile,
            correction: calibrationStore.correction
        )
        let measurement = HbMeasurement(
            id: UUID(),
            timestamp: Date(),
            heartRateBpm: features.heartRateBpm,
            hemoglobinGPerDl: estimate.hemoglobinGPerDl,
            rawHemoglobinGPerDl: estimate.rawHemoglobinGPerDl,
            hemoglobinBand: estimate.band,
            perfusionIndex: estimate.perfusionIndex,
            signalQuality: estimate.quality,
            anemia: estimate.anemia,
            genderAtCapture: profile.gender
        )
        store.append(measurement)
        ZSHaptics.success()
        phase = .done(measurement)
    }
}
