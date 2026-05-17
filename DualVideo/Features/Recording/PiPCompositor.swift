import AVFoundation
import CoreImage
import CoreVideo
import UIKit
import os.log

private let logger = Logger(subsystem: "com.naujgs.DualVideo", category: "PiPCompositor")

/// Composites back-camera and front-camera pixel buffers into a single 1920×1080 PiP frame
/// using Core Image (CISourceOverCompositing + CILanczosScaleTransform).
///
/// Threading model (MUST NOT change):
/// - captureOutput(_:didOutput:from:) is called by AVFoundation on dataOutputQueue.
/// - pipOffsetSnapshot is a nonisolated(unsafe) property written only from the main thread
///   via updatePiPOffset(_:). The compositor reads it on dataOutputQueue. This is safe:
///   one-directional write (main) → read (data queue), stale by at most one frame (acceptable).
/// - CIContext is created once on init. Creating CIContext per frame is a critical pitfall
///   that causes GPU resource exhaustion at 30fps.
/// - pixelBufferPool from AVAssetWriterInputPixelBufferAdaptor is set externally after
///   MovieRecorder sets up the writer. Until set, composite() allocates its own buffer.
final class PiPCompositor: NSObject {

    // MARK: - Test observability (incremented only in init)
    /// Number of times CIContext was initialized. Must be exactly 1 after init.
    private(set) var ciContextInitCount: Int = 0

    // MARK: - Core Image context (created ONCE on init — never inside composite())
    private let ciContext: CIContext

    // MARK: - Output dimensions (portrait: frames arrive pre-rotated 90° by videoRotationAngle)
    static let outputWidth = 1080
    static let outputHeight = 1920

    // MARK: - PiP offset snapshot (thread-safe: written on main, read on dataOutputQueue)
    /// Snapshot of PiPOverlayState.offset. Updated from the main thread via updatePiPOffset(_:).
    /// The compositor reads this on dataOutputQueue — safe because writes are one-directional
    /// from main and a one-frame staleness is visually imperceptible.
    nonisolated(unsafe) private(set) var pipOffsetSnapshot: CGSize = .zero

    // MARK: - Screen metric snapshots (CR-01: UIScreen.main is @MainActor — must not be read on dataOutputQueue)
    /// Snapshot of UIScreen.main.bounds.width. Updated from the main thread via updateScreenMetrics().
    nonisolated(unsafe) private(set) var screenWidthSnapshot: CGFloat = 393  // safe default for portrait iPhone
    /// Snapshot of UIScreen.main.scale. Updated from the main thread via updateScreenMetrics().
    nonisolated(unsafe) private(set) var screenScaleSnapshot: CGFloat = 2.0

    // MARK: - Frame buffers (dataOutputQueue-serialized)
    /// Latest back-camera pixel buffer from AVCaptureVideoDataOutputSampleBufferDelegate.
    nonisolated(unsafe) private var latestBackBuffer: CVPixelBuffer?
    /// Latest front-camera pixel buffer.
    nonisolated(unsafe) private var latestFrontBuffer: CVPixelBuffer?

    // MARK: - Output delegate
    /// Called on dataOutputQueue with the composited pixel buffer and its presentation timestamp.
    /// MovieRecorder sets this to append frames to AVAssetWriterInputPixelBufferAdaptor.
    var onComposited: ((CVPixelBuffer, CMTime) -> Void)?

    // MARK: - Pixel buffer pool (provided by MovieRecorder after writer setup)
    /// When set, composite() acquires output buffers from this pool (avoids per-frame allocation).
    /// When nil, composite() allocates a fresh CVPixelBuffer each call (acceptable for tests).
    nonisolated(unsafe) var pixelBufferPool: CVPixelBufferPool?

    // MARK: - Output references (used to identify which output is back vs front in delegate)
    /// The AVCaptureVideoDataOutput wired to the back camera. Set by CameraManager.
    nonisolated(unsafe) weak var backVideoOutput: AVCaptureVideoDataOutput?
    /// The AVCaptureVideoDataOutput wired to the front camera. Set by CameraManager.
    nonisolated(unsafe) weak var frontVideoOutput: AVCaptureVideoDataOutput?

    // MARK: - Init

