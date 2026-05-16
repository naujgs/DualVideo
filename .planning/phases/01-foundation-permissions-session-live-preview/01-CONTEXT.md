# Phase 1: Foundation - Permissions, Session, Live Preview - Context

**Gathered:** 2026-05-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 delivers supported-device MultiCam startup with dual live preview, permission handling, unsupported fallback UX, draggable PiP, and back-camera pinch zoom. This phase does not include recording/compositing/write pipeline or Photos save implementation.

</domain>

<decisions>
## Implementation Decisions

### Permission flow and denial UX
- **D-01:** Request camera, microphone, and Photo Library permissions up front on first launch before any capture/session flow (Choice `1B`).
- **D-02:** If any required permission is denied, keep the user in a clear blocked state with explanatory copy and Settings recovery path; do not attempt partial capture mode in Phase 1.

### Unsupported-device fallback UX
- **D-03:** Use a disabled preview shell with a clear explanation banner when MultiCam is unsupported (Choice `2B`).
- **D-04:** Fallback copy must explicitly state A12+ requirement and that dual-camera recording is unavailable on this hardware.

### Live preview composition defaults
- **D-05:** Default PiP layout is front camera in top-right, rounded-rect shape, approximately 28% of screen width, safe-area inset margins, draggable (Choice `3A`).
- **D-06:** Back camera remains full-bleed primary preview layer.

### Interaction behavior (Phase 1 scope)
- **D-07:** PiP drag is clamped to safe-area bounds with inset margins (Choice `4A`).
- **D-08:** Corner snapping is deferred (not implemented in Phase 1).
- **D-09:** Back-camera pinch zoom range is clamped to `1.0x` through `3.0x` in Phase 1.

### the agent's Discretion
- Exact copywriting text for permission/fallback banners and blocked-state messaging.
- Exact constants for drag insets and animation polish, as long as they preserve D-05 and D-07.
- Gesture smoothing/hysteresis details for drag and pinch interactions.

</decisions>

<specifics>
## Specific Ideas

- Keep Phase 1 strictly as foundation and interaction readiness; do not pull in recording pipeline concerns.
- Prioritize stable behavior on minimum supported hardware while preserving the chosen UX defaults.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project and phase definition
- `.planning/PROJECT.md` — product scope, constraints, and key decisions
- `.planning/REQUIREMENTS.md` — requirement IDs mapped to this phase (`DEV-01`, `DEV-02`, `CAP-01`, `CAP-02`, `CAP-03`)
- `.planning/ROADMAP.md` — Phase 1 goal/success criteria and plan structure
- `.planning/STATE.md` — current project state and active phase

### Technical research baseline
- `.planning/research/SUMMARY.md` — validated MultiCam architecture, queueing model, and phase risks

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- No application source files are present yet; implementation starts from greenfield project scaffolding.

### Established Patterns
- Planning artifacts establish MVVM + `CameraManager` architecture and a strict phase boundary separating preview foundation (Phase 1) from recording pipeline work (Phase 2).

### Integration Points
- Phase 1 output must provide a stable camera/session surface that Phase 2 can attach compositor and recording services to.

</code_context>

<deferred>
## Deferred Ideas

- PiP corner snapping behavior (planned for Phase 3 per roadmap).
- Recording controls/countdown/timer and composited file writing (Phase 2).
- Photos save workflow, success/failure feedback polish, and persistent PiP position (Phase 3).

</deferred>

---

*Phase: 01-foundation-permissions-session-live-preview*
*Context gathered: 2026-05-16*
