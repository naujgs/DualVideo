---
phase: 02-recording-pipeline-compositor-writer-audio
plan: "01"
subsystem: recording
tags: [compositor, core-image, pixel-buffer, tdd, swift6, avfoundation]
dependency_graph:
  requires:
    - DualVideo/Features/Camera/CameraManager.swift
    - DualVideo/Features/Camera/PiPOverlayState.swift
    - DualVideo/Features/Camera/CameraActor.swift
  provides:
    - DualVideo/Features/Recording/PiPCompositor.swift
  affects:
    - DualVideoTests/UnitTests/PiPCompositorTests.swift
tech_stack:
  added:
    - CoreImage (CISourceOverCompositing filter, CIContext Metal-backed)
    - CoreVideo (CVPixelBuffer, CVPixelBufferPool)
  patterns:
    - nonisolated(unsafe) snapshot for cross-thread state (pipOffsetSnapshot)
    - CIContext singleton — created once in init, never per frame
    - AVCaptureVideoDataOutputSampleBufferDelegate nonisolated func pattern (Swift 6)
    - @MainActor write / nonisolated(unsafe) read for PiP offset (one-directional, one-frame stale is acceptable)
key_files:
  created:
    - DualVideo/Features/Recording/PiPCompositor.swift
    - DualVideoTests/UnitTests/PiPCompositorTests.swift
  modified:
    - DualVideo.xcodeproj/project.pbxproj
decisions:
  - "CIContext created in init as a stored let — never inside composite() — prevents GPU resource exhaustion at 30fps"
  - "pipOffsetSnapshot is nonisolated(unsafe) written only @MainActor, read on dataOutputQueue — one-frame staleness acceptable"
  - "@MainActor on PiPCompositorTests class — required by Swift 6 strict concurrency since updatePiPOffset is @MainActor"
  - "UIKit import added to PiPCompositor for UIScreen access in captureOutput delegate — acceptable since UIKit is available on iOS"
metrics:
  duration: "~25 minutes"
  completed: "2026-05-17"
  tasks: 2
  files: 3
---

# Phase 02 Plan 01: PiPCompositor — Core Image Pipeline Summary

One-liner: Core Image PiP compositor using CISourceOverCompositing with a singleton CIContext, nonisolated(unsafe) offset snapshot for cross-thread safety, and full Swift 6 compliance.

## What Was Built

`PiPCompositor` is the frame-by-frame compositing engine that accepts CVPixelBuffers from both AVCaptureVideoDataOutput instances and produces a single 1920×1080 PiP CVPixelBuffer for `MovieRecorder` to append.

### API Surface

**Public methods and properties:**

| Symbol | Type | Description |
|--------|------|-------------|
| `composite(back:front:pipRect:)` | `func (CVPixelBuffer, CVPixelBuffer, CGRect) -> CVPixelBuffer?` | Composites back+front into 1920×1080 output |
| `updatePiPOffset(_:)` | `@MainActor func (CGSize)` | Updates pipOffsetSnapshot from main thread |
| `pipOffsetSnapshot` | `nonisolated(unsafe) private(set) CGSize` | Readable from any thread; written only @MainActor |
| `onComposited` | `var ((CVPixelBuffer, CMTime) -> Void)?` | Delegate callback for composited frames |
| `pixelBufferPool` | `nonisolated(unsafe) var CVPixelBufferPool?` | Set by MovieRecorder for zero-copy allocation |
| `backVideoOutput` | `nonisolated(unsafe) weak var AVCaptureVideoDataOutput?` | Identity used to route frames in delegate |
| `frontVideoOutput` | `nonisolated(unsafe) weak var AVCaptureVideoDataOutput?` | Identity used to route frames in delegate |
| `ciContextInitCount` | `private(set) var Int` | Test observability: must be 1 after init |

**Conforms to:** `AVCaptureVideoDataOutputSampleBufferDelegate` with `nonisolated func captureOutput`

### Threading Invariants Established

1. **CIContext singleton:** Created once in `init()` as a stored `let`. `ciContextInitCount` incremented exactly once. The `testCIContextCreatedOnce` test asserts this invariant.

2. **pipOffsetSnapshot cross-thread safety:** `nonisolated(unsafe) private(set)` — written only via `@MainActor func updatePiPOffset`, readable from `dataOutputQueue` without locks. One-directional write (main) → read (dataOutputQueue). One-frame staleness is visually imperceptible.

3. **captureOutput nonisolated:** Matches the Swift 6 pattern established in `CameraManager`. No actor isolation on the hot path.

4. **pixelBufferPool fallback:** When pool is nil (tests, before MovieRecorder setup), `allocateFallbackBuffer()` creates a fresh 1920×1080 BGRA buffer per call.

## Test Results

| Test | Result |
|------|--------|
| `testCompositeOutputNonNil` | PASSED |
| `testCompositeOutputDimensions` | PASSED |
| `testPiPOffsetSnapshot` | PASSED |
| `testCIContextCreatedOnce` | PASSED |

**Build:** `xcodebuild build -scheme DualVideo` exits 0. Swift 6 strict concurrency — clean.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 concurrency: @MainActor required on test class**
- **Found during:** Task 2 verification (xcodebuild test run)
- **Issue:** `PiPCompositorTests.testPiPOffsetSnapshot` called `compositor.updatePiPOffset(...)` synchronously from a non-isolated XCTestCase method. Swift 6 strict concurrency rejects calling `@MainActor` methods from non-isolated synchronous contexts.
- **Fix:** Added `@MainActor` to `final class PiPCompositorTests`. XCTest methods already run on the main thread at runtime; the annotation is correct and has no behavioral change.
- **Files modified:** `DualVideoTests/UnitTests/PiPCompositorTests.swift`
- **Commit:** 17f7785

**2. Minor deviation: UIKit import added to PiPCompositor**
- **Found during:** Task 2 implementation
- **Reason:** `captureOutput` delegate uses `UIScreen.main.bounds.width` and `UIScreen.main.scale` to convert PiP offset from UI-space to output-space. This requires `UIKit`.
- **Impact:** None — UIKit is universally available on iOS. The plan's provided implementation snippet used `UIScreen.main` without specifying the import; added `import UIKit` as necessary.
- **Files modified:** `DualVideo/Features/Recording/PiPCompositor.swift`

## Known Stubs

None. The compositor is fully functional for its defined scope. `pixelBufferPool` starts nil (tests allocate directly), which is documented and intentional — MovieRecorder (Plan 02-02) sets it after writer setup.

## Threat Flags

No new trust boundaries beyond the plan's threat model. All three STRIDE threats (T-02-01-01 through T-02-01-03) are mitigated as planned.

## Self-Check: PASSED

- `DualVideo/Features/Recording/PiPCompositor.swift` — FOUND
- `DualVideoTests/UnitTests/PiPCompositorTests.swift` — FOUND
- Task 1 commit 2c045a6 — present in git log
- Task 2 commit dfb5f7c — present in git log
- Fix commit 17f7785 — present in git log
- `grep -c "CIContext(" PiPCompositor.swift` returns 1 (init only) — VERIFIED
- All 4 PiPCompositorTests pass — VERIFIED
- `xcodebuild build` exits 0 — VERIFIED
