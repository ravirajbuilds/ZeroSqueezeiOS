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

    /// Like `synthSCG` but adds an AC (aortic-valve closing) lobe `lvet`
    /// seconds after each AO complex, so the processor can recover LVET.
    private func synthSCGWithAC(bpm: Double, lvet: Double, seconds: Double, fs: Double = 100) -> [SCGSample] {
        let beatPeriod = 60.0 / bpm
        let n = Int(seconds * fs)
        var out: [SCGSample] = []
        for i in 0..<n {
            let t = Double(i) / fs
            let phase = t.truncatingRemainder(dividingBy: beatPeriod)
            var a = 0.0
            if phase < 0.05 { a += 0.03 * exp(-phase / 0.015) * sin(2 * .pi * 30 * phase) }
            let ac = phase - lvet
            if ac >= 0, ac < 0.05 { a += 0.013 * exp(-ac / 0.012) * sin(2 * .pi * 26 * ac) }
            out.append(SCGSample(t: t, ax: 0, ay: 0, az: a + 1e-4))
        }
        return out
    }

    /// Full chain: AO+AC synthetic beats → SCGProcessor.features() → a complete
    /// SCGMeasurement-style set with a plausible LVET and a BP index.
    func testFullChainRecoversLVETAndBloodPressure() {
        let p = SCGProcessor()
        for s in synthSCGWithAC(bpm: 66, lvet: 0.30, seconds: 10) { p.ingest(s) }
        let f = p.features()
        XCTAssertNotNil(f.heartRateBpm)
        let lvet = try! XCTUnwrap(f.lvetMs, "LVET should be recovered from AO→AC")
        XCTAssertEqual(lvet, 300, accuracy: 60)
        let bp = try! XCTUnwrap(
            BloodPressureEstimator.estimate(lvetMs: f.lvetMs, hrBpm: f.heartRateBpm,
                                            signalQuality: f.quality, beatCount: f.ibiCount)
        )
        XCTAssertGreaterThanOrEqual(bp.systolicMmHg, 85)
        XCTAssertLessThanOrEqual(bp.systolicMmHg, 185)
        XCTAssertGreaterThanOrEqual(bp.systolicMmHg - bp.diastolicMmHg, 25)
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
