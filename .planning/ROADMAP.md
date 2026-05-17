# Roadmap: DualVideo

## Overview

Build DualVideo in three phases: establish reliable multi-camera preview and permissions first, then implement compositor + recording pipeline, then finish with Photos save flow and UX polish/edge-case hardening.

## Phases

- [ ] **Phase 1: Foundation - Permissions, Session, Live Preview** - Bring up MultiCam safely on target hardware and deliver interactive dual preview.
- [ ] **Phase 2: Recording Pipeline - Compositor, Writer, Audio** - Produce a valid composited file from synchronized camera frames.
- [ ] **Phase 3: Save, Polish, and Edge Cases** - Auto-save to Photos and ship expected UX quality and resilience.

## Phase Details

### Phase 1: Foundation - Permissions, Session, Live Preview
**Goal**: App starts `AVCaptureMultiCamSession` on supported hardware and renders live back + front preview with draggable PiP.
**Depends on**: Nothing (first phase)
**Requirements**: DEV-01, DEV-02, CAP-01, CAP-02, CAP-03
**Success Criteria** (what must be TRUE):
  1. Supported device shows both camera previews simultaneously in-app.
  2. Unsupported device path shows a clear non-blocking fallback screen.
  3. PiP drag and back-camera pinch zoom both work in live preview.
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md — Xcode project scaffold, Info.plist keys, PermissionManager actor, UnsupportedDeviceView, RootView routing
- [x] 01-02-PLAN.md — CameraActor global actor, CameraManager with AVCaptureMultiCamSession, CameraPreviewView UIViewRepresentable, dual live preview wired into RootView
- [x] 01-03-PLAN.md — PiPOverlayState drag clamp logic, DragGesture on PiP, MagnificationGesture pinch-to-zoom, human-verify checkpoint

### Phase 2: Recording Pipeline - Compositor, Writer, Audio
**Goal**: Record one composited PiP video with stable writer state management and audio.
**Depends on**: Phase 1
**Requirements**: CAP-04, REC-01, REC-02, REC-03, REC-04
**Success Criteria** (what must be TRUE):
  1. Record/Stop creates a valid 1080p `.mov` file every run.
  2. Elapsed timer accurately reflects recording lifecycle (no countdown per D-04).
  3. Recording survives normal app interruptions without corrupt output.
**Plans**: 3 plans

Plans:
- [ ] 02-01-PLAN.md — PiPCompositor Core Image pipeline (CISourceOverCompositing), AVCaptureVideoDataOutputSampleBufferDelegate, synthetic buffer unit tests
- [ ] 02-02-PLAN.md — MovieRecorder AVAssetWriter state machine (H.264/AAC), RecordingManager coordinator + elapsed timer, RecordButton + RecordingStatusOverlay UI wired into CameraContentView
- [ ] 02-03-PLAN.md — Wire compositor + dual-mic audio into CameraManager, interruption auto-stop (D-06), orphaned temp file cleanup, end-to-end device validation

### Phase 3: Save, Polish, and Edge Cases
**Goal**: Save recordings to Photos automatically and complete core UX polish features.
**Depends on**: Phase 2
**Requirements**: DEV-03, OUT-01, OUT-02, OUT-03, OUT-04
**Success Criteria** (what must be TRUE):
  1. Stopped recordings auto-save to Photos with clear success/failure feedback.
  2. PiP position persists and corner snapping behaves consistently.
  3. Torch toggle, zoom label, and orientation lock work without breaking capture.
**Plans**: 3 plans

Plans:
- [ ] 03-01: Implement photo-library save flow with robust permission and temp-file lifecycle handling
- [ ] 03-02: Add PiP snapping/persistence and recording UX feedback polish
- [ ] 03-03: Add torch/orientation controls and complete interruption/recovery edge-case handling

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation - Permissions, Session, Live Preview | 3/3 | Complete | 2026-05-16 |
| 2. Recording Pipeline - Compositor, Writer, Audio | 0/3 | Ready to execute | - |
| 3. Save, Polish, and Edge Cases | 0/3 | Not started | - |
