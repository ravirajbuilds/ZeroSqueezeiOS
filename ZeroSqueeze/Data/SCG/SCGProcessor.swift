import Foundation

/// Online seismocardiography analyser.
///
/// Pipeline, per sample, on the vector-magnitude trace:
///   1. DC removal over a rolling window (detrend).
///   2. A cardiac-band emphasis: short moving-average envelope of the squared
///      band-limited signal — Pan-Tompkins style energy that makes the AO
///      complex stand out from respiratory drift and broadband shake.
///   3. Adaptive-threshold peak detection over the envelope → AO peaks → IBIs.
///
/// Outputs heart rate (AO-to-AO), HRV (SDNN), signal quality, the mean AO
/// amplitude (a contractility proxy), and — by searching each beat's diastolic
/// window for the second energy lobe — left-ventricular ejection time (LVET =
/// AO→AC). All O(1) per sample plus an O(N) bounded-window pass.
final class SCGProcessor {

    // ── Public outputs ─────────────────────────────────────────────
    private(set) var lastEnvelope: Double = 0
    private(set) var ibis: [Double] = []
    private(set) var quality: Double = 0
    /// Mean AO-complex peak amplitude over the window, in g.
    private(set) var aoAmplitude: Double = 0
    /// Strictly-increasing count of accepted AO peaks since `reset()`. Unlike
    /// `ibis.count` (which is trimmed to a rolling window) this only grows, so
    /// UIs can drive a per-beat animation/haptic off changes to it.
    private(set) var beatCounter: Int = 0

    var heartRateBpm: Int? {
        let valid = ibis.suffix(10).filter { $0 > 0.3 && $0 < 1.7 }
        guard valid.count >= 3 else { return nil }
        let mean = valid.reduce(0, +) / Double(valid.count)
        return Int((60.0 / mean).rounded())
    }

    /// SDNN over the physiological IBI range, milliseconds. 0 if too few beats.
    var ibiStdMs: Double {
        let valid = ibis.filter { $0 > 0.3 && $0 < 1.7 }
        guard valid.count >= 3 else { return 0 }
        let mean = valid.reduce(0, +) / Double(valid.count)
        let variance = valid.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(valid.count)
        return variance.squareRoot() * 1000
    }

    // ── Config ─────────────────────────────────────────────────────
    let windowSeconds: Double
    private(set) var sampleRate: Double
    private let initialSampleRate: Double
    /// Envelope smoothing window in seconds (~AO complex width).
    private let envelopeSeconds = 0.05
    /// Refractory between AO peaks (300 ms → 200 BPM cap).
    private let refractory = 0.3

    init(windowSeconds: Double = 6.0, sampleRate: Double = 100) {
        self.windowSeconds = windowSeconds
        self.sampleRate = sampleRate
        self.initialSampleRate = sampleRate
    }

    // ── State ──────────────────────────────────────────────────────
    private var samples: [SCGSample] = []
    private var detrended: [Double] = []
    private var envelope: [Double] = []
    private var lastPeakT: Double?
    private var peakAmps: [Double] = []
    /// (peakTime, envelopeValue) pairs, used for LVET search.
    private var peaks: [(t: Double, amp: Double)] = []

    var bufferCount: Int { samples.count }

    func reset() {
        samples.removeAll(keepingCapacity: true)
        detrended.removeAll(keepingCapacity: true)
        envelope.removeAll(keepingCapacity: true)
        ibis.removeAll(keepingCapacity: true)
        peakAmps.removeAll(keepingCapacity: true)
        peaks.removeAll(keepingCapacity: true)
        lastPeakT = nil
        lastEnvelope = 0
        aoAmplitude = 0
        quality = 0
        beatCounter = 0
        sampleRate = initialSampleRate
    }

    @discardableResult
    func ingest(_ sample: SCGSample) -> Bool {
        samples.append(sample)
        trimWindow()
        updateSampleRate()

        // 1. Detrend: subtract the rolling DC (mean magnitude).
        let dc = samples.reduce(0.0) { $0 + $1.magnitude } / Double(samples.count)
        let ac = sample.magnitude - dc
        detrended.append(ac)
        if detrended.count > samples.count { detrended.removeFirst(detrended.count - samples.count) }

        // 2. Energy envelope: moving average of the squared detrended signal.
        let envN = max(1, Int(sampleRate * envelopeSeconds))
        let slice = detrended.suffix(envN)
        let env = slice.reduce(0.0) { $0 + $1 * $1 } / Double(slice.count)
        envelope.append(env)
        if envelope.count > samples.count { envelope.removeFirst(envelope.count - samples.count) }
        lastEnvelope = env.squareRoot()

        detectPeak()
        recomputeAmplitudeAndQuality()
        return true
    }

    // ── Internals ──────────────────────────────────────────────────

    private func trimWindow() {
        guard let last = samples.last?.t else { return }
        while let first = samples.first {
            let age = last - first.t
            if age > windowSeconds || age < 0 { samples.removeFirst() } else { break }
        }
    }

