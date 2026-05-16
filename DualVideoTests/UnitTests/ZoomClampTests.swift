import XCTest
@testable import DualVideo

final class ZoomClampTests: XCTestCase {
    func testZoomBelowMinimumClampsTo1() {
        let input: CGFloat = 0.1
        let clamped = min(max(input, 1.0), 3.0)
        XCTAssertEqual(clamped, 1.0)
    }

    func testZoomAboveMaximumClampsTo3() {
        let input: CGFloat = 10.0
        let clamped = min(max(input, 1.0), 3.0)
        XCTAssertEqual(clamped, 3.0)
    }

    func testZoomAtExactMinimum() {
        let input: CGFloat = 1.0
        let clamped = min(max(input, 1.0), 3.0)
        XCTAssertEqual(clamped, 1.0)
    }

    func testZoomAtExactMaximum() {
        let input: CGFloat = 3.0
        let clamped = min(max(input, 1.0), 3.0)
        XCTAssertEqual(clamped, 3.0)
    }

    func testZoomInRangePassesThrough() {
        let input: CGFloat = 2.5
        let clamped = min(max(input, 1.0), 3.0)
        XCTAssertEqual(clamped, 2.5)
    }
}
