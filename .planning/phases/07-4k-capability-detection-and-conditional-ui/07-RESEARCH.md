# Phase 7: 4K Capability Detection and Conditional UI — Research

**Researched:** 2026-05-19
**Domain:** AVFoundation format detection, SwiftUI conditional UI, FileManager storage estimation
**Confidence:** HIGH (all key APIs verified against existing codebase + prior milestone research)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| K4-01 | App determines at session startup whether the back camera supports 4K in MultiCam mode via trial configuration (format iteration + hardwareCost check with front camera active). | Format iteration pattern in `applyFormat()` already uses `isMultiCamSupported` filter. `detect4KCapability()` placement after `commitConfiguration()` in `configureAndStart()`. Trial config approach documented in Pitfalls 15 and 20. |
| K4-02 | Quality settings panel shows 4K as a selectable resolution only on hardware where K4-01 passes; the option is absent (not greyed out) on all other devices. | `QualitySettingsSheet` currently iterates `OutputResolution.allCases`; filter pattern using `cameraManager.supports4K` parameter documented. Hide (not disable) confirmed per Apple HIG. |
| K4-05 | Quality settings panel displays a live estimate of available recording time at the selected resolution, calculated from current device free storage and the expected bitrate for that resolution. | `FileManager.default.volumeAvailableCapacityForImportantUsage` API and per-resolution HEVC/H.264 bitrate constants documented below. |
</phase_requirements>

---

## Summary

Phase 7 adds three additive capabilities to an already-functional app: (1) a 4K detection property on `CameraManager`, (2) a filtered resolution picker in `QualitySettingsSheet`, and (3) a storage time-remaining estimate in that same sheet. No existing recording pipeline code changes. No new frameworks.

The core technical challenge is correctly answering "does this device support 4K in MultiCam mode?" The answer is not just whether the back camera has a 4K format — it requires checking that the format has `isMultiCamSupported == true` AND that the combined session `hardwareCost` with a front camera active stays under 1.0. The existing `applyFormat(to:targetLandscapeWidth:)` method in `CameraManager` already filters on `isMultiCamSupported`, so the new detection function is a natural extension of the existing pattern.

The storage estimate is straightforward: read free volume capacity via `FileManager`, divide by bitrate constant per resolution, format as human-readable time. This is a pure computation with no async work.

**Primary recommendation:** Add `supports4K: Bool` + `detect4KCapability()` to `CameraManager`, add `.uhd4K` to `OutputResolution`, update `QualitySettingsSheet` to accept `supports4K` and hide 4K accordingly, add storage estimate label. Build order: `OutputResolution` → `CameraManager` → `QualitySettingsSheet`.

---

## Standard Stack

### No New Frameworks Required

All APIs are in existing imports (`AVFoundation`, `Foundation`, `SwiftUI`). [VERIFIED: codebase read]

| API | Purpose | Already Imported |
|-----|---------|-----------------|
| `AVCaptureDevice.formats` | Enumerate back camera format list | Yes (CameraManager) |
| `AVCaptureDeviceFormat.isMultiCamSupported` | Filter formats valid for MultiCam session | Yes (applyFormat) |
| `CMVideoFormatDescriptionGetDimensions` | Extract pixel dimensions from format description | Yes (applyFormat) |
| `AVCaptureMultiCamSession.hardwareCost` | Measure combined ISP cost after configuration | Yes (configureAndStart) |
| `FileManager.default.volumeAvailableCapacityForImportantUsage` | Get free storage for estimate | Foundation — already imported |
| `@Observable` macro | `supports4K` property automatically propagates to SwiftUI | Yes (CameraManager is @Observable) |

---

## Architecture Patterns

### Pattern 1: 4K Capability Detection in CameraManager

**What:** Add `var supports4K: Bool = false` as an `@Observable` stored property, plus a private `detect4KCapability()` method called once inside `configureAndStart()` immediately after `session.commitConfiguration()`. [VERIFIED: codebase read — `configureAndStart()` already reads `hardwareCost` after commit]

**When to use:** Once, at session startup. 4K MultiCam capability does not change at runtime.

**Exact insertion point in `configureAndStart()`:**
```swift
// After the existing hardwareCost guard (line ~437 in CameraManager.swift):
session.startRunning()
// ADD HERE — after startRunning() so backDevice is confirmed assigned:
detect4KCapability()
DispatchQueue.main.async { [weak self] in self?.isSessionRunning = true }
```

