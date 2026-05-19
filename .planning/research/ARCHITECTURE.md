# Architecture Research — 4K Integration (v1.1)

**Researched:** 2026-05-19
**Milestone:** v1.1 — 4K Resolution Support
**Confidence:** HIGH for component mapping (code read directly). MEDIUM for hardware cost specifics (Apple docs + WWDC 2019; device-specific 4K MultiCam availability has not changed materially per available public documentation through 2025).

---

## Scope

This document answers four specific questions about integrating 4K into the existing dual-camera pipeline:

1. Which components need to change for 4K?
2. Where does 4K capability detection live?
3. How does the `applyResolutionFormat` flow need to extend?
4. What AVCaptureMultiCamSession hardware cost constraints limit 4K + front camera simultaneous capture?

---

## Existing Architecture (as-built, v1.0)

Data flows in a straight line:

```
AVCaptureMultiCamSession
  └─ back camera → AVCaptureVideoDataOutput (backVideoOutput)
  └─ front camera → AVCaptureVideoDataOutput (frontVideoOutput)
        ↓ both delegate to PiPCompositor (dataOutputQueue)
PiPCompositor.captureOutput(...)
  └─ on back-camera frame: composite(back:front:pipRect:) → CVPixelBuffer
  └─ calls onComposited(pixelBuffer, pts)
        ↓
RecordingManager.wireCompositor closure
  └─ recorder.appendVideoBuffer(pixelBuffer, pts:)
        ↓
MovieRecorder (AVAssetWriter + AVAssetWriterInputPixelBufferAdaptor)
  └─ H.264, pool sized to settings.resolution.width × settings.resolution.height
```

Resolution propagates via `VideoQualitySettings.resolution` (an `OutputResolution` enum). At recording start, `RecordingManager.startRecording(settings:)` sets `compositor.outputWidth/Height` and then calls `recorder.startRecording(settings:)`. The `AVAssetWriterInputPixelBufferAdaptor` pool is created synchronously inside `recorder.startRecording`, then bridged back to `compositor.pixelBufferPool`.

Format selection on the device is handled by `CameraManager.applyResolutionFormat(resolution:)`, which calls the private `applyFormat(to:targetLandscapeWidth:)` helper. That helper filters `device.formats` by `isMultiCamSupported && dims.width == landscapeWidth`.

---

## Components That Need to Change

### 1. `OutputResolution` (VideoQualitySettings.swift) — MODIFIED

**Change:** Add a `.uhd4K` case.

```swift
enum OutputResolution: String, Codable, CaseIterable, Sendable {
    case hd720p  = "720p"
    case hd1080p = "1080p"
    case uhd4K   = "4K"          // NEW

    var width: Int {
        switch self {
        case .hd720p:  return 720
        case .hd1080p: return 1080
        case .uhd4K:   return 2160   // portrait short side
        }
    }

    var height: Int {
        switch self {
        case .hd720p:  return 1280
        case .hd1080p: return 1920
        case .uhd4K:   return 3840   // portrait long side
        }
    }

    var landscapeWidth: Int {
        switch self {
        case .hd720p:  return 1280
        case .hd1080p: return 1920
        case .uhd4K:   return 3840   // landscape sensor width
        }
    }
}
```

No other changes to the type are required. `VideoQualitySettings` is a `Codable` struct — adding a new enum case with a distinct raw value is backward-compatible; old persisted JSON without `"4K"` simply decodes to the default `.hd1080p`.

`FrameRatePreset` does not change. 4K will be limited by hardware to 30 fps in MultiCam contexts (see hardware cost section below); the existing `.fps30` case covers this.

---

### 2. `CameraManager` — MODIFIED (capability detection + format selection)

**New stored property:** `var supports4K: Bool = false` (observable, main-thread readable)

**New private method:** `detect4KCapability()` — queries the back camera's format list on `sessionQueue` immediately after `commitConfiguration()` in `configureAndStart()`. Sets `supports4K` on main thread.

**Detection logic:**

```swift
private func detect4KCapability() {
    // Must run on sessionQueue, after commitConfiguration().
    // A format is considered "4K-capable for MultiCam" only if:
    //   - dims.width == 3840
    //   - isMultiCamSupported == true
    // Absence of such a format means 4K cannot be used without busting hardwareCost.
    guard let back = backDevice else { return }
    let has4K = back.formats.contains { fmt in
        let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        return Int(dims.width) == 3840 && fmt.isMultiCamSupported
    }
    DispatchQueue.main.async { [weak self] in
        self?.supports4K = has4K
        logger.info("CameraManager: 4K MultiCam support detected=\(has4K)")
    }
}
```

