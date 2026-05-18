---
status: complete
phase: 03-save-polish-and-edge-cases
source: [03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md]
started: 2026-05-18T00:00:00Z
updated: 2026-05-18T09:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Auto-save to Photos
expected: Record for ~5 seconds. Tap stop. Within a few seconds, a "Saved to Photos" banner appears at the bottom of the screen. Open the Photos app — the .mov file is present in the Camera Roll with portrait orientation.
result: pass

### 2. "Saved to Photos" banner auto-dismisses
expected: After a successful save the "Saved to Photos" banner appears. Without touching anything, it disappears on its own after ~2.5 seconds.
result: pass

### 3. PiP spring-snaps to nearest corner
expected: Drag the front-camera PiP away from its default corner and release. It immediately animates with a spring to whichever of the 4 corners was closest to where you let go.
result: pass

### 4. PiP corner persists across launches
expected: Drag PiP to a non-default corner, let it snap there. Force-quit the app. Reopen it. The PiP appears in the same corner it was left in — no jump to top-right on launch.
result: pass

### 5. Torch button toggles LED
expected: The torch button (flashlight icon) is visible in the bottom-left. Tap it — the iPhone LED turns on and the icon turns yellow. Tap again — LED turns off and icon returns to white.
result: pass

### 6. Zoom label updates during pinch
expected: "1.0x" label is visible just above the record button. Pinch-to-zoom the back camera — the label updates in real time (e.g. "1.5x", "2.0x"). Double-tap resets it to "1.0x".
result: pass

### 7. Recording counter appears at top
expected: Tap record. A timer (00:00, 00:01 …) appears at the top of the screen, just below the Dynamic Island / notch, clearly readable.
result: pass

### 8. Camera preview recovers after interruption
expected: With both cameras live (not recording), receive or make a brief phone call. After hanging up and returning to the app, both camera previews resume automatically — no manual tap required.
result: pass

## Summary

total: 8
passed: 8
issues: 0
skipped: 0
pending: 0

## Gaps

[none yet]
