# Architecture Research — DualVideo

**Researched:** 2026-05-16
**Confidence:** HIGH — based on Apple WWDC 2019 session 249, Apple AVMultiCamPiP sample code structure, and verified AVFoundation threading documentation.

---

## Component Map

| Component | Layer | Responsibility | Owns |
|-----------|-------|---------------|------|
| `ContentView` | View | Root layout: full-screen back preview + PiP overlay + controls | Nothing stateful |
| `RecordingControlsView` | View | Countdown display, record/stop button, zoom indicator | Nothing stateful |
| `CameraPreviewView` | View | `UIViewRepresentable` wrapper around `AVCaptureVideoPreviewLayer` | One `UIView` per camera |
| `RecordingViewModel` | ViewModel | Recording state machine, gesture handling, countdown timer, error presentation | `@Observable`, refs `CameraManager` |
| `CameraManager` | Service | All AVFoundation logic: session lifecycle, inputs, outputs, compositor, writer | `AVCaptureMultiCamSession`, `PiPCompositor`, `MovieRecorder` |
| `PiPCompositor` | Service | Merges back + front pixel buffers into one composited frame | Metal or Core Image render pipeline |
| `MovieRecorder` | Service | `AVAssetWriter` lifecycle: start, append buffers, finish, write to temp file | `AVAssetWriter`, `AVAssetWriterInput` |
| `PhotoLibrarySaver` | Service | Takes a file URL, saves to `PHPhotoLibrary`, deletes temp file | No session state |
| `PermissionManager` | Service | Checks and requests camera, microphone, photo library authorization | No capture state |

### Component Boundary Rules

- Views never import AVFoundation. They observe `RecordingViewModel` only.
- `RecordingViewModel` never directly touches `AVCaptureSession` or buffers. It calls `CameraManager` methods and reads published state.
- `CameraManager` never imports SwiftUI. It publishes state via `@Observable` properties that the ViewModel reads.
- `PiPCompositor` and `MovieRecorder` are owned and called only by `CameraManager`. They are internal implementation details — the ViewModel does not know they exist.
- `PhotoLibrarySaver` is called by `CameraManager` after `MovieRecorder` finishes (or optionally by ViewModel as a thin coordination step).

---

## Data Flow

### Live Preview Path (no-copy, hardware accelerated)

```
Hardware sensors
  → AVCaptureMultiCamSession (back input port → back preview connection)
                             (front input port → front preview connection)
  → AVCaptureVideoPreviewLayer (back)  — rendered by CameraPreviewView (full-screen)
  → AVCaptureVideoPreviewLayer (front) — rendered by CameraPreviewView (PiP overlay)
```

Preview layers are CALayer-backed and hardware-accelerated. No CPU copy occurs on this path.

### Recording Path (pixel buffer compositor)

```
AVCaptureMultiCamSession
  → AVCaptureVideoDataOutput (back)  ─┐
  → AVCaptureVideoDataOutput (front) ─┤→ AVCaptureDataOutputSynchronizer
                                       │    (delivers both frames in one callback,
                                       │     same presentation timestamp)
                                       ↓
                               PiPCompositor.mix(back:front:pipFrame:)
                                       │  (Metal shader or CIFilter overlay)
                                       ↓
                               CVPixelBuffer (composited 1080p frame)
                                       ↓
                               MovieRecorder.appendVideoBuffer(_:at:)
                                       ↓
                               AVAssetWriterInputPixelBufferAdaptor
                                       ↓
                               AVAssetWriter → temp .mov in app container
```

### Audio Path

```
AVCaptureMultiCamSession
  → AVCaptureAudioDataOutput (back mic)  ─┐
  → AVCaptureAudioDataOutput (front mic) ─┤
                                           │  Note: mixing two mic tracks in real-time
                                           │  is complex. Recommended approach:
                                           │  record ONE mic (back) during capture,
                                           │  or use AVCaptureDataOutputSynchronizer
                                           │  to pick the dominant audio track.
                                           ↓
                               MovieRecorder.appendAudioBuffer(_:at:)
                                       ↓
                               AVAssetWriterInput (audio track)
                                       ↓
                               Muxed into same temp .mov
```

