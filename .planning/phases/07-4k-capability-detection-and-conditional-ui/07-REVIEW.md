---
phase: 07-4k-capability-detection-and-conditional-ui
reviewed: 2026-05-19T00:00:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - DualVideo/Features/Camera/CameraContentView.swift
  - DualVideo/Features/Camera/CameraManager.swift
  - DualVideo/Features/Recording/UI/QualitySettingsSheet.swift
  - DualVideo/Features/Recording/VideoQualitySettings.swift
  - DualVideoTests/UnitTests/MovieRecorderTests.swift
  - DualVideoTests/UnitTests/QualitySettingsSheetTests.swift
  - DualVideoTests/UnitTests/RecordingManagerTests.swift
  - DualVideoTests/UnitTests/VideoQualitySettingsTests.swift
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-05-19
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Phase 7 adds 4K capability detection (`detect4KCapability`), a `supports4K` observable property on `CameraManager`, conditional hiding of the 4K option in `QualitySettingsSheet`, a storage-estimate label, and a downgrade guard in `CameraContentView`. The implementation is generally sound — threading model for `supports4K` is correct (set via `DispatchQueue.main.async`), the picker filter logic is correct, and the `onDisappear` dismiss path correctly persists settings and applies format changes.

Three warnings were found: the camera always initializes at the hardcoded 1080p default on cold start regardless of persisted user settings; `setZoom` writes an `@Observable` property without enforcing main-thread execution; and `VideoQualitySettings.save()` silently swallows encode failures with no logging. Three info items cover dead code, a weakly-asserted test, and a missing test for the hot-path that actually restores user settings at startup.

## Warnings

### WR-01: Camera always initializes at 1080p on cold start — ignores persisted user resolution

**File:** `DualVideo/Features/Camera/CameraManager.swift:421`
**Issue:** `configureAndStart()` applies the initial camera format using `VideoQualitySettings().resolution`, which always returns `.hd1080p` (the struct default). If the user has previously saved `.uhd4K` or `.hd720p`, the camera device format is set to 1080p at startup. The persisted setting is only applied when the user opens and dismisses the quality sheet (via `applyResolutionFormat` in `CameraContentView.onDismiss`). If the user never opens the sheet in a session, recording happens at 1080p regardless of their saved preference.

**Fix:** Load the persisted settings and pass the resolution into `configureAndStart`, or have `AppState` call `applyResolutionFormat` immediately after `startSession()` completes (when `isSessionRunning` becomes true).

Option A — pass resolution through:
```swift
// In configureAndStart(), replace:
let defaultResolution = VideoQualitySettings().resolution

// With:
let defaultResolution = VideoQualitySettings.load().resolution
```

Option B (preferred for consistency with existing architecture): in `CameraContentView.onChange(of: cameraManager.isSessionRunning)`, after `recordingManager.setup(cameraManager:)`, also apply the persisted format:
```swift
.onChange(of: cameraManager.isSessionRunning) { _, isRunning in
    if isRunning {
        Task { @MainActor in
            recordingManager.setup(cameraManager: cameraManager)
            // Restore persisted format after session starts
            cameraManager.applyResolutionFormat(resolution: appState.qualitySettings.resolution)
            cameraManager.applyFrameRate(appState.qualitySettings.frameRate)
        }
    }
}
```

---

### WR-02: `setZoom` writes `@Observable` property without main-actor enforcement

**File:** `DualVideo/Features/Camera/CameraManager.swift:78-80`
**Issue:** `setZoom(_ factor:)` writes `backZoomFactor = clamped` directly on the calling thread before dispatching to `sessionQueue`. All current call sites are SwiftUI gesture handlers (main thread), so there is no current crash. However, `setZoom` has no `@MainActor` annotation and no guard enforcing main-thread execution. Any future caller (e.g., a background restore path or unit test) could write the `@Observable` property off-main-thread, which is undefined behaviour under the `@Observable` macro and can cause silent corruption or crashes in Swift 6 strict concurrency checking.

**Fix:** Annotate `setZoom` with `@MainActor`:
```swift
@MainActor
func setZoom(_ factor: CGFloat) {
    let clamped = min(max(factor, 1.0), 3.0)
    backZoomFactor = clamped
    sessionQueue.async { [weak self] in
        guard let device = self?.backDevice else { return }
        // ... lockForConfiguration ...
    }
}
```
This is consistent with how `isSessionRunning`, `sessionError`, and `supports4K` are always set on the main actor via `DispatchQueue.main.async`.

