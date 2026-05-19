# Stack Research — DualVideo

**Researched:** 2026-05-16 (v1 base) / 2026-05-19 (v1.1 4K addendum)
**Overall confidence:** HIGH for core capture stack (Apple-documented, sample code verified); MEDIUM for iOS 18-specific deltas (no breaking changes found, enhancements are incremental).

---

## v1.1 Addendum: 4K Detection and Recording

This section supersedes any v1 claims about resolution limits. All v1 stack decisions remain valid; the sections below document what changes or is added for 4K support.

### What Changes for 4K

| Component | v1 State | v1.1 Change | Why |
|-----------|----------|-------------|-----|
| `OutputResolution` enum | `.hd720p`, `.hd1080p` | Add `.uhd4K` | New resolution case required |
| `VideoQualitySettings` | Default `.hd1080p` | No default change | 4K is hardware-gated, not default |
| `MovieRecorder` codec | `AVVideoCodecType.h264` | Use HEVC for 4K, H.264 for ≤1080p | H.264 encoder cannot sustain 4K30 on A-series within practical bitrate |
| `MovieRecorder` bitrate | Not set (uses encoder default for H.264) | Explicit `AVVideoAverageBitRateKey` for HEVC 4K | Default HEVC encoding is too conservative at 4K |
| `PiPCompositor` output dimensions | `1080×1920` (portrait) | Set to `2160×3840` when 4K selected | Buffer pool and CI render target must match output |
| `CameraManager.applyFormat` | Matches on `landscapeWidth == 1920` | Matches on `landscapeWidth == 3840` for 4K | Existing filter pattern extends naturally |
| 4K capability detection | Not present | New function: enumerate back camera formats, find 4K `isMultiCamSupported == true` | Gate UI option on hardware capability |

### 4K Capability Detection

**API to use:** `AVCaptureDevice.formats` + `AVCaptureDeviceFormat.isMultiCamSupported` + `CMVideoFormatDescriptionGetDimensions`

**The correct detection pattern:**

```swift
func deviceSupports4KMultiCam(for device: AVCaptureDevice) -> Bool {
    return device.formats.contains { fmt in
        guard fmt.isMultiCamSupported else { return false }
        let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        return dims.width == 3840
    }
}
```

**Where to call it:** In `CameraManager.configureAndStart()` after `backDevice` is assigned, before `commitConfiguration()`. Publish a `Bool` observable property (e.g., `supports4K`) to `@Observable CameraManager`. `QualitySettingsSheet` reads this property to conditionally show the 4K option.

**Why `isMultiCamSupported` is the right filter:** Apple limits the formats allowed in `AVCaptureMultiCamSession` to those that can operate simultaneously within ISP bandwidth. A 4K format with `isMultiCamSupported == true` is explicitly approved by the system for dual-camera use. Do NOT use `AVCaptureSessionPreset3840x2160` — presets are unsupported by `AVCaptureMultiCamSession`. Enumerate formats directly.