**Audio simplification note:** True dual-mic mixing into a single real-time track requires a Core Audio mixing graph, which adds significant complexity. The simpler approach — selecting one microphone (back camera mic) for recording — satisfies the core requirement and is a Phase 1 decision. Dual-mic mixing can be added in a later phase.

### Save Path

```
MovieRecorder finishes writing
  → temp file URL in app's tmp/ directory
  → PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
    }
  → on completion: delete temp file, publish .done state to ViewModel
```

---

## Threading Model

Three queues are required. Using more creates synchronization bugs; collapsing them blocks the UI or drops frames.

| Queue | Name | Type | What Runs On It |
|-------|------|------|----------------|
| Main | `DispatchQueue.main` | System | UI updates, `@Observable` property mutations that drive SwiftUI, `CALayer` preview attachment |
| Session queue | `sessionQueue` (serial) | Private | `session.beginConfiguration/commitConfiguration`, `session.startRunning/stopRunning`, adding/removing inputs and outputs. These calls block — never run on main. |
| Data output queue | `dataOutputQueue` (serial) | Private | `AVCaptureDataOutputSynchronizer` delegate callback, `PiPCompositor.mix()`, `MovieRecorder.appendVideoBuffer/appendAudioBuffer`. Must be serial to guarantee frame ordering. |

### Queue Rules

- `session.startRunning()` blocks the calling thread. Always call from `sessionQueue`.
- `AVCaptureVideoDataOutput.setSampleBufferDelegate(_:queue:)` — pass `dataOutputQueue`. The delegate fires on whatever queue you specify.
- `AVAssetWriter` calls (startWriting, startSession, append, finishWriting) must all happen on the same serial queue. Using `dataOutputQueue` for append and a separate completion queue for finish is a common source of crashes — keep them on `dataOutputQueue`.
- `AVCaptureVideoPreviewLayer` can be added to a view's layer from the main queue after `session.beginConfiguration()` is called on the session queue. Attach preview layers before `commitConfiguration()`.
- Never mutate `@Observable` published properties from `dataOutputQueue` directly. Use `DispatchQueue.main.async { }` to hop to main for any state that drives SwiftUI.

### Canonical Queue Setup in CameraManager

```swift
private let sessionQueue = DispatchQueue(label: "com.dualvideo.session")
private let dataOutputQueue = DispatchQueue(label: "com.dualvideo.dataoutput",
                                            qos: .userInitiated)
```

---

## State Machine

`RecordingViewModel` owns the state. `CameraManager` owns the session running state. These are separate.

### Session Setup States (CameraManager internal)

```
.uninitialized
    → .checkingPermissions (async)
        → .permissionDenied  [terminal — show settings prompt]
        → .hardwareUnsupported  [terminal — show error, A12 not detected]
        → .configuring (sessionQueue)
            → .configurationFailed  [terminal — show error]
            → .ready  [session running, previews live]
```

### Recording States (RecordingViewModel published)

```
.idle
    ─[tap record]→ .countdown(secondsRemaining: 3)
                       ─[timer tick]→ .countdown(2) → .countdown(1)
                       ─[timer fires]→ .recording(startedAt: Date)
                                           ─[tap stop]→ .saving
                                                            ─[write complete]→ .done(assetID: String?)
                                                            ─[write error]→ .error(RecordingError)
    ─[any error]→ .error(RecordingError)
                       ─[user dismisses]→ .idle
```

### State Enum

```swift
enum RecordingState: Equatable {
    case idle
    case countdown(secondsRemaining: Int)
    case recording(startedAt: Date)
    case saving
    case done(assetLocalIdentifier: String?)
    case error(RecordingError)
}

enum RecordingError: Error, Equatable {
    case permissionDenied(PermissionType)
    case hardwareUnsupported
    case sessionConfigurationFailed
    case writerSetupFailed
    case writeFailed(underlying: String)
    case photoLibrarySaveFailed(underlying: String)
}

enum PermissionType { case camera, microphone, photoLibrary }
```

### Countdown Timer

The countdown is owned by `RecordingViewModel`. Use a `Task` with `try await Task.sleep(for: .seconds(1))` in a loop, or a `Timer.publish` stream. Do not put timer logic in `CameraManager`. The ViewModel transitions `.countdown(n)` → `.recording` and then calls `cameraManager.startRecording()`.

