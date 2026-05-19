---
phase: 07-4k-capability-detection-and-conditional-ui
plan: 02
subsystem: ui
tags: [swiftui, avfoundation, 4k, quality-settings, storage-estimate]

# Dependency graph
requires:
  - phase: 07-4k-capability-detection-and-conditional-ui plan 01
    provides: OutputResolution.uhd4K enum case, CameraManager.supports4K Bool property

provides:
  - QualitySettingsSheet with supports4K parameter that hides .uhd4K picker segment on non-capable hardware
  - storageEstimate computed property showing recording time remaining based on free disk space and resolution bitrate
  - CameraContentView fallback .onChange guard that downgrades saved .uhd4K setting to .hd1080p on non-capable devices
  - Unit tests for picker filter logic (K4-02) and storageEstimate (K4-05)

affects:
  - future quality settings UI changes
  - any phase modifying CameraContentView sheet presentation

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Hide unavailable options from picker (not disable) per Apple HIG — filter OutputResolution.allCases"
    - "Storage query via volumeAvailableCapacityForImportantUsageKey in .onAppear, stored in @State freeBytes"
    - "Defensive .onChange(of: supports4K) guard to downgrade persisted .uhd4K setting on non-capable hardware"

key-files:
  created:
    - DualVideoTests/UnitTests/QualitySettingsSheetTests.swift
  modified:
    - DualVideo/Features/Recording/UI/QualitySettingsSheet.swift
    - DualVideo/Features/Camera/CameraContentView.swift

key-decisions:
  - "Hide .uhd4K from picker (not disable) on non-capable hardware — per Apple HIG; avoids confusion from greyed-out option"
  - "Sheet detent increased to .height(320) from 260 to accommodate storage estimate label below picker"
  - "storageEstimate uses 8/16/45 Mbps bitrate constants for 720p/1080p/4K with <1 GB low-storage threshold"
  - "freeBytes loaded in .onAppear via volumeAvailableCapacityForImportantUsageKey — OS accounts for reserves"

patterns-established:
  - "Pattern: free storage query via URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])"
  - "Pattern: .onChange(of: capability) downgrade guard for persisted enum values that may be stale on restore"

requirements-completed: [K4-02, K4-05]

# Metrics
duration: 8min
completed: 2026-05-19
---

# Phase 7 Plan 02: 4K Conditional UI Summary

**QualitySettingsSheet conditionally hides 4K option on non-capable hardware and shows live storage time-remaining estimate using volumeAvailableCapacityForImportantUsageKey**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-19T12:49:00Z
- **Completed:** 2026-05-19T12:54:51Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- QualitySettingsSheet accepts `supports4K: Bool` and filters `OutputResolution.allCases` to hide `.uhd4K` when false (K4-02)
- Storage estimate label appears below resolution picker using OS-recommended `volumeAvailableCapacityForImportantUsageKey` (K4-05)
- CameraContentView passes `appState.cameraManager.supports4K` to sheet and guards against stale `.uhd4K` persisted setting via `.onChange` fallback
- Full unit test coverage for picker filter logic and storageEstimate computed property

## Task Commits

Each task was committed atomically:

1. **Task 1: Create QualitySettingsSheetTests.swift** - `32ecfcd` (test)
2. **Task 2: Update QualitySettingsSheet** - `327c7ae` (feat)
3. **Task 3: Update CameraContentView** - `8983504` (feat)

## Files Created/Modified
- `DualVideoTests/UnitTests/QualitySettingsSheetTests.swift` - New: QualitySettingsPickerFilterTests and StorageEstimateTests suites (K4-02, K4-05)
- `DualVideo/Features/Recording/UI/QualitySettingsSheet.swift` - Added supports4K param, filtered picker ForEach, @State freeBytes, .onAppear storage query, storageEstimate computed property, .height(320) detent
- `DualVideo/Features/Camera/CameraContentView.swift` - Added supports4K: argument at call site, added fallback .onChange guard for stale .uhd4K downgrade

## Decisions Made
- Hide .uhd4K from the segmented picker (not disable) when device is not 4K-capable — matches Apple HIG guidance; disabled segments confuse users
- Sheet detent raised from .height(260) to .height(320) to accommodate the storage estimate label without clipping
- `storageEstimate` uses 8/16/45 Mbps bitrate constants (H.264 720p, H.264 1080p, HEVC 4K) and treats < 1 GB as "Low storage"

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered
- After Task 2 was applied (adds `supports4K:` parameter), the build reported a type-check error at CameraContentView line 44 (`min(max(...))`) rather than the expected "missing argument" error. This is a Swift compiler artifact: when the call site has type errors, the compiler sometimes reports type-check failures in nearby complex expressions. Task 3 resolved the call site and the build succeeded cleanly.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- K4-02 and K4-05 requirements satisfied
- Phase 7 plans complete: model layer (Plan 01) and conditional UI (Plan 02) both shipped
- Device testing recommended: verify 4K picker segment hidden on iPhone XR (non-capable), visible on iPhone 17 Pro Max (capable)
- Storage estimate visible after opening quality sheet on any device with sufficient free space (> 0 bytes from OS query)

---
*Phase: 07-4k-capability-detection-and-conditional-ui*
*Completed: 2026-05-19*

## Self-Check: PASSED

- FOUND: DualVideoTests/UnitTests/QualitySettingsSheetTests.swift
- FOUND: DualVideo/Features/Recording/UI/QualitySettingsSheet.swift
- FOUND: DualVideo/Features/Camera/CameraContentView.swift
- FOUND: .planning/phases/07-4k-capability-detection-and-conditional-ui/07-02-SUMMARY.md
- FOUND commit: 32ecfcd (test(07-02): QualitySettingsSheetTests)
- FOUND commit: 327c7ae (feat(07-02): QualitySettingsSheet)
- FOUND commit: 8983504 (feat(07-02): CameraContentView)
