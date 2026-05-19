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
- [ ] **Phase 7: 4K Capability Detection and Conditional UI** - Detect 4K MultiCam viability at session startup and expose 4K as a selectable option only on hardware that passes the trial configuration check.
- [ ] **Phase 8: 4K Recording Pipeline** - Configure the full recording path for 3840x2160 output: HEVC codec, correct pixel buffer pool, front camera capped at 1080p, PiP coordinate scaling, and hardwareCost revert guard.
- [ ] **Phase 9: Localization Infrastructure and Code Fixes** - Configure Xcode for Spanish/English localization, create String Catalogs, and fix computed properties so all UI strings are catalog-eligible.
- [ ] **Phase 10: Spanish Translations** - Fill all Spanish translations in both String Catalogs including permission descriptions and plural variants.
- [ ] **Phase 11: Localization Validation** - Verify every app screen and recording workflow displays correctly in Spanish on a physical device.

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
- [x] 05-01-PLAN.md — GlassBackground.swift shared modifier + ZoomPresetView (replaces ZoomLabelView), three tappable glass capsule buttons (GLASS-01, GLASS-02, LAYOUT-01)
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

### Phase 7: 4K Capability Detection and Conditional UI
**Goal**: Users on capable hardware see 4K as a selectable resolution in the quality panel, and users on all other hardware see no 4K option at all.
**Depends on**: Phase 4
**Requirements**: K4-01, K4-02, K4-05
**Success Criteria** (what must be TRUE):
  1. On iPhone XR (A12), the quality panel contains no 4K option and `CameraManager.supports4K` is false after session startup.
  2. On a 4K-capable device (A15 Pro or newer), the quality panel shows 4K as a selectable resolution after session startup.
  3. The quality panel displays a live recording-time estimate (e.g. "~12 min remaining") that updates when the user switches resolution.
  4. A saved 4K quality setting on a non-4K device silently falls back to 1080p before session start — no crash or error alert.
**Plans**: TBD
**UI hint**: yes

### Phase 8: 4K Recording Pipeline
**Goal**: When 4K is selected on a capable device, the app records and saves a valid 3840x2160 HEVC file with the front camera capped at 1080p and no hardware cost overrun.
**Depends on**: Phase 7
**Requirements**: K4-03, K4-04
**Success Criteria** (what must be TRUE):
  1. A recording started with 4K selected produces a `.mov` file readable in Photos at 3840x2160 resolution.
  2. Front camera input is confirmed at 1920x1080 (not 4K) when the back camera records at 4K — verifiable via format log at session start.
  3. `hardwareCost` stays below 1.0 throughout a 5-minute 4K recording; if it would exceed 1.0, the session reverts to 1080p before recording starts (no silent session stop).
  4. PiP overlay renders correctly positioned in the 4K output frame — no offset to lower-left quadrant.
**Plans**: TBD

### Phase 9: Localization Infrastructure and Code Fixes
**Goal**: The Xcode project is configured for English and Spanish localization, String Catalogs exist with all UI strings cataloged, and computed string properties are fixed so the catalog is complete and accurate.
**Depends on**: Phase 8
**Requirements**: L10N-02, L10N-03, L10N-04, L10N-05, L10N-06, L10N-07, L10N-08
**Success Criteria** (what must be TRUE):
  1. Xcode Build Settings shows Spanish (es) and English (en) as supported localizations and `SWIFT_EMIT_LOC_STRINGS = YES` is set.
  2. `Localizable.xcstrings` and `InfoPlist.xcstrings` exist in the project bundle and open without errors in Xcode's String Catalog editor.
  3. A build produces no "missing translation" warnings for English strings — all `Text("literal")` and `Button("literal")` call sites appear in the catalog.
  4. `blockedMessage` and `storageEstimate` computed properties use `String(localized:)` and their keys appear in the catalog.
  5. Technical labels (fps values, resolution names, elapsed timer) are marked `Text(verbatim:)` and do not appear as untranslated entries in the catalog.
**Plans**: 2 plans

Plans:
- [ ] 09-01-PLAN.md — Add es to knownRegions in project.pbxproj, create Localizable.xcstrings with all 23 UI string keys, create InfoPlist.xcstrings with 3 permission description keys (L10N-02, L10N-03, L10N-04, L10N-05)
- [ ] 09-02-PLAN.md — Convert blockedMessage to String(localized:comment:), convert storageEstimate to String(localized:) with interpolation, mark picker items and elapsed timer Text(verbatim:) (L10N-06, L10N-07, L10N-08)

### Phase 10: Spanish Translations
**Goal**: Every user-visible string in the app has a correct Spanish translation in the appropriate catalog, including permission descriptions and plural-sensitive storage estimates.
**Depends on**: Phase 9
**Requirements**: L10N-01, L10N-09, L10N-10, L10N-11
**Success Criteria** (what must be TRUE):
  1. All ~32 strings in `Localizable.xcstrings` have a non-empty Spanish translation — the catalog shows zero untranslated entries for the `es` locale.
  2. All three permission usage descriptions in `InfoPlist.xcstrings` have Spanish translations that appear in the iOS permission prompt when the device language is Spanish.
  3. The storage estimate label shows "1 min restante" for singular and "N mins restantes" for plural in Spanish — both plural variants are present in the catalog.
**Plans**: TBD

### Phase 11: Localization Validation
**Goal**: Every screen and workflow in the app functions correctly and displays only Spanish text when the device language is set to Spanish.
**Depends on**: Phase 10
**Requirements**: L10N-12, L10N-13
**Success Criteria** (what must be TRUE):
  1. With device language set to Spanish, all app screens (camera view, quality panel, permissions flow, countdown overlay, alerts, unsupported-device view) display Spanish text — no English strings are visible.
  2. A complete recording cycle (grant permissions, start preview, record, stop, save to Photos) completes without displaying any untranslated English strings.
  3. Error states (permission denied, save failure) display Spanish alert text when the device language is Spanish.
  4. Switching the device back to English restores all strings to English with no missing or blank labels.
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation - Permissions, Session, Live Preview | 3/3 | Complete | 2026-05-17 |
| 2. Recording Pipeline - Compositor, Writer, Audio | 3/3 | Complete | 2026-05-17 |
| 3. Save, Polish, and Edge Cases | 3/3 | Complete   | 2026-05-17 |
| 4. Video Quality and Export Options | 4/4 | Complete | 2026-05-17 |
| 5. UI Polish | 0/2 | Not started | — |
| 6. Compositor Polish | 0/? | Not started | — |
| 7. 4K Capability Detection and Conditional UI | 0/? | Not started | — |
| 8. 4K Recording Pipeline | 0/? | Not started | — |
| 9. Localization Infrastructure and Code Fixes | 0/2 | Not started | — |
| 10. Spanish Translations | 0/? | Not started | — |
| 11. Localization Validation | 0/? | Not started | — |
