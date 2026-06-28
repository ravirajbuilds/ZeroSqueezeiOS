import XCTest
@testable import ZeroSqueeze

final class HemoglobinEstimatorTests: XCTestCase {

    private func features(pi: Double = 2.0, rRatio: Double = 1.0, quality: Double = 0.8) -> PPGFeatures {
        // Set acRed / dcRed so PI matches, and acGreen / dcGreen so rRatio matches.
        let dcRed = 200.0
        let acRed = pi / 100.0 * dcRed
        let dcGreen = 100.0
        // rRatio = (acRed/dcRed) / (acGreen/dcGreen) → solve for acGreen.
        let acGreen = (acRed / dcRed) / rRatio * dcGreen
        return PPGFeatures(
            sampleRate: 30,
            dcRed: dcRed,
            dcGreen: dcGreen,
            dcBlue: 50,
            acRed: acRed,
            acGreen: acGreen,
            perfusionIndex: pi,
            heartRateBpm: 70,
            ibiCount: 8,
            ibiStdMs: 25,
            quality: quality
        )
    }

    /// Features with the green AC channel zeroed out — `rRatio` collapses to 0
    /// (its "unmeasurable" sentinel). The estimator must treat this as
    /// missing-data, not as a literal ratio-of-zero, otherwise it would
    /// silently bias Hb down by ~0.4 g/dL for anyone whose green PPG is too
    /// weak to resolve.
    private func featuresWithNoGreenAC() -> PPGFeatures {
        PPGFeatures(
            sampleRate: 30,
            dcRed: 200, dcGreen: 100, dcBlue: 50,
            acRed: 4, acGreen: 0,
            perfusionIndex: 2.0,
            heartRateBpm: 70,
            ibiCount: 8,
            ibiStdMs: 25,
            quality: 0.8
        )
    }

    func testMaleAdultBaseline() {
        let profile = UserProfile(age: 30, gender: .male, skinTone: 3)
        let est = HemoglobinEstimator.estimate(features: features(), profile: profile)
        XCTAssertGreaterThan(est.hemoglobinGPerDl, 13)
        XCTAssertLessThan(est.hemoglobinGPerDl, 17)
    }

    func testFemaleAdultBaselineLowerThanMale() {
        let male = HemoglobinEstimator.estimate(
            features: features(),
            profile: UserProfile(age: 30, gender: .male, skinTone: 3)
        )
        let female = HemoglobinEstimator.estimate(
            features: features(),
            profile: UserProfile(age: 30, gender: .female, skinTone: 3)
        )
        XCTAssertGreaterThan(male.hemoglobinGPerDl, female.hemoglobinGPerDl)
    }

    func testLowQualityWidensBand() {
        let high = HemoglobinEstimator.estimate(
            features: features(quality: 0.9),
            profile: UserProfile(age: 30, gender: .male, skinTone: 3)
        )
        let low = HemoglobinEstimator.estimate(
            features: features(quality: 0.2),
            profile: UserProfile(age: 30, gender: .male, skinTone: 3)
        )
        XCTAssertGreaterThan(low.band, high.band)
    }

    func testDeepSkinToneAdjustsDownAndWidensBand() {
        let light = HemoglobinEstimator.estimate(
            features: features(),
            profile: UserProfile(age: 30, gender: .male, skinTone: 1)
        )
        let dark = HemoglobinEstimator.estimate(
            features: features(),
            profile: UserProfile(age: 30, gender: .male, skinTone: 9)
        )
        XCTAssertLessThan(dark.hemoglobinGPerDl, light.hemoglobinGPerDl)
        XCTAssertGreaterThanOrEqual(dark.band, light.band)
    }

    func testUnmeasurableRRatioDoesNotBiasDown() {
        let profile = UserProfile(age: 30, gender: .male, skinTone: 3)
        let withRatio = HemoglobinEstimator.estimate(
            features: features(rRatio: 1.0),
            profile: profile
        )
        let unmeasurable = HemoglobinEstimator.estimate(
            features: featuresWithNoGreenAC(),
            profile: profile
        )
        // rRatio=1.0 → rAdj=0. Unmeasurable also → rAdj=0. Both should land
        // on the same point estimate (or within float-rounding distance).
        XCTAssertEqual(
            withRatio.hemoglobinGPerDl,
            unmeasurable.hemoglobinGPerDl,
            accuracy: 0.01,
            "Missing green AC must not bias Hb downward"
        )
    }

