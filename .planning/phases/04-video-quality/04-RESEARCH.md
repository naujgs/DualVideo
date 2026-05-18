# Phase 4: Video Quality and Export Options - Research

**Researched:** 2026-05-18
**Domain:** AVFoundation video encoding (resolution/bitrate), post-recording trim (AVAssetExportSession), SwiftUI settings UI, UserDefaults persistence
**Confidence:** MEDIUM-HIGH — core AVFoundation facts verified against Apple docs and forums; architecture impact is ASSUMED from codebase analysis

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VQ-01 | User can select output resolution (720p / 1080p) | Resolution is set in `AVAssetWriterInput` video settings and `PiPCompositor` output dimensions; device format must be changed on `AVCaptureDevice` via `activeFormat` before recording starts |
| VQ-02 | User can select bitrate (low / medium / high) | `AVVideoAverageBitRateKey` inside `AVVideoCompressionPropertiesKey` dictionary in `AVAssetWriterInput` output settings; three named presets map to Mbps values |
| VQ-03 | Video trimming UI before saving to Photos | `AVAssetExportSession` with `timeRange` set to user-selected CMTimeRange; SwiftUI sheet with two-handle range slider + AVPlayer preview |
| VQ-04 | Settings persist across launches | Codable `VideoQualitySettings` struct encoded to `Data` and stored in `UserDefaults` |
</phase_requirements>

---

## Summary

Phase 4 adds two independent user-facing features on top of the existing recording pipeline: (1) configurable output quality (resolution + bitrate), and (2) video trimming before save.

**Quality settings** (VQ-01, VQ-02) require changes at two layers. The `MovieRecorder`'s hardcoded 1080p/10 Mbps `AVAssetWriterInput` settings must become configurable, and the `PiPCompositor`'s hardcoded `outputWidth`/`outputHeight` static constants must become dynamic. The active `AVCaptureDevice` format on both cameras should also be selected to match the target resolution, since `AVCaptureMultiCamSession` does not support `sessionPreset` — format selection must be done per-device via `activeFormat` + `lockForConfiguration`. [VERIFIED: Apple WWDC19-249, Apple Developer Forums thread/134114]

**Trimming** (VQ-03) is a post-recording, pre-save operation. The existing auto-save flow in `RecordingManager.saveRecording()` must be gated behind a trim UI. The standard approach is `AVAssetExportSession` with a `timeRange` — this re-encodes the composited `.mov`, which is a new background export step. The UI is a SwiftUI sheet with a custom range slider (two thumbs representing in/out points) and an `AVPlayer` preview. [VERIFIED: Apple AVAssetExportSession docs, multiple community sources]

**Primary recommendation:** Implement quality settings as a `VideoQualitySettings` struct injected into `MovieRecorder` at `startRecording()` time, and implement trimming as a separate `VideoTrimManager` actor that runs `AVAssetExportSession` before calling `PhotoSaveManager`. Do not change resolution mid-recording — resolution is a pre-recording decision.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AVFoundation | iOS 18+ (system) | `AVAssetWriterInput` compression settings, `AVAssetExportSession` trim, `AVCaptureDevice.activeFormat` | Only API for these operations on iOS |
| AVKit | iOS 18+ (system) | `AVPlayer` + `AVPlayerViewController` for trim preview playback | Native, zero-dependency playback |
| CoreMedia | iOS 18+ (system) | `CMTime`, `CMTimeRange` for trim in/out points | Required by AVFoundation APIs |
| SwiftUI | iOS 18+ (system) | Settings bottom sheet, quality picker, trim UI | Already in use throughout app |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| UserDefaults | system | Persist `VideoQualitySettings` as `Data` | Suitable for lightweight settings structs |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom range-slider SwiftUI view | `PHPickerViewController` / iOS Photos trim UI | iOS Photos trim UI cannot be embedded in-app for in-flight trimming; must build custom |
| `AVAssetExportSession` | `AVAssetReader` + `AVAssetWriter` | Export session is simpler and correct for trimming a finished file; reader+writer gives more control but adds complexity the phase doesn't need |
| `AVVideoCodecType.h264` | `AVVideoCodecType.hevc` | HEVC cuts file size ~50% at same quality but requires explicit HEVC support check; H.264 is simpler and already in use — add HEVC as optional v2 enhancement |

