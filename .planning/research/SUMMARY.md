# Research Summary — DualVideo v1.1: 4K Resolution Support

**Project:** DualVideo
**Domain:** iOS dual-camera capture / AVFoundation pipeline extension
**Researched:** 2026-05-19
**Confidence:** HIGH (stack/architecture — code read directly + Apple docs); MEDIUM (hardware behavior at 4K in MultiCam — requires device validation)

---

## Executive Summary

DualVideo v1.1 adds optional 4K (3840×2160) recording to an existing dual-camera PiP pipeline that is already built and validated at 1080p. The core challenge is not codec or rendering complexity — the existing AVCaptureMultiCamSession + PiPCompositor + AVAssetWriter stack handles 4K without structural redesign. The challenge is hardware gating: `AVCaptureMultiCamSession` imposes a hard ISP bandwidth budget (`hardwareCost <= 1.0`) and Apple does not document which specific device models have a back-camera 4K format with `isMultiCamSupported == true`. 4K in MultiCam mode is effectively a Pro-tier hardware feature. iPhone XR (the minimum test device) will almost certainly show 4K as unavailable; iPhone 17 Pro Max will almost certainly support it. All devices in between require runtime detection.

The recommended approach is narrow and additive: add an `OutputResolution.uhd4K` enum case, implement runtime format detection on `CameraManager` at session startup, gate the UI picker conditionally, and ensure `MovieRecorder`/`PiPCompositor` receive 3840×2160 dimensions when 4K is selected. No new frameworks, no new pipeline stages, no new actors. The codec change to HEVC for 4K output and the asymmetric camera configuration (4K back, 1080p front) are the two meaningful new decisions. Everything else is parameter propagation through an already-working system.

The primary risk is incorrect capability detection. There are two distinct failure modes: (1) showing 4K on a device where `isMultiCamSupported` is false, causing a session stop at `startRunning()` time; (2) showing 4K on a device where a format passes `isMultiCamSupported` but the combined `hardwareCost` with any front camera format still exceeds 1.0. Both must be caught before the 4K option is shown in the UI. A trial configuration at session startup — apply 4K back + lowest-cost front, commit, read `hardwareCost`, revert — is the only reliable mechanism.

---

## Key Findings

### Stack Additions for v1.1

No new frameworks. All required APIs are already in the existing imports (`AVFoundation`, `CoreImage`, `CoreVideo`). The three meaningful additions:

**New APIs in use:**
- `CMVideoFormatDescriptionGetDimensions` + `AVCaptureDeviceFormat.isMultiCamSupported`: format-level 4K capability detection — the only correct API for MultiCam gating (not `supportsSessionPreset`, which checks single-cam capability)
- `AVVideoCodecType.hevc` in `MovieRecorder`: required for practical 4K bitrate (~45 Mbps HEVC vs ~90 Mbps H.264 at equivalent quality for 4K30)
- `AVCaptureVideoDataOutput.recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType:)`: Apple-calibrated HEVC settings; avoids hardcoded bitrate that may be wrong per device/chip

**Critical version note:** `videoRotationAngle` (iOS 17+) must be used instead of deprecated `videoOrientation` — project targets iOS 18.0+ so this is already the right API.

### Feature Table Stakes vs. Differentiators

**Must have (table stakes) — v1.1 ships incomplete without these:**
- 4K option visible only on hardware where a trial session configuration stays under `hardwareCost == 0.95` — hide (not disable) per Apple HIG
- Static storage hint below resolution picker: "~400 MB/min at 30fps" — users selecting 4K need storage context before recording
- Setting persists across restarts via existing `VideoQualitySettings` Codable path (no code change required)
- Graceful fallback: saved 4K setting on non-4K device resets to 1080p silently before session start

**Should have (differentiators) — high value, not blocking:**
- Live storage-remaining estimate in quality sheet at selected resolution
- Low-storage pre-recording warning when free space < 1 GB and 4K is selected

