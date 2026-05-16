# Project Research Summary

**Project:** DualVideo
**Domain:** iOS dual-camera simultaneous recording with real-time PiP compositing
**Researched:** 2026-05-16
**Confidence:** HIGH (core AVFoundation stack verified against Apple sample code and WWDC documentation)

---

## Executive Summary

DualVideo is a real-time dual-camera capture app that uses `AVCaptureMultiCamSession` — Apple's only session type capable of running front and back cameras simultaneously — to composite both feeds into a single PiP video file. The established expert approach, codified in Apple's own AVMultiCamPiP sample code from WWDC 2019, uses a Metal compute shader to merge two `CVPixelBuffer` streams in under 2ms per frame, feeding the result into `AVAssetWriter` for H.264 encoding. This is a narrow but well-documented technology stack with very few viable alternatives; every candidate that bypasses `AVCaptureMultiCamSession` or `AVAssetWriter` fails to meet the core requirement of producing a composited 1080p PiP video file.

The recommended architecture is strict MVVM with a clean three-layer separation: SwiftUI views observe a `RecordingViewModel`, which coordinates a `CameraManager` service that encapsulates all AVFoundation code. Two internal services — `PiPCompositor` and `MovieRecorder` — handle Metal compositing and `AVAssetWriter` lifecycle respectively and are never exposed above `CameraManager`. A custom global actor (`CameraActor`) or a dedicated serial GCD queue is required to avoid Swift 6 concurrency violations and prevent `startRunning` from blocking the main thread. Three queues (main, session, data-output) is the correct threading model — collapsing or expanding that number causes UI freezes or synchronization bugs.

The dominant risks are hardware-budget exhaustion on iPhone XR (A12), AVAssetWriter state-machine violations producing corrupt files, and Swift 6 concurrency warnings that, if suppressed rather than fixed, hide real data races. All three are fully preventable with upfront architectural decisions: use `AVCaptureDataOutputSynchronizer` for frame synchronization, wrap `beginConfiguration/commitConfiguration` in `defer`, and design the actor boundary before writing any AVFoundation code. On-device testing on iPhone XR from Phase 1 is non-negotiable — Simulator exercises none of this code.

---

## Key Findings

### Recommended Stack

The stack has essentially one correct answer at each layer, all verified against Apple's own sample code. `AVCaptureMultiCamSession` is the only session type that runs two cameras simultaneously; `AVCaptureVideoDataOutput` is the only output type that delivers raw `CVPixelBuffer` frames suitable for compositing; `AVAssetWriter` is the only writer that accepts composited pixel buffers. Metal (via `CVMetalTextureCacheCreateTextureFromImage` for zero-copy texture import) is the right compositor — Core Image adds unnecessary overhead. `AVCaptureVideoPreviewLayer` via `UIViewRepresentable` is the only viable live-preview path from SwiftUI. There is no flexibility in this stack without sacrificing correctness.

**Core technologies:**
- `AVCaptureMultiCamSession`: dual-camera session — only API that runs front + back simultaneously; A12 minimum
- `AVCaptureVideoDataOutput` (x2): raw pixel buffer delivery — required for compositor input
- `AVCaptureDataOutputSynchronizer`: frame synchronization — eliminates timestamp-matching problem between two camera outputs
- Metal + `CVMetalTextureCacheCreateTextureFromImage`: zero-copy compositor — 0.2–1.5ms per frame, fits 30fps budget
- `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`: file writing — only path that accepts pre-composited buffers
- H.264 / MPEG-4 AAC: output codec — Photos-compatible, appropriate for iPhone XR, 1080p target
- `AVCaptureVideoPreviewLayer` via `UIViewRepresentable`: live preview — hardware-accelerated, zero CPU copy, mandatory UIKit bridge
- `@Observable` (`RecordingViewModel`, `CameraManager`): state management — iOS 17+ API, finer-grained observation than `ObservableObject`
- iOS 18.0 minimum: deployment target — grants `videoRotationAngle` (non-deprecated orientation API); A12 hardware floor

### Expected Features

The MVP critical path is: hardware detection → permissions (camera + mic) → live dual preview → compositor pipeline → record/stop → auto-save. Everything else layers on top.