**Installation:** All libraries are system frameworks — no `npm install` or SPM packages required.

---

## Architecture Patterns

### Current Architecture (Phase 3 baseline)

```
AppState
├── CameraManager          (AVCaptureMultiCamSession, sessionQueue, per-device audio/video outputs)
│   └── PiPCompositor      (Metal CIContext, fixed 1080×1920, onComposited callback)
└── RecordingManager       (coordinates composite → recorder → save)
    ├── MovieRecorder      (AVAssetWriter, hardcoded 1080p/10Mbps H.264)
    └── PhotoSaveManager   (PHPhotoLibrary save)
```

### Recommended Phase 4 Structure

```
AppState
├── VideoQualitySettings   (NEW: Codable struct, UserDefaults-backed, shared instance)
├── CameraManager          (MODIFIED: applyResolutionFormat() method added)
│   └── PiPCompositor      (MODIFIED: outputWidth/outputHeight become var, injected from settings)
└── RecordingManager       (MODIFIED: passes settings to MovieRecorder.startRecording)
    ├── MovieRecorder      (MODIFIED: accepts VideoQualitySettings at startRecording)
    ├── VideoTrimManager   (NEW: runs AVAssetExportSession with timeRange, async/await)
    └── PhotoSaveManager   (UNCHANGED)
```

### Pattern 1: VideoQualitySettings Struct (VQ-01, VQ-02, VQ-04)

**What:** Codable struct encoding the user's chosen resolution and bitrate tier. Stored as `Data` in `UserDefaults`. Shared via `AppState`.

**When to use:** Before every recording start; read once from UserDefaults at launch.

```swift
// Source: [ASSUMED] — standard Codable/UserDefaults pattern
enum OutputResolution: String, Codable, CaseIterable {
    case hd720p = "720p"
    case hd1080p = "1080p"

    var width: Int  { self == .hd720p ? 720  : 1080 }
    var height: Int { self == .hd720p ? 1280 : 1920 }
}

enum BitratePreset: String, Codable, CaseIterable {
    case low    = "Low"
    case medium = "Medium"
    case high   = "High"

    // H.264 bits per second — tuned for portrait PiP composite at 30fps
    var bitsPerSecond: Int {
        switch self {
        case .low:    return 3_000_000   //  3 Mbps  ~= 22 MB/min
        case .medium: return 6_000_000   //  6 Mbps  ~= 45 MB/min
        case .high:   return 10_000_000  // 10 Mbps  ~= 75 MB/min (current default)
        }
    }
}

struct VideoQualitySettings: Codable {
    var resolution: OutputResolution = .hd1080p
    var bitrate: BitratePreset       = .high

    // UserDefaults round-trip
    static let defaultsKey = "com.naujgs.DualVideo.videoQualitySettings"

    static func load() -> VideoQualitySettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(VideoQualitySettings.self, from: data)
        else { return VideoQualitySettings() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
```

[CITED: tanaschita.com — Storing Swift structs in UserDefaults, hackingwithswift.com Codable UserDefaults]

### Pattern 2: Device Format Selection (VQ-01)

**What:** For `AVCaptureMultiCamSession`, `sessionPreset` is intentionally not applicable. Resolution must be set by selecting a matching `AVCaptureDevice.Format` and assigning it to `device.activeFormat` inside `lockForConfiguration` on `sessionQueue`. [VERIFIED: WWDC19 Session 249, Apple Developer Forums thread/134114]

**When to use:** Before `startRunning()` during initial `configureAndStart()`. Cannot change format during an active recording (would corrupt the running AVAssetWriter pixel buffer pool). Resolution changes therefore require the user to pick resolution *before* starting a recording.

**Key constraint:** Changing `activeFormat` changes `hardwareCost`. After changing both camera formats to 720p, `hardwareCost` should decrease below 1.0 — read it again with the same guard as the existing code.

```swift
// Source: [ASSUMED] — standard AVCaptureDevice format selection pattern
// Call from sessionQueue inside beginConfiguration / commitConfiguration block
private func selectFormat(for device: AVCaptureDevice, targetWidth: Int) {
    let preferred = device.formats.first { fmt in
        let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        return Int(dims.width) == targetWidth && fmt.isMultiCamSupported
    }
    guard let format = preferred else { return }
    do {
        try device.lockForConfiguration()
        device.activeFormat = format
        device.unlockForConfiguration()
    } catch {
        logger.error("CameraManager: format lock failed: \(error)")
    }
}
```