**Hardware expectation:** On A12 (iPhone XR), 4K formats on the back camera are unlikely to have `isMultiCamSupported == true` — ISP bandwidth at A12 generation was the constraint that capped MultiCam at 1080p per WWDC 2019 documentation. On iPhone Pro models with A15+ and higher ISP bandwidth, 4K MultiCam formats are more likely to be available (Apple's own Dual Capture feature on iPhone 17 supports 4K at 30fps). The detection function must always be run at runtime — never hardcode by device model.

**Confidence:** MEDIUM — the API pattern is HIGH confidence (this is exactly the right API), but actual `isMultiCamSupported == true` availability at 3840px on specific hardware (A15 vs A16 vs A17) can only be confirmed by running on physical device. The test device (iPhone 17 Pro Max) is highly likely to have 4K MultiCam formats available. iPhone XR will likely return `false` and 4K will correctly not appear in the UI.

### Asymmetric Resolution: 4K Back + 1080p Front

Run the back camera at 4K (`landscapeWidth: 3840`) and the front camera at 1080p (`landscapeWidth: 1920`). The compositor scales the 1080p front PiP into the 4K output frame — this is already what the compositor does at every resolution, the only change is the output buffer dimensions.

**Why not 4K on both cameras:** The ISP bandwidth for two simultaneous 4K streams would exceed `hardwareCost == 1.0` on all current devices. Apple's own Dual Capture uses this asymmetric approach. The front camera PiP occupies ~28% of the output width; the visual quality difference between a 1080p-sourced PiP and a 4K-sourced PiP at that size is imperceptible.

**Implementation:** `CameraManager.applyResolutionFormat(resolution:)` already iterates inputs and calls `applyFormat(to:targetLandscapeWidth:)` on each. For 4K, pass `landscapeWidth: 3840` to the back camera and `landscapeWidth: 1920` to the front camera. This requires splitting the single `resolution.landscapeWidth` call into per-camera resolution logic, or defining front camera as always capped at 1080p regardless of selected resolution.

**Recommended approach:** Add a `frontCameraLandscapeWidth` computed property to `OutputResolution` that caps at 1920 for 4K:

```swift
var frontCameraLandscapeWidth: Int {
    switch self {
    case .uhd4K: return 1920   // front stays at 1080p regardless
    default:     return landscapeWidth
    }
}
```

### Codec Selection: HEVC for 4K, H.264 for ≤1080p

**Decision: Use HEVC (`AVVideoCodecType.hevc`) for 4K output only. Keep H.264 for 720p and 1080p.**

**Why HEVC at 4K:**
- H.264 at 4K30 requires 80–100Mbps for adequate quality. At that bitrate the encoder may not sustain real-time output on A12/A13.
- HEVC at 4K30 achieves equivalent visual quality at 40–60Mbps. Apple's native Camera app targets ~45Mbps for 4K30 HEVC.
- HEVC hardware encode is available on A9 and later (all devices supported by iOS 18.0+).
- `AVCaptureVideoDataOutput.availableVideoCodecTypesForAssetWriter(writingTo: .mov)` will include `.hevc` on all A9+ devices. Verify at runtime before using.

**Why keep H.264 for ≤1080p:**
- H.264 is universally compatible. The existing `MovieRecorder` is validated with H.264. Changing 1080p to HEVC offers no user benefit for this use case and adds unnecessary risk.
- Files saved to Photos play equally well in H.264 or HEVC on any current iPhone.

**Codec selection in `MovieRecorder.startRecording(settings:)`:**

```swift
let codec: AVVideoCodecType = (settings.resolution == .uhd4K) ? .hevc : .h264
```

### Bitrate for HEVC 4K

**Do not hardcode a bitrate.** Use the Apple-recommended API to get codec-appropriate settings:

```swift
// On backVideoOutput (AVCaptureVideoDataOutput):
let recommendedSettings = backVideoOutput.recommendedVideoSettings(
    forVideoCodecType: .hevc,
    assetWriterOutputFileType: .mov
)
```

This method (`recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType:)`, iOS 11+) returns a dictionary calibrated for the device's current active format and codec capabilities. Pass it directly (or after overriding only the width/height keys) to `AVAssetWriterInput(mediaType: .video, outputSettings: recommendedSettings)`.

**Why this API over hardcoded bitrate:**
- Returns hardware-optimized settings for the specific A-series chip and camera format.
- Automatically sets profile level (`Main` vs `Main10`), keyframe interval, and bitrate appropriate for the active format.
- Bitrate will scale correctly as Apple updates the recommended encoding parameters in future OS releases.

**If `recommendedVideoSettings` is not viable** (e.g., called outside the capture pipeline where `backVideoOutput` may not be configured yet): use `AVVideoAverageBitRateKey: 45_000_000` (45 Mbps) as a fallback for 4K30 HEVC. This matches Apple's native Camera app target.

**Confidence:** HIGH for the API recommendation (Apple's own documentation and WWDC guidance); MEDIUM for the 45Mbps fallback value (derived from native Camera app behavior, not a published Apple specification).

### PiPCompositor Output Buffer at 4K

The existing `PiPCompositor` uses `nonisolated(unsafe) var outputWidth: Int` and `outputHeight: Int`. Setting these to `2160` and `3840` (portrait dimensions) before recording starts is all that is needed to make the compositor produce 4K output buffers.

**Memory implication:** A single `kCVPixelFormatType_32BGRA` buffer at 3840×2160 = 3840 × 2160 × 4 bytes ≈ 33MB. The `AVAssetWriterInputPixelBufferAdaptor` pixel buffer pool holds several buffers (typically 3–5). Total pool memory at 4K: ~100–165MB. On A12 this may cause memory pressure; on A15+ it is manageable. The pool is created by `AVAssetWriterInput`/`AVAssetWriterInputPixelBufferAdaptor` automatically — no pool size change is needed in code, but this is a factor in the hardwareCost/memory constraint on older supported hardware.

**CIContext performance at 4K:** Core Image renders 4× more pixels per frame at 4K vs 1080p. The existing Metal-backed `CIContext` (created once on init) scales well with resolution — Metal handles larger textures efficiently. At 30fps and A12, the 33ms frame budget may be tight with 4K rendering. Monitoring via Instruments on-device is required. The existing `alwaysDiscardsLateVideoFrames = true` on `AVCaptureVideoDataOutput` provides a safety valve.

**No CIContext changes needed:** The existing `CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB(), .useSoftwareRenderer: false])` is correct at any resolution.

### `OutputResolution` Enum Addition

```swift
case uhd4K = "4K"

var width: Int {
    case .uhd4K: return 2160   // portrait short side
}

var height: Int {
    case .uhd4K: return 3840   // portrait long side
}

var landscapeWidth: Int {
    case .uhd4K: return 3840   // camera sensor landscape
}

var frontCameraLandscapeWidth: Int {
    case .uhd4K: return 1920   // cap front camera at 1080p
    default:     return landscapeWidth
}
```

### No New Frameworks

All APIs required for 4K are already in the existing imports: `AVFoundation`, `CoreImage`, `CoreVideo`. No new framework dependencies.

### What NOT to Add for 4K

| Candidate | Why Not |
|-----------|---------|
| ProRes codec (`AVVideoCodecType.proRes4444` etc.) | ProRes is not supported by `AVAssetWriter` for live capture on all devices; requires specific hardware. Unnecessary for personal-use output. |
| 4K on front camera simultaneously | ISP bandwidth ceiling — would push `hardwareCost` beyond 1.0. Front PiP at 1080p scaled to 4K output is visually equivalent. |
| Separate 4K detection on front camera | Front camera 4K is explicitly not used; detecting it is noise. |
| `AVCaptureSessionPreset3840x2160` | Presets are unsupported by `AVCaptureMultiCamSession`. Always enumerate formats directly. |
| Separate `AVCaptureSession` for 4K recording | Defeats the purpose of `AVCaptureMultiCamSession`; cannot composite two sessions. |
| Metal compute shader replacement of CIContext | Premature optimization. Profile first. Core Image on Metal is adequate; a rewrite adds complexity with uncertain benefit. |
| HDR / Dolby Vision output | Different concern from resolution; no user request; significant complexity. Out of scope for v1.1. |

---

## Recommended Stack (v1 base — unchanged)

| Layer | Choice | Rationale | Confidence |
|-------|--------|-----------|------------|
| Capture session | `AVCaptureMultiCamSession` | Only session type that runs front + back cameras simultaneously; standard `AVCaptureSession` cannot | HIGH |
| Video output | `AVCaptureVideoDataOutput` (x2) | Delivers raw `CVPixelBuffer` frames needed for compositor; one per camera | HIGH |
| Audio output | `AVCaptureAudioDataOutput` (x2) | Required for per-beam audio; MultiCam session exposes separate front/back mic ports on a single device input | HIGH |
| Video compositor | Core Image (`CISourceOverCompositing`, `CILanczosScaleTransform`) via Metal-backed `CIContext` | Validated in phases 01–05; adequate at 1080p; scales to 4K with same code | HIGH |
| Pixel buffer bridge | `CVPixelBufferPool` from `AVAssetWriterInputPixelBufferAdaptor` | Zero-alloc per-frame path; pool created automatically by adaptor | HIGH |
| File writer | `AVAssetWriter` + `AVAssetWriterInput` + `AVAssetWriterInputPixelBufferAdaptor` | Only path that accepts pre-composited pixel buffers | HIGH |
| Output codec (≤1080p) | H.264 (`AVVideoCodecType.h264`) + MPEG-4 AAC | Compatible with Photos app, iPhone XR, validated in v1 | HIGH |
| Output codec (4K) | HEVC (`AVVideoCodecType.hevc`) + MPEG-4 AAC | Required for practical 4K bitrate; hardware encode on all A9+ devices | HIGH |
| Preview layers | `AVCaptureVideoPreviewLayer` (x2) | One per camera; unchanged | HIGH |
| SwiftUI bridge | `UIViewRepresentable` wrapping `UIView` hosting `AVCaptureVideoPreviewLayer` | Unchanged | HIGH |
| Session orchestration | `CameraManager` (`@Observable`) | Adds `supports4K: Bool` observable property | HIGH |
| Permissions | `AVCaptureDevice.requestAccess` + `PHPhotoLibrary.requestAuthorization` | Unchanged | HIGH |
| Save to Photos | `PHPhotoLibrary.performChanges` + `PHAssetChangeRequest.creationRequestForAssetFromVideo` | Unchanged | HIGH |
| Minimum deployment | iOS 18.0 | Unchanged | HIGH |
| Hardware gate | `AVCaptureMultiCamSession.isMultiCamSupported` (session-level) + `AVCaptureDeviceFormat.isMultiCamSupported` (format-level for 4K) | Both checks required | HIGH |

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
  AVAssetWriterInput (video, H.264/HEVC, resolution-dependent)
  AVAssetWriterInputPixelBufferAdaptor
    → append(compositePixelBuffer, withPresentationTime: backFrameTime)
  AVAssetWriterInput (audio, AAC)
    → append(audioSampleBuffer)
```

**Synchronization:** Back-camera frame callback drives the composite. It reads the most recently cached front-camera buffer (`currentPiPSampleBuffer`). This is the same pattern used in Apple's sample. The two cameras are not guaranteed to be frame-synchronous; caching the latest PiP frame and using the back-camera timestamp for the output file is the correct approach.

**Output pixel buffer pool:** `AVAssetWriterInputPixelBufferAdaptor` creates and manages a `CVPixelBufferPool`; use `pixelBufferPool` property to obtain pre-allocated output buffers — do not create buffers per-frame.

**Metal vs. Core Image:** The existing app uses Core Image (not Metal shaders) for compositing, which is a validated working implementation. At 4K the Core Image path renders 4× more pixels per frame; on A15+ this remains within the 33ms budget. On A12 (iPhone XR), 4K MultiCam formats are unlikely to have `isMultiCamSupported == true`, so this device will not exercise 4K compositing in practice. If 4K performance proves inadequate on A15-class hardware after profiling, replacing Core Image compositing with Metal compute is the correct escalation path.

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
- [recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType:) — Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/2867900-recommendedvideosettings)
- [isMultiCamSupported (format) — Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/ismulticamsupported)
- [hevc — AVVideoCodecType — Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avvideocodectype/2875385-hevc)
- [Working with HEIF and HEVC — WWDC17 Session 511 transcript](https://asciiwwdc.com/2017/sessions/511)
- [WWDC19 Session 249 transcript — ASCIIwwdc](https://asciiwwdc.com/2019/sessions/249)
- [iOS 18 & 17 new Camera APIs — YLabZ / Medium](https://zoewave.medium.com/ios-18-17-new-camera-apis-645f7a1e54e8)
- [iPhone 17 Dual Capture — MacRumors](https://www.macrumors.com/how-to/iphone-17-dual-capture-video/)
