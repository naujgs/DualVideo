---
phase: 03-save-polish-and-edge-cases
plan: "01"
subsystem: recording
tags: [photos, photolibrary, swift6, tdd, concurrency]

requires:
  - phase: 02-recording-pipeline-compositor-writer-audio
    provides: RecordingManager with stopRecording completion, MovieRecorder producing .mov temp file

provides:
  - PhotoSaveManager: injectable PHPhotoLibrary save actor with permission re-check and temp file cleanup
  - PhotoSaveError enum (permissionDenied | saveFailed) — Equatable, propagated via saveResult
  - RecordingManager.saveResult: Result<Void, PhotoSaveError>? observable for SwiftUI bindings
  - CameraContentView: save-failure alert (Open Settings) + transient "Saved to Photos" banner
  - No share sheet anywhere in app

affects:
  - 03-02-PLAN (PiP polish — no dependencies on save flow, but shares CameraContentView)
  - 03-03-PLAN (interruption hardening — saveResult nil-reset on interrupted recording)

tech-stack:
  added: [Photos framework (PHPhotoLibrary.performChanges), nonisolated(unsafe) var in XCTest]
  patterns:
    - Testable closure injection for PHPhotoLibrary (statusProvider + performChanges)
    - "@Sendable completion dispatched via DispatchQueue.main.async for @Observable state"
    - "nonisolated(unsafe) var for XCTestExpectation result capture under Swift 6 strict concurrency"
    - "async XCTest function + withCheckedContinuation for background-dispatch main-thread verification"

key-files:
  created:
    - DualVideo/Features/Recording/PhotoSaveManager.swift
    - DualVideoTests/UnitTests/PhotoSaveManagerTests.swift
  modified:
    - DualVideo/Features/Recording/RecordingManager.swift
    - DualVideo/Features/Camera/CameraContentView.swift
    - DualVideo.xcodeproj/project.pbxproj

key-decisions:
  - "Use testable closure injection (statusProvider + performChanges) rather than subclassing PHPhotoLibrary — enables pure unit tests with no Photos entitlement on simulator"
  - "PhotoSaveError.saveFailed stores localizedDescription as String not Error — makes enum Equatable without custom conformance"
  - "completion marked @Sendable on saveVideoToPhotos to satisfy Swift 6 strict concurrency when dispatching across queues"
  - "nonisolated(unsafe) var for XCTestExpectation result capture — safe because fulfill() happens-before wait() returns"
  - "Test 4 (main-thread dispatch) uses async test + withCheckedContinuation to avoid runloop deadlock with @MainActor test class"
  - "worktree has independent DualVideo.xcodeproj/project.pbxproj — both worktree and main workspace project files updated"

patterns-established:
  - "PhotoSaveManager injection pattern: all external dependencies (status, performChanges) injectable via init for testability"
  - "Swift 6 @Sendable completion: closures crossing concurrency domains must be @Sendable; use nonisolated(unsafe) for XCTest capture"

requirements-completed: [DEV-03, OUT-01, OUT-02]

duration: 45min
completed: 2026-05-17
---

# Phase 03 Plan 01: Save Flow Summary

**PHPhotoLibrary auto-save wired end-to-end: PhotoSaveManager with injectable mocks, 4 passing tests, share sheet replaced by save-failure alert and transient success banner**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-05-17T14:53:00Z
- **Completed:** 2026-05-17T15:38:00Z
- **Tasks:** 2 of 3 (Task 3 is human-verify checkpoint — awaiting on-device confirmation)
- **Files modified:** 5

## Accomplishments

- PhotoSaveManager implemented with full closure injection for PHPhotoLibrary status and performChanges — unit-testable without real Photos access
- 4 PhotoSaveManagerTests pass: permission-denied, temp-file-deleted-on-success, temp-file-preserved-on-failure, main-thread-dispatch
- RecordingManager.saveResult observable wired from stopRecording completion via saveRecording(url:)
- ActivityView share sheet and shareURL state fully removed from CameraContentView
- Save-failure alert with "Open Settings" / "Dismiss" added; transient "Saved to Photos" banner auto-dismisses after 2.5s
- Full 33-test suite passes (29 existing + 4 new)

## Task Commits

1. **Task 1: PhotoSaveManager + RecordingManager wire** - `fe57dea` (feat)
2. **Task 2: Replace share sheet with save-result alert** - `60269b5` (feat)
3. **Task 3: On-device verification** - awaiting human checkpoint

## Files Created/Modified

