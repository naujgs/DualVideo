# Roadmap: DualVideo

## Overview

Build DualVideo in three phases: establish reliable multi-camera preview and permissions first, then implement compositor + recording pipeline, then finish with Photos save flow and UX polish/edge-case hardening.

## Phases

- [x] **Phase 1: Foundation - Permissions, Session, Live Preview** - Bring up MultiCam safely on target hardware and deliver interactive dual preview.
- [x] **Phase 2: Recording Pipeline - Compositor, Writer, Audio** - Produce a valid composited file from synchronized camera frames.
- [x] **Phase 3: Save, Polish, and Edge Cases** - Auto-save to Photos and ship expected UX quality and resilience. (completed 2026-05-17)
- [x] **Phase 4: Video Quality and Export Options** - Give users control over quality, resolution, bitrate, and trimming.
- [ ] **Phase 5: UI Polish** - Reorganize camera controls layout and apply glass/material visual style across all controls.
- [ ] **Phase 6: Compositor Polish** - Apply 12pt rounded corners to the PiP overlay in the saved video compositor output.

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
- [x] 04-01-PLAN.md — VideoQualitySettings struct + VideoTrimManager actor (TDD), Wave 0 test files (VQ-01, VQ-02, VQ-03, VQ-04)
- [x] 04-02-PLAN.md — Pipeline wiring: MovieRecorder + PiPCompositor + CameraManager + RecordingManager + AppState (VQ-01, VQ-02, VQ-04)
- [x] 04-03-PLAN.md — Quality settings UI: QualitySettingsButton + QualitySettingsSheet, pendingTrimURL trigger in CameraContentView (VQ-01, VQ-02, VQ-04)
- [x] 04-04-PLAN.md — Trim UI: TrimRangeBar + TrimSheet, replace Plan 03 placeholder, human-verify checkpoint (VQ-03)

### Phase 5: UI Polish
**Goal**: Camera controls are repositioned and every control displays a cohesive glass/material background.
**Depends on**: Phase 4
**Requirements**: LAYOUT-01, LAYOUT-02, GLASS-01, GLASS-02, GLASS-03
**Success Criteria** (what must be TRUE):
  1. Zoom label (1.0x, 1.5x…) appears directly above the record button in the bottom-center area, not in the left column.
  2. Quality settings button appears at the bottom-right of the screen, not in the left column.
  3. Zoom label, torch toggle, and quality button all display a glass/material background (no black opacity rectangle visible).
  4. On iOS 26+, controls use `.glassEffect()`; on iOS 18–25, `.ultraThinMaterial` is used — both render without visual artifacts.
  5. Recording status overlay (elapsed time capsule) matches the glass style of the other controls with no visual inconsistency.
**Plans**: 2 plans
**UI hint**: yes

Plans:
- [ ] 05-01-PLAN.md — GlassBackground.swift shared modifier + ZoomPresetView (replaces ZoomLabelView), three tappable glass capsule buttons (GLASS-01, GLASS-02, LAYOUT-01)
- [ ] 05-02-PLAN.md — CameraContentView layout restructure + TorchToggleButton/QualitySettingsButton glass + sheet glass + human-verify checkpoint (LAYOUT-01, LAYOUT-02, GLASS-01, GLASS-02, GLASS-03)

### Phase 6: Compositor Polish
**Goal**: The PiP overlay in the saved video file has the same 12pt rounded corners as the live preview overlay.
**Depends on**: Phase 4
**Requirements**: COMPOSITOR-01
**Success Criteria** (what must be TRUE):
  1. A saved recording viewed in Photos shows the front-camera PiP with rounded corners (visually matching the live preview).
  2. The rounded-corner mask does not clip, bleed, or produce artifacts at any supported resolution (720p and 1080p).
  3. The compositor change does not affect audio sync or file writing reliability.
**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation - Permissions, Session, Live Preview | 3/3 | Complete | 2026-05-17 |
| 2. Recording Pipeline - Compositor, Writer, Audio | 3/3 | Complete | 2026-05-17 |
| 3. Save, Polish, and Edge Cases | 3/3 | Complete   | 2026-05-17 |
| 4. Video Quality and Export Options | 4/4 | Complete | 2026-05-17 |
| 5. UI Polish | 0/2 | Not started | — |
| 6. Compositor Polish | 0/? | Not started | — |