**Must have (table stakes):**
- Live preview of both cameras simultaneously — core premise; absence is instant abandonment
- Single tap to start/stop recording — universal camera app pattern
- 3-second countdown before recording — standard pattern; users miss first second without it
- Auto-save to Photos on stop — no manual export step; friction kills personal-use apps
- Elapsed recording time display (red dot + MM:SS) — recording anxiety without it
- PiP overlay draggable to reposition — expected by every comparable app
- Pinch-to-zoom on back camera — muscle memory; absence feels broken
- Permission prompts with clear explanations — required by iOS; silence causes trust failure
- Graceful "permissions denied" state with Settings deep-link
- Graceful "hardware not supported" state (pre-A12 devices)

**Should have (competitive differentiators):**
- Corner snapping for PiP overlay — Apple's native Dual Capture does NOT snap; this is a genuine differentiator
- Haptic feedback on record start/stop — `UIImpactFeedbackGenerator`; requires `setAllowHapticsAndSystemSoundsDuringRecording(true)`
- Persistent PiP position across sessions — `UserDefaults`; no competitor documents this
- Zoom level label (e.g., `1.4x`) near back camera preview
- Flash/torch toggle for video recording
- Orientation lock toggle once recording begins

**Defer to v2+:**
- Split-screen 50/50 layout — doubles compositor complexity; not the product thesis
- Camera swap (front becomes background) — requires full pipeline rewire
- Separate file export per camera — single merged file is the correct personal-use output
- 4K output — fills storage; dual 4K saturates A15 thermal budget
- Audio level VU indicator — medium complexity; value is low for personal use
- In-app trim, filters, social sharing, pause/resume — out of scope per PROJECT.md

### Architecture Approach

The app follows strict MVVM where views import only SwiftUI, the ViewModel imports no AVFoundation types, and `CameraManager` owns the entire capture stack. Two nested services — `PiPCompositor` and `MovieRecorder` — are internal to `CameraManager` and invisible to the ViewModel. Three dedicated queues (main, `sessionQueue`, `dataOutputQueue`) handle UIKit/SwiftUI updates, session configuration, and frame delivery respectively. `RecordingViewModel` owns a well-typed `RecordingState` enum that drives all conditional UI; `CameraManager` owns a separate session setup state machine. The `AVCaptureDataOutputSynchronizer` delivers both camera frames in a single callback at the same `CMTime`, eliminating the timestamp-matching problem.

**Major components:**
1. `CameraManager` — owns `AVCaptureMultiCamSession`, all inputs/outputs, `PiPCompositor`, `MovieRecorder`; publishes state only
2. `PiPCompositor` — Metal compute shader merges back + front `CVPixelBuffer` into single composited 1080p frame
3. `MovieRecorder` — `AVAssetWriter` wrapper; strict state machine: startWriting, startSession, append, markAsFinished, finishWriting
4. `RecordingViewModel` — `@Observable` state machine (idle, countdown, recording, saving, done/error); coordinates above services; no AVFoundation imports
5. `PhotoLibrarySaver` — isolated service; saves temp `.mov` URL to `PHPhotoLibrary`, deletes temp file on success
6. `PermissionManager` — checks and requests camera, microphone, photo-library permissions in sequence before any session setup
7. `CameraPreviewView` — `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer`; zero logic; instantiated twice (back full-screen, front PiP)

### Critical Pitfalls

1. **Hardware cost budget exceeded on A12** — log `session.hardwareCost` after `commitConfiguration()`; if >= 0.9, downgrade front camera to binned 720p. Lowering frame rate at runtime does NOT reduce cost; format selection does.
2. **`startRunning` on main thread** — always dispatch to `sessionQueue`; iOS 18.0/18.1 has a confirmed 10-second freeze if violated during MultiCam audio attachment.
3. **`beginConfiguration` without guaranteed `commitConfiguration`** — always use `defer { session.commitConfiguration() }` immediately after `session.beginConfiguration()`.
4. **AVAssetWriter state-machine violations** — stop sequence must be: stop buffer flow, `markAsFinished()` on all inputs, `finishWriting(completionHandler:)`; never append after stop, never `finishWriting` concurrently with append.
5. **Pixel buffer pool exhaustion** — delegate callbacks must be fast; copy `CVPixelBuffer` out and release `CMSampleBuffer` immediately; use `AVAssetWriterInputPixelBufferAdaptor.pixelBufferPool` for output allocation.
6. **Audio session misconfiguration** — set `session.automaticallyConfiguresApplicationAudioSession = false` and explicitly configure `AVAudioSession` before adding inputs; observe `AVAudioSessionInterruptionNotification`.
7. **Swift 6 concurrency vs. GCD AVFoundation** — design a `@globalActor CameraActor` before writing any AVFoundation code; do not mark `CameraManager` as `@MainActor`.

