import XCTest
@testable import ZeroSqueeze

/// Regression tests for the store decode-resilience fix: a corrupt or
/// future-versioned history file must never be silently overwritten (which
/// previously wiped all history), and partial corruption must recover the
/// good records.
@MainActor
final class StoreDecodingTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private func sample(anemia: AnemiaStatus = .normal) -> HbMeasurement {
        HbMeasurement(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            heartRateBpm: 72,
            hemoglobinGPerDl: 13.4,
            hemoglobinBand: 1.2,
            perfusionIndex: 2.1,
            signalQuality: 0.82,
            anemia: anemia
        )
    }

    /// Garbage file → empty load AND the original is quarantined, not
    /// overwritten. (The bug: next append() would erase recoverable history.)
    func testCorruptFileIsQuarantinedNotOverwritten() throws {
        let url = tempURL()
        try Data("this is not json".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
        }

        let store = MeasurementStore(fileURL: url)
        XCTAssertTrue(store.measurements.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "corrupt file should have been moved aside")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                      "corrupt file should be quarantined")
    }

    /// An unknown enum raw value (e.g. a case a newer build added) must not
    /// fail the whole-array decode; the record survives with the fallback case.
    func testUnknownEnumValueFallsBackInsteadOfWiping() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try JSONEncoder().encode([sample(anemia: .moderate)])
        var json = String(data: data, encoding: .utf8)!
        json = json.replacingOccurrences(of: "\"moderate\"", with: "\"a_future_case\"")
        try Data(json.utf8).write(to: url)

        let store = MeasurementStore(fileURL: url)
        XCTAssertEqual(store.measurements.count, 1)
        XCTAssertEqual(store.measurements.first?.anemia, .normal) // fallback
    }

    /// One unrecoverable record must not take the whole history with it.
    func testPartialCorruptionRecoversGoodRecords() throws {
        let url = tempURL()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt"))
        }

        let valid = try JSONEncoder().encode(sample())
        let validObj = String(data: valid, encoding: .utf8)!
        // Second element is missing every required field — undecodable.
        let json = "[\(validObj),{\"id\":\"not-a-uuid\"}]"
        try Data(json.utf8).write(to: url)

        let store = MeasurementStore(fileURL: url)
        XCTAssertEqual(store.measurements.count, 1)
    }
}
