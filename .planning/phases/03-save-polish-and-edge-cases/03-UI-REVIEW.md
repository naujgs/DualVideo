# Phase 03 — UI Review

**Audited:** 2026-05-17
**Baseline:** Abstract 6-pillar standards (no UI-SPEC.md for this phase)
**Screenshots:** Not captured — native iOS app (no web dev server; Playwright not applicable)

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 4/4 | All strings are specific, contextual, and action-oriented |
| 2. Visuals | 3/4 | Strong hierarchy and SF Symbol use; ZoomLabelView placement split from TorchToggleButton reduces column cohesion |
| 3. Color | 4/4 | Minimal, purposeful palette — red for record, yellow for torch-on, white for inactive, black backgrounds |
| 4. Typography | 3/4 | 5 distinct font expressions in use; mixed point-size and semantic-size specification style |
| 5. Spacing | 3/4 | Mostly consistent; two arbitrary point values (20, 40) without a documented spacing token |
| 6. Experience Design | 4/4 | Disabled states, transient banners, error alerts with recovery action, accessibility labels on all icon buttons |

**Overall: 21/24**

---

## Top 3 Priority Fixes

1. **ZoomLabelView placed in bottom-center VStack, not left column with TorchToggleButton** — Users scanning for zoom level must look away from the torch button area, breaking the spatial grouping of camera controls — Move `ZoomLabelView` into the left-column `VStack` that currently holds only `TorchToggleButton`, removing it from the bottom-center `VStack(spacing: 0)`. The current code in `CameraContentView.swift` lines 108–114 puts the zoom label above the record button; the plan (03-03-PLAN.md Task 2) specified a stacked left column for both controls.

2. **Mixed font specification styles create implicit coupling debt** — Specifying `TorchToggleButton` at `.system(size: 30)` and `ZoomLabelView` at `.system(size: 14)` as raw point values means these sizes will not scale with Dynamic Type — users with accessibility display sizes will not benefit from larger text — Replace both with semantic text styles (`RecordingStatusOverlay` already uses `.system(.body, design: .monospaced)`) or document the intentional exception with a comment explaining why fixed sizes are used in a camera HUD context.

3. **`RecordingStatusOverlay` lacks an accessibility label on the blinking dot** — The red dot is a purely visual blink indicator with no accessible equivalent — VoiceOver users will not know recording is active beyond the elapsed timer text — Add `.accessibilityHidden(true)` to the blinking dot `Circle()` and an `.accessibilityLabel("Recording")` to the enclosing `HStack`, or wrap the entire overlay in an `accessibilityElement(children: .combine)` with a computed label like `"Recording — \(formattedTime)"`.

---

## Detailed Findings

### Pillar 1: Copywriting (4/4)

All user-visible strings are specific and contextual. No generic labels ("OK", "Cancel", "Submit") found anywhere in the codebase.

Standout examples:
- **Save-failure alert** (`CameraContentView.swift:207`): "DualVideo doesn't have permission to save to Photos. Open Settings to allow access." — names the app, explains the gap, directs action.
- **saveFailed branch** (`CameraContentView.swift:209`): "Could not save recording: \(msg)" — concrete, includes system error detail.
- **Success banner** (`CameraContentView.swift:116`): "Saved to Photos" — minimal, accurate, no unnecessary punctuation.
- **Permission blocked messages** (`RootView.swift:88–95`): each branch addresses the specific denied permission by name and explains why it is required.
- **UnsupportedDeviceView** (`UnsupportedDeviceView.swift:9`): "Dual-Camera Recording Unavailable" — product-specific, not "Error".
- **RecordButton accessibility** (`RecordButton.swift:35`): dynamic "Stop Recording" / "Start Recording" — no generic "Button".
- **TorchToggleButton accessibility** (`TorchToggleButton.swift:18`): "Turn off torch" / "Turn on torch" — state-aware, directional.

No empty-state strings were needed for this phase (camera always has content when the view is shown). No "No data" or "Nothing here" antipatterns found.

---

### Pillar 2: Visuals (3/4)

**Strengths:**
- The full-bleed back camera as the primary layer with a 28%-width front PiP at top-right creates an immediate and clear visual hierarchy (`CameraContentView.swift:21–82`).
- PiP has `cornerRadius: 12`, `shadow(radius: 4)`, and spring corner-snap — it reads as a distinct overlay, not a flush camera frame.
- `RecordingStatusOverlay` uses `.ultraThinMaterial` capsule background — good depth separation from video content without fully obscuring.
- `RecordButton` design (outer ring always visible, inner shape morphs) communicates state without color alone.
- SF Symbols `flashlight.on.fill` / `flashlight.off.fill` are semantically correct and well-established for torch controls.

