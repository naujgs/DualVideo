# Phase 2: Recording Pipeline - Compositor, Writer, Audio - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-17
**Phase:** 02-recording-pipeline-compositor-writer-audio
**Areas discussed:** PiP position in recording, Recording controls UI, Audio strategy, Interruption behavior

---

## PiP Position in Recording

| Option | Description | Selected |
|--------|-------------|----------|
| Dynamic — follows drag | Compositor reads `PiPOverlayState.offset`; recording matches live preview | ✓ |
| Fixed — always top-right | Compositor ignores drag state; constant PiP rect | |

**User's choice:** Dynamic — follows drag
**Notes:** What the user sees in the live preview = what is baked into the recording.

---

## Recording Controls UI

### Button placement

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom-center, always visible | Large circular Record button above home indicator | ✓ |
| Minimal floating button | Smaller button at fixed position (e.g. bottom-right) | |
| Claude's discretion | Planner decides placement | |

**User's choice:** Bottom-center, always visible

### Recording state indicator

| Option | Description | Selected |
|--------|-------------|----------|
| Red dot + elapsed MM:SS timer | Blinking red circle + timer at top of screen | ✓ |
| Red border around preview | Screen border during recording + elapsed timer | |
| Claude's discretion | Planner designs in-recording state | |

**User's choice:** Red dot + elapsed MM:SS timer at top of screen

### Countdown

| Option | Description | Selected |
|--------|-------------|----------|
| Large centered number, cancellable | 3→2→1 centered; tapping Record cancels | |
| Large centered number, not cancellable | 3→2→1 centered; recording begins, no cancel | |
| No countdown | Record tap = instant start | ✓ |

**User's choice:** No countdown at all — instant recording start on Record tap
**Notes:** CAP-04 countdown requirement explicitly dropped by user.

---

## Audio Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Both mics, one blended track | Back + front mic mixed into single AAC track | ✓ |
| Back mic only | Single rear microphone input | |
| Claude's discretion | Planner chooses based on AVFoundation capabilities | |

**User's choice:** Both mics, one blended AAC track

---

## Interruption Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-stop and finalize the file | Clean AVAssetWriter stop; partial .mov preserved for Phase 3 | ✓ |
| Auto-stop and discard | Stop writing and delete temp file | |
| Claude's discretion | Planner decides per Apple best practices | |

**User's choice:** Auto-stop and finalize — partial file is kept for Phase 3 save

---

## Claude's Discretion

- Compositor implementation strategy (Metal vs CVPixelBuffer copy)
- Exact threading model for compositor ↔ MovieRecorder handoff
- AVAudioSession configuration details for dual-mic input
- AVAssetWriter track configuration (bitrate, keyframe interval)
- Actor isolation approach for new Phase 2 types

## Deferred Ideas

- Resume-after-interruption (re-start after phone call ends) — Phase 3
- Separate per-camera audio tracks — blended single track confirmed; separate deferred
- 4K recording — out of scope
