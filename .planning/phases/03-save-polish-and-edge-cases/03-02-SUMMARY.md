---
phase: 03-save-polish-and-edge-cases
plan: "02"
subsystem: pip-overlay
tags: [pip, corner-snap, userdefaults, tdd, swift6, swiftui]

requires:
  - phase: 03-save-polish-and-edge-cases
    plan: "01"
    provides: CameraContentView with save-result alert and banner; PiPOverlayState baseline

provides:
  - PiPOverlayState.snapToNearestCorner(): spring-animates PiP to nearest of 4 corners, persists index to UserDefaults
  - PiPOverlayState.restorePersistedCorner(): restores PiP to last-used corner from UserDefaults on launch
  - UserDefaults key "pip_corner_index" (Int 0-3): persisted corner index, sanitized via switch/default
  - CameraContentView.onAppear: wired to restorePersistedCorner with current GeometryReader geometry
  - PiPSnapTests.swift: 6 unit tests covering all 4 quadrant snaps, persistence, and default restore

affects:
  - 03-03-PLAN (interruption hardening — no PiP state dependencies)

tech-stack:
  added: [UserDefaults (pip_corner_index key), SwiftUI.withAnimation(.spring)]
  patterns:
    - "Corner offset math: xLeft = -(containerWidth - pipWidth - 2*margin), yBottom = containerHeight - safeTop - safeBottom - pipHeight - 2*margin"
    - "euclidean() helper for nearest-corner distance comparison"
    - "UserDefaults.standard.integer(forKey:) / set(_:forKey:) directly — no @AppStorage in @Observable class"
    - "Spring animation: .spring(response: 0.35, dampingFraction: 0.75)"

key-files:
  created:
    - DualVideoTests/UnitTests/PiPSnapTests.swift
  modified:
    - DualVideo/Features/Camera/PiPOverlayState.swift
    - DualVideo/Features/Camera/CameraContentView.swift
    - DualVideo.xcodeproj/project.pbxproj

key-decisions:
  - "Use UserDefaults.standard directly (not @AppStorage) — @AppStorage cannot be used inside @Observable class"
  - "Clamp before snap in endDrag — ensures snap candidates are within safe-area bounds before euclidean comparison"
  - "Corner index 0 (top-right) is the default, matching the existing .zero offset anchor from Phase 1"
  - "restorePersistedCorner sets offset + baseOffset directly (no animation) — avoids visible snap on launch"
  - "snapToNearestCorner uses withAnimation(.spring) — visible animated snap on drag release"

requirements-completed: [OUT-03]

duration: 11min
completed: 2026-05-17
---

# Phase 03 Plan 02: PiP Corner Snap and Persistence Summary

**PiP spring-snaps to nearest corner on drag release; corner index 0-3 persisted to UserDefaults and restored on launch via restorePersistedCorner wired into onAppear**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-05-17T19:00:41Z
- **Completed:** 2026-05-17T19:11:00Z
- **Tasks:** 2 of 3 (Task 3 is human-verify checkpoint — awaiting on-device confirmation)
- **Files modified:** 4

## Accomplishments

- `snapToNearestCorner()` implemented with euclidean nearest-corner logic, spring animation, and UserDefaults persistence
- `restorePersistedCorner()` implemented to restore offset + baseOffset from stored corner index on launch
- `endDrag()` updated to call `snapToNearestCorner()` after clamping — D-08 deferred comment replaced with real implementation
- `CameraContentView.onAppear` wired to call `restorePersistedCorner()` with current GeometryReader geometry
- 6 PiPSnapTests added and passing: all 4 quadrant snaps, index 1 restore, default (0) restore
- Full 39-test suite passes with no regressions

## Task Commits

1. **Task 1: snapToNearestCorner + restorePersistedCorner + PiPSnapTests (TDD)** - `c879fc3` (feat)
2. **Task 2: Wire restorePersistedCorner into CameraContentView.onAppear** - `96fd0bc` (feat)
3. **Task 3: On-device verification** - awaiting human checkpoint

## Files Created/Modified

- `DualVideo/Features/Camera/PiPOverlayState.swift` — added snapToNearestCorner(), restorePersistedCorner(), euclidean() helper; updated endDrag() to call snap; updated class doc comment
- `DualVideoTests/UnitTests/PiPSnapTests.swift` — 6 TDD tests covering all 4 corner quadrants, persistence, and default restore
- `DualVideo/Features/Camera/CameraContentView.swift` — onAppear wired to restorePersistedCorner()
- `DualVideo.xcodeproj/project.pbxproj` — PiPSnapTests.swift registered (1A000052/1B000052)

## Decisions Made

- `UserDefaults.standard` used directly — `@AppStorage` cannot be used inside `@Observable` class (compiler error)
- Clamp before snap in `endDrag` — the `clampedOffset()` call gates the starting position before euclidean distance comparison, keeping snapped offsets within safe-area bounds
- `restorePersistedCorner()` sets offset directly without animation (no `withAnimation`) — avoids jarring visible snap on app launch
- Corner index sanitization: `switch` with `default: .zero` handles any out-of-range UserDefaults value safely

## Deviations from Plan

None — plan executed exactly as written. All interfaces matched. No Swift 6 concurrency issues (no cross-actor boundaries in pure value/computation code).

## Known Stubs

None — corner snap is fully implemented and wired. UserDefaults persistence is real (no mock). `restorePersistedCorner` reads live UserDefaults on every `onAppear`.

## Threat Flags

None — no new network endpoints, auth paths, or trust boundary changes. UserDefaults key `pip_corner_index` is sanitized via `switch/default` in `restorePersistedCorner` as noted in the plan's threat model (T-03-02-01: accept).

## Self-Check

- [x] `DualVideoTests/UnitTests/PiPSnapTests.swift` exists (6 tests)
- [x] `c879fc3` commit exists
- [x] `96fd0bc` commit exists
- [x] `snapToNearestCorner` in PiPOverlayState.swift: 2 matches (call site + definition)
- [x] `pip_corner_index` in PiPOverlayState.swift: 1 match
- [x] `restorePersistedCorner` in CameraContentView.swift: 1 match (inside onAppear)
- [x] `D-08 deferred` in PiPOverlayState.swift: 0 matches (comment removed)
- [x] Full 39-test suite: TEST SUCCEEDED

## Self-Check: PASSED
