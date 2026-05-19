# DualVideo

An iPhone app that records from both cameras simultaneously and composites them into a single Picture-in-Picture video saved directly to your Photos library.

The back camera fills the screen. The front camera appears as a draggable overlay. Hit record — one file, both perspectives.

![platform](https://img.shields.io/badge/platform-iOS%2018%2B-blue)
![swift](https://img.shields.io/badge/swift-6-orange)
![license](https://img.shields.io/badge/license-personal%20use-lightgrey)

---

## Features

- **Simultaneous dual-camera capture** using `AVCaptureMultiCamSession`
- **Draggable PiP overlay** — reposition the front camera anywhere before or during recording; snaps to corners on release
- **Pinch-to-zoom** on the back camera (1×–3×)
- **Torch toggle** with auto-off on interruption
- **Recording countdown** (3 s) and elapsed timer
- **Video quality settings** — 720p, 1080p; 30 / 60 / 120 fps
- **4K capability detection** — 4K option surfaces only on supported hardware
- **Auto-save to Photos** with success/failure feedback
- **Graceful fallback** for unsupported devices (pre-A12)

## Requirements

| Requirement | Minimum |
|-------------|---------|
| iOS | 18.0 |
| iPhone | XR / XS (A12 Bionic) or newer |
| Xcode | 16+ |

> `AVCaptureMultiCamSession` requires an A12 Bionic chip or later. The app displays a clear error on unsupported hardware rather than crashing.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6 |
| UI | SwiftUI + `@Observable` |
| Capture | AVFoundation — `AVCaptureMultiCamSession` |
| Compositor | Core Image (`CISourceOverCompositing`) with Metal-backed `CIContext` |
| Output | `AVAssetWriter` → H.264 (≤1080p) / HEVC (4K) `.mov` |
| Audio | `AVCaptureAudioDataOutput`, back-beam microphone |
| Storage | `PHPhotoLibrary` |

## Project Structure

```
DualVideo/
├── App/
│   ├── DualVideoApp.swift       # Entry point
│   └── Info.plist
├── Shared/
│   ├── AppState.swift           # Central @Observable state
│   └── GlassBackground.swift
└── Features/
    ├── Root/
    │   └── RootView.swift       # Route: capability → permissions → camera
    ├── Camera/
    │   ├── CameraManager.swift  # AVCaptureMultiCamSession lifecycle
    │   ├── CameraPreviewView.swift
    │   ├── CameraContentView.swift
    │   ├── PiPOverlayState.swift
    │   ├── PermissionManager.swift
    │   └── UnsupportedDeviceView.swift
    └── Recording/
        ├── RecordingManager.swift
        ├── MovieRecorder.swift  # AVAssetWriter state machine
        ├── PiPCompositor.swift  # Core Image frame compositor
        ├── PhotoSaveManager.swift
        ├── VideoQualitySettings.swift
        └── UI/                  # RecordButton, overlays, settings sheet
```

## Building & Running

1. Open `DualVideo.xcodeproj` in Xcode 16+
2. Select your connected iPhone as the run destination (Simulator has no camera)
3. Set your development team in **Signing & Capabilities**
4. Build and run (`⌘R`)

Camera, microphone, and photo library permissions are requested at runtime on first launch.

## Architecture Notes

The app uses MVVM with Swift 6 strict concurrency:

- **Main thread** — SwiftUI state updates and gesture handling
- **`sessionQueue`** — All `AVCaptureMultiCamSession` mutations
- **`dataOutputQueue`** — Sample buffer delegate callbacks (video + audio frames)

Properties shared across queues are marked `nonisolated(unsafe)` with explicit access guarantees documented at each site. One-frame staleness is acceptable for the PiP position snapshot read during compositing.

---

## About

A personal vibe coding project by two cousins — **Sergio & Juan** — who just wanted to experience building something together and ended up shipping a real iOS app.

No App Store. No monetization. Just a useful little tool we wanted to exist.
