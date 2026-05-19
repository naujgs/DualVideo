---
status: partial
phase: 07-4k-capability-detection-and-conditional-ui
source: [07-VERIFICATION.md]
started: 2026-05-19T00:00:00Z
updated: 2026-05-19T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Non-capable device — 4K option hidden
expected: On iPhone XR / A12 (or any device without 4K MultiCam support), the 4K option is absent from the quality picker in QualitySettingsSheet
result: [pending]

### 2. Capable device — 4K option visible
expected: On iPhone 15 Pro+ (A17 Pro with 4K MultiCam), the 4K option appears in the quality picker after the camera session starts
result: [pending]

### 3. Storage estimate label renders on device
expected: The storage time-remaining label is visible in QualitySettingsSheet on real hardware (Simulator always returns 0 free bytes, so this can only be verified on device)
result: [pending]

### 4. Stale .uhd4K persisted setting auto-downgraded
expected: If .uhd4K was previously saved to UserDefaults and the app is launched on non-capable hardware, the .onChange guard in CameraContentView silently downgrades to .hd1080p at runtime without user action
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
