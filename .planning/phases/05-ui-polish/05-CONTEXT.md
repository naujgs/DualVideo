# Phase 5: UI Polish - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 5 delivers two things: (1) repositioning the camera control layout — zoom label above the record button, quality button at bottom-right; and (2) applying a cohesive glass/material visual style across all camera controls, the quality settings sheet, and the "Saved to Photos" notification. PiP compositor rounded corners are deferred to Phase 6.

</domain>

<decisions>
## Implementation Decisions

### Layout Reorganization
- **D-01:** Zoom control moves from the left column to directly above the record button in the bottom-center area (LAYOUT-01).
- **D-02:** Quality settings button moves from the left column to the bottom-right of the screen (LAYOUT-02).
- **D-03:** Torch toggle position is Claude's discretion — it was the only remaining control in the former left column after zoom and quality move out.

### Zoom Control — Interactive Preset Buttons
- **D-04:** The zoom control becomes three separate tappable preset buttons: `[ 1x ]  [ 2x ]  [ 3x ]`. The active preset is highlighted (bold/filled). This replaces the current single `ZoomLabelView` display label.
- **D-05:** Presets are 1x, 2x, 3x — matching the current pinch clamping range (1.0–3.0x).
- **D-06:** Visual design must match the iPhone Camera app aesthetic — capsule-shaped buttons, active state clearly distinguished from inactive.
- **D-07:** Pinch-to-zoom gesture continues to work and updates the active preset highlight when the zoom lands near a preset value (Claude's discretion on threshold).

### Glass Style — Scope
- **D-08:** All camera controls get glass treatment — `ZoomPresetButton`, `TorchToggleButton`, `QualitySettingsButton`, `RecordingStatusOverlay`. No `Color.black.opacity(0.4)` backgrounds remain on controls.
- **D-09:** Glass API: `.glassEffect()` on iOS 26+; `.ultraThinMaterial` fallback on iOS 18–25. (Locked in STATE.md — do not revisit.)
- **D-10:** Quality settings sheet (`QualitySettingsSheet`) gets glass styling applied to its background and controls.
- **D-11:** "Saved to Photos" success capsule gets glass styling (`.ultraThinMaterial` / `.glassEffect()`) — replaces `.black.opacity(0.6)`.
- **D-12:** Trim sheet and unsupported device view are NOT in scope for glass styling in Phase 5.

### RecordingStatusOverlay
- **D-13:** `RecordingStatusOverlay` already uses `.ultraThinMaterial` — GLASS-03 is largely satisfied. Verify it looks consistent with the new glass controls and adjust only if there's a visual inconsistency.
- **D-14:** Position stays at top-center (below Dynamic Island / notch) — no position change.

### Claude's Discretion
- Exact torch toggle position after the left column is vacated by zoom and quality controls.
- Zoom preset highlight threshold (how close pinch zoom must be to a preset for it to appear "active").
- Exact padding/spacing between the three zoom preset buttons.
- Any tinting, vibrancy, or opacity tuning on glass backgrounds to ensure readability over the camera feed.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project and phase definition
- `.planning/PROJECT.md` — product scope, constraints, architecture decisions
- `.planning/REQUIREMENTS.md` — requirement IDs for this phase: LAYOUT-01, LAYOUT-02, GLASS-01, GLASS-02, GLASS-03
- `.planning/ROADMAP.md` — Phase 5 goal, success criteria, and plan structure
- `.planning/STATE.md` — current project state; glass API decision locked here

### Key source files (read before modifying)
- `DualVideo/Features/Camera/CameraContentView.swift` — main layout file; all controls are composed here
- `DualVideo/Features/Recording/UI/ZoomLabelView.swift` — current zoom label; will be replaced by zoom preset buttons
- `DualVideo/Features/Recording/UI/TorchToggleButton.swift` — torch control; receives glass background
- `DualVideo/Features/Recording/UI/QualitySettingsButton.swift` — quality button; moves to bottom-right, receives glass background
- `DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift` — already uses .ultraThinMaterial; verify consistency
- `DualVideo/Features/Recording/UI/QualitySettingsSheet.swift` — sheet to receive glass styling

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `RecordingStatusOverlay` already uses `.background(.ultraThinMaterial, in: Capsule())` — this is the correct pattern to apply to other controls.
- `QualitySettingsButton` and `TorchToggleButton` both use `Color.black.opacity(0.4)` circle backgrounds — direct swap target for glass treatment.
- `ZoomLabelView` uses `Color.black.opacity(0.4)` capsule — will be replaced entirely by new `ZoomPresetView` with three tappable buttons.

### Established Patterns
- Controls are composed in `CameraContentView` using `ZStack` with positioned `HStack`/`VStack` layers.
- Button tap actions are passed as closures (`onTap: () -> Void`) — pattern to reuse in new zoom preset buttons.
- `cameraManager.setZoom(_:)` is the API for programmatic zoom changes — zoom presets will call this.
- `cameraManager.backZoomFactor` is the current zoom source of truth — zoom preset highlight reads from this.

### Integration Points
- New zoom preset component connects to `cameraManager.setZoom()` and reads `cameraManager.backZoomFactor`.
- Layout changes live entirely in `CameraContentView.swift` — no routing or state model changes expected.
- Quality sheet stays triggered via `showQualitySettings` bool state already in `CameraContentView`.

</code_context>

<specifics>
## Specific Ideas

- Zoom preset button design: match the iPhone Camera app — three small capsule buttons side by side, active state is bold/filled/highlighted, inactive state is subtle glass treatment.
- The three buttons ( `1x`, `2x`, `3x` ) sit as a horizontal row directly above the record button.

</specifics>

<deferred>
## Deferred Ideas

- Trim sheet glass styling — user explicitly excluded; could be Phase 6 or a future polish pass.
- Unsupported device view glass styling — excluded from this phase.
- Animated glass shimmer on record start — noted in REQUIREMENTS.md Future Requirements; remains deferred.
- Custom PiP corner radius user setting — future requirement; remains deferred.

</deferred>

---

*Phase: 05-ui-polish*
*Context gathered: 2026-05-18*
