import XCTest
@testable import ZeroSqueeze

@MainActor
final class SCGMeasurementTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let original = SCGMeasurement(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            heartRateBpm: 68,
            hrvSdnnMs: 42.5,
            lvetMs: 300,
            aoAmplitudeMg: 16,
            estSystolicMmHg: 118,
            estDiastolicMmHg: 76,
            signalQuality: 0.74
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SCGMeasurement.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodableWithNilFields() throws {
        let original = SCGMeasurement(
            id: UUID(), timestamp: Date(),
            heartRateBpm: nil, hrvSdnnMs: nil, signalQuality: 0.3
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SCGMeasurement.self, from: data)
        XCTAssertNil(decoded.heartRateBpm)
        XCTAssertNil(decoded.hrvSdnnMs)
        XCTAssertNil(decoded.lvetMs)
        XCTAssertNil(decoded.estSystolicMmHg)
    }

    /// Old records (pre-SCG-morphology) must still decode: the morphology and
    /// BP fields are optional, so a minimal JSON should round-trip with nils.
    func testDecodesLegacyRecordWithoutMorphology() throws {
        let json = """
        {"id":"\(UUID().uuidString)","timestamp":726000000,"heartRateBpm":70,"hrvSdnnMs":40,"signalQuality":0.8}
        """
        let decoded = try JSONDecoder().decode(SCGMeasurement.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.heartRateBpm, 70)
        XCTAssertNil(decoded.lvetMs)
        XCTAssertNil(decoded.aoAmplitudeMg)
    }

    func testStorePersistsAndLoads() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zerosqueeze-scg-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let s1 = SCGMeasurementStore(fileURL: url)
        XCTAssertEqual(s1.measurements.count, 0)
        s1.append(SCGMeasurement.placeholder)
        s1.append(SCGMeasurement(
            id: UUID(), timestamp: Date(),
            heartRateBpm: 80, hrvSdnnMs: 30, signalQuality: 0.8
        ))

        let exp = expectation(description: "persist")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let s2 = SCGMeasurementStore(fileURL: url)
        XCTAssertEqual(s2.measurements.count, 2)
        XCTAssertEqual(s2.latest?.heartRateBpm, 80)
    }

    func testStoreSurvivesCorruptFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zerosqueeze-scg-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("garbage".utf8).write(to: url)
        let s = SCGMeasurementStore(fileURL: url)
        XCTAssertEqual(s.measurements.count, 0)
    }
}
