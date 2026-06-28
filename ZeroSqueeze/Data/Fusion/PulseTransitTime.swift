import Foundation

/// Pulse transit time (PTT) from *simultaneous* chest SCG + finger PPG.
///
/// The heartbeat's mechanical event at the chest (the SCG AO complex, aortic-
/// valve opening) starts the pressure pulse; the PPG records when that pulse
/// reaches the fingertip. The delay between them is the pulse transit time, and
/// PTT is inversely related to blood pressure and arterial stiffness — the
/// foundation of cuffless BP estimation.
///
/// This is the fusion the app is built around: neither sensor alone gives PTT;
/// together they do. Both sample streams must share a clock (the fused capture
/// service re-stamps them on a single monotonic timeline).
enum PulseTransitTime {

    struct Estimate: Equatable {
        /// Median PTT in milliseconds.
        let pttMs: Double
        /// Beats that contributed a valid AO→finger pairing.
        let beatCount: Int
        /// Confidence in [0, 1] from pairing yield + PTT stability.
        let confidence: Double
    }

    /// Physiological PTT window at the fingertip (ms). Outside this a pairing
    /// is rejected as a mismatch.
    static let minPTTMs = 80.0
    static let maxPTTMs = 400.0

    /// Pair each SCG AO peak with the *next* PPG systolic peak and take the
    /// robust (median) transit time. `scg` and `ppg` must be on the same clock.
    static func estimate(scg: [SCGSample], ppg: [PPGSample]) -> Estimate? {
        let aoTimes = scgAOPeakTimes(scg)
        let ppgTimes = ppgPeakTimes(ppg)
        guard aoTimes.count >= 3, ppgTimes.count >= 3 else { return nil }

        var ptts: [Double] = []
        var pj = 0
        for ao in aoTimes {
            // Advance to the first PPG peak after this AO.
            while pj < ppgTimes.count && ppgTimes[pj] <= ao { pj += 1 }
            guard pj < ppgTimes.count else { break }
            let dt = (ppgTimes[pj] - ao) * 1000
            if dt >= minPTTMs && dt <= maxPTTMs { ptts.append(dt) }
        }
        guard ptts.count >= 3 else { return nil }

        let sorted = ptts.sorted()
        let median = sorted[sorted.count / 2]
        // Stability: coefficient of variation → confidence.
        let mean = ptts.reduce(0, +) / Double(ptts.count)
        let sd = (ptts.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(ptts.count)).squareRoot()
        let cv = mean > 0 ? sd / mean : 1
        let stability = max(0, 1 - cv / 0.4)
        let yield = min(1.0, Double(ptts.count) / 8.0)
        return Estimate(pttMs: median, beatCount: ptts.count, confidence: 0.5 * stability + 0.5 * yield)
    }

    // ── Event detection ────────────────────────────────────────────

    /// AO peak times from the SCG magnitude trace: detrend → squared-energy
    /// envelope → adaptive-threshold peaks with a 300 ms refractory. Mirrors
    /// `SCGProcessor` but returns absolute peak times.
    static func scgAOPeakTimes(_ samples: [SCGSample]) -> [Double] {
        guard samples.count > 10 else { return [] }
        let mag = samples.map(\.magnitude)
        let dc = mag.reduce(0, +) / Double(mag.count)
        let ac = mag.map { $0 - dc }
        // 50 ms energy envelope.
        let fs = estimateFs(samples.map(\.t))
        let env = movingEnergy(ac, window: max(1, Int(fs * 0.05)))
        return peaks(env, times: samples.map(\.t), refractory: 0.30, fraction: 0.30)
    }

    /// PPG systolic peak times from the red-channel AC trace.
    static func ppgPeakTimes(_ samples: [PPGSample]) -> [Double] {
        guard samples.count > 6 else { return [] }
        let red = samples.map(\.r)
        let dc = red.reduce(0, +) / Double(red.count)
        let ac = red.map { $0 - dc }
        return peaks(ac, times: samples.map(\.t), refractory: 0.30, fraction: 0.35)
    }

    // ── Shared helpers ─────────────────────────────────────────────

    private static func estimateFs(_ t: [Double]) -> Double {
        guard let f = t.first, let l = t.last, l > f, t.count > 1 else { return 100 }
        return Double(t.count - 1) / (l - f)
    }

    private static func movingEnergy(_ x: [Double], window: Int) -> [Double] {
        guard window > 1 else { return x.map { $0 * $0 } }
        var out = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lo = max(0, i - window + 1)
            var s = 0.0
            for j in lo...i { s += x[j] * x[j] }
            out[i] = s / Double(i - lo + 1)
        }
        return out
    }

    /// Local-maximum peak times above `fraction` of the rolling max, honouring
    /// a refractory period.
    private static func peaks(_ x: [Double], times: [Double], refractory: Double, fraction: Double) -> [Double] {
        guard x.count >= 3 else { return [] }
        let globalMax = x.max() ?? 0
        guard globalMax > 1e-12 else { return [] }
        let threshold = fraction * globalMax
        var out: [Double] = []
        var lastT: Double?
        for i in 1..<(x.count - 1) {
            guard x[i] > x[i - 1], x[i] >= x[i + 1], x[i] > threshold else { continue }
            let t = times[i]
            if let last = lastT, t - last < refractory { continue }
            out.append(t)
            lastT = t
        }
        return out
    }
}
