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
    var isTorchOn: Bool = false

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

    /// Toggle back-camera torch on/off. Guards hasTorch and isTorchModeSupported (Pitfall 6).
    /// Uses same lockForConfiguration pattern as setZoom() (RESEARCH.md Pattern 3).
    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let device = self?.backDevice,
                  device.hasTorch,
                  device.isTorchModeSupported(.on) else { return }
            do {
                try device.lockForConfiguration()
                let newMode: AVCaptureDevice.TorchMode = (device.torchMode == .on) ? .off : .on
                device.torchMode = newMode
                device.unlockForConfiguration()
                DispatchQueue.main.async { self?.isTorchOn = (newMode == .on) }
            } catch {
                logger.error("Torch toggle failed: \(error.localizedDescription)")
            }
        }
    }

    /// Turn torch off if currently on. Called on recording interruption (RESEARCH.md Pitfall 3).
    func turnTorchOff() {
        sessionQueue.async { [weak self] in
            guard let device = self?.backDevice,
                  device.hasTorch,
                  device.isTorchModeSupported(.on),
                  device.torchMode == .on else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
                DispatchQueue.main.async { self?.isTorchOn = false }
            } catch {
                logger.error("Torch off failed: \(error.localizedDescription)")
            }
        }
    }

    /// Apply a resolution to both cameras by selecting matching AVCaptureDevice formats.
    /// Must be called before session starts (format cannot change during active recording).
    /// Call from sessionQueue. Exposed for use by CameraContentView via AppState.qualitySettings.
    func applyResolutionFormat(resolution: OutputResolution) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if let back = self.backDevice {
                self.applyFormat(to: back, targetLandscapeWidth: resolution.landscapeWidth)
            }
            // Front device: get from session inputs
            for input in self.session.inputs {
                if let deviceInput = input as? AVCaptureDeviceInput,
                   deviceInput.device.position == .front {
                    self.applyFormat(to: deviceInput.device, targetLandscapeWidth: resolution.landscapeWidth)
                }
            }
            self.session.commitConfiguration()
            let cost = self.session.hardwareCost
            logger.info("CameraManager: applyResolutionFormat complete, hardwareCost=\(cost, format: .fixed(precision: 3))")
            if cost >= 0.9 {
                logger.error("CameraManager: hardwareCost \(cost) >= 0.9 after format change — may need to revert")
            }
        }
    }

    /// Apply a frame rate to both cameras by setting activeVideoMinFrameDuration and
    /// activeVideoMaxFrameDuration on each capture device.
    /// Must be called when not actively recording (format/rate changes during recording are unsupported).
    /// Dispatches to sessionQueue internally.
    func applyFrameRate(_ fps: FrameRatePreset) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let duration = CMTime(value: 1, timescale: CMTimeScale(fps.rawValue))
            // Back camera
            if let back = self.backDevice {
                self.setFrameDuration(duration, on: back)
            }
            // Front camera (accessed via session inputs)
            for input in self.session.inputs {
                if let deviceInput = input as? AVCaptureDeviceInput,
                   deviceInput.device.position == .front {
                    self.setFrameDuration(duration, on: deviceInput.device)
                }
            }
            logger.info("CameraManager: applyFrameRate \(fps.rawValue) fps applied to both cameras")
        }
    }

    /// Sync isSessionRunning with the actual session state. Called after interruptionEnded.
    func syncSessionRunningState() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let running = self.session.isRunning
            DispatchQueue.main.async { self.isSessionRunning = running }
        }
    }

    // MARK: - Private helpers

    /// Sets activeVideoMinFrameDuration and activeVideoMaxFrameDuration on a device.
    /// Must be called on sessionQueue.
    private func setFrameDuration(_ duration: CMTime, on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
            logger.info("CameraManager: set frame duration \(duration.timescale) fps on \(device.localizedName)")
        } catch {
            logger.error("CameraManager: frame duration lock failed for \(device.localizedName): \(error)")
        }
    }

    /// Selects the AVCaptureDevice activeFormat matching targetLandscapeWidth.
    /// Filters for isMultiCamSupported to avoid formats invalid for AVCaptureMultiCamSession.
    /// Must be called inside a beginConfiguration/commitConfiguration block on sessionQueue.
    /// - Parameters:
    ///   - device: The AVCaptureDevice to configure.
    ///   - targetLandscapeWidth: Landscape pixel width (1280 for 720p, 1920 for 1080p).
    private func applyFormat(to device: AVCaptureDevice, targetLandscapeWidth: Int) {
        let preferred = device.formats.first { fmt in
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            return Int(dims.width) == targetLandscapeWidth && fmt.isMultiCamSupported
        }
        guard let format = preferred else {
            logger.warning("CameraManager: no isMultiCamSupported format found for landscapeWidth=\(targetLandscapeWidth) on \(device.localizedName) — keeping current format")
            return
        }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            logger.info("CameraManager: set activeFormat \(dims.width)×\(dims.height) on \(device.localizedName)")
        } catch {
            logger.error("CameraManager: format lock failed for \(device.localizedName): \(error)")
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
                // Explicitly disable mirroring on back camera data output.
                // AVCaptureMultiCamSession can default isVideoMirrored=true for back camera
                // connections when videoRotationAngle is applied, causing the recorded frames
                // to appear horizontally flipped relative to the live preview.
                if backConn.isVideoMirroringSupported {
                    backConn.automaticallyAdjustsVideoMirroring = false
                    backConn.isVideoMirrored = false
                }
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
                // Disable mirroring on front camera data output.
                // Front camera connections default isVideoMirrored=true (selfie mirror behavior).
                // For recorded video, un-mirror so content matches physical reality.
                if frontConn.isVideoMirroringSupported {
                    frontConn.automaticallyAdjustsVideoMirroring = false
                    frontConn.isVideoMirrored = false
                }
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

        // Apply initial resolution format from default settings (D-01: 1080p default)
        // Uses backDevice captured above; front device accessed via session inputs
        let defaultResolution = VideoQualitySettings().resolution
        if let back = backDevice {
            applyFormat(to: back, targetLandscapeWidth: defaultResolution.landscapeWidth)
        }
        for input in session.inputs {
            if let deviceInput = input as? AVCaptureDeviceInput,
               deviceInput.device.position == .front {
                applyFormat(to: deviceInput.device, targetLandscapeWidth: defaultResolution.landscapeWidth)
            }
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
