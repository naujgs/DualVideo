---
phase: 02-recording-pipeline-compositor-writer-audio
plan: "03"
subsystem: recording
tags: [avfoundation, compositor-wiring, dual-mic, interruption-resilience, background-task, swift6, avsession]
dependency_graph:
  requires:
    - DualVideo/Features/Recording/PiPCompositor.swift
    - DualVideo/Features/Recording/RecordingManager.swift
    - DualVideo/Features/Recording/MovieRecorder.swift
    - DualVideo/Features/Camera/CameraManager.swift
    - DualVideo/Shared/AppState.swift
    - DualVideo/Features/Camera/CameraContentView.swift
  provides:
    - End-to-end recording pipeline: frames -> compositor -> recorder -> .mov
    - Dual-mic audio capture (back-beam + front-beam) wired to RecordingManager
    - Interruption resilience: auto-stop on background/phone-call with background task
    - Orphaned temp .mov cleanup on app launch (ASVS T-02-03-01)
  affects:
    - DualVideoTests/UnitTests/MovieRecorderTests.swift
tech_stack:
  added:
    - UIApplication.beginBackgroundTask (background finalization, D-06)
    - AVCaptureAudioDataOutputSampleBufferDelegate (RecordingManager audio delegate)
    - NotificationCenter interruption observers (UIApplication.didEnterBackgroundNotification + AVCaptureSession.wasInterruptedNotification)
  patterns:
    - Stored property promotion (backVideoOutput/frontVideoOutput from local to stored)
    - NSObject inheritance for AVCaptureAudioDataOutputSampleBufferDelegate conformance
    - @unchecked Sendable on RecordingManager (established pattern from CameraManager)
    - onChange(of: isSessionRunning) for deferred wiring after session starts
    - Dual-mic inside beginConfiguration/commitConfiguration block (WWDC 2019 Session 249)
key_files:
  modified:
    - DualVideo/Features/Camera/CameraManager.swift
    - DualVideo/Features/Recording/RecordingManager.swift
    - DualVideo/Shared/AppState.swift
    - DualVideo/Features/Camera/CameraContentView.swift
    - DualVideoTests/UnitTests/MovieRecorderTests.swift
decisions:
  - "backVideoOutput/frontVideoOutput promoted from local let to stored nonisolated(unsafe) private(set) properties — required so compositor can hold weak references"
  - "RecordingManager inherits NSObject to satisfy NSObjectProtocol requirement of AVCaptureAudioDataOutputSampleBufferDelegate"
  - "RecordingManager marked @unchecked Sendable — established pattern from CameraManager; serialization enforced by queue discipline"
  - "Both audio beams route to same appendAudioBuffer call — blended approach per D-05"
  - "hardwareCost read once after commitConfiguration (includes both video and audio inputs) — single guard at 0.9 threshold"
  - "setup(cameraManager:) called from CameraContentView.onChange(isSessionRunning) — deferred until session is live"
metrics:
  duration: "~30 minutes"
  completed: "2026-05-17"
  tasks: 1
  files: 5
---

# Phase 02 Plan 03: Pipeline Wiring — Compositor, Audio, Interruption Resilience Summary

One-liner: End-to-end recording pipeline wired — PiPCompositor delegates set on both video outputs, dual-mic back/front-beam audio inputs added inside commitConfiguration block, interruption auto-stop with UIApplication.beginBackgroundTask, orphaned temp file cleanup on init.

## What Was Built

### CameraManager Changes

**Stored property promotion:** `backVideoOutput` and `frontVideoOutput` promoted from local `let` variables inside `configureAndStart()` to `nonisolated(unsafe) private(set)` stored properties. This is required so `PiPCompositor` can hold `weak var` references to them (T-02-03-04).

**New stored properties added:**
- `backAudioOutput: AVCaptureAudioDataOutput?` — back-beam audio output for dual-mic
- `frontAudioOutput: AVCaptureAudioDataOutput?` — front-beam audio output for dual-mic
- `compositor: PiPCompositor?` — set by AppState.init() before session starts
- `dataOutputQueue` promoted from `private` to internal access for audio delegate queue sharing

