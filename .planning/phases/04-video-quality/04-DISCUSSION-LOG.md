# Phase 4: Video Quality and Export Options - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-18
**Phase:** 04-video-quality
**Areas discussed:** Default quality preset, Bitrate tier values

---

## Default Quality Preset

| Option | Description | Selected |
|--------|-------------|----------|
| 1080p | Matches native camera capture; both template files are 1080p; existing app hardcodes 1080p | ✓ |
| 720p | Smaller file size, still good quality; better default for storage-conscious users | |

**User's choice:** 1080p

---

| Option | Description | Selected |
|--------|-------------|----------|
| High | Matches native recording quality; existing app already hardcodes ~10 Mbps (maps to High) | ✓ |
| Medium | Balanced default — smaller files, opt-in to full quality | |
| Low | Maximizes storage; visible downgrade from current hardcoded output | |

**User's choice:** High

---

## Bitrate Tier Values

| Option | Description | Selected |
|--------|-------------|----------|
| 10 Mbps | Existing hardcoded value; proven on iPhone XR; ~75 MB/min | |
| 15 Mbps | Matches front camera native capture rate (~15.4 Mbps); ~112 MB/min | ✓ |
| 12 Mbps | Midpoint between existing and native front camera | |

**User's choice:** High = 15 Mbps (matches front-camera.MOV native bitrate)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Medium 8 Mbps / Low 3 Mbps | ~50% and ~20% of High; Low matches old UI-SPEC hints | |
| Medium 10 Mbps / Low 5 Mbps | Medium = existing hardcoded (proven); Low = half of Medium | ✓ |
| Medium 6 Mbps / Low 2 Mbps | Wider tier separation; max file size savings at cost of Low quality | |

**User's choice:** Medium = 10 Mbps, Low = 5 Mbps

**Notes:** Medium set to 10 Mbps intentionally so it equals the existing hardcoded value — existing Phase 1–3 users experience no quality change if they stay on Medium. High raised to 15 Mbps to match native front-camera capture.

---

## Claude's Discretion

- Live quality HUD badge (UI-SPEC "if added") — not discussed; Claude decides
- Trim sheet minimum clip gate — not discussed; Claude decides
- 720p device format vs compositor downscale — technical implementation; per RESEARCH.md recommendation
- Audio bitrate — match template file (~132 kbps AAC); not user-configurable in Phase 4

## Deferred Ideas

None raised during discussion.
