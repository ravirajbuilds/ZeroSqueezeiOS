import XCTest
@testable import ZeroSqueeze

@MainActor
final class StoreDeleteTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("store-del-\(UUID().uuidString).json")
    }

    func testRemoveHbById() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MeasurementStore(fileURL: url)
        let a = HbMeasurement.placeholder
        let b = HbMeasurement(
            id: UUID(), timestamp: Date(), heartRateBpm: 70,
            hemoglobinGPerDl: 13, hemoglobinBand: 1, perfusionIndex: 2,
            signalQuality: 0.8, anemia: .normal
        )
        store.append(a)
        store.append(b)
        XCTAssertEqual(store.measurements.count, 2)
        store.remove(id: a.id)
        XCTAssertEqual(store.measurements.map(\.id), [b.id])
    }

    func testRemoveUnknownIdIsNoOp() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MeasurementStore(fileURL: url)
        store.append(.placeholder)
        store.remove(id: UUID())
        XCTAssertEqual(store.measurements.count, 1)
    }

    func testRemoveFaceById() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SCGMeasurementStore(fileURL: url)
        let a = SCGMeasurement.placeholder
        let b = SCGMeasurement(
            id: UUID(), timestamp: Date(), heartRateBpm: 66, hrvSdnnMs: 40, signalQuality: 0.7
        )
        store.append(a)
        store.append(b)
        store.remove(id: b.id)
        XCTAssertEqual(store.measurements.map(\.id), [a.id])
    }
}