**Important:** `fmt.isMultiCamSupported` must be checked — not all formats are valid for `AVCaptureMultiCamSession`. [CITED: Apple Developer Forums thread/134114]

### Pattern 3: Configurable AVAssetWriterInput (VQ-01, VQ-02)

**What:** Replace the hardcoded video settings dictionary in `MovieRecorder.startRecording()` with values derived from the injected `VideoQualitySettings`.

```swift
// Source: [ASSUMED] — derived from Apple AVFoundation docs and existing MovieRecorder code
func startRecording(settings: VideoQualitySettings) {
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey:  settings.resolution.width,
        AVVideoHeightKey: settings.resolution.height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey:      settings.bitrate.bitsPerSecond,
            AVVideoMaxKeyFrameIntervalKey: 30
        ]
    ]
    // Adaptor source attributes must match the new dimensions:
    let adaptorAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String:           settings.resolution.width,
        kCVPixelBufferHeightKey as String:          settings.resolution.height
    ]
    // ... rest of AVAssetWriter setup unchanged
}
```

**Bitrate keys verified:** `AVVideoAverageBitRateKey` inside `AVVideoCompressionPropertiesKey` is the correct approach for H.264 on iOS. [VERIFIED: Apple Developer Forums thread/91165, testfairy.com Swift 4 fine-tuned compression guide]

### Pattern 4: PiPCompositor Output Dimensions (VQ-01)

**What:** `PiPCompositor` currently has static constants `outputWidth = 1080` and `outputHeight = 1920`. These must become instance properties set from `VideoQualitySettings` before recording starts.

```swift
// Source: [ASSUMED]
// PiPCompositor changes:
var outputWidth:  Int = 1080  // was: static let outputWidth = 1080
var outputHeight: Int = 1920  // was: static let outputHeight = 1920

// Pixel buffer fallback allocator must use the instance vars, not Self.outputWidth
// The pipRect computation in captureOutput also references Self.outputWidth/Height — update to self
```

**Timing:** Update compositor dimensions *before* `startRecording()` in `RecordingManager.startRecording()`. The pixel buffer pool (bridged from `MovieRecorder`) is created after `startRecording()`, so the compositor's new dimensions will be used automatically for pool allocation via the adaptor.

### Pattern 5: Video Trimming (VQ-03)

**What:** After recording stops, instead of auto-saving immediately, show a SwiftUI sheet with a trim UI. User defines in/out points. On confirm, run `AVAssetExportSession` with the `timeRange`, then call `PhotoSaveManager`. On skip, pass the original URL directly to `PhotoSaveManager`.

**Flow change to RecordingManager:**

```
CURRENT:  stopAndFinalize → saveRecording(url) (auto)
PHASE 4:  stopAndFinalize → pendingTrimURL = url → show TrimView sheet
          TrimView: confirm → VideoTrimManager.trim(url, range) → saveRecording(trimmedURL)
          TrimView: skip   → saveRecording(originalURL)
```

**AVAssetExportSession trim pattern:**

```swift
// Source: [CITED: developer.apple.com/documentation/avfoundation/avassetexportsession]
// Source: [CITED: github.com/acj/b8c5f8eafe0605a38692 — trim gist]
actor VideoTrimManager {
    func trim(sourceURL: URL, range: CMTimeRange) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough  // no re-encode; preserves quality
        ) else { throw TrimError.sessionUnavailable }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        session.outputURL      = outputURL
        session.outputFileType = .mov
        session.timeRange      = range

        await session.export()
        guard session.status == .completed else {
            throw TrimError.exportFailed(session.error)
        }
        return outputURL
    }
}
```

**Important:** `AVAssetExportPresetPassthrough` avoids re-encoding, which is faster and lossless. The composited .mov from `MovieRecorder` is already H.264, so passthrough is valid. Only use a quality preset (`AVAssetExportPreset1920x1080`) if the output codec needs to change — which Phase 4 does not require. [CITED: Apple AVFoundation Programming Guide — Export]

**Async export:** Use `await session.export()` (iOS 18 `async` variant) instead of `exportAsynchronously(completionHandler:)` with a callback. This simplifies the actor boundary. [ASSUMED — verify iOS 18 availability of `export()` async overload]

