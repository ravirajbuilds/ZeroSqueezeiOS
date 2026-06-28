import XCTest
@testable import ZeroSqueeze

final class RestingHeartRateTests: XCTestCase {

    private let calendar = Calendar.current

    private func measurement(daysAgo: Int, hour: Int, bpm: Int?, quality: Float) -> SCGMeasurement {
        let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysAgo, to: Date())!)
        let ts = calendar.date(byAdding: .hour, value: hour, to: day)!
        return SCGMeasurement(
            id: UUID(), timestamp: ts, heartRateBpm: bpm, hrvSdnnMs: nil, signalQuality: quality
        )
    }

    func testLowQualityReadingsGatedOut() {
        let daily = RestingHeartRate.daily(from: [
            measurement(daysAgo: 0, hour: 9, bpm: 60, quality: 0.8),
            measurement(daysAgo: 0, hour: 10, bpm: 180, quality: 0.1)  // junk spike
        ])
        XCTAssertEqual(daily.count, 1)
        XCTAssertEqual(daily[0].rhr, 60, accuracy: 0.01)
        XCTAssertEqual(daily[0].readingCount, 1)
    }

    func testNilBpmExcluded() {
        let daily = RestingHeartRate.daily(from: [
            measurement(daysAgo: 0, hour: 9, bpm: nil, quality: 0.9)
        ])
        XCTAssertTrue(daily.isEmpty)
    }

    /// 8 readings → lowest quartile = 2 lowest values averaged. Exercise
    /// spikes in the upper range must not move RHR.
    func testLowestQuartileAggregation() {
        let bpms = [58, 60, 65, 70, 75, 90, 110, 130]
        let daily = RestingHeartRate.daily(from: bpms.enumerated().map {
            measurement(daysAgo: 0, hour: 8 + $0.offset, bpm: $0.element, quality: 0.8)
        })
        XCTAssertEqual(daily.count, 1)
        XCTAssertEqual(daily[0].rhr, 59, accuracy: 0.01)  // mean(58, 60)
        XCTAssertEqual(daily[0].readingCount, 8)
    }

    func testGroupsByDaySortedAscending() {
        let daily = RestingHeartRate.daily(from: [
            measurement(daysAgo: 0, hour: 9, bpm: 62, quality: 0.8),
            measurement(daysAgo: 2, hour: 9, bpm: 70, quality: 0.8),
            measurement(daysAgo: 1, hour: 9, bpm: 66, quality: 0.8)
        ])
        XCTAssertEqual(daily.count, 3)
        XCTAssertEqual(daily.map(\.rhr), [70, 66, 62])
        XCTAssertTrue(daily[0].day < daily[1].day && daily[1].day < daily[2].day)
    }

    func testLatestReturnsMostRecentDay() {
        let latest = RestingHeartRate.latest(from: [
            measurement(daysAgo: 3, hour: 9, bpm: 70, quality: 0.8),
            measurement(daysAgo: 0, hour: 9, bpm: 61, quality: 0.8)
        ])
        XCTAssertEqual(latest?.rhr ?? 0, 61, accuracy: 0.01)
    }
}
