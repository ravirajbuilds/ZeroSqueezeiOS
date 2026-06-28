import XCTest
@testable import ZeroSqueeze

final class DemoSeederTests: XCTestCase {

    private var defaults: UserDefaults!
    private var hbURL: URL!
    private var faceURL: URL!
    private var checkInURL: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "zerosqueeze.seeder.test.\(UUID().uuidString)")
        hbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hb-\(UUID().uuidString).json")
        faceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hb-scg-\(UUID().uuidString).json")
        checkInURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ci-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: hbURL)
        try? FileManager.default.removeItem(at: faceURL)
        try? FileManager.default.removeItem(at: checkInURL)
        super.tearDown()
    }

    /// Isolated check-in store so seeding never touches the shared on-disk one.
    @MainActor private func makeCheckInStore() -> CheckInStore {
        CheckInStore(fileURL: checkInURL)
    }

    @MainActor
    func test_seedsWhenStoresEmpty() {
        let hb = MeasurementStore(fileURL: hbURL)
        let scg = SCGMeasurementStore(fileURL: faceURL)
        DemoSeeder.seedIfEmpty(hbStore: hb, scgStore: scg, checkInStore: makeCheckInStore(), defaults: defaults)
        XCTAssertGreaterThan(hb.measurements.count, 0)
        XCTAssertGreaterThan(scg.measurements.count, 0)
    }

    @MainActor
    func test_seedsJournalCheckIns() {
        let hb = MeasurementStore(fileURL: hbURL)
        let scg = SCGMeasurementStore(fileURL: faceURL)
        let checkIns = makeCheckInStore()
        DemoSeeder.seedIfEmpty(hbStore: hb, scgStore: scg, checkInStore: checkIns, defaults: defaults)
        XCTAssertGreaterThan(checkIns.entries.count, 0)
        // Newest-first invariant holds for the seeded journal.
        if let first = checkIns.entries.first, let last = checkIns.entries.last {
            XCTAssertGreaterThanOrEqual(first.day, last.day)
        }
    }

    /// User explicitly clearing their captures must NOT cause demo data
    /// to zombie back on next launch.
    @MainActor
    func test_doesNotReseedAfterClear() {
        let hb = MeasurementStore(fileURL: hbURL)
        let scg = SCGMeasurementStore(fileURL: faceURL)
        DemoSeeder.seedIfEmpty(hbStore: hb, scgStore: scg, checkInStore: makeCheckInStore(), defaults: defaults)
        hb.clear()
        scg.clear()
        DemoSeeder.seedIfEmpty(hbStore: hb, scgStore: scg, checkInStore: makeCheckInStore(), defaults: defaults)
        XCTAssertEqual(hb.measurements.count, 0)
        XCTAssertEqual(scg.measurements.count, 0)
    }

    /// `store.latest` (Home, History) relies on index 0 = newest.
    @MainActor
    func test_orderingIsNewestFirst() {
        let hb = MeasurementStore(fileURL: hbURL)
        let scg = SCGMeasurementStore(fileURL: faceURL)
        DemoSeeder.seedIfEmpty(hbStore: hb, scgStore: scg, checkInStore: makeCheckInStore(), defaults: defaults)
        guard let first = hb.measurements.first, let last = hb.measurements.last else {
            XCTFail("Expected populated history"); return
        }
        XCTAssertGreaterThan(first.timestamp, last.timestamp)
    }

    @MainActor
    func test_resetFlagPermitsReseed() {
        let hb = MeasurementStore(fileURL: hbURL)
        let scg = SCGMeasurementStore(fileURL: faceURL)
        DemoSeeder.seedIfEmpty(hbStore: hb, scgStore: scg, checkInStore: makeCheckInStore(), defaults: defaults)
        hb.clear()
        scg.clear()
        DemoSeeder.resetSeededFlag(defaults: defaults)
        DemoSeeder.seedIfEmpty(hbStore: hb, scgStore: scg, checkInStore: makeCheckInStore(), defaults: defaults)
        XCTAssertGreaterThan(hb.measurements.count, 0)
    }

    /// Generated Hb stays within HemoglobinEstimator's clamp envelope
    /// [4, 20] g/dL, so the History Chart Y-domain (newly widened) covers
    /// every demo point without clipping.
    @MainActor
    func test_demoHbValues_stayWithinClampEnvelope() {
        let hb = MeasurementStore(fileURL: hbURL)
        let scg = SCGMeasurementStore(fileURL: faceURL)
        DemoSeeder.seedIfEmpty(hbStore: hb, scgStore: scg, checkInStore: makeCheckInStore(), defaults: defaults)
        for m in hb.measurements {
            XCTAssertGreaterThanOrEqual(m.hemoglobinGPerDl, 4.0)
            XCTAssertLessThanOrEqual(m.hemoglobinGPerDl, 20.0)
        }
    }
}
