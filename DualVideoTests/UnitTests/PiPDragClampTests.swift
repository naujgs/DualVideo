import XCTest
import SwiftUI
@testable import DualVideo

final class PiPDragClampTests: XCTestCase {
    let state = PiPOverlayState()
    let containerSize = CGSize(width: 390, height: 844)  // iPhone 15 points
    let pipSize = CGSize(width: 109, height: 145)        // 28% of 390
    let safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    func testDefaultOffsetIsZero() {
        // Proposed .zero hits the topGuardMargin clamp → height offset equals topGuardMargin
        let result = state.clampedOffset(proposed: .zero, containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
        XCTAssertEqual(result.width, 0, accuracy: 0.5)
        XCTAssertEqual(result.height, PiPOverlayState.topGuardMargin, accuracy: 0.5)
    }

    func testClampTopEdge() {
        // Drag upward past top safe area — should clamp at yMin (includes topGuardMargin)
        let proposed = CGSize(width: 0, height: -200)
        let result = state.clampedOffset(proposed: proposed, containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
        // yMin = safeAreaInsets.top + margin + topGuardMargin = 59 + 12 + 44 = 115
        // yAnchor = 59 + 12 = 71 → clampedOffsetY = 115 - 71 = topGuardMargin = 44
        XCTAssertEqual(result.height, PiPOverlayState.topGuardMargin, accuracy: 0.5, "PiP should not go above safe-area + margin + topGuardMargin")
    }

    func testClampBottomEdge() {
        // Drag downward past bottom safe area
        let proposed = CGSize(width: 0, height: 1000)
        let result = state.clampedOffset(proposed: proposed, containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
        let yMax = containerSize.height - safeAreaInsets.bottom - pipSize.height - PiPOverlayState.edgeMargin - PiPOverlayState.bottomGuardMargin
        let yAnchor = safeAreaInsets.top + PiPOverlayState.edgeMargin
        let expectedMaxHeightOffset = yMax - yAnchor
        XCTAssertEqual(result.height, expectedMaxHeightOffset, accuracy: 0.5, "PiP should not go below safe-area + margin + bottomGuardMargin")
    }

    func testClampLeadingEdge() {
        // Drag left (negative width = moves PiP left, matching SwiftUI translation convention)
        let proposed = CGSize(width: -1000, height: 0)
        let result = state.clampedOffset(proposed: proposed, containerSize: containerSize, pipSize: pipSize, safeAreaInsets: safeAreaInsets)
        let xAnchor = containerSize.width - pipSize.width - PiPOverlayState.edgeMargin
        // xAbs = xAnchor - 1000, clamped to xMin = margin; offsetX = margin - xAnchor (negative)
        XCTAssertEqual(result.width, PiPOverlayState.edgeMargin - xAnchor, accuracy: 0.5, "PiP should not go past leading margin")
    }
}
