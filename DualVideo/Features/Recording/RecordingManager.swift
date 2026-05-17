import AVFoundation
import Foundation
import Observation
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
final class RecordingManager {

    // MARK: - Observable state (main thread)

    var phase: RecordingPhase = .idle
    var elapsedSeconds: Int = 0
    var pendingFileURL: URL? = nil

    // MARK: - Internals

    nonisolated(unsafe) private let recorder = MovieRecorder()
    nonisolated(unsafe) private var timerTask: Task<Void, Never>?

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
    /// completion called on an arbitrary queue with the output URL (or nil on failure).
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

        recorder.stopAndFinalize { [weak self] url in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingFileURL = url
                self.phase = .idle
                self.elapsedSeconds = 0
                logger.info("RecordingManager: finalized, url=\(url?.lastPathComponent ?? "nil")")
                completion(url)
            }
        }
    }

    /// Interrupt handler — auto-stop for phone calls / backgrounding (D-06).
    /// Called from RecordingManager interrupt observer (wired in Plan 02-03).
    @MainActor
    func handleInterruption() {
        guard case .recording = phase else { return }
        logger.info("RecordingManager: interruption detected — auto-stopping")
        stopRecording()
    }

    /// Wire compositor output to recorder. Called by Plan 02-03 after compositor is set up.
    /// compositor.onComposited is called on dataOutputQueue — recorder appends there.
    func wireCompositor(_ compositor: PiPCompositor) {
        compositor.onComposited = { [weak self] pixelBuffer, pts in
            // Already on dataOutputQueue — pass directly to recorder
            self?.recorder.appendVideoBuffer(pixelBuffer, pts: pts)
        }
    }

    /// Forward audio sample buffer to recorder (called on dataOutputQueue by audio delegate in Plan 02-03).
    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        recorder.appendAudioBuffer(sampleBuffer)
    }
}