**Dual-mic wiring (D-05, Pattern 3):** Inside `beginConfiguration/commitConfiguration` block:
1. `AVCaptureDevice.default(for: .audio)` → single mic input
2. `session.addInputWithNoConnections(micInput)`
3. Two `AVCaptureAudioDataOutput` instances: `backAudioOut` and `frontAudioOut`
4. `addOutputWithNoConnections` for each
5. Beam port retrieval via `micInput.ports(for: .audio, sourceDeviceType:, sourceDevicePosition:)`
6. `AVCaptureConnection` added for each beam port

**Compositor delegate wiring:** After `commitConfiguration()`, if `compositor` is set:
```swift
comp.backVideoOutput = bvo
comp.frontVideoOutput = fvo
bvo.setSampleBufferDelegate(comp, queue: dataOutputQueue)
fvo.setSampleBufferDelegate(comp, queue: dataOutputQueue)
```

**hardwareCost:** Read once after `commitConfiguration()` (which includes all video + audio inputs). Single guard at `< 0.9`. Logged with precision 3.

### RecordingManager Changes

**NSObject inheritance:** Added to satisfy `NSObjectProtocol` requirement of `AVCaptureAudioDataOutputSampleBufferDelegate`. `@unchecked Sendable` added (established pattern from `CameraManager`) to resolve Swift 6 sendability errors from `NotificationCenter` closures.

**`override init()`:** Calls `super.init()` then `cleanUpOrphanedTempFiles()` (T-02-03-01).

**`cleanUpOrphanedTempFiles()`:** Scans `FileManager.default.temporaryDirectory` for `.mov` files and deletes them. Runs on every app launch to prevent orphaned temp files from prior crashes (ASVS information-disclosure mitigation).

**`setup(cameraManager:)`** `@MainActor` method that:
1. Calls `wireCompositor(compositor)` — sets `onComposited` closure to forward frames to `MovieRecorder`
2. Sets `self` as `AVCaptureAudioDataOutputSampleBufferDelegate` on both audio outputs (D-05)
3. Registers `didEnterBackgroundNotification` and `AVCaptureSession.wasInterruptedNotification` observers calling `handleInterruption()` (D-06)

**`stopRecording()` with background task (T-02-03-02, D-06):**
```swift
let bgTask = UIApplication.shared.beginBackgroundTask(withName: "finalize-recording") {
    self.recorder.cancelAndDiscard()
    UIApplication.shared.endBackgroundTask(.invalid)
}
// ... recorder.stopAndFinalize { url in
//     UIApplication.shared.endBackgroundTask(bgTask)
// }
```
Expiration handler cancels and discards to prevent corrupt partial files.

**`AVCaptureAudioDataOutputSampleBufferDelegate` extension:** `nonisolated func captureOutput(...)` forwards both back-beam and front-beam buffers to `appendAudioBuffer(_:)` — blended into the single AAC audio track (D-05).

### AppState Changes

`init()` now creates and attaches a `PiPCompositor` to `cameraManager.compositor` before `startSession()` is called. This ensures the compositor is in place when `configureAndStart()` runs.

### CameraContentView Changes

Two `.onChange` modifiers added:

1. **Session running hook:** Calls `recordingManager.setup(cameraManager:)` once when `isSessionRunning` transitions to `true`. Deferred until session is live so all outputs are committed and valid.

2. **PiP offset hook:** Forwards `pipState.offset` to `cameraManager.compositor?.updatePiPOffset(newOffset)` so the D-01 baked-position invariant is maintained — the recording reflects the live drag position.

### MovieRecorderTests Additions

