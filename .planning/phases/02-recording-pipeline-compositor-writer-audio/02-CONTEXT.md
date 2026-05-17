# Phase 2: Recording Pipeline - Compositor, Writer, Audio - Context

**Gathered:** 2026-05-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 2 delivers the complete recording pipeline: a Metal-based PiP compositor that combines synchronized camera frames into a single composited frame stream, an `AVAssetWriter` write pipeline that produces a valid 1080p `.mov` file, dual-mic audio integration, and the recording controls UI (Record/Stop button, recording state indicator). The output is a finalized temp `.mov` file — saving to Photos is Phase 3.

</domain>

<decisions>
## Implementation Decisions

### Compositor — PiP frame layout
- **D-01:** The compositor renders the PiP (front camera) at the user's **current drag position** — i.e., reads `PiPOverlayState.offset` at each frame so the recording matches what the user sees in the live preview. A user who drags the PiP to bottom-left before or during recording gets that position baked into the output.

### Recording controls UI
- **D-02:** The Record/Stop button is **bottom-center, always visible** — large circular button anchored above the home indicator, thumb-reachable, conventional iOS video app placement.
- **D-03:** During active recording, show a **blinking red dot + elapsed MM:SS timer** at the top of the screen. No border or full-screen overlay.

### Countdown
- **D-04:** **No countdown** — tapping Record starts recording immediately. The CAP-04 "3-second countdown" requirement is explicitly dropped. Elapsed timer begins on Record tap.

### Audio
- **D-05:** Capture audio from **both the back and front microphones**, mixed into a **single blended AAC audio track** in the output file. Use `AVCaptureMultiCamSession` dual audio inputs; let AVFoundation blend them.

### Interruption and resilience
- **D-06:** When a phone call or app backgrounding interrupts recording, **auto-stop and cleanly finalize** the `AVAssetWriter`. The partial-but-valid `.mov` temp file is preserved for Phase 3 to save to Photos. No data is discarded on interruption.

### Claude's Discretion
- Compositor implementation strategy (Metal shaders vs `CVPixelBuffer` copy via `vImageScale` — whichever is more reliable on A12 hardware at 1080p without exceeding `hardwareCost` constraints).
- Exact threading model for compositor ↔ `MovieRecorder` handoff (must stay consistent with established `sessionQueue`/`dataOutputQueue` pattern in `CameraManager`).
- Exact AVAudioSession configuration details for dual-mic input.
- Specific `AVAssetWriter` track configuration (bitrate, keyframe interval).
- Output resolution: 1080p (1920×1080), format: H.264/AAC `.mov` — from project requirements.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project and phase definition
- `.planning/PROJECT.md` — product scope, constraints, key decisions (PiP compositing approach, iOS 18.0+ minimum, A12+ hardware floor)
- `.planning/REQUIREMENTS.md` — requirement IDs for this phase: `CAP-04`, `REC-01`, `REC-02`, `REC-03`, `REC-04`
- `.planning/ROADMAP.md` — Phase 2 goal, success criteria, and 3-plan structure
- `.planning/STATE.md` — current project state; Phase 1 complete

### Prior phase context
- `.planning/phases/01-foundation-permissions-session-live-preview/01-CONTEXT.md` — Phase 1 decisions (D-05 PiP default position, D-06 full-bleed back cam, D-07 clamp logic, D-08 corner snapping deferred, D-09 zoom range 1.0–3.0x)

### Implementation baseline
- `DualVideo/Features/Camera/CameraManager.swift` — MUST READ: owns `AVCaptureMultiCamSession`, `backVideoOutput`, `frontVideoOutput` (already wired as `AVCaptureVideoDataOutput`), `sessionQueue`, `dataOutputQueue`. Phase 2 attaches compositor as delegate to these outputs.
- `DualVideo/Features/Camera/CameraActor.swift` — global actor for AVFoundation work; Phase 2 must stay consistent with this actor isolation model.
- `DualVideo/Shared/AppState.swift` — `AppState` observable; recording state additions belong here or in a new `RecordingManager` attached to it.
- `DualVideo/Features/Camera/PiPOverlayState.swift` — `offset` property is the source of truth for dynamic PiP position (D-01).
- `DualVideo/Features/Camera/CameraContentView.swift` — existing UI structure; Record button and recording state overlay slot into this view's `ZStack`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CameraManager.backVideoOutput` / `frontVideoOutput`: already-configured `AVCaptureVideoDataOutput` objects with connections wired to `dataOutputQueue`. Compositor sets itself as `setSampleBufferDelegate` on these — no new outputs needed.
- `PiPOverlayState.offset`: live drag position — compositor reads this for D-01 dynamic PiP placement.
- `CameraActor` global actor: established isolation boundary for AVFoundation work. New compositor/recorder types should respect this pattern.
- `@Observable` + `nonisolated(unsafe)`: established threading pattern — `@Observable` for UI-facing state, `nonisolated(unsafe)` for AVFoundation objects serialized on dedicated queues.

### Established Patterns
- All AVFoundation session mutations run on `sessionQueue`; pixel buffer callbacks come in on `dataOutputQueue`.
- `DispatchQueue.main.async` for `@Observable` state updates from background queues.
- `DispatchQueue.main.sync` only where safe (not on main, not creating deadlock) — see `CameraManager.configureAndStart()`.
- `precondition(!Thread.isMainThread, ...)` guards on session-thread-only methods.

### Integration Points
- `CameraContentView`'s `ZStack`: Record button and recording state overlay (red dot + timer) layer on top of existing preview layers.
- `AppState.route`: recording state (idle, recording, finalizing) either extends `AppRoute` or lives in a new observable on `AppState`.
- `CameraManager.session`: `AVCaptureMultiCamSession` — compositor and audio inputs attach to this existing session.

</code_context>

<specifics>
## Specific Ideas

- The compositor needs to handle `PiPOverlayState.offset` thread-safely — `offset` is an `@Observable` main-thread value, while compositor runs on `dataOutputQueue`. A snapshot of the current offset should be captured (e.g., via `@MainActor` read or a thread-safe copy) at frame time.
- No countdown UI at all — Record tap = recording starts. The elapsed timer appears immediately.
- The "both mics blended" approach should be validated against `AVCaptureMultiCamSession` audio limits on iPhone XR (minimum target hardware).

</specifics>

<deferred>
## Deferred Ideas

- Photos save flow — Phase 3 (`OUT-01`, `OUT-02`)
- PiP corner snapping — Phase 3 (D-08 from Phase 1)
- Resume-after-interruption (re-start recording after a phone call ends) — Phase 3 edge-case hardening
- Separate per-camera audio tracks — PROJECT.md specifies blended single track; separate tracks deferred
- 4K recording output — explicitly out of scope (PROJECT.md)

</deferred>

---

*Phase: 02-recording-pipeline-compositor-writer-audio*
*Context gathered: 2026-05-17*