---

## Build Order

Dependencies flow upward. Build lower layers first.

```
Layer 0 — Foundation (no dependencies)
  PermissionManager
  RecordingState enum + RecordingError enum

Layer 1 — Capture Infrastructure (depends on Layer 0)
  CameraManager (session setup, inputs, preview layers, hardware check)
  CameraPreviewView (UIViewRepresentable — thin wrapper, no logic)

Layer 2 — Recording Pipeline (depends on Layer 1)
  MovieRecorder (AVAssetWriter wrapper)
  PiPCompositor (pixel buffer merging)
  [Wire CameraManager → AVCaptureDataOutputSynchronizer → PiPCompositor → MovieRecorder]

Layer 3 — Save & State (depends on Layer 2)
  PhotoLibrarySaver
  RecordingViewModel (state machine, countdown, coordinates all of the above)

Layer 4 — UI (depends on Layer 3)
  RecordingControlsView
  ContentView (layout: previews + controls + gestures)
```

### Rationale for This Order

- **CameraManager before ViewModel:** The ViewModel is thin coordination logic. You cannot test or use it without a working session.
- **MovieRecorder before wiring compositor:** The writer needs to be verified standalone (start → append fake buffers → finish → check output file) before connecting to live camera data.
- **PiPCompositor after MovieRecorder:** Compositor correctness can be verified by feeding it two static pixel buffers and checking the output, independent of the recording pipeline.
- **Save path late:** PHPhotoLibrary authorization and save logic is isolated and easily added after recording produces a valid file.
- **UI last:** SwiftUI views are thin and fast to build once the data model is stable.

---

## MVVM Breakdown

### View Layer — SwiftUI only, no AVFoundation

| View | Responsibility |
|------|---------------|
| `ContentView` | Root ZStack: back preview fills screen, PiP overlay positioned by `@State pipPosition`, controls at bottom |
| `CameraPreviewView` | `UIViewRepresentable`. Accepts `AVCaptureVideoPreviewLayer`. Sets `videoGravity` to `.resizeAspectFill`. No logic. |
| `RecordingControlsView` | Displays countdown number during `.countdown` state, record/stop button, error banner. Reads from ViewModel only. |
| `PiPOverlayView` | Draggable container around the front camera `CameraPreviewView`. Exposes drag gesture, calls `viewModel.updatePipPosition(_:)`. |

**Gestures that belong in View:** drag position (local `@State`), pinch zoom gesture recognizer (calls `viewModel.setZoom(_:)`). The ViewModel does not store raw gesture values.

### ViewModel Layer — `@Observable`, no AVFoundation types exposed

`RecordingViewModel` publishes:
- `recordingState: RecordingState` — drives all conditional UI
- `zoomLevel: CGFloat` — shown in a label, clamped by CameraManager's actual range
- `pipPosition: CGPoint` — used by PiPOverlayView; stored here so it survives view re-renders
- `errorMessage: String?` — derived from `RecordingState.error` for alert presentation

`RecordingViewModel` handles:
- `tapRecord()` / `tapStop()` — state transitions, countdown Task
- `setZoom(_ factor: CGFloat)` — delegates to `cameraManager.setBackCameraZoom(_:)`
- `updatePipPosition(_ point: CGPoint)` — stores position, passes to compositor for recording

`RecordingViewModel` does NOT:
- Import AVFoundation
- Hold `AVCaptureSession`, pixel buffers, or file URLs
- Know about queues or threading

### CameraManager Layer — `@Observable`, encapsulates all AVFoundation

Published state (read by ViewModel):
- `sessionState: SessionState` — .uninitialized → .ready / .failed / .unsupported
- `isRecording: Bool` — set on session queue, published to main queue
- `backCameraPreviewLayer: AVCaptureVideoPreviewLayer`
- `frontCameraPreviewLayer: AVCaptureVideoPreviewLayer`
- `backCameraZoomRange: ClosedRange<CGFloat>` — exposed so ViewModel can clamp slider

Methods called by ViewModel:
- `func configure() async` — runs permission check then session setup
- `func startRecording(pipFrame: CGRect)` — transitions writer, starts synchronizer
- `func stopRecording() async throws -> URL` — finalizes writer, returns temp file URL
- `func setBackCameraZoom(_ factor: CGFloat)` — clamps and applies to `AVCaptureDevice`