**Test 5 (`testStopAndFinalizeProducesMovFile`):** Creates a recorder, starts recording, synthesizes a 1920×1080 CVPixelBuffer, appends it (triggers `startSession(atSourceTime:)`), calls `stopAndFinalize`. Uses `XCTestExpectation` with 5-second timeout. Asserts `.mov` extension and file existence. PASSED on simulator.

**Test 6 (`testCancelAndDiscardRemovesFile`):** Starts recording, captures `outputURL`, calls `cancelAndDiscard()`. Asserts `outputURL` is nil and no file exists at original URL. PASSED on simulator.

## Test Results

| Suite | Tests | Result |
|-------|-------|--------|
| `MovieRecorderTests` | 6/6 (4 existing + 2 new) | PASSED |
| `RecordingManagerTests` | 5/5 | PASSED |
| `PiPCompositorTests` | 4/4 | PASSED |
| `CameraManagerTests` | 3/3 | PASSED |
| `ZoomClampTests` | 5/5 | PASSED |
| `PiPDragClampTests` | 4/4 | PASSED |
| `PermissionManagerTests` | 1/1 | PASSED |
| `CapabilityGateTests` | 1/1 | PASSED |
| **Total** | **29/29** | **ALL PASSED** |

**Build:** `xcodebuild build -scheme DualVideo` exits 0. Swift 6 strict concurrency — clean (warnings only, no errors).

## Checkpoint Status

Task 2 is `checkpoint:human-verify` (blocking) — requires physical iPhone XR to validate:
- Both camera previews render, Record button visible
- 10-second recording produces a .mov that plays in QuickTime with audio
- PiP position baked correctly into recording (D-01)
- App backgrounding during recording auto-stops and finalizes (D-06)
- hardwareCost logged as < 0.9 before and after audio inputs

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] RecordingManager requires NSObject for AVCaptureAudioDataOutputSampleBufferDelegate**
- **Found during:** Task 1 first build attempt
- **Issue:** `AVCaptureAudioDataOutputSampleBufferDelegate` extends `NSObjectProtocol`. Conforming to it in a `final class` without `NSObject` inheritance produces: "cannot declare conformance to 'NSObjectProtocol' in Swift; should inherit 'NSObject' instead"
- **Fix:** Added `NSObject` as base class for `RecordingManager`. Added `override init()` with `super.init()` call. Added `@unchecked Sendable` (established pattern from `CameraManager`) to resolve Swift 6 sendability errors in `NotificationCenter` closures.
- **Files modified:** `DualVideo/Features/Recording/RecordingManager.swift`
- **Commit:** cb25c63

**2. [Rule 3 - Blocking] Missing AVFoundation + CoreVideo imports in MovieRecorderTests**
- **Found during:** Task 1 test run
- **Issue:** New tests use `CMTime` and `CVPixelBufferCreate` which require `import AVFoundation` and `import CoreVideo`. The existing test file only had `import XCTest`.
- **Fix:** Added `import AVFoundation` and `import CoreVideo` at top of `MovieRecorderTests.swift`.
- **Files modified:** `DualVideoTests/UnitTests/MovieRecorderTests.swift`
- **Commit:** cb25c63

**3. Minor: hardwareCost read once (not twice as plan suggested)**
- **Plan suggested:** Two separate hardwareCost reads — one after video-only commit and one after audio commit.
- **Actual:** All inputs (video + audio) are added inside a single `beginConfiguration/commitConfiguration` block, so `commitConfiguration()` is called once and `hardwareCost` is read once after. This is architecturally cleaner (single atomic configuration) and avoids the complexity of a second `beginConfiguration` block for audio only.
- **Impact:** The console will show one hardwareCost log line (not two). Both video and audio cost are included in the single reading.

## Known Stubs

None. All wiring is complete for the defined scope of this plan.

- Dual-mic audio delivery on device requires physical hardware validation (Open Question 1). The code is complete; the fallback (silent/single-beam) is already logged via `logger.warning`.
- `pixelBufferPool` on `PiPCompositor` is set by `MovieRecorder` internally via the adaptor — this wiring was established in Plan 02-01 and does not change here.

