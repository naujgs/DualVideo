# Feature Landscape — v1.1: 4K Resolution Support

**Domain:** Hardware-gated resolution selection in an iOS dual-camera recording app
**Researched:** 2026-05-19
**Milestone:** v1.1 (adds to existing QualitySettingsSheet / VideoQualitySettings infrastructure)
**Confidence:** HIGH for AVFoundation constraints (WWDC 2019 + Apple Docs); MEDIUM for UX conventions (no authoritative source; derived from Apple native camera app patterns and HIG principles)

---

## Critical Domain Finding

**4K in AVCaptureMultiCamSession is not guaranteed to be `isMultiCamSupported`.** Apple deliberately limits formats available to `AVCaptureMultiCamSession` to "ones that can comfortably run simultaneously on end devices" (WWDC 2019 Session 249). As of that session, the documented ceiling was 1920×1440. More recent hardware (A15+, iPhone 14 Pro+) may expose 4K formats with `isMultiCamSupported = true`, but this is device-specific and cannot be assumed.

Consequence: the 4K option must be discovered at runtime by querying `backDevice.formats` for a format where `dims.width == 3840 && isMultiCamSupported == true`. On iPhone XR (the minimum test device, A12), 4K is likely **unavailable in multicam mode** — the option must be hidden or permanently disabled for that device. On iPhone 17 Pro Max (the secondary device, A18 Pro), 4K multicam is confirmed by MacRumors/FiLMiC DoubleTake marketing.

The feature must be truly runtime-gated, not assumed from chip generation.

---

## Table Stakes

Features users expect once any 4K option exists in the quality panel. These are not optional — they define baseline quality.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| 4K appears only if hardware supports it | If 4K is offered but fails at recording time, the app is broken. Users cannot tolerate silent format fallbacks | Low | Query `backDevice.formats` for `width == 3840 && isMultiCamSupported == true` before exposing option |
| Storage size indicator next to 4K label | 4K HEVC at 30fps is ~400–450 MB/min; at 60fps ~400 MB/min. Users making storage decisions need this cue. Apple's native Camera Settings shows "High Efficiency" / "Most Compatible" with storage impact labels | Low | Static label: e.g. "~400 MB/min" beneath or beside the 4K segment |
| 4K seamlessly integrated into existing segmented picker | QualitySettingsSheet already has a segmented Picker for `OutputResolution.allCases`. The 4K case must slot in with no visual seam | Low | Add `.uhd4K` to `OutputResolution` enum; the picker renders it automatically |
| Resolution saved/restored correctly across sessions | `VideoQualitySettings.load()` already round-trips via UserDefaults. The `.uhd4K` raw value must survive an app restart | Low | Codable conformance handles this if raw value is stable ("4K") |
| `applyFormat` picks correct 4K format | `CameraManager.applyFormat(to:targetLandscapeWidth:)` already filters for `isMultiCamSupported`. Passing `landscapeWidth: 3840` must match a real format on the device | Low | Add `landscapeWidth = 3840` to `OutputResolution.uhd4K`; no logic change needed in `applyFormat` |
| Graceful degradation if 4K format missing | If a saved "4K" setting is loaded on a device that doesn't support it, the app must fall back to 1080p silently (no crash, no error state) | Low | On session start, if `supports4K == false && qualitySettings.resolution == .uhd4K`, reset to `.hd1080p` |

---

## Differentiators

Features that go beyond the functional floor. Not expected, but add real value and distinguish the quality panel.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Live storage estimate while sheet is open | Show remaining-space estimate for the selected resolution at current settings: "At 4K 30fps, ~12 min recording remaining (5.1 GB free)". No iOS camera app does this natively | Medium | `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` on session start; update estimate when resolution changes |
| Per-resolution storage impact comparison | Inline footnote comparing selected resolution to others: "4K uses ~7× more storage than 720p". Helps users understand the tradeoff at decision time | Low | Static copy based on known ratios; no dynamic calculation needed |
| Notification when selected 4K + low storage | If the user selects 4K and free storage < 1 GB, warn before they start recording. Apple's native Camera app does a similar warning but only at recording time | Medium | Check available storage in `RecordingManager.startRecording()`; surface via existing `sessionError` / toast mechanism |

