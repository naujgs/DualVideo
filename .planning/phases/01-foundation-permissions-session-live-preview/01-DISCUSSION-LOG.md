# Phase 1 Discussion Log

**Date:** 2026-05-16
**Phase:** 01 - Foundation - Permissions, Session, Live Preview

## Selected Gray Areas

1. Permission flow + denial UX
2. Unsupported-device fallback UX
3. Live preview composition defaults
4. Interaction behavior (Phase 1 scope)

## Final Choices

- `1B`: Request camera + microphone + Photo Library up front on first launch.
- `2B`: Show disabled preview shell with explanation banner on unsupported devices.
- `3A`: Front PiP top-right, rounded-rect, ~28% width, safe-area inset margins, draggable.
- `4A`: Drag clamped to safe area; no corner snapping yet; pinch zoom `1.0x`-`3.0x`.

## Notes

- Decisions are locked for planning and execution of Phase 1.
- Recording pipeline and save flow remain explicitly out of Phase 1 scope.

---

*Decisions canonized in:* `01-CONTEXT.md`
