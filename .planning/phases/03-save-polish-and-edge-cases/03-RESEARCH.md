# Phase 3: Save, Polish, and Edge Cases - Research

**Researched:** 2026-05-17
**Domain:** PhotoKit save flow, SwiftUI UX polish (corner snapping, zoom label, torch), AVCaptureSession interruption recovery
**Confidence:** HIGH (APIs well-established; torch-in-MultiCam and interruptionEnded auto-restart need on-device confirmation)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DEV-03 | App requests Photo Library add permission before save and handles denial gracefully | `PHPhotoLibrary.requestAuthorization(for: .addOnly)` already called in PermissionManager; save-time re-check required |
| OUT-01 | On stop, app auto-saves the composited file to Photos | `PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:) }` |
| OUT-02 | App shows success/failure save feedback to the user | SwiftUI `.alert` / transient banner driven by `@Observable` save state property on RecordingManager |
| OUT-03 | PiP corner snapping and persisted PiP position work across sessions | `withAnimation(.spring())` snap to nearest corner in `endDrag`; `@AppStorage` to persist corner index |
| OUT-04 | App provides torch toggle, zoom label, and orientation lock during recording | `AVCaptureDevice.torchMode` + `lockForConfiguration`; Text overlay reading `cameraManager.backZoomFactor`; Info.plist already portrait-only |
</phase_requirements>

---

## Summary

Phase 3 has three independent tracks that can be planned in parallel: (1) the Photos save flow, (2) PiP snapping and position persistence, and (3) torch/zoom-label/orientation-lock controls plus session-level interruption recovery hardening.

**Track 1 — Save flow (Plan 03-01):** `PermissionManager` already requests `.addOnly` authorization at startup. The save path is `PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }` invoked from `RecordingManager.stopRecording`'s completion handler. The temp `.mov` must be deleted after a confirmed save success (`performChanges` completion with `success == true`). A re-check of authorization status at save time handles the edge case where the user revoked access in Settings after launch. The current `ActivityView` share-sheet stub in `CameraContentView` must be replaced with this Photos flow.

