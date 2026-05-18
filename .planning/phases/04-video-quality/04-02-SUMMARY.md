---
phase: 04-video-quality
plan: "02"
subsystem: recording-pipeline
tags: [tdd, video-quality, avfoundation, settings-wiring, pipcompositor, movierecorder]
dependency_graph:
  requires: [VideoQualitySettings, BitratePreset, OutputResolution]
  provides: [startRecording(settings:), applyResolutionFormat(resolution:), AppState.qualitySettings]
  affects: [MovieRecorder, PiPCompositor, RecordingManager, AppState, CameraManager]
tech_stack:
  added: []
  patterns: [settings-injection at recording start, nonisolated(unsafe) instance vars for thread-safe mutation, AVCaptureDevice format filtering with isMultiCamSupported, hardwareCost post-commitConfiguration logging]
key_files:
  created: []
  modified:
    - DualVideo/Features/Recording/MovieRecorder.swift
    - DualVideo/Features/Recording/PiPCompositor.swift
    - DualVideo/Features/Recording/RecordingManager.swift
    - DualVideo/Features/Camera/CameraManager.swift
    - DualVideo/Shared/AppState.swift
    - DualVideoTests/UnitTests/MovieRecorderTests.swift
    - DualVideoTests/UnitTests/RecordingManagerTests.swift
    - DualVideoTests/UnitTests/CameraManagerTests.swift
    - DualVideoTests/UnitTests/PiPCompositorTests.swift
decisions:
  - "PiPCompositor.outputWidth/Height changed from static let to nonisolated(unsafe) var — same thread-safety pattern as existing pipOffsetSnapshot and latestBackBuffer properties in the same class"
  - "applyFormat(to:targetLandscapeWidth:) is private; applyResolutionFormat(resolution:) is public — separation keeps the lock-for-configuration details encapsulated"
  - "Inline format selection inside configureAndStart() uses synchronous applyFormat call within the existing beginConfiguration block, not a separate sessionQueue.async dispatch"
metrics:
  duration: "~18 minutes"
  completed_date: "2026-05-18"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 9
---

# Phase 04 Plan 02: VideoQualitySettings Pipeline Wiring — Summary

**One-liner:** Settings-driven recording pipeline: MovieRecorder accepts VideoQualitySettings at start time, PiPCompositor dimensions become dynamic instance vars, CameraManager selects isMultiCamSupported AVCaptureDevice formats, and AppState owns the shared settings instance loaded from UserDefaults.

## What Was Built

**MovieRecorder.swift**
- `startRecording()` signature changed to `startRecording(settings: VideoQualitySettings = VideoQualitySettings())`
- `AVAssetWriterInput` video settings now use `settings.resolution.width`, `settings.resolution.height`, `settings.bitrate.bitsPerSecond` — no hardcoded 1080/1920/10_000_000
- `AVAssetWriterInputPixelBufferAdaptor` pool attributes use `settings.resolution.width/height`
- Default parameter preserves backward compatibility with all existing call sites

**PiPCompositor.swift**
- `static let outputWidth = 1080` / `static let outputHeight = 1920` replaced with `nonisolated(unsafe) var outputWidth: Int = 1080` / `nonisolated(unsafe) var outputHeight: Int = 1920`
- All `Self.outputWidth` / `Self.outputHeight` references updated to `self.outputWidth` / `self.outputHeight` (6 sites: allocateFallbackBuffer + captureOutput delegate)
- Threading model unchanged: `nonisolated(unsafe)` is the established pattern for cross-queue properties in this file

**RecordingManager.swift**
- `startRecording()` → `startRecording(settings: VideoQualitySettings = VideoQualitySettings())`
- Sets `compositor?.outputWidth = settings.resolution.width` and `compositor?.outputHeight = settings.resolution.height` BEFORE calling `recorder.startRecording(settings:)` — ensures pool and compositor dimensions match (T-04-02-02)
- Bridges pixel buffer pool from adaptor to compositor after recorder starts (existing WR-02 pattern preserved)

**CameraManager.swift**
- New private `applyFormat(to:targetLandscapeWidth:)`: filters `device.formats` for `isMultiCamSupported && dims.width == targetLandscapeWidth`, applies via `lockForConfiguration`, logs result. Warns and keeps current format if no match found (T-04-02-01)
- New public `applyResolutionFormat(resolution:)`: dispatches to `sessionQueue`, calls `applyFormat` for backDevice and all front inputs, commits configuration, logs `hardwareCost`, errors if >= 0.9
- `configureAndStart()` applies default 1080p format inside the existing `beginConfiguration/commitConfiguration` block after inputs are added

