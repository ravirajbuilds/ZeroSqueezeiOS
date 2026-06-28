import Foundation

/// Online PPG signal analyser.
///
/// Maintains rolling buffers of (t, red), runs a moving-average detrend
/// and a 2-pole IIR bandpass, then a peak detector that emits inter-beat
/// intervals (IBIs). Heart-rate, perfusion index and signal quality are
/// derived from the rolling window.
///
/// Designed to be cheap — every call is O(1) per sample plus an O(N)
/// window mean. N is bounded by `windowSeconds × sampleRate`.
final class PPGProcessor {

    // ── Public outputs (read after each sample) ────────────────────

    /// Latest filtered AC value of the red channel.
    private(set) var lastFilteredRed: Double = 0
    /// Mean red in current window (the DC level).
    private(set) var dcRed: Double = 0
    /// Rolling AC amplitude (peak-to-trough average) of red.
    private(set) var acRed: Double = 0
    /// Most recent perfusion index = (AC / DC) × 100.
    private(set) var perfusionIndex: Double = 0
    /// Recent inter-beat intervals (seconds).
    private(set) var ibis: [Double] = []
    /// Confidence in the heart rate estimate, [0, 1].
    private(set) var quality: Double = 0
    /// Mean green / blue DC levels — used by the Hb estimator.
    private(set) var dcGreen: Double = 0
    private(set) var dcBlue: Double = 0
    private(set) var acGreen: Double = 0

    /// Heart rate in BPM, or nil if signal not yet stable.
    var heartRateBpm: Int? {
        let valid = ibis.suffix(8).filter { $0 > 0.3 && $0 < 1.7 }
        guard valid.count >= 3 else { return nil }
        let mean = valid.reduce(0, +) / Double(valid.count)
        return Int((60.0 / mean).rounded())
    }

    // ── Config ─────────────────────────────────────────────────────

    /// Length of detrend window.
    let windowSeconds: Double
    /// Sampling rate hint. Updated automatically from sample timestamps.
    private(set) var sampleRate: Double
    /// Minimum AC peak-to-trough amplitude (0-255 space) required before the
    /// peak detector will emit. Fingertip-with-torch defaults to 3; low-amplitude PPG
    /// (where pulsatile amplitudes are typically 0.5-2) must lower this.
    let noiseFloor: Double
    /// Absolute floor for the adaptive peak threshold. Same units as `noiseFloor`.
    let minPeakThreshold: Double
    /// AC amplitude (0-255 space) that maps to a full-credit quality acScore.
    /// Fingertip-with-torch AC runs ~10-60 so 40 is "strong"; low-amplitude PPG AC is
    /// ~0.5-2, so the scg path must pass a far smaller scale or acScore is
    /// permanently ~0 and quality is driven by PI/stability alone.
    let acQualityScale: Double

    /// Initial sampleRate hint — also restored by `reset()` so a re-armed
    /// capture doesn't inherit the previous run's measured rate.
    private let initialSampleRate: Double

    init(
        windowSeconds: Double = 4.0,
        sampleRate: Double = 30,
        noiseFloor: Double = 3,
        minPeakThreshold: Double = 1.0,
        acQualityScale: Double = 40
    ) {
        self.windowSeconds = windowSeconds
        self.sampleRate = sampleRate
        self.initialSampleRate = sampleRate
        self.noiseFloor = noiseFloor
        self.minPeakThreshold = minPeakThreshold
        self.acQualityScale = acQualityScale
    }

    // ── State ──────────────────────────────────────────────────────

    private var samples: [PPGSample] = []
    private var filtered: [Double] = []
    private var greenFiltered: [Double] = []

    /// Exposed for tests so the trim-window invariant (bounded buffer) can
    /// be asserted without poking private state.
    var bufferCount: Int { samples.count }
    /// Time of last detected peak.
    private var lastPeakT: Double?
    /// Rolling refractory: ignore peaks within 300 ms of last peak (200 BPM cap).
    private let refractory: Double = 0.3

    // ── Public API ─────────────────────────────────────────────────

    func reset() {
        samples.removeAll(keepingCapacity: true)
        filtered.removeAll(keepingCapacity: true)
        greenFiltered.removeAll(keepingCapacity: true)
        ibis.removeAll(keepingCapacity: true)
        lastPeakT = nil
        lastFilteredRed = 0
        dcRed = 0; dcGreen = 0; dcBlue = 0
        acRed = 0; acGreen = 0
        perfusionIndex = 0
        quality = 0
        sampleRate = initialSampleRate
    }

    /// Append one sample. Cheap. Caller should drive at ~targetFps.
    @discardableResult
    func ingest(_ sample: PPGSample) -> Bool {
        samples.append(sample)
        trimWindow()
        updateSampleRate()
        recomputeDC()
        let ac = sample.r - dcRed
        filtered.append(ac)
        greenFiltered.append(sample.g - dcGreen)
        if filtered.count > samples.count { filtered.removeFirst(filtered.count - samples.count) }
        if greenFiltered.count > samples.count { greenFiltered.removeFirst(greenFiltered.count - samples.count) }
        lastFilteredRed = ac
        recomputeACAndPI()
        detectPeak()
        recomputeQuality()
        return true
    }

    /// Latest features for the Hb estimator.
    func features() -> PPGFeatures {
        PPGFeatures(
            sampleRate: sampleRate,
            dcRed: dcRed,
            dcGreen: dcGreen,
            dcBlue: dcBlue,
            acRed: acRed,
            acGreen: acGreen,
            perfusionIndex: perfusionIndex,
            heartRateBpm: heartRateBpm,
            ibiCount: ibis.count,
            ibiStdMs: ibiStdMs,
            quality: quality
        )
    }

