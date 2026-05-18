---
phase: 4
slug: video-quality
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-18
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (system, iOS SDK) |
| **Config file** | Xcode scheme — `DualVideoTests` target |
| **Quick run command** | `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DualVideoTests/VideoQualitySettingsTests` |
| **Full suite command** | `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16'` |
| **Estimated runtime** | ~60 seconds (simulator boot + unit tests) |

---

## Sampling Rate

- **After every task commit:** Run quick command targeting affected test class
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | VQ-01, VQ-02, VQ-04 | — | Resolution/bitrate values are clamped to enum cases (no arbitrary injection) | unit | `xcodebuild test ... -only-testing:DualVideoTests/VideoQualitySettingsTests` | ❌ W0 | ⬜ pending |
| 4-01-02 | 01 | 1 | VQ-01 | — | activeFormat selection filters isMultiCamSupported | unit | `xcodebuild test ... -only-testing:DualVideoTests/CameraManagerTests` | ✅ extend | ⬜ pending |
| 4-01-03 | 01 | 1 | VQ-01, VQ-02 | — | MovieRecorder uses dimensions/bitrate from settings, not hardcoded | unit | `xcodebuild test ... -only-testing:DualVideoTests/MovieRecorderTests` | ✅ extend | ⬜ pending |
| 4-02-01 | 02 | 2 | VQ-03 | Trim range OOB | inPoint >= .zero, outPoint <= duration, inPoint < outPoint enforced | unit (async) | `xcodebuild test ... -only-testing:DualVideoTests/VideoTrimManagerTests` | ❌ W0 | ⬜ pending |
| 4-02-02 | 02 | 2 | VQ-03 | — | pendingTrimURL set after stopRecording; auto-save NOT called until user acts | unit | `xcodebuild test ... -only-testing:DualVideoTests/RecordingManagerTests` | ✅ extend | ⬜ pending |
| 4-03-01 | 03 | 3 | VQ-03 | — | Trim UI sheet appears after recording stops | manual | Launch app, record, stop — verify trim sheet appears | N/A | ⬜ pending |
| 4-03-02 | 03 | 3 | VQ-01, VQ-02 | — | Quality settings sheet accessible pre-recording | manual | Tap settings icon — verify picker shows 720p/1080p + Low/Medium/High | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `DualVideoTests/UnitTests/VideoQualitySettingsTests.swift` — unit tests for `OutputResolution`, `BitratePreset`, `VideoQualitySettings` save/load (covers VQ-01, VQ-02, VQ-04)
- [ ] `DualVideoTests/UnitTests/VideoTrimManagerTests.swift` — async unit test for `VideoTrimManager.trim(url:range:)` with a synthetic `.mov` (covers VQ-03)

*Existing `MovieRecorderTests.swift`, `RecordingManagerTests.swift`, `CameraManagerTests.swift` will be extended — not replaced.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Trim sheet appears after stopping recording | VQ-03 | Requires live camera session + real recording file | Record 5s clip, stop, verify trim sheet appears before Photos save |
| Quality settings picker accessible pre-recording | VQ-01, VQ-02 | UI interaction on physical device | Tap settings icon while idle, change resolution, start recording, verify no crash |
| Settings persist after app kill | VQ-04 | Requires real UserDefaults across process restart | Change quality setting, force-quit app, relaunch, verify setting retained |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