**Track 2 — PiP polish (Plan 03-02):** Corner snapping is pure SwiftUI math: after drag ends, compute which of the four corners is nearest the PiP's current center, animate with `.spring()` to that corner's offset. `@AppStorage` (backed by UserDefaults) persists the corner index across launches. The `PiPOverlayState` class must gain a corner-snap method and a stored corner index. Screen metrics must be respected (the same safe-area-aware clamp logic from Phase 1 determines each corner's offset). The existing `D-08` deferral note in `PiPOverlayState.endDrag` marks exactly the insertion point.

**Track 3 — Controls + edge cases (Plan 03-03):** Orientation lock is already enforced at the Info.plist and build-settings level (`UIInterfaceOrientationPortrait` only) — no code work needed. Zoom label is a read-only display of `cameraManager.backZoomFactor` (already `@Observable`), formatted as e.g. "1.4x". Torch toggle requires `lockForConfiguration()` on the back `AVCaptureDevice`, with `hasTorch && isTorchModeSupported(.on)` guards; in `AVCaptureMultiCamSession`, the back camera device reference is already stored in `CameraManager.backDevice`. Interruption recovery for _session resume_ (after a phone call ends) uses `AVCaptureSession.interruptionEndedNotification` — if the session was not explicitly stopped, the OS can restart it automatically; code must listen and update `isSessionRunning` accordingly.

**Primary recommendation:** Implement in three sequential plans: save flow first (highest value delivery), then PiP polish, then controls/edge-cases last (lowest risk of breaking recording pipeline).

---

## Codebase Baseline (Phase 2 outputs)

These are the exact integration points Phase 3 builds on. Verified by reading source.

| Symbol | Location | Phase 3 use |
|--------|----------|-------------|
| `RecordingManager.pendingFileURL: URL?` | `RecordingManager.swift:28` | Set after finalization; Phase 3 triggers Photos save when this becomes non-nil |
| `RecordingManager.stopRecording(completion:)` | `RecordingManager.swift:128` | Phase 3 adds Photos save call inside the completion closure |
| `CameraContentView.ActivityView` | `CameraContentView.swift:149` | Temporary stub — Phase 3 replaces the `.sheet` with a save-result alert |
| `CameraManager.backDevice: AVCaptureDevice?` | `CameraManager.swift:27` | `nonisolated(unsafe)` stored property — torch toggle calls `lockForConfiguration` on it |
| `CameraManager.backZoomFactor: CGFloat` | `CameraManager.swift:47` | `@Observable` property already tracking current zoom — zoom label reads this |
| `PiPOverlayState.endDrag(...)` | `PiPOverlayState.swift:33` | Contains `// NOTE: no corner snapping — D-08 deferred to Phase 3` — exact insertion point |
| `PiPOverlayState.offset: CGSize` | `PiPOverlayState.swift:8` | Currently in-memory only; Phase 3 persists via `@AppStorage` |
| `PermissionManager.requestAll()` | `PermissionManager.swift:17` | Already calls `PHPhotoLibrary.requestAuthorization(for: .addOnly)` — no change needed for permissions |
| `Info.plist UISupportedInterfaceOrientations` | `DualVideo/App/Info.plist:28` | `[UIInterfaceOrientationPortrait]` — orientation lock already complete, no code work |

---

## Standard Stack

### Core

| Library/API | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| `Photos` / `PHPhotoLibrary` | iOS 14+ | Save video asset to user photo library | Only approved API for write-to-Photos on iOS; no alternatives |
| `PHAssetChangeRequest` | iOS 8+ | Create new asset from file URL inside `performChanges` block | Required companion to `PHPhotoLibrary.performChanges` |
| `SwiftUI` `.spring()` / `withAnimation` | iOS 18 | Animate PiP snap to corner | Existing animation layer in `CameraContentView`; consistent with `interactiveSpring` already on PiP |
| `@AppStorage` | iOS 14+ | Persist PiP corner index across launches | Lightest-weight persistence for a single integer; backed by UserDefaults automatically |
| `AVCaptureDevice.torchMode` + `lockForConfiguration` | iOS 4+ | Toggle back-camera torch | Standard AVFoundation API; no alternative for hardware torch control |

[VERIFIED: Apple documentation references, existing codebase inspection]

### Supporting

| Library/API | Purpose | When to Use |
|-------------|---------|-------------|
| `FileManager.removeItem(at:)` | Delete temp `.mov` after confirmed save | Call only from `performChanges` success completion path; never on failure |
| `AVCaptureSession.interruptionEndedNotification` | Detect when OS re-enables camera after phone call | Register in `RecordingManager.setup(cameraManager:)` alongside existing `wasInterruptedNotification` |
| `NotificationCenter` | Route interruption-ended notification to UI recovery | Already used in Phase 2 for `wasInterruptedNotification` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `@AppStorage` for PiP corner | `UserDefaults` directly | `@AppStorage` is the SwiftUI-native wrapper; less boilerplate; observable in Views automatically |
| `PHPhotoLibrary.performChanges` | `UISaveVideoAtPathToSavedPhotosAlbum` | Legacy API; deprecated in favor of PhotoKit |
| `withAnimation(.spring())` corner snap | `UISpringTimingParameters` via UIKit | Would require bridging out of SwiftUI unnecessarily |

---

## Architecture Patterns

### Recommended Project Structure (Phase 3 additions)

```
DualVideo/Features/Recording/
├── PhotoSaver.swift           # Isolated save actor: permissions re-check, performChanges, temp file cleanup
DualVideo/Features/Camera/
├── PiPOverlayState.swift      # (existing) — add snapToNearestCorner() + @AppStorage corner index
├── CameraContentView.swift    # (existing) — replace ActivityView with save-result alert
├── CameraManager.swift        # (existing) — add toggleTorch() method
DualVideo/Features/Recording/UI/
├── SaveFeedbackView.swift     # Transient success/failure banner (optional; alert is simpler)
├── ZoomLabelView.swift        # "1.4x" text overlay reading cameraManager.backZoomFactor
├── TorchToggleButton.swift    # Torch button wired to CameraManager.toggleTorch()
```

### Pattern 1: PHPhotoLibrary Save Flow

**What:** After `stopRecording` finalization produces a temp `.mov` URL, call `performChanges` to create a photo asset, then delete the temp file on success.

**Authorization re-check:** Even though `PermissionManager.requestAll()` already obtains `.addOnly` access at startup, the user can revoke it in Settings while the app runs. The save path must call `PHPhotoLibrary.authorizationStatus(for: .addOnly)` synchronously and bail with a user-visible error if status is not `.authorized` or `.limited`.

**Pattern:**

```swift
// [VERIFIED: PHPhotoLibrary.requestAuthorization(for:) API confirmed via Apple Developer Documentation]
// Source: developer.apple.com/documentation/photos/phphotolibrary/requestauthorization(for:handler:)
func saveToPhotos(url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
    // Re-check at save time — user may have revoked in Settings
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    guard status == .authorized || status == .limited else {
        completion(.failure(SaveError.permissionDenied))
        return
    }

    PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
    } completionHandler: { success, error in
        if success {
            // Delete temp file only after confirmed Photos save
            try? FileManager.default.removeItem(at: url)
            completion(.success(()))
        } else {
            completion(.failure(error ?? SaveError.unknown))
        }
    }
}
```

**CRITICAL: Temp file deletion timing.** Delete the `.mov` only inside the `success == true` completion path. On failure, preserve the temp file so the user can retry or share manually. Do not delete in `defer` — that runs on both success and failure paths.

**Threading:** `performChanges` completion is called on an arbitrary queue. Dispatch back to `DispatchQueue.main.async` before updating `@Observable` state.

### Pattern 2: PiP Corner Snapping

**What:** On drag end, compute which of four corners is geometrically nearest to the PiP's current position, animate the `offset` to that corner's offset value, and persist the corner index.

**Math:** Four corner offsets relative to the top-right anchor (`offset == .zero`):
- Top-right: `.zero` (default anchor)
- Top-left: `CGSize(width: -(containerWidth - pipWidth - 2*margin), height: 0)`
- Bottom-right: `CGSize(width: 0, height: containerHeight - safeTop - safeBottom - pipHeight - 2*margin)`
- Bottom-left: both above combined

**Nearest corner:** Compute Euclidean distance from current `offset` to each corner's canonical offset; pick minimum.

**Animation:** `withAnimation(.spring(response: 0.35, dampingFraction: 0.75))` applied when mutating `offset` in `endDrag`. This is a pure SwiftUI state change — no `UIKit` bridging required.

**Persistence:**

```swift
// [VERIFIED: @AppStorage wraps UserDefaults; backed by documentation at developer.apple.com/documentation/swiftui/appstorage]
// In PiPOverlayState:
@AppStorage("pip_corner_index") var persistedCornerIndex: Int = 0  // 0=topRight, 1=topLeft, 2=bottomRight, 3=bottomLeft
```

On app launch, read `persistedCornerIndex` and restore the matching `offset` using the same corner-offset math (requires containerSize — read from `GeometryReader` on first layout in `CameraContentView.onAppear`).

**Thread note:** `@AppStorage` and `@Observable` both require main-thread access — `PiPOverlayState` is always mutated from the main thread via gesture handlers, so no isolation issue.

### Pattern 3: Torch Toggle

**What:** Toggle `backDevice.torchMode` between `.on` and `.off`. Must call `lockForConfiguration()` / `unlockForConfiguration()` around the mutation. Must check `hasTorch` and `isTorchModeSupported(.on)` before attempting.

**Where it lives:** `CameraManager.toggleTorch()` — keeps all device configuration in one place, consistent with `setZoom`.

**Pattern:**

```swift
// [ASSUMED] — consistent with lockForConfiguration pattern already used in setZoom()
func toggleTorch() {
    sessionQueue.async { [weak self] in
        guard let device = self?.backDevice,
              device.hasTorch,
              device.isTorchModeSupported(.on) else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = (device.torchMode == .on) ? .off : .on
            device.unlockForConfiguration()
        } catch {
            logger.error("Torch toggle failed: \(error.localizedDescription)")
        }
    }
}
```

**Observable state:** Add `var isTorchOn: Bool = false` to `CameraManager` (`@Observable`). Update it on main after the sessionQueue mutation so the UI button reflects current state.

**AVCaptureMultiCamSession compatibility:** Torch control via `AVCaptureDevice.lockForConfiguration` is independent of session type — it operates on the device directly, not on the session. No known restriction prevents torch use with `AVCaptureMultiCamSession`. [ASSUMED — no documented restriction found; needs on-device verification]

### Pattern 4: Zoom Label Display

**What:** A `Text` view overlaid on `CameraContentView` showing the current zoom factor formatted as `"1.0x"`, `"2.5x"`, etc.

**Source data:** `cameraManager.backZoomFactor: CGFloat` is already `@Observable` and updated by `setZoom()`. Reading it in a SwiftUI `Text` view causes automatic re-render when it changes.

**Format:** `String(format: "%.1fx", cameraManager.backZoomFactor)` produces `"1.0x"`, `"1.4x"` etc.

**Display rules:** Show at all times (not just during recording). Position: bottom-left or center-top, not overlapping Record button or RecordingStatusOverlay.

### Pattern 5: Interruption Recovery (interruptionEndedNotification)

**What:** When a phone call ends and camera access is restored, the session may auto-resume (if it was not explicitly stopped). The app must listen for `AVCaptureSession.interruptionEndedNotification` and update `isSessionRunning` to match reality.

**Key insight from research:** If `stopRunning()` was never called (the session was merely interrupted, not stopped), the OS may restart the session automatically when the interruption ends. The app receives `interruptionEndedNotification`. If the session was auto-stopped via the Phase 2 interruption handler (`handleInterruption()` calling `stopRecording()`), the _recording_ is already finalized but the camera session itself can restart.

**Pattern:**

```swift
// [VERIFIED: interruptionEndedNotification documented at developer.apple.com/documentation/avfoundation/avcapturesession/interruptionendednotification]
NotificationCenter.default.addObserver(
    forName: AVCaptureSession.interruptionEndedNotification,
    object: session,
    queue: .main
) { [weak self] _ in
    // Session may have auto-restarted; sync observable state
    DispatchQueue.main.async {
        self?.cameraManager.isSessionRunning = self?.session.isRunning ?? false
    }
}
```

**Recording recovery:** Phase 2's `handleInterruption()` already auto-stops and finalizes recording on interruption. Phase 3 does NOT auto-restart recording after a phone call — that is explicitly deferred (from Phase 2 CONTEXT.md). Recovery means the preview resumes; the user must tap Record again.

### Anti-Patterns to Avoid

- **Deleting temp `.mov` unconditionally:** Always delete only on confirmed `success == true` from `performChanges`. On failure, the user may want to retry.
- **Calling `PHPhotoLibrary.performChanges` from the main thread and blocking:** `performChanges` is async; its completion handler is on an arbitrary background queue. Never call synchronous `performChangesAndWait` on main.
- **Creating PiP corner offsets without safe-area awareness:** The corner snap must use the same `safeAreaInsets` clamp logic as `PiPOverlayState.clampedOffset`. Hard-coding pixel positions will break on devices with different notch/island geometry.
- **Persisting `CGSize` offset directly to UserDefaults:** Store a corner index (0–3 Int) instead. Offsets depend on screen size and safe-area insets that change at runtime; the corner index is stable.
- **Setting `torchMode` without `lockForConfiguration`:** AVFoundation will crash or throw without the configuration lock.
- **Reading `PHPhotoLibrary.authorizationStatus()` (no-arg, deprecated):** Use `authorizationStatus(for: .addOnly)` on iOS 14+. The legacy API returns `.authorized` when status is actually `.limited`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Video save to Photos | Custom file copy to Camera Roll path | `PHPhotoLibrary.performChanges` + `PHAssetChangeRequest` | Camera Roll path is private since iOS 9; only PhotoKit write API works reliably |
| Spring snap animation | Manual `Timer` + position interpolation | `withAnimation(.spring(...))` | SwiftUI springs handle physics, interrupt, and reverse correctly; manual interpolation is fragile |
| UserDefaults persistence | Raw `UserDefaults.standard.set` | `@AppStorage` | `@AppStorage` is reactive: Views auto-refresh when the stored value changes, at zero additional code |
| Torch state management | Custom polling timer | `@Observable` property on `CameraManager` | The device state already exists; just mirror it to an observable property after `lockForConfiguration` |

---

## Common Pitfalls

### Pitfall 1: Photos Save on a Device with Restricted Permission After Launch

**What goes wrong:** User grants permission at launch, then revokes it in Settings without restarting the app. `performChanges` fails silently (or with a permission error) and the user sees no feedback.

**Why it happens:** `PHPhotoLibrary.requestAuthorization` is checked once at startup; runtime revocation is not automatically detected.

**How to avoid:** Always call `PHPhotoLibrary.authorizationStatus(for: .addOnly)` immediately before `performChanges`. If not `.authorized` or `.limited`, show an alert directing user to Settings.

**Warning signs:** `performChanges` completion handler receives `success: false` with `PHPhotosErrorDomain` error code 3302 (permission denied).

### Pitfall 2: PiP Corner Persisted Offset Wrong on First Launch After Screen Rotation or New Device

**What goes wrong:** Restoring a persisted `CGSize` offset from a previous session on a different screen geometry places the PiP off-screen or in the wrong corner.

**Why it happens:** `CGSize` offsets are absolute pixel-space values; they change when safe area or container size changes.

**How to avoid:** Persist only the corner index (0–3). Recompute the pixel offset at restore time using current `GeometryReader` values from `CameraContentView`.

**Warning signs:** PiP appears off-screen or partially clipped on first launch after re-install or device change.

### Pitfall 3: Torch Stays On After Recording Stops

**What goes wrong:** User enables torch during recording; recording stops (phone call, app background); torch stays on, draining battery.

**Why it happens:** Torch state is device hardware state — it survives recording lifecycle. Nothing in `RecordingManager.stopRecording` resets it.

**How to avoid:** In `CameraManager.handleInterruption()` or wherever `stopRecording` is triggered, also call `turnTorchOff()` (or set `torchMode = .off` if currently on). Or: turn torch off automatically in `RecordingManager.handleInterruption()`.

**Warning signs:** Torch LED stays lit on device screen after recording finalization.

### Pitfall 4: performChanges Completion on Background Queue Updating @Observable State

**What goes wrong:** `performChanges` completion handler updates `RecordingManager.pendingFileURL` or a new `saveResult` property directly — this happens on a background queue, causing a Swift 6 actor isolation violation or a runtime crash.

**Why it happens:** `PHPhotoLibrary.performChanges` documentation does not specify which queue the completion runs on; it is background.

**How to avoid:** Always wrap state updates inside `DispatchQueue.main.async` in the `performChanges` completion handler.

**Warning signs:** Swift 6 main actor isolation warning on state property access from background queue.

### Pitfall 5: Temp File Leaked on Save Failure

**What goes wrong:** `performChanges` fails; code deletes the temp file anyway (e.g., in `defer`). User has no recourse — the recording is gone.

**Why it happens:** Cleanup code is written as cleanup-always rather than cleanup-on-success.

**How to avoid:** Delete temp file only inside the `success == true` branch of `performChanges` completion. On failure, preserve the file (it will be cleaned up by `cleanUpOrphanedTempFiles` on next launch, or offer retry).

**Warning signs:** `pendingFileURL` is non-nil after a failed save attempt, but the file at that URL no longer exists.

### Pitfall 6: Torch isTorchModeSupported Not Checked Before Set

**What goes wrong:** Calling `device.torchMode = .on` without checking `isTorchModeSupported(.on)` throws an `NSInvalidArgumentException` on devices where torch is unavailable or the session is in a state that prevents torch use.

**Why it happens:** `hasTorch` is true for the device, but torch may be temporarily unavailable (e.g., device overheating, or during certain camera configurations).

**How to avoid:** Guard: `device.hasTorch && device.isTorchModeSupported(.on)` before setting `torchMode`.

---

## Code Examples

### Full Photos Save with Cleanup

```swift
// [VERIFIED pattern: performChanges + PHAssetChangeRequest.creationRequestForAssetFromVideo
// Source: developer.apple.com/documentation/photos/phphotolibrary/requesting_changes_to_the_photo_library]
// [VERIFIED: authorizationStatus(for:) uses .addOnly per iOS 14+ docs]

enum PhotoSaveError: Error {
    case permissionDenied
    case saveFailed(Error?)
}

func saveVideoToPhotos(url: URL) async -> Result<Void, PhotoSaveError> {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    guard status == .authorized || status == .limited else {
        return .failure(.permissionDenied)
    }

    return await withCheckedContinuation { continuation in
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(returning: .success(()))
                } else {
                    continuation.resume(returning: .failure(.saveFailed(error)))
                }
            }
        }
    }
}
```

### Corner Snap Math in PiPOverlayState

```swift
// [ASSUMED] — pure geometry, no API-specific behavior; consistent with existing clampedOffset logic
func snapToNearestCorner(containerSize: CGSize, pipSize: CGSize, safeAreaInsets: EdgeInsets) {
    let margin = Self.edgeMargin
    let xRight: CGFloat = 0   // top-right anchor is .zero
    let xLeft = -(containerSize.width - pipSize.width - 2 * margin)
    let yTop: CGFloat = 0
    let yBottom = containerSize.height - safeAreaInsets.top - safeAreaInsets.bottom - pipSize.height - 2 * margin

    let corners: [(index: Int, offset: CGSize)] = [
        (0, CGSize(width: xRight, height: yTop)),    // top-right (default)
        (1, CGSize(width: xLeft,  height: yTop)),    // top-left
        (2, CGSize(width: xRight, height: yBottom)), // bottom-right
        (3, CGSize(width: xLeft,  height: yBottom)), // bottom-left
    ]

    let nearest = corners.min { a, b in
        distance(offset, a.offset) < distance(offset, b.offset)
    }!

    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
        offset = nearest.offset
        baseOffset = nearest.offset
    }
    persistedCornerIndex = nearest.index
}

private func distance(_ a: CGSize, _ b: CGSize) -> CGFloat {
    let dx = a.width - b.width
    let dy = a.height - b.height
    return sqrt(dx * dx + dy * dy)
}
```

### Zoom Label View

```swift
// [ASSUMED] — trivial SwiftUI Text; @Observable auto-refresh is well-established
struct ZoomLabelView: View {
    let zoomFactor: CGFloat

    var body: some View {
        Text(String(format: "%.1fx", zoomFactor))
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.4))
            .clipShape(Capsule())
    }
}
```

### Torch Toggle in CameraManager

```swift
// [ASSUMED] — matches established lockForConfiguration pattern in setZoom()
func toggleTorch() {
    sessionQueue.async { [weak self] in
        guard let device = self?.backDevice,
              device.hasTorch,
              device.isTorchModeSupported(.on) else { return }
        do {
            try device.lockForConfiguration()
            let newMode: AVCaptureDevice.TorchMode = (device.torchMode == .on) ? .off : .on
            device.torchMode = newMode
            device.unlockForConfiguration()
            DispatchQueue.main.async { self?.isTorchOn = (newMode == .on) }
        } catch {
            logger.error("Torch toggle failed: \(error.localizedDescription)")
        }
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `UISaveVideoAtPathToSavedPhotosAlbum` | `PHPhotoLibrary.performChanges` + `PHAssetChangeRequest.creationRequestForAssetFromVideo` | iOS 8 (PhotoKit) | Legacy API still compiles but is deprecated; PhotoKit is the only path that works correctly with `.addOnly` permission |
| `PHPhotoLibrary.requestAuthorization(_:)` (no access level) | `requestAuthorization(for: .addOnly)` | iOS 14 | Old API returns `.authorized` even for `.limited` status; use the access-level variant |
| Persisting raw CGPoint/CGSize offsets to UserDefaults | Persisting corner index (Int) | — | Pixel offsets are screen-geometry-dependent; corner index is stable across device sizes |

**Deprecated/outdated:**
- `PHPhotoLibrary.requestAuthorization(_:)` (single-arg, no accessLevel): Works on iOS 18 but returns incorrect status for `.limited` grants. [VERIFIED: confirmed by Apple documentation noting the new API as preferred for iOS 14+]
- `UISaveVideoAtPathToSavedPhotosAlbum`: Compiles but is not recommended; requires full read/write permission rather than `.addOnly`.

---

## Orientation Lock: Already Complete

`Info.plist` has `UISupportedInterfaceOrientations = [UIInterfaceOrientationPortrait]` and the build setting `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait`. [VERIFIED: read from DualVideo/App/Info.plist and project.pbxproj directly]

Plan 03-03 must note this explicitly: **no code work is needed for orientation lock**. The requirement is satisfied by existing project configuration. The plan's task for OUT-04 orientation lock is: verify on device that rotation produces no response, then mark done.

---

## DEV-03 Permission Handling: PermissionManager Already Correct

`PermissionManager.requestAll()` already calls `PHPhotoLibrary.requestAuthorization(for: .addOnly)` and `currentStatus()` checks `PHPhotoLibrary.authorizationStatus(for: .addOnly)`. [VERIFIED: read from PermissionManager.swift directly]

The only remaining work for DEV-03 is the **save-time re-check** (described in Pattern 1 above) and the **denial UX** (an alert directing the user to Settings when `performChanges` fails due to permission).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `AVCaptureDevice.torchMode` can be set during an active `AVCaptureMultiCamSession` without stopping or reconfiguring the session | Architecture Patterns — Pattern 3 | MEDIUM: if torch requires session reconfiguration in MultiCam, toggleTorch() would need to stop/restart inside `beginConfiguration/commitConfiguration`; needs on-device test |
| A2 | After phone call ends, `AVCaptureSession.interruptionEndedNotification` fires and the session auto-restarts without calling `startRunning()` again (if it was not explicitly stopped) | Architecture Patterns — Pattern 5 | MEDIUM: if auto-restart does not happen, `CameraManager.startSession()` must be called again from the notification handler |
| A3 | `withAnimation(.spring(response: 0.35, dampingFraction: 0.75))` applied to PiP offset mutation in `PiPOverlayState` propagates correctly through the existing `.animation(.interactiveSpring(...), value: pipState.offset)` modifier in `CameraContentView` | Architecture Patterns — Pattern 2 | LOW: SwiftUI animation transaction precedence may cause the outer `.animation` modifier to win; may need to use `.transaction` override |
| A4 | `@AppStorage` on a non-`@Observable` property of `PiPOverlayState` (which is `@Observable`) will synthesize correct UserDefaults read/write | Architecture Patterns — Pattern 2 | LOW: `@AppStorage` inside an `@Observable` class may not work as a `@State` replacement; may need explicit `UserDefaults.standard` read/write instead |
| A5 | The corner-snap offset formula correctly maps index 0-3 to the four visible corners for all container sizes (including notch/Dynamic Island geometry) | Code Examples | LOW: formula is straightforward geometry; the existing `clampedOffset` tests validate the math domain |

---

## Open Questions

1. **Does torch work during active AVCaptureMultiCamSession recording on iPhone XR?**
   - What we know: `lockForConfiguration` is the documented API; no explicit restriction documented for MultiCam.
   - What's unclear: Whether hardware constraints on A12 prevent torch during dual-camera capture.
   - Recommendation: Plan 03-03 must include an explicit device-verification step: start recording, toggle torch, confirm LED activates.

2. **Does interruptionEndedNotification auto-restart the session?**
   - What we know: Apple documentation states "if you don't call stopRunning, your startRunning request is preserved." Phase 2's `handleInterruption()` calls `stopRecording()` on the recording manager, but does NOT call `session.stopRunning()` on the camera session itself.
   - What's unclear: Whether `wasInterruptedNotification` for a phone call automatically stops the session or merely pauses it. If paused (not stopped), it should auto-resume.
   - Recommendation: On-device test during Plan 03-03 checkpoint: make a 5-second call while previewing, hang up, observe whether preview resumes without user action.

3. **Does @AppStorage work inside an @Observable class?**
   - What we know: `@AppStorage` is a SwiftUI property wrapper; `@Observable` uses the Observation framework macro.
   - What's unclear: Mixing `@AppStorage` inside `@Observable` — the macro may not synthesize correct storage access.
   - Recommendation: If `@AppStorage` fails inside `PiPOverlayState`, fall back to `UserDefaults.standard.integer(forKey:)` / `set(_:forKey:)` in `snapToNearestCorner` and `init`. This is low-risk to implement.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Physical iPhone XR | Torch test, camera session validation | ✓ (per PROJECT.md and Phase 2 verified) | A12, iOS 18.7.9 | None — Simulator has no torch or camera |
| Photos framework | OUT-01 save flow | ✓ (iOS 18.0+) | Built-in | None — required by requirements |
| Xcode 26 | Build/deploy | ✓ (verified: Xcode 26.4.1) | 26.4.1 | None |
| Swift 6.3.1 | Strict concurrency | ✓ (verified) | 6.3.1 | None |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Xcode built-in) |
| Config file | Xcode scheme — no external config file |
| Quick run command | `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty` |
| Full suite command | `xcodebuild test -scheme DualVideo -destination 'id=<device-udid>'` (device for camera/torch tests) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEV-03 | `authorizationStatus(for: .addOnly)` re-check returns correct deny path | Unit (mock status) | `xcodebuild test -only-testing:DualVideoTests/PhotoSaverTests` | ❌ Wave 0 |
| OUT-01 | `performChanges` called with correct URL; temp file deleted on success | Unit (mock PHPhotoLibrary) | `xcodebuild test -only-testing:DualVideoTests/PhotoSaverTests` | ❌ Wave 0 |
| OUT-02 | Save result state transitions (idle → saving → success/failure) observable | Unit | `xcodebuild test -only-testing:DualVideoTests/PhotoSaverTests` | ❌ Wave 0 |
| OUT-03 | `snapToNearestCorner` returns correct corner offset for each quadrant | Unit | `xcodebuild test -only-testing:DualVideoTests/PiPSnapTests` | ❌ Wave 0 |
| OUT-03 | Corner index persists across `PiPOverlayState` init | Unit | `xcodebuild test -only-testing:DualVideoTests/PiPSnapTests` | ❌ Wave 0 |
| OUT-04 | Torch toggle transitions `isTorchOn` from false→true→false | Manual | Record on device, tap torch button | Manual only (requires hardware torch) |
| OUT-04 | Zoom label text matches `backZoomFactor` formatted value | Unit | `xcodebuild test -only-testing:DualVideoTests/ZoomLabelTests` | ❌ Wave 0 |
| OUT-04 | Orientation lock: rotation produces no interface change | Manual | Rotate iPhone XR during preview | Manual only (device-only) |

### Sampling Rate

- **Per task commit:** Existing 29-test suite + any new Phase 3 unit tests (simulator)
- **Per wave merge:** Full unit suite + manual on-device smoke: save recording to Photos, verify in Photos app
- **Phase gate:** All unit tests green + full manual checkpoint (save to Photos, PiP snap, torch, zoom label) before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `DualVideoTests/UnitTests/PhotoSaverTests.swift` — covers DEV-03, OUT-01, OUT-02 (mock `PHPhotoLibrary`, verify state transitions and temp file cleanup)
- [ ] `DualVideoTests/UnitTests/PiPSnapTests.swift` — covers OUT-03 corner snap math and corner index persistence
- [ ] `DualVideoTests/UnitTests/ZoomLabelTests.swift` — covers OUT-04 zoom label formatting (pure function, no device required)

*(No framework install needed — XCTest is available in existing Xcode project. All 29 existing tests remain applicable.)*

---

## Security Domain

Phase 3 adds one new data flow: temp `.mov` file saved to the system Photos library. No network access, no credentials, no new trust boundaries beyond existing camera/microphone.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | Yes (limited) | `PHPhotoLibrary.authorizationStatus(for: .addOnly)` re-check at save time |
| V5 Input Validation | Minimal | Validate temp file URL is non-nil and exists before calling `performChanges` |
| V6 Cryptography | No | Local file; no encryption required |

### Threat Patterns for Phase 3 Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Temp `.mov` remains after save failure | Information disclosure | Preserve file on failure (user retry); `cleanUpOrphanedTempFiles` removes it on next launch |
| `performChanges` called with revoked permission | Elevation of privilege | `authorizationStatus(for: .addOnly)` re-check + user-visible error before save attempt |
| Torch left on after unexpected session termination | Availability | Turn off torch in `handleInterruption()` alongside recording stop |

---

## Sources

### Primary (HIGH confidence)
- `DualVideo/DualVideo/Features/Camera/PermissionManager.swift` — confirmed `PHPhotoLibrary.requestAuthorization(for: .addOnly)` already implemented
- `DualVideo/DualVideo/Shared/AppState.swift` — confirmed integration point for PhotoSaver
- `DualVideo/DualVideo/Features/Camera/CameraManager.swift` — confirmed `backDevice` stored property, `sessionQueue` pattern, `backZoomFactor` @Observable property
- `DualVideo/DualVideo/Features/Camera/PiPOverlayState.swift` — confirmed `endDrag` insertion point and existing clamp logic
- `DualVideo/DualVideo/Features/Camera/CameraContentView.swift` — confirmed `ActivityView` stub to replace, `pipState.offset` animation modifier
- `DualVideo/DualVideo/App/Info.plist` — confirmed `UISupportedInterfaceOrientations = [UIInterfaceOrientationPortrait]`; orientation lock is complete
- Apple Developer Documentation: `PHPhotoLibrary.requestAuthorization(for:handler:)` — `.addOnly` access level confirmed for iOS 14+
- Apple Developer Documentation: `AVCaptureSession.interruptionEndedNotification` — notification existence confirmed
- Apple Developer Documentation: `PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:)` — confirmed API for video save

### Secondary (MEDIUM confidence)
- mackuba.eu/2020/07/07/photo-library-changes-ios-14 — iOS 14 `.addOnly` authorization behavior and `.limited` status semantics
- swiftsenpai.com/development/photo-library-permission — practical `authorizationStatus(for:)` usage patterns
- samwize.com/2020/08/24/ios-14-photo-access-add-only — `.addOnly` vs `.readWrite` behavioral differences
- developer.apple.com/forums/thread/811759 — `interruptionEndedNotification` auto-restart behavior discussion (2026)
- hackingwithswift.com — torch `lockForConfiguration` pattern (iOS 4+)

### Tertiary (LOW confidence)
- General web search on `AVCaptureDevice.torchMode` + `AVCaptureMultiCamSession` — no documented restriction found, but absence of documentation is not confirmation; needs device validation

---

## Metadata

**Confidence breakdown:**
- Photos save flow (DEV-03, OUT-01, OUT-02): HIGH — `PHPhotoLibrary` APIs are stable; `PermissionManager` already correct; temp file lifecycle is straightforward
- PiP corner snap (OUT-03): HIGH — pure SwiftUI/geometry math; `@AppStorage` caveat is LOW risk with known fallback
- Torch toggle (OUT-04): MEDIUM — API is well-known; MultiCam compatibility needs on-device verification
- Zoom label (OUT-04): HIGH — trivial `Text` reading `@Observable` property already tracked
- Orientation lock (OUT-04): HIGH — already complete in Info.plist; verified directly
- Interruption recovery (REC-04 hardening): MEDIUM — `interruptionEndedNotification` documented; auto-restart behavior needs device confirmation

**Research date:** 2026-05-17
**Valid until:** 2026-06-17 (PhotoKit and AVFoundation APIs are stable; `@AppStorage` behavior in `@Observable` classes is a Swift evolution area — check if behavior changes with Xcode/Swift updates)