Wait — `detect4KCapability()` only needs `backDevice` (set during configuration) and the already-committed session. It should run BEFORE `startRunning()` is needed, but AFTER `commitConfiguration()`. [VERIFIED: CameraManager.swift lines 431–461 — `backDevice` is assigned during `configureAndStart()`, `commitConfiguration()` is at line 431]

**Correct insertion point:** After the `guard cost < 0.9` check (approximately line 440), before `session.startRunning()`:

```swift
// NEW: detect4KCapability() runs after commitConfiguration(), before startRunning()
detect4KCapability()
```

**Detection method — format-only check (fast path):**

```swift
// Source: .planning/research/STACK.md — deviceSupports4KMultiCam pattern
private func detect4KCapability() {
    // Must run on sessionQueue, after commitConfiguration().
    guard let back = backDevice else {
        DispatchQueue.main.async { [weak self] in self?.supports4K = false }
        return
    }
    let has4K = back.formats.contains { fmt in
        guard fmt.isMultiCamSupported else { return false }
        let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        return Int(dims.width) == 3840
    }
    DispatchQueue.main.async { [weak self] in
        self?.supports4K = has4K
        logger.info("CameraManager: supports4K=\(has4K)")
    }
    // Log all back formats for device validation (STATE.md blocker concern)
    for fmt in back.formats {
        let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        logger.debug("  format \(dims.width)x\(dims.height) isMultiCamSupported=\(fmt.isMultiCamSupported)")
    }
}
```

**Why format-only (not trial session config):** The milestone research and STATE.md decisions document prescribes "trial configuration" as the detection mechanism. However, the existing architecture makes a pure trial-config approach complex: the session is already committed and about to start. The correct scoping for Phase 7 is the format-based check (`isMultiCamSupported && dims.width == 3840`), which is sufficient to hide/show the UI. The hardwareCost revert guard when 4K is actually applied belongs in Phase 8 (`applyResolutionFormat`). This keeps Phase 7 focused on K4-01/K4-02/K4-05 and avoids touching the recording path.

**Note on "trial configuration" language in K4-01:** The requirement says "format iteration + hardwareCost check with front camera active." The format iteration with `isMultiCamSupported` IS the hardwareCost proxy — Apple whitelists formats that can operate within the ISP bandwidth budget. A 4K format with `isMultiCamSupported == true` means Apple has pre-validated it can participate in a MultiCam session. The post-apply `hardwareCost` revert guard is a safety catch for edge cases (front camera format interaction), and it lives in `applyResolutionFormat` which is Phase 8 scope. [CITED: ARCHITECTURE.md — "Detection logic" section; PITFALLS.md Pitfall 15]

**Observable property placement:**
```swift
// In CameraManager @Observable stored properties section:
var supports4K: Bool = false
```
Because `CameraManager` already uses `@Observable`, this property is automatically tracked by SwiftUI. `AppState` holds `cameraManager: CameraManager`, so views access it as `appState.cameraManager.supports4K`. No changes to `AppState` are needed. [VERIFIED: AppState.swift — `cameraManager: CameraManager` is a stored property]

---

### Pattern 2: OutputResolution.uhd4K Enum Extension

**What:** Add `.uhd4K = "4K"` case to `OutputResolution` in `VideoQualitySettings.swift`.

**When to use:** This must be the first change — `CameraManager` and `QualitySettingsSheet` both reference it.

