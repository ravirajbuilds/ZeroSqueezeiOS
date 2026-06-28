import Foundation
import CoreML

/// A windowed HR estimate from one SCG backend. Mirrors the PPG-side
/// `HeartRateEstimate` so the two modalities can share downstream code.
struct SCGHeartRateEstimate: Equatable {
    let bpm: Double
    let confidence: Double
    let source: String
}

/// Pluggable HR estimator over a window of SCG samples.
///
/// Two backends:
///   - `ClassicSCGHeartRateModel` — the adaptive-threshold AO-peak detector
///     (`SCGProcessor`). Always available.
///   - `CoreMLSCGHeartRateModel` — a learned 1-D CNN over the band-limited
///     acceleration envelope (see `training/`). Available only when a compiled
///     `ZSCardiacSCG.mlmodelc` is bundled; absent by default, so the app runs
///     on the classic detector alone.
protocol SCGHeartRateModel: Sendable {
    var name: String { get }
    var isAvailable: Bool { get }
    func estimate(window: [SCGSample]) -> SCGHeartRateEstimate?
}

// ── Classic backend ─────────────────────────────────────────────────

struct ClassicSCGHeartRateModel: SCGHeartRateModel {
    let name = "classic-scg"
    let isAvailable = true

    func estimate(window: [SCGSample]) -> SCGHeartRateEstimate? {
        guard !window.isEmpty else { return nil }
        let p = SCGProcessor()
        for s in window { p.ingest(s) }
        guard let bpm = p.heartRateBpm else { return nil }
        return SCGHeartRateEstimate(bpm: Double(bpm), confidence: p.quality, source: name)
    }
}

// ── Learned backend ─────────────────────────────────────────────────

/// Runs a bundled Core ML model over a 6-second, single-channel SCG envelope
/// resampled to 100 Hz and standardized. `init` returns nil when no model is
/// bundled, so the router falls back to the classic detector — the app never
/// requires the model.
///
/// `@unchecked Sendable`: wraps a non-`Sendable` `MLModel`, but
/// `MLModel.prediction` is thread-safe and the model is never mutated.
struct CoreMLSCGHeartRateModel: SCGHeartRateModel, @unchecked Sendable {
    static let windowSeconds: Double = 6
    static let sampleRate: Double = 100
    static var sampleCount: Int { Int(windowSeconds * sampleRate) }

    let name = "coreml-scg"
    var isAvailable: Bool { true }

    private let model: MLModel

    init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "ZSCardiacSCG", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url) else { return nil }
        self.model = model
    }

    func estimate(window: [SCGSample]) -> SCGHeartRateEstimate? {
        guard let input = Self.envelopeTensor(from: window) else { return nil }
        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: ["envelope": input])
            let output = try model.prediction(from: provider)
            guard let bpm = output.featureValue(for: "bpm")?.multiArrayValue?[0].doubleValue,
                  let confidence = output.featureValue(for: "confidence")?.multiArrayValue?[0].doubleValue,
                  (25...220).contains(bpm) else { return nil }
            return SCGHeartRateEstimate(bpm: bpm, confidence: min(max(confidence, 0), 1), source: name)
        } catch {
            ZSLogger.error(.ppg, "CoreML SCG prediction failed", error: error)
            return nil
        }
    }

    /// Trailing 6 s → magnitude trace, uniformly resampled to 100 Hz and
    /// standardized → Float32 [1, 1, 600]. Nil when the window is too short.
    static func envelopeTensor(from window: [SCGSample]) -> MLMultiArray? {
        guard let last = window.last else { return nil }
        let start = last.t - windowSeconds
        let trailing = window.filter { $0.t >= start }
        guard trailing.count >= sampleCount / 2, let first = trailing.first,
              last.t - first.t > windowSeconds / 2 else { return nil }

        let n = sampleCount
        var trace = [Double](repeating: 0, count: n)
        var j = 0
        for i in 0..<n {
            let t = first.t + (last.t - first.t) * Double(i) / Double(n - 1)
            while j < trailing.count - 2 && trailing[j + 1].t < t { j += 1 }
            let a = trailing[j], b = trailing[min(j + 1, trailing.count - 1)]
            let span = b.t - a.t
            let frac = span > 0 ? (t - a.t) / span : 0
            trace[i] = a.magnitude + (b.magnitude - a.magnitude) * frac
        }
        guard let array = try? MLMultiArray(shape: [1, 1, NSNumber(value: n)], dataType: .float32) else { return nil }
        let mean = trace.reduce(0, +) / Double(n)
        let variance = trace.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n)
        let std = max(variance.squareRoot(), 1e-6)
        for i in 0..<n { array[i] = NSNumber(value: Float((trace[i] - mean) / std)) }
        return array
    }
}

// ── Router ──────────────────────────────────────────────────────────

/// Prefers the learned model; falls back to the classic AO detector when the
/// model is missing, fails, or is unconfident.
struct SCGHeartRateModelRouter {
    var primary: SCGHeartRateModel?
    var fallback: SCGHeartRateModel
    var minPrimaryConfidence: Double = 0.5

    @MainActor private static let bundledModel: SCGHeartRateModel? = CoreMLSCGHeartRateModel()

    @MainActor static func standard() -> SCGHeartRateModelRouter {
        SCGHeartRateModelRouter(primary: bundledModel, fallback: ClassicSCGHeartRateModel())
    }

    func estimate(window: [SCGSample]) -> SCGHeartRateEstimate? {
        if let primary, primary.isAvailable,
           let est = primary.estimate(window: window),
           est.confidence >= minPrimaryConfidence {
            return est
        }
        return fallback.estimate(window: window)
    }
}