## Threat Flags

No new trust boundaries beyond the plan's threat model.

All five T-02-03 threats mitigated as planned:
- **T-02-03-01:** `cleanUpOrphanedTempFiles()` in `RecordingManager.init()` — verified by grep
- **T-02-03-02:** `beginBackgroundTask` expiration handler calls `cancelAndDiscard()` — verified by grep
- **T-02-03-03:** `appendAudioBuffer` guards `state == .recording && aInput.isReadyForMoreMediaData` before append — verified in `MovieRecorder.appendAudioBuffer`
- **T-02-03-04:** `compositor.backVideoOutput` and `compositor.frontVideoOutput` are `weak var` — verified in `PiPCompositor.swift`
- **T-02-03-05:** `hardwareCost < 0.9` guard present after `commitConfiguration()` — verified by grep

## Self-Check

- `DualVideo/Features/Camera/CameraManager.swift` modified — FOUND
- `DualVideo/Features/Recording/RecordingManager.swift` modified — FOUND
- `DualVideo/Shared/AppState.swift` modified — FOUND
- `DualVideo/Features/Camera/CameraContentView.swift` modified — FOUND
- `DualVideoTests/UnitTests/MovieRecorderTests.swift` modified — FOUND
- Task 1 commit cb25c63 — present in git log
- `grep -c "setSampleBufferDelegate" CameraManager.swift` — 2 (back + front video outputs)
- `grep "cleanUpOrphanedTempFiles" RecordingManager.swift` — match found
- `grep "didEnterBackgroundNotification" RecordingManager.swift` — match found
- `grep "beginBackgroundTask" RecordingManager.swift` — match found
- `grep "updatePiPOffset" CameraContentView.swift` — match found
- All 29 tests PASSED on iOS 18.5 simulator

## Self-Check: PASSED

---

## Device Verification Results (iPhone XR, iOS 18.7.9)

Three additional bugs were discovered and fixed during on-device testing after the executor agent completed.

### Bug 1 — Wave 3 worktree never merged to phase_2
- **Symptom:** `stop called before first frame — cancelling writer`; `url=nil` on every attempt
- **Root cause:** Cherry-pick of worktree commit `cb25c63` onto `phase_2` was never performed. `setup(cameraManager:)`, compositor wiring, and audio delegate code existed only on the worktree branch.
- **Fix:** `git cherry-pick cb25c63` → commit `099c0d8`

### Bug 2 — Audio 2× duration / slow playback / noise
- **Symptom:** Video at half speed; audio noisy; ffprobe: audio 22.22s vs video 11.11s
- **Root cause:** Both `backAudioOutput` and `frontAudioOutput` registered as delegate, each independently delivering a full sample stream to the same `AVAssetWriterInput`. 2× samples → 2× duration.
- **Fix:** Use only `backAudioOutput` as audio delegate. → commit `fb6e211`

### Bug 3 — Portrait recording saved as landscape
- **Symptom:** 10s portrait recording opened landscape in QuickTime
- **Root cause:** `AVCaptureVideoDataOutput` delivers raw sensor-native landscape frames (1920×1080). Compositor and writer accepted them without rotation.
- **Fix:** Set `videoRotationAngle = 90` on both video data output connections. Updated `PiPCompositor.outputWidth/Height` to 1080×1920 and `MovieRecorder` video + adaptor settings to 1080×1920. → commit `2d29a0e`

### Checkpoint Results

| # | Test | Result |
|---|------|--------|
| 1 | Basic 10s recording, non-nil URL | ✅ PASS |
| 2 | Audio present, clean | ✅ PASS |
| 3 | Portrait orientation | ✅ PASS |
| 4 | PiP inset baked into recording | ✅ PASS |
| 5 | hardwareCost = 0.667 (< 0.9) | ✅ PASS |
| 6 | Interruption: Home button auto-stops, non-nil URL | ✅ PASS |
