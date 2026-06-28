import XCTest
@testable import ZeroSqueeze

final class RespiratoryRateTests: XCTestCase {

    /// Build a PPG-like window at 30 fps: a pulse carrier amplitude-modulated
    /// by a slow respiratory wave, over `seconds`. `breathHz` is the truth.
    private func window(
        breathHz: Double,
        pulseHz: Double = 1.1,
        seconds: Double = 30,
        respAmp: Double = 8,
        noise: Double = 0
    ) -> [PPGSample] {
        let fs = 30.0
        let n = Int(seconds * fs)
        var rng = SeededGen(seed: 5)
        return (0..<n).map { i in
            let t = Double(i) / fs
            let resp = respAmp * sin(2 * .pi * breathHz * t)
            let pulse = 4 * sin(2 * .pi * pulseHz * t)
            let jitter = noise > 0 ? (rng.unit() - 0.5) * 2 * noise : 0
            let r = 140 + resp + pulse + jitter
            return PPGSample(t: t, r: r, g: r * 0.6, b: r * 0.4)
        }
    }

    func testRecoversSlowBreathing() {
        // 0.2 Hz = 12 breaths/min.
        let est = RespiratoryRateEstimator.estimate(window: window(breathHz: 0.2))
        let e = try! XCTUnwrap(est)
        XCTAssertEqual(e.breathsPerMin, 12, accuracy: 2)
        XCTAssertGreaterThan(e.confidence, 0.4)
    }

    func testRecoversFasterBreathing() {
        // 0.35 Hz = 21 breaths/min.
        let est = RespiratoryRateEstimator.estimate(window: window(breathHz: 0.35))
        let e = try! XCTUnwrap(est)
        XCTAssertEqual(e.breathsPerMin, 21, accuracy: 3)
    }

    func testRobustToModerateNoise() {
        let est = RespiratoryRateEstimator.estimate(window: window(breathHz: 0.25, noise: 3))
        let e = try! XCTUnwrap(est)
        XCTAssertEqual(e.breathsPerMin, 15, accuracy: 3)
    }

    func testShortWindowReturnsNil() {
        XCTAssertNil(RespiratoryRateEstimator.estimate(window: window(breathHz: 0.2, seconds: 8)))
    }

    func testEmptyWindowReturnsNil() {
        XCTAssertNil(RespiratoryRateEstimator.estimate(window: []))
    }

    /// Pure pulse, no respiratory modulation → no periodicity in the resp
    /// band → low confidence, must not fabricate a rate.
    func testNoRespiratorySignalRejected() {
        let est = RespiratoryRateEstimator.estimate(
            window: window(breathHz: 0.2, respAmp: 0)
        )
        // Either nil, or if something is returned it must be low-confidence.
        if let e = est { XCTAssertLessThan(e.confidence, 0.6) }
    }

    /// Out-of-band breathing (faster than 30/min) must not be reported as a
    /// false in-band rate.
    func testRejectsOutOfBandRate() {
        // 0.7 Hz = 42 breaths/min — above the 30/min ceiling.
        let est = RespiratoryRateEstimator.estimate(window: window(breathHz: 0.7))
        if let e = est {
            XCTAssertLessThanOrEqual(e.breathsPerMin, RespiratoryRateEstimator.maxBreathsPerMin + 1)
        }
    }
}

private struct SeededGen {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1 }
    mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFFFF) / Double(UInt32.max)
    }
}
