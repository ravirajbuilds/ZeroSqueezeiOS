import XCTest
@testable import ZeroSqueeze

/// Edge-case + stress tests that probe for latent bugs not exercised by the
/// happy-path suites. Each failure here should map to a concrete bug to fix.
@MainActor
final class BugHuntTests: XCTestCase {

    // ── AnemiaStatus threshold boundaries ──────────────────────────

    /// WHO thresholds use inclusive ranges (moderate = 8.0–10.9 g/dL).
    /// Off-by-one at boundary would silently misclassify millions of users.
    func testAnemiaThresholdsAtExactBoundaries() {
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(7.99, gender: .male), .severe)
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(8.0, gender: .male), .moderate)
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(10.9, gender: .male), .moderate)
        // 10.91 — just above moderate ceiling — should bump to mild.
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(10.91, gender: .male), .mild)
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(11.0, gender: .male), .mild)
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(12.99, gender: .male), .mild)
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(13.0, gender: .male), .normal)

        XCTAssertEqual(AnemiaStatus.fromHemoglobin(11.99, gender: .female), .mild)
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(12.0, gender: .female), .normal)

        XCTAssertEqual(AnemiaStatus.fromHemoglobin(12.49, gender: .other), .mild)
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(12.5, gender: .other), .normal)
    }

    // ── UserProfile / HbMeasurement Codable round-trip ─────────────

    func testUserProfileCodableRoundTrip() throws {
        let original = UserProfile(age: 42, gender: .female, skinTone: 7)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testUserProfileCodableWithNilSkinTone() throws {
        let original = UserProfile(age: 30, gender: .other, skinTone: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.skinTone)
        XCTAssertNil(decoded.monkSkinTone)
    }

    func testHbMeasurementCodableRoundTrip() throws {
        let original = HbMeasurement(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            heartRateBpm: 72,
            hemoglobinGPerDl: 13.4,
            hemoglobinBand: 1.2,
            perfusionIndex: 2.1,
            signalQuality: 0.82,
            anemia: .normal
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HbMeasurement.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testHbMeasurementCodableWithNilHeartRate() throws {
        let original = HbMeasurement(
            id: UUID(), timestamp: Date(), heartRateBpm: nil,
            hemoglobinGPerDl: 14, hemoglobinBand: 1.5,
            perfusionIndex: 1.0, signalQuality: 0.3, anemia: .normal
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HbMeasurement.self, from: data)
        XCTAssertNil(decoded.heartRateBpm)
        XCTAssertEqual(decoded, original)
    }

    // ── UserProfile.ageType bucket boundaries ──────────────────────

    func testAgeTypeBoundaries() {
        XCTAssertEqual(UserProfile(age: 0, gender: .other, skinTone: nil).ageType, .child)
        XCTAssertEqual(UserProfile(age: 17, gender: .other, skinTone: nil).ageType, .child)
        XCTAssertEqual(UserProfile(age: 18, gender: .other, skinTone: nil).ageType, .adult)
        XCTAssertEqual(UserProfile(age: 64, gender: .other, skinTone: nil).ageType, .adult)
        XCTAssertEqual(UserProfile(age: 65, gender: .other, skinTone: nil).ageType, .senior)
    }

    // ── MeasurementStore persist round-trip ────────────────────────

    func testMeasurementStorePersistsAndLoads() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zerosqueeze-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store1 = MeasurementStore(fileURL: url)
        XCTAssertEqual(store1.measurements.count, 0)
        store1.append(HbMeasurement.placeholder)
        store1.append(HbMeasurement(
            id: UUID(), timestamp: Date(), heartRateBpm: 80,
            hemoglobinGPerDl: 11.5, hemoglobinBand: 1.0,
            perfusionIndex: 1.8, signalQuality: 0.7, anemia: .mild
        ))

        // Persist is async on a utility queue — wait for the write to settle.
        let exp = expectation(description: "persist")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let store2 = MeasurementStore(fileURL: url)
        XCTAssertEqual(store2.measurements.count, 2)
        XCTAssertEqual(store2.latest?.anemia, .mild)
    }

    func testMeasurementStoreSurvivesCorruptFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zerosqueeze-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        // Garbage that isn't a valid JSON array of HbMeasurement.
        try Data("not json".utf8).write(to: url)
        let store = MeasurementStore(fileURL: url)
        XCTAssertEqual(store.measurements.count, 0, "Corrupt file should load as empty, not crash")
    }

    // ── PPGProcessor non-monotonic timestamps ──────────────────────

    /// If the camera session restarts mid-app-session, PTS may reset to a
    /// smaller value. The trim window must not get stuck — otherwise samples
    /// grow without bound and quality stays high on stale data.
    func testProcessorRecoversFromBackwardTimestamps() {
        let processor = PPGProcessor()
        // Fill buffer with healthy 30 s @ 30 fps.
        for i in 0..<900 {
            let t = Double(i) / 30 + 1000  // start far from zero
            processor.ingest(PPGSample(t: t, r: 200 + 5 * sin(2 * .pi * 1.2 * t), g: 100, b: 50))
        }
        // PTS jumps backward (clock reset).
        for i in 0..<300 {
            let t = Double(i) / 30  // back near zero
            processor.ingest(PPGSample(t: t, r: 200 + 5 * sin(2 * .pi * 1.2 * t), g: 100, b: 50))
        }
        // Buffer must stay bounded by ~windowSeconds × sampleRate after the
        // jump, not balloon to the cumulative count (1200).
        XCTAssertLessThan(processor.bufferCount, 200,
            "Backward PTS must not defeat the trim window — buffer would leak")
        XCTAssertGreaterThan(processor.acRed, 1)
        XCTAssertGreaterThan(processor.perfusionIndex, 0)
    }

    // ── PPGProcessor at the upper HR end ───────────────────────────

    func testHighHeartRate170Bpm() {
        let processor = PPGProcessor()
        let fs: Double = 30
        let trueHz: Double = 170.0 / 60  // ~2.83 Hz
        let duration: Double = 20
        for i in 0..<Int(duration * fs) {
            let t = Double(i) / fs
            let r = 200 + 6 * sin(2 * .pi * trueHz * t)
            processor.ingest(PPGSample(t: t, r: r, g: 100, b: 50))
        }
        let bpm = processor.heartRateBpm
        XCTAssertNotNil(bpm)
        if let bpm {
            // ±8 bpm tolerance — high HR is harder; ensure we don't completely
            // miss the rate.
            XCTAssertEqual(Double(bpm), trueHz * 60, accuracy: 8)
        }
    }

    // ── PPGProcessor reset mid-stream ──────────────────────────────

    func testResetClearsIBIs() {
        let processor = PPGProcessor()
        for i in 0..<300 {
            let t = Double(i) / 30
            let r = 200 + 6 * sin(2 * .pi * 1.2 * t)
            processor.ingest(PPGSample(t: t, r: r, g: 100, b: 50))
        }
        XCTAssertFalse(processor.ibis.isEmpty)
        XCTAssertGreaterThan(processor.quality, 0)
        processor.reset()
        XCTAssertTrue(processor.ibis.isEmpty)
        XCTAssertNil(processor.heartRateBpm)
        XCTAssertEqual(processor.quality, 0)
        XCTAssertEqual(processor.acRed, 0)
        XCTAssertEqual(processor.perfusionIndex, 0)
    }

    // ── HemoglobinEstimator demographic coverage ───────────────────

    /// Every (ageType, gender) combo must produce a Hb in plausible
    /// adult-clinical range with a typical signal. Catches a baseline going
    /// out of bounds.
    func testEstimatorAcrossAllDemographics() {
        let goodFeatures = PPGFeatures(
            sampleRate: 30, dcRed: 200, dcGreen: 100, dcBlue: 50,
            acRed: 4, acGreen: 2, perfusionIndex: 2.0,
            heartRateBpm: 70, ibiCount: 8, ibiStdMs: 20, quality: 0.85
        )
        for age in [10, 30, 70] {
            for gender in Gender.allCases {
                for tone in [nil, 1, 5, 10] as [Int?] {
                    let profile = UserProfile(age: age, gender: gender, skinTone: tone)
                    let est = HemoglobinEstimator.estimate(features: goodFeatures, profile: profile)
                    XCTAssertGreaterThanOrEqual(est.hemoglobinGPerDl, 8,
                        "Hb suspiciously low for \(profile)")
                    XCTAssertLessThanOrEqual(est.hemoglobinGPerDl, 18,
                        "Hb suspiciously high for \(profile)")
                    XCTAssertGreaterThanOrEqual(est.band, 0.8)
                    XCTAssertLessThanOrEqual(est.band, 4.0)
                }
            }
        }
    }

    /// Confidence band's low end should never go below zero — a "negative Hb"
    /// would be nonsensical to display.
    func testEstimateBandLowDoesNotGoNegative() {
        let bad = PPGFeatures(
            sampleRate: 30, dcRed: 200, dcGreen: 100, dcBlue: 50,
            acRed: 1, acGreen: 0, perfusionIndex: 0.5,
            heartRateBpm: nil, ibiCount: 0, ibiStdMs: 0, quality: 0.0
        )
        let profile = UserProfile(age: 30, gender: .female, skinTone: 10)
        let est = HemoglobinEstimator.estimate(features: bad, profile: profile)
        XCTAssertGreaterThan(est.low, 0, "Lower bound of Hb range must remain positive")
    }
}
