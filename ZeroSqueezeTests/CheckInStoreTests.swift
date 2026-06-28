import XCTest
@testable import ZeroSqueeze

@MainActor
final class CheckInStoreTests: XCTestCase {

    private let cal = Calendar.current

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("checkin-\(UUID().uuidString).json")
    }

    private func entry(daysAgo: Int, mood: Int, energy: Int = 3) -> CheckIn {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
        return CheckIn(day: cal.startOfDay(for: day), timestamp: Date(), mood: mood, energy: energy)
    }

    func testUpsertReplacesSameDayEntry() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CheckInStore(fileURL: url)

        store.upsert(entry(daysAgo: 0, mood: 2))
        store.upsert(entry(daysAgo: 0, mood: 5))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.mood, 5)
    }

    func testEntriesSortedNewestFirst() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CheckInStore(fileURL: url)

        store.upsert(entry(daysAgo: 2, mood: 3))
        store.upsert(entry(daysAgo: 0, mood: 4))
        store.upsert(entry(daysAgo: 1, mood: 5))

        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries.map(\.mood), [4, 5, 3])
    }

    func testEntryOnDate() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CheckInStore(fileURL: url)
        store.upsert(entry(daysAgo: 0, mood: 4))

        XCTAssertEqual(store.entry(on: Date())?.mood, 4)
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertNil(store.entry(on: yesterday))
    }

    func testPersistenceRoundTrips() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CheckInStore(fileURL: url)
        store.upsert(entry(daysAgo: 0, mood: 4, energy: 2))

        // A persist is async; wait for the file to materialise.
        let exp = expectation(description: "file written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        let reloaded = CheckInStore(fileURL: url)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.energy, 2)
    }
}
