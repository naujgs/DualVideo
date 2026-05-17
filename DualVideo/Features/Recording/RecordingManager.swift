import AVFoundation
import Foundation
import Observation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.naujgs.DualVideo", category: "RecordingManager")

/// Recording lifecycle state, observable on the main thread.
enum RecordingPhase {
    case idle
    case recording(startedAt: Date)
    case finalizing
}

/// Coordinates PiPCompositor and MovieRecorder. Owns the observable recording state
/// and the elapsed timer. Attached to AppState.
///
/// Threading: phase and elapsedSeconds are @Observable main-thread properties.
/// Compositor callbacks arrive on dataOutputQueue and are forwarded to MovieRecorder there.
@Observable
final class RecordingManager: NSObject, @unchecked Sendable {

    // MARK: - Observable state (main thread)

    var phase: RecordingPhase = .idle
    var elapsedSeconds: Int = 0
    var pendingFileURL: URL? = nil
    /// Result of the most recent auto-save attempt. nil = no save attempted yet.
    var saveResult: Result<Void, PhotoSaveError>? = nil

    // MARK: - Internals

    nonisolated(unsafe) private let recorder = MovieRecorder()
    nonisolated(unsafe) private let photoSaver = PhotoSaveManager()
    nonisolated(unsafe) private var timerTask: Task<Void, Never>?
    /// Retained so startRecording() can bridge the pixel buffer pool to the compositor (WR-02).
    nonisolated(unsafe) private weak var compositor: PiPCompositor?

    // MARK: - Init

    override init() {
        super.init()
        // Clean up any orphaned .mov temp files from previous crashes (ASVS mitigation T-02-03-01)
        cleanUpOrphanedTempFiles()
    }

    // MARK: - Test support

    /// Test-only: advance the internal clock by `seconds`. Updates elapsedSeconds directly.
    func advanceClock(by seconds: Int) {
        elapsedSeconds += seconds
    }

    /// Test-only: inject a file URL as if stopRecording completed with that URL.
    func injectMockStopURL(_ url: URL) {
        pendingFileURL = url
    }

    // MARK: - Public API