### Pattern 6: SwiftUI Trim UI

**What:** A `.sheet` with `presentationDetents([.large])` showing:
- An `AVPlayer` preview via `VideoPlayer(player:)` (AVKit)
- Two `Slider` or custom drag handles for in-point and out-point
- "Save Trimmed" and "Save Full" buttons

**Recommended approach:** Use SwiftUI `VideoPlayer` (from AVKit) for preview, and two `Slider` controls bound to `Double` values in `[0.0, 1.0]` representing fractional position in the clip. Convert to `CMTime` via `asset.duration * fraction`. [ASSUMED — standard SwiftUI/AVKit pattern]

**Key pitfall:** `Slider` does not natively support a two-thumb range. Must either: (a) use two overlapping `Slider` views with z-ordering and min/max clamping, or (b) implement a custom `DragGesture`-based range bar. Option (a) is simpler and sufficient for this use case.

### Anti-Patterns to Avoid

- **Changing resolution mid-recording:** `AVCaptureDevice.activeFormat` cannot be changed while a recording is active (the pixel buffer pool is keyed to the original dimensions; mismatched buffers produce corrupt output). Resolution must be a pre-recording setting only. [ASSUMED — derived from AVFoundation threading model; treat as MEDIUM confidence]
- **Using sessionPreset on AVCaptureMultiCamSession:** Setting `session.sessionPreset = .hd1920x1080` silently fails or produces unexpected behavior. Use `device.activeFormat` per camera instead. [VERIFIED: WWDC19-249, Apple Developer Forums]
- **Recreating CIContext inside composite() when dimensions change:** The existing `PiPCompositor` correctly creates `CIContext` once. When dimensions change, only the pixel buffer pool and adaptor attributes need to change — do not recreate the CIContext. [VERIFIED: existing code comment + standard Metal practice]
- **Calling `AVAssetExportSession.exportAsynchronously` from an `@MainActor` context without dispatching:** Block the main thread risk. Use the `async` variant or `Task { }` wrapper.
- **Forgetting to delete the original temp file after trim:** After `VideoTrimManager.trim()` completes successfully, the source `.mov` (original recording) must be deleted from temp storage. Otherwise orphaned files accumulate.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Video file trimming | Custom sample-level copy loop | `AVAssetExportSession` with `timeRange` | Handles audio sync, metadata, and keyframe alignment automatically |
| Pixel format conversion between resolutions | Manual Core Image scaling | Compositor `CGAffineTransform` already scales to output dimensions; just change output dims | Already solved in `PiPCompositor.composite()` |
| Settings persistence | Custom plist serializer | `JSONEncoder` + `UserDefaults` with Codable | Standard iOS pattern; battle-tested |
| Video playback in trim UI | Custom Metal player | `VideoPlayer(player:)` from AVKit | Native, handles buffering and scrubbing |
| Bitrate estimation UI | Compute from raw formulas | Pre-defined `BitratePreset` enum with display labels | Users don't know Mbps; labels ("Low/Medium/High") are sufficient |

**Key insight:** Both quality settings and trimming are entirely served by existing AVFoundation APIs. The complexity is integration (wiring settings through the call chain), not algorithm implementation.

---

## Common Pitfalls

### Pitfall 1: Resolution Mismatch Between Compositor and Recorder

**What goes wrong:** `PiPCompositor.outputWidth/Height` and `MovieRecorder` `AVVideoWidthKey`/`AVVideoHeightKey` + adaptor `kCVPixelBufferWidthKey`/`kCVPixelBufferHeightKey` must all agree. If they disagree, the adaptor rejects buffers silently (returns false from `append()`), producing a zero-byte or corrupt `.mov`.

**Why it happens:** Settings are injected at multiple call sites that were previously hardcoded to the same value.

**How to avoid:** Pass a single `VideoQualitySettings` value object through the call chain. `PiPCompositor`, `MovieRecorder.startRecording()`, and the adaptor attributes all read from the same object.

**Warning signs:** `MovieRecorder: adaptor.append failed` in logs. File size ~0 bytes after recording.

### Pitfall 2: AVCaptureDevice Format Not isMultiCamSupported

