import XCTest
@testable import ZeroSqueeze

final class ReportBuilderTests: XCTestCase {

    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func hb(daysAgo: Int, value: Float, anemia: AnemiaStatus = .normal) -> HbMeasurement {
        HbMeasurement(
            id: UUID(),
            timestamp: cal.date(byAdding: .day, value: -daysAgo, to: now)!,
            heartRateBpm: 70,
            hemoglobinGPerDl: value,
            hemoglobinBand: 1.0,
            perfusionIndex: 2.0,
            signalQuality: 0.8,
            anemia: anemia
        )
    }

    func testReportContainsHeaderAndDisclaimer() {
        let text = ReportBuilder.text(
            profile: .placeholder,
            hb: [],
            scg: [],
            checkIns: [],
            readiness: .empty,
            now: now
        )
        XCTAssertTrue(text.contains("ZeroSqueeze — Wellness Report"))
        XCTAssertTrue(text.contains("not a medical diagnosis"))
        XCTAssertTrue(text.contains("No readings yet."))
    }

    func testReportSummarisesVitalsAndCheckIns() {
        let scg = SCGMeasurement(
            id: UUID(), timestamp: now, heartRateBpm: 64,
            hrvSdnnMs: 48, signalQuality: 0.8
        )
        let checkIn = CheckIn(
            day: cal.startOfDay(for: now), timestamp: now,
            mood: 4, energy: 2, symptoms: ["Tired"], note: "Long day"
        )
        let text = ReportBuilder.text(
            profile: .placeholder,
            hb: [hb(daysAgo: 0, value: 13.4)],
            scg: [scg],
            checkIns: [checkIn],
            readiness: .empty,
            now: now
        )
        XCTAssertTrue(text.contains("13.4 g/dL"))
        XCTAssertTrue(text.contains("64 bpm"))
        XCTAssertTrue(text.contains("RECENT CHECK-INS"))
        XCTAssertTrue(text.contains("Long day"))
    }
}
