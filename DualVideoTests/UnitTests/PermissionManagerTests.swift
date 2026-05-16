import XCTest
@testable import DualVideo

final class PermissionManagerTests: XCTestCase {
    func testPermissionStatusGrantedCoverage() async {
        // Stub: PermissionManager type is importable and requestAll returns a known value
        // Full permission flows require physical device interaction — tested manually per VALIDATION.md
        let manager = PermissionManager()
        let status = await manager.currentStatus()
        // Just validate it returns without crashing; simulator returns .notDetermined
        _ = status
    }
}
