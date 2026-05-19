---
phase: 7
slug: 4k-capability-detection-and-conditional-ui
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-19
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest / Swift Testing |
| **Config file** | None — Wave 0 installs stubs |
| **Quick run command** | Build scheme "DualVideo" (device or simulator) |
| **Full suite command** | Run "DualVideoTests" scheme on physical device |
| **Estimated runtime** | ~30 seconds (unit tests); manual device checks for K4-01/K4-02 |

> Note: AVFoundation camera sessions require a physical device. Unit-testable logic (storage estimate, enum extension, fallback guard) can run in simulator.

---

## Sampling Rate

- **After every task commit:** Build succeeds, zero compiler errors
- **After every plan wave:** Run DualVideoTests unit targets for storage estimate + fallback logic
- **Before phase verification:** Full suite green + manual device verification of K4-01 and K4-02 on both test devices (iPhone XR + iPhone 17 Pro Max)
- **Max feedback latency:** ~30 seconds (build + unit run)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 7-01-01 | 01 | 1 | K4-01, K4-02 | — | N/A | build | `xcodebuild build -scheme DualVideo` | ✅ | ⬜ pending |
| 7-01-02 | 01 | 1 | K4-01 | — | N/A | manual device | Run on iPhone XR, verify `supports4K=false` in log | N/A | ⬜ pending |
| 7-01-03 | 01 | 1 | K4-02 | — | N/A | unit | XCTest: QualitySettingsSheet picker filters `.uhd4K` when `supports4K=false` | ❌ W0 | ⬜ pending |
| 7-02-01 | 02 | 1 | K4-05 | — | N/A | unit | XCTest: `storageEstimate` returns "~X min remaining" at valid freeBytes | ❌ W0 | ⬜ pending |
| 7-02-02 | 02 | 1 | K4-05 | — | N/A | unit | XCTest: `storageEstimate` returns "Low storage" when freeBytes < 1 GB | ❌ W0 | ⬜ pending |
| 7-02-03 | 02 | 1 | SC-4 | — | N/A | unit | XCTest: fallback guard writes `.hd1080p` when `supports4K=false` + saved `.uhd4K` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `DualVideoTests/QualitySettingsSheetTests.swift` — stubs for K4-02 (conditional picker) and K4-05 (storage estimate label logic)
- [ ] `DualVideoTests/VideoQualitySettingsTests.swift` — stubs for `.uhd4K` enum case, `Codable` round-trip, and decode fallback
- [ ] `DualVideoTests/CameraManagerSupports4KTests.swift` — unit-testable portion: mock format list to drive `supports4K` detection result

*Note: CameraManager has AVFoundation dependencies. The unit-testable portion is the format-list filtering logic. Full K4-01 device validation is manual-only (no simulator camera).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `supports4K == false` on iPhone XR | K4-01 | No simulator camera; XCTest cannot mock AVCaptureDevice format list at runtime | Run app on XR; open Console.app or Xcode logs; confirm `CameraManager: detect4KCapability result=false` |
| 4K absent from quality panel on XR | K4-02 | Physical device required for full end-to-end UI verification | Tap quality button on XR; verify picker shows only 720p and 1080p |
| `supports4K` result on iPhone 17 Pro Max | K4-01 | STATE.md blocker — A18 Pro 4K MultiCam is MEDIUM confidence, requires device validation | Run app on iPhone 17 Pro Max; check log for `supports4K=true/false`; log full format list if false |
| 4K option visible on 17 Pro Max (if K4-01 passes) | K4-02 | Physical device required | Open quality panel on 17 Pro Max; verify 4K segment appears |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
