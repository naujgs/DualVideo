# Phase 1: Foundation - Permissions, Session, Live Preview - Research

**Researched:** 2026-05-16  
**Domain:** iOS AVFoundation MultiCam foundation (permissions + live dual preview)  
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
### Permission flow and denial UX
- **D-01:** Request camera, microphone, and Photo Library permissions up front on first launch before any capture/session flow (Choice `1B`).
- **D-02:** If any required permission is denied, keep the user in a clear blocked state with explanatory copy and Settings recovery path; do not attempt partial capture mode in Phase 1.

### Unsupported-device fallback UX
- **D-03:** Use a disabled preview shell with a clear explanation banner when MultiCam is unsupported (Choice `2B`).
- **D-04:** Fallback copy must explicitly state A12+ requirement and that dual-camera recording is unavailable on this hardware.

### Live preview composition defaults
- **D-05:** Default PiP layout is front camera in top-right, rounded-rect shape, approximately 28% of screen width, safe-area inset margins, draggable (Choice `3A`).
- **D-06:** Back camera remains full-bleed primary preview layer.

### Interaction behavior (Phase 1 scope)
- **D-07:** PiP drag is clamped to safe-area bounds with inset margins (Choice `4A`).
- **D-08:** Corner snapping is deferred (not implemented in Phase 1).
- **D-09:** Back-camera pinch zoom range is clamped to `1.0x` through `3.0x` in Phase 1.

### Claude's Discretion
- Exact copywriting text for permission/fallback banners and blocked-state messaging.
- Exact constants for drag insets and animation polish, as long as they preserve D-05 and D-07.
- Gesture smoothing/hysteresis details for drag and pinch interactions.

### Deferred Ideas (OUT OF SCOPE)
- PiP corner snapping behavior (planned for Phase 3 per roadmap).
- Recording controls/countdown/timer and composited file writing (Phase 2).
- Photos save workflow, success/failure feedback polish, and persistent PiP position (Phase 3).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DEV-01 | Block unsupported hardware with clear message | Use `AVCaptureMultiCamSession.isMultiCamSupported` gate before setup; render blocked fallback shell |
| DEV-02 | Request camera + microphone permission before capture | Use AVFoundation permission flow before session configuration |
| CAP-01 | Simultaneous back full preview + front PiP | Use `AVCaptureMultiCamSession` + two video inputs + preview layers |
| CAP-02 | Draggable PiP | SwiftUI drag gesture with safe-area clamping |
| CAP-03 | Pinch zoom back camera live preview | `AVCaptureDevice.videoZoomFactor` updates with clamp and `lockForConfiguration()` |
</phase_requirements>

## Summary

Phase 1 should implement a strict preflight path: capability check, then permissions, then session graph configuration, then preview rendering. `AVCaptureMultiCamSession` is the required session type for simultaneous front+back capture, and support must be checked with `isMultiCamSupported`. [CITED: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/]  

