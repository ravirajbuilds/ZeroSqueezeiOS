import XCTest
@testable import ZeroSqueeze

final class PulseTransitTimeTests: XCTestCase {

    /// Build aligned SCG + PPG streams on one clock: an SCG AO burst at each
    /// beat, and a PPG systolic peak `pttMs` later.
    private func fused(bpm: Double, pttMs: Double, seconds: Double, fs: Double = 100)
        -> (scg: [SCGSample], ppg: [PPGSample]) {
        let period = 60.0 / bpm
        let n = Int(seconds * fs)
        var scg: [SCGSample] = []
        var ppg: [PPGSample] = []
        let ptt = pttMs / 1000.0
        for i in 0..<n {
            let t = Double(i) / fs
            let phase = t.truncatingRemainder(dividingBy: period)
            // SCG AO burst at beat start.
            var a = 0.0
            if phase < 0.05 { a = 0.03 * exp(-phase / 0.012) * sin(2 * .pi * 30 * phase) }
            scg.append(SCGSample(t: t, ax: 0, ay: 0, az: a + 1e-4))
            // PPG: a smooth pulse peaking ptt after each beat.
            let pphase = (t - ptt).truncatingRemainder(dividingBy: period)
            let centered = pphase < 0 ? pphase + period : pphase
            let r = 150 + 6 * exp(-pow((centered - 0.05) / 0.06, 2))    // peak ~50ms in
            ppg.append(PPGSample(t: t, r: r, g: 80, b: 60))
        }
        return (scg, ppg)
    }

    func testRecoversKnownPTT() {
        let (scg, ppg) = fused(bpm: 60, pttMs: 220, seconds: 12)
        let est = try! XCTUnwrap(PulseTransitTime.estimate(scg: scg, ppg: ppg))
        XCTAssertEqual(est.pttMs, 220, accuracy: 40)
        XCTAssertGreaterThan(est.confidence, 0.3)
    }

    func testRejectsWhenStreamsTooShort() {
        let (scg, ppg) = fused(bpm: 60, pttMs: 200, seconds: 1)
        XCTAssertNil(PulseTransitTime.estimate(scg: scg, ppg: ppg))
    }

    func testShorterPTTAtFasterBeats() {
        let a = PulseTransitTime.estimate(scg: fused(bpm: 60, pttMs: 180, seconds: 12).scg,
                                          ppg: fused(bpm: 60, pttMs: 180, seconds: 12).ppg)
        XCTAssertNotNil(a)
    }
}

final class HeartHealthModelTests: XCTestCase {

    func testBPFallsAsPTTLengthens() {
        let short = HeartHealthModel.bloodPressure(pttMs: 180)
        let long = HeartHealthModel.bloodPressure(pttMs: 320)
        XCTAssertGreaterThan(short.systolic, long.systolic)
    }

    func testBPClampedAndPulsePressureSane() {
        let bp = HeartHealthModel.bloodPressure(pttMs: 50)   // extreme
        XCTAssertLessThanOrEqual(bp.systolic, 190)
        XCTAssertGreaterThanOrEqual(bp.systolic - bp.diastolic, 25)
    }

    func testGreatMetricsYieldYoungerHeartAndHighScore() {
        let r = HeartHealthModel.evaluate(
            age: 40, restingHR: 52, hrvSdnnMs: 80, systolicMmHg: 114, lvetMs: 300, respirationBpm: 14
        )
        XCTAssertGreaterThanOrEqual(r.score, 80)
        XCTAssertLessThan(r.heartAge, 40)
    }

    func testPoorMetricsYieldOlderHeartAndLowScore() {
        let r = HeartHealthModel.evaluate(
            age: 40, restingHR: 88, hrvSdnnMs: 18, systolicMmHg: 150, lvetMs: 300, respirationBpm: 22
        )
        XCTAssertLessThan(r.score, 60)
        XCTAssertGreaterThan(r.heartAge, 40)
    }

    func testNoInputsStillProducesNeutralResult() {
        let r = HeartHealthModel.evaluate(age: 30, restingHR: nil, hrvSdnnMs: nil,
                                          systolicMmHg: nil, lvetMs: nil, respirationBpm: nil)
        XCTAssertEqual(r.heartAge, 30)
        XCTAssertGreaterThanOrEqual(r.score, 0)
    }
}