    override init() {
        // Create CIContext ONCE. Metal-backed (default on iOS; useSoftwareRenderer: false is the default).
        // Do NOT pass .workingColorSpace: nil — use explicit device RGB.
        ciContext = CIContext(options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .useSoftwareRenderer: false
        ])
        ciContextInitCount += 1
        super.init()
    }

    // MARK: - Public API

    /// Update the PiP offset snapshot. MUST be called from the main thread.
    /// Typically called from a SwiftUI onChange or PiPOverlayState observation.
    @MainActor
    func updatePiPOffset(_ offset: CGSize) {
        pipOffsetSnapshot = offset
    }

    /// Cache UIScreen metrics for use on dataOutputQueue. MUST be called from the main thread.
    /// Call once after session starts (e.g. from RecordingManager.setup) and on orientation change.
    @MainActor
    func updateScreenMetrics() {
        screenWidthSnapshot = UIScreen.main.bounds.width
        screenScaleSnapshot = UIScreen.main.scale
    }

    /// Composites back and front pixel buffers into a 1920×1080 PiP output buffer.
    /// - Parameters:
    ///   - back: 1920×1080 CVPixelBuffer from the back camera.
    ///   - front: CVPixelBuffer from the front camera (any resolution; scaled to pipRect).
    ///   - pipRect: Destination rect for the front camera PiP in output coordinates (1920×1080 space).
    /// - Returns: A 1920×1080 CVPixelBuffer with front camera composited over back camera at pipRect, or nil on failure.
    func composite(back: CVPixelBuffer, front: CVPixelBuffer, pipRect: CGRect) -> CVPixelBuffer? {
        // Acquire output buffer from pool if available, otherwise allocate
        guard let outBuffer = acquireOutputBuffer() else {
            logger.error("PiPCompositor: failed to acquire output buffer")
            return nil
        }

        let backCI = CIImage(cvPixelBuffer: back)

        // Scale front camera to pipRect dimensions
        let frontCI = CIImage(cvPixelBuffer: front)
        let srcWidth = CGFloat(CVPixelBufferGetWidth(front))
        let srcHeight = CGFloat(CVPixelBufferGetHeight(front))
        let scaleX = pipRect.width / srcWidth
        let scaleY = pipRect.height / srcHeight

        let scaledFront = frontCI
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: pipRect.minX, y: pipRect.minY))

        // Composite: front over back using CISourceOverCompositing
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            logger.error("PiPCompositor: CISourceOverCompositing unavailable")
            return nil
        }
        compositeFilter.setValue(scaledFront, forKey: kCIInputImageKey)
        compositeFilter.setValue(backCI, forKey: kCIInputBackgroundImageKey)
        guard let composited = compositeFilter.outputImage else {
            logger.error("PiPCompositor: CIFilter produced nil outputImage")
            return nil
        }

        // Render into output buffer using the singleton CIContext (never recreate inside this method)
        ciContext.render(composited, to: outBuffer)
        return outBuffer
    }

    // MARK: - Private helpers

    private func acquireOutputBuffer() -> CVPixelBuffer? {
        if let pool = pixelBufferPool {
            var buf: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buf)
            if status == kCVReturnSuccess { return buf }
            logger.warning("PiPCompositor: pool allocation failed (\(status)), falling back to direct alloc")
        }
        // Fallback: allocate directly (used in tests and before MovieRecorder sets pool)
        return allocateFallbackBuffer()
    }

    private func allocateFallbackBuffer() -> CVPixelBuffer? {
        var buf: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.outputWidth,
            kCVPixelBufferHeightKey as String: Self.outputHeight,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Self.outputWidth, Self.outputHeight,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buf
        )
        guard status == kCVReturnSuccess else {
            logger.error("PiPCompositor: CVPixelBufferCreate failed with \(status)")
            return nil
        }
        return buf
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PiPCompositor: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on dataOutputQueue by AVFoundation for each camera frame.
    /// Routes frame to back or front buffer based on output identity.
    /// Composites and calls onComposited when both buffers are available.
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if output === backVideoOutput {
            latestBackBuffer = pixelBuffer
        } else if output === frontVideoOutput {
            latestFrontBuffer = pixelBuffer
        }

        // Only composite on back-camera frames (back is the clock reference for output)
        guard output === backVideoOutput,
              let back = latestBackBuffer,
              let front = latestFrontBuffer else { return }

        // Compute pipRect from offset snapshot (read pipOffsetSnapshot — safe on dataOutputQueue)
        let offset = pipOffsetSnapshot
        // PiP: 28% of 1920 wide, 4:3 aspect, positioned at offset from top-right of 1920x1080 space.
        // Top-right anchor in 1920×1080: x = 1920 - pipWidth - margin, y = margin
        let pipWidth: CGFloat = CGFloat(Self.outputWidth) * 0.28
        let pipHeight: CGFloat = pipWidth * (4.0 / 3.0)
        // Use cached screen metrics — UIScreen.main is @MainActor and must not be read here (CR-01)
        let screenWidth = screenWidthSnapshot
        let screenScale = screenScaleSnapshot
        let margin: CGFloat = PiPOverlayState.edgeMargin / screenScale * (CGFloat(Self.outputWidth) / screenWidth)
        // Scale UI-space offset to output space (portrait: 1080 wide)
        let scaleToOutput = CGFloat(Self.outputWidth) / screenWidth
        let xAnchor = CGFloat(Self.outputWidth) - pipWidth - margin
        let yAnchor = margin
        let pipRect = CGRect(
            x: xAnchor + offset.width * scaleToOutput,
            y: yAnchor + offset.height * scaleToOutput,
            width: pipWidth,
            height: pipHeight
        )

        guard let composited = composite(back: back, front: front, pipRect: pipRect) else { return }
        onComposited?(composited, pts)
    }
}