**Defer to v1.2+:**
- Thermal-aware frame rate reduction (reactive `systemPressureCost` monitoring)
- ProRes or LOG output (requires hardware entitlements, out of scope)
- 4K on front camera (ISP bandwidth ceiling — Apple's own Dual Capture uses asymmetric approach)

### Architecture Changes Required

Four components change; three require no modification.

**Components that change:**

1. **`OutputResolution` enum** (`VideoQualitySettings.swift`) — add `.uhd4K` case (`width: 2160`, `height: 3840`, `landscapeWidth: 3840`). Add `frontCameraLandscapeWidth` computed property that returns 1920 for `.uhd4K` (front camera never gets 4K format — ISP bandwidth ceiling).

2. **`CameraManager`** — add `supports4K: Bool` observable property. Add `detect4KCapability()` called once after `commitConfiguration()`: performs a trial configuration (4K back + lowest-cost front), reads `hardwareCost`, reverts, publishes result on main thread. Also add `hardwareCost > 1.0` revert guard inside `applyResolutionFormat` — existing code only logs at >= 0.9 but does not revert.

3. **`QualitySettingsSheet`** — add `supports4K: Bool` parameter. Filter `OutputResolution.allCases` to exclude `.uhd4K` when `supports4K == false`. Add storage hint label below resolution picker. Sheet height stays at 260pt.

4. **`MovieRecorder`** — codec selection: HEVC when `settings.resolution == .uhd4K`, H.264 otherwise. Use `recommendedVideoSettings(forVideoCodecType: .hevc, assetWriterOutputFileType: .mov)` as settings base, overriding width/height. `AVAssetWriterInputPixelBufferAdaptor` `sourcePixelBufferAttributes` must specify 3840×2160 — recreate from scratch, not resize.

**Components with no changes:**
- `PiPCompositor` — `outputWidth`/`outputHeight` already set by `RecordingManager.startRecording(settings:)`; compositor is resolution-agnostic
- `RecordingManager` — already passes `settings.resolution.width/height` to compositor and recorder
- `AppState` — reads `cameraManager.supports4K` directly via `@Observable`; no new property needed

### Top Pitfalls to Avoid

1. **4K hardwareCost exceeds 1.0 with front camera (Pitfalls 14, 20)** — Session stops at `startRunning()` with no user error if `hardwareCost >= 1.0`. Fix: trial configuration at startup. Never show 4K based on back-camera format alone; test the combined session cost.

2. **CVPixelBufferPool undersized for 4K (Pitfall 17)** — Existing 1080p pool causes silent 1080p output or `kCVReturnWouldExceedAllocationThreshold` at recording start. Fix: recreate `MovieRecorder` and adaptor with 3840×2160 `sourcePixelBufferAttributes` when resolution changes.

3. **sessionPreset assignment breaks MultiCam format (Pitfall 16)** — `session.sessionPreset = .hd3840x2160` sets `activeFormat` to a format with `isMultiCamSupported == false`. Fix: already avoided in v1.0; must stay avoided — always use `device.activeFormat` assignment directly.

4. **H.264 at 4K causes encoder backpressure (Pitfall 19)** — H.264 at 4K30 requires ~90 Mbps; encoder may not sustain real-time on A12/A13 and files are impractically large. Fix: HEVC for 4K only; derive settings from `recommendedVideoSettings`.

5. **PiP coordinate space not scaled for 4K (Pitfall 22)** — `pipFrame` in 1080p coordinates renders overlay in lower-left quadrant of 4K frame. Fix: `PiPCompositor` must scale `pipFrame` proportionally to output dimensions; assert buffer width matches expected in debug builds.

---

## Implications for Roadmap

The dependency graph is short and clear. Three sequential phases cover the full v1.1 scope.

### Phase 1: Capability Detection + Conditional UI

**Rationale:** Everything downstream depends on knowing whether 4K is viable on the current device. `OutputResolution.uhd4K` must compile before any consumer references it. These are the zero-risk items that unblock all recording work.

**Delivers:** `OutputResolution.uhd4K` enum case; `CameraManager.supports4K` from trial configuration; `QualitySettingsSheet` conditional picker; static storage hint label

**Addresses:** Table-stakes features 1–4 (hardware gating, storage cue, picker integration, persisted setting)

**Avoids:** Pitfalls 14, 15, 16, 20 (all incorrect capability detection paths)

**Research flag:** None — detection pattern is HIGH confidence from Apple docs

---

### Phase 2: 4K Recording Pipeline

**Rationale:** Phase 1 guarantees `applyResolutionFormat(.uhd4K)` only runs on viable devices. Phase 2 wires the recording path to produce actual 4K output.

**Delivers:** HEVC codec selection in `MovieRecorder`; 3840×2160 `AVAssetWriterInputPixelBufferAdaptor` recreation; front camera capped at 1080p in `applyResolutionFormat`; `hardwareCost > 1.0` revert guard; `pipFrame` coordinate scaling verified in `PiPCompositor`

**Avoids:** Pitfalls 17, 18, 19, 22 (pool size, compositor performance, writer settings, coordinate space)

**Research flag:** Requires device validation — `hardwareCost` with 4K back + 1080p front on iPhone 17 Pro Max cannot be confirmed without running on physical hardware. Log `hardwareCost` and format list throughout.

---

### Phase 3: Device Validation

**Rationale:** All 4K behavior is hardware-specific. Simulator is useless. Phase 3 confirms Phase 1 detection correctly predicts recording viability and that performance (frame budget, thermal) is acceptable.

**Delivers:** Confirmed `supports4K == false` on iPhone XR; confirmed `supports4K` value on iPhone 17 Pro Max with `hardwareCost` logged; 5-minute 4K recording with no frame drops or thermal stops; graceful 4K-to-1080p fallback on non-4K device

**Avoids:** Pitfall 21 (thermal `systemPressureCost` management during long recordings)

**Research flag:** If iPhone 17 Pro Max returns `supports4K == false`, the pipeline is untestable until a 4K-capable device is added. Plan contingency: log full `back.formats` list with `isMultiCamSupported` values at session startup to diagnose the exact capability boundary.

---

### Phase Ordering Rationale

- Phase 1 before Phase 2: enum and detection must compile before recording pipeline can reference them; trial config check is also a prerequisite to knowing whether Phase 2 will ever run
- Phase 2 before Phase 3: nothing to validate until the recording path exists; Phase 3 is purely observational
- No phase requires additional framework research — all APIs are HIGH confidence from Apple docs and the v1.0 codebase has already exercised the same interfaces at 1080p

### Research Flags

**Needs device validation before declaring complete:**
- **Phase 2/3:** Whether `back.formats` contains any format with `dims.width == 3840 && isMultiCamSupported == true` on iPhone 17 Pro Max — the single unknown that determines whether the full pipeline is exercisable
- **Phase 3:** `hardwareCost` after applying 4K back + 1080p front on Pro hardware — must stay under 0.95 for the feature to be reliable

**Standard patterns (no additional research needed):**
- Phase 1 — enum extension, detection logic, conditional picker: well-understood SwiftUI + AVFoundation patterns
- All phases — HEVC codec, `recommendedVideoSettings`, adaptor recreation: fully documented Apple APIs

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | No new frameworks; HEVC and `recommendedVideoSettings` are Apple-documented; H.264 path is validated in v1.0 |
| Features | HIGH | Table stakes derived from Apple HIG and first-party app behavior; storage estimates from measured HEVC output data |
| Architecture | HIGH | Component change list from direct code read of all five source files; three of five components need zero changes |
| Pitfalls | MEDIUM | 4K-specific pitfalls are well-reasoned from WWDC 2019 and `hardwareCost` semantics; actual values at 4K on A15–A18 are unverified without a public compatibility matrix post-2019 |

**Overall confidence:** HIGH for implementation approach; MEDIUM for hardware outcome on specific devices

### Gaps to Address

- **4K MultiCam availability on Pro hardware (A15–A18):** Log `back.formats` with `isMultiCamSupported` at session startup in Phase 1 development before writing any Phase 2 code. If iPhone 17 Pro Max returns `supports4K == false`, escalate test device requirements.
- **`hardwareCost` value at 4K back + 1080p front:** Architecture notes a degradation ladder (4K+720p front, then 4K+480p front, then 4K back-only). Actual cost thresholds per device are unknown until measured. Phase 3 validation step must capture these values.
- **CIContext performance at 4K on A15:** Expected to stay within 33ms frame budget on Metal, but this is projection from 1080p behavior. Instruments profiling in Phase 3 is the validation step.

---

## Sources

### Primary (HIGH confidence)
- [AVCaptureMultiCamSession — Apple Developer Docs](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession) — `hardwareCost`, `systemPressureCost`, `isMultiCamSupported`
- [AVCaptureDevice.Format.isMultiCamSupported — Apple Developer Docs](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/ismulticamsupported)
- [recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType:) — Apple Developer Docs](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/2867900-recommendedvideosettings)
- [AVMultiCamPiP Apple sample code](https://developer.apple.com/documentation/AVFoundation/avmulticampip-capturing-from-multiple-cameras)
- [WWDC 2019 Session 249 — Introducing Multi-Camera Capture for iOS](https://asciiwwdc.com/2019/sessions/249) — hardware cost model, ISP bandwidth limits, format constraints

### Secondary (MEDIUM confidence)
- [iPhone 17 Dual Capture 4K — MacRumors Forums](https://forums.macrumors.com/threads/iphone-17-using-the-new-dual-capture-video-feature.2466908/) — confirms 4K MultiCam viability on A18 Pro
- [About Apple ProRes on iPhone — Apple Support](https://support.apple.com/en-us/109041) — hide-when-unsupported pattern for hardware-gated features
- [iPhone Video Size per Minute — VideoProc](https://www.videoproc.com/iphone-video-processing/iphone-video-size-per-minute.htm) — HEVC storage reference (~400 MB/min at 4K30)
- [WWDC 2020 Session 10008 — Optimize the Core Image Pipeline for Your Video App](https://developer.apple.com/videos/play/wwdc2020/10008/) — CIContext singleton, `cacheIntermediates: false` for video

---
*Research completed: 2026-05-19*
*Ready for roadmap: yes*
