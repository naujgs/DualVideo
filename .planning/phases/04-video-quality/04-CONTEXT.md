# Phase 4: Video Quality and Export Options - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 4 adds two independent, user-facing features on top of the existing recording pipeline:

1. **Configurable output quality** (VQ-01, VQ-02, VQ-04): resolution (720p / 1080p) and bitrate (Low / Medium / High) selectable before recording. Settings persist across app launches via UserDefaults.
2. **Post-recording trim UI** (VQ-03): a full-screen sheet shown after every `stopRecording()` that lets the user define in/out points before saving to Photos.

Phase boundary: Does NOT change the live preview behavior, the dual-mic audio blend, the PiP drag compositing, or the Photos save mechanism. All Phase 1–3 behaviors are unchanged.

</domain>

<decisions>
## Implementation Decisions

### Default Quality Preset (VQ-01, VQ-02, VQ-04)
- **D-01:** Default resolution on first install is **1080p**. Basis: both template camera files (`front-camera.MOV`, `back camera.MOV`) capture at native 1920×1080. The existing app hardcodes 1080p. No downgrade on first launch.
- **D-02:** Default bitrate tier on first install is **High**. Basis: the existing `MovieRecorder` hardcodes ~10 Mbps and has been validated on-device. Phase 4 raises "High" above that value (see D-04), but "High" remains the correct default tier since it preserves the quality users already have.

### Bitrate Tier Values (VQ-02)
- **D-03:** Source of truth for tier calibration is the camera template recordings: `front-camera.MOV` at **~15.4 Mbps** (1080p H.264 High Profile, 29.97fps) and `back camera.MOV` at **~11.3 Mbps** (same spec). These represent the native per-camera quality floor.
- **D-04:** **High = 15 Mbps** (~112 MB/min). Matches front camera native capture rate. Rationale: the composited PiP output should be able to match what the device's front camera alone produces.
- **D-05:** **Medium = 10 Mbps** (~75 MB/min). Matches the existing hardcoded `MovieRecorder` bitrate — proven to work well on the minimum supported hardware (iPhone XR A12). Users who previously used the app experienced this quality as "normal".
- **D-06:** **Low = 5 Mbps** (~37 MB/min). Half of Medium. Provides meaningful file size savings for users who record frequently or have limited storage.

### File Size Hints (UI-SPEC Update)
- **D-07:** The UI-SPEC copywriting contract lists file size hints calibrated for a 10 Mbps High. These must be updated to reflect the new tier values:
  - Low: **~37 MB/min** (was ~22 MB/min — applies to both 720p and 1080p at same bitrate)
  - Medium: **~75 MB/min** (was ~45 MB/min)
  - High: **~112 MB/min** (was ~75 MB/min)
  - Note: file size hints are identical for 720p and 1080p at the same tier because the same bitrate is applied regardless of resolution (720p output = same bits, fewer pixels = higher relative quality, same file size). This matches the UI-SPEC's intentional design.

### Claude's Discretion
- Live quality HUD badge: not discussed — Claude may implement or omit the "if added to control column" badge from the UI-SPEC based on implementation complexity. The gear button alone is the minimum acceptable; a badge is a quality-of-life addition only.
- Trim sheet minimum clip gate: not discussed — Claude decides whether very short clips (< 2 seconds) bypass the trim sheet and auto-save. Reasonable default: always show trim sheet if `pendingTrimURL` is non-nil, regardless of duration.
- 720p device format vs compositor downscale: technical implementation choice per RESEARCH.md recommendation (prefer device `activeFormat` change over compositor-only downscale for battery/CPU efficiency).
- AVCaptureDevice format selection for each resolution tier: RESEARCH.md recommended approach.
- Audio bitrate: AAC LC, 44.1kHz, stereo, ~128–160 kbps — match template file audio (~132 kbps) and existing app behavior. Not user-configurable in Phase 4.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase definition and requirements
- `.planning/PROJECT.md` — product scope, constraints, key decisions (1080p output, iOS 18+, A12+ floor, MVVM + SwiftUI architecture)
- `.planning/REQUIREMENTS.md` — requirement IDs for this phase: VQ-01, VQ-02, VQ-03, VQ-04
- `.planning/ROADMAP.md` — Phase 4 goal and success criteria
- `.planning/STATE.md` — current project state; Phases 1–3 complete

### Technical research and design contract
- `.planning/phases/04-video-quality/04-RESEARCH.md` — AVFoundation encoding architecture, `VideoQualitySettings` struct design, `VideoTrimManager` pattern, architecture diagram for Phase 4 additions (MUST READ before any implementation planning)
- `.planning/phases/04-video-quality/04-UI-SPEC.md` — **APPROVED visual and interaction contract** for all Phase 4 UI elements: `QualitySettingsButton`, `QualitySettingsSheet`, `TrimSheet`, `TrimRangeBar`, colors, typography, spacing, and full copywriting contract (MUST READ — planners and executors must not deviate from this spec)

### Prior phase context
- `.planning/phases/02-recording-pipeline-compositor-writer-audio/02-CONTEXT.md` — Phase 2 decisions: D-01 PiP position baked at frame time, D-05 dual-mic blended audio, D-06 auto-stop on interruption. Phase 4 modifies `MovieRecorder` and `PiPCompositor` — do not break these decisions.

