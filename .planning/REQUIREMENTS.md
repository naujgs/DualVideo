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
| K4-01 | TBD | Pending |
| K4-02 | TBD | Pending |
| K4-03 | TBD | Pending |
| K4-04 | TBD | Pending |
| K4-05 | TBD | Pending |

**Coverage:**
- v1 requirements: 15 total
- v1.1 requirements: 5 total
- Mapped to phases: 15 (v1) + 0 (v1.1, pending roadmap)
- Unmapped: 5 (v1.1)

---
*Requirements defined: 2026-05-16*
*Last updated: 2026-05-19 — v1.1 requirements added (K4-01 through K4-05)*