    private func updateSampleRate() {
        guard samples.count >= 2, let f = samples.first?.t, let l = samples.last?.t, l > f else { return }
        sampleRate = Double(samples.count - 1) / (l - f)
    }

    /// Adaptive-threshold peak detector over the energy envelope.
    private func detectPeak() {
        guard envelope.count >= 3, envelope.count == samples.count else { return }
        let n = envelope.count
        let i = n - 2
        let prev = envelope[i - 1], curr = envelope[i], next = envelope[i + 1]
        guard curr > prev, curr >= next else { return }

        // Threshold: a fraction of the recent envelope peak. Robust to the
        // 100× amplitude span between a bony and a fleshy chest.
        let recentMax = envelope.suffix(min(envelope.count, Int(sampleRate * 2))).max() ?? 0
        let threshold = 0.30 * recentMax
        guard curr > threshold, recentMax > 1e-9 else { return }

        let t = samples[i].t
        if let last = lastPeakT, t - last < refractory { return }
        if let last = lastPeakT {
            ibis.append(t - last)
            if ibis.count > 20 { ibis.removeFirst(ibis.count - 20) }
        }
        lastPeakT = t
        beatCounter += 1
        let amp = curr.squareRoot()
        peakAmps.append(amp)
        if peakAmps.count > 20 { peakAmps.removeFirst(peakAmps.count - 20) }
        peaks.append((t: t, amp: amp))
        if peaks.count > 40 { peaks.removeFirst(peaks.count - 40) }
    }

    private func recomputeAmplitudeAndQuality() {
        // AO amplitude: median-ish mean of recent peak amplitudes (g).
        if !peakAmps.isEmpty {
            aoAmplitude = peakAmps.suffix(10).reduce(0, +) / Double(min(10, peakAmps.count))
        }
        // Quality from beat-interval stability (low CV = clean) + having a
        // strong, consistent AO amplitude vs the noise floor.
        let stab: Double
        if ibis.count >= 3 {
            let mean = ibis.reduce(0, +) / Double(ibis.count)
            let cv = ibiStdMs / max(1, mean * 1000)
            stab = max(0, 1 - cv / 0.30)
        } else {
            stab = 0
        }
        // Envelope SNR: peak amplitude over background.
        let bg = envelope.isEmpty ? 0 : envelope.reduce(0, +) / Double(envelope.count)
        let snr = bg > 1e-12 ? min(1.0, (aoAmplitude * aoAmplitude) / (bg * 6)) : 0
        quality = 0.6 * stab + 0.4 * snr
    }

    /// Snapshot of derived features for the result builder. Runs an O(N)
    /// diastolic search per detected beat to localise the AC peak and average
    /// the LVET (AO→AC) across beats.
    func features() -> SCGFeatures {
        SCGFeatures(
            sampleRate: sampleRate,
            heartRateBpm: heartRateBpm,
            ibiCount: ibis.count,
            ibiStdMs: ibiStdMs,
            aoAmplitude: aoAmplitude,
            lvetMs: estimateLVET(),
            quality: quality
        )
    }

    /// LVET = mean AO→AC interval. For each AO peak we look inside the systolic
    /// window (40–60% of the beat) for the next prominent envelope lobe — the
    /// aortic-valve-closing complex. Returns nil when fewer than 3 beats yield
    /// a plausible (180–420 ms) interval.
    private func estimateLVET() -> Double? {
        guard peaks.count >= 4, !envelope.isEmpty, let t0 = samples.first?.t else { return nil }
        let dt = 1.0 / sampleRate
        func idx(forTime t: Double) -> Int { Int(((t - t0) / dt).rounded()) }

        var lvets: [Double] = []
        for k in 0..<(peaks.count - 1) {
            let ao = peaks[k]
            let beat = peaks[k + 1].t - ao.t
            guard beat > 0.3, beat < 1.7 else { continue }
            // Search 180 ms…(55% of the beat) after AO for the AC lobe.
            let lo = ao.t + 0.18
            let hi = ao.t + min(0.55 * beat, 0.42)
            let iLo = max(0, idx(forTime: lo))
            let iHi = min(envelope.count - 1, idx(forTime: hi))
            guard iHi > iLo + 1 else { continue }
            var bestI = iLo, bestV = -Double.infinity
            for i in iLo...iHi where envelope[i] > bestV { bestV = envelope[i]; bestI = i }
            // Require the AC lobe to be a real local maximum, not the window edge.
            guard bestI > iLo, bestI < iHi else { continue }
            let acT = t0 + Double(bestI) * dt
            let lvet = (acT - ao.t) * 1000
            if lvet > 180, lvet < 420 { lvets.append(lvet) }
        }
        guard lvets.count >= 3 else { return nil }
        return lvets.reduce(0, +) / Double(lvets.count)
    }
}

/// Derived SCG features handed to the measurement builder + BP model.
struct SCGFeatures: Equatable {
    let sampleRate: Double
    let heartRateBpm: Int?
    let ibiCount: Int
    let ibiStdMs: Double
    let aoAmplitude: Double
    let lvetMs: Double?
    let quality: Double
}
