---
phase: 02-recording-pipeline-compositor-writer-audio
plan: "02"
subsystem: recording
tags: [avfoundation, avassetwriter, swiftui, recording-ui, state-machine, tdd, swift6]
dependency_graph:
  requires:
    - DualVideo/Features/Recording/PiPCompositor.swift
    - DualVideo/Shared/AppState.swift
    - DualVideo/Features/Camera/CameraContentView.swift
    - DualVideo/Features/Camera/CameraManager.swift
  provides:
    - DualVideo/Features/Recording/MovieRecorder.swift
    - DualVideo/Features/Recording/RecordingManager.swift
    - DualVideo/Features/Recording/UI/RecordButton.swift
    - DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift
  affects:
    - DualVideo/Shared/AppState.swift
    - DualVideo/Features/Camera/CameraContentView.swift
    - DualVideo/Features/Root/RootView.swift
    - DualVideoTests/UnitTests/MovieRecorderTests.swift
    - DualVideoTests/UnitTests/RecordingManagerTests.swift
tech_stack:
  added:
    - AVAssetWriter (H.264 video + AAC audio, 1080p .mov)
    - AVAssetWriterInputPixelBufferAdaptor (CVPixelBuffer append path)
  patterns:
    - nonisolated(unsafe) state machine serialized on dataOutputQueue
    - @Observable RecordingManager with Task-based elapsed timer
    - startSession(atSourceTime:) deferred to first sample PTS (Pitfall 3 guard)
    - isReadyForMoreMediaData guard before every append
    - cancelWriting() guard when stop called before first frame (Pitfall 6)
key_files:
  created:
    - DualVideo/Features/Recording/MovieRecorder.swift
    - DualVideo/Features/Recording/RecordingManager.swift
    - DualVideo/Features/Recording/UI/RecordButton.swift
    - DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift
    - DualVideoTests/UnitTests/MovieRecorderTests.swift
    - DualVideoTests/UnitTests/RecordingManagerTests.swift
  modified:
    - DualVideo/Shared/AppState.swift
    - DualVideo/Features/Camera/CameraContentView.swift
    - DualVideo/Features/Root/RootView.swift
    - DualVideo.xcodeproj/project.pbxproj
decisions:
  - "UI files (RecordButton, RecordingStatusOverlay) created in Task 1 to fix build error — pbxproj referenced them before they existed on disk"
  - "RecordingManagerTests marked @MainActor — startRecording/stopRecording are @MainActor and must be called from main in test context"
  - "advanceClock(by:) and injectMockStopURL(_:) added as test-only hooks to avoid AVAssetWriter dependency in unit tests"
  - "stopAndFinalize guards state == .starting with cancelWriting() (Pitfall 6: finishWriting before startWriting)"
metrics:
  duration: "~10 minutes"
  completed: "2026-05-17"
  tasks: 2
  files: 10
---

# Phase 02 Plan 02: MovieRecorder + RecordingManager + Recording UI Summary

One-liner: AVAssetWriter state machine (idle/starting/recording/finalizing) with @Observable RecordingManager coordinator, bottom-center RecordButton (D-02), and blinking-dot MM:SS RecordingStatusOverlay (D-03) wired into CameraContentView.

## What Was Built

### MovieRecorder — AVAssetWriter State Machine

`MovieRecorder` is the write engine. It owns `AVAssetWriter`, video `AVAssetWriterInput` (H.264 1080p 10Mbps), audio `AVAssetWriterInput` (AAC 44.1kHz stereo 128kbps), and an `AVAssetWriterInputPixelBufferAdaptor` for pixel buffer appends.

**State machine:** `idle → starting → recording → finalizing → idle`

**Key guards implemented (all plan must_haves honored):**

| Guard | Location | Purpose |
|-------|----------|---------|
| `startSession(atSourceTime: pts)` deferred to first sample | `appendVideoBuffer` | Pitfall 3: use actual PTS, not .zero |
| `isReadyForMoreMediaData` before every append | `appendVideoBuffer`, `appendAudioBuffer` | Prevents buffer overflow crash |
| `writer.status == .writing` before every append | `appendVideoBuffer`, `appendAudioBuffer` | Detects writer failure early |
| `cancelWriting()` if stop before first frame | `stopAndFinalize` | Pitfall 6: never call finishWriting before startSession |
| `guard state == .idle` in `startRecording()` | `startRecording` | Prevents double-start crash |

**`nonisolated(unsafe)` pattern:** All AVFoundation objects (`writer`, `videoInput`, `audioInput`, `adaptor`, `outputURL`, `state`) are `nonisolated(unsafe)` — serialized on `dataOutputQueue`, consistent with `CameraManager` threading model.

### RecordingManager — Phase Coordinator

`RecordingManager` is the `@Observable` coordinator owned by `AppState`. It exposes:

| Property | Type | Description |
|----------|------|-------------|
| `phase` | `RecordingPhase` | `.idle` / `.recording(startedAt:)` / `.finalizing` |
| `elapsedSeconds` | `Int` | Seconds since recording started (updated by Task-based timer) |
| `pendingFileURL` | `URL?` | Set after successful finalization |

**Elapsed timer:** `Task { @MainActor }` that sleeps 1 second per iteration and computes `Date().timeIntervalSince(startDate)` — avoids timer drift. Cancelled in `stopRecording()`.

**Compositor wiring:** `wireCompositor(_:)` sets `compositor.onComposited` closure to forward pixel buffers to `MovieRecorder.appendVideoBuffer` on `dataOutputQueue`. Called by Plan 02-03 after compositor delegates are set.

