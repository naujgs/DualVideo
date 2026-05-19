# Requirements: DualVideo

**Defined:** 2026-05-16
**Core Value:** Both cameras record together and the result lands in Photos as a single watchable video.

## v1 Requirements

### Device + Permissions

- [ ] **DEV-01**: App detects and blocks unsupported hardware (pre-A12) with a clear message.
- [ ] **DEV-02**: App requests camera and microphone permission before starting capture.
- [ ] **DEV-03**: App requests Photo Library add permission before save and handles denial gracefully.

### Dual Preview + Controls

- [ ] **CAP-01**: App shows simultaneous back-camera full preview and front-camera PiP preview.
- [ ] **CAP-02**: User can drag PiP overlay before and during recording.
- [ ] **CAP-03**: User can pinch to zoom the back camera in live preview.
- [ ] **CAP-04**: App shows clear recording state (countdown, red-dot timer, elapsed MM:SS).

### Recording + Compositing

- [ ] **REC-01**: Single Record/Stop control starts and stops one synchronized recording pipeline.
- [ ] **REC-02**: App composites both camera feeds into one PiP frame stream in real time.
- [ ] **REC-03**: App writes a valid 1080p H.264/AAC video file to temporary storage.
- [ ] **REC-04**: Recording finalization is resilient to interruption/background transitions.

### Save + UX Polish

- [ ] **OUT-01**: On stop, app auto-saves the composited file to Photos.
- [ ] **OUT-02**: App shows success/failure save feedback to the user.
- [ ] **OUT-03**: PiP corner snapping and persisted PiP position work across sessions.
- [x] **OUT-04**: App provides torch toggle, zoom label, and orientation lock during recording.

## v1.1 Requirements — 4K Resolution Support

### 4K Capability Detection

- [ ] **K4-01**: App determines at session startup whether the back camera supports 4K in MultiCam mode via trial configuration (format iteration + hardwareCost check with front camera active).
- [ ] **K4-02**: Quality settings panel shows 4K as a selectable resolution only on hardware where K4-01 passes; the option is absent (not greyed out) on all other devices.

### 4K Recording Pipeline

- [ ] **K4-03**: When 4K is selected, app records the back camera at 3840×2160 using HEVC with the front camera capped at 1080p; a hardwareCost revert guard falls back to 1080p if cost ≥ 1.0.
- [ ] **K4-04**: PiPCompositor and MovieRecorder pixel buffer pool are sized to 3840×2160 when 4K is active, and the pipRect coordinate scaling is updated to match the 4K output frame.

### Storage Awareness

- [ ] **K4-05**: Quality settings panel displays a live estimate of available recording time at the selected resolution, calculated from current device free storage and the expected bitrate for that resolution.

## v1.4 Requirements — Language / Localization

### Infrastructure Setup

- [ ] **L10N-01**: User sees all app text in their iOS system language (English or Spanish) automatically — no in-app language picker is present.
- [ ] **L10N-02**: Xcode project lists Spanish (es) and English (en) as supported localizations and `SWIFT_EMIT_LOC_STRINGS = YES` is set in Build Settings.
- [ ] **L10N-03**: `Localizable.xcstrings` (String Catalog) exists in the project bundle with all UI strings and Spanish translations.
- [ ] **L10N-04**: `InfoPlist.xcstrings` exists with Spanish translations for all three permission usage descriptions (camera, microphone, Photo Library).

### String Extraction & Code Fixes

- [ ] **L10N-05**: All `Text("literal")` and `Button("literal")` call sites auto-extract into the catalog on build — a manual audit confirms zero strings are missed.
- [ ] **L10N-06**: `blockedMessage` (PermissionsBlockedView computed `String` property) is converted to `String(localized:)` so it appears in the catalog and localizes correctly.
- [ ] **L10N-07**: `storageEstimate` (QualitySettingsSheet computed `String` property) is converted to `String(localized:)` so the storage estimate label localizes correctly.
- [ ] **L10N-08**: Technical labels that must not be translated (fps values "30 FPS"/"60 FPS"/"120 FPS", resolution names "720p"/"1080p"/"4K", elapsed timer "MM:SS") are marked `Text(verbatim:)` to suppress catalog warnings.