**What goes wrong:** Some `AVCaptureDevice.formats` entries at 720p or 1080p are not valid for `AVCaptureMultiCamSession`. Setting an incompatible format causes `session.commitConfiguration()` to silently revert to the previous format, and the camera may fail to start.

**Why it happens:** `AVCaptureMultiCamSession` imposes constraints on format combinations (hardware cost budget).

**How to avoid:** Always filter `device.formats` with `fmt.isMultiCamSupported` before selecting. Log the chosen format after `commitConfiguration`. [CITED: Apple Developer Forums thread/134114]

**Warning signs:** `hardwareCost` unexpectedly jumps above 0.9 after format change; preview layer shows blank.

### Pitfall 3: Pixel Buffer Pool Size Mismatch After Resolution Change

**What goes wrong:** The `AVAssetWriterInputPixelBufferAdaptor.pixelBufferPool` is sized to the writer's declared dimensions. If `PiPCompositor` was previously using 1080p and `MovieRecorder` is now configured for 720p (or vice versa), the pool hands out buffers of the wrong size. The compositor's `acquireOutputBuffer()` will get a pool buffer sized for the old resolution and render into it — producing garbage output.

**Why it happens:** `RecordingManager.startRecording()` bridges the pool to the compositor *after* `recorder.startRecording()`. If the compositor's dimensions were not updated first, the pool is the wrong size.

**How to avoid:** In `RecordingManager.startRecording()`, update `compositor.outputWidth/Height` from `settings` *before* calling `recorder.startRecording()`.

### Pitfall 4: AVAssetExportSession Passthrough Incompatibility

**What goes wrong:** `AVAssetExportPresetPassthrough` does not re-encode, which is fastest. However, if the source `.mov` has any non-standard metadata or encoding flags, passthrough can fail (`session.status == .failed`). 

**Why it happens:** Recorded `.mov` from `AVAssetWriter` with H.264 is standard and should work. But if the error appears, fall back to `AVAssetExportPresetHighestQuality` or `AVAssetExportPreset1920x1080` to force re-encode.

**How to avoid:** Guard on `session.status` after export and surface the error; implement a fallback preset retry. Log `session.error?.localizedDescription`.

**Warning signs:** Export completes immediately with `.failed` status and `AVError.Code.exportFailed`.

### Pitfall 5: Trim UI Blocking Auto-Save

**What goes wrong:** The current `RecordingManager.saveRecording(url:)` is called automatically from `stopRecording()`'s completion. If a trim sheet is inserted between them, auto-save must be suppressed until the user acts.

**Why it happens:** The auto-save flow was designed for Phase 3's "record and save immediately" UX.

**How to avoid:** Introduce a `pendingTrimURL: URL?` observable on `RecordingManager`. When non-nil, show trim sheet. Auto-save is only called after the user taps "Save Trimmed" or "Save Full". Set `pendingTrimURL = nil` after either path.

### Pitfall 6: CMTime Precision in Trim Range Sliders

**What goes wrong:** Converting a `Double` slider value (0.0–1.0) to `CMTime` using `* asset.duration` without rounding can produce fractional CMTime values that `AVAssetExportSession` rounds to the nearest keyframe, causing unexpected trim boundaries.

**Why it happens:** H.264 keyframe interval is 30 frames (1 second). Export trims to keyframe boundaries.

**How to avoid:** This is expected behavior and acceptable for this use case. Display the trim endpoints in seconds (rounded to 0.1s) in the UI so the user has accurate feedback. Do not attempt sub-frame trim precision — it is not supported by passthrough export.

---

## Code Examples

### Enumerating Supported Formats for 720p

```swift
// Source: [ASSUMED] — standard AVCaptureDevice format enumeration pattern
let targetWidth = 720 // for 720p portrait (sensor delivers landscape; rotation corrects)
// Note: camera sensor delivers landscape (width > height); 720p landscape = 1280x720
let landscapeTargetWidth = settings.resolution.height // 1280 for 720p, 1920 for 1080p

let preferred = backDevice.formats.first { fmt in
    let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
    let matchesWidth = Int(dims.width) == landscapeTargetWidth
    return matchesWidth && fmt.isMultiCamSupported
}
```

**Note on orientation:** The camera sensor is landscape. `videoRotationAngle = 90` in `CameraManager` rotates the *connection*, not the format. The `AVCaptureDevice.Format` dimensions are always landscape (e.g., 1920x1080 not 1080x1920). When selecting a "1080p" format, filter for `dims.width == 1920`. For "720p", filter for `dims.width == 1280`. [ASSUMED — derived from existing CameraManager videoRotationAngle = 90 usage]

