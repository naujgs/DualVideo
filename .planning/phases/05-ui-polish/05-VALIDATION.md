---
phase: 5
slug: ui-polish
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-18
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None (no test target in project) |
| **Config file** | None |
| **Quick run command** | `xcodebuild -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` |
| **Full suite command** | Same (no automated tests exist) |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run build command to confirm no compile errors
- **After every plan wave:** Run build + visual check on iOS 26 simulator and iOS 18 simulator
- **Before `/gsd-verify-work`:** Full build must succeed clean; visual review on both OS versions
- **Max feedback latency:** 90 seconds (build time)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| shared-glass-modifier | 01 | 0 | GLASS-01, GLASS-02 | — | N/A | build | `xcodebuild ... build` | ❌ W0 | ⬜ pending |
| zoom-preset-view | 01 | 1 | LAYOUT-01, GLASS-01 | — | N/A | build + visual | `xcodebuild ... build` | ❌ W0 | ⬜ pending |
| layout-restructure | 01 | 1 | LAYOUT-01, LAYOUT-02 | — | N/A | build + visual | `xcodebuild ... build` | N/A | ⬜ pending |
| torch-quality-glass | 02 | 1 | GLASS-01 | — | N/A | build + visual | `xcodebuild ... build` | N/A | ⬜ pending |
| sheet-glass | 02 | 2 | GLASS-01 | — | N/A | build + visual | `xcodebuild ... build` | N/A | ⬜ pending |
| overlay-verify | 02 | 2 | GLASS-03 | — | N/A | visual | manual | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- `DualVideo/Shared/GlassBackground.swift` — shared `cameraGlassBackground(in:)` ViewModifier extension (GLASS-01, GLASS-02)

*All other changes modify existing files — no new test infrastructure needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Zoom preset row appears above record button | LAYOUT-01 | Visual layout — no automated UI test target | Launch on iOS 26 sim, confirm preset row directly above RecordButton |
| Quality button at bottom-right | LAYOUT-02 | Visual layout | Launch on iOS 26 sim, confirm trailing position |
| Controls show glass (no black rectangle) | GLASS-01 | Visual — glass rendering is perceptual | Point camera at bright scene; confirm material is adaptive |
| iOS 26 uses .glassEffect(), iOS 18 uses .ultraThinMaterial | GLASS-02 | Requires two simulator targets | Build and launch on iPhone 16 Pro (iOS 26) + iPhone 15 (iOS 18) |
| Recording overlay consistent with glass controls | GLASS-03 | Visual comparison | Start recording, compare overlay capsule vs zoom/torch/quality glass weight |

---

## Validation Sign-Off

- [ ] All tasks have build verification (compile-time feedback)
- [ ] Visual checks specified for all 5 requirements
- [ ] Wave 0 covers GlassBackground.swift creation before application tasks
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s (build time)
- [ ] `nyquist_compliant: true` set in frontmatter when complete

**Approval:** pending
