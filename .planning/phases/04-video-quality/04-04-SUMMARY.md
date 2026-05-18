---
plan: 04-04
status: complete
tasks_completed: 2
tasks_total: 2
---

## Summary

Removed trim feature per user decision. Replaced BitratePreset with FrameRatePreset (30/60/120 FPS) throughout the quality settings stack. QualitySettingsSheet now shows FPS picker with "Applies to both cameras" subtitle.

## Key files changed
- VideoQualitySettings.swift — FrameRatePreset replaces BitratePreset; frameRate persisted with dedicated UserDefaults key
- QualitySettingsSheet.swift — FPS picker, "Applies to both cameras" subtitle, removed file size hints
- RecordingManager.swift — auto-save restored, pendingTrimURL removed, saveRecording back to private
- CameraContentView.swift — TrimSheet removed; onDismiss now calls applyResolutionFormat + applyFrameRate
- CameraManager.swift — applyFrameRate() added; setFrameDuration() private helper
- MovieRecorder.swift — keyframe interval tracks fps, bitrate removed
- VideoQualitySettingsTests.swift — BitratePreset suite replaced with FrameRatePreset suite
- Deleted: TrimSheet.swift, TrimRangeBar.swift, VideoTrimManager.swift, VideoTrimManagerTests.swift

## Commits

| Hash | Description |
|------|-------------|
| ca4fc5d | feat(04): remove trim feature — user chose not to include post-recording trim |
| 7d0af39 | feat(04): replace bitrate with FPS setting; label sheet "Applies to both cameras" |

## Self-Check: PASSED
