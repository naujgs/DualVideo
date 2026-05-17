---
phase: 2
slug: recording-pipeline-compositor-writer-audio
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-17
---

# Phase 2 — Validation Strategy

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
- **After every plan wave:** Run full unit suite + manual on-device smoke test (record 10 seconds, verify `.mov` plays in QuickTime)
- **Before `/gsd-verify-work`:** Full unit suite green + manual device validation of valid output `.mov`
- **Max feedback latency:** ~45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | REC-02 | — | Compositor output is non-nil and non-zero-size | unit | `xcodebuild test -only-testing:DualVideoTests/PiPCompositorTests` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | REC-02 | — | CIContext created once, not per frame | unit | `xcodebuild test -only-testing:DualVideoTests/PiPCompositorTests` | ❌ W0 | ⬜ pending |
| 02-02-01 | 02 | 2 | REC-03 | T-temp-file | Valid `.mov` non-zero duration on device | integration/manual | Record on device, inspect in QuickTime | Manual only | ⬜ pending |
| 02-02-02 | 02 | 2 | REC-04 | — | finishWriting called on background notification; file URL non-nil | unit (mock) | `xcodebuild test -only-testing:DualVideoTests/MovieRecorderTests` | ❌ W0 | ⬜ pending |
| 02-02-03 | 02 | 2 | REC-03 | — | startSession uses first sample's actual PTS, not .zero | unit (mock) | `xcodebuild test -only-testing:DualVideoTests/MovieRecorderTests` | ❌ W0 | ⬜ pending |
| 02-03-01 | 03 | 3 | REC-01 | — | RecordingState transitions idle→recording→idle on start/stop | unit | `xcodebuild test -only-testing:DualVideoTests/RecordingManagerTests` | ❌ W0 | ⬜ pending |
| 02-03-02 | 03 | 3 | CAP-04 | — | Elapsed timer increments from 0 after Record tap | unit | `xcodebuild test -only-testing:DualVideoTests/RecordingManagerTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `DualVideoTests/PiPCompositorTests.swift` — stubs for REC-02 (compositor with synthetic CVPixelBuffers)
- [ ] `DualVideoTests/RecordingManagerTests.swift` — stubs for CAP-04 (timer), REC-01 (state transitions)
- [ ] `DualVideoTests/MovieRecorderTests.swift` — stubs for REC-04 (finalization under mock interruption), REC-03 timestamp contract

*No framework install needed — XCTest is available in Xcode project*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Output `.mov` file is valid and playable with non-zero duration | REC-03 | Requires physical camera — Simulator has no camera; AVCaptureMultiCamSession not available on Simulator | 1. Build and run on iPhone XR. 2. Tap Record. 3. Wait 10 seconds. 4. Tap Stop. 5. Open recorded file URL in Files or airdrop to Mac. 6. Open in QuickTime — verify video plays with audio, duration ≥ 9s. |
| Dual-mic audio: both back and front mic beams deliver non-silent audio | REC-03 (audio track) | iOS 16.1+ regression may cause silent frames — must validate on iOS 18 device | 1. Record 10 seconds. 2. Inspect waveform in QuickTime or Audacity. 3. Confirm non-zero amplitude throughout. If silent: activate single back-mic fallback. |
| Recording survives app backgrounding without corrupt file | REC-04 | Cannot simulate background transition in unit tests with AVFoundation state | 1. Start recording. 2. Press Home button to background app. 3. Foreground app. 4. Verify pending file URL is set and `.mov` is playable. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
