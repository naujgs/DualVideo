---
phase: 3
slug: save-polish-and-edge-cases
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-17
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built into Xcode) |
| **Config file** | Xcode scheme — no external config file |
| **Quick run command** | `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DualVideoTests` |
| **Full suite command** | `xcodebuild test -scheme DualVideo -destination 'id=<device-udid>'` (physical device) |
| **Estimated runtime** | ~45 seconds (unit tests on simulator) |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DualVideoTests`
- **After every plan wave:** Run full unit suite + manual on-device smoke test
- **Before `/gsd-verify-work`:** Full unit suite green + manual device validation
- **Max feedback latency:** ~45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | OUT-01 | T-temp-file | Temp .mov deleted only after Photos save succeeds | unit (mock) | `xcodebuild test -only-testing:DualVideoTests/PhotoSaveManagerTests` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | OUT-02 | — | Save denied UX shown when Photos permission denied | unit | `xcodebuild test -only-testing:DualVideoTests/PhotoSaveManagerTests` | ❌ W0 | ⬜ pending |
| 03-01-03 | 01 | 1 | DEV-03 | — | PHPhotoLibrary.authorizationStatus checked before save | unit (mock) | `xcodebuild test -only-testing:DualVideoTests/PhotoSaveManagerTests` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | 2 | OUT-03 | — | PiP snaps to nearest corner on drag end | unit | `xcodebuild test -only-testing:DualVideoTests/PiPSnapTests` | ❌ W0 | ⬜ pending |
| 03-02-02 | 02 | 2 | OUT-03 | — | PiP corner persists across app launches | unit | `xcodebuild test -only-testing:DualVideoTests/PiPSnapTests` | ❌ W0 | ⬜ pending |
| 03-03-01 | 03 | 3 | OUT-04 | — | Torch toggles on/off without crashing MultiCam session | manual | On-device: tap torch, verify LED, verify recording continues | Manual only | ⬜ pending |
| 03-03-02 | 03 | 3 | OUT-04 | — | Zoom label reflects backZoomFactor | unit | `xcodebuild test -only-testing:DualVideoTests/ZoomLabelTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `DualVideoTests/UnitTests/PhotoSaveManagerTests.swift` — stubs for OUT-01, OUT-02, DEV-03

*PiPOverlayStateTests and CameraManagerTests already exist from Phase 1/2.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Video saves to Photos and appears in Camera Roll | OUT-01 | PHPhotoLibrary write requires physical device entitlement | 1. Record 5s. 2. Stop. 3. Verify Photos notification appears. 4. Open Photos — confirm .mov is present. |
| Torch LED activates during recording | OUT-04 | Requires physical torch hardware | 1. Start recording. 2. Tap torch button. 3. Verify LED lights. 4. Tap again — verify LED off. 5. Stop recording — verify .mov is valid. |
| Interruption recovery: phone call during recording | OUT-04 (edge case) | Cannot simulate phone call in simulator | 1. Start recording. 2. Receive/make a phone call. 3. End call, foreground app. 4. Verify recording stopped cleanly, .mov saved. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
