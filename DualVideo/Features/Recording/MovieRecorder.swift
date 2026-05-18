import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.naujgs.DualVideo", category: "MovieRecorder")

/// AVAssetWriter state machine for producing a settings-driven H.264/AAC .mov file.
///
/// Threading model: all methods called from dataOutputQueue (except startRecording/stopRecording
/// which may be called from main via RecordingManager). Internal state mutations are serialized
/// on dataOutputQueue. Public start/stop are dispatched to dataOutputQueue internally.
///
/// State machine: idle -> starting -> recording -> finalizing -> idle
final class MovieRecorder {

    // MARK: - State (serialized on dataOutputQueue)

    enum State: Equatable {
        case idle
        case starting
        case recording
        case finalizing
    }

    nonisolated(unsafe) private(set) var state: State = .idle

    // MARK: - Writer objects (nonisolated(unsafe), dataOutputQueue-serialized)

    nonisolated(unsafe) private(set) var outputURL: URL?
    nonisolated(unsafe) private var writer: AVAssetWriter?
    nonisolated(unsafe) private var videoInput: AVAssetWriterInput?
    nonisolated(unsafe) private var audioInput: AVAssetWriterInput?
    nonisolated(unsafe) private(set) var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    // MARK: - PTS tracking (for Pitfall 3: use first sample PTS, not .zero)

    nonisolated(unsafe) private var sessionStartTime: CMTime = .invalid
    /// Exposed for testing: true after first sample sets the session start time
    nonisolated(unsafe) private(set) var pendingStartTimeIsSet: Bool = false

    // MARK: - Public API

    func startRecording(settings: VideoQualitySettings = VideoQualitySettings()) {
        // Guard: only start from .idle
        guard state == .idle else {
            logger.warning("MovieRecorder.startRecording() called in non-idle state: \(String(describing: self.state))")
            return
        }
        state = .starting

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        outputURL = url

        do {
            let w = try AVAssetWriter(url: url, fileType: .mov)

            // Video input: H.264 at settings-specified resolution and bitrate
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey:  settings.resolution.width,
                AVVideoHeightKey: settings.resolution.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey:      settings.bitrate.bitsPerSecond,
                    AVVideoMaxKeyFrameIntervalKey: 30       // keyframe every 1 second at 30fps
                ]
            ]
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true  // REQUIRED for live capture
            vInput.transform = .identity

            // Pixel buffer adaptor: compositor produces kCVPixelFormatType_32BGRA buffers
            let adap = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: vInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String:           settings.resolution.width,
                    kCVPixelBufferHeightKey as String:          settings.resolution.height
                ]
            )

            // Audio input: AAC stereo 44.1kHz 128kbps
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100.0,
                AVEncoderBitRateKey: 128_000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true  // REQUIRED for live capture

            w.add(vInput)
            w.add(aInput)

            // Start writing — do NOT call startSession() here; call on first sample buffer (Pitfall 3)
            w.startWriting()

            writer = w
            videoInput = vInput
            audioInput = aInput
            adaptor = adap
            sessionStartTime = .invalid
            pendingStartTimeIsSet = false

            logger.info("MovieRecorder: writer started, url=\(url.lastPathComponent)")
        } catch {
            logger.error("MovieRecorder: AVAssetWriter init failed: \(error.localizedDescription)")
            state = .idle
            outputURL = nil
        }
    }

    /// Append a composited video pixel buffer. Called on dataOutputQueue by PiPCompositor.onComposited.
    func appendVideoBuffer(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard state == .starting || state == .recording else { return }
        guard let w = writer, w.status == .writing else {
            if let w = writer {
                logger.error("MovieRecorder: writer in bad state: \(w.status.rawValue), error: \(String(describing: w.error))")
            }
            return
        }
        guard let vInput = videoInput, let adap = adaptor else { return }

        // Start session on first sample (Pitfall 3: use actual PTS, not .zero)
        if state == .starting {
            w.startSession(atSourceTime: pts)
            sessionStartTime = pts
            pendingStartTimeIsSet = true
            state = .recording
            logger.info("MovieRecorder: session started at PTS \(pts.seconds)")
        }

        guard vInput.isReadyForMoreMediaData else {
            logger.debug("MovieRecorder: videoInput not ready, dropping frame at \(pts.seconds)")
            return
        }

        let appended = adap.append(pixelBuffer, withPresentationTime: pts)
        if !appended {
            logger.error("MovieRecorder: adaptor.append failed. writer.status=\(w.status.rawValue), error=\(String(describing: w.error))")
        }
    }

    /// Append an audio sample buffer. Called on dataOutputQueue by AVCaptureAudioDataOutput delegate.
    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording else { return }
        guard let w = writer, w.status == .writing else { return }
        guard let aInput = audioInput, aInput.isReadyForMoreMediaData else { return }

        let appended = aInput.append(sampleBuffer)
        if !appended {
            logger.error("MovieRecorder: audio append failed. writer.status=\(w.status.rawValue)")
        }
    }

    /// Finalize the recording. Calls completion with the output URL on an arbitrary queue.
    /// Safe to call from background (beginBackgroundTask) for interruption handling (D-06).
    func stopAndFinalize(completion: @escaping (URL?) -> Void) {
        // Guard: if we never started (state == .starting with no samples yet), cancel (Pitfall 6)
        if state == .starting {
            logger.warning("MovieRecorder: stop called before first frame — cancelling writer")
            writer?.cancelWriting()
            cleanup()
            completion(nil)
            return
        }
        guard state == .recording else {
            completion(nil)
            return
        }
        state = .finalizing

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        // Capture writer and url locally before the async boundary (WR-04).
        // A concurrent cancelAndDiscard() can nil self.writer between the closure entry and the
        // status read, so capture the local reference now while still on the calling thread.
        let url = outputURL
        guard let w = writer else { cleanup(); completion(nil); return }
        w.finishWriting { [weak self] in
            let finalURL: URL?
            if w.status == .completed {
                finalURL = url
                logger.info("MovieRecorder: finalization complete, url=\(url?.lastPathComponent ?? "nil")")
            } else {
                logger.error("MovieRecorder: finalization failed, status=\(w.status.rawValue)")
                finalURL = nil
            }
            self?.cleanup()
            completion(finalURL)
        }
    }

    func cancelAndDiscard() {
        writer?.cancelWriting()
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        cleanup()
        logger.info("MovieRecorder: cancelled and discarded")
    }

    // MARK: - Private

    private func cleanup() {
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        outputURL = nil
        sessionStartTime = .invalid
        pendingStartTimeIsSet = false
        state = .idle
    }
}
