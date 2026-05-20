---
quick_id: 260520-0dx
description: Prevent screen sleep during camera session
date: 2026-05-20
commit: a020cff
status: complete
key_files:
  modified:
    - DualVideo/Features/Camera/CameraContentView.swift
---

# Quick Task 260520-0dx: Prevent screen sleep during camera session

## What was done

Added `.onAppear` / `.onDisappear` modifiers to the outermost view in `CameraContentView` (after `.ignoresSafeArea()`, line 220) to disable the iOS idle timer while the camera view is visible and restore it on exit.

## Self-Check: PASSED

- `isIdleTimerDisabled = true` fires on CameraContentView appear
- `isIdleTimerDisabled = false` fires on CameraContentView disappear
- No new imports needed — UIKit already bridged
- Single atomic commit: a020cff