---

## Implications for Roadmap

### Phase 1: Foundation — Permissions, Session, Live Preview

**Rationale:** Nothing else can be built without a running `AVCaptureMultiCamSession` delivering live preview on the target device. Permissions must be verified before hardware is touched. Swift 6 concurrency actor boundary must be established before any AVFoundation code is written — retrofitting is extremely painful.

**Delivers:** App launches, requests permissions in correct order, detects hardware support, starts MultiCam session, shows live back + front camera preview with draggable PiP overlay. No recording yet.

**Addresses:** Hardware detection, all three permissions (camera, microphone, photos), live dual preview, draggable PiP overlay, pinch-to-zoom, basic orientation handling.

**Avoids:**
- Validate `hardwareCost` on iPhone XR immediately after `commitConfiguration()`; adjust front camera format if needed
- Architect `sessionQueue` from the first line of `CameraManager`
- Use `defer` for `commitConfiguration()` from first configuration call
- Design `CameraActor` before writing any AVFoundation code
- Device-only workflow established from day 1

**Research flag:** Standard patterns — Apple AVMultiCamPiP sample code covers this phase almost entirely. Skip phase research.

---

### Phase 2: Recording Pipeline — Compositor, Writer, Audio

**Rationale:** The compositor and writer are independent sub-systems that should be verified standalone before being wired together. `MovieRecorder` should be tested with synthetic pixel buffers before connecting to live camera data. `PiPCompositor` correctness can be verified with two static images before live frames arrive.

**Delivers:** Tapping record starts a composited recording; tapping stop finalizes the `AVAssetWriter` and produces a valid `.mov` file in the app's temp directory. Elapsed timer displays. Countdown before recording starts. Haptic feedback on start/stop. One audio track (back camera mic).

**Addresses:** Record/stop button, countdown timer, elapsed time display, Metal compositor, AVAssetWriter pipeline, single audio track, haptic feedback.

**Avoids:**
- `MovieRecorder` implements strict state machine with correct stop sequence
- Frame callback copies buffer and releases `CMSampleBuffer` immediately; uses pixel buffer pool for output allocation
- `AVAudioSession` configured before session starts; interruption handling added in this phase
- Observe `UIApplication.willResignActiveNotification`; stop and save current recording gracefully on background

**Research flag:** The Metal compositor shader is well-documented conceptually but the specific compute kernel for PiP blending (scaling, positioning, alpha compositing) may benefit from reviewing Apple's AVMultiCamPiP sample shader code directly before implementation.

---

### Phase 3: Save, Polish, and Edge Cases

**Rationale:** Photos save depends on a valid file from Phase 2. Polish features (corner snapping, persistent PiP position, zoom label, torch, orientation lock) are all additive and non-breaking. This phase closes all edge cases identified in pitfalls research.

**Delivers:** Auto-save to Photos with success toast; corner snapping on PiP drag release; persistent PiP position across sessions; zoom level label; torch toggle; orientation lock toggle; complete background-interruption handling; polished permission-denied and hardware-unsupported error screens.

**Addresses:** Auto-save, success toast, corner snapping, `UserDefaults` PiP persistence, zoom label, torch, orientation lock, graceful error states.

**Avoids:**
- Never delete temp file until `performChanges` completion fires with `success == true`
- Dispatch UI updates from `performChanges` completion handler to main queue

**Research flag:** Standard patterns. Skip phase research.

---

### Phase Ordering Rationale