### AVAssetExportSession Trim (Passthrough)

```swift
// Source: [CITED: developer.apple.com/documentation/avfoundation/avassetexportsession]
let asset = AVURLAsset(url: sourceURL)
let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)!
session.outputURL      = outputURL
session.outputFileType = .mov
session.timeRange      = CMTimeRange(start: inPoint, end: outPoint)
await session.export()
```

### SwiftUI Quality Settings Bottom Sheet

```swift
// Source: [CITED: sarunw.com — SwiftUI bottom sheet with presentationDetents]
// Source: [ASSUMED] — standard SwiftUI picker pattern
.sheet(isPresented: $showQualitySettings) {
    VStack(spacing: 20) {
        Picker("Resolution", selection: $settings.resolution) {
            ForEach(OutputResolution.allCases, id: \.self) { r in
                Text(r.rawValue).tag(r)
            }
        }
        .pickerStyle(.segmented)

        Picker("Quality", selection: $settings.bitrate) {
            ForEach(BitratePreset.allCases, id: \.self) { b in
                Text(b.rawValue).tag(b)
            }
        }
        .pickerStyle(.segmented)
    }
    .presentationDetents([.height(200)])
    .presentationDragIndicator(.visible)
}
```

---

## File Size Reference (for UI labels)

These are approximate estimates to inform quality preset label design: [ASSUMED — derived from bitrate formulas and WebSearch results]

| Resolution | Bitrate Preset | Mbps | ~MB/minute |
|------------|----------------|------|------------|
| 720p       | Low            | 3    | ~22 MB/min |
| 720p       | Medium         | 6    | ~45 MB/min |
| 720p       | High           | 10   | ~75 MB/min |
| 1080p      | Low            | 3    | ~22 MB/min |
| 1080p      | Medium         | 6    | ~45 MB/min |
| 1080p      | High           | 10   | ~75 MB/min (current default) |

Note: 720p at Low (3 Mbps) produces the same file size as 1080p at Low because bitrate — not resolution — drives file size in this codec. Resolution affects quality for a given bitrate, not the storage arithmetic. Recommend surfacing only bitrate tier in the UI (Low/Medium/High) with an approximate storage hint per minute.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `exportAsynchronously(completionHandler:)` | `await session.export()` (async) | iOS 18 | Cleaner actor boundaries; use async variant |
| `sessionPreset` for resolution | `device.activeFormat` per camera | iOS 13 MultiCam | Required for `AVCaptureMultiCamSession` |
| UIKit UISlider for trim range | SwiftUI `Slider` + custom range bar | SwiftUI availability | Pure SwiftUI preferred; two `Slider` views suffice |
| `presentationDetents` (custom) | `.presentationDetents([.medium])` | iOS 16 | No UIKit subclassing needed |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Resolution must be set before recording starts; cannot change mid-recording | Architecture Patterns / Anti-Patterns | If wrong, could attempt runtime format switch — would likely corrupt the recording |
| A2 | `PiPCompositor.outputWidth/Height` should become instance `var` instead of static `let` | Architecture Patterns | If wrong, need a different injection approach (e.g., compositor re-init) |
| A3 | `AVAssetExportPresetPassthrough` works with the composited H.264 `.mov` output | Pitfall 4 / Pattern 5 | If wrong, must use a quality preset and accept re-encode time penalty |
| A4 | `await session.export()` async overload is available on iOS 18 | Pattern 5 | If wrong, must use `exportAsynchronously(completionHandler:)` with `withCheckedContinuation` |
| A5 | Camera sensor format dimensions are landscape (e.g., 1920×1080 for 1080p) even though rotation corrects to portrait | Code Examples | If wrong, format filter width/height criteria must be swapped |
| A6 | Bitrate of 3/6/10 Mbps produces acceptable quality at 720p/1080p for portrait PiP composite | File Size Reference | If wrong, adjust bitrate values before shipping — no architecture impact |
| A7 | Two-thumb range slider can be implemented as two `SwiftUI.Slider` views with overlap | Pattern 6 | If wrong, requires a `DragGesture`-based custom component — more SwiftUI work |

