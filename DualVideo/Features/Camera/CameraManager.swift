import AVFoundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.naujgs.DualVideo", category: "CameraManager")

/// CameraManager owns the AVCaptureMultiCamSession and all session-related objects.
///
/// Threading model:
/// - @Observable properties (backZoomFactor, isSessionRunning, sessionError) are read/written
///   on the main actor.
/// - All AVFoundation session work runs on sessionQueue via nonisolated(unsafe) + manual
///   serialization. nonisolated(unsafe) opts these properties out of Swift 6 actor isolation
///   checks; correctness is enforced by the caller always accessing them only from sessionQueue
///   or under DispatchQueue.main.sync.
/// - backPreviewLayer / frontPreviewLayer are set up before startSession() and their session
///   reference is assigned under DispatchQueue.main.sync in configureAndStart(), making them
///   safe to read from UIViewRepresentable.makeUIView/updateUIView (main thread).
@Observable
final class CameraManager: @unchecked Sendable {
    // MARK: - Session objects (sessionQueue-serialized; nonisolated(unsafe) for Swift 6)
    nonisolated(unsafe) private let session = AVCaptureMultiCamSession()
    nonisolated(unsafe) private let sessionQueue = DispatchQueue(
        label: "com.naujgs.DualVideo.session", qos: .userInitiated)
    nonisolated(unsafe) let dataOutputQueue = DispatchQueue(
        label: "com.naujgs.DualVideo.dataOutput", qos: .userInitiated)
    nonisolated(unsafe) private var backDevice: AVCaptureDevice?

    // MARK: - Preview layers
    // Created on init (main thread); session reference assigned under main.sync in
    // configureAndStart(). Safe to read from UIViewRepresentable on main thread.
    nonisolated(unsafe) private(set) var backPreviewLayer: AVCaptureVideoPreviewLayer
    nonisolated(unsafe) private(set) var frontPreviewLayer: AVCaptureVideoPreviewLayer

    // MARK: - Video outputs (stored so compositor can reference them)
    nonisolated(unsafe) private(set) var backVideoOutput: AVCaptureVideoDataOutput?
    nonisolated(unsafe) private(set) var frontVideoOutput: AVCaptureVideoDataOutput?

    // MARK: - Audio outputs (stored so RecordingManager can set delegate)
    nonisolated(unsafe) private(set) var backAudioOutput: AVCaptureAudioDataOutput?
    nonisolated(unsafe) private(set) var frontAudioOutput: AVCaptureAudioDataOutput?

    // MARK: - Compositor (set before startSession() by AppState; wired after commitConfiguration)
    nonisolated(unsafe) var compositor: PiPCompositor?

    // MARK: - Observable state (main thread reads/writes via @Observable)
    var backZoomFactor: CGFloat = 1.0
    var isSessionRunning: Bool = false
    var sessionError: String? = nil

    init() {
        backPreviewLayer = AVCaptureVideoPreviewLayer()
        frontPreviewLayer = AVCaptureVideoPreviewLayer()
    }

    // MARK: - Public API

    func startSession() {
        sessionQueue.async { [weak self] in
            self?.configureAndStart()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { [weak self] in self?.isSessionRunning = false }
        }
    }

