import XCTest
import SwiftUI
@testable import DualVideo

final class PiPDragClampTests: XCTestCase {
    let state = PiPOverlayState()
    let containerSize = CGSize(width: 390, height: 844)  // iPhone 15 points
    let pipSize = CGSize(width: 109, height: 145)        // 28% of 390
    let safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    func testDefaultOffsetIsZero() {
        let result = state.clampedOffset(proposed: .zero, containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
        XCTAssertEqual(result.width, 0, accuracy: 0.5)
        XCTAssertEqual(result.height, 0, accuracy: 0.5)
    }

    func testClampTopEdge() {
        // Drag upward past top safe area — should clamp at yMin
        let proposed = CGSize(width: 0, height: -200)
        let result = state.clampedOffset(proposed: proposed, containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
        // After clamping, PiP top edge = safeAreaInsets.top + margin = 59 + 12 = 71
        // clamped yAbs == yMin == 71 → height offset == 0
        XCTAssertEqual(result.height, 0, accuracy: 0.5, "PiP should not go above safe-area + margin")
    }

    func testClampBottomEdge() {
        // Drag downward past bottom safe area
        let proposed = CGSize(width: 0, height: 1000)
        let result = state.clampedOffset(proposed: proposed, containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
        let yMax = containerSize.height - safeAreaInsets.bottom - pipSize.height - PiPOverlayState.edgeMargin
        let yAnchor = safeAreaInsets.top + PiPOverlayState.edgeMargin
        let expectedMaxHeightOffset = yMax - yAnchor
        XCTAssertEqual(result.height, expectedMaxHeightOffset, accuracy: 0.5, "PiP should not go below safe-area + margin")
    }

    func testClampLeadingEdge() {
        // Drag left (positive width offset = moves PiP left)
        let proposed = CGSize(width: 1000, height: 0)
        let result = state.clampedOffset(proposed: proposed, containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
        let xAnchor = containerSize.width - pipSize.width - PiPOverlayState.edgeMargin
        // xAbs clamped to xMin = margin = 12; offsetX = xAnchor - 12
        XCTAssertEqual(result.width, xAnchor - PiPOverlayState.edgeMargin, accuracy: 0.5, "PiP should not go past leading margin")
    }
}