---

## Open Questions (RESOLVED)

1. **Can `AVAssetExportPresetPassthrough` be used with the composited `.mov`?**
   - What we know: Passthrough is documented for re-packaging without re-encode; the source is a valid AVAssetWriter-produced H.264 .mov.
   - What's unclear: Whether keyframe interval (30 frames = 1 sec) limits trim precision to ±1 second at boundaries.
   - Recommendation: Test in `VideoTrimManagerTests` with a short synthetic `.mov`. If passthrough fails, fall back to `AVAssetExportPresetHighestQuality`.
   - RESOLVED: Plans use `AVAssetExportPresetPassthrough`; `VideoTrimManagerTests` validates end-to-end (Plan 04-01 Wave 0). Fallback to `AVAssetExportPresetHighestQuality` is documented in the `VideoTrimManager` action block (Plan 04-02).

2. **Does changing `device.activeFormat` during session configuration affect `hardwareCost` enough to require re-validation?**
   - What we know: The existing code guards `hardwareCost < 0.9` after `commitConfiguration()`. Format changes happen inside `beginConfiguration()` / `commitConfiguration()`.
   - What's unclear: Whether selecting 720p formats for both cameras reduces cost enough to notice, or whether it could exceed budget in unexpected combinations.
   - Recommendation: Always re-read and log `hardwareCost` after format-change commit; keep the existing `< 0.9` guard.
   - RESOLVED: Plans log `hardwareCost` after `activeFormat` change in `CameraManager` (Plan 04-02 Task 2). No blocking re-validation required — diagnostic logging is sufficient; the existing `< 0.9` guard is retained.

3. **Is `VideoPlayer(player:)` from AVKit suitable for the trim preview, or does `AVPlayerViewController` wrapped in `UIViewControllerRepresentable` perform better?**
   - What we know: `VideoPlayer` is a SwiftUI native API. `AVPlayerViewController` supports native transport controls but is harder to customize.
   - What's unclear: Whether `VideoPlayer` supports seeking by scrubbing the AVPlayer `.seek(to:)` reliably during simultaneous gesture handling.
   - Recommendation: Use `VideoPlayer(player:)` first (simpler). If scrubbing is laggy, switch to `AVPlayerViewController` wrapped in `UIViewControllerRepresentable`.
   - RESOLVED: Plans use `VideoPlayer(player:)` from AVKit in `TrimSheet` (Plan 04-04 Task 1) for inline playback. If scrubbing proves laggy during implementation, the fallback to `AVPlayerViewController` in `UIViewControllerRepresentable` is documented as a known escape hatch.

---

## Environment Availability

Step 2.6: SKIPPED — all APIs required (AVFoundation, AVKit, SwiftUI, CoreMedia, UserDefaults) are system frameworks; no external tools, CLIs, or services are required. Confirmed by codebase: all existing phases use only system frameworks.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (system, iOS SDK) |
| Config file | Xcode scheme — `DualVideoTests` target |
| Quick run command | `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16' -testPlan DualVideo` |
| Full suite command | Same — all test files under `DualVideoTests/UnitTests/` run as one target |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| VQ-01 | `VideoQualitySettings.resolution` returns correct width/height | unit | `xcodebuild test ... -only-testing:DualVideoTests/VideoQualitySettingsTests` | ❌ Wave 0 |
| VQ-01 | `MovieRecorder.startRecording(settings:)` uses correct video dimensions | unit | `xcodebuild test ... -only-testing:DualVideoTests/MovieRecorderTests` | ✅ (extend existing) |
| VQ-02 | `BitratePreset.bitsPerSecond` returns correct Mbps for each case | unit | `xcodebuild test ... -only-testing:DualVideoTests/VideoQualitySettingsTests` | ❌ Wave 0 |
| VQ-03 | `VideoTrimManager.trim(url:range:)` produces a valid .mov with correct duration | unit (async) | `xcodebuild test ... -only-testing:DualVideoTests/VideoTrimManagerTests` | ❌ Wave 0 |
| VQ-03 | `RecordingManager.pendingTrimURL` is set after `stopRecording`, not auto-saved | unit | `xcodebuild test ... -only-testing:DualVideoTests/RecordingManagerTests` | ✅ (extend existing) |
| VQ-04 | `VideoQualitySettings.save()` / `.load()` round-trips correctly | unit | `xcodebuild test ... -only-testing:DualVideoTests/VideoQualitySettingsTests` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** Run affected test class only (e.g., `VideoQualitySettingsTests`)
- **Per wave merge:** Full suite — all tests in `DualVideoTests/UnitTests/`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `DualVideoTests/UnitTests/VideoQualitySettingsTests.swift` — covers VQ-01, VQ-02, VQ-04
- [ ] `DualVideoTests/UnitTests/VideoTrimManagerTests.swift` — covers VQ-03 (async XCTestExpectation)

