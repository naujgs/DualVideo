---
phase: 01-foundation-permissions-session-live-preview
plan: "02"
subsystem: camera-session-preview
tags: [swift6, avfoundation, multicam, preview-layer, swiftui, uikit]
dependency_graph:
  requires:
    - 01-01 (AppState, AppRoute, RootView routing shell, PermissionManager)
  provides:
    - CameraActor global actor definition
    - CameraManager owning AVCaptureMultiCamSession, sessionQueue, back/front inputs and preview layers
    - CameraPreviewView UIViewRepresentable (addSublayer pattern)
    - CameraContentView with back full-bleed + front PiP layout
    - AppState extended with cameraManager property
    - RootView .camera route wired to live preview
  affects:
    - Plan 01-03: consumes CameraManager.backPreviewLayer/frontPreviewLayer, setZoom(), startSession/stopSession
tech_stack:
  added:
    - AVCaptureMultiCamSession (dual-camera session graph)
    - AVCaptureVideoPreviewLayer (hardware preview path)
    - nonisolated(unsafe) + @unchecked Sendable (Swift 6 custom-queue concurrency pattern)
    - UIViewRepresentable + UIView sublayer (SwiftUI/UIKit bridge for CALayer)
  patterns:
    - sessionQueue DispatchQueue serialization for all AVFoundation mutations
    - beginConfiguration → explicit commitConfiguration (no defer) → hardwareCost → guard
    - addSublayer (not layerClass override) for externally-owned AVCaptureVideoPreviewLayer
    - @unchecked Sendable on CameraManager for DispatchQueue-based custom synchronization
key_files:
  created:
    - DualVideo/Features/Camera/CameraActor.swift
    - DualVideo/Features/Camera/CameraManager.swift
    - DualVideo/Features/Camera/CameraPreviewView.swift
    - DualVideo/Features/Camera/CameraContentView.swift
    - DualVideoTests/UnitTests/CameraManagerTests.swift
  modified:
    - DualVideo/Shared/AppState.swift (added cameraManager property)
    - DualVideo/Features/Root/RootView.swift (replaced Text placeholder with CameraContentView)
    - DualVideo.xcodeproj/project.pbxproj (added 5 new source files to both targets)
decisions:
  - "@unchecked Sendable on CameraManager used instead of @MainActor to keep sessionQueue dispatch fully nonisolated — @MainActor would require Task { @MainActor } hops that complicate the DispatchQueue.main.sync pattern needed for preview layer session wiring before startRunning"
  - "nonisolated(unsafe) on AVFoundation stored properties (session, sessionQueue, backDevice, preview layers) — Swift 6 cannot verify these are Sendable, but correctness is guaranteed by sessionQueue serialization and the single main.sync barrier before startRunning"
  - "addSublayer chosen over layerClass override in PreviewUIView — preview layers are externally owned instances already connected to the session; layerClass requires the UIView to own creation which conflicts with the external-instance model"
  - "CameraActor defined but NOT applied to CameraManager — reserved for Phase 2 compositor work where multiple classes need shared actor isolation; CameraManager manages its own threading via sessionQueue"
metrics:
  duration: "6 minutes"
  completed: "2026-05-16T19:19:09Z"
  tasks_completed: 2
  files_created: 5
  files_modified: 3
---

# Phase 1 Plan 2: CameraManager AVCaptureMultiCamSession Graph and Live Preview Summary

**One-liner:** AVCaptureMultiCamSession with sessionQueue isolation, explicit commitConfiguration→hardwareCost guard, dual AVCaptureVideoPreviewLayer surfaces via UIViewRepresentable addSublayer bridge, and CameraContentView back-full-bleed + front-PiP layout wired into RootView.

## What Was Built

Task 1 created `CameraActor` (global actor for future Phase 2 compositor isolation), `CameraManager` (owns `AVCaptureMultiCamSession`, `sessionQueue`, `dataOutputQueue`, back/front camera inputs, data outputs, preview layer connections), and extended `AppState` with a `cameraManager` property. The session graph uses `beginConfiguration` followed by explicit per-exit-path `commitConfiguration` calls (no defer), reads `hardwareCost` only after commit, and guards startup at 0.9. Swift 6 compliance achieved via `nonisolated(unsafe)` on AVFoundation objects and `@unchecked Sendable` on `CameraManager` (custom queue serialization).

