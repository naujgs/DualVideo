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

## v2 Requirements

### Deferred Enhancements

- **V2-01**: Split-screen (50/50) layout mode.
- **V2-02**: Foreground/background camera role swap.
- **V2-03**: Separate file export per camera.
- **V2-04**: 4K recording output.
- **V2-05**: In-app trim/filters/sharing tools.

## Out of Scope

| Feature | Reason |
|---------|--------|
| App Store distribution/compliance | Personal side-load scope for v1 |
| Cloud sync/sharing backend | Not required for core capture value |
| Advanced editing suite | Photos app already covers basic editing |

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

**Coverage:**
- v1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-05-16*
*Last updated: 2026-05-16 after research synthesis*
