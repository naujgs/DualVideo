import XCTest
import CoreVideo
import CoreImage
@testable import DualVideo

final class PiPCompositorTests: XCTestCase {

    // MARK: - Helpers

    /// Create a synthetic BGRA CVPixelBuffer filled with a solid color, for use without real cameras.
    private func makeSyntheticBuffer(width: Int, height: Int, red: UInt8 = 128, green: UInt8 = 64, blue: UInt8 = 32) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess, "CVPixelBufferCreate failed")
        guard let buffer = pixelBuffer else { XCTFail("nil pixel buffer"); fatalError() }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let count = CVPixelBufferGetDataSize(buffer)
            // Fill with BGRA: B=blue, G=green, R=red, A=255
            var ptr = base.assumingMemoryBound(to: UInt8.self)
            for _ in 0 ..< (count / 4) {
                ptr[0] = blue; ptr[1] = green; ptr[2] = red; ptr[3] = 255
                ptr = ptr.advanced(by: 4)
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    // MARK: - Tests

    func testCompositeOutputNonNil() {
        let compositor = PiPCompositor()
        let back = makeSyntheticBuffer(width: 1920, height: 1080)
        let front = makeSyntheticBuffer(width: 1440, height: 1080, red: 200, green: 100, blue: 50)
        let pipRect = CGRect(x: 100, y: 100, width: 320, height: 240)
        let result = compositor.composite(back: back, front: front, pipRect: pipRect)
        XCTAssertNotNil(result, "composite() must return a non-nil CVPixelBuffer")
    }

    func testCompositeOutputDimensions() {
        let compositor = PiPCompositor()
        let back = makeSyntheticBuffer(width: 1920, height: 1080)
        let front = makeSyntheticBuffer(width: 1440, height: 1080)
        let pipRect = CGRect(x: 0, y: 0, width: 480, height: 360)
        guard let result = compositor.composite(back: back, front: front, pipRect: pipRect) else {
            XCTFail("composite() returned nil"); return
        }
        XCTAssertEqual(CVPixelBufferGetWidth(result), 1920)
        XCTAssertEqual(CVPixelBufferGetHeight(result), 1080)
    }

    func testPiPOffsetSnapshot() {
        let compositor = PiPCompositor()
        compositor.updatePiPOffset(CGSize(width: 50, height: 80))
        XCTAssertEqual(compositor.pipOffsetSnapshot.width, 50)
        XCTAssertEqual(compositor.pipOffsetSnapshot.height, 80)
    }

    func testCIContextCreatedOnce() {
        let compositor = PiPCompositor()
        let back = makeSyntheticBuffer(width: 1920, height: 1080)
        let front = makeSyntheticBuffer(width: 1440, height: 1080)
        let pipRect = CGRect(x: 0, y: 0, width: 320, height: 240)
        _ = compositor.composite(back: back, front: front, pipRect: pipRect)
        _ = compositor.composite(back: back, front: front, pipRect: pipRect)
        // ciContextInitCount is incremented only in init; calling composite() twice must not increment it
        XCTAssertEqual(compositor.ciContextInitCount, 1, "CIContext must be created once on init, not per composite() call")
    }
}
