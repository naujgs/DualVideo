# Requirements: DualVideo

**Defined:** 2026-05-16
**Core Value:** Both cameras record together and the result lands in Photos as a single watchable video.

## v1.2 Requirements (Visual Polish)

**Milestone goal:** Reorganize the camera UI layout and apply a cohesive liquid glass visual style, including fixing PiP rounded corners in the recorded video output.

### Layout

- [ ] **LAYOUT-01**: User sees the zoom label (1.0x, 1.5x…) positioned above the record button in the bottom-center area
- [ ] **LAYOUT-02**: User accesses the quality settings button at the bottom-right of the screen (no longer in the left column)

### Compositor

- [ ] **COMPOSITOR-01**: PiP overlay in the saved video has the same rounded corners (12pt radius) as the live preview overlay

### Glass Style

- [ ] **GLASS-01**: Camera control buttons (zoom label, torch toggle, quality button) display a glass/material background instead of `black.opacity(0.4)`
- [ ] **GLASS-02**: On iOS 26+, `.glassEffect()` is used for controls; on iOS 18–25, `.ultraThinMaterial` with appropriate tinting is the fallback
- [ ] **GLASS-03**: Recording status overlay (elapsed time capsule) is visually consistent with the glass style applied to other controls

---

## v1 Requirements

### Device + Permissions

- [x] **DEV-01**: App detects and blocks unsupported hardware (pre-A12) with a clear message.
- [x] **DEV-02**: App requests camera and microphone permission before starting capture.
- [x] **DEV-03**: App requests Photo Library add permission before save and handles denial gracefully.

### Dual Preview + Controls

- [x] **CAP-01**: App shows simultaneous back-camera full preview and front-camera PiP preview.
- [x] **CAP-02**: User can drag PiP overlay before and during recording.
- [x] **CAP-03**: User can pinch to zoom the back camera in live preview.
- [x] **CAP-04**: App shows clear recording state (countdown, red-dot timer, elapsed MM:SS).

### Recording + Compositing

- [x] **REC-01**: Single Record/Stop control starts and stops one synchronized recording pipeline.
- [x] **REC-02**: App composites both camera feeds into one PiP frame stream in real time.
- [x] **REC-03**: App writes a valid 1080p H.264/AAC video file to temporary storage.
- [x] **REC-04**: Recording finalization is resilient to interruption/background transitions.

### Save + UX Polish

- [x] **OUT-01**: On stop, app auto-saves the composited file to Photos.
- [x] **OUT-02**: App shows success/failure save feedback to the user.
- [x] **OUT-03**: PiP corner snapping and persisted PiP position work across sessions.
- [x] **OUT-04**: App provides torch toggle, zoom label, and orientation lock during recording.

### Video Quality

- [x] **VQ-01**: User can select output resolution (720p / 1080p) before recording.
- [x] **VQ-02**: User can select bitrate (Low / Medium / High) before recording.
- [x] **VQ-03**: User can trim a recorded clip before saving to Photos.
- [x] **VQ-04**: Quality settings persist across app launches.

---

## Future Requirements

- Custom PiP corner radius user setting — user could pick corner radius size
- Animated glass shimmer on record start — purely decorative, defer
- PiP border/stroke outline — minor enhancement, defer
- Split-screen (50/50) layout mode — **V2-01**
- Foreground/background camera role swap — **V2-02**
- 4K recording output — **V2-03**
- In-app trim/filters/sharing tools — **V2-04**

## Out of Scope

| Feature | Reason |
|---------|--------|
| App Store distribution/compliance | Personal side-load scope |
| Cloud sync/sharing backend | Not required for core capture value |
| Advanced editing suite | Photos app already covers basic editing |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| LAYOUT-01 | Phase 5 | Pending |
| LAYOUT-02 | Phase 5 | Pending |
| GLASS-01 | Phase 5 | Pending |
| GLASS-02 | Phase 5 | Pending |
| GLASS-03 | Phase 5 | Pending |
| COMPOSITOR-01 | Phase 6 | Pending |
| DEV-01 | Phase 1 | Complete |
| DEV-02 | Phase 1 | Complete |
| DEV-03 | Phase 3 | Complete |
| CAP-01 | Phase 1 | Complete |
| CAP-02 | Phase 1 | Complete |
| CAP-03 | Phase 1 | Complete |
| CAP-04 | Phase 2 | Complete |
| REC-01 | Phase 2 | Complete |
| REC-02 | Phase 2 | Complete |
| REC-03 | Phase 2 | Complete |
| REC-04 | Phase 2 | Complete |
| OUT-01 | Phase 3 | Complete |
| OUT-02 | Phase 3 | Complete |
| OUT-03 | Phase 3 | Complete |
| OUT-04 | Phase 3 | Complete |
| VQ-01 | Phase 4 | Complete |
| VQ-02 | Phase 4 | Complete |
| VQ-03 | Phase 4 | Complete |
| VQ-04 | Phase 4 | Complete |

**Coverage:**
- v1.2 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0

---
*Requirements defined: 2026-05-16*
*Last updated: 2026-05-18 — v1.2 Visual Polish requirements added*