Internal, not exposed:
- `sessionQueue`, `dataOutputQueue`
- `AVCaptureDataOutputSynchronizer` delegate
- `PiPCompositor` instance
- `MovieRecorder` instance

### Model Layer

There is no traditional "Model" in the data-persistence sense — the app has no database or network layer. The Model role is filled by:
- Value types: `RecordingState`, `RecordingError`, `PermissionType` enums
- `PHAsset` local identifier (String) returned after successful save — stored transiently in `.done` state

---

## Preview Layer Integration Decision

**Recommendation: `AVCaptureVideoPreviewLayer` via `UIViewRepresentable` — not Metal.**

Rationale:
- `AVCaptureVideoPreviewLayer` is hardware-accelerated in the driver. It has near-zero latency and zero CPU copy cost for preview.
- Metal (`MTKView`) is appropriate when you need to apply real-time visual filters to the preview itself. DualVideo does not — the live preview is for framing only.
- The compositor (`PiPCompositor`) uses Metal or Core Image for combining pixel buffers destined for the file. That is a separate pipeline from the visible preview.
- `AVCaptureVideoPreviewLayer` handles orientation and aspect ratio automatically on iOS 18.
- Mixing Metal preview with a separate Metal compositor adds synchronization complexity with no user-visible benefit.

The two `AVCaptureVideoPreviewLayer` instances (back full-screen, front PiP) are created by `CameraManager`, stored as published properties, and passed into two `CameraPreviewView` instances via ViewModel. The views attach the layers to their underlying `UIView.layer`.

---

## Key Architecture Decisions and Rationale

| Decision | Rationale |
|----------|-----------|
| `AVCaptureDataOutputSynchronizer` instead of two independent delegates | Guarantees both camera frames arrive with the same `CMTime` in a single callback. Eliminates the timestamp-matching problem you would otherwise have to solve manually in `PiPCompositor`. |
| Separate `sessionQueue` and `dataOutputQueue` | Session configuration blocks — must not block main. Frame callbacks fire 30/60 fps — must not block session configuration. Keeping them separate prevents priority inversion. |
| `MovieRecorder` as a separate class from `CameraManager` | Writer lifecycle (startWriting → startSession → append → finishWriting) is a distinct state machine from session lifecycle. Separation makes both independently testable and prevents the class from growing unmanageable. |
| Temp file in app container, then `PHPhotoLibrary` save | `AVAssetWriter` requires a file URL it controls. Writing directly to Photos is not possible. The temp-then-save pattern is the only supported approach. Always delete the temp file after a successful or failed save. |
| `@Observable` over `ObservableObject` + `@Published` | iOS 18 target means `@Observable` (introduced in iOS 17) is fully available. It provides finer-grained observation (only properties that are actually read by a view trigger re-renders), reducing unnecessary redraws in a high-frequency data app. |
| Compositor in `CameraManager` scope, not in ViewModel | Compositor touches raw pixel buffers and runs on `dataOutputQueue`. ViewModel runs on main queue. Crossing that boundary for every frame (30–60 fps) would be catastrophically expensive. |

---

## Sources

- Apple WWDC 2019 Session 249 "Introducing Multi-Camera Capture for iOS" — https://developer.apple.com/videos/play/wwdc2019/249/
- Apple AVMultiCamPiP sample code structure — https://developer.apple.com/documentation/AVFoundation/avmulticampip-capturing-from-multiple-cameras
- Community reproduction of AVMultiCamPiP architecture — https://github.com/tatetate55/iOS13_camera_test/blob/master/AVMultiCamPiP/CameraViewController.swift
- AVCaptureDataOutputSynchronizer — https://developer.apple.com/documentation/avfoundation/avcapturedataoutputsynchronizer
- AVCaptureVideoDataOutput threading — https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput
- AVAssetWriterInputPixelBufferAdaptor — https://developer.apple.com/documentation/avfoundation/avassetwriterinputpixelbufferadaptor
- objc.io "Capturing Video on iOS" — https://www.objc.io/issues/23-video/capturing-video/
- PHPhotoLibrary save pattern — https://developer.apple.com/forums/thread/658402
