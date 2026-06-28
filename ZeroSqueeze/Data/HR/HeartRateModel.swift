import Foundation

/// A windowed heart-rate estimate from one model backend.
struct HeartRateEstimate: Equatable {
    /// Beats per minute.
    let bpm: Double
    /// Model confidence in [0, 1]. Readings below the router's gate are
    /// discarded rather than shown — PHRM-style confidence gating.
    let confidence: Double
    /// Which backend produced this ("classic-ppg", "coreml-tsm", …).
    let source: String
}

/// Pluggable HR estimator over a window of PPG samples.
///
/// Two backends ship today:
///   - `ClassicHeartRateModel` — the adaptive-threshold peak detector
///     (`PPGProcessor`). Always available.
///   - `CoreMLHeartRateModel` — a learned trace model (temporal-shift CNN
///     family, see `training/`). Available only when a compiled
///     `ZSHR.mlmodelc` is bundled.
///
/// `HeartRateModelRouter` prefers the learned model and falls back to the
/// classic one when the model is absent or unconfident.
protocol HeartRateModel: Sendable {
    var name: String { get }
    var isAvailable: Bool { get }
    /// `window` is chronological. Returns nil when no HR can be derived.
    func estimate(window: [PPGSample]) -> HeartRateEstimate?
}

// ── Classic backend ─────────────────────────────────────────────────

/// Wraps `PPGProcessor` (adaptive-threshold peak detection) behind the
/// model interface. Confidence is the processor's signal-quality score.
struct ClassicHeartRateModel: HeartRateModel {
    let name = "classic-ppg"
    let isAvailable = true

    /// Low-amplitude PPG needs lower thresholds than contact PPG; callers pick.
    var noiseFloor: Double = 0.3
    var minPeakThreshold: Double = 0.15
    /// AC amplitude that maps to full quality credit. Must match the live
    /// processor's scale (low-amplitude PPG green AC ≈ 0.3–2) — otherwise the stored
    /// `signalQuality` is computed at the fingertip scale (40) and clean scg
    /// scans land near 0.37, failing the RHR `>= 0.4` inclusion gate.
    var acQualityScale: Double = 2.5

    func estimate(window: [PPGSample]) -> HeartRateEstimate? {
        guard !window.isEmpty else { return nil }
        let processor = PPGProcessor(
            noiseFloor: noiseFloor,
            minPeakThreshold: minPeakThreshold,
            acQualityScale: acQualityScale
        )
        for sample in window {
            processor.ingest(sample)
        }
        let features = processor.features()
        guard let bpm = features.heartRateBpm else { return nil }
        return HeartRateEstimate(
            bpm: Double(bpm),
            confidence: features.quality,
            source: name
        )
    }
}

// ── Router ──────────────────────────────────────────────────────────

/// Prefers the learned model; falls back to the classic peak detector
/// when the model is missing, fails, or is unconfident.
struct HeartRateModelRouter {
    var primary: HeartRateModel?
    var fallback: HeartRateModel
    /// Primary results below this confidence are discarded in favour of
    /// the fallback.
    var minPrimaryConfidence: Double = 0.5

    /// Loaded once — Core ML model compilation is not free, and every
    /// capture view model builds a router.
    @MainActor private static let bundledModel: HeartRateModel? = CoreMLHeartRateModel()

    /// Default app router: Core ML model if bundled, classic otherwise.
    @MainActor static func standard() -> HeartRateModelRouter {
        HeartRateModelRouter(
            primary: bundledModel,
            fallback: ClassicHeartRateModel()
        )
    }

    func estimate(window: [PPGSample]) -> HeartRateEstimate? {
        if let primary, primary.isAvailable,
           let est = primary.estimate(window: window),
           est.confidence >= minPrimaryConfidence {
            return est
        }
        return fallback.estimate(window: window)
    }
}
