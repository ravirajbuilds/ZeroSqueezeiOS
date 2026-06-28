import XCTest
@testable import ZeroSqueeze

final class HbCorrectionTests: XCTestCase {

    func testEmptyPointsIsIdentity() {
        XCTAssertEqual(HbCorrection.fit(points: []), .identity)
        XCTAssertFalse(HbCorrection.identity.isCalibrated)
    }

    func testSinglePointIsPureOffset() {
        let c = HbCorrection.fit(points: [
            point(raw: 14.0, lab: 12.5)
        ])
        XCTAssertEqual(c.slope, 1.0, accuracy: 1e-9)
        XCTAssertEqual(c.intercept, -1.5, accuracy: 1e-9)
        XCTAssertEqual(c.apply(14.0), 12.5, accuracy: 1e-9)
    }

    func testSinglePointOffsetClamped() {
        let c = HbCorrection.fit(points: [
            point(raw: 20.0, lab: 4.0)
        ])
        XCTAssertEqual(c.intercept, -5.0, accuracy: 1e-9)
    }

    /// Two consistent points pull the line toward them; the ridge prior
    /// keeps it between identity and the exact two-point fit.
    func testTwoPointsMoveTowardObservedLine() {
        // Exact line through these points: y = 0.5x + 6 (slope 0.5).
        let c = HbCorrection.fit(points: [
            point(raw: 12.0, lab: 12.0),
            point(raw: 16.0, lab: 14.0)
        ])
        XCTAssertLessThan(c.slope, 1.0)
        XCTAssertGreaterThanOrEqual(c.slope, 0.5)
        // Fit must improve on identity for the observed pairs.
        let identityErr = abs(12.0 - 12.0) + abs(16.0 - 14.0)
        let fitErr = abs(c.apply(12.0) - 12.0) + abs(c.apply(16.0) - 14.0)
        XCTAssertLessThan(fitErr, identityErr)
    }

    /// Identical raws (Sxx = 0) must not blow up — degrade to offset.
    func testDegenerateRawsFallBackToOffset() {
        let c = HbCorrection.fit(points: [
            point(raw: 14.0, lab: 13.0),
            point(raw: 14.0, lab: 12.0)
        ])
        XCTAssertEqual(c.slope, 1.0, accuracy: 1e-9)
        XCTAssertEqual(c.apply(14.0), 12.5, accuracy: 0.01)
    }

    func testSlopeClampAgainstOutliers() {
        // Wild pair implying slope 5 — must clamp to 1.5.
        let c = HbCorrection.fit(points: [
            point(raw: 13.0, lab: 8.0),
            point(raw: 15.0, lab: 18.0)
        ], lambda: 0.0)
        XCTAssertLessThanOrEqual(c.slope, 1.5)
        XCTAssertGreaterThanOrEqual(c.slope, 0.5)
    }

    private func point(raw: Float, lab: Float) -> HbCorrection.Point {
        HbCorrection.Point(id: UUID(), date: Date(), rawHb: raw, labHb: lab)
    }
}

@MainActor
final class CalibrationStoreTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("calibration-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testStartsIdentity() {
        let store = CalibrationStore(fileURL: tempURL)
        XCTAssertEqual(store.correction, .identity)
        XCTAssertTrue(store.points.isEmpty)
    }

    func testAddPointRefits() {
        let store = CalibrationStore(fileURL: tempURL)
        store.add(labHb: 12.5, rawHb: 14.0)
        XCTAssertEqual(store.correction.intercept, -1.5, accuracy: 1e-6)
        XCTAssertEqual(store.points.count, 1)
    }

    func testLegacyOffsetMigration() {
        let store = CalibrationStore(fileURL: tempURL)
        store.migrateLegacyOffset(-0.8)
        XCTAssertEqual(store.correction.intercept, -0.8, accuracy: 1e-6)
        // Second migration attempt is a no-op.
        store.migrateLegacyOffset(2.0)
        XCTAssertEqual(store.correction.intercept, -0.8, accuracy: 1e-6)
        // First real point supersedes the legacy offset.
        store.add(labHb: 13.0, rawHb: 14.0)
        XCTAssertEqual(store.correction.intercept, -1.0, accuracy: 1e-6)
    }

    func testPersistsAcrossInstances() {
        let store = CalibrationStore(fileURL: tempURL)
        store.add(labHb: 12.5, rawHb: 14.0)
        // Persistence is async on a utility queue; poll briefly.
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: tempURL.path), Date() < deadline {
            usleep(20_000)
        }
        let reloaded = CalibrationStore(fileURL: tempURL)
        XCTAssertEqual(reloaded.points.count, 1)
        XCTAssertEqual(reloaded.correction.intercept, -1.5, accuracy: 1e-6)
    }

    func testClearResetsToIdentity() {
        let store = CalibrationStore(fileURL: tempURL)
        store.add(labHb: 12.5, rawHb: 14.0)
        store.clear()
        XCTAssertEqual(store.correction, .identity)
        XCTAssertTrue(store.points.isEmpty)
    }
}
