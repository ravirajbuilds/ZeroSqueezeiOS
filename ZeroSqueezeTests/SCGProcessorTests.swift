import XCTest
@testable import ZeroSqueeze

final class SCGProcessorTests: XCTestCase {

    /// Build a synthetic SCG magnitude trace: a periodic AO complex (a short
    /// damped burst once per beat) on top of a small baseline, sampled at
    /// `fs` Hz for `seconds`. Returns samples on the z-axis so magnitude
    /// reflects the burst.
    private func synthSCG(bpm: Double, seconds: Double, fs: Double = 100) -> [SCGSample] {
        let beatPeriod = 60.0 / bpm
        let n = Int(seconds * fs)
        var out: [SCGSample] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / fs
            let phase = t.truncatingRemainder(dividingBy: beatPeriod)
            // 40 ms damped 30 Hz burst at the start of each beat = AO complex.
            var a = 0.0
            if phase < 0.05 {
                a = 0.03 * exp(-phase / 0.015) * sin(2 * .pi * 30 * phase)
            }
            out.append(SCGSample(t: t, ax: 0, ay: 0, az: a + 1e-4))
        }
        return out
    }

    func testDetectsHeartRateFromSyntheticBeats() {
        let p = SCGProcessor()
        for s in synthSCG(bpm: 72, seconds: 8) { p.ingest(s) }
        let hr = try! XCTUnwrap(p.heartRateBpm)
        XCTAssertEqual(Double(hr), 72, accuracy: 6)
    }

    func testClassicModelMatchesProcessor() {
        let window = synthSCG(bpm: 60, seconds: 8)
        let est = try! XCTUnwrap(ClassicSCGHeartRateModel().estimate(window: window))
        XCTAssertEqual(est.source, "classic-scg")
        XCTAssertEqual(est.bpm, 60, accuracy: 6)
    }

    func testRouterFallsBackToClassicWhenNoModel() {
        // No bundled Core ML model in tests → router must use the classic AO
        // detector and still return a result.
        let router = SCGHeartRateModelRouter(primary: nil, fallback: ClassicSCGHeartRateModel())
        let est = router.estimate(window: synthSCG(bpm: 90, seconds: 8))
        XCTAssertEqual(est?.bpm ?? 0, 90, accuracy: 8)
    }

    func testQualityRisesWithCleanSignal() {
        let p = SCGProcessor()
        for s in synthSCG(bpm: 66, seconds: 8) { p.ingest(s) }
        XCTAssertGreaterThan(p.quality, 0.3)
    }
}