---

## Anti-Features

Explicitly do not build these for v1.1.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Greyed-out 4K segment on unsupported devices | SwiftUI segmented pickers cannot disable individual segments without custom implementation. A greyed segment implies "maybe later" — but 4K in multicam may never be available on that hardware. A greyed option creates friction and false hope | Hide 4K entirely when not supported. The picker shows only 720p and 1080p, identical to v1.0 behavior |
| `supportsSessionPreset(.hd4K3840x2160)` as detection method | `sessionPreset` checks do not account for `isMultiCamSupported`. A device may support 4K in single-cam but not multicam. Using preset check could expose 4K, which then silently fails or pushes `hardwareCost >= 0.9` at session start | Use format-level detection: iterate `backDevice.formats`, filter `dims.width == 3840 && format.isMultiCamSupported` |
| 4K on the front camera | The PiP front-camera overlay is small (25–30% of screen width). A 3840-wide capture for a PiP overlay is waste; the compositied PiP output is only 3840 wide total. Apply 4K only to the back (background) camera; keep front at 1080p | `applyFormat` on front device: always cap at `landscapeWidth: 1920` when output resolution is 4K |
| ProRes or LOG output at 4K | Not accessible via AVAssetWriter without an iPhone 13 Pro+ hardware encoder and specific entitlements. Entirely out of scope for a personal sideload | HEVC (H.265) only via existing `AVAssetWriter` pipeline |
| Dynamic bitrate control | The existing `VideoQualitySettings` model has no bitrate field; the current `MovieRecorder`/`PiPCompositor` derives bitrate from resolution. Adding manual bitrate to a 4K flow doubles the settings surface area | Use a fixed target bitrate for 4K (e.g. 60–80 Mbps HEVC); no picker needed |
| "4K not available on this device" placeholder row | Shows users a feature they can never have. Better to say nothing | Omit; the 720p / 1080p picker is the complete UI on unsupported hardware |

---

## UX Pattern: Conditional Offering (Hardware-Gated)

**Recommendation: hide, do not disable.**

Apple's own HIG guidance on disabled controls (from button state documentation) is: "disable a control when its action is temporarily unavailable and the control communicates information the person might need." The word "temporarily" is key — 4K in multicam on an iPhone XR will never be available. It is not a temporary condition. Permanent unavailability justifies hiding over disabling.

Observed behavior in Apple-first-party apps:
- iOS Camera Settings hides format options entirely on unsupported models (e.g., ProRes does not appear on non-Pro models at all — not greyed, not shown)
- Apple's Cinematic mode, Action mode, ProRes are all hidden-when-unsupported in the native app, never shown-and-disabled

Community convention in third-party camera apps:
- Halide Mark II hides RAW toggle on iPhone models where RAW is unsupported
- FiLMiC DoubleTake limits quality preset UI to the formats the detected hardware can deliver

**Implementation for QualitySettingsSheet:**
- `AppState` holds a `Bool supports4K` computed once at session startup
- `QualitySettingsSheet` receives `supports4K: Bool` as a parameter
- `ForEach(filteredResolutions)` where `filteredResolutions` excludes `.uhd4K` when `!supports4K`
- Sheet `presentationDetents` may need to grow from `.height(260)` to `.height(300)` to accommodate a 3-segment picker without crowding

---

## Storage Warning UX Convention

**What users expect:**

| Scenario | Expected UX |
|----------|-------------|
| User selects 4K in quality panel | Static storage impact note near the picker ("~400 MB/min at 30fps") |
| User starts recording in 4K with <1 GB free | Alert before recording starts, not mid-recording (silent disk-full mid-recording produces a corrupt or empty file) |
| User is mid-recording in 4K and disk fills | OS terminates write; app must catch `AVAssetWriter.status == .failed` and surface an error (already handled by existing MovieRecorder error path) |

**File size reference (HEVC, not ProRes):**

| Resolution | 30fps | 60fps |
|------------|-------|-------|
| 720p | ~60 MB/min | ~90 MB/min |
| 1080p | ~130 MB/min | ~200 MB/min |
| 4K | ~400 MB/min | ~400–750 MB/min |

