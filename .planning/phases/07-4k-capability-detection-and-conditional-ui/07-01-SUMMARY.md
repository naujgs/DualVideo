---
phase: 07-4k-capability-detection-and-conditional-ui
plan: "01"
subsystem: model-layer
tags: [4k, capability-detection, enum, observable, avfoundation]
dependency_graph:
  requires: []
  provides:
    - OutputResolution.uhd4K enum case (rawValue "4K", width 2160, height 3840, landscapeWidth 3840)
    - CameraManager.supports4K observable Bool property
    - CameraManager.detect4KCapability() private method
  affects:
    - DualVideo/Features/Recording/VideoQualitySettings.swift
    - DualVideo/Features/Camera/CameraManager.swift
    - DualVideoTests/UnitTests/VideoQualitySettingsTests.swift
tech_stack:
  added: []
  patterns:
    - TDD (red-green) for enum case and Codable round-trip
    - Observable property + DispatchQueue.main.async dispatch for AVFoundation→SwiftUI bridge
    - isMultiCamSupported format filter as ISP bandwidth proxy
key_files:
  created: []
  modified:
    - DualVideo/Features/Recording/VideoQualitySettings.swift
    - DualVideo/Features/Camera/CameraManager.swift
    - DualVideoTests/UnitTests/VideoQualitySettingsTests.swift
    - DualVideoTests/UnitTests/MovieRecorderTests.swift
    - DualVideoTests/UnitTests/RecordingManagerTests.swift
decisions:
  - "Use isMultiCamSupported && dims.width == 3840 as the 4K detection predicate — Apple's format whitelist is the correct ISP bandwidth proxy"
  - "Log per-format list at DEBUG level for Phase 8 device validation on iPhone 17 Pro Max"
  - "detect4KCapability() called after commitConfiguration() and before startRunning() — only point where backDevice is confirmed set and session state is stable"
metrics:
  duration_minutes: 90
  completed_date: "2026-05-19"
  tasks_completed: 2
  files_changed: 5
---

# Phase 7 Plan 01: 4K Model Layer — uhd4K enum case + CameraManager capability detection

One-liner: Added `OutputResolution.uhd4K = "4K"` enum case and `CameraManager.supports4K` observable property with `detect4KCapability()` format-based detection on session startup.

## Tasks Completed

| # | Name | Commit | Type | Files |
|---|------|--------|------|-------|
| 1 | Add OutputResolution.uhd4K and extend tests | 100bd9c | feat (GREEN) | VideoQualitySettings.swift, VideoQualitySettingsTests.swift |
| RED | Failing tests first | 79b45ec | test | VideoQualitySettingsTests.swift |
| 2 | Add supports4K + detect4KCapability() | 15ebbcc | feat | CameraManager.swift |

## Success Criteria Verification

- `OutputResolution.allCases` contains exactly 3 cases: `.hd720p`, `.hd1080p`, `.uhd4K` — PASS (allCasesCountIsThree test)
- `OutputResolution.uhd4K.rawValue` is `"4K"`, `.landscapeWidth` is `3840` — PASS
- `CameraManager` has `var supports4K: Bool = false` observable property — PASS
- `detect4KCapability()` called in `configureAndStart()` before `session.startRunning()` — PASS
- 7 new test cases pass — PASS (uhd4KRawValue, uhd4KWidth, uhd4KHeight, uhd4KLandscapeWidth, allCasesCountIsThree, uhd4KRoundTrip, unknownResolutionRawValueFallsBackToDefault)
- Zero compiler errors or warnings introduced — PASS (BUILD SUCCEEDED)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pre-existing `bitrate:` parameter in MovieRecorderTests and RecordingManagerTests**
- **Found during:** Task 1 — test compilation phase
- **Issue:** `VideoQualitySettings(resolution:bitrate:)` calls in `MovieRecorderTests.swift` (lines 86, 113) and `RecordingManagerTests.swift` (line 52) referenced a `bitrate` parameter that was removed from the struct in a prior phase. These caused the entire test target to fail to compile, blocking verification of the new uhd4K tests.
- **Fix:** Removed `bitrate:` argument from all three call sites; the struct initializer uses `resolution:` and `frameRate:` only.
- **Files modified:** `DualVideoTests/UnitTests/MovieRecorderTests.swift`, `DualVideoTests/UnitTests/RecordingManagerTests.swift`
- **Commit:** 100bd9c (included in GREEN commit)

**Note:** The same stale `bitrate:` references existed in the main repo working tree (separate from the worktree). Those were also fixed as a side-effect of investigating where the tests were running.

## Known Stubs

None. Both new properties are fully implemented: `uhd4K` has correct computed values, `supports4K` is set by real AVFoundation format inspection at session startup.

## Threat Flags

None. All changes are internal app model-layer only — no new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries. The `detect4KCapability()` DEBUG logs contain only hardware capability facts (format dimensions, Bool), no PII.

## Self-Check

- [x] `DualVideo/Features/Recording/VideoQualitySettings.swift` — contains `case uhd4K = "4K"`
- [x] `DualVideo/Features/Camera/CameraManager.swift` — contains `var supports4K: Bool = false` and `detect4KCapability()`
- [x] `DualVideoTests/UnitTests/VideoQualitySettingsTests.swift` — contains all 7 new test cases
- [x] Commits exist: 79b45ec (RED), 100bd9c (GREEN), 15ebbcc (Task 2)
- [x] BUILD SUCCEEDED
- [x] All 17 tests in OutputResolutionTests + VideoQualitySettingsTests pass

## Self-Check: PASSED
