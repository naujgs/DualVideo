---
phase: 02-recording-pipeline-compositor-writer-audio
reviewed: 2026-05-17T00:00:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - DualVideo/Features/Recording/PiPCompositor.swift
  - DualVideo/Features/Recording/MovieRecorder.swift
  - DualVideo/Features/Recording/RecordingManager.swift
  - DualVideo/Features/Recording/UI/RecordButton.swift
  - DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift
  - DualVideo/Features/Camera/CameraManager.swift
  - DualVideo/Shared/AppState.swift
  - DualVideo/Features/Camera/CameraContentView.swift
findings:
  critical: 1
  warning: 4
  info: 2
  total: 7
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-05-17
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

The Phase 2 recording pipeline is well-structured. The threading model is coherent: `nonisolated(unsafe)` is used consistently for AVFoundation state that is manually serialized on `dataOutputQueue` or `sessionQueue`, and the reasoning is documented. The AVAssetWriter state machine correctly defers `startSession()` to the first sample PTS. The background-task guard in `stopRecording` is a good safety net.

Four issues require attention before shipping: one critical (UIKit API called on a background thread), two highs (a use-after-cancel memory/resource leak in the background-expiry handler, and a missing pixel-buffer pool handoff that causes per-frame heap allocation throughout recording), and one medium (the `audioAdded` flag tests an insufficient condition). Two additional warnings and two informational items are noted below.

---

## Critical Issues

### CR-01: `UIScreen.main` accessed on `dataOutputQueue` (background thread)

**File:** `DualVideo/Features/Recording/PiPCompositor.swift:195-196`

**Issue:** `captureOutput(_:didOutput:from:)` is marked `nonisolated` and is called by AVFoundation on `dataOutputQueue` — a background serial queue. Lines 195-196 read `UIScreen.main.bounds.width` and `UIScreen.main.scale` directly inside that callback. `UIScreen.main` is a `@MainActor`-isolated API on iOS 16+. Accessing it off the main thread is undefined behaviour and triggers a `UIKit accessed from background thread` runtime warning (and occasionally a crash) in iOS 17/18.

**Fix:** Cache the screen metrics on the main thread and store them as a `nonisolated(unsafe)` snapshot on `PiPCompositor`, updated the same way `pipOffsetSnapshot` is:

```swift
// PiPCompositor — add alongside pipOffsetSnapshot
nonisolated(unsafe) private(set) var screenMetricsSnapshot: (width: CGFloat, scale: CGFloat) = (390, 3)

@MainActor
func updateScreenMetrics() {
    let s = UIScreen.main
    screenMetricsSnapshot = (s.bounds.width, s.scale)
}
```

Call `updateScreenMetrics()` from `CameraContentView.onAppear` (already has a main-thread context) and whenever `geo.size` changes. Replace the two `UIScreen.main` reads in `captureOutput` with `screenMetricsSnapshot.width` and `screenMetricsSnapshot.scale`.

---

## Warnings

### WR-01: Background-task expiry handler calls `cancelAndDiscard()` without ending the background task

**File:** `DualVideo/Features/Recording/RecordingManager.swift:135-140`

**Issue:** When the OS triggers the background-task expiry handler (lines 135-140), `cancelAndDiscard()` is called and `UIApplication.shared.endBackgroundTask(.invalid)` is invoked. The argument `.invalid` is wrong — the system expects the token that was returned by `beginBackgroundTask`, which is `bgTask`. Passing `.invalid` means the OS never receives the end signal for that task, which keeps the background assertion alive until the process is suspended and can trigger a watchdog kill.

```swift
// Current (line 139) — wrong token:
UIApplication.shared.endBackgroundTask(.invalid)

// Fix — use the captured token:
UIApplication.shared.endBackgroundTask(bgTask)
```

Note: `bgTask` is already in scope via the closure capture list (it is declared on line 135 and the expiry block is a closure that closes over it).

### WR-02: Pixel-buffer pool is never handed off from `MovieRecorder` to `PiPCompositor`

**File:** `DualVideo/Features/Recording/MovieRecorder.swift:73-101` / `DualVideo/Features/Recording/RecordingManager.swift`

**Issue:** `PiPCompositor.pixelBufferPool` is designed to receive the pool from `AVAssetWriterInputPixelBufferAdaptor` after `startWriting()` is called. `MovieRecorder.startRecording()` creates the adaptor (line 73) and calls `w.startWriting()` (line 96), but never assigns `adaptor.pixelBufferPool` to `compositor.pixelBufferPool`. As a result, `acquireOutputBuffer()` in `PiPCompositor` always falls through to `allocateFallbackBuffer()`, allocating a new `CVPixelBuffer` on the heap for every composited frame at 30 fps. This is a correctness issue (the pool path is dead code) and a heap-churn issue that will show up under Instruments as constant allocation pressure.

