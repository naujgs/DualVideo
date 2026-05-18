---
phase: 04-video-quality
plan: "04"
subsystem: recording-ui
tags: [swiftui, trim-ui, avkit, range-slider, sheet, recording-pipeline]
dependency_graph:
  requires: [VideoTrimManager.trim(sourceURL:range:), RecordingManager.saveRecording(url:), RecordingManager.pendingTrimURL]
  provides: [TrimRangeBar, TrimSheet]
  affects: [CameraContentView, RecordingManager.pendingTrimURL (cleared after action)]
tech_stack:
  added: [AVKit.VideoPlayer, CoreMedia.CMTimeRange]
  patterns: [SwiftUI invisible-Slider custom range control, Task @MainActor actor-bridged async trim, AVURLAsset async load(.duration), presentationDetents(.large) full-height sheet]
key_files:
  created:
    - DualVideo/Features/Recording/UI/TrimRangeBar.swift
    - DualVideo/Features/Recording/UI/TrimSheet.swift
  modified:
    - DualVideo/Features/Camera/CameraContentView.swift
decisions:
  - "TrimRangeBar uses invisible Slider (opacity 0.01) over custom-drawn ZStack track — standard SwiftUI pattern from RESEARCH.md A7 for gesture+accessibility without UIKit"
  - "trimPhase state machine replaces simple Bool isTrimming — enables precise error branch rendering and alert discrimination"
  - "saveTrimmed() deletes sourceURL after successful trim (try? removeItem) — implements T-04-04-01 orphan file mitigation"
  - "loadDuration() checks FileManager.fileExists before AVURLAsset load — implements T-04-04-03 missing-file guard"
  - "Trimming... uses Unicode ellipsis (\\u{2026}) to match UI-SPEC copy exactly and avoid ASCII triple-dot ligature issues"
metrics:
  duration: "~2 minutes"
  completed_date: "2026-05-18"
  tasks_completed: 2
  tasks_total: 3
  files_created: 2
  files_modified: 2
---

# Phase 04 Plan 04: Trim UI (TrimRangeBar + TrimSheet) — Summary

**One-liner:** TrimRangeBar two-thumb range slider with 1s minimum gap and TrimSheet full-height AVKit sheet wired to VideoTrimManager.trim() and RecordingManager.saveRecording(); CameraContentView placeholder replaced with live TrimSheet.

## What Was Built

**TrimRangeBar.swift**
- Custom two-thumb range slider using the invisible-Slider pattern (opacity 0.01) over a custom-drawn ZStack track
- Track: `Capsule().fill(Color.white.opacity(0.3))`, 4pt height; selected range: `Capsule().fill(Color.white)` offset by `inValue * trackWidth`
- `minimumGap`: computed as `max(1.0 / duration, 0.01)` — prevents inverted/zero-length ranges even for very short clips (T-04-04-02)
- Accessibility: `.accessibilityLabel("Trim start")` / `.accessibilityLabel("Trim end")` with `.accessibilityValue(formatTime(...))` on both sliders
- `formatTime()`: `m:ss` format, no leading zero on minutes per UI-SPEC

**TrimSheet.swift**
- Full-height sheet: `.presentationDetents([.large])`
- `VideoPlayer(player:)` with `.layoutPriority(1)` fills top 60%
- `TrimRangeBar` with `onChange(of: inValue)` driving `player.seek(to:toleranceBefore:toleranceAfter:)` for frame-accurate preview
- In/out time labels using `.font(.system(.footnote, design: .monospaced))`
- State machine via `TrimPhase` enum: `.idle` → `.trimming` → success (pendingTrimURL = nil) or `.error` (alert shown)
- Save Trimmed button shows `ProgressView` + "Trimming…" during export; both buttons disabled while trimming
- `saveTrimmed()`: constructs `CMTimeRange` from fractional slider values × duration → `VideoTrimManager.trim()` → deletes sourceURL on success → `recordingManager.saveRecording(url: trimmedURL)` → `pendingTrimURL = nil`
- `saveFull()`: calls `recordingManager.saveRecording(url: sourceURL)` directly → `pendingTrimURL = nil`
- "Trim Failed" alert with "Save Full" fallback + "Dismiss" (T-04-04-04 path)
- "Save Failed" alert with "Dismiss" only when file unreachable (T-04-04-03 path)
- `loadDuration()`: guards `FileManager.fileExists(atPath:)` before `AVURLAsset.load(.duration)`
- `.onDisappear { player.pause() }` prevents background audio playback after sheet dismissal

**CameraContentView.swift changes**
- Replaced `Color.clear.onAppear` placeholder (Plan 03 stub) with `TrimSheet(sourceURL: url, recordingManager: recordingManager)`
- Sheet trigger binding unchanged: `Binding(get: pendingTrimURL != nil, set: ...)`

**Xcode project.pbxproj**
- Added build file entries `1A000092` / `1A000093` for TrimRangeBar.swift / TrimSheet.swift
- Added file references `1B000092` / `1B000093`
- Added both files to UI group `1E000016` and Sources build phase `2B000001`

## Commits

| Hash | Description |
|------|-------------|
| f690986 | feat(04-04): add TrimRangeBar and TrimSheet UI components |
| 976fadc | feat(04-04): replace pendingTrimURL placeholder with real TrimSheet in CameraContentView |

## Checkpoint

Plan reached `checkpoint:human-verify` (Task 3) after completing Tasks 1 and 2. Human verification of the trim UI on device is required before this plan is marked complete.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — the Plan 03 `Color.clear.onAppear` stub has been fully replaced by the real TrimSheet.

## Threat Surface Scan

All four threat register entries from the plan's `<threat_model>` are mitigated in the implementation:

| Threat | Mitigation Applied |
|--------|-------------------|
| T-04-04-01 Orphaned trimmed output | `saveTrimmed()` calls `try? FileManager.default.removeItem(at: sourceURL)` after successful trim |
| T-04-04-02 Inverted CMTimeRange from Slider | `TrimRangeBar.minimumGap` enforces `inPoint < outPoint` at Slider bounds; `VideoTrimManager.trim()` provides second-layer guard |
| T-04-04-03 pendingTrimURL file missing | `loadDuration()` guards `FileManager.fileExists` → shows "Save Failed" alert → sets `pendingTrimURL = nil` on dismiss |
| T-04-04-04 Export failure | `saveTrimmed()` catch path sets `trimPhase = .error(...)` → shows "Trim Failed" alert with "Save Full" fallback |

No new network endpoints, auth paths, or trust boundaries introduced.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| DualVideo/Features/Recording/UI/TrimRangeBar.swift | FOUND |
| DualVideo/Features/Recording/UI/TrimSheet.swift | FOUND |
| DualVideo/Features/Camera/CameraContentView.swift (TrimSheet wired) | FOUND |
| Color.clear.onAppear placeholder removed | CONFIRMED (grep count = 0) |
| commit f690986 | FOUND |
| commit 976fadc | FOUND |
| Build succeeded | PASSED |
| Full test suite | PASSED (** TEST SUCCEEDED **) |
