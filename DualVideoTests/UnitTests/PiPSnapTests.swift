import XCTest
import SwiftUI
@testable import DualVideo

final class PiPSnapTests: XCTestCase {
    let container = CGSize(width: 390, height: 844)  // iPhone 14 logical pts
    let pip = CGSize(width: 109, height: 146)        // 28% of 390, 4:3 ratio
    let safe = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)  // typical notch device

    var margin: CGFloat { PiPOverlayState.edgeMargin }

    // Expected corner offsets (computed from formula, including guard margins):
    //   xLeft = -(390 - 109 - 24) = -257
    //   yTop  = topGuardMargin = 44
    //   yBottom = 844 - 59 - 34 - 146 - 24 - 80 (bottomGuardMargin) = 501
    var expectedTopRight:    CGSize { CGSize(width: 0, height: PiPOverlayState.topGuardMargin) }
    var expectedTopLeft:     CGSize { CGSize(width: -(container.width - pip.width - 2*margin), height: PiPOverlayState.topGuardMargin) }
    var expectedBottomRight: CGSize { CGSize(width: 0, height: container.height - safe.top - safe.bottom - pip.height - 2*margin - PiPOverlayState.bottomGuardMargin) }
    var expectedBottomLeft:  CGSize { CGSize(width: -(container.width - pip.width - 2*margin), height: container.height - safe.top - safe.bottom - pip.height - 2*margin - PiPOverlayState.bottomGuardMargin) }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "pip_corner_index")
    }

    func testSnapToTopRight() {
        let state = PiPOverlayState()
        state.offset = CGSize(width: -5, height: -5)  // near top-right
        state.snapToNearestCorner(containerSize: container, pipSize: pip, safeAreaInsets: safe)
        XCTAssertEqual(state.offset.width, expectedTopRight.width, accuracy: 1)
        XCTAssertEqual(state.offset.height, expectedTopRight.height, accuracy: 1)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "pip_corner_index"), 0)
    }

    func testSnapToTopLeft() {
        let state = PiPOverlayState()
        // Place offset solidly in top-left quadrant
        state.offset = CGSize(width: -200, height: 10)
        state.snapToNearestCorner(containerSize: container, pipSize: pip, safeAreaInsets: safe)
        XCTAssertEqual(state.offset.width, expectedTopLeft.width, accuracy: 1)
        XCTAssertEqual(state.offset.height, expectedTopLeft.height, accuracy: 1)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "pip_corner_index"), 1)
    }

    func testSnapToBottomRight() {
        let state = PiPOverlayState()
        state.offset = CGSize(width: -5, height: 400)
        state.snapToNearestCorner(containerSize: container, pipSize: pip, safeAreaInsets: safe)
        XCTAssertEqual(state.offset.width, expectedBottomRight.width, accuracy: 1)
        XCTAssertEqual(state.offset.height, expectedBottomRight.height, accuracy: 1)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "pip_corner_index"), 2)
    }

    func testSnapToBottomLeft() {
        let state = PiPOverlayState()
        state.offset = CGSize(width: -200, height: 400)
        state.snapToNearestCorner(containerSize: container, pipSize: pip, safeAreaInsets: safe)
        XCTAssertEqual(state.offset.width, expectedBottomLeft.width, accuracy: 1)
        XCTAssertEqual(state.offset.height, expectedBottomLeft.height, accuracy: 1)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "pip_corner_index"), 3)
    }

    func testRestorePersistedCornerIndex1() {
        UserDefaults.standard.set(1, forKey: "pip_corner_index")
        let state = PiPOverlayState()
        state.restorePersistedCorner(containerSize: container, pipSize: pip, safeAreaInsets: safe)
        XCTAssertEqual(state.offset.width, expectedTopLeft.width, accuracy: 1)
        XCTAssertEqual(state.offset.height, expectedTopLeft.height, accuracy: 1)
    }

    func testRestoreDefaultIsZero() {
        // No UserDefaults entry — index defaults to 0 (top-right with topGuardMargin)
        let state = PiPOverlayState()
        state.restorePersistedCorner(containerSize: container, pipSize: pip, safeAreaInsets: safe)
        XCTAssertEqual(state.offset.width, 0, accuracy: 1)
        XCTAssertEqual(state.offset.height, PiPOverlayState.topGuardMargin, accuracy: 1)
    }
}
