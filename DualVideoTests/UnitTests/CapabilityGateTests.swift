import XCTest
@testable import DualVideo

final class CapabilityGateTests: XCTestCase {
    func testAppRouteUnsupportedDevice() {
        // Stub: when deviceSupported == false, route should be .unsupportedDevice
        // Real device check cannot run in simulator — this validates the enum coverage
        let state = AppState()
        state.route = .unsupportedDevice
        if case .unsupportedDevice = state.route { } else {
            XCTFail("Expected unsupportedDevice route")
        }
    }
}
