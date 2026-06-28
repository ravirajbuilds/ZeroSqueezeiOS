import XCTest
@testable import ZeroSqueeze

final class TimeRangeTests: XCTestCase {

    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func dated(_ daysAgo: Int) -> Date {
        cal.date(byAdding: .day, value: -daysAgo, to: now)!
    }

    func testAllHasNoCutoff() {
        XCTAssertNil(TimeRange.all.cutoff(now: now))
        XCTAssertNil(TimeRange.all.days)
    }

    func testWeekCutoffSevenDays() {
        let cutoff = TimeRange.week.cutoff(now: now)
        XCTAssertEqual(cutoff, dated(7))
    }

    func testFilterWeekKeepsRecentOnly() {
        let items = [dated(0), dated(3), dated(6), dated(8), dated(20)]
        let kept = TimeRange.week.filter(items, now: now, timestamp: { $0 })
        XCTAssertEqual(kept.count, 3)   // 0, 3, 6 days ago
        XCTAssertFalse(kept.contains(dated(8)))
    }

    func testFilterMonthBoundaryInclusive() {
        // Exactly 30 days ago must be kept (>= cutoff).
        let items = [dated(30), dated(31)]
        let kept = TimeRange.month.filter(items, now: now, timestamp: { $0 })
        XCTAssertEqual(kept, [dated(30)])
    }

    func testFilterAllKeepsEverything() {
        let items = [dated(0), dated(100), dated(1000)]
        XCTAssertEqual(TimeRange.all.filter(items, now: now, timestamp: { $0 }).count, 3)
    }

    func testAllCasesPresent() {
        XCTAssertEqual(TimeRange.allCases.map(\.rawValue), ["7D", "30D", "All"])
    }
}