    /// Wire all session outputs to RecordingManager and register interruption observers.
    /// Must be called after CameraManager finishes session configuration (i.e., after startSession() completes).
    /// Call from the main thread after session is running.
    @MainActor
    func setup(cameraManager: CameraManager) {
        // Wire compositor and cache screen metrics for dataOutputQueue use (CR-01)
        if let comp = cameraManager.compositor {
            wireCompositor(comp)
            comp.updateScreenMetrics()
        }

        // Use back-beam only for the audio recording track.
        // Wiring both outputs to the same AVAssetWriterInput doubles the sample count,
        // producing 2× audio duration and causing slow playback + noise.
        let audioQueue = DispatchQueue(label: "com.naujgs.DualVideo.audioDelegate", qos: .userInitiated)
        cameraManager.backAudioOutput?.setSampleBufferDelegate(self, queue: audioQueue)

        // Interruption observers (D-06)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak cameraManager] _ in
            self?.handleInterruption(cameraManager: cameraManager)
        }
        NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak cameraManager] _ in
            self?.handleInterruption(cameraManager: cameraManager)
        }

        // Interruption recovery (RESEARCH.md Pattern 5): when OS re-enables camera after phone call,
        // sync session running state so preview recovers without user action.
        NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: nil,
            queue: .main
        ) { [weak cameraManager] _ in
            // If session auto-restarted, reflect that in observable state
            cameraManager?.syncSessionRunningState()
            logger.info("RecordingManager: interruptionEnded — synced session running state")
        }

        logger.info("RecordingManager: setup complete, interruption observers registered")
    }

    /// Start recording. Transitions phase to .recording immediately (D-04: no countdown).
    /// Must be called from the main thread.
    @MainActor
    func startRecording() {
        guard case .idle = phase else {
            logger.warning("RecordingManager.startRecording() called in non-idle phase")
            return
        }

        let startDate = Date()
        phase = .recording(startedAt: startDate)
        elapsedSeconds = 0

        recorder.startRecording()
        // Bridge the pixel buffer pool from the adaptor to the compositor (WR-02).
        // recorder.startRecording() creates the adaptor synchronously, so the pool is available here.
        compositor?.pixelBufferPool = recorder.adaptor?.pixelBufferPool

        // Start elapsed timer — updates elapsedSeconds on main every second
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, case .recording = self.phase else { break }
                self.elapsedSeconds = Int(Date().timeIntervalSince(startDate))
            }
        }

        logger.info("RecordingManager: recording started")
    }

    /// Stop recording. Transitions to .finalizing, finalizes writer, then to .idle.
    /// Uses UIApplication.beginBackgroundTask to allow finalization even if app backgrounds (D-06).
    /// completion called on the main queue with the output URL (or nil on failure).
    @MainActor
    func stopRecording(completion: @escaping (URL?) -> Void = { _ in }) {
        guard case .recording = phase else {
            logger.warning("RecordingManager.stopRecording() called outside .recording phase")
            completion(nil)
            return
        }

        timerTask?.cancel()
        timerTask = nil
        phase = .finalizing

        // Acquire background task to ensure finalization completes even if app backgrounds (T-02-03-02).
        // bgTask is declared as var so the expiry closure captures the correct identifier (WR-01).
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "finalize-recording") {
            // OS-triggered expiration: cancel to avoid corruption
            logger.error("RecordingManager: background task expired — cancelling recorder")
            self.recorder.cancelAndDiscard()
            UIApplication.shared.endBackgroundTask(bgTask)
        }

        recorder.stopAndFinalize { [weak self] url in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingFileURL = url
                self.phase = .idle
                self.elapsedSeconds = 0
                UIApplication.shared.endBackgroundTask(bgTask)
                logger.info("RecordingManager: finalized, bgTask ended, url=\(url?.lastPathComponent ?? "nil")")
                if let url { self.saveRecording(url: url) }
                completion(url)
            }
        }
    }

    /// Trigger Photos auto-save for the given URL. Called from stopRecording completion.
    @MainActor
    private func saveRecording(url: URL) {
        photoSaver.saveVideoToPhotos(url: url) { [weak self] result in
            // Already dispatched to main by PhotoSaveManager
            self?.saveResult = result
            if case .success = result { self?.pendingFileURL = nil }
        }
    }

    /// Interrupt handler — auto-stop for phone calls / backgrounding (D-06).
    /// Called from interruption observers registered in setup(cameraManager:).
    /// Turns torch off before stopping to prevent battery drain (T-03-03-01).
    @MainActor
    func handleInterruption(cameraManager: CameraManager? = nil) {
        guard case .recording = phase else { return }
        logger.info("RecordingManager: interruption detected — auto-stopping")
        cameraManager?.turnTorchOff()
        stopRecording()
    }

    /// Wire compositor output to recorder. Called by setup(cameraManager:) after compositor is set up.
    /// compositor.onComposited is called on dataOutputQueue — recorder appends there.
    /// Stores a weak reference so startRecording() can bridge the pixel buffer pool (WR-02).
    func wireCompositor(_ compositor: PiPCompositor) {
        self.compositor = compositor
        compositor.onComposited = { [weak self] pixelBuffer, pts in
            // Already on dataOutputQueue — pass directly to recorder
            self?.recorder.appendVideoBuffer(pixelBuffer, pts: pts)
        }
    }

    /// Forward audio sample buffer to recorder (called on dataOutputQueue by audio delegate).
    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        recorder.appendAudioBuffer(sampleBuffer)
    }

    // MARK: - Private helpers

    private func cleanUpOrphanedTempFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        let orphans = contents.filter { $0.pathExtension == "mov" }
        for url in orphans {
            try? FileManager.default.removeItem(at: url)
            logger.info("RecordingManager: removed orphaned temp file \(url.lastPathComponent)")
        }
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension RecordingManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    /// Called on audioDelegate queue by the back-beam audio output (D-05).
    /// Only the back beam is registered as delegate; wiring both caused 2× audio duration.
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        appendAudioBuffer(sampleBuffer)
    }
}