This is called once, inside `configureAndStart()`, right after the existing `commitConfiguration()` + `hardwareCost` check. No session restart needed.

**`applyResolutionFormat` — no logic change required.** The existing `applyFormat(to:targetLandscapeWidth:)` already:
- Filters by `isMultiCamSupported`
- Logs a warning and keeps the current format if no matching format is found

Passing `landscapeWidth: 3840` will correctly select a 4K MultiCam-supported format if one exists, or silently fall back to the current format if not. The caller (`applyResolutionFormat`) already logs `hardwareCost` after `commitConfiguration()` and warns if cost >= 0.9. That warning is the correct behavior for 4K on constrained hardware — no new error handling is needed here.

**New: post-format-change hardwareCost guard.** The existing code logs a warning at >= 0.9 but does not revert the format. For 4K, a cost > 1.0 would crash the session. Add a revert path:

```swift
// Inside applyResolutionFormat, after commitConfiguration():
let cost = session.hardwareCost
logger.info("CameraManager: after 4K format apply, hardwareCost=\(cost)")
if cost > 1.0 {
    logger.error("CameraManager: hardwareCost \(cost) > 1.0 — reverting to 1080p")
    session.beginConfiguration()
    if let back = backDevice {
        applyFormat(to: back, targetLandscapeWidth: 1920)
    }
    // front camera revert...
    session.commitConfiguration()
}
```

---

### 3. `AppState` — MODIFIED (expose `supports4K`)

`AppState` holds `cameraManager: CameraManager`. The UI needs to read `cameraManager.supports4K` to conditionally show the 4K option. No structural change is needed — `AppState` does not need a new property; the view reads `appState.cameraManager.supports4K` directly. However, `CameraManager` must be `@Observable` on `supports4K` (it already uses `@Observable` macro), so this is automatic.

---

### 4. `QualitySettingsSheet` — MODIFIED (conditional 4K display)

**Change:** Filter the resolution picker to only show `.uhd4K` if the device supports it.

```swift
Picker("Resolution", selection: $settings.resolution) {
    ForEach(OutputResolution.allCases.filter { r in
        r != .uhd4K || cameraManager.supports4K
    }, id: \.self) { r in
        Text(r.rawValue).tag(r)
    }
}
```

The sheet needs to receive `cameraManager` (or just `supports4K: Bool`) as a parameter. Currently it takes only `@Binding var settings: VideoQualitySettings`. Add a `let supports4K: Bool` parameter.

**Sheet height:** Adding a third segment to the segmented picker does not overflow the existing `.presentationDetents([.height(260)])` height. No height change needed.

---

### 5. `MovieRecorder` — NO CHANGE REQUIRED

`AVAssetWriterInput` is configured with `AVVideoWidthKey` and `AVVideoHeightKey` from `settings.resolution.width/height`. These are already driven by `VideoQualitySettings`. Adding `.uhd4K` with width=2160, height=3840 flows through without any code change.

The `AVAssetWriterInputPixelBufferAdaptor` pool is also sized from `settings.resolution.width/height`. No change required.

**Codec note:** H.264 at 4K is valid on iOS and supported by `AVAssetWriter`. HEVC (H.265) would produce smaller files at 4K but requires a codec change. For v1.1, H.264 is the correct choice — it keeps the change minimal and avoids a new encoder decision. HEVC can be a future enhancement.

---

### 6. `PiPCompositor` — NO CHANGE REQUIRED

`outputWidth` and `outputHeight` are set by `RecordingManager.startRecording(settings:)` before the pool is created. The compositor's `composite(back:front:pipRect:)` method scales the front camera to `pipRect` using `CGAffineTransform` — this is resolution-independent. The `roundedCornerMask` cache is keyed on `pipWidth`, which scales proportionally with `outputWidth`. No code changes needed.

**Memory note:** A 4K CVPixelBuffer (2160×3840, BGRA) is approximately 33 MB per frame. The pixel buffer pool will hold several such buffers. This is within iOS norms for video capture on A15+ hardware but should be noted as a difference from 1080p (≈8 MB per frame).

---

### 7. `RecordingManager` — NO CHANGE REQUIRED

`startRecording(settings:)` already reads `settings.resolution.width/height` and assigns them to `compositor.outputWidth/Height`. The `settings` parameter is passed through to `recorder.startRecording(settings:)`. Adding `.uhd4K` to `OutputResolution` flows through without any code change.

---