**Issues:**
- **ZoomLabelView is positioned in the bottom-center VStack** (`CameraContentView.swift:112`), not in the left column with `TorchToggleButton` (`CameraContentView.swift:95–106`). The plan (03-03-PLAN.md Task 2, lines 387–419) shows both controls in a single left-column `VStack(spacing: 8)`. The implementation broke them into separate ZStack layers: torch is bottom-left, zoom label is bottom-center just above the record button. This creates the false impression that zoom level is a record button affordance rather than a camera control.
- **`ProgressView("Starting…")` and `ProgressView("Requesting permissions…")`** in `RootView.swift` have no visual framing (no background, no logo) — they appear as raw spinner+label on the default system background. For a camera app this is a jarring system-feel interruption before the full-bleed camera experience. This is a pre-existing issue not introduced in Phase 3, but still a visual gap.

---

### Pillar 3: Color (4/4)

The palette is small and intentional:

| Color | Usage | Element |
|-------|-------|---------|
| `Color.red` | Record indicator dot, idle record button fill | RecordingStatusOverlay, RecordButton |
| `Color.yellow` | Torch active state | TorchToggleButton |
| `Color.white` | All other foreground UI — inactive torch, record ring, status timer, zoom label | TorchToggleButton, RecordButton, RecordingStatusOverlay, ZoomLabelView |
| `Color.black.opacity(0.4–0.6)` | HUD element backgrounds | ZoomLabelView, TorchToggleButton, "Saved to Photos" banner |
| `Color.clear` | Gesture capture layer | CameraContentView |
| `.secondary` | Unsupported/permission-blocked screen text | UnsupportedDeviceView, PermissionsBlockedView |
| `.ultraThinMaterial` | RecordingStatusOverlay capsule | RecordingStatusOverlay |

No hardcoded hex literals or `rgb()` values found anywhere. No color token system exists (this is a single-developer native iOS app), but the usage is consistent enough that no token system is needed at this scale.

Red is used exclusively for recording-state signals (dot, button fill), never for errors or destructive actions — which is the correct semantic for a camera app where red = record.

---

### Pillar 4: Typography (3/4)

**Font expressions found across the codebase:**

| Expression | File | Context |
|-----------|------|---------|
| `.system(size: 64)` | RootView.swift:67, UnsupportedDeviceView.swift:7 | Icon-sized SF Symbol |
| `.title2.bold()` | RootView.swift:70, UnsupportedDeviceView.swift:10 | Heading text |
| `.body` | RootView.swift:72, UnsupportedDeviceView.swift:15 | Body copy |
| `.system(.body, design: .monospaced).bold()` | RecordingStatusOverlay.swift:27 | Timer MM:SS |
| `.system(size: 14, weight: .semibold, design: .monospaced)` | ZoomLabelView.swift:8 | Zoom factor label |
| `.system(size: 30, weight: .medium)` | TorchToggleButton.swift:12 | SF Symbol icon size |
| `.caption` | CameraContentView.swift:117 | "Saved to Photos" banner |

**Issues:**
- 7 distinct font expressions is more than the abstract 4-font-size guideline, though several are in non-overlapping contexts (loading screens vs camera HUD vs unsupported device).
- `TorchToggleButton` and `ZoomLabelView` use raw `.system(size:)` point values rather than semantic text styles, which means they do not respond to Dynamic Type accessibility settings. Camera HUDs frequently exempt themselves from Dynamic Type, but this decision is not documented in code comments.
- The plan specified `TorchToggleButton` at `size: 22` (03-03-PLAN.md line 256) but the implemented file uses `size: 30` (`TorchToggleButton.swift:12`). The change likely improved tap target feel (larger icon = easier touch on a camera HUD), and the on-device verification passed, but it is an undocumented deviation.
- Mixing `.semibold` (ZoomLabelView) and `.medium` (TorchToggleButton) at adjacent locations in the same HUD column is a minor weight inconsistency; `.medium` throughout the HUD would be more uniform.

---

### Pillar 5: Spacing (3/4)

**Spacing values found in Phase 3 UI files:**

| Value | Location | Purpose |
|-------|----------|---------|
| `PiPOverlayState.edgeMargin` (= 12pt) | CameraContentView.swift:60–61 | PiP edge inset — named constant, good |
| `40` pt | CameraContentView.swift:88 | RecordingStatusOverlay top padding below Dynamic Island |
| `20` pt | CameraContentView.swift:102 | TorchToggleButton leading padding |
| `24` pt | CameraContentView.swift:103, 149 | Bottom padding above home indicator (used consistently) |
| `10` pt | CameraContentView.swift:113 | ZoomLabelView bottom gap above record button |
| `8` pt | CameraContentView.swift:123 | "Saved to Photos" banner bottom padding |
| `12` pt | CameraContentView.swift:119, RecordingStatusOverlay:30 | Horizontal capsule padding (consistent) |
| `6` pt | CameraContentView.swift:120, RecordingStatusOverlay:31 | Vertical capsule padding (consistent) |
| `16` pt | TorchToggleButton.swift:14 | Icon internal padding |
| `8/4` pt | ZoomLabelView.swift:10–11 | Pill horizontal/vertical padding |