    func testClampedToPlausibleRange() {
        let est = HemoglobinEstimator.estimate(
            features: features(pi: 0.05, rRatio: 0.1, quality: 0.0),
            profile: UserProfile(age: 30, gender: .female, skinTone: 10)
        )
        XCTAssertGreaterThanOrEqual(est.hemoglobinGPerDl, 4)
        XCTAssertLessThanOrEqual(est.hemoglobinGPerDl, 20)
    }

    /// Point estimate must hard-clamp to [4.0, 20.0] even when the inputs are
    /// engineered to drive it outside. Guards the bottom of the range — a sub-4
    /// Hb result on the UI would be nonsensical / alarming.
    func testPointEstimateClampsAtLowerBound() {
        // Maximally-negative adjustments: low PI (negative piAdj), low rRatio
        // (negative rAdj), MST 10 (toneAdj = -0.603), female baseline (13.5).
        // Even summed, this won't drop below 4 — but we lock in the floor.
        let est = HemoglobinEstimator.estimate(
            features: features(pi: 0.0, rRatio: 0.0001, quality: 0.0),
            profile: UserProfile(age: 30, gender: .female, skinTone: 10)
        )
        XCTAssertGreaterThanOrEqual(est.hemoglobinGPerDl, 4.0,
            "Hb point estimate must never sit below 4.0 g/dL")
    }

    /// Band hard-clamp upper bound: even with worst-case signal + skin tone,
    /// the displayed range can't sprawl beyond ±4 g/dL.
    func testBandClampsAtUpperBound() {
        let est = HemoglobinEstimator.estimate(
            features: features(pi: 0.5, rRatio: 1.0, quality: 0.0),
            profile: UserProfile(age: 30, gender: .female, skinTone: 10)
        )
        XCTAssertLessThanOrEqual(est.band, 4.0)
        XCTAssertGreaterThanOrEqual(est.band, 0.8)
    }

    /// Band hard-clamp lower bound: with a great signal + light skin, band
    /// still can't shrink below 0.8 — we always want a visible uncertainty.
    func testBandClampsAtLowerBound() {
        let est = HemoglobinEstimator.estimate(
            features: features(pi: 3.0, rRatio: 1.0, quality: 1.0),
            profile: UserProfile(age: 30, gender: .male, skinTone: 1)
        )
        XCTAssertGreaterThanOrEqual(est.band, 0.8,
            "Confidence band must never collapse below 0.8 g/dL")
    }

    /// Personal calibration shifts the point estimate by exactly the fitted
    /// intercept (away from the clamp bounds) and narrows the band floor.
    func testCalibrationCorrectionShiftsEstimate() {
        let profile = UserProfile(age: 30, gender: .male, skinTone: 3)
        let correction = HbCorrection(slope: 1, intercept: -1.0)

        let uncal = HemoglobinEstimator.estimate(features: features(), profile: profile)
        let cal = HemoglobinEstimator.estimate(
            features: features(), profile: profile, correction: correction
        )

        XCTAssertEqual(cal.hemoglobinGPerDl, uncal.hemoglobinGPerDl - 1.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(cal.band, uncal.band)
        // Raw must stay pre-correction so refits don't compound.
        XCTAssertEqual(cal.rawHemoglobinGPerDl, uncal.hemoglobinGPerDl, accuracy: 0.01)
    }

    /// Calibrated estimates still respect the [4, 20] clamp.
    func testCalibrationCorrectionStillClamped() {
        let profile = UserProfile(age: 30, gender: .female, skinTone: 10)
        let est = HemoglobinEstimator.estimate(
            features: features(pi: 0.05, rRatio: 0.1, quality: 0.0),
            profile: profile,
            correction: HbCorrection(slope: 0.5, intercept: -5.0)
        )
        XCTAssertGreaterThanOrEqual(est.hemoglobinGPerDl, 4.0)
    }
}
