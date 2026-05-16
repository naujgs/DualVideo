---
phase: 1
slug: foundation-permissions-session-live-preview
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-16
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift — Xcode built-in) |
| **Config file** | DualVideoTests/ (created in Wave 0) |
| **Quick run command** | `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing DualVideoTests/UnitTests 2>&1 \| tail -20` |
| **Full suite command** | `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 \| tail -40` |
| **Estimated runtime** | ~30 seconds |

> **Note:** Camera/AVCaptureMultiCamSession features require a physical device (iPhone XR or later). Simulator tests cover state machines, permission logic, and non-camera units. Device tests are manual-only.

---

## Sampling Rate

- **After every task commit:** Run quick XCTest unit suite
- **After every plan wave:** Run full XCTest suite + manual device smoke test
- **Before `/gsd-verify-work`:** Full suite must be green + device preview confirmed
- **Max feedback latency:** 30 seconds (unit), device test on demand

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | DEV-01 | — | N/A | unit | `xcodebuild build -scheme DualVideo` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | DEV-02 | — | PermissionManager handles denied state | unit | `xcodebuild test -only-testing DualVideoTests/PermissionManagerTests` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 1 | CAP-01 | — | N/A | manual | Device: dual preview visible | — | ⬜ pending |
| 1-02-02 | 02 | 2 | CAP-02 | — | N/A | unit | `xcodebuild test -only-testing DualVideoTests/CameraManagerTests` | ❌ W0 | ⬜ pending |
| 1-03-01 | 03 | 2 | CAP-03 | — | N/A | manual | Device: PiP drag + pinch-zoom | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `DualVideoTests/UnitTests/PermissionManagerTests.swift` — stubs for DEV-02
- [ ] `DualVideoTests/UnitTests/CameraManagerTests.swift` — stubs for CAP-02 state machine
- [ ] `DualVideoTests/UnitTests/RecordingViewModelTests.swift` — stubs for state enum
- [ ] XCTest is pre-installed with Xcode — no framework install needed

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Dual camera live preview (back full-screen, front PiP) | CAP-01 | Requires physical device; Simulator has no camera | Connect iPhone XR, run on device, verify both previews render simultaneously |
| PiP overlay drag gesture | CAP-03 | Requires physical touch input on device | Drag front-camera overlay to each corner; verify smooth repositioning |
| Pinch-to-zoom on back camera | CAP-03 | Requires physical pinch gesture on device | Pinch on back camera area; verify zoom label updates and zoom responds |
| Hardware cost log on A12 | CAP-01 | Requires A12 device + console | Check Xcode console for `session.hardwareCost` < 0.9 after commitConfiguration |
| Permission prompts | DEV-02 | Requires device + fresh install | Delete app, reinstall, verify camera/mic prompts appear with explanation text |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
