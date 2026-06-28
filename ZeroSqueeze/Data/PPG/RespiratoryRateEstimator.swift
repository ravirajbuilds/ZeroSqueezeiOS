import Foundation

/// Estimates respiratory rate (breaths per minute) from a PPG trace.
///
/// Breathing modulates the PPG baseline and pulse amplitude (respiratory
/// sinus arrhythmia + intrathoracic pressure). That modulation lives in
/// the 0.1–0.5 Hz band (6–30 breaths/min) — far slower than the pulse, so
/// it needs a long window (PPGProcessor's 4 s rolling window is far too
/// short). Callers feed the whole capture buffer.
///
/// Method (pure Swift, no FFT dependency):
///   1. Take the dominant channel, uniformly resample to a fixed grid.
///   2. Bandpass to the respiratory band: a moving-average high-pass kills
///      DC drift slower than breathing, then a moving-average low-pass
///      kills the pulse (≈1 Hz) and its harmonics — without it the pulse
///      autocorrelates inside the resp band and fakes a breathing rate.
///   3. Normalized autocorrelation; the lag with the highest peak inside
///      the respiratory band is the breathing period.
///   4. Confidence = that peak's normalized height.
enum RespiratoryRateEstimator {

    /// Resampling grid. Respiration is slow, so 10 Hz is ample and keeps
    /// the autocorrelation cheap over a 30 s window (300 samples).
    static let gridRate: Double = 10
    static let minBreathsPerMin: Double = 6    // 0.1 Hz
    static let maxBreathsPerMin: Double = 30   // 0.5 Hz
    /// Need at least this much signal to even attempt a fit — one full
    /// slow breath plus margin.
    static let minSeconds: Double = 15

    struct Estimate: Equatable {
        let breathsPerMin: Double
        /// Normalized autocorrelation peak height in [0, 1].
        let confidence: Double
    }

    /// `channel` picks which trace carries the modulation. Chest captures
    /// remap green into the `.r` slot, so `.r` is the right default for
    /// both fingertip and scg buffers.
    enum Channel { case r, g, b }

    static func estimate(window: [PPGSample], channel: Channel = .r) -> Estimate? {
        guard let first = window.first?.t, let last = window.last?.t,
              last - first >= minSeconds else { return nil }

        let series = resample(window, channel: channel)
        guard series.count >= Int(minSeconds * gridRate) else { return nil }

        let banded = bandpass(series)
        guard let rate = dominantRate(banded) else { return nil }

        // Band-power gate. Autocorrelation is energy-normalized, so even a
        // tiny pure-pulse residual autocorrelates to ~1 when no real
        // breathing competes. Require the respiratory band to hold a
        // meaningful share of the signal's AC power before trusting the
        // peak; scale confidence by that share so weak modulation reads as
        // low-confidence rather than a confident fabrication.
        let acPower = variancePower(series)
        let bandPower = banded.reduce(0) { $0 + $1 * $1 } / Double(banded.count)
        guard acPower > 0 else { return nil }
        let bandShare = bandPower / acPower
        let gated = rate.confidence * min(1, bandShare / 0.15)
        guard gated > 0.3 else { return nil }
        return Estimate(breathsPerMin: rate.breathsPerMin, confidence: gated)
    }

    /// Variance (AC power) of a series.
    private static func variancePower(_ x: [Double]) -> Double {
        guard !x.isEmpty else { return 0 }
        let mean = x.reduce(0, +) / Double(x.count)
        return x.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(x.count)
    }

    // ── Steps ───────────────────────────────────────────────────────

    /// Linear-interpolate the chosen channel onto a uniform `gridRate` grid.
    static func resample(_ window: [PPGSample], channel: Channel) -> [Double] {
        guard let first = window.first?.t, let last = window.last?.t, last > first
        else { return [] }
        func value(_ s: PPGSample) -> Double {
            switch channel { case .r: return s.r; case .g: return s.g; case .b: return s.b }
        }
        let n = Int((last - first) * gridRate)
        guard n >= 2 else { return [] }
        var out = [Double](repeating: 0, count: n)
        var j = 0
        for i in 0..<n {
            let t = first + Double(i) / gridRate
            while j < window.count - 2 && window[j + 1].t < t { j += 1 }
            let a = window[j]
            let b = window[min(j + 1, window.count - 1)]
            let span = b.t - a.t
            let frac = span > 0 ? (t - a.t) / span : 0
            out[i] = value(a) + (value(b) - value(a)) * frac
        }
        return out
    }

    /// Bandpass to the respiratory band via two cascaded moving averages.
    ///
    /// High-pass: subtract a centred 3.3 s mean (kills drift slower than
    /// the slowest breath, 6/min). Low-pass: smooth with a centred 1 s
    /// mean (attenuates the ≈1 Hz pulse and faster harmonics so they can't
    /// autocorrelate in-band). Centred windows avoid the phase lag a
    /// trailing window would inject. Finally mean-subtract for a
    /// zero-centred autocorrelation.
    static func bandpass(_ x: [Double]) -> [Double] {
        let highW = max(1, Int(60.0 / minBreathsPerMin * gridRate))  // slowest breath period
        let lowW = max(1, Int(gridRate))                              // ≈1 s — below pulse period
        let hp = (0..<x.count).map { x[$0] - centredMean(x, at: $0, half: highW / 2) }
        var out = (0..<hp.count).map { centredMean(hp, at: $0, half: lowW / 2) }
        let m = out.reduce(0, +) / Double(out.count)
        for i in 0..<out.count { out[i] -= m }
        return out
    }

    /// Mean of `x` over `[i-half, i+half]`, clamped to bounds.
    private static func centredMean(_ x: [Double], at i: Int, half: Int) -> Double {
        let lo = max(0, i - half)
        let hi = min(x.count - 1, i + half)
        var sum = 0.0
        for k in lo...hi { sum += x[k] }
        return sum / Double(hi - lo + 1)
    }

    /// Normalized autocorrelation; pick the highest peak whose lag lands in
    /// the respiratory band. Returns nil when no clear periodicity exists.
    static func dominantRate(_ x: [Double]) -> Estimate? {
        let energy = x.reduce(0) { $0 + $1 * $1 }
        guard energy > 0 else { return nil }

        let minLag = Int((60.0 / maxBreathsPerMin) * gridRate)  // fastest breath
        let maxLag = Int((60.0 / minBreathsPerMin) * gridRate)  // slowest breath
        guard maxLag < x.count else { return nil }

        var bestLag = -1
        var bestCorr = 0.0
        // Only accept a true local maximum so we don't latch onto the
        // monotonic shoulder near minLag.
        for lag in (minLag + 1)..<min(maxLag, x.count - 1) {
            let c = autocorr(x, lag: lag, energy: energy)
            let cPrev = autocorr(x, lag: lag - 1, energy: energy)
            let cNext = autocorr(x, lag: lag + 1, energy: energy)
            if c > cPrev, c >= cNext, c > bestCorr {
                bestCorr = c
                bestLag = lag
            }
        }
        guard bestLag > 0, bestCorr > 0.3 else { return nil }

        let periodSeconds = Double(bestLag) / gridRate
        let bpm = 60.0 / periodSeconds
        return Estimate(breathsPerMin: bpm, confidence: min(1, bestCorr))
    }

    private static func autocorr(_ x: [Double], lag: Int, energy: Double) -> Double {
        var sum = 0.0
        for i in lag..<x.count { sum += x[i] * x[i - lag] }
        return sum / energy
    }
}