Task 2 created `CameraPreviewView` (`UIViewRepresentable` using `addSublayer` to host an externally-owned `AVCaptureVideoPreviewLayer`), `CameraContentView` (back camera full-bleed with `.ignoresSafeArea()`, front camera PiP top-right at 28% screen width per D-05), and replaced the `Text("Camera ready")` placeholder in `RootView` with `CameraContentView` wired to `startSession`/`stopSession` lifecycle.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | b2f66c3 | CameraActor, CameraManager AVCaptureMultiCamSession graph, AppState extension |
| Task 2 | 94855a9 | CameraPreviewView UIViewRepresentable and CameraContentView wired into RootView |

## Verification Results

- `xcodebuild build -scheme DualVideo -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO` → **BUILD SUCCEEDED**
- All Task 1 acceptance criteria: PASSED (sessionQueue, dataOutputQueue, beginConfiguration, no defer, explicit commitConfiguration, hardwareCost after commit, guard cost < 0.9, precondition, setZoom, zoom clamp, cameraManager in AppState, testZoomClampLower in tests)
- All Task 2 acceptance criteria: PASSED (UIViewRepresentable, PreviewUIView, layoutSubviews, addSublayer, backPreviewLayer/frontPreviewLayer in CameraContentView, ignoresSafeArea, 28% pipWidth, topTrailing, CameraContentView in RootView, onAppear startSession)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 concurrency errors: `sending 'self' risks causing data races`**
- **Found during:** Task 1 verification (first build attempt)
- **Issue:** The plan's CameraManager code pattern used `DispatchQueue.main.async { self.property = value }` inside `sessionQueue.async` closures. Swift 6 strict concurrency rejects sending a non-`Sendable` `self` into a main-actor-isolated closure from a non-isolated context.
- **Attempted fix 1:** Made CameraManager `@MainActor` with `nonisolated` methods — failed because `AVCaptureMultiCamSession` is not `Sendable` and cannot exit `nonisolated` context.
- **Fix applied:** Added `nonisolated(unsafe)` to all AVFoundation stored properties (manually serialized via `sessionQueue`) and marked `CameraManager: @unchecked Sendable` (custom synchronization via `DispatchQueue`). This is the standard Swift 6 pattern for classes using explicit queue-based synchronization.
- **Files modified:** `DualVideo/Features/Camera/CameraManager.swift`
- **Commit:** b2f66c3

**2. [Rule 3 - Blocking] CameraPreviewView and CameraContentView added to project.pbxproj before files existed**
- **Found during:** First build after Task 1 commit (project file already referenced Task 2 files)
- **Issue:** Adding all new files to `project.pbxproj` in one edit (for efficiency) caused build to fail with "Build input files cannot be found" because Task 2 source files hadn't been written yet.
- **Fix:** Created CameraPreviewView.swift and CameraContentView.swift immediately before the build check.
- **Files modified:** none additional (resolved by creating the files)
- **Commit:** 94855a9

## Threat Mitigations Applied

| Threat ID | Mitigation Applied |
|-----------|-------------------|
| T-02-01 | `guard cost < 0.9` gate with `handleError()` propagation to `AppState.sessionError`; logged via `os.log` |
| T-02-02 | `precondition(!Thread.isMainThread)` inside `configureAndStart`; `sessionQueue.async` in `startSession()` |
| T-02-03 | `min(max(factor, 1.0), 3.0)` clamp in `setZoom()` before `lockForConfiguration` |
| T-02-04 | `installedLayer === layer` identity check in `PreviewUIView.setPreviewLayer()` |
| T-02-05 | Logger subsystem namespaced to `com.naujgs.DualVideo`; no PII logged |

## Known Stubs

None — all preview surfaces are wired to live `AVCaptureMultiCamSession` instances. The PiP drag position is intentionally static (top-right default per D-05); Plan 03 adds the gesture layer.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check: PASSED

All 5 created files confirmed present on disk. Both commits (b2f66c3, 94855a9) confirmed in git log. Build succeeds with BUILD SUCCEEDED. All acceptance criteria verified via grep.