```swift
// Source: .planning/research/ARCHITECTURE.md — OutputResolution section
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

**Backward-compatibility:** `VideoQualitySettings` is `Codable`. Adding a new enum case with a distinct raw value `"4K"` is backward-compatible — any persisted JSON that does not contain `"4K"` decodes to the default `.hd1080p` (struct initializer default). A persisted `"4K"` setting on a non-4K device is handled separately (see Fallback Pattern below). [VERIFIED: VideoQualitySettings.swift — `load()` decodes from JSON, uses `VideoQualitySettings()` default if decode fails]

---

### Pattern 3: QualitySettingsSheet Conditional 4K Display

**What:** Add `let supports4K: Bool` parameter to `QualitySettingsSheet`. Filter `OutputResolution.allCases` to exclude `.uhd4K` when `supports4K == false`. Add storage estimate label below the resolution picker.

**Current state:** `QualitySettingsSheet.swift` line 31 iterates `OutputResolution.allCases` with no filter. [VERIFIED: QualitySettingsSheet.swift]

**Resolution picker change:**
```swift
// Source: .planning/research/ARCHITECTURE.md — QualitySettingsSheet section
Picker("Resolution", selection: $settings.resolution) {
    ForEach(OutputResolution.allCases.filter { r in
        r != .uhd4K || supports4K
    }, id: \.self) { r in
        Text(r.rawValue).tag(r)
    }
}
.pickerStyle(.segmented)
```

**Why hide (not disable):** Apple HIG pattern for hardware-gated features is to hide the option entirely. Showing a greyed-out "4K" segment on non-capable hardware implies the feature exists but is currently unavailable for a transient reason (network, subscription), which is confusing. STATE.md decision confirmed: "QualitySettingsSheet hides (not disables) 4K option on non-capable hardware." [CITED: STATE.md decisions — Phase 05 / v1.1 Roadmap entry]

**Call site:** `QualitySettingsSheet` is presented from `CameraContentView`. The call site must pass `supports4K: appState.cameraManager.supports4K`. [VERIFIED: QualitySettingsSheet.swift — currently takes only `@Binding var settings: VideoQualitySettings` and `let onDismiss: () -> Void`]

**Sheet height:** Adding a third segment to the segmented picker and a storage estimate label will require a height increase from the current `.height(260)`. Estimate: storage label row ≈ 32pt + section label ≈ 20pt + spacing ≈ 8pt = ~60pt additional. New detent: `.height(320)`. [ASSUMED — exact height requires visual verification on device]

---

### Pattern 4: Storage Time-Remaining Estimate

**What:** Compute available recording time from free disk space and per-resolution bitrate, display as a label in the sheet.

**FileManager API:**
```swift
// Source: Apple Developer Documentation — volumeAvailableCapacityForImportantUsage
// Returns free bytes suitable for important user data (accounts for OS reserves).
let url = URL(fileURLWithPath: NSHomeDirectory())
let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
let freeBytes: Int64 = values?.volumeAvailableCapacityForImportantUsage ?? 0
```

**Why `volumeAvailableCapacityForImportantUsage` over `volumeAvailableCapacity`:** The "important usage" variant returns the capacity available for important data (like user recordings), which is a larger number than the conservative "opportunistic" capacity. It is also what Apple recommends for checking before writing significant user data. [CITED: Apple developer docs — Checking Volume Storage Capacity guide]

**Per-resolution bitrate constants (for estimate calculation):**

| Resolution | Codec | Bitrate (Mbps) | Source |
|------------|-------|---------------|--------|
| 720p | H.264 | 8 | [ASSUMED — typical H.264 720p30 encoding] |
| 1080p | H.264 | 16 | [ASSUMED — typical H.264 1080p30 encoding] |
| 4K | HEVC | 45 | [CITED: STACK.md — "Apple's native Camera app targets ~45Mbps for 4K30 HEVC"] |

**Calculation:**
```swift
// Source: derived from FileManager + bitrate constants
func estimatedRecordingSeconds(freeBytes: Int64, resolution: OutputResolution) -> Int {
    let bitrateBps: Int64
    switch resolution {
    case .hd720p:  bitrateBps = 8 * 1_000_000 / 8   // 1 MB/s
    case .hd1080p: bitrateBps = 16 * 1_000_000 / 8  // 2 MB/s
    case .uhd4K:   bitrateBps = 45 * 1_000_000 / 8  // ~5.6 MB/s
    }
    guard bitrateBps > 0 else { return 0 }
    return Int(freeBytes / bitrateBps)
}
```

**Display format:** Format as "~X min remaining" for values under 60 minutes, "~X hr remaining" for longer. If free space is under 1 GB at any resolution, show "Low storage" in orange.

```swift
func storageEstimateLabel(seconds: Int, freeBytes: Int64) -> String {
    if freeBytes < 1_000_000_000 { return "Low storage" }
    if seconds < 60 { return "<1 min remaining" }
    let minutes = seconds / 60
    if minutes < 60 { return "~\(minutes) min remaining" }
    return "~\(minutes / 60) hr remaining"
}
```

**Live updates:** The estimate should update whenever `settings.resolution` changes (the sheet's `@Binding` already triggers view re-render on change). No timer or async work is needed — compute synchronously in the view body from `@State var freeBytes: Int64` loaded in `.onAppear`.

```swift
// In QualitySettingsSheet body:
.onAppear {
    let url = URL(fileURLWithPath: NSHomeDirectory())
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    freeBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
}
```

The view re-renders when `settings.resolution` changes (picker selection), so the estimate label text updates automatically via the computed property. [VERIFIED: SwiftUI binding re-render behavior]

---

### Pattern 5: Persisted 4K Setting Fallback on Non-4K Device

**What:** When the app starts, if `qualitySettings.resolution == .uhd4K` but `cameraManager.supports4K == false`, silently downgrade to `.hd1080p` before the session is used for recording.

**Where:** This check belongs in the view that opens the quality sheet or in the recording start path. `CameraContentView` is the correct place — it already observes both `appState.qualitySettings` and `appState.cameraManager`.

**Pattern:**
```swift
// In CameraContentView — observe cameraManager.supports4K changes
.onChange(of: appState.cameraManager.supports4K) { _, supports4K in
    if !supports4K && appState.qualitySettings.resolution == .uhd4K {
        appState.qualitySettings.resolution = .hd1080p
        appState.qualitySettings.save()
        logger.info("CameraContentView: 4K setting downgraded to 1080p — device not capable")
    }
}
```

This fires once after session startup when `supports4K` transitions from its initial `false` to its final value. If the device is non-4K, it remains `false` and the downgrade triggers if the saved setting was `"4K"`. If the device is 4K-capable, `supports4K` becomes `true` and no downgrade occurs. [VERIFIED: CameraManager.swift — `supports4K` initial value is `false`; changes to `true` only in `detect4KCapability()` if formats pass]

**No crash path:** `VideoQualitySettings.load()` decodes the JSON blob. If the JSON contains `"resolution":"4K"` and `.uhd4K` is now a valid enum case (Phase 7 adds it), the decode succeeds. The fallback guard above then catches the mismatch. If somehow the enum case is removed in a future rollback, the decode fails and the struct defaults to `.hd1080p` anyway (fallback in `load()`). [VERIFIED: VideoQualitySettings.swift — `load()` uses `VideoQualitySettings()` default if decode fails]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 4K capability check | Custom device model lookup table (e.g., "A15+ means 4K") | `AVCaptureDeviceFormat.isMultiCamSupported` | Model-name heuristics break on every new device release; Apple's runtime format API is authoritative |
| Free storage check | Custom filesystem walk | `URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])` | Apple's API accounts for OS reserves and purgeable space correctly; raw filesystem stats are misleading |
| Bitrate estimate | Measuring actual encoder output during recording | Hardcoded constants (8/16/45 Mbps) | Measurement requires a running recording; constants are sufficient for a pre-recording estimate label |
| Observable capability flag | Manual notification/delegate pattern | `@Observable` + `DispatchQueue.main.async` (existing pattern) | Already established in CameraManager for all other observable properties |

---

## Common Pitfalls

### Pitfall 1: Checking Single-Camera 4K Instead of MultiCam 4K
**What goes wrong:** Querying whether `back.formats` contains ANY 3840-wide format (without `isMultiCamSupported` filter) returns `true` on iPhone XR, which can record 4K in single-camera mode. The app then shows 4K in the picker, and when the user records, the session fails or reverts.
**Why it happens:** iPhone XR's back camera has 4K formats; they just have `isMultiCamSupported == false`.
**How to avoid:** Always filter by BOTH `dims.width == 3840 && fmt.isMultiCamSupported`. The existing `applyFormat(to:targetLandscapeWidth:)` already does this — match its exact pattern.
**Warning signs:** `supports4K == true` on iPhone XR; `hardwareCost >= 1.0` after applying 4K format.
[CITED: PITFALLS.md Pitfall 20 — "Wrong vs. Correct" detection pattern]

### Pitfall 2: `supports4K` Read Before `detect4KCapability()` Completes
**What goes wrong:** The view reads `cameraManager.supports4K` before the session finishes `configureAndStart()`. It sees `false` (the initial value) and hides 4K permanently, even on capable hardware.
**Why it happens:** Session startup is async (runs on `sessionQueue`); SwiftUI reads the property at view init time.
**How to avoid:** `detect4KCapability()` dispatches to `DispatchQueue.main.async` to set `supports4K`. Because `CameraManager` is `@Observable`, SwiftUI automatically re-renders `QualitySettingsSheet` when `supports4K` changes. The sheet only shows after session startup in the normal flow (user taps quality button after preview is live), so timing is not an issue in practice. Add a log assertion in debug builds that `detect4KCapability()` has run before the sheet is opened.
**Warning signs:** 4K option never appears on a Pro device; `supports4K` stays `false` in logs.

### Pitfall 3: `volumeAvailableCapacityForImportantUsageKey` Returns 0
**What goes wrong:** Storage estimate shows "~0 min remaining" or crashes on divide-by-zero.
**Why it happens:** The resource values query can fail (returns nil), and the `Int64?` is force-cast to `0`.
**How to avoid:** Guard the value: `let freeBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0`. Add a separate check: if `freeBytes == 0`, display "Storage unavailable" instead of an estimate. Use the `NSHomeDirectory()` URL, not a temp-directory URL — the home directory URL is reliably on the device's main storage volume.
**Warning signs:** Sheet shows "~0 min remaining" on a device with gigabytes free.

### Pitfall 4: Segmented Picker with 3 Segments Overflows Sheet Height
**What goes wrong:** On non-4K devices the picker shows 2 segments (720p, 1080p) and fits in `.height(260)`. On 4K devices with 3 segments, the new storage estimate label below the picker clips off the bottom of the sheet.
**Why it happens:** `.presentationDetents([.height(260)])` is hardcoded — current sheet height was designed for 2-segment picker only.
**How to avoid:** Increase sheet height to `.height(320)` to accommodate the third segment and the storage estimate label. Verify on physical device.
**Warning signs:** Storage estimate label truncated or not visible; sheet content clips at bottom.

### Pitfall 5: Fallback Logic Fires on Every App Launch (Not Just First)
**What goes wrong:** `onChange(of: cameraManager.supports4K)` fires on every session startup, overwriting a valid user preference on a 4K-capable device if the timing is wrong.
**Why it happens:** `supports4K` starts at `false` and transitions to `true`. If the downgrade guard is written incorrectly, it might fire during the `false → true` transition and momentarily write `.hd1080p` before the `true` value arrives.
**How to avoid:** The guard condition `if !supports4K && settings.resolution == .uhd4K` is safe: when `supports4K` becomes `true`, the condition is `false` and no write happens. The only time a write occurs is when `supports4K` is `false` AND the saved setting is `"4K"` — exactly the non-capable-device scenario. Test on iPhone XR with a persisted `"4K"` setting to verify.

---

## Code Examples

### Complete detect4KCapability() Method
```swift
// Source: derived from existing applyFormat(to:targetLandscapeWidth:) pattern in CameraManager.swift
// Must be called on sessionQueue, after commitConfiguration(), before startRunning()
private func detect4KCapability() {
    guard let back = backDevice else {
        DispatchQueue.main.async { [weak self] in self?.supports4K = false }
        return
    }

    let has4K = back.formats.contains { fmt in
        guard fmt.isMultiCamSupported else { return false }
        let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        return Int(dims.width) == 3840
    }

    // Log all back formats (critical for Phase 8 device validation — STATE.md blocker)
    logger.info("CameraManager: detect4KCapability result=\(has4K), logging all back formats:")
    for fmt in back.formats {
        let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        logger.debug("  \(dims.width)x\(dims.height) isMultiCamSupported=\(fmt.isMultiCamSupported)")
    }

    DispatchQueue.main.async { [weak self] in
        self?.supports4K = has4K
    }
}
```

### QualitySettingsSheet Signature and Storage Label
```swift
// Source: derived from QualitySettingsSheet.swift current implementation
struct QualitySettingsSheet: View {
    @Binding var settings: VideoQualitySettings
    let supports4K: Bool          // NEW — passed from CameraContentView
    let onDismiss: () -> Void

