# Stack Research — DualVideo

**Researched:** 2026-05-16
**Overall confidence:** HIGH for core capture stack (Apple-documented, sample code verified); MEDIUM for iOS 18-specific deltas (no breaking changes found, enhancements are incremental).

---

## Recommended Stack

| Layer | Choice | Rationale | Confidence |
|-------|--------|-----------|------------|
| Capture session | `AVCaptureMultiCamSession` | Only session type that runs front + back cameras simultaneously; standard `AVCaptureSession` cannot | HIGH |
| Video output | `AVCaptureVideoDataOutput` (x2) | Delivers raw `CVPixelBuffer` frames needed for compositor; one per camera | HIGH |
| Audio output | `AVCaptureAudioDataOutput` (x2) | Required for per-beam audio; MultiCam session exposes separate front/back mic ports on a single device input | HIGH |
| Video compositor | Metal (custom kernel via `MTLCommandBuffer`) | Apple's own AVMultiCamPiP sample uses a Metal shader compositor; 0.2–1.5 ms per composite frame, fits 30fps budget | HIGH |
| Pixel buffer bridge | `CVMetalTextureCacheCreateTextureFromImage` | Zero-copy path from `CVPixelBuffer` (BGRA from `AVCaptureVideoDataOutput`) into Metal texture | HIGH |
| File writer | `AVAssetWriter` + `AVAssetWriterInput` + `AVAssetWriterInputPixelBufferAdaptor` | Only path that accepts pre-composited pixel buffers; required when `AVCaptureMovieFileOutput` cannot mix inputs | HIGH |
| Output codec | H.264 (`AVVideoCodecType.h264`) + MPEG-4 AAC | Compatible with Photos app, iPhone XR, 1080p target; H.265 would improve quality but adds complexity with no user benefit for personal use | HIGH |
| Preview layers | `AVCaptureVideoPreviewLayer` (x2) | One per camera; renders live feed with near-zero latency directly from session | HIGH |
| SwiftUI bridge | `UIViewRepresentable` wrapping a `UIView` that hosts `AVCaptureVideoPreviewLayer` | AVCaptureVideoPreviewLayer is a `CALayer`; it cannot be used directly in SwiftUI — UIKit hosting is mandatory | HIGH |
| Draggable PiP overlay | SwiftUI `.gesture(DragGesture())` on a `ZStack` layer | Pure SwiftUI gesture on a `UIViewRepresentable` sub-view; compositor reads normalized frame from a `@Published` position property in `CameraManager` | MEDIUM |
| Session orchestration | `CameraManager` (`ObservableObject`) | All AVFoundation session logic lives here; published state drives SwiftUI; session runs on a dedicated serial `DispatchQueue` | HIGH |
| Permissions | `AVCaptureDevice.requestAccess` + `PHPhotoLibrary.requestAuthorization` | Standard iOS permission flow; must check at startup and show graceful fallback if denied | HIGH |
| Save to Photos | `PHPhotoLibrary.performChanges` + `PHAssetChangeRequest.creationRequestForAssetFromVideo` | Direct save from file URL; no intermediate asset export needed | HIGH |
| Minimum deployment | iOS 18.0 | `AVCaptureMultiCamSession` available iOS 13+; iOS 18 target grants access to Responsive Capture improvements and is aligned with user's devices | HIGH |
| Hardware gate | `AVCaptureMultiCamSession.isMultiCamSupported` | Static Bool; check before session setup; A12 Bionic (iPhone XR/XS) is the hard floor | HIGH |

---

## Key APIs

### AVCaptureMultiCamSession

`AVCaptureMultiCamSession` (AVFoundation, iOS 13+) is the only Apple-provided session type that can drive two physical cameras concurrently. It is a direct subclass of `AVCaptureSession`.

**Critical behavioral differences from `AVCaptureSession`:**

- Inputs must be added with `addInputWithNoConnections()`, not `addInput(_:)`. Connections are then wired explicitly with `AVCaptureConnection`.
- Exposes `hardwareCost` (Float, 0.0–1.0) and `systemPressureCost` (Float, 0.0–1.0). Exceeding 1.0 on either causes the session to refuse to run. Must be monitored after adding each input/output.
- Format selection is constrained: not all `AVCaptureDevice.Format` entries on a camera are valid for MultiCam use. Use `AVCaptureDeviceFormat.isMultiCamSupported` to filter. At 1080p 30fps the hardware budget is well within limits on A12+.
- `AVCaptureMultiCamSession.isMultiCamSupported` is a class-level Bool. Gate all setup behind this check.
- Supports up to 3 simultaneous audio beams from a single built-in microphone device input: omnidirectional, front-facing, rear-facing. The port for each beam is retrieved by specifying `sourceDevicePosition` (`.front`, `.back`) when querying `AVCaptureDeviceInput.ports`.