    var ibiStdMs: Double {
        // Filter to the same physiological IBI range the BPM getter uses
        // (35–200 BPM), so one spurious interval can't inflate the reported
        // SDNN while being ignored by the heart-rate readout.
        let valid = ibis.filter { $0 > 0.3 && $0 < 1.7 }
        guard valid.count >= 3 else { return 0 }
        let mean = valid.reduce(0, +) / Double(valid.count)
        let variance = valid.map { pow($0 - mean, 2) }.reduce(0, +) / Double(valid.count)
        return sqrt(variance) * 1000
    }

    // ── Internals ──────────────────────────────────────────────────

    private func trimWindow() {
        guard let last = samples.last?.t else { return }
        // Trim oldest samples that fall outside the window. The `age < 0`
        // branch catches a non-monotonic timestamp (e.g. camera session
        // restart resetting PTS); without it the window would never shed
        // older entries and `samples` would grow unbounded.
        while let first = samples.first {
            let age = last - first.t
            if age > windowSeconds || age < 0 {
                samples.removeFirst()
            } else {
                break
            }
        }
    }

    private func updateSampleRate() {
        guard samples.count >= 2 else { return }
        let first = samples.first!.t
        let last = samples.last!.t
        let dt = last - first
        if dt > 0 {
            sampleRate = Double(samples.count - 1) / dt
        }
    }

    private func recomputeDC() {
        guard !samples.isEmpty else { return }
        var r = 0.0, g = 0.0, b = 0.0
        for s in samples { r += s.r; g += s.g; b += s.b }
        let n = Double(samples.count)
        dcRed = r / n
        dcGreen = g / n
        dcBlue = b / n
    }

    private func recomputeACAndPI() {
        guard !filtered.isEmpty else { return }
        // Floor at 1 sample so a transient sub-1 Hz sampleRate estimate (e.g.
        // very first frames before the rate stabilises) doesn't produce a
        // zero-length window slice and stall AC/PI updates.
        let windowN = max(1, Int(sampleRate * 2))
        let recent = filtered.suffix(min(filtered.count, windowN))
        let maxV = recent.max() ?? 0
        let minV = recent.min() ?? 0
        acRed = max(0, maxV - minV)
        perfusionIndex = dcRed > 0 ? (acRed / dcRed) * 100 : 0
        let recentG = greenFiltered.suffix(min(greenFiltered.count, windowN))
        acGreen = max(0, (recentG.max() ?? 0) - (recentG.min() ?? 0))
    }

    /// Simple slope-change peak detector with adaptive threshold (0.5 × recent AC half-amplitude).
    private func detectPeak() {
        guard samples.count >= 3, filtered.count == samples.count else { return }
        // Absolute noise floor: AC peak-to-trough must clear `noiseFloor`.
        // Below this the signal is dominated by shot noise — emitting peaks
        // would just produce a noise-driven false heart rate. Tuned per
        // instance (fingertip ≈ 3, low-amplitude PPG ≈ 0.3).
        guard acRed >= noiseFloor else { return }
        let n = samples.count
        let i = n - 2
        let prev = filtered[i - 1]
        let curr = filtered[i]
        let next = filtered[i + 1]
        guard curr > prev, curr >= next else { return }
        let threshold = max(0.25 * acRed, minPeakThreshold)
        guard curr > threshold else { return }
        let t = samples[i].t
        if let last = lastPeakT, t - last < refractory { return }
        if let last = lastPeakT {
            ibis.append(t - last)
            if ibis.count > 16 { ibis.removeFirst(ibis.count - 16) }
        }
        lastPeakT = t
    }

    private func recomputeQuality() {
        // Three signals combine into a [0, 1] quality:
        //   1. PI > 0.5 indicates good perfusion (clamped at 5 = great).
        //   2. AC amplitude relative to noise floor (here approximated as recent
        //      standard deviation of differences).
        //   3. IBI variability < 25% suggests stable HR.
        let piScore = min(1.0, max(0, perfusionIndex / 4.0))
        let acScore = min(1.0, acRed / max(0.0001, acQualityScale))
        let stab: Double
        if ibis.count >= 3 {
            let mean = ibis.reduce(0, +) / Double(ibis.count)
            let cv = ibiStdMs / max(1, mean * 1000)
            stab = max(0, 1.0 - cv / 0.30)
        } else {
            stab = 0
        }
        quality = 0.4 * piScore + 0.3 * acScore + 0.3 * stab
    }
}

struct PPGFeatures {
    let sampleRate: Double
    let dcRed: Double
    let dcGreen: Double
    let dcBlue: Double
    let acRed: Double
    let acGreen: Double
    let perfusionIndex: Double
    let heartRateBpm: Int?
    let ibiCount: Int
    let ibiStdMs: Double
    let quality: Double

    /// Red-over-green ratio of the AC/DC components.
    ///
    /// This is the smartphone analogue of the SpO2 R-ratio: the two channels
    /// have different absorption curves for oxy- vs deoxy- haemoglobin, so the
    /// ratio of pulsatile amplitudes is informative for blood composition.
    var rRatio: Double {
        guard dcRed > 0, dcGreen > 0, acGreen > 0 else { return 0 }
        return (acRed / dcRed) / (acGreen / dcGreen)
    }
}