**Fix:** After `startRecording()` sets up the writer, pass the pool to the compositor. Since `RecordingManager` owns both objects, the cleanest place is inside `wireCompositor(_:)` or by having `MovieRecorder` expose a callback:

```swift
// In RecordingManager.startRecording(), after recorder.startRecording():
if let pool = recorder.adaptor?.pixelBufferPool,
   let compositor = /* reference to compositor */ {
    compositor.pixelBufferPool = pool
}
```

`RecordingManager` needs a reference to the compositor (it already calls `wireCompositor` which receives one). Store it as `nonisolated(unsafe) private weak var compositor: PiPCompositor?` and assign during `wireCompositor(_:)`. On `stopRecording` completion, nil it out to break the cycle.

### WR-03: `audioAdded` flag only checks `backAudioOut` connection, silently misreports front-beam failure

**File:** `DualVideo/Features/Camera/CameraManager.swift:179-212`

**Issue:** `audioAdded` is set to `true` only when the back-beam audio connection succeeds (line 190). If the back-beam succeeds but the front-beam fails, the warning on line 211-213 is never printed, and `self.frontAudioOutput` is stored pointing to a `backAudioOut`-less, connection-less output — an output that was added to the session (`addOutputWithNoConnections`, line 196) but has no live connection. That dangling output wastes session capacity and is never delegated.

More importantly: because `RecordingManager.setup` only sets a delegate on `backAudioOutput` (by design), the front-beam output being broken is silent. The warning message on line 212 ("dual-mic audio wiring failed") should fire on any partial failure:

```swift
// Replace:
if !audioAdded {
    logger.warning("CameraManager: dual-mic audio wiring failed...")
}

// With explicit checks for each beam:
if !backBeamConnected {
    logger.warning("CameraManager: back-beam audio connection failed — no audio track")
}
if !frontBeamConnected {
    logger.warning("CameraManager: front-beam audio connection failed — front beam unavailable")
}
```

Use separate `backBeamConnected` and `frontBeamConnected` booleans.

### WR-04: `stopAndFinalize` reads `writer?.status` inside `finishWriting` closure — writer may be nilled by racing `cleanup()`

**File:** `DualVideo/Features/Recording/MovieRecorder.swift:177-189`

**Issue:** The `finishWriting` completion closure (line 180) reads `self.writer?.status`. `finishWriting` calls its completion on an arbitrary background queue. If a second code path (e.g. `cancelAndDiscard`) calls `cleanup()` concurrently on `dataOutputQueue`, `writer` can be nilled between the check on line 180 and the read on line 185, producing an incorrect log entry (status reported as -1) and potentially causing `cleanup()` to run twice (writer nil'd twice, pool nil'd twice — idempotent but confusing). The correct fix is to capture `url` and a local `status` before the async boundary:

```swift
writer?.finishWriting { [weak self] in
    guard let self else { return }
    let status = self.writer?.status   // capture before cleanup
    let finalURL: URL? = (status == .completed) ? url : nil
    if status != .completed {
        logger.error("MovieRecorder: finalization failed, status=\(status?.rawValue ?? -1)")
    }
    self.cleanup()
    completion(finalURL)
}
```

Alternatively, capture `writer` as a local before the async call so cleanup cannot race it.

---

## Info

### IN-01: `RecordingManager` comment/delegate header mentions both beams but only back-beam is wired

**File:** `DualVideo/Features/Recording/RecordingManager.swift:195-196`

**Issue:** The `AVCaptureAudioDataOutputSampleBufferDelegate` extension comment says "Called on audioDelegate queue by both back and front audio outputs (D-05). Both beams go to the same recorder audio track (blended approach per D-05)." However, `setup(cameraManager:)` only sets the delegate on `backAudioOutput` (line 71). The comment is stale and will mislead future maintainers into thinking the front beam is already being forwarded.

**Fix:** Update the comment to: "Called on audioDelegate queue by the back-beam audio output only. Front-beam audio output intentionally not delegated to avoid 2x audio duration bug."

### IN-02: `cleanUpOrphanedTempFiles()` deletes all `.mov` files in the system temp directory

**File:** `DualVideo/Features/Recording/RecordingManager.swift:180-190`

**Issue:** `FileManager.default.temporaryDirectory` is shared across all apps on the device in some configurations, and on simulator it may overlap with other processes' temp usage. The cleanup removes *every* `.mov` file it finds — including files written by other processes that happened to land in the same `tmp` directory. This is not exploitable but could silently delete files that aren't ours.

**Fix:** Write files into a subdirectory unique to this app (e.g. `temporaryDirectory.appendingPathComponent("DualVideo", isDirectory: true)`) and only clean up that subdirectory. This also makes the cleanup O(1) in terms of scope.

---

_Reviewed: 2026-05-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
