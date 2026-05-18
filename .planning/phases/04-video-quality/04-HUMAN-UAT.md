---
status: partial
phase: 04-video-quality
source: [04-VERIFICATION.md]
started: 2026-05-18T00:00:00.000Z
updated: 2026-05-18T00:00:00.000Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. QualitySettingsButton opens sheet when idle, is non-interactive when recording
expected: Tap button while idle → QualitySettingsSheet opens. During active recording → button at 50% opacity, tap does nothing.
result: [pending]

### 2. Frame rate applies to both cameras end-to-end
expected: Select 60 FPS in sheet, record a clip, inspect file — both camera streams run at 60 FPS.
result: [pending]

### 3. Settings persist across force-quit / relaunch
expected: Set 720p + 60 FPS, force-quit, relaunch → settings still show 720p + 60 FPS.
result: [pending]

### 4. Output file dimensions match 720p selection
expected: Select 720p, record a clip, inspect file dimensions → width=720 (portrait), height=1280.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
