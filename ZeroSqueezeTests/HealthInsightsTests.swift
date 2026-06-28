import XCTest
@testable import ZeroSqueeze

final class HealthInsightsTests: XCTestCase {

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

    private func scg(daysAgo: Int, hour: Int, bpm: Int, hrv: Double?) -> SCGMeasurement {
        let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysAgo, to: now)!)
        return SCGMeasurement(
            id: UUID(),
            timestamp: cal.date(byAdding: .hour, value: hour, to: day)!,
            heartRateBpm: bpm,
            hrvSdnnMs: hrv,
            signalQuality: 0.8
        )
    }

    func testEmptyShowsGetStarted() {
        let out = HealthInsights.build(hb: [], scg: [], now: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.id, "get-started")
    }

    func testNormalAnemiaIsPositive() {
        let out = HealthInsights.build(hb: [hb(daysAgo: 0, value: 14)], scg: [], now: now)
        let anemia = out.first { $0.id == "anemia-normal" }
        XCTAssertNotNil(anemia)
        XCTAssertEqual(anemia?.severity, .positive)
    }

    func testLowAnemiaIsCaution() {
        let out = HealthInsights.build(
            hb: [hb(daysAgo: 0, value: 9, anemia: .moderate)], scg: [], now: now
        )
        let anemia = out.first { $0.id == "anemia-low" }
        XCTAssertEqual(anemia?.severity, .caution)
    }

    func testHbDowntrendSurfacesAsCaution() {
        // This week ~12.5, last week ~14.5 → ~-2 g/dL.
        let data =
            [hb(daysAgo: 1, value: 12.4), hb(daysAgo: 3, value: 12.6)] +
            [hb(daysAgo: 8, value: 14.4), hb(daysAgo: 10, value: 14.6)]
        let out = HealthInsights.build(hb: data, scg: [], now: now)
        let trend = out.first { $0.id == "hb-trend" }
        XCTAssertEqual(trend?.severity, .caution)
        XCTAssertTrue(trend?.title.contains("down") ?? false)
    }

    func testHbStableProducesNoTrend() {
        // Within the noise floor (<0.4 g/dL change).
        let data =
            [hb(daysAgo: 1, value: 14.0), hb(daysAgo: 3, value: 14.1)] +
            [hb(daysAgo: 8, value: 14.0), hb(daysAgo: 10, value: 14.05)]
        let out = HealthInsights.build(hb: data, scg: [], now: now)
        XCTAssertNil(out.first { $0.id == "hb-trend" })
    }

    func testInsufficientDataNoTrend() {
        // Only one reading in each window — below minPerWindow.
        let data = [hb(daysAgo: 1, value: 12.0), hb(daysAgo: 8, value: 15.0)]
        let out = HealthInsights.build(hb: data, scg: [], now: now)
        XCTAssertNil(out.first { $0.id == "hb-trend" })
    }

    func testRhrDowntrendIsPositive() {
        // This week ~58, last week ~70.
        let data = [
            scg(daysAgo: 1, hour: 8, bpm: 58, hrv: 40),
            scg(daysAgo: 2, hour: 8, bpm: 60, hrv: 40),
            scg(daysAgo: 8, hour: 8, bpm: 70, hrv: 40),
            scg(daysAgo: 9, hour: 8, bpm: 72, hrv: 40),
        ]
        let out = HealthInsights.build(hb: [], scg: data, now: now)
        let rhr = out.first { $0.id == "rhr-trend" }
        XCTAssertEqual(rhr?.severity, .positive)
        XCTAssertTrue(rhr?.title.contains("down") ?? false)
    }

    func testLowHrvIsNeutralWarning() {
        let data = (0..<3).map { scg(daysAgo: $0, hour: 9, bpm: 70, hrv: 12) }
        let out = HealthInsights.build(hb: [], scg: data, now: now)
        let hrv = out.first { $0.id == "hrv-low" }
        XCTAssertNotNil(hrv)
        XCTAssertEqual(hrv?.severity, .neutral)
    }

    func testHealthyHrvIsPositive() {
        let data = (0..<3).map { scg(daysAgo: $0, hour: 9, bpm: 70, hrv: 55) }
        let out = HealthInsights.build(hb: [], scg: data, now: now)
        XCTAssertNotNil(out.first { $0.id == "hrv-ok" })
    }

    /// Anemia insight (latest reading) must rank above the weekly trend.
    func testOrderingAnemiaBeforeTrend() {
        let data =
            [hb(daysAgo: 1, value: 12.4), hb(daysAgo: 3, value: 12.6)] +
            [hb(daysAgo: 8, value: 14.4), hb(daysAgo: 10, value: 14.6)]
        let out = HealthInsights.build(hb: data, scg: [], now: now)
        let anemiaIdx = out.firstIndex { $0.id.hasPrefix("anemia") }
        let trendIdx = out.firstIndex { $0.id == "hb-trend" }
        XCTAssertNotNil(anemiaIdx)
        XCTAssertNotNil(trendIdx)
        XCTAssertLessThan(anemiaIdx!, trendIdx!)
    }
}