Note: 4K at 60fps bitrate variation is wide (400–750 MB/min) depending on Apple's HEVC encoder efficiency and scene complexity. Use 400 MB/min as a conservative/safe estimate for any storage warning copy.

---

## Feature Dependencies (v1.1 delta)

The v1.1 additions are narrow. All depend on the existing `QualitySettingsSheet` / `VideoQualitySettings` / `CameraManager.applyFormat` chain that is already built and validated.

```
[Existing] VideoQualitySettings.OutputResolution enum
    └── Add .uhd4K case (landscapeWidth: 3840, portrait: 2160×3840)

[Existing] CameraManager.applyFormat(to:targetLandscapeWidth:)
    └── No logic change; 3840 width query works via existing isMultiCamSupported filter
    └── [NEW] Detection step: query backDevice.formats for 3840-wide isMultiCamSupported format
        └── [NEW] AppState.supports4K: Bool (published once at session startup)
            └── [NEW] QualitySettingsSheet(supports4K:) — conditional ForEach
                └── [NEW] Storage hint label below Resolution picker

[Existing] VideoQualitySettings.load() / save()
    └── No change; Codable round-trips new .uhd4K raw value automatically

[Existing] PiPCompositor / MovieRecorder
    └── Must configure AVAssetWriter output at 3840×2160 when resolution == .uhd4K
    └── Front camera: capped at 1920-wide format regardless of selected resolution

[Existing] RecordingManager.startRecording()
    └── [OPTIONAL] Low-storage guard: check available bytes before starting 4K recording
```

**Critical path for v1.1:** `OutputResolution.uhd4K` enum case → detection (`supports4K`) → conditional picker → `applyFormat(3840)` → compositor at 3840×2160 output.

The only genuinely new surface area is the capability detection (`supports4K`) and how it propagates to the sheet. Everything else is parameter changes to existing code.

---

## MVP Recommendation for v1.1

Build in this order:

1. **`OutputResolution.uhd4K`** — add enum case, `width/height/landscapeWidth` properties. Codable for free.
2. **Capability detection** — query `backDevice.formats` at session start; publish `supports4K: Bool` on `CameraManager` or `AppState`.
3. **QualitySettingsSheet conditional picker** — pass `supports4K`; hide 4K segment when false. Add static storage hint ("~400 MB/min") below the resolution picker.
4. **Compositor + recorder at 4K** — `PiPCompositor` output frame at 3840×2160; `MovieRecorder` `AVAssetWriter` output settings at 3840×2160.
5. **Front camera cap** — ensure `applyFormat` on the front device never attempts 3840-wide; hard-cap at 1920.

Defer: live storage-remaining estimate, low-storage pre-recording warning (valuable but not blocking; existing `MovieRecorder` error path already handles disk-full at write time).

---

## Sources

- [WWDC 2019 Session 249: Introducing Multi-Camera Capture for iOS — ASCII WWDC](https://asciiwwdc.com/2019/sessions/249) — authoritative on multicam format constraints and hardware cost model
- [AVCaptureDevice.Format.isMultiCamSupported — Apple Developer Docs](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/ismulticamsupported) — per-format multicam support flag
- [AVCaptureMultiCamSession — Apple Developer Docs](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession) — session-level isMultiCamSupported
- [How to check if an iOS camera supports 4K capture — GitHub Gist simonkim](https://gist.github.com/simonkim/4c7a20fb978c9dfc350b6bb4c1512332) — `supportsSessionPreset(.hd4K3840x2160)` pattern (note: this is single-cam; multicam requires format-level check)
- [iPhone Video Size per Minute — VideoProc](https://www.videoproc.com/iphone-video-processing/iphone-video-size-per-minute.htm) — HEVC storage reference (170 MB/min 4K 30fps; 400 MB/min 4K 60fps)
- [About Apple ProRes on iPhone — Apple Support](https://support.apple.com/en-us/109041) — confirms hide-when-unsupported pattern for hardware-gated formats in native Camera app
- [iPhone 17 Dual Capture 4K — MacRumors Forums](https://forums.macrumors.com/threads/iphone-17-using-the-new-dual-capture-video-feature.2466908/page-2) — confirms 4K 60fps dual-cam is available on A18 Pro (iPhone 17 Pro); cross-validates that newer silicon unlocks higher multicam formats