- `DualVideo/Features/Recording/PhotoSaveManager.swift` — PHPhotoLibrary save actor, permissionDenied/saveFailed errors, @Sendable completion, removeItem only on success
- `DualVideoTests/UnitTests/PhotoSaveManagerTests.swift` — 4 unit tests with injected mocks, Swift 6 concurrency-safe
- `DualVideo/Features/Recording/RecordingManager.swift` — saveResult property, photoSaver instance, saveRecording(url:) method, wired into stopRecording
- `DualVideo/Features/Camera/CameraContentView.swift` — share sheet removed, .alert for failures, "Saved to Photos" banner
- `DualVideo.xcodeproj/project.pbxproj` — PhotoSaveManager + PhotoSaveManagerTests added to both worktree and main workspace project files

## Decisions Made

- Testable closure injection over PHPhotoLibrary subclassing — cleaner, no real Photos entitlement needed in simulator tests
- `PhotoSaveError.saveFailed(String)` stores `localizedDescription` as a String to keep the enum `Equatable` without custom conformance
- `@Sendable` on `saveVideoToPhotos` completion to satisfy Swift 6 strict concurrency across DispatchQueue boundaries
- `nonisolated(unsafe) var` for XCTest result capture — safe because XCTestExpectation's `fulfill()`/`wait()` provide the happens-before relationship
- Async test function with `withCheckedContinuation` for Test 4 — avoids `@MainActor` + `wait(for:timeout:)` runloop deadlock

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added @Sendable to saveVideoToPhotos completion signature**
- **Found during:** Task 1 (GREEN phase)
- **Issue:** Swift 6 strict concurrency: `completion` closure captured across `DispatchQueue.main.async` boundary without `@Sendable`, causing data race errors
- **Fix:** Marked completion parameter `@escaping @Sendable (Result<Void, PhotoSaveError>) -> Void`
- **Files modified:** DualVideo/Features/Recording/PhotoSaveManager.swift
- **Verification:** Build succeeded with no concurrency warnings
- **Committed in:** fe57dea (Task 1 commit)

**2. [Rule 1 - Bug] Fixed XCTest Swift 6 concurrency: nonisolated(unsafe) var for result capture**
- **Found during:** Task 1 (after @Sendable fix cascaded to tests)
- **Issue:** `@MainActor` test class + `@Sendable` completion: `var result` mutated from `@Sendable` closure was a Swift 6 data race error
- **Fix:** `nonisolated(unsafe) var result` for Tests 1-3; async `withCheckedContinuation` for Test 4 (runloop deadlock risk)
- **Files modified:** DualVideoTests/UnitTests/PhotoSaveManagerTests.swift
- **Verification:** All 4 tests pass; Test 4 uses async/await avoiding 2s timeout failure
- **Committed in:** fe57dea (Task 1 commit)

**3. [Rule 3 - Blocking] Updated both worktree and main workspace project.pbxproj**
- **Found during:** Task 1 (after creating source files)
- **Issue:** Xcode worktree has independent project.pbxproj — new files added to main workspace file weren't picked up by worktree build
- **Fix:** Applied identical PBXBuildFile/PBXFileReference/group/Sources additions to both project files
- **Files modified:** DualVideo.xcodeproj/project.pbxproj (worktree copy)
- **Verification:** Build succeeded from worktree directory
- **Committed in:** fe57dea (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs, 1 Rule 3 blocking)
**Impact on plan:** All fixes required for Swift 6 correctness and build system operation. No scope creep.

## Issues Encountered

- Swift 6 strict concurrency required `@Sendable` on completion closures and `nonisolated(unsafe)` in XCTest capture — both are established patterns for this codebase going forward
- `@MainActor` XCTest class + `wait(for:timeout:)` causes runloop starvation for background-dispatched completions; resolved via async test + `withCheckedContinuation`
- Xcode worktrees have independent project.pbxproj copies — each new file must be registered in the worktree's copy, not just the main workspace copy

## Known Stubs

None — all data flows are wired end-to-end. `saveResult` is populated by real `PhotoSaveManager` calls; `CameraContentView` renders actual result state.

## Next Phase Readiness

- Task 3 (on-device verification) blocks v0.1.0 tag — human tester must confirm .mov saves to Camera Roll
- Plan 03-02 (PiP polish) and 03-03 (interruption hardening) can proceed in parallel with Task 3 verification
- `saveResult` nil-reset pattern established — 03-03 can hook into interruption handling to clear saveResult on interrupted recordings

---
*Phase: 03-save-polish-and-edge-cases*
*Completed: 2026-05-17*