**Issues:**
- `40` (RecordingStatusOverlay top offset, line 88) and `20` (TorchToggleButton leading, line 102) are magic numbers with no named constant. `edgeMargin` (12pt) is defined as a static constant on `PiPOverlayState` — the `20` leading inset and `40` top offset for status should follow the same pattern or be documented as intentional per-layout values.
- `24` is used twice for the "above home indicator" spacing and is consistent, which is a positive signal. Worth extracting to a named layout constant for future maintainability.
- The plan specified `TorchToggleButton` internal padding at `12` pt (`03-03-PLAN.md:258`) but implementation uses `16` pt (`TorchToggleButton.swift:14`). This results in a larger tap circle than planned — likely an improvement for usability, but undocumented.
- Capsule padding (12/6) is consistent between `RecordingStatusOverlay` and the "Saved to Photos" banner — good system cohesion.

---

### Pillar 6: Experience Design (4/4)

Phase 3 specifically targeted this pillar and delivers strong coverage:

**State coverage:**

| State | Implementation | File |
|-------|--------------|------|
| Loading (app startup) | `ProgressView("Starting…")` | RootView.swift:12 |
| Permission requesting | `ProgressView("Requesting permissions…")` | RootView.swift:18 |
| Permission denied | `PermissionsBlockedView` with "Open Settings" CTA | RootView.swift:21 |
| Unsupported device | `UnsupportedDeviceView` with explanation | RootView.swift:15 |
| Recording active | `RecordingStatusOverlay` with blinking dot + timer | CameraContentView.swift:85–92 |
| Finalizing recording | Record button disabled + 0.5 opacity | RecordButton.swift:32–33 |
| Save success | Transient "Saved to Photos" banner, auto-dismisses after 2.5s | CameraContentView.swift:115–131 |
| Save failed (permission) | Alert "Save Failed" with "Open Settings" / "Dismiss" and specific message | CameraContentView.swift:183–213 |
| Save failed (system) | Same alert with `error.localizedDescription` in message | CameraContentView.swift:209 |
| Torch on | Yellow icon, `accessibilityLabel` "Turn off torch" | TorchToggleButton.swift |
| Torch off | White icon, `accessibilityLabel` "Turn on torch" | TorchToggleButton.swift |
| Session interruption | Torch auto-off, recording stops cleanly, session sync on resume | RecordingManager.swift |
| PiP restore | Restores last-used corner on `onAppear` without animation | PiPOverlayState.swift:116–133 |

**Accessibility:**
- `RecordButton`: `.accessibilityLabel(isRecording ? "Stop Recording" : "Start Recording")` — dynamic, correct.
- `TorchToggleButton`: `.accessibilityLabel(isTorchOn ? "Turn off torch" : "Turn on torch")` — dynamic, correct.
- `RecordingStatusOverlay`: no accessibility label on the composite HStack. VoiceOver will read the timer digits but not convey "recording in progress." This is the one gap.
- Zoom label (`ZoomLabelView`) displays formatted text — VoiceOver reads it correctly as-is.

**Interaction hardening:**
- `snapToNearestCorner()` with euclidean distance prevents PiP from floating in ambiguous mid-screen positions.
- `withAnimation(.interactiveSpring)` on PiP during drag + `withAnimation(.spring)` on snap release creates a two-phase feel: rubber-band drag, then snap.
- Double-tap gesture on back camera resets zoom — discoverable convenience but not labelled; acceptable for a power-user feature.

---

## Files Audited

- `DualVideo/Features/Camera/CameraContentView.swift`
- `DualVideo/Features/Camera/PiPOverlayState.swift`
- `DualVideo/Features/Camera/UnsupportedDeviceView.swift`
- `DualVideo/Features/Recording/UI/TorchToggleButton.swift`
- `DualVideo/Features/Recording/UI/ZoomLabelView.swift`
- `DualVideo/Features/Recording/UI/RecordButton.swift`
- `DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift`
- `DualVideo/Features/Root/RootView.swift`
- `.planning/phases/03-save-polish-and-edge-cases/03-01-SUMMARY.md`
- `.planning/phases/03-save-polish-and-edge-cases/03-02-SUMMARY.md`
- `.planning/phases/03-save-polish-and-edge-cases/03-03-SUMMARY.md`
- `.planning/phases/03-save-polish-and-edge-cases/03-01-PLAN.md`
- `.planning/phases/03-save-polish-and-edge-cases/03-02-PLAN.md`
- `.planning/phases/03-save-polish-and-edge-cases/03-03-PLAN.md`