The permission API path should be explicit (not implicit) so UX follows D-01/D-02: request access before creating capture inputs, and hard-block UI when denied. AVFoundation documents both camera/microphone request behavior and required Info.plist usage strings. [CITED: https://developer.apple.com/documentation/avfoundation/avcapturedevice/1624584-requestaccess]  

**Primary recommendation:** Implement a `CameraManager` with a dedicated session queue, and gate `startRunning` behind both permission success and `isMultiCamSupported == true`. [CITED: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/]

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6.3.1 [VERIFIED: `swift --version`] | App language/concurrency | Current local toolchain; aligns with project baseline |
| Xcode / iOS SDK | Xcode 26.4.1 [VERIFIED: `xcodebuild -version`] | Build + iOS frameworks | Required Apple toolchain for AVFoundation |
| AVFoundation (`AVCaptureMultiCamSession`, `AVCaptureVideoPreviewLayer`) | System framework (iOS SDK) [CITED: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/] | MultiCam session + live preview | Official and required API surface for dual preview |
| SwiftUI + UIKit bridge (`UIViewRepresentable`) | System framework [ASSUMED] | Host preview layers + gestures | Standard for camera previews in SwiftUI apps |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Photos (`PHPhotoLibrary` auth only in this phase) | System framework [CITED: https://developer.apple.com/documentation/photos/phphotolibrary/requestauthorization%28for%3Ahandler%3A%29] | Up-front permission per D-01 | First-launch permission preflight |
| AVFoundation Synchronizer (`AVCaptureDataOutputSynchronizer`) | System framework [CITED: https://developer.apple.com/documentation/avfoundation/avcapturedataoutputsynchronizer] | Frame sync primitive for next phase | Define extension seam now, implement in Phase 2 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `AVCaptureMultiCamSession` | Two independent `AVCaptureSession`s | Not viable for stable simultaneous front+back capture on iOS [ASSUMED] |

**Installation:** No package installation required; frameworks are SDK-provided. [VERIFIED: codebase is greenfield with no package manifests]

## Architecture Patterns

### Recommended Project Structure
```text
DualVideo/
├── App/
├── Features/Camera/
│   ├── CameraManager.swift
│   ├── CameraPermissions.swift
│   ├── CameraPreviewView.swift
│   ├── PiPOverlayState.swift
│   └── UnsupportedDeviceView.swift
├── Features/Root/
└── Shared/
```

### Pattern 1: Queue-Isolated Camera Manager
**What:** All session mutation and `startRunning/stopRunning` occur on one serial queue. [ASSUMED]  
**When to use:** Always, for AVFoundation session lifecycle work.  
**Example:**
```swift
// Source: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/
final class CameraManager {
    private let session = AVCaptureMultiCamSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    func startIfReady() {
        sessionQueue.async {
            guard AVCaptureMultiCamSession.isMultiCamSupported else { return }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }
}
```

### Pattern 2: Explicit Permission Preflight
**What:** Request camera and microphone before capture setup; include blocked state. [CITED: https://developer.apple.com/documentation/avfoundation/avcapturedevice/1624584-requestaccess]  
**When to use:** First launch and when returning from Settings.

### Pattern 3: Preview Layer Bridge for SwiftUI
**What:** Use `AVCaptureVideoPreviewLayer` as backing layer in UIKit view bridged into SwiftUI. [CITED: https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer]  
**When to use:** Rendering full-bleed back preview and PiP front preview.

### Anti-Patterns to Avoid
- **Session on main thread:** Can freeze UI/startup path under load. [ASSUMED]
- **Implicit permission by creating input first:** Loses UX control and conflicts with D-01 copy flow. [CITED: https://developer.apple.com/documentation/avfoundation/avcapturedevice/1624584-requestaccess]
- **Unclamped pinch/drag state:** Violates D-07 and D-09 behavior contract. [VERIFIED: `.planning/phases/.../01-CONTEXT.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-camera capability detection | Device model lookup tables | `AVCaptureMultiCamSession.isMultiCamSupported` | Official runtime truth by OS/API [CITED: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/ismulticamsupported] |
| Live camera rendering pipeline | Custom Metal renderer for preview in Phase 1 | `AVCaptureVideoPreviewLayer` | Lowest-risk path for foundation phase [CITED: https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer] |
| Permission state storage logic | Custom persisted permission flags | System authorization APIs each launch/resume | Avoid stale local state [CITED: https://developer.apple.com/documentation/avfoundation/avcapturedevice/1624584-requestaccess] |

**Key insight:** Phase 1 is about stable bring-up; use AVFoundation’s built-in session and preview primitives directly. [VERIFIED: `.planning/research/SUMMARY.md`]

## Common Pitfalls

### Pitfall 1: Missing Info.plist Usage Strings
**What goes wrong:** App crashes when requesting access. [CITED: https://developer.apple.com/documentation/avfoundation/avcapturedevice/1624584-requestaccess]  
**Why it happens:** `NSCameraUsageDescription` / `NSMicrophoneUsageDescription` absent. [CITED: same]  
**How to avoid:** Add keys before any permission/session code.  
**Warning signs:** Exception on first permission call.

### Pitfall 2: Unsupported Hardware Path Not First-Class
**What goes wrong:** User sees broken/blank preview on unsupported devices. [ASSUMED]  
**Why it happens:** Capability check happens too late.  
**How to avoid:** Evaluate `isMultiCamSupported` before any graph creation. [CITED: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/ismulticamsupported]  
**Warning signs:** Session addInput failures, inconsistent startup.

### Pitfall 3: Gesture Math Not Safe-Area Aware
**What goes wrong:** PiP can be dragged under notch/home indicator. [ASSUMED]  
**Why it happens:** Clamping to screen bounds instead of safe area insets.  
**How to avoid:** Clamp with inset margins defined by D-07. [VERIFIED: `.planning/phases/.../01-CONTEXT.md`]  
**Warning signs:** PiP partially hidden after drag.

## Code Examples

### Capability Gate
```swift
// Source: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/ismulticamsupported
let supported = AVCaptureMultiCamSession.isMultiCamSupported
if !supported {
    // render disabled preview shell + A12+ message
}
```

### Camera/Microphone Permission Preflight
```swift
// Source: https://developer.apple.com/documentation/avfoundation/avcapturedevice/1624584-requestaccess
let cam = await AVCaptureDevice.requestAccess(for: .video)
let mic = await AVCaptureDevice.requestAccess(for: .audio)
let ready = cam && mic
```

### Preview Layer Host
```swift
// Source: https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single-camera `AVCaptureSession` assumptions | Explicit MultiCam session type + support gate | iOS 13 MultiCam introduction [ASSUMED] | Required for simultaneous front+back |
| Implicit permission prompts by side effect | Explicit preflight permission UX | Modern camera UX baseline [ASSUMED] | Predictable onboarding/blocked states |

**Deprecated/outdated:**
- `AVAudioSession` record permission path is deprecated in favor of `AVAudioApplication` APIs. [CITED: https://developer.apple.com/documentation/avfaudio/avaudiosession/requestrecordpermission%28_%3A%29?language=objc]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Queue-isolated AVFoundation manager is mandatory for stable startup | Architecture Patterns | Medium |
| A2 | Two independent `AVCaptureSession`s are not viable for this product goal | Standard Stack | Medium |
| A3 | Safe-area clamping pitfalls are common in PiP UX | Common Pitfalls | Low |
| A4 | iOS 13 is the specific MultiCam introduction point | State of the Art | Low |

## Open Questions

1. **Should Photo Library permission be requested in Phase 1 or deferred to save-time?**
- What we know: D-01 locks it to up-front request. [VERIFIED: `.planning/phases/.../01-CONTEXT.md`]
- What's unclear: Whether product wants less intrusive onboarding in future.
- Recommendation: Keep D-01 for this phase; revisit in future decision round only.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `xcodebuild` | Build/run iOS app | ✓ [VERIFIED: `command -v xcodebuild`] | Xcode 26.4.1 [VERIFIED: `xcodebuild -version`] | — |
| `swift` | Swift compilation | ✓ [VERIFIED: `command -v swift`] | 6.3.1 [VERIFIED: `swift --version`] | — |
| `xcrun` | SDK tooling/device commands | ✓ [VERIFIED: `command -v xcrun`] | 72 [VERIFIED: `xcrun --version`] | — |
| `simctl` | Simulator automation | ✗ [VERIFIED: `command -v simctl`] | — | Use Xcode UI/device-first testing |

**Missing dependencies with no fallback:**
- None.

**Missing dependencies with fallback:**
- `simctl` missing; not blocking because this phase requires physical device validation for MultiCam anyway. [ASSUMED]

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (expected once Xcode project scaffold is created) [ASSUMED] |
| Config file | none — see Wave 0 [VERIFIED: repository scan has no test config files] |
| Quick run command | `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16'` [ASSUMED] |
| Full suite command | same as quick until test matrix exists [ASSUMED] |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEV-01 | Unsupported device shows blocked UI | unit/UI | `xcodebuild test ... -only-testing:DualVideoTests/CapabilityGateTests` | ❌ Wave 0 |
| DEV-02 | Permission preflight gates session start | unit | `xcodebuild test ... -only-testing:DualVideoTests/PermissionFlowTests` | ❌ Wave 0 |
| CAP-01 | Back full preview + front PiP render state | integration/manual-device | `xcodebuild test ... -only-testing:DualVideoTests/PreviewLayoutTests` | ❌ Wave 0 |
| CAP-02 | PiP drag clamps in safe bounds | unit | `xcodebuild test ... -only-testing:DualVideoTests/PiPDragClampTests` | ❌ Wave 0 |
| CAP-03 | Zoom gesture clamps to 1.0x...3.0x | unit | `xcodebuild test ... -only-testing:DualVideoTests/ZoomClampTests` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DualVideoTests`
- **Per wave merge:** full `xcodebuild test` for app test target
- **Phase gate:** Full suite green + manual on-device smoke for MultiCam

### Wave 0 Gaps
- [ ] `DualVideoTests/CapabilityGateTests.swift` — covers DEV-01
- [ ] `DualVideoTests/PermissionFlowTests.swift` — covers DEV-02
- [ ] `DualVideoTests/PiPDragClampTests.swift` — covers CAP-02
- [ ] `DualVideoTests/ZoomClampTests.swift` — covers CAP-03
- [ ] Xcode project + test target scaffold — required before any automated test command runs

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A (no user auth surface in this phase) [VERIFIED: requirements scope] |
| V3 Session Management | no | N/A (no auth session tokens) [VERIFIED: requirements scope] |
| V4 Access Control | no | N/A (single-user local app workflow) [VERIFIED: requirements scope] |
| V5 Input Validation | yes | Validate gesture/zoom ranges and state transitions (clamped bounds) [VERIFIED: D-07/D-09] |
| V6 Cryptography | no | N/A in Phase 1 (no crypto requirements) [VERIFIED: phase scope] |

### Known Threat Patterns for iOS camera foundation

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Permission confusion / consent bypass UX | Spoofing | System permission prompts + explicit blocked state + Settings deep link |
| Resource exhaustion from invalid session setup | Denial of Service | Capability gate + controlled queue + guarded session lifecycle |
| Unsafe gesture state leading to invisible controls | Tampering | Clamp PiP/zoom to policy bounds |

## Sources

### Primary (HIGH confidence)
- https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/ - MultiCam API, support gate, hardware/system pressure cost
- https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/ismulticamsupported - runtime support detection
- https://developer.apple.com/documentation/avfoundation/avcapturedevice/1624584-requestaccess - camera/mic permission model and Info.plist requirements
- https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer - official preview rendering layer
- https://developer.apple.com/documentation/photos/phphotolibrary/requestauthorization%28for%3Ahandler%3A%29 - Photos permission API
- https://developer.apple.com/documentation/avfoundation/avcapturedataoutputsynchronizer - synchronized output API
- Local verification commands: `xcodebuild -version`, `swift --version`, `.planning/config.json`, `.planning/phases/.../01-CONTEXT.md`

### Secondary (MEDIUM confidence)
- `.planning/research/SUMMARY.md` (project-local prior synthesis; used for consistency checks)

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - core APIs and toolchain directly verified from Apple docs and local environment.
- Architecture: MEDIUM - patterns are proven, but project currently has no code scaffold.
- Pitfalls: MEDIUM - major failures are known; exact runtime behavior depends on final device matrix.

**Research date:** 2026-05-16  
**Valid until:** 2026-06-15
