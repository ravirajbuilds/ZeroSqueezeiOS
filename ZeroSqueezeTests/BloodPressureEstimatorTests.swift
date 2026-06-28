import XCTest
@testable import ZeroSqueeze

final class BloodPressureEstimatorTests: XCTestCase {

    func testNilWhenLVETMissing() {
        XCTAssertNil(BloodPressureEstimator.estimate(lvetMs: nil, hrBpm: 70, signalQuality: 0.9, beatCount: 10))
    }

    func testNilWhenHeartRateImplausible() {
        XCTAssertNil(BloodPressureEstimator.estimate(lvetMs: 300, hrBpm: 12, signalQuality: 0.9, beatCount: 10))
    }

    /// LVET sitting exactly on the rate-corrected expectation should land on
    /// (or very near) the normotensive reference at the 60 bpm anchor.
    func testExpectedLVETLandsNearReference() {
        let hr = 60
        let lvet = BloodPressureEstimator.expectedLVET(hrBpm: Double(hr))
        let est = BloodPressureEstimator.estimate(lvetMs: lvet, hrBpm: hr, signalQuality: 1, beatCount: 10)
        let e = try! XCTUnwrap(est)
        XCTAssertEqual(e.systolicMmHg, 118, accuracy: 2)
        XCTAssertEqual(e.diastolicMmHg, 76, accuracy: 2)
    }

    /// A shorter-than-expected ejection (higher afterload) must push systolic up.
    func testShorterEjectionRaisesPressure() {
        let hr = 70
        let expected = BloodPressureEstimator.expectedLVET(hrBpm: Double(hr))
        let normal = BloodPressureEstimator.estimate(lvetMs: expected, hrBpm: hr, signalQuality: 1, beatCount: 10)!
        let short = BloodPressureEstimator.estimate(lvetMs: expected - 35, hrBpm: hr, signalQuality: 1, beatCount: 10)!
        XCTAssertGreaterThan(short.systolicMmHg, normal.systolicMmHg)
    }

    /// Output is always clamped to a sane physiological display range with a
    /// plausible pulse pressure.
    func testClampsToPhysiologicalRange() {
        let est = BloodPressureEstimator.estimate(lvetMs: 180, hrBpm: 200, signalQuality: 1, beatCount: 10)!
        XCTAssertLessThanOrEqual(est.systolicMmHg, 185)
        XCTAssertGreaterThanOrEqual(est.diastolicMmHg, 50)
        XCTAssertGreaterThanOrEqual(est.systolicMmHg - est.diastolicMmHg, 25)
    }

    func testCategoryBuckets() {
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 115, diastolic: 75), "Normal range")
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 125, diastolic: 78), "Elevated")
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 135, diastolic: 85), "Stage 1 range")
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 150, diastolic: 95), "Stage 2 range")
    }
}
