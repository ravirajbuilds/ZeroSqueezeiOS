import Foundation
import CoreML

/// Learned HR backend. Runs a bundled Core ML trace model (temporal-shift
/// CNN family — see `training/README.md` for the training and conversion
/// pipeline) over an 8-second, 3-channel mean-RGB trace.
///
/// Model contract (enforced by `training/convert_to_coreml.py`):
///   - file:    `ZSHR.mlpackage`, compiled into the bundle as
///              `ZSHR.mlmodelc`
///   - input:   `trace`      Float32 [1, 3, 240]  — r/g/b mean traces,
///              uniformly resampled to 30 Hz over the trailing 8 s and
///              per-channel standardized (zero mean, unit variance)
///   - output:  `bpm`        Float32 [1]
///   - output:  `confidence` Float32 [1] in [0, 1]
///
/// `init` returns nil when no model is bundled — the router then runs
/// the classic peak detector alone. The app never requires the model.
/// `@unchecked Sendable`: wraps an `MLModel` (not `Sendable`-marked) but
/// `MLModel.prediction` is thread-safe and the model is never mutated after
/// init, so it's safe to hand to a background task.
struct CoreMLHeartRateModel: HeartRateModel, @unchecked Sendable {
    static let windowSeconds: Double = 8
    static let sampleRate: Double = 30
    static var sampleCount: Int { Int(windowSeconds * sampleRate) }

    let name = "coreml-tsm"
    var isAvailable: Bool { true }

    private let model: MLModel

    init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "ZSHR", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url) else {
            return nil
        }
        self.model = model
    }

    func estimate(window: [PPGSample]) -> HeartRateEstimate? {
        guard let input = Self.traceTensor(from: window) else { return nil }
        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: ["trace": input])
            let output = try model.prediction(from: provider)
            guard let bpm = output.featureValue(for: "bpm")?.multiArrayValue?[0].doubleValue,
                  let confidence = output.featureValue(for: "confidence")?.multiArrayValue?[0].doubleValue
            else { return nil }
            guard (25...220).contains(bpm) else { return nil }
            return HeartRateEstimate(
                bpm: bpm,
                confidence: min(max(confidence, 0), 1),
                source: name
            )
        } catch {
            ZSLogger.error(.ppg, "CoreML HR prediction failed", error: error)
            return nil
        }
    }

    // ── Preprocessing ───────────────────────────────────────────────

    /// Trailing 8 s of the window → uniformly resampled, per-channel
    /// standardized Float32 [1, 3, 240] tensor. Nil when the window spans
    /// less than half the model's receptive field.
    static func traceTensor(from window: [PPGSample]) -> MLMultiArray? {
        guard let last = window.last else { return nil }
        let start = last.t - windowSeconds
        let trailing = window.filter { $0.t >= start }
        guard trailing.count >= sampleCount / 2,
              let first = trailing.first,
              last.t - first.t > windowSeconds / 2 else { return nil }

        let n = sampleCount
        var channels = [[Double]](repeating: [Double](repeating: 0, count: n), count: 3)

        // Linear interpolation onto a uniform 30 Hz grid.
        var j = 0
        for i in 0..<n {
            let t = first.t + (last.t - first.t) * Double(i) / Double(n - 1)
            while j < trailing.count - 2 && trailing[j + 1].t < t { j += 1 }
            let a = trailing[j]
            let b = trailing[min(j + 1, trailing.count - 1)]
            let span = b.t - a.t
            let frac = span > 0 ? (t - a.t) / span : 0
            channels[0][i] = a.r + (b.r - a.r) * frac
            channels[1][i] = a.g + (b.g - a.g) * frac
            channels[2][i] = a.b + (b.b - a.b) * frac
        }

        guard let array = try? MLMultiArray(shape: [1, 3, NSNumber(value: n)], dataType: .float32)
        else { return nil }

        for c in 0..<3 {
            let mean = channels[c].reduce(0, +) / Double(n)
            let variance = channels[c].reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n)
            let std = max(sqrt(variance), 1e-6)
            for i in 0..<n {
                array[c * n + i] = NSNumber(value: Float((channels[c][i] - mean) / std))
            }
        }
        return array
    }
}
