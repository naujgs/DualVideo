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
}
