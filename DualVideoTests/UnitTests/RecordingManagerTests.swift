import XCTest
@testable import DualVideo

@MainActor
final class RecordingManagerTests: XCTestCase {

    func testInitialPhaseIsIdle() {
        let manager = RecordingManager()
        if case .idle = manager.phase { } else {
            XCTFail("Initial phase must be .idle, got \(manager.phase)")
        }
    }

    func testStartRecordingTransitionsToRecording() {
        let manager = RecordingManager()
        manager.startRecording()
        if case .recording = manager.phase { } else {
            XCTFail("Phase must be .recording after startRecording(), got \(manager.phase)")
        }
    }

    func testElapsedSecondsStartsAtZero() {
        let manager = RecordingManager()
        manager.startRecording()
        XCTAssertEqual(manager.elapsedSeconds, 0)
    }

    func testElapsedSecondsIncrementsWithClock() {
        let manager = RecordingManager()
        manager.startRecording()
        manager.advanceClock(by: 3)
        XCTAssertEqual(manager.elapsedSeconds, 3)
    }

    func testPendingFileURLSetAfterStop() {
        let manager = RecordingManager()
        manager.startRecording()
        let expectURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.mov")
        manager.injectMockStopURL(expectURL)  // test-only hook: bypasses AVAssetWriter
        XCTAssertEqual(manager.pendingFileURL, expectURL)
    }

    // MARK: - Settings-driven tests (Plan 04-02, Task 2)

    /// After startRecording(settings:) with hd720p, compositor dimensions must be 720×1280.
    /// Verifies compositor.outputWidth/Height are updated BEFORE recorder.startRecording(settings:).
    func testStartRecordingWithSettingsUpdatesCompositorDimensions() {
        let manager = RecordingManager()
        let compositor = PiPCompositor()
        manager.wireCompositor(compositor)

        let settings = VideoQualitySettings(resolution: .hd720p)
        manager.startRecording(settings: settings)

        XCTAssertEqual(compositor.outputWidth, 720,
                       "compositor.outputWidth must be 720 after startRecording with hd720p")
        XCTAssertEqual(compositor.outputHeight, 1280,
                       "compositor.outputHeight must be 1280 after startRecording with hd720p")
    }
}
