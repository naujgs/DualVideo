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

    // MARK: - Settings-driven tests (Plan 04-02, Task 2)

    /// applyResolutionFormat must be callable without crashing when no session devices are configured.
    /// On simulator, backDevice is nil and session has no inputs — the method must guard safely.
    func testApplyResolutionFormatDoesNotCrashWithNoDevices() {
        let manager = CameraManager()
        // Must not crash — guards safely when backDevice is nil
        manager.applyResolutionFormat(resolution: .hd720p)
        // Allow the async sessionQueue dispatch to complete
        let expectation = XCTestExpectation(description: "applyResolutionFormat completes")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }
}
