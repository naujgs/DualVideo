import XCTest
import SwiftUI
@testable import DualVideo

final class ZoomLabelTests: XCTestCase {
    func testFormatOne()        { XCTAssertEqual(ZoomLabelView.formatZoom(1.0),  "1.0x") }
    func testFormatTwoFive()    { XCTAssertEqual(ZoomLabelView.formatZoom(2.5),  "2.5x") }
    func testFormatRoundsUp()   { XCTAssertEqual(ZoomLabelView.formatZoom(1.45), "1.5x") }
    func testFormatThree()      { XCTAssertEqual(ZoomLabelView.formatZoom(3.0),  "3.0x") }
}