- Session must come before compositor: cannot validate hardware cost, format selection, or frame delivery without a running session. All Phase 2 work depends on confirmed Phase 1 output.
- Compositor before writer: `PiPCompositor` can be tested with static pixel buffers, isolating compositor bugs from writer bugs.
- Writer verified standalone before wiring: `MovieRecorder` should produce a valid file from synthetic input before receiving compositor output.
- Save path last: `PhotoLibrarySaver` depends only on a valid file URL and can be added after any working recording exists; deferring avoids premature Photos permission requests during development.
- Actor boundary upfront: the Swift 6 concurrency architecture is the one decision that cannot be retrofitted without rewriting `CameraManager` from scratch.

### Research Flags

Phases needing deeper research during planning:
- **Phase 2 (Metal compositor shader):** PiP blending kernel specifics — review Apple's AVMultiCamPiP sample shader before writing custom Metal code.

Phases with standard patterns (skip research-phase):
- **Phase 1:** AVMultiCamPiP Apple sample code covers session setup, format selection, and preview layer integration completely.
- **Phase 3:** PHPhotoLibrary save, UserDefaults persistence, gesture polish — all standard iOS patterns with extensive documentation.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified against Apple AVMultiCamPiP sample code, WWDC 2019 Session 249, and official Apple documentation. No ambiguity at any layer. |
| Features | MEDIUM-HIGH | Table stakes verified against 4 comparable App Store apps. Differentiators based on App Store listings and reviews — MEDIUM for competitor feature accuracy. |
| Architecture | HIGH | Based on Apple WWDC 2019 Session 249 and AVMultiCamPiP sample code structure. Threading model and state machine directly derived from Apple source. |
| Pitfalls | HIGH | Most critical pitfalls have Apple documentation links, confirmed community reproduction, and open-source crash reports. iOS 18 main-thread freeze confirmed via HaishinKit community discussion. |

**Overall confidence:** HIGH

### Gaps to Address

- **Hardware cost on iPhone XR at 1080p back + 720p front:** Reported as near budget ceiling but exact `hardwareCost` value with the binned front format has not been measured on a physical XR. Must be validated in Phase 1 before committing to the format configuration.
- **iOS 18.0/18.1 `startRunning` freeze:** Community-confirmed but exact trigger conditions are not fully characterized. Deferring `startRunning` to first user gesture is the documented workaround; validate this eliminates the freeze on the target device.
- **Haptic + audio session interaction:** `setAllowHapticsAndSystemSoundsDuringRecording(true)` is documented as required, but the interaction with `automaticallyConfiguresApplicationAudioSession = false` on `AVCaptureMultiCamSession` is unverified. Validate haptics fire correctly during recording without disrupting audio.
- **Swift 6 strict concurrency with custom global actor + AVFoundation delegates:** Community guidance on the `@globalActor` pattern for camera apps exists but is not an official Apple pattern. Needs early validation to confirm no data-race warnings at `SWIFT_STRICT_CONCURRENCY = complete`.

---

## Sources

### Primary (HIGH confidence)
- Apple AVMultiCamPiP Sample Code — session setup, compositor architecture, frame synchronization
- WWDC 2019 Session 249 "Introducing Multi-Camera Capture for iOS" — MultiCam session constraints, hardware cost
- Apple Developer Documentation: AVCaptureMultiCamSession, AVAssetWriterInputPixelBufferAdaptor, AVCaptureDataOutputSynchronizer, CVMetalTextureCacheCreateTextureFromImage

### Secondary (MEDIUM confidence)
- App Store listings and reviews: DualCapture, DoubleTake by Filmic, MixCam, iPhone 17 native Dual Capture (feature comparison)
- HaishinKit.swift community discussion — iOS 18.0/18.1 startRunning main-thread freeze
- Fatbobman: "Swift 6 Refactoring in a Camera App" — globalActor pattern for AVFoundation
- Nonstrict.eu: "Distorted Audio when recording with AVCaptureSession" (2025) — audio session configuration

### Tertiary (needs on-device validation)
- Hardware cost headroom on iPhone XR with back 1080p + front 720p binned — requires physical device measurement
- Haptic + automaticallyConfiguresApplicationAudioSession = false interaction — unverified combination

---

*Research completed: 2026-05-16*
*Ready for roadmap: yes*