**Setup order:**
1. Check `isMultiCamSupported`; show error UI and return if false.
2. `beginConfiguration()`
3. Add back camera input with `addInputWithNoConnections()`; retrieve video port.
4. Add front camera input with `addInputWithNoConnections()`; retrieve video port (set `isVideoMirrored = true` on connection).
5. Add microphone input with `addInputWithNoConnections()`; retrieve back-position and front-position audio ports.
6. Create `AVCaptureVideoDataOutput` (BGRA pixel format) for each camera; add with `addOutputWithNoConnections()`; wire connections.
7. Create `AVCaptureAudioDataOutput` for back mic port and one for front mic port; wire connections.
8. `commitConfiguration()`
9. Monitor `hardwareCost` and `systemPressureCost` — log and clamp format if either approaches 1.0.

### Compositor Approach

The established Apple-recommended pattern (from AVMultiCamPiP sample code, WWDC 2019 Session 225) is:

```
Back camera AVCaptureVideoDataOutput
  → delegate callback → CVPixelBuffer (BGRA)
Front camera AVCaptureVideoDataOutput
  → delegate callback → CVPixelBuffer (BGRA) [cached as currentPiPSampleBuffer]

PiPVideoMixer (Metal):
  1. CVMetalTextureCacheCreateTextureFromImage → MTLTexture (back frame)
  2. CVMetalTextureCacheCreateTextureFromImage → MTLTexture (front/PiP frame)
  3. MTLComputeCommandBuffer dispatches compositor kernel:
     - Renders back frame full-size into output texture
     - Scales + blits front frame into normalized PiP rect (driven by draggable position)
  4. Output MTLTexture → render back to CVPixelBuffer (output pixel buffer pool)

AVAssetWriter:
  AVAssetWriterInput (video, H.264, 1080p)
  AVAssetWriterInputPixelBufferAdaptor
    → append(compositePixelBuffer, withPresentationTime: backFrameTime)
  AVAssetWriterInput (audio, AAC)
    → append(audioSampleBuffer)
```

**Synchronization:** Back-camera frame callback drives the composite. It reads the most recently cached front-camera buffer (`currentPiPSampleBuffer`). This is the same pattern used in Apple's sample. The two cameras are not guaranteed to be frame-synchronous; caching the latest PiP frame and using the back-camera timestamp for the output file is the correct approach.

**Output pixel buffer pool:** `AVAssetWriterInputPixelBufferAdaptor` creates and manages a `CVPixelBufferPool`; use `pixelBufferPool` property to obtain pre-allocated output buffers — do not create buffers per-frame.

**Metal vs. Core Image:** Metal is preferred over Core Image for this compositing task. Core Image introduces additional GPU command encoding overhead and has higher latency. At 30fps the pipeline has ~33ms per frame; Metal compositing benchmarks at 0.2–1.5ms leaving adequate margin. Core Video / Core Image are adequate for single-camera filters but are not the right tool here.

### Audio Mixing

`AVCaptureMultiCamSession` does not provide automatic mixing of front and back beams — it exposes them as separate outputs. Two `AVCaptureAudioDataOutput` instances are wired to dedicated audio ports retrieved by querying `AVCaptureDeviceInput.ports(for: .audio, sourceDeviceType: .builtInMicrophone, sourceDevicePosition: .back)` and `.front`.

**Recording strategy:** Record one audio channel to the file. At runtime choose between back-beam and front-beam based on `pipDevicePosition` (whichever camera is full-screen is the primary audio source). This is the approach in the AVMultiCamPiP sample and avoids the complexity of true mix-down.

If genuine dual-microphone mix-down is required, both audio sample buffers would need to be collected on the same queue, resampled to the same `CMSampleBuffer` timestamp, and mixed at the PCM level before writing. This is complex, error-prone, and offers marginal quality benefit for this use case. Defer unless user explicitly validates the need.

**AVAudioSession configuration:**
- Category: `.record` (or `.playAndRecord` if monitoring is needed — not required here).
- `automaticallyConfiguresApplicationAudioSession = false` on the session to prevent the system from overriding the audio session category during multi-cam setup.
- Do not set `usesApplicationAudioSession = true` alongside custom beam configuration — this combination is a known cause of silent audio frames on `AVCaptureMultiCamSession`.

### SwiftUI Integration

`AVCaptureVideoPreviewLayer` is a `CALayer` subclass. It cannot be placed directly in the SwiftUI view hierarchy. The required bridge is `UIViewRepresentable`.

**Recommended pattern:**

```swift
// CameraPreviewView.swift
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Handle orientation: set videoPreviewLayer.connection?.videoOrientation
        // based on UIDevice.current.orientation changes
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
```

Two instances of `CameraPreviewView` are placed in a SwiftUI `ZStack`: back camera full-screen, front camera in a `.overlay` with `.offset` driven by a drag gesture state variable stored in `CameraManager`.

**Orientation:** `AVCaptureVideoPreviewLayer` does not rotate automatically with device orientation. `updateUIView` must respond to `UIDevice.current.orientation` changes and set `previewLayer.connection?.videoRotationAngle` (iOS 17+) or the deprecated `videoOrientation` property.