## Data Flow With 4K Added

```
AppState.init()
  └─ cameraManager.compositor = PiPCompositor()

cameraManager.startSession()  →  configureAndStart()  (sessionQueue)
  └─ [existing] addInputs, addOutputs, addConnections, commitConfiguration
  └─ [NEW] detect4KCapability()
       └─ back.formats.contains { dims.width==3840 && isMultiCamSupported }
       └─ main thread: cameraManager.supports4K = true|false

QualitySettingsSheet (conditioned on supports4K)
  └─ user selects .uhd4K
  └─ appState.qualitySettings.resolution = .uhd4K
  └─ onDismiss → appState.qualitySettings.save()
  └─ cameraManager.applyResolutionFormat(resolution: .uhd4K)
       └─ applyFormat(to: back, targetLandscapeWidth: 3840)  — existing filter: isMultiCamSupported
       └─ applyFormat(to: front, targetLandscapeWidth: 3840) — likely falls back (front has no 4K MultiCam)
       └─ commitConfiguration()
       └─ [NEW] hardwareCost > 1.0 guard → revert to 1080p

RecordingManager.startRecording(settings: qualitySettings)
  └─ compositor.outputWidth = 2160, outputHeight = 3840
  └─ recorder.startRecording(settings:)
       └─ AVAssetWriter: AVVideoWidthKey=2160, AVVideoHeightKey=3840, H.264
       └─ AVAssetWriterInputPixelBufferAdaptor: 2160×3840 BGRA pool
  └─ compositor.pixelBufferPool = recorder.adaptor?.pixelBufferPool
```

---

## AVCaptureMultiCamSession Hardware Cost Constraints for 4K

### What Apple Documents (MEDIUM confidence — WWDC 2019 + Apple docs; no device-specific update post-2019 found)

`AVCaptureMultiCamSession.hardwareCost` is a Float in [0.0, 1.0+]. The session refuses to run if cost >= 1.0 after `commitConfiguration`. The ISP bandwidth is the limiting factor, not compute.

Factors that increase hardware cost:
- Video resolution (the dominant factor — 4K is 4× 1080p in pixel count)
- Frame rate
- Number of active outputs
- Binned vs unbinned formats (binned reduces cost at the same resolution)

### 4K + Front Camera: The Critical Constraint

WWDC 2019 Session 249 explicitly listed the MultiCam-supported formats for iPhone XS and XS Max. 4K (3840×2160) was **not among them**. The session stated: "We do not support 12 megapixel on N cameras. That would certainly do bad things to the phone."

The `multiCamSupported` property on `AVCaptureDeviceFormat` is the runtime arbiter. The existing `applyFormat(to:targetLandscapeWidth:)` already filters on `fmt.isMultiCamSupported`. If the back camera has no 4K format with `isMultiCamSupported == true`, the format selection falls back silently and 4K recording is not possible on that device.

**Expected behavior by hardware tier:**

| Device | Back 4K `isMultiCamSupported` | Front 4K `isMultiCamSupported` | Notes |
|--------|-------------------------------|-------------------------------|-------|
| iPhone XR (A12, min target) | Likely false | False | A12 ISP bandwidth insufficient for dual 4K |
| iPhone 11 Pro / 12 Pro (A13–A14) | Possibly false | False | 4K MultiCam not confirmed in public sources |
| iPhone 15 Pro / 17 Pro (A17–A18) | Possibly true | False | Pro SoC ISP may support 4K back in MultiCam — must be validated on device |
| iPhone 17 Pro Max (A18 Pro) | Possibly true | False | Same — device validation required |

**Key implication:** Even if back camera 4K has `isMultiCamSupported = true` on Pro hardware, the front camera will almost certainly not have a 4K MultiCam-supported format. The front camera in the PiP compositor is scaled down to ~28% of output width anyway. Selecting a lower-resolution format for the front (e.g., 1080p) while back is 4K is the expected configuration. The existing `applyFormat` logic already handles this: it silently keeps whatever format it found when the target width is unavailable.

**Recommended approach:** Do not force the front camera to 4K. Apply `landscapeWidth: 3840` to the back camera only. Leave the front camera at its current format (1080p or 720p). The compositor scales the front buffer regardless of source resolution.

This means `applyResolutionFormat` should be modified to only apply the 4K format change to the back camera, while leaving the front camera at its current format when resolution is `.uhd4K`.

---

## Where Capability Detection Lives

**Detection belongs in `CameraManager`.** Rationale:

- `CameraManager` owns `backDevice` and the session. It is the only component that can query `backDevice.formats` after the session is committed.
- `AppState` is the correct place to *expose* the capability to the UI, but it should read it from `CameraManager.supports4K`, not compute it independently.
- `VideoQualitySettings` must not contain detection logic — it is a pure data struct.
- Detection must happen on `sessionQueue` after `commitConfiguration()`. `CameraManager.configureAndStart()` is already that exact location.

**Detection timing:** Once, at session startup. The device's 4K MultiCam capability does not change at runtime. No need for re-detection on format changes.

---

## Build Order

The dependency graph determines build order. Each item must compile before the next item that depends on it.

```
1. OutputResolution (.uhd4K case added)
   — no dependencies other than Foundation

2. CameraManager (supports4K property + detect4KCapability method)
   — depends on OutputResolution (for landscapeWidth: 3840)

3. QualitySettingsSheet (conditional .uhd4K display)
   — depends on OutputResolution (ForEach over allCases) and CameraManager.supports4K
   — the existing Picker already uses OutputResolution.allCases; adding the filter is additive

4. Integration test / manual validation on device
   — verify supports4K is false on iPhone XR
   — verify supports4K is true/false on iPhone 17 Pro Max (determine actual value)
   — verify hardwareCost stays < 1.0 after 4K format selection on supporting hardware
```

No changes to `RecordingManager`, `MovieRecorder`, or `PiPCompositor` are required. The resolution-agnostic design of those components means 4K flows through without modification.

---

## Risks and Open Questions

### Risk 1: 4K `isMultiCamSupported = false` on all current hardware (HIGH probability on XR, LOW probability on Pro)

If no device in the test set has `isMultiCamSupported = true` for 4K back camera formats, the feature cannot be validated end-to-end. The UI correctly hides the 4K option in this case. This is not a bug but limits the feature to unreleased or untested hardware.

**Mitigation:** Test on iPhone 17 Pro Max first. Log `back.formats` with their `isMultiCamSupported` values at session startup during development to get ground truth.

### Risk 2: 4K `isMultiCamSupported = true` but hardwareCost > 1.0 after adding front camera

Some Pro devices may have 4K formats with `isMultiCamSupported = true` individually, but the combined session cost with back 4K + front 1080p + two VideoDataOutputs exceeds 1.0. The new revert guard in `applyResolutionFormat` handles this.

**Mitigation:** Log `hardwareCost` immediately after committing the 4K format. If > 1.0, revert and surface an error via `sessionError` (same pattern as existing `handleError`).

### Risk 3: Front camera left at higher resolution than needed wastes ISP bandwidth

When back camera is configured 4K, the front camera's format is unchanged (left at 1080p by the existing format application from session startup). This consumes additional ISP bandwidth that might push the total cost over the limit.

**Mitigation:** When applying 4K to the back camera, explicitly set the front camera to the lowest MultiCam-supported format that preserves reasonable PiP quality (e.g., 720p or even 480p — the front PiP is only 28% output width, so 720p is more than sufficient). This is an explicit addition to `applyResolutionFormat` for the 4K case only.

### Open Question: Does `systemPressureCost` matter for 4K?

`AVCaptureMultiCamSession.systemPressureCost` tracks thermal/CPU pressure separately from `hardwareCost`. 4K compositing in Core Image on `dataOutputQueue` will increase CPU/GPU utilization. If thermal throttling occurs during long 4K recordings, frame drops will appear in the compositor output. This is a runtime observation question, not an architecture question — no code change addresses it at design time.

---

## Confidence Assessment

| Area | Confidence | Basis |
|------|------------|-------|
| Component change list | HIGH | Direct code read of all five source files |
| Detection placement (CameraManager) | HIGH | Follows existing pattern; only component with `backDevice` access post-session |
| `OutputResolution` extension | HIGH | Additive enum case, existing consumer code is unaffected |
| `applyFormat` flow adequacy | HIGH | Filter already uses `isMultiCamSupported`; 4K just adds a new `landscapeWidth` value |
| 4K `isMultiCamSupported = false` on most hardware | MEDIUM | WWDC 2019 documentation; no public source confirms Pro hardware changed this |
| Front camera should stay at 1080p/720p for 4K back | MEDIUM | Follows ISP bandwidth reasoning from Apple docs; unverified on specific hardware |
| H.264 at 4K via AVAssetWriter | HIGH | Supported on iOS per Apple documentation |
| MovieRecorder / PiPCompositor require no changes | HIGH | Resolution flows through via `settings.resolution.width/height`; code paths are resolution-agnostic |