**AppState.swift**
- Added `var qualitySettings: VideoQualitySettings = VideoQualitySettings.load()` as stored property alongside `cameraManager` and `recordingManager`

**Test files**
- `MovieRecorderTests`: 2 new tests — `testStartRecordingWith720pLowCreatesWith720x1280Adaptor` and `testStartRecordingWith1080pHighCreatesWith1080x1920Adaptor` verify pool dimensions via `CVPixelBufferPoolCreatePixelBuffer`
- `RecordingManagerTests`: 1 new test — `testStartRecordingWithSettingsUpdatesCompositorDimensions` verifies compositor.outputWidth/Height == 720/1280 after startRecording with hd720p
- `CameraManagerTests`: 1 new test — `testApplyResolutionFormatDoesNotCrashWithNoDevices` verifies graceful guard when no devices configured (simulator)
- `PiPCompositorTests`: Fixed `testCompositeOutputDimensions` to use `compositor.outputWidth/Height` (instance) instead of `PiPCompositor.outputWidth/Height` (type) — required by static→instance change

## Commits

| Hash | Description |
|------|-------------|
| b59919d | test(04-02): add failing tests for startRecording(settings:) with VideoQualitySettings (RED) |
| 3cd54d4 | feat(04-02): make MovieRecorder and PiPCompositor settings-driven (GREEN) |
| cb2962d | test(04-02): add failing tests for Task 2 settings wiring (RED) |
| 322befe | feat(04-02): wire VideoQualitySettings through AppState, RecordingManager, CameraManager (GREEN) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PiPCompositorTests used type-level access after static→instance change**
- **Found during:** Task 1, GREEN phase — compilation error on `PiPCompositor.outputWidth` and `PiPCompositor.outputHeight`
- **Issue:** Existing `testCompositeOutputDimensions` test referenced `PiPCompositor.outputWidth` as a static type member. Changing to instance vars broke this access pattern.
- **Fix:** Updated both assertions to `compositor.outputWidth` and `compositor.outputHeight` using the already-available local `compositor` instance.
- **Files modified:** `DualVideoTests/UnitTests/PiPCompositorTests.swift`
- **Commit:** 3cd54d4 (included in task commit)

**2. [Rule 3 - Blocking] Worktree reset lost plan 01 source files from staging area**
- **Found during:** Pre-execution branch verification — `git reset --soft` moved plan 01 files to staged deletions
- **Issue:** The `git reset --soft f55b4337` command staged all files from plan 01 commits (VideoQualitySettings.swift, VideoTrimManager.swift, test files, project.pbxproj) as deletions. Build failed with "cannot find 'VideoQualitySettings' in scope".
- **Fix:** Restored files via `git checkout d61aa4c -- <files>` before beginning RED phase. Planning docs restored from main repo (they were untracked, so git restore wasn't available).
- **Files modified:** None — restoration, not modification
- **Commit:** Not a separate commit — resolved before first task commit

## Known Stubs

None. All wiring is real: `VideoQualitySettings` values flow from `AppState.qualitySettings` through `RecordingManager.startRecording(settings:)` into both `PiPCompositor` dimension vars and `MovieRecorder.startRecording(settings:)` AVAssetWriter configuration. No hardcoded dimensions remain in the recording path.

## Threat Surface Scan

No new network endpoints, auth paths, or trust boundaries introduced. All changes are local to the recording pipeline. Threat mitigations implemented as specified:
- T-04-02-01: `applyFormat` filters `isMultiCamSupported`, warns if no format found, logs `hardwareCost` after commit, errors if >= 0.9
- T-04-02-02: `compositor.outputWidth/Height` set from settings BEFORE `recorder.startRecording(settings:)` — single value object, no divergence possible
- T-04-02-03: `applyResolutionFormat` is a separate public method; `configureAndStart` applies format before `startRunning` — no mid-recording format change path

## Self-Check: PASSED

| Item | Status |
|------|--------|
| DualVideo/Features/Recording/MovieRecorder.swift | FOUND |
| DualVideo/Features/Recording/PiPCompositor.swift | FOUND |
| DualVideo/Features/Recording/RecordingManager.swift | FOUND |
| DualVideo/Features/Camera/CameraManager.swift | FOUND |
| DualVideo/Shared/AppState.swift | FOUND |
| DualVideoTests/UnitTests/MovieRecorderTests.swift | FOUND |
| DualVideoTests/UnitTests/RecordingManagerTests.swift | FOUND |
| DualVideoTests/UnitTests/CameraManagerTests.swift | FOUND |
| commit b59919d | FOUND |
| commit 3cd54d4 | FOUND |
| commit cb2962d | FOUND |
| commit 322befe | FOUND |
| Full test suite | PASSED (** TEST SUCCEEDED **) |