### Recording UI

**RecordButton (D-02):** 72pt circle with 3pt white stroke ring. Inner shape: red filled circle (idle) or white rounded-square (recording). Disabled + 50% opacity during `.finalizing`. `accessibilityLabel` switches between "Start Recording" and "Stop Recording". Eased 0.2s shape transition.

**RecordingStatusOverlay (D-03):** Blinking red dot (10pt, `easeInOut(0.6s)` repeating toggle) + monospaced bold MM:SS text. `ultraThinMaterial` capsule background. No border, no full-screen overlay.

**CameraContentView:** Added `recordingManager: RecordingManager` parameter. ZStack additions:
- Recording overlay: conditionally visible (`if case .recording = recordingManager.phase`) at top with `.transition(.opacity)`
- RecordButton: always visible at bottom-center, padded above home indicator

**RootView:** Updated `CameraContentView(...)` call site to pass `appState.recordingManager`.

### AppState

Added `var recordingManager: RecordingManager = RecordingManager()`.

## Test Results

| Suite | Tests | Result |
|-------|-------|--------|
| `MovieRecorderTests` | 4/4 | PASSED |
| `RecordingManagerTests` | 5/5 | PASSED |
| All prior tests (PiPCompositorTests, ZoomClamp, PiPDrag, Camera, Permission, Capability) | 18/18 | PASSED |
| **Total** | **27/27** | **ALL PASSED** |

**Build:** `xcodebuild build -scheme DualVideo` exits 0. Swift 6 strict concurrency — clean.

## Checkpoint Status

Task 3 is `checkpoint:human-verify` (blocking) — requires physical iPhone XR to validate:
- Record/Stop button renders and toggles correctly
- Blinking red dot + MM:SS timer appear/disappear on tap
- AVAssetWriter logs show "writer started", "session started at PTS", "finalization complete"
- No crash on Record → Stop cycle

This checkpoint must be approved by the user before Plan 02-03 proceeds.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] UI files created in Task 1 to unblock build**
- **Found during:** Task 1 first build attempt
- **Issue:** `project.pbxproj` was updated to reference `RecordButton.swift` and `RecordingStatusOverlay.swift` (needed for Sources build phase registration), but xcodebuild errored: "Build input files cannot be found". The plan staged UI file creation in Task 2, but the pbxproj addition in Task 1 caused an immediate build failure.
- **Fix:** Created `RecordButton.swift` and `RecordingStatusOverlay.swift` with their full final implementation during Task 1 instead of Task 2. Task 2 then only needed to update `CameraContentView.swift` and `RootView.swift`.
- **Impact:** None — same files, same content, earlier creation. Task 2 commit still covers the CameraContentView wiring.
- **Files modified:** `DualVideo/Features/Recording/UI/RecordButton.swift`, `DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift`
- **Commit:** 9a7579b (included in Task 1 commit)

**2. [Rule 2 - Missing critical functionality] @MainActor on RecordingManagerTests**
- **Found during:** Task 1 test writing (anticipating Swift 6 pattern from 02-01 deviation)
- **Issue:** `startRecording()` and `stopRecording()` are `@MainActor` methods. Calling them from a non-isolated XCTestCase synchronous context would cause a Swift 6 error.
- **Fix:** Added `@MainActor` to `final class RecordingManagerTests` — same fix applied in Plan 02-01 for `PiPCompositorTests`. XCTest runs on main thread at runtime; annotation is correct.
- **Files modified:** `DualVideoTests/UnitTests/RecordingManagerTests.swift`

## Known Stubs

None. All files are fully implemented for their defined scope.

- `wireCompositor(_:)` in RecordingManager is complete but not yet called — Plan 02-03 calls it after CameraManager wires the compositor delegates. This is intentional deferred wiring, not a stub.
- `appendAudioBuffer(_:)` in RecordingManager is complete but not yet called — Plan 02-03 wires the `AVCaptureAudioDataOutput` delegate. Intentional.

## Threat Flags

No new trust boundaries beyond the plan's threat model. All four STRIDE threats (T-02-02-01 through T-02-02-04) are mitigated as planned:

- T-02-02-02: `isReadyForMoreMediaData && w.status == .writing` guards present — verified by grep
- T-02-02-03: `cancelWriting()` on `.starting` state in `stopAndFinalize` — implemented and covered by `testDoubleStartDoesNotCrash`
- T-02-02-04: `timerTask?.cancel()` in `stopRecording()`, Task checks `Task.isCancelled` — implemented

T-02-02-01 (orphaned temp .mov cleanup) deferred to Plan 02-03 startup hook as planned.

## Self-Check: PASSED

- `DualVideo/Features/Recording/MovieRecorder.swift` — FOUND
- `DualVideo/Features/Recording/RecordingManager.swift` — FOUND
- `DualVideo/Features/Recording/UI/RecordButton.swift` — FOUND
- `DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift` — FOUND
- `DualVideoTests/UnitTests/MovieRecorderTests.swift` — FOUND
- `DualVideoTests/UnitTests/RecordingManagerTests.swift` — FOUND
- Task 1 commit 9a7579b — present in git log
- Task 2 commit 40362a6 — present in git log
- `grep "startSession(atSourceTime: pts)"` — VERIFIED (1 match)
- `grep "isReadyForMoreMediaData"` — VERIFIED (2 matches: video + audio)
- `grep "expectsMediaDataInRealTime = true"` — VERIFIED (2 matches)
- All 27 tests pass — VERIFIED
- `xcodebuild build` exits 0 — VERIFIED
