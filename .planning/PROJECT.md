# DualVideo

## What This Is

DualVideo is an iPhone app that records both the front and back cameras simultaneously, compositing them into a single Picture-in-Picture video file saved directly to the user's Photo Library. The back camera fills the screen; the front camera appears as a smaller draggable overlay. It targets iOS 18.0+ and runs on any iPhone with an A12 Bionic chip or newer (iPhone XR / XS and later).

## Core Value

Both cameras record together and the result lands in Photos as a single watchable video — that moment of capture must always work, even if every other feature is rough.

## Current Milestone: v1.1 — 4K Resolution Support

**Goal:** Detect whether the device's back camera supports 4K and offer it as a selectable resolution in the quality settings panel, with the full recording pipeline configured for 3840×2160 output when selected.

**Target features:**
- 4K capability detection at session startup via `AVCaptureDevice` format query
- Conditional UI: 4K option appears in `QualitySettingsSheet` only on supported hardware
- 4K recording pipeline: `PiPCompositor` and `MovieRecorder` configured for 3840×2160 output

---

## Requirements

### Validated

- [x] Show live preview of back camera full-screen and front camera as a draggable PiP overlay simultaneously — Validated in Phase 01: foundation-permissions-session-live-preview
- [x] User can drag the front-camera PiP overlay to any position on screen before or during recording — Validated in Phase 01
- [x] Pinch-to-zoom gesture controls the back camera zoom level during live preview — Validated in Phase 01
- [x] Camera, microphone, and Photo Library permissions are handled with clear prompts and graceful fallback messaging — Validated in Phase 01
- [x] Graceful detection and user-facing error when device does not support AVCaptureMultiCamSession (pre-A12 hardware) — Validated in Phase 01

### Active

- [ ] Single master Record / Stop button starts and stops both cameras in sync
- [ ] Combined PiP layout is captured into a single 1080p .mov / .mp4 file saved to Photos
- [ ] Audio is mixed from both front and back microphones into the recorded file
- [ ] 3-second countdown timer before recording begins

### Out of Scope

- App Store distribution — personal side-load only; no App Store review compliance work needed for v1
- Camera swap (back ↔ front as foreground/background) — deferred; adds complexity to compositor
- 4K recording — promoted to v1.1 milestone (hardware-gated, conditional UI)
- Cloud sync / sharing features — not needed for personal use
- Video trimming or editing within the app — Photos app handles that

## Context

- **Development machine:** MacBook Air M3 / 16 GB RAM — fast compilation, no thermal issues
- **Primary test device:** iPhone XR (A12 Bionic) — the minimum hardware that supports `AVCaptureMultiCamSession`; also used on iPhone 17 Pro Max
- **Simulator limitation:** Xcode Simulator has no camera support — physical device required for every test run
- **IDE:** Xcode is the correct choice for native iOS development; no better alternative exists for Swift/SwiftUI
- **AVCaptureMultiCamSession** is the Apple-native API for simultaneous multi-camera capture; available on A12+ devices only
- PiP compositing approach: render both `AVCaptureVideoPreviewLayer` feeds into an offscreen `CALayer` / `AVAssetWriter` pipeline, or use `AVCaptureMovieFileOutput` with pixel buffer compositor — research will confirm best pattern for iOS 18
- **Mixed audio:** `AVAudioSession` with `.record` category; configure two `AVCaptureDeviceInput` audio channels or mix via `AVMutableComposition`

## Constraints

- **Compatibility:** iOS 18.0+ minimum deployment target
- **Hardware:** `AVCaptureMultiCamSession` requires A12 Bionic or newer — must detect and communicate gracefully on older hardware
- **Physical device required:** All camera features must be tested on real iPhone; Simulator is not an option
- **Architecture:** MVVM + SwiftUI; all session logic encapsulated in `CameraManager` / `CameraController`
- **Output format:** Single `.mov` or `.mp4` file at 1080p; no split-file output

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Draggable PiP overlay | User flexibility without complexity of full resize | — Pending |
| Mixed dual-mic audio | Covers both environment and speaker — richest capture | — Pending |
| 1080p output | Balanced quality/file-size; sufficient for sharing | — Pending |
| Personal side-load only | No App Store overhead for v1 | — Pending |
| iOS 18.0+ minimum | Access to latest AVFoundation APIs; user's device is current | — Pending |
| MVVM + SwiftUI | Clean separation; `CameraManager` isolates AVFoundation complexity | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-19 — Milestone v1.1 started: 4K resolution support (hardware-gated)*
