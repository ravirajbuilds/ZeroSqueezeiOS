import XCTest
@testable import ZeroSqueeze

final class ReadinessTests: XCTestCase {

    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func scg(daysAgo: Int, bpm: Int, hrv: Double = 50, quality: Float = 0.8) -> SCGMeasurement {
        SCGMeasurement(
            id: UUID(),
            timestamp: cal.date(byAdding: .day, value: -daysAgo, to: now)!,
            heartRateBpm: bpm,
            hrvSdnnMs: hrv,
            signalQuality: quality
        )
    }

    func testNoDataReturnsEmpty() {
        let score = Readiness.compute(scg: [], now: now)
        XCTAssertFalse(score.hasData)
        XCTAssertEqual(score, .empty)
    }

    func testStaleDataReturnsEmpty() {
        // Only an old reading (10 days ago) — nothing fresh to anchor today.
        let score = Readiness.compute(scg: [scg(daysAgo: 10, bpm: 60)], now: now)
        XCTAssertFalse(score.hasData)
    }

    func testElevatedRestingHeartRateLowersScore() {
        // 12 days of baseline at 60 bpm, plus a fresh reading today.
        var baseline: [SCGMeasurement] = []
        for d in 3...14 { baseline.append(scg(daysAgo: d, bpm: 60)) }

        let calm = Readiness.compute(scg: [scg(daysAgo: 0, bpm: 60)] + baseline, now: now)
        let strained = Readiness.compute(scg: [scg(daysAgo: 0, bpm: 78)] + baseline, now: now)

        XCTAssertTrue(calm.hasData)
        XCTAssertTrue(strained.hasData)
        XCTAssertLessThan(strained.value, calm.value)
    }

    func testScoreStaysInRange() {
        var readings: [SCGMeasurement] = [scg(daysAgo: 0, bpm: 120, hrv: 8)]
        for d in 3...14 { readings.append(scg(daysAgo: d, bpm: 55, hrv: 70)) }
        let score = Readiness.compute(scg: readings, now: now)
        XCTAssertGreaterThanOrEqual(score.value, 0)
        XCTAssertLessThanOrEqual(score.value, 100)
    }

    func testBandThresholds() {
        XCTAssertEqual(Readiness.band(for: 30), .rest)
        XCTAssertEqual(Readiness.band(for: 50), .low)
        XCTAssertEqual(Readiness.band(for: 60), .fair)
        XCTAssertEqual(Readiness.band(for: 80), .good)
        XCTAssertEqual(Readiness.band(for: 95), .peak)
    }
}
