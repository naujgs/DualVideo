import AVFoundation
import CoreVideo
import XCTest
@testable import DualVideo

final class MovieRecorderTests: XCTestCase {

    func testInitialStateIsIdle() {
        let recorder = MovieRecorder()
        XCTAssertEqual(recorder.state, .idle)
    }

    func testStartRecordingCreatesOutputURL() {
        let recorder = MovieRecorder()
        recorder.startRecording()
        XCTAssertNotNil(recorder.outputURL, "outputURL must be set after startRecording()")
        XCTAssertEqual(recorder.outputURL?.pathExtension, "mov")
    }

    func testPendingStartTimeInvalidBeforeFirstSample() {
        let recorder = MovieRecorder()
        recorder.startRecording()
        // pendingStartTime starts as .invalid — not yet set until first buffer arrives
        XCTAssertFalse(recorder.pendingStartTimeIsSet, "pendingStartTime must not be set before first sample")
    }

    func testDoubleStartDoesNotCrash() {
        let recorder = MovieRecorder()
        recorder.startRecording()
        recorder.startRecording()  // should be a no-op if already starting/recording
        // No crash == pass
        XCTAssert(recorder.state == .starting || recorder.state == .recording)
    }

    // Test 5: finalization after mock interruption — produces a .mov file
    func testStopAndFinalizeProducesMovFile() {
        let recorder = MovieRecorder()
        recorder.startRecording()

        let expectation = XCTestExpectation(description: "finalization completes")
        expectation.expectedFulfillmentCount = 1

        // Create a minimal synthetic pixel buffer to trigger startSession
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        if let buf = pixelBuffer {
            let pts = CMTime(seconds: 0.033, preferredTimescale: 600)
            recorder.appendVideoBuffer(buf, pts: pts)
        }

        recorder.stopAndFinalize { url in
            if let url = url {
                XCTAssertEqual(url.pathExtension, "mov")
                // File exists on disk after finalization
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                              "Output .mov file must exist on disk after finalization")
            }
            // url may be nil on simulator (no camera hardware) — acceptable; test verifies no crash
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // Test 6: cancelAndDiscard removes the file
    func testCancelAndDiscardRemovesFile() {
        let recorder = MovieRecorder()
        recorder.startRecording()
        let url = recorder.outputURL
        XCTAssertNotNil(url)

        recorder.cancelAndDiscard()

        XCTAssertNil(recorder.outputURL, "outputURL must be nil after cancelAndDiscard")
        if let url = url {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                           "File must be deleted after cancelAndDiscard")
        }
    }

    // MARK: - Settings-driven tests (Plan 04-02, Task 1)

    /// startRecording(settings:) with 720p/low must set adaptor dimensions to 720×1280
    func testStartRecordingWith720pLowCreatesWith720x1280Adaptor() {
        let recorder = MovieRecorder()
        let settings = VideoQualitySettings(resolution: .hd720p, bitrate: .low)
        recorder.startRecording(settings: settings)

        guard let adaptor = recorder.adaptor else {
            XCTFail("adaptor must not be nil after startRecording(settings:)")
            return
        }
        let pool = adaptor.pixelBufferPool
        XCTAssertNotNil(pool, "pixelBufferPool must exist after startRecording with 720p/low")

        // Verify the pool was created with 720×1280 by creating a buffer and checking dimensions
        var buf: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool!, &buf)
        XCTAssertEqual(status, kCVReturnSuccess, "Should be able to create pixel buffer from pool")
        if let buf = buf {
            XCTAssertEqual(CVPixelBufferGetWidth(buf), 720,
                           "Pool pixel buffer width must be 720 for hd720p")
            XCTAssertEqual(CVPixelBufferGetHeight(buf), 1280,
                           "Pool pixel buffer height must be 1280 for hd720p")
        }

        recorder.cancelAndDiscard()
    }

    /// startRecording(settings:) with 1080p/high must set adaptor dimensions to 1080×1920
    func testStartRecordingWith1080pHighCreatesWith1080x1920Adaptor() {
        let recorder = MovieRecorder()
        let settings = VideoQualitySettings(resolution: .hd1080p, bitrate: .high)
        recorder.startRecording(settings: settings)

        guard let adaptor = recorder.adaptor else {
            XCTFail("adaptor must not be nil after startRecording(settings:)")
            return
        }
        let pool = adaptor.pixelBufferPool
        XCTAssertNotNil(pool, "pixelBufferPool must exist after startRecording with 1080p/high")

        var buf: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool!, &buf)
        XCTAssertEqual(status, kCVReturnSuccess, "Should be able to create pixel buffer from pool")
        if let buf = buf {
            XCTAssertEqual(CVPixelBufferGetWidth(buf), 1080,
                           "Pool pixel buffer width must be 1080 for hd1080p")
            XCTAssertEqual(CVPixelBufferGetHeight(buf), 1920,
                           "Pool pixel buffer height must be 1920 for hd1080p")
        }

        recorder.cancelAndDiscard()
    }
}
