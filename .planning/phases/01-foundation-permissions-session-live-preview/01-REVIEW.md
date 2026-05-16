---
phase: 01-foundation-permissions-session-live-preview
reviewed: 2026-05-16T00:00:00Z
depth: standard
files_reviewed: 16
files_reviewed_list:
  - DualVideo/App/DualVideoApp.swift
  - DualVideo/App/Info.plist
  - DualVideo/Features/Camera/CameraActor.swift
  - DualVideo/Features/Camera/CameraContentView.swift
  - DualVideo/Features/Camera/CameraManager.swift
  - DualVideo/Features/Camera/CameraPreviewView.swift
  - DualVideo/Features/Camera/PermissionManager.swift
  - DualVideo/Features/Camera/PiPOverlayState.swift
  - DualVideo/Features/Camera/UnsupportedDeviceView.swift
  - DualVideo/Features/Root/RootView.swift
  - DualVideo/Shared/AppState.swift
  - DualVideoTests/UnitTests/CameraManagerTests.swift
  - DualVideoTests/UnitTests/CapabilityGateTests.swift
  - DualVideoTests/UnitTests/PermissionManagerTests.swift
  - DualVideoTests/UnitTests/PiPDragClampTests.swift
  - DualVideoTests/UnitTests/ZoomClampTests.swift
findings:
  critical: 0
  warning: 4
  info: 4
  total: 8
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-05-16
**Depth:** standard
**Files Reviewed:** 16
**Status:** issues_found

## Summary

The foundation layer is well-structured. The threading model is carefully documented and the use of `nonisolated(unsafe)` is justified in comments. Permission sequencing, capability gating, and PiP clamping logic are all correct. No critical (security, crash, data-loss) issues were found.

Four warnings were identified: a main-actor write that happens off the main thread in `setZoom`, silent swallowing of `AVCaptureConnection` setup failures, an `Equatable` implementation that loses associated-value identity for the `permissionsBlocked` route, and test cases that duplicate clamping logic inline rather than exercising the actual production code path. Four informational items cover a misleading comment, a dead property, redundant `videoGravity` assignment, and an unused variable in tests.

---

## Warnings

### WR-01: `setZoom` writes `@Observable` property from non-main-actor context

**File:** `DualVideo/Features/Camera/CameraManager.swift:64`

**Issue:** `backZoomFactor` is an `@Observable`-synthesized stored property. Swift's `@Observable` macro generates access via `_$observationRegistrar`, which is not thread-safe when written from arbitrary threads. `setZoom` is a non-isolated method; it writes `backZoomFactor` on whatever thread the caller uses (in practice the SwiftUI gesture callback, which runs on the main thread, but the method makes no guarantee). The subsequent `sessionQueue.async` block at line 65 closes over `clamped`, which is fine — but the property write at line 64 is not dispatched to the main actor.

**Fix:** Isolate the property write to the main actor explicitly:

```swift
func setZoom(_ factor: CGFloat) {
    let clamped = min(max(factor, 1.0), 3.0)
    // Write @Observable property on main actor
    Task { @MainActor in
        backZoomFactor = clamped
    }
    sessionQueue.async { [weak self] in
        guard let device = self?.backDevice else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            logger.error("Zoom lock failed: \(error.localizedDescription)")
        }
    }
}
```

Alternatively, mark `setZoom` as `@MainActor` — since it is called exclusively from SwiftUI gesture callbacks which are already on the main thread, this is the cleanest fix and makes the threading contract explicit.

---

### WR-02: Silent `AVCaptureConnection` failures leave session running with no video path

**File:** `DualVideo/Features/Camera/CameraManager.swift:133-146`

**Issue:** The four `canAddConnection`/`addConnection` calls (back data, back preview, front data, front preview) silently do nothing on failure. If any of these fail — e.g. because the port could not be resolved — the session starts (`session.startRunning()` is reached), `isSessionRunning` becomes `true`, but no video frames are delivered and no previews are shown. The user sees black viewfinders with no error. This is a logic error: a session that fails to wire connections should not be presented as a successfully running session.

**Fix:** Treat connection failures as configuration errors and bail out before `startRunning`:

```swift
guard session.canAddConnection(backConn) else {
    session.commitConfiguration()
    handleError("Cannot add back video connection")
    return
}
session.addConnection(backConn)

guard session.canAddConnection(backPreviewConn) else {
    session.commitConfiguration()
    handleError("Cannot add back preview connection")
    return
}
session.addConnection(backPreviewConn)
// ... same for front connections
```

If partial failure is acceptable (e.g. front camera unavailable), document that explicitly and surface it to the user rather than silently proceeding.

---

### WR-03: `AppRoute.Equatable` loses associated-value identity for `permissionsBlocked`

**File:** `DualVideo/Features/Root/RootView.swift:109-111`

**Issue:** The `==` implementation compares routes by `id` only. Both `.permissionsBlocked(which: "camera")` and `.permissionsBlocked(which: "microphone")` return `id == 3`, so they are considered equal. If the app transitions from one blocked state to another (e.g. camera denied → retry → microphone denied), the `animation` modifier driven by `appState.route.id` will not fire, and `PermissionsBlockedView` will not re-render with the new `deniedPermission` string.