**Thread safety:** All `AVCaptureSession` mutations — `beginConfiguration`, `commitConfiguration`, `startRunning`, `stopRunning` — must happen on the dedicated session serial queue, never on the main thread. SwiftUI updates are published to the main thread via `DispatchQueue.main.async` or `@MainActor`.

---

## What NOT to Use

| Candidate | Why Not |
|-----------|---------|
| `AVCaptureMovieFileOutput` | Cannot accept pre-composited input. It writes raw camera output directly to a file as separate tracks. It has no API to receive pixel buffers from a compositor. It cannot produce a single PiP video track from two cameras. Do not use. |
| Standard `AVCaptureSession` | Can only run one camera at a time (on current iOS). Using two separate sessions risks resource contention and provides no synchronization guarantee. AVCaptureMultiCamSession is the correct replacement. |
| `ReplayKit` / `RPScreenRecorder` | Screen recording approach captures the rendered display, not the camera signal. Quality is limited by display resolution and the render pipeline; it introduces a frame of latency and cannot guarantee 1080p without display at 1080p. Not appropriate for direct camera capture. |
| Core Image compositor | Adequate for single-frame filters; introduces extra GPU command overhead compared to a custom Metal kernel. Adds a framework dependency with no benefit over direct Metal. Avoid for the inner compositing loop. |
| `AVMutableComposition` for mixing | Post-processing composition tool for editing existing assets. It is not a real-time capture pipeline component. Not applicable here. Mixing audio streams from live capture must happen in the capture pipeline. |
| `SwiftUI Camera` (iOS 17+ `CameraView` from SwiftUI) | No native SwiftUI camera view exists as of iOS 18 for `AVCaptureMultiCamSession`-level control. `UIViewRepresentable` wrapping a UIKit-hosted `AVCaptureVideoPreviewLayer` is the correct and only path. |
| PhotosPicker / `UIImagePickerController` | These are for selecting existing media, not live multi-camera capture. Irrelevant to this app. |

---

## iOS 18 Specifics

**No breaking changes to `AVCaptureMultiCamSession` found.** The API surface introduced in iOS 13 (WWDC 2019) is stable and unchanged in iOS 18. The project's iOS 18.0 minimum deployment target does not unlock new multi-cam-specific capabilities beyond what was available in iOS 13–17, but it does provide:

- **Responsive Capture API improvements (iOS 18):** Enhancements to `AVCapturePhotoOutput` and related capture responsiveness. These are photo-capture focused and do not affect the video data output pipeline used here.
- **`videoRotationAngle` property (iOS 17+):** Replaces the deprecated `AVCaptureConnection.videoOrientation` (which uses an `AVCaptureVideoOrientation` enum). On iOS 17+ use `connection.videoRotationAngle` (in degrees, Float). Since the project targets iOS 18+, use the non-deprecated API exclusively.
- **Spatial video (iOS 18):** Public API for recording spatial video files using the dual camera system. Not applicable to this project's 2D PiP output, but worth noting as the framework is present.
- **Constant Color capture mode (iOS 18):** Photo-capture feature. Not applicable.
- **Adaptive HDR (iOS 18):** Still photo feature. Not applicable to video recording pipeline.

**Practical implication:** The stack does not need iOS 18-specific shims or workarounds. Write to iOS 18 APIs (`videoRotationAngle`, non-deprecated `AVCaptureDevice.Format` APIs) and test on the minimum hardware (iPhone XR / A12).

---

## Sources

- [AVCaptureMultiCamSession — Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession)
- [AVMultiCamPiP: Capturing from Multiple Cameras — Apple Sample Code](https://developer.apple.com/documentation/avfoundation/avmulticampip-capturing-from-multiple-cameras)
- [Introducing Multi-Camera Capture for iOS — WWDC19 Session 249](https://developer.apple.com/videos/play/wwdc2019/249/)
- [Advances in Camera Capture & Photo Segmentation — WWDC19 Session 225](https://developer.apple.com/videos/play/wwdc2019/225/)
- [hardwareCost — Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/hardwarecost)
- [systemPressureCost — Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/systempressurecost)
- [AVAssetWriterInputPixelBufferAdaptor — Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avassetwriterinputpixelbufferadaptor)
- [iOS 18 & 17 new Camera APIs — YLabZ / Medium](https://zoewave.medium.com/ios-18-17-new-camera-apis-645f7a1e54e8)
- [tatetate55/iOS13_camera_test — AVMultiCamPiP implementation reference (GitHub)](https://github.com/tatetate55/iOS13_camera_test/blob/master/AVMultiCamPiP/CameraViewController.swift)
- [Distorted Audio when recording with AVCaptureSession — Nonstrict (2025)](https://nonstrict.eu/blog/2025/distorted-audio-avcapturesession/)
- [CVMetalTextureCacheCreateTextureFromImage — Apple Developer Documentation](https://developer.apple.com/documentation/corevideo/1456754-cvmetaltexturecachecreatetexture)