### Spanish Translations

- [ ] **L10N-09**: All UI strings have Spanish translations in `Localizable.xcstrings` (~32 strings including alerts, buttons, labels, error messages, quality panel, overlay).
- [ ] **L10N-10**: Permission usage descriptions have Spanish translations in `InfoPlist.xcstrings`.
- [ ] **L10N-11**: Storage estimate string includes Spanish plural variants ("1 min restante" vs "N mins restantes").

### Validation

- [ ] **L10N-12**: All app screens (camera view, quality panel, permissions flow, countdown overlay, alerts, error/unsupported-device states) display Spanish when device language is Spanish.
- [ ] **L10N-13**: App records, saves, and handles errors correctly when running in Spanish — no untranslated (English) strings are visible during a full recording cycle.

## v2 Requirements

### Deferred Enhancements

- **V2-01**: Split-screen (50/50) layout mode.
- **V2-02**: Foreground/background camera role swap.
- **V2-03**: Separate file export per camera.
- **V2-05**: In-app trim/filters/sharing tools.

## Out of Scope

| Feature | Reason |
|---------|--------|
| App Store distribution/compliance | Personal side-load scope |
| Cloud sync/sharing backend | Not required for core capture value |
| Advanced editing suite | Photos app already covers basic editing |
| Frame-drop / thermal warning during 4K | Deferred — detection logic is non-trivial; rely on hardware guard for v1.1 |
| Live storage countdown during recording | Deferred — only needed in quality panel before recording starts |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DEV-01 | Phase 1 | Pending |
| DEV-02 | Phase 1 | Pending |
| DEV-03 | Phase 3 | Pending |
| CAP-01 | Phase 1 | Pending |
| CAP-02 | Phase 1 | Pending |
| CAP-03 | Phase 1 | Pending |
| CAP-04 | Phase 2 | Pending |
| REC-01 | Phase 2 | Pending |
| REC-02 | Phase 2 | Pending |
| REC-03 | Phase 2 | Pending |
| REC-04 | Phase 2 | Pending |
| OUT-01 | Phase 3 | Pending |
| OUT-02 | Phase 3 | Pending |
| OUT-03 | Phase 3 | Pending |
| OUT-04 | Phase 3 | Complete |
| K4-01 | Phase 7 | Pending |
| K4-02 | Phase 7 | Pending |
| K4-05 | Phase 7 | Pending |
| K4-03 | Phase 8 | Pending |
| K4-04 | Phase 8 | Pending |
| L10N-02 | Phase 9 | Pending |
| L10N-03 | Phase 9 | Pending |
| L10N-04 | Phase 9 | Pending |
| L10N-05 | Phase 9 | Pending |
| L10N-06 | Phase 9 | Pending |
| L10N-07 | Phase 9 | Pending |
| L10N-08 | Phase 9 | Pending |
| L10N-01 | Phase 10 | Pending |
| L10N-09 | Phase 10 | Pending |
| L10N-10 | Phase 10 | Pending |
| L10N-11 | Phase 10 | Pending |
| L10N-12 | Phase 11 | Pending |
| L10N-13 | Phase 11 | Pending |

**Coverage:**
- v1 requirements: 15 total
- v1.1 requirements: 5 total
- v1.4 requirements: 13 total
- Mapped to phases: 15 (v1) + 5 (v1.1) + 13 (v1.4)
- Unmapped: 0

---
*Requirements defined: 2026-05-16*
*Last updated: 2026-05-19 — v1.4 traceability added (L10N-01 through L10N-13 mapped to phases 9–11)*