*(Existing `MovieRecorderTests.swift` and `RecordingManagerTests.swift` will be extended, not replaced.)*

---

## Security Domain

`security_enforcement` is not explicitly set to false in `.planning/config.json` — treating as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | n/a |
| V3 Session Management | no | n/a |
| V4 Access Control | no | n/a |
| V5 Input Validation | yes — trim range bounds | Clamp `inPoint >= .zero` and `outPoint <= asset.duration`; ensure `inPoint < outPoint` before calling `AVAssetExportSession` |
| V6 Cryptography | no | n/a |

### Known Threat Patterns for AVFoundation / File I/O

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Trim range out-of-bounds (negative start, end > duration) | Tampering | Clamp CMTime values in `VideoTrimManager` before setting `session.timeRange` |
| Orphaned temp files after failed export | Information Disclosure | Delete sourceURL and outputURL in the `catch` path of `VideoTrimManager.trim()`; existing `cleanUpOrphanedTempFiles()` in `RecordingManager` covers `.mov` files in temp dir |
| UserDefaults tampering (jailbroken device) | Tampering | No sensitive data in `VideoQualitySettings` — resolution/bitrate preferences carry no security risk |

---

## Sources

### Primary (HIGH confidence)
- Apple WWDC19 Session 249 "Introducing Multi-Camera Capture for iOS" — sessionPreset not applicable to AVCaptureMultiCamSession; use activeFormat per device
- [Apple Developer Forums thread/134114](https://developer.apple.com/forums/thread/134114) — AVCaptureMultiCamSession preset and activeFormat constraints; isMultiCamSupported requirement
- [AVAssetExportSession Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avassetexportsession) — timeRange, passthrough preset, async export
- [hardwareCost Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/hardwarecost) — hardwareCost semantics
- [presentationDetents Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)) — bottom sheet API

### Secondary (MEDIUM confidence)
- [testfairy.com — Fine Tuned Video Compression in iOS](https://testfairy.com/blog/fine-tuned-video-compression-in-ios-swift-4-no-dependencies/) — AVVideoCompressionPropertiesKey / AVVideoAverageBitRateKey usage for H.264
- [Apple Developer Forums thread/91165](https://developer.apple.com/forums/thread/91165) — AVAssetWriter H.265/HEVC bitrate defaults; H.264 vs HEVC default bitrate difference
- [tanaschita.com — Storing Swift structs in UserDefaults](https://tanaschita.com/swift-user-defaults-storing-structs/) — Codable + UserDefaults pattern
- [sarunw.com — SwiftUI bottom sheet](https://sarunw.com/posts/swiftui-bottom-sheet/) — presentationDetents usage
- [bacancytechnology.com — AVFoundation trim guide](https://www.bacancytechnology.com/blog/avfoundation-framework-to-trim-the-video) — AVAssetExportSession timeRange trim workflow
- [GitHub gist acj — trim video AVFoundation](https://gist.github.com/acj/b8c5f8eafe0605a38692) — canonical trim implementation

### Tertiary (LOW confidence)
- [WebSearch] File size estimates per minute by resolution/bitrate — multiple calculator sites, cross-referenced with bitrate formula; used only for UI label guidance

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all system frameworks, no third-party dependencies
- Resolution/bitrate AVFoundation API: HIGH — verified against Apple docs and WWDC session
- AVAssetExportSession trim: MEDIUM-HIGH — documented API; passthrough viability with AVAssetWriter output is ASSUMED
- Architecture impact on PiPCompositor: MEDIUM — derived from codebase analysis; no test run in this session
- SwiftUI UI patterns: HIGH — presentationDetents is documented, picker is standard

**Research date:** 2026-05-18
**Valid until:** 2026-11-18 (stable AVFoundation APIs; 6-month horizon)