This is unlikely during normal flows (permission requests are sequential and the user cannot retry without reopening the app), but it is a correctness defect that would bite if retry logic is added in a later phase.

**Fix:** Include the associated value in equality:

```swift
static func == (lhs: AppRoute, rhs: AppRoute) -> Bool {
    switch (lhs, rhs) {
    case (.checkingCapability, .checkingCapability),
         (.unsupportedDevice, .unsupportedDevice),
         (.requestingPermissions, .requestingPermissions),
         (.camera, .camera):
        return true
    case (.permissionsBlocked(let l), .permissionsBlocked(let r)):
        return l == r
    default:
        return false
    }
}
```

---

### WR-04: `CameraManagerTests` tests duplicated inline expressions, not production code

**File:** `DualVideoTests/UnitTests/CameraManagerTests.swift:5-23`

**Issue:** All three test methods instantiate a `CameraManager` but never call `setZoom` on it. The clamping math (`min(max(..., 1.0), 3.0)`) is duplicated inline in the test body. This means the tests do not exercise `CameraManager.setZoom` at all — if the bounds in `setZoom` were changed from `1.0`/`3.0` to different values, all three tests would still pass. `ZoomClampTests` duplicates the same pattern.

**Fix:** Test the actual method. Since `setZoom` writes to an `@Observable` property, expose a testable pure function or test via the published property:

```swift
func testZoomClampLower() {
    let manager = CameraManager()
    manager.setZoom(0.5)
    XCTAssertEqual(manager.backZoomFactor, 1.0)
}

func testZoomClampUpper() {
    let manager = CameraManager()
    manager.setZoom(5.0)
    XCTAssertEqual(manager.backZoomFactor, 3.0)
}
```

Note that `setZoom` dispatches to `sessionQueue` for the AVFoundation work — `backZoomFactor` is written synchronously before the async dispatch, so reading it immediately after the call is valid.

---

## Info

### IN-01: Misleading comment on horizontal offset direction in `clampedOffset`

**File:** `DualVideo/Features/Camera/PiPOverlayState.swift:58`

**Issue:** The comment block says "negative offset moves right-to-left, positive moves left" which is self-contradictory. The formula `xAbs = xAnchor + proposed.width` means positive `proposed.width` moves the PiP rightward from the top-right anchor (i.e. off-screen right, which is clamped away) and negative values move it left toward the leading edge. The math is correct; only the comment is misleading.

**Fix:** Replace the directional comment with an accurate description:

```swift
// x_abs = x_anchor + proposed.width
//   positive proposed.width → moves PiP right of anchor (clamped to xMax)
//   negative proposed.width → moves PiP toward leading edge
```

---

### IN-02: Dead property `deviceSupported` in `AppState`

**File:** `DualVideo/Shared/AppState.swift:15`

**Issue:** `var deviceSupported: Bool = false` is declared but never read or written anywhere. The capability check is performed directly in `RootView.checkCapabilityAndPermissions()` via `AVCaptureMultiCamSession.isMultiCamSupported` and the result is encoded in the `route` state machine. `deviceSupported` is redundant.

**Fix:** Remove the property:

```swift
@Observable
final class AppState {
    var route: AppRoute = .checkingCapability
    var cameraManager: CameraManager = CameraManager()
}
```

---

### IN-03: Redundant `videoGravity` assignment in `CameraPreviewView`

**File:** `DualVideo/Features/Camera/CameraPreviewView.swift:34`

**Issue:** `layer.videoGravity = .resizeAspectFill` is set in `PreviewUIView.setPreviewLayer`. The same property is also set in `CameraManager.configureAndStart` (line 167-168 of CameraManager.swift) under the `main.sync` block. The duplicate assignment is harmless but creates two sources of truth for the gravity setting.

**Fix:** Remove the `videoGravity` assignment from one of the two sites. The `CameraManager` site is closer to the session configuration; the `PreviewUIView` site is a sensible default. Either is acceptable — pick one and add a brief comment noting the authoritative location.

---

### IN-04: Unused `manager` variable in `PermissionManagerTests`

**File:** `DualVideoTests/UnitTests/PermissionManagerTests.swift:8`

**Issue:** `let manager = PermissionManager()` is created but only used to call `currentStatus()`. The result is discarded via `_ = status`. This tests that the type is importable and does not crash — which is a valid smoke test — but the intent is unclear from the test name `testPermissionStatusGrantedCoverage`. The test asserts nothing.

**Fix:** Either add an explicit assertion that acknowledges the simulator-only constraint, or rename the test to make the smoke-test intent clear:

```swift
func testPermissionManagerIsInstantiableAndDoesNotCrash() async {
    let manager = PermissionManager()
    // currentStatus() on simulator always returns .notDetermined — no assertion,
    // but must not throw or crash.
    _ = await manager.currentStatus()
}
```

---

_Reviewed: 2026-05-16_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
