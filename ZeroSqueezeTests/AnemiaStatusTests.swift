import XCTest
@testable import ZeroSqueeze

final class AnemiaStatusTests: XCTestCase {

    func testNormalMale() {
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(14, gender: .male), .normal)
    }

    func testNormalFemale() {
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(12.5, gender: .female), .normal)
    }

    func testMildMale() {
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(11.5, gender: .male), .mild)
    }

    func testModerate() {
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(9, gender: .female), .moderate)
    }

    func testSevere() {
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(7, gender: .male), .severe)
    }

    func testOtherGenderMidpoint() {
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(12.6, gender: .other), .normal)
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(11.5, gender: .other), .mild)
    }

    /// NaN/inf must not silently fall through to `.mild` (which all
    /// comparisons against NaN would produce). Guard returns `.normal`.
    func testNonFiniteHemoglobinDoesNotMisclassify() {
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(.nan, gender: .male), .normal)
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(.infinity, gender: .female), .normal)
        XCTAssertEqual(AnemiaStatus.fromHemoglobin(-.infinity, gender: .other), .normal)
    }
}
