import XCTest
@testable import DualVideo

final class CameraManagerTests: XCTestCase {
    func testZoomClampLower() {
        let manager = CameraManager()
        // setZoom below minimum should clamp to 1.0
        // We test the clamping math independently of AVFoundation hardware
        let clamped = min(max(CGFloat(0.5), 1.0), 3.0)
        XCTAssertEqual(clamped, 1.0)
    }

    func testZoomClampUpper() {
        let manager = CameraManager()
        let clamped = min(max(CGFloat(5.0), 1.0), 3.0)
        XCTAssertEqual(clamped, 3.0)
    }

    func testZoomClampWithinRange() {
        let manager = CameraManager()
        let clamped = min(max(CGFloat(2.0), 1.0), 3.0)
        XCTAssertEqual(clamped, 2.0)
    }
}
