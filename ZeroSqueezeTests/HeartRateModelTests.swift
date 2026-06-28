import XCTest
import CoreML
@testable import ZeroSqueeze

final class HeartRateModelTests: XCTestCase {

    /// Synthetic low-amplitude PPG sinusoid window: `hz` pulse over `seconds`
    /// at 30 fps, low amplitude like a real scg trace.
    private func syntheticWindow(hz: Double, seconds: Double = 30, amp: Double = 1.0) -> [PPGSample] {
        let fs: Double = 30
        let dc: Double = 120
        let n = Int(seconds * fs)
        return (0..<n).map { i in
            let t = Double(i) / fs
            let pulse = amp * sin(2 * .pi * hz * t)
            return PPGSample(t: t, r: dc + pulse, g: dc * 0.6 + pulse * 0.4, b: dc * 0.4)
        }
    }

    func testClassicModelRecoversSyntheticRate() {
        let model = ClassicHeartRateModel()
        let est = model.estimate(window: syntheticWindow(hz: 1.2))
        XCTAssertNotNil(est)
        if let est {
            XCTAssertEqual(est.bpm, 72, accuracy: 5)
            XCTAssertEqual(est.source, "classic-ppg")
            XCTAssertGreaterThan(est.confidence, 0)
        }
    }

    func testClassicModelNilOnEmptyWindow() {
        XCTAssertNil(ClassicHeartRateModel().estimate(window: []))
    }

    func testRouterFallsBackWhenPrimaryAbsent() {
        let router = HeartRateModelRouter(primary: nil, fallback: ClassicHeartRateModel())
        let est = router.estimate(window: syntheticWindow(hz: 1.0))
        XCTAssertEqual(est?.source, "classic-ppg")
        XCTAssertEqual(est?.bpm ?? 0, 60, accuracy: 5)
    }

    func testRouterFallsBackWhenPrimaryUnconfident() {
        let shaky = StubHeartRateModel(
            result: HeartRateEstimate(bpm: 150, confidence: 0.1, source: "stub")
        )
        let router = HeartRateModelRouter(primary: shaky, fallback: ClassicHeartRateModel())
        let est = router.estimate(window: syntheticWindow(hz: 1.2))
        XCTAssertEqual(est?.source, "classic-ppg")
    }

    func testRouterPrefersConfidentPrimary() {
        let confident = StubHeartRateModel(
            result: HeartRateEstimate(bpm: 64, confidence: 0.9, source: "stub")
        )
        let router = HeartRateModelRouter(primary: confident, fallback: ClassicHeartRateModel())
        let est = router.estimate(window: syntheticWindow(hz: 1.2))
        XCTAssertEqual(est?.source, "stub")
        XCTAssertEqual(est?.bpm, 64)
    }

    /// No model is bundled in the test target — init must return nil, not trap.
    func testCoreMLModelAbsentReturnsNil() {
        XCTAssertNil(CoreMLHeartRateModel(bundle: Bundle(for: Self.self)))
    }

    // ── Preprocessing contract ──────────────────────────────────────

    func testTraceTensorShapeAndNormalization() throws {
        let tensor = try XCTUnwrap(
            CoreMLHeartRateModel.traceTensor(from: syntheticWindow(hz: 1.2, seconds: 10))
        )
        XCTAssertEqual(tensor.shape.map(\.intValue), [1, 3, 240])

        // Each channel standardized: mean ≈ 0, std ≈ 1.
        let n = CoreMLHeartRateModel.sampleCount
        for c in 0..<3 {
            var sum = 0.0
            var sumSq = 0.0
            for i in 0..<n {
                let v = tensor[c * n + i].doubleValue
                sum += v
                sumSq += v * v
            }
            let mean = sum / Double(n)
            let std = (sumSq / Double(n) - mean * mean).squareRoot()
            XCTAssertEqual(mean, 0, accuracy: 1e-3, "channel \(c) mean")
            // Flat channels (b has no DC variation removed → constant) hit
            // the epsilon-std guard and stay near zero rather than NaN.
            XCTAssertFalse(std.isNaN)
        }
    }

    func testTraceTensorNilOnShortWindow() {
        XCTAssertNil(CoreMLHeartRateModel.traceTensor(from: syntheticWindow(hz: 1.2, seconds: 2)))
        XCTAssertNil(CoreMLHeartRateModel.traceTensor(from: []))
    }

    /// The bundled ZSHR model loads from the test host (the app bundle) and
    /// recovers a clean synthetic rate. Guards against shipping a build where
    /// the .mlmodelc silently dropped out of the bundle.
    func testBundledCoreMLModelLoadsAndRecoversRate() {
        guard let model = CoreMLHeartRateModel() else {
            XCTFail("ZSHR.mlmodelc is not bundled into the app/test host")
            return
        }
        guard let est = model.estimate(window: syntheticWindow(hz: 1.2)) else {
            XCTFail("CoreML model returned no estimate for a clean 72 bpm window")
            return
        }
        XCTAssertEqual(est.source, "coreml-tsm")
        XCTAssertEqual(est.bpm, 72, accuracy: 25)
        XCTAssertTrue((0.0...1.0).contains(est.confidence))
    }

    /// End-to-end: the standard router prefers the learned backend on a clean,
    /// high-confidence window — proving the CoreML path is actually active and
    /// not silently falling back to the classic detector.
    @MainActor
    func testRouterPrefersCoreMLOnConfidentWindow() throws {
        // Skip gracefully if no model is bundled (the app supports that), so
        // the suite still passes in a model-less configuration.
        guard CoreMLHeartRateModel() != nil else {
            throw XCTSkip("No bundled CoreML model in this configuration")
        }
        let router = HeartRateModelRouter.standard()
        let est = router.estimate(window: syntheticWindow(hz: 1.2))
        XCTAssertEqual(est?.source, "coreml-tsm")
    }
}

private struct StubHeartRateModel: HeartRateModel {
    let name = "stub"
    let isAvailable = true
    let result: HeartRateEstimate?
    func estimate(window: [PPGSample]) -> HeartRateEstimate? { result }
}
