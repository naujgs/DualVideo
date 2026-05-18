# Roadmap: DualVideo

## Overview

Build DualVideo in three phases: establish reliable multi-camera preview and permissions first, then implement compositor + recording pipeline, then finish with Photos save flow and UX polish/edge-case hardening.

## Phases

- [x] **Phase 1: Foundation - Permissions, Session, Live Preview** - Bring up MultiCam safely on target hardware and deliver interactive dual preview.
- [x] **Phase 2: Recording Pipeline - Compositor, Writer, Audio** - Produce a valid composited file from synchronized camera frames.
- [x] **Phase 3: Save, Polish, and Edge Cases** - Auto-save to Photos and ship expected UX quality and resilience. (completed 2026-05-17)

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
  2. Countdown + elapsed timer accurately reflect recording lifecycle.
  3. Recording survives normal app interruptions without corrupt output.
**Plans**: 3 plans

Plans:
- [x] 02-01: Implement `PiPCompositor` Metal pipeline with synchronized frame ingest
- [x] 02-02: Implement `MovieRecorder` `AVAssetWriter` state machine and audio session integration
- [x] 02-03: Wire recording controls/state model (countdown, timer, start/stop, interruption handling)

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
- [x] 03-01-PLAN.md — PhotoSaveManager, auto-save to Photos, permission re-check, save-result alert, share sheet removal (DEV-03, OUT-01, OUT-02)
- [x] 03-02-PLAN.md — PiP corner snapping with spring animation, UserDefaults corner persistence, onAppear restore (OUT-03)
- [x] 03-03-PLAN.md — Torch toggle + auto-off on interrupt, zoom label HUD, interruptionEnded recovery, orientation lock device verification (OUT-04)

### Phase 4: Video Quality and Export Options
**Goal**: Give users control over video quality, resolution, and bitrate, and add video trimming before saving to Photos.
**Depends on**: Phase 3
**Requirements**: VQ-01, VQ-02, VQ-03, VQ-04
**Success Criteria** (what must be TRUE):
  1. User can select output resolution (720p / 1080p) and bitrate (Low / Medium / High) before recording.
  2. Video trimming UI lets the user define in/out points on a recorded clip before saving.
  3. Settings persist across app launches via UserDefaults.
**Plans**: 4 plans

Plans:
- [ ] 04-01-PLAN.md — VideoQualitySettings struct + VideoTrimManager actor (TDD), Wave 0 test files (VQ-01, VQ-02, VQ-03, VQ-04)
- [ ] 04-02-PLAN.md — Pipeline wiring: MovieRecorder + PiPCompositor + CameraManager + RecordingManager + AppState (VQ-01, VQ-02, VQ-04)
- [ ] 04-03-PLAN.md — Quality settings UI: QualitySettingsButton + QualitySettingsSheet, pendingTrimURL trigger in CameraContentView (VQ-01, VQ-02, VQ-04)
- [ ] 04-04-PLAN.md — Trim UI: TrimRangeBar + TrimSheet, replace Plan 03 placeholder, human-verify checkpoint (VQ-03)

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation - Permissions, Session, Live Preview | 3/3 | Complete | 2026-05-17 |
| 2. Recording Pipeline - Compositor, Writer, Audio | 3/3 | Complete | 2026-05-17 |
| 3. Save, Polish, and Edge Cases | 3/3 | Complete   | 2026-05-17 |
| 4. Video Quality and Export Options | 0/4 | Planning | — |
