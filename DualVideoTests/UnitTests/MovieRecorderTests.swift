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
}