### Implementation baseline (existing code — READ before modifying)
- `DualVideo/Features/Recording/MovieRecorder.swift` — MUST READ: hardcoded 1080p / 10 Mbps `AVAssetWriterInput` settings. Phase 4 makes these configurable via `VideoQualitySettings` injected at `startRecording()` time.
- `DualVideo/Features/Recording/RecordingManager.swift` — MUST READ: owns recording lifecycle, `pendingFileURL`, and the auto-save trigger. Phase 4 changes the auto-save flow: instead of immediately saving, set `pendingTrimURL` to trigger the trim sheet.
- `DualVideo/Features/Recording/PiPCompositor.swift` — MUST READ: hardcoded `outputWidth`/`outputHeight` constants. Phase 4 makes these dynamic based on selected resolution.
- `DualVideo/Features/Recording/PhotoSaveManager.swift` — UNCHANGED in Phase 4. Called after trim or as "Save Full" action.
- `DualVideo/Shared/AppState.swift` — MUST READ: `AppState` owns `CameraManager` and `RecordingManager`. New `VideoQualitySettings` shared instance attaches here.
- `DualVideo/Features/Camera/CameraManager.swift` — MUST READ: `AVCaptureMultiCamSession`, `activeFormat` selection per device. Phase 4 adds `applyResolutionFormat()` method.

### Camera template files (bitrate calibration reference)
- `~/Downloads/front-camera.MOV` — Native front camera capture: H.264 High Profile, 1920×1080, 29.97fps, **15.4 Mbps** video, AAC LC 44.1kHz stereo ~132 kbps. This recording is the basis for D-04 (High = 15 Mbps).
- `~/Downloads/back camera.MOV` — Native back camera capture: H.264 High Profile, 1920×1080, 29.97fps, **11.3 Mbps** video. Both cameras at same resolution confirms D-01 (default 1080p).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MovieRecorder`: owns `AVAssetWriterInput` — the exact place where `AVVideoAverageBitRateKey` and output dimensions are currently hardcoded. Phase 4 threads `VideoQualitySettings` into `startRecording(settings:)`.
- `PiPCompositor`: `outputWidth`/`outputHeight` are currently static constants. Phase 4 converts them to `var` injected from settings before each recording.
- `RecordingManager.pendingFileURL`: existing property. Phase 4 may rename/repurpose as `pendingTrimURL` to signal the trim sheet trigger.
- `PhotoSaveManager.save()`: unchanged call site. Reached via "Save Full" or after successful `VideoTrimManager.trim()`.
- `AppState`: existing `@Observable` — `VideoQualitySettings` shared instance mounts here as a new property.
- `TorchToggleButton` + `ZoomLabelView`: established pattern for the left-column control style that `QualitySettingsButton` must match (see UI-SPEC §QualitySettingsButton).
- `CameraContentView` ZStack: Phase 4 adds `QualitySettingsButton` to the left control column and the `TrimSheet` sheet presentation.

### Established Patterns
- All AVFoundation session mutations on `sessionQueue`; pixel buffer callbacks on `dataOutputQueue`.
- `@Observable` + `DispatchQueue.main.async` for UI-facing state updates from background queues.
- `nonisolated(unsafe)` for AVFoundation objects serialized on dedicated queues (Swift 6 isolation).
- `precondition(!Thread.isMainThread, ...)` guards on session-only methods.
- Codable + UserDefaults pattern: encode `Codable` struct to `Data`, store under a single key. Straightforward for `VideoQualitySettings`.

### Integration Points
- `CameraContentView` left column `VStack(spacing: 8)`: `QualitySettingsButton` slots in here (above or below `TorchToggleButton` per UI-SPEC).
- `RecordingManager.stopRecording()` completion path: instead of immediately calling `saveRecording()`, set `pendingTrimURL` to a non-nil `URL` to trigger `TrimSheet`.
- `CameraManager.configureAndStart()`: after session configuration, call `applyResolutionFormat()` with the current `VideoQualitySettings.resolution` to set the correct `AVCaptureDevice.activeFormat` on both cameras.
- `AppState.init()`: add `VideoQualitySettings.load()` call to restore persisted settings at launch.

</code_context>

<specifics>
## Specific Ideas

- **Camera template file bitrate anchor:** The user provided native iPhone camera recordings as the quality reference. `front-camera.MOV` at 15.4 Mbps is the ceiling for what a single camera stream looks like. The composited PiP output at "High" (15 Mbps) is set to match this. This is the explicit basis for D-04.
- **Medium = existing hardcoded value:** The choice of 10 Mbps for Medium was deliberate — it preserves the quality that all Phase 1–3 users already had. No existing user will experience a downgrade if they stay on Medium.
- **File size hint copy update:** The UI-SPEC's copywriting contract for `~22 MB/min`, `~45 MB/min`, `~75 MB/min` must be replaced with `~37 MB/min`, `~75 MB/min`, `~112 MB/min` across all 6 rows (all combinations of 720p/1080p × Low/Medium/High).

</specifics>

<deferred>
## Deferred Ideas

- HEVC (H.265) encoding option — RESEARCH.md notes ~50% file size savings but adds HEVC support check complexity. Deferred to v2 (PROJECT.md explicit).
- Per-camera audio track separation — blended single track is the current design (Phase 2 D-05). Out of scope.
- 4K output — explicitly out of scope (PROJECT.md).
- In-app sharing / cloud sync — out of scope.
- Resume-after-interruption — Phase 3 edge case hardening; Phase 4 does not change interruption behavior.

</deferred>

---

*Phase: 04-video-quality*
*Context gathered: 2026-05-18*