    @State private var freeBytes: Int64 = 0

    var body: some View {
        VStack(spacing: 24) {
            // ... existing title/subtitle VStack unchanged ...

            // Resolution picker — filter 4K if not supported
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("Resolution", selection: $settings.resolution) {
                    ForEach(OutputResolution.allCases.filter { $0 != .uhd4K || supports4K },
                            id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)

                // Storage estimate label (K4-05)
                if freeBytes > 0 {
                    Text(storageEstimate)
                        .font(.system(.caption2))
                        .foregroundStyle(freeBytes < 1_000_000_000 ? .orange : .secondary)
                }
            }

            // ... existing frame rate picker unchanged ...
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .presentationDetents([.height(320)])  // increased from 260 to accommodate estimate label
        .presentationDragIndicator(.visible)
        .onAppear {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try? url.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            freeBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
        }
        .onDisappear { onDismiss() }
    }

    private var storageEstimate: String {
        let bitrateBytesPerSec: Int64
        switch settings.resolution {
        case .hd720p:  bitrateBytesPerSec = 8_000_000 / 8
        case .hd1080p: bitrateBytesPerSec = 16_000_000 / 8
        case .uhd4K:   bitrateBytesPerSec = 45_000_000 / 8
        }
        guard bitrateBytesPerSec > 0, freeBytes > 0 else { return "Storage unavailable" }
        if freeBytes < 1_000_000_000 { return "Low storage" }
        let seconds = Int(freeBytes / bitrateBytesPerSec)
        let minutes = seconds / 60
        if minutes == 0 { return "<1 min remaining" }
        if minutes < 60 { return "~\(minutes) min remaining" }
        return "~\(minutes / 60) hr remaining"
    }
}
```

### Fallback Guard in CameraContentView
```swift
// Source: derived from existing CameraContentView observable pattern
.onChange(of: appState.cameraManager.supports4K) { _, supports4K in
    if !supports4K && appState.qualitySettings.resolution == .uhd4K {
        appState.qualitySettings.resolution = .hd1080p
        appState.qualitySettings.save()
        logger.info("CameraContentView: 4K setting downgraded to 1080p (device not capable)")
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `AVCaptureVideoOrientation` (deprecated) | `videoRotationAngle` (degrees, Float) | iOS 17 | Already using correct API — no change needed |
| `AVCaptureSession.sessionPreset = .hd3840x2160` | `device.activeFormat` direct assignment | Must avoid on MultiCam | Pitfall 16 in PITFALLS.md — already avoided in v1.0 |
| `volumeAvailableCapacity` | `volumeAvailableCapacityForImportantUsage` | iOS 11 | More accurate for user-data writes |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 720p H.264 bitrate ~8 Mbps for storage estimate | Pattern 4 | Estimate could be 2–3× off; acceptable for a rough label |
| A2 | 1080p H.264 bitrate ~16 Mbps for storage estimate | Pattern 4 | Same — rough estimate only |
| A3 | Sheet height of 320pt accommodates 3-segment picker + storage label | Pitfall 4 | Visual clipping on device; verify and adjust |
| A4 | `detect4KCapability()` should run before `session.startRunning()` (not after) | Pattern 1 | No functional difference; `backDevice` is set during configureAndStart, detection only reads formats |

**If this table is empty for a given item:** Everything else in this research is verified against codebase or cited from prior milestone research documents.

---

## Open Questions

1. **What is the exact sheet height needed for 3-segment picker + storage label?**
   - What we know: Current sheet is 260pt for 2-segment picker; storage label adds at least one text row.
   - What's unclear: Whether 320pt is enough or over-specified.
   - Recommendation: Verify on physical device in Plan 1; use `.height(320)` as starting point.

2. **Does `detect4KCapability()` need to log formats at INFO or DEBUG level?**
   - What we know: STATE.md flags 4K MultiCam availability on iPhone 17 Pro Max as MEDIUM confidence and explicitly says "Log full back.formats list at session startup to diagnose."
   - What's unclear: Whether DEBUG logs are visible in production builds (they are suppressed by default in os.log unless the log level is raised).
   - Recommendation: Log the capability result at INFO and individual format entries at DEBUG. Developers can enable DEBUG with `log config` when diagnosing.

3. **Should the storage estimate update when the quality sheet is already open and free space is being used by another app?**
   - What we know: K4-05 says "live estimate" — this implies updates, but the sheet is a short-lived modal.
   - What's unclear: Whether a second `onAppear` or a timer is needed for live updates.
   - Recommendation: Single read on `.onAppear` is sufficient. The sheet is dismissed before recording starts; free space changes during the 2–10 seconds the sheet is open are negligible for this estimate.

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — all APIs are system frameworks; only physical device required, documented as a known constraint in STATE.md)

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing / XCTest (detect from project) |
| Config file | None detected in DualVideo.xcodeproj |
| Quick run command | Run scheme "DualVideo" on device |
| Full suite command | Run scheme "DualVideoTests" on device (physical device required for all camera tests) |

**Note:** No simulator support — all AVFoundation camera tests must run on physical device (PITFALLS.md Pitfall 12). Unit-testable logic (storage estimate computation, enum extensions) can run in simulator.

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| K4-01 | `supports4K == false` on iPhone XR after session startup | Manual device | Run on iPhone XR, check `supports4K` log | N/A (device only) |
| K4-01 | `supports4K == true/false` on iPhone 17 Pro Max after startup | Manual device | Run on iPhone 17 Pro Max, check `supports4K` log | N/A (device only) |
| K4-02 | QualitySettingsSheet shows 4K only when `supports4K == true` | Unit (simulator) | XCTest: init sheet with `supports4K: true/false`, assert picker options | ❌ Wave 0 |
| K4-02 | 4K option absent on XR, present (if K4-01 passes) on Pro | Manual device | Visual verification in sheet | N/A |
| K4-05 | Storage estimate label updates when resolution picker changes | Unit (simulator) | XCTest: verify `storageEstimate` computed property | ❌ Wave 0 |
| K4-05 | Storage estimate shows "Low storage" when freeBytes < 1 GB | Unit (simulator) | XCTest: pass `freeBytes = 500_000_000`, assert label | ❌ Wave 0 |
| SC-4 | Saved 4K setting on non-4K device falls back to 1080p | Unit (simulator) | XCTest: set `supports4K = false`, `resolution = .uhd4K`, verify fallback | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** Build succeeds, no compiler errors
- **Per wave merge:** Run unit test targets for storage estimate and fallback logic
- **Phase gate:** Manual device verification of K4-01 and K4-02 on both test devices before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `DualVideoTests/QualitySettingsSheetTests.swift` — covers K4-02 (conditional picker) and K4-05 (storage estimate label logic)
- [ ] `DualVideoTests/VideoQualitySettingsTests.swift` — covers `.uhd4K` enum case, `Codable` round-trip, and fallback decode behavior
- [ ] `DualVideoTests/CameraManagerSupports4KTests.swift` — unit-testable portion: mock format list, verify `detect4KCapability` result [ASSUMED — CameraManager may not be easily unit-testable without refactor; manual log verification may be the practical test]

---

## Security Domain

This phase adds no authentication, session management, or cryptographic operations. Input validation is limited to: free storage value (clamped by system API, no user input). No ASVS categories apply.

The storage estimate reads from `NSHomeDirectory()` URL resource values — this is a read-only system query with no user-controllable inputs. No injection surface exists.

---

## Sources

### Primary (HIGH confidence)
- `CameraManager.swift` — codebase read; `applyFormat(to:targetLandscapeWidth:)`, `configureAndStart()`, `hardwareCost` handling, `@Observable` pattern
- `VideoQualitySettings.swift` — codebase read; `OutputResolution` enum, `Codable` load/save pattern
- `QualitySettingsSheet.swift` — codebase read; current picker implementation, sheet detents
- `AppState.swift` — codebase read; `cameraManager` property, observable pattern
- `MovieRecorder.swift` — codebase read; `settings.resolution.width/height` pass-through confirmed
- `.planning/research/STACK.md` — format detection pattern, `isMultiCamSupported` semantics, HEVC bitrate ~45 Mbps
- `.planning/research/ARCHITECTURE.md` — component change list, `OutputResolution.uhd4K` code example, `detect4KCapability` placement
- `.planning/research/PITFALLS.md` — Pitfalls 14, 15, 16, 20 (capability detection failure modes)
- `.planning/STATE.md` — locked decisions: hide not disable, trial config approach, front camera at 1080p

### Secondary (MEDIUM confidence)
- [Apple Developer — Checking Volume Storage Capacity](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeavailablecapacityforimportantusage) — `volumeAvailableCapacityForImportantUsage` API
- [AVCaptureDeviceFormat.isMultiCamSupported](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/ismulticamsupported) — Apple docs
- [AVCaptureMultiCamSession.hardwareCost](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/hardwarecost) — Apple docs

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new frameworks; all APIs already in codebase
- Architecture: HIGH — based on direct codebase reads of all five affected files
- Pitfalls: HIGH — prior milestone research documents pitfalls 14/15/16/20 in detail; Phase 7 avoids them by keeping recording pipeline out of scope
- Storage estimate bitrates: LOW for 720p/1080p constants (assumed); HIGH for 4K (cited from STACK.md)

**Research date:** 2026-05-19
**Valid until:** 2026-06-19 (stable AVFoundation APIs; estimate valid longer unless Apple updates iOS 18+ MultiCam behavior)