---

### WR-03: `VideoQualitySettings.save()` silently swallows JSON encode failure

**File:** `DualVideo/Features/Recording/VideoQualitySettings.swift:87`
**Issue:** If `JSONEncoder().encode(self)` fails (unlikely but possible under memory pressure or if the type becomes non-encodable after a future refactor), `save()` returns silently with no log. The user's settings are not persisted, but the app shows no indication of failure. On next launch, defaults are loaded instead. This is particularly impactful for the 4K downgrade path (CameraContentView line 255), where `save()` is called after a programmatic downgrade — a silent failure there would cause the stale `.uhd4K` setting to persist across launches.

**Fix:** Add logging on encode failure:
```swift
func save() {
    guard let data = try? JSONEncoder().encode(self) else {
        // Use os.log or print — but at minimum make it visible in debug builds
        assertionFailure("VideoQualitySettings: JSONEncoder failed to encode settings — settings not saved")
        return
    }
    UserDefaults.standard.set(data, forKey: VideoQualitySettings.defaultsKey)
    UserDefaults.standard.set(frameRate.rawValue, forKey: VideoQualitySettings.frameRateDefaultsKey)
}
```

---

## Info

### IN-01: `"<1 min remaining"` branch in `storageEstimate` is unreachable dead code

**File:** `DualVideo/Features/Recording/UI/QualitySettingsSheet.swift:99`
**Issue:** The `if minutes == 0 { return "<1 min remaining" }` branch on line 99 can never execute. To reach it, `seconds < 60` is required, which means `freeBytes / bitrateBytesPerSec < 60`. For the lowest-bitrate option (720p at 1_000_000 bytes/sec), this requires `freeBytes < 60_000_000` — well below the `1_000_000_000` threshold checked on line 96, which would already return `"Low storage"`. The `QualitySettingsSheetTests.swift:lessThanOneMinuteReturnsLessThanOneMin` test explicitly documents this unreachability. The dead branch should be removed to avoid confusion.

**Fix:** Remove the unreachable branch:
```swift
private var storageEstimate: String {
    // ...
    let seconds = Int(freeBytes / bitrateBytesPerSec)
    let minutes = seconds / 60
    // minutes == 0 is unreachable: freeBytes >= 1 GB and min bitrate 1 MB/s → seconds >= 1000
    if minutes < 60 { return "~\(minutes) min remaining" }
    return "~\(minutes / 60) hr remaining"
}
```

---

### IN-02: `testLessThanOneMinuteReturnsLessThanOneMin` doesn't actually test the code path

**File:** `DualVideoTests/UnitTests/QualitySettingsSheetTests.swift:96-118`
**Issue:** The test only asserts `30 / 60 == 0` (line 115-116) — a pure arithmetic assertion with no call to the `storageEstimate` function. The comment acknowledges the branch is unreachable but the test's name implies coverage that isn't there. This can mislead future reviewers into thinking the `"<1 min remaining"` path is tested.

**Fix:** Either rename the test to make its documentation-only intent explicit, or delete it and instead add a comment in `storageEstimate` noting the unreachable branch. If the branch is removed (per IN-01), this test should be removed too.

---

### IN-03: `testStopAndFinalizeProducesMovFile` passes on simulator without verifying file output

**File:** `DualVideoTests/UnitTests/MovieRecorderTests.swift:36-63`
**Issue:** The test accepts `url == nil` as a valid outcome on line 58 ("url may be nil on simulator — acceptable; test verifies no crash"). On CI (simulator), the test always passes the `expectation.fulfill()` branch regardless of whether a file was written. The test name claims it verifies `.mov` file production, but it only guarantees no crash on non-hardware environments.

**Fix:** Either rename the test to `testStopAndFinalizeDoesNotCrash` to accurately reflect what is verified on all platforms, or add a simulator-only assertion that at least verifies the state machine progressed to a non-starting state after `stopAndFinalize`:
```swift
recorder.stopAndFinalize { url in
    // On hardware: verify file exists
    if let url = url {
        XCTAssertEqual(url.pathExtension, "mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    // On simulator: verify recorder reached a terminal state (not still in .starting)
    XCTAssertNotEqual(recorder.state, .starting, "Recorder should not be stuck in .starting after finalization")
    expectation.fulfill()
}
```

---

_Reviewed: 2026-05-19_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