    /// Clamp zoom to D-09 range: 1.0x–3.0x. Called from Plan 03 pinch gesture.
    func setZoom(_ factor: CGFloat) {
        let clamped = min(max(factor, 1.0), 3.0)
        backZoomFactor = clamped
        sessionQueue.async { [weak self] in
            guard let device = self?.backDevice else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                logger.error("Zoom lock failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private session configuration (always runs on sessionQueue)

    private func configureAndStart() {
        // NEVER call startRunning on main thread — iOS 18 freeze risk
        precondition(!Thread.isMainThread, "configureAndStart must not run on main thread")

        session.beginConfiguration()

        // Back camera input
        guard
            let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let backInput = try? AVCaptureDeviceInput(device: backCamera),
            session.canAddInput(backInput)
        else {
            session.commitConfiguration()
            handleError("Failed to add back camera input")
            return
        }
        session.addInputWithNoConnections(backInput)
        backDevice = backCamera

        // Front camera input
        guard
            let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let frontInput = try? AVCaptureDeviceInput(device: frontCamera),
            session.canAddInput(frontInput)
        else {
            session.commitConfiguration()
            handleError("Failed to add front camera input")
            return
        }
        session.addInputWithNoConnections(frontInput)

        // Back video data output (Phase 2: promoted to stored property for compositor wiring)
        let bvo = AVCaptureVideoDataOutput()
        bvo.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(bvo) else {
            session.commitConfiguration()
            handleError("Cannot add back video output")
            return
        }
        session.addOutputWithNoConnections(bvo)
        self.backVideoOutput = bvo

        // Front video data output (Phase 2: promoted to stored property for compositor wiring)
        let fvo = AVCaptureVideoDataOutput()
        fvo.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(fvo) else {
            session.commitConfiguration()
            handleError("Cannot add front video output")
            return
        }
        session.addOutputWithNoConnections(fvo)
        self.frontVideoOutput = fvo

        // Wire connections: back port → back output, front port → front output
        // videoRotationAngle = 90 rotates delivered pixel buffers 90° CW, correcting the iPhone
        // sensor's native landscape orientation to portrait for compositor + recorder.
        if let backPort = backInput.ports(for: .video, sourceDeviceType: backCamera.deviceType, sourceDevicePosition: .back).first {
            let backConn = AVCaptureConnection(inputPorts: [backPort], output: bvo)
            if session.canAddConnection(backConn) {
                session.addConnection(backConn)
                if backConn.isVideoRotationAngleSupported(90) { backConn.videoRotationAngle = 90 }
            }

            // Back preview layer connection
            let backPreviewConn = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backPreviewLayer)
            if session.canAddConnection(backPreviewConn) { session.addConnection(backPreviewConn) }
        }

        if let frontPort = frontInput.ports(for: .video, sourceDeviceType: frontCamera.deviceType, sourceDevicePosition: .front).first {
            let frontConn = AVCaptureConnection(inputPorts: [frontPort], output: fvo)
            if session.canAddConnection(frontConn) {
                session.addConnection(frontConn)
                if frontConn.isVideoRotationAngleSupported(90) { frontConn.videoRotationAngle = 90 }
            }

            // Front preview layer connection
            let frontPreviewConn = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontPreviewLayer)
            if session.canAddConnection(frontPreviewConn) { session.addConnection(frontPreviewConn) }
        }

        // Dual-mic audio input (D-05): back-beam + front-beam, blended by AVFoundation
        if let micDevice = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: micDevice),
           session.canAddInput(micInput) {
            session.addInputWithNoConnections(micInput)

            let backAudioOut = AVCaptureAudioDataOutput()
            let frontAudioOut = AVCaptureAudioDataOutput()

            // Track each beam independently so partial failures are logged separately (WR-03)
            var backAudioWired = false
            var frontAudioWired = false
            if session.canAddOutput(backAudioOut) {
                session.addOutputWithNoConnections(backAudioOut)
                if let backAudioPort = micInput.ports(
                    for: .audio,
                    sourceDeviceType: micDevice.deviceType,
                    sourceDevicePosition: .back
                ).first {
                    let backAudioConn = AVCaptureConnection(inputPorts: [backAudioPort], output: backAudioOut)
                    if session.canAddConnection(backAudioConn) {
                        session.addConnection(backAudioConn)
                        backAudioWired = true
                        logger.info("CameraManager: back-beam audio output wired")
                    }
                }
            }
            if session.canAddOutput(frontAudioOut) {
                session.addOutputWithNoConnections(frontAudioOut)
                if let frontAudioPort = micInput.ports(
                    for: .audio,
                    sourceDeviceType: micDevice.deviceType,
                    sourceDevicePosition: .front
                ).first {
                    let frontAudioConn = AVCaptureConnection(inputPorts: [frontAudioPort], output: frontAudioOut)
                    if session.canAddConnection(frontAudioConn) {
                        session.addConnection(frontAudioConn)
                        frontAudioWired = true
                        logger.info("CameraManager: front-beam audio output wired")
                    }
                }
            }
            self.backAudioOutput = backAudioOut
            self.frontAudioOutput = frontAudioOut
            if !backAudioWired {
                logger.warning("CameraManager: back-beam audio wiring failed — no audio will be recorded; check iOS 16.1+ regression")
            }
            if !frontAudioWired {
                logger.warning("CameraManager: front-beam audio wiring failed — front mic unavailable")
            }
        } else {
            logger.warning("CameraManager: microphone input unavailable — no audio will be recorded")
        }

        // Explicit commitConfiguration() BEFORE reading hardwareCost.
        // hardwareCost reflects COMMITTED session state only — reading before commit gives a
        // stale value. Do NOT use defer here. (Apple docs: hardwareCost valid after commit only.)
        session.commitConfiguration()

        // Hardware cost validation — read AFTER commitConfiguration (includes audio inputs).
        // Re-read hardwareCost after audio inputs added (RESEARCH.md Open Question 3).
        let cost = session.hardwareCost
        logger.info("AVCaptureMultiCamSession hardwareCost (with audio): \(cost, format: .fixed(precision: 3))")
        guard cost < 0.9 else {
            handleError("Hardware cost \(cost) after audio exceeds 0.9 — session not started")
            return
        }

        // Wire compositor as video delegate on both outputs (Phase 2 hookup)
        if let comp = compositor {
            comp.backVideoOutput = bvo
            comp.frontVideoOutput = fvo
            bvo.setSampleBufferDelegate(comp, queue: dataOutputQueue)
            fvo.setSampleBufferDelegate(comp, queue: dataOutputQueue)
            logger.info("CameraManager: PiPCompositor wired as video delegate")
        }

        // Associate real session with preview layers before startRunning.
        // DispatchQueue.main.sync is safe — we are on sessionQueue (not main), no deadlock.
        DispatchQueue.main.sync {
            self.backPreviewLayer.session = self.session
            self.frontPreviewLayer.session = self.session
            self.backPreviewLayer.videoGravity = .resizeAspectFill
            self.frontPreviewLayer.videoGravity = .resizeAspectFill
        }

        session.startRunning()
        DispatchQueue.main.async { [weak self] in self?.isSessionRunning = true }
        logger.info("AVCaptureMultiCamSession started")
    }

    private func handleError(_ message: String) {
        logger.error("\(message)")
        DispatchQueue.main.async { [weak self] in self?.sessionError = message }
    }
}
