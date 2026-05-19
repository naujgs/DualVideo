# Phase 5: UI Polish - Research

**Researched:** 2026-05-18
**Domain:** SwiftUI layout restructuring + iOS 26 Liquid Glass / ultraThinMaterial fallback
**Confidence:** HIGH (glass API), HIGH (layout patterns), HIGH (existing code inventory)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Zoom control moves from the left column to directly above the record button in the bottom-center area (LAYOUT-01).
- **D-02:** Quality settings button moves from the left column to the bottom-right of the screen (LAYOUT-02).
- **D-03:** Torch toggle position is Claude's discretion — it was the only remaining control in the former left column after zoom and quality move out.
- **D-04:** The zoom control becomes three separate tappable preset buttons: `[ 1x ]  [ 2x ]  [ 3x ]`. The active preset is highlighted (bold/filled). This replaces the current single `ZoomLabelView` display label.
- **D-05:** Presets are 1x, 2x, 3x — matching the current pinch clamping range (1.0–3.0x).
- **D-06:** Visual design must match the iPhone Camera app aesthetic — capsule-shaped buttons, active state clearly distinguished from inactive.
- **D-07:** Pinch-to-zoom gesture continues to work and updates the active preset highlight when the zoom lands near a preset value (Claude's discretion on threshold).
- **D-08:** All camera controls get glass treatment — ZoomPresetButton, TorchToggleButton, QualitySettingsButton, RecordingStatusOverlay. No Color.black.opacity(0.4) backgrounds remain on controls.
- **D-09:** Glass API: `.glassEffect()` on iOS 26+; `.ultraThinMaterial` fallback on iOS 18–25. (Locked in STATE.md — do not revisit.)
- **D-10:** QualitySettingsSheet gets glass styling applied to its background and controls.
- **D-11:** "Saved to Photos" success capsule gets glass styling — replaces `.black.opacity(0.6)`.
- **D-12:** Trim sheet and unsupported device view are NOT in scope for glass styling in Phase 5.
- **D-13:** RecordingStatusOverlay already uses `.ultraThinMaterial` — GLASS-03 is largely satisfied. Verify consistency only.
- **D-14:** RecordingStatusOverlay position stays at top-center — no position change.

### Claude's Discretion
- Exact torch toggle position after the left column is vacated by zoom and quality controls.
- Zoom preset highlight threshold (how close pinch zoom must be to a preset for it to appear "active").
- Exact padding/spacing between the three zoom preset buttons.
- Any tinting, vibrancy, or opacity tuning on glass backgrounds to ensure readability over the camera feed.

### Deferred Ideas (OUT OF SCOPE)
- Trim sheet glass styling — excluded from Phase 5.
- Unsupported device view glass styling — excluded from Phase 5.
- Animated glass shimmer on record start — deferred future requirement.
- Custom PiP corner radius user setting — future requirement.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LAYOUT-01 | Zoom label positioned above the record button in the bottom-center area | ZoomPresetView replaces ZoomLabelView; placed in the bottom-center VStack above RecordButton |
| LAYOUT-02 | Quality settings button at bottom-right of the screen (not left column) | QualitySettingsButton relocated to a trailing-aligned overlay in CameraContentView |
| GLASS-01 | Camera control buttons display glass/material background (no black.opacity) | Replace Color.black.opacity(0.4) on TorchToggleButton, QualitySettingsButton; ZoomPresetView uses glass from the start |
| GLASS-02 | iOS 26+ uses .glassEffect(); iOS 18–25 uses .ultraThinMaterial fallback | glassedBackground ViewModifier pattern with #available(iOS 26, *) |
| GLASS-03 | Recording status overlay is visually consistent with glass controls | RecordingStatusOverlay already uses .ultraThinMaterial; verify consistency; no change expected |
</phase_requirements>

---

## Summary

Phase 5 has two independent workstreams that can be developed in parallel: (1) CameraContentView layout restructuring — moving zoom and quality controls to new positions and replacing `ZoomLabelView` with a new `ZoomPresetView` — and (2) glass/material styling across all controls.

The glass API surface is well-understood. iOS 26 ships `.glassEffect()` as a SwiftUI view modifier applied to any view; older iOS uses `.background(.ultraThinMaterial, in: Shape())`. The cleanest pattern for this project is a shared `@ViewBuilder` extension or `ViewModifier` that branches on `#available(iOS 26, *)`, so each control calls one modifier and the conditional is isolated to a single place.

`RecordingStatusOverlay` already uses `.ultraThinMaterial` and will need minimal or no work — it is the reference implementation the other controls should match in weight. `QualitySettingsSheet` uses the system-provided sheet background by default; adding glass requires either a `.presentationBackground(.ultraThinMaterial)` / `.glassEffect()` on the sheet content or a custom sheet background.

**Primary recommendation:** Build the shared glass modifier first (Wave 0 infra), then apply it uniformly to each control (Wave 1). Handle layout restructuring in the same wave as the zoom preset replacement since both touch `CameraContentView`.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 18+ built-in | All UI composition | Already in use throughout app |
| AVFoundation | iOS 18+ built-in | Camera manager, zoom API | Already integrated |

### Supporting APIs
| API | Availability | Purpose | Notes |
|-----|-------------|---------|-------|
| `.glassEffect(_:in:)` | iOS 26+ | Liquid Glass on any view | New in iOS 26 (WWDC 2025) [VERIFIED: Apple Docs] |
| `.background(.ultraThinMaterial, in:)` | iOS 15+ | Glass fallback | Already used in RecordingStatusOverlay [VERIFIED: codebase] |
| `GlassEffectContainer` | iOS 26+ | Groups adjacent glass views for merged rendering | Use for the three zoom preset buttons together [CITED: dev.to/diskcleankit] |
| `.buttonStyle(.glass)` | iOS 26+ | Applies glass to Button without modifier ordering issues | Useful workaround for interactive button artifacts [CITED: atelier-socle.com] |
| `.presentationBackground` | iOS 16.4+ | Custom sheet background material | For QualitySettingsSheet glass [ASSUMED] |

**No new packages to install** — all APIs are system-provided.

---

## Architecture Patterns

### Recommended Project Structure

No new directories are needed. Changes stay inside:

```
DualVideo/Features/
├── Camera/
│   └── CameraContentView.swift       # Layout restructure — all control positions change
└── Recording/
    └── UI/
        ├── ZoomPresetView.swift       # NEW — replaces ZoomLabelView.swift
        ├── ZoomLabelView.swift        # DELETED (or repurposed for formatZoom helper)
        ├── TorchToggleButton.swift    # MODIFIED — glass background
        ├── QualitySettingsButton.swift # MODIFIED — glass background
        ├── RecordingStatusOverlay.swift # VERIFY ONLY — already uses ultraThinMaterial
        └── QualitySettingsSheet.swift  # MODIFIED — glass sheet background
DualVideo/Shared/                      # Consider adding GlassBackground.swift here
```

### Pattern 1: Shared Glass ViewModifier (the key reuse pattern)

**What:** A single `@ViewBuilder` extension on `View` that applies the correct glass style based on runtime iOS version.
**When to use:** On every control background, replacing every `Color.black.opacity(0.4)` call.

```swift
// Source: livsycode.com/swiftui/implementing-the-glasseffect-in-swiftui/
// Adapted for project's circle and capsule shapes
extension View {
    @ViewBuilder
    func cameraGlassBackground<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
```

Applying it (replaces `.background(Color.black.opacity(0.4)).clipShape(Circle())`):
```swift
Image(systemName: "flashlight.off.fill")
    .padding(16)
    .cameraGlassBackground(in: Circle())
```

### Pattern 2: ZoomPresetView — Three Capsule Buttons

**What:** A horizontal row of three tappable capsule-shaped buttons (1x, 2x, 3x). The active preset has a visually distinct (bold/filled) state; inactive buttons are subtle glass.
**When to use:** Replaces `ZoomLabelView` entirely in `CameraContentView`.

```swift
// Source: existing codebase patterns + [CITED: dev.to/diskcleankit GlassEffectContainer pattern]
struct ZoomPresetView: View {
    let currentZoom: CGFloat
    let onPresetSelected: (CGFloat) -> Void

    private let presets: [CGFloat] = [1.0, 2.0, 3.0]
    // Threshold: within 0.25x of a preset triggers active highlight
    // (Claude's discretion per D-07 — 0.25 covers most tap-settle positions)
    private func isActive(_ preset: CGFloat) -> Bool {
        abs(currentZoom - preset) < 0.25
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.self) { preset in
                Button(action: { onPresetSelected(preset) }) {
                    Text(formatPreset(preset))
                        .font(.system(.footnote, design: .monospaced,
                                      weight: isActive(preset) ? .bold : .regular))
                        .foregroundStyle(isActive(preset) ? Color.primary : Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                // Active: glassProminent (filled/tinted); Inactive: regular glass
                // [CITED: Apple glassEffect docs — .glassProminent for emphasis]
                .buttonStyle(.plain)
                .cameraGlassBackground(in: Capsule())  // applied uniformly; foreground handles active emphasis
            }
        }
        // Wrap in GlassEffectContainer on iOS 26+ for merged rendering
        // [CITED: dev.to/diskcleankit]
    }
}

private func formatPreset(_ factor: CGFloat) -> String {
    factor == factor.rounded() ? "\(Int(factor))x" : "\(factor)x"
}
```

**Note on GlassEffectContainer:** On iOS 26+ the three zoom buttons should be wrapped in `GlassEffectContainer` so they render as a unified glass group (morphing effect when close together). On iOS 18–25 the container is unavailable — use an `if #available` guard around it, or factor out via the shared modifier extension.

```swift
// iOS 26+: merged pill group
if #available(iOS 26, *) {
    GlassEffectContainer {
        zoomButtonRow
    }
} else {
    zoomButtonRow
}
```

### Pattern 3: CameraContentView Layout After Restructure

**What:** Remove the left column VStack entirely. Place torch toggle in bottom-leading or mid-screen overlay. Place quality button in bottom-trailing. Place zoom preset row directly above record button.

```swift
// Bottom-center stack: zoom presets above, record button below
VStack(spacing: 12) {
    Spacer()
    ZoomPresetView(
        currentZoom: cameraManager.backZoomFactor,
        onPresetSelected: { factor in
            cameraManager.setZoom(factor)
            activeZoomBase = factor   // keep pinch baseline in sync
        }
    )
    RecordButton(...)
        .padding(.bottom, geo.safeAreaInsets.bottom + 24)
}

// Bottom-trailing: quality button
VStack {
    Spacer()
    HStack {
        Spacer()
        QualitySettingsButton(isRecording: ..., onTap: ...)
            .padding(.trailing, 24)
            .padding(.bottom, geo.safeAreaInsets.bottom + 28)
    }
}

// Bottom-leading (recommendation for torch, D-03 discretion):
VStack {
    Spacer()
    HStack {
        TorchToggleButton(isTorchOn: ..., onTap: ...)
            .padding(.leading, 20)
            .padding(.bottom, geo.safeAreaInsets.bottom + 28)
        Spacer()
    }
}
```

### Pattern 4: Saved to Photos Glass Capsule

**What:** Replace `.background(.black.opacity(0.6))` with glass background.

```swift
// Current (to remove):
.background(.black.opacity(0.6))
.clipShape(Capsule())

// New:
.cameraGlassBackground(in: Capsule())
```

### Pattern 5: QualitySettingsSheet Glass Background

**What:** Apply glass or material to the sheet content.

```swift
// Option A — presentationBackground (iOS 16.4+, clean approach):
.sheet(isPresented: $showQualitySettings) {
    QualitySettingsSheet(...)
        .presentationBackground(.ultraThinMaterial)   // works iOS 16.4+
}

// Option B — on iOS 26 with glassEffect on the sheet container:
// Apply .glassEffect() inside QualitySettingsSheet on the VStack wrapper
```

D-10 says "glass styling on sheet background and controls" — `presentationBackground(.ultraThinMaterial)` on iOS 18–25 and `.glassEffect()` on the sheet root VStack on iOS 26+ achieves this. [ASSUMED — presentationBackground(.glassEffect) may not exist; verify at build time]

### Anti-Patterns to Avoid

- **Glass over glass:** Never stack `.glassEffect()` on a view that is itself inside another glass view — the lens sampling breaks visually. `GlassEffectContainer` is the correct solution for adjacent glass elements. [CITED: atelier-socle.com]
- **Wrong modifier order:** Apply `.glassEffect()` to the Button (or its label container), not nested inside the label hierarchy. Modifier order on iOS 26 is significant.
- **`.glassProminent` + `.circle`:** Known rendering artifacts on iOS 26. Test thoroughly if used for the torch button active state; use `.regular` + foreground tint change as the safer alternative. [CITED: atelier-socle.com]
- **Leaving `activeZoomBase` stale on preset tap:** When the user taps a preset (e.g., 2x), the gesture baseline must be updated to 2.0 or pinch-to-zoom will snap back to the wrong value on the next gesture.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Glass/material style | Custom blur + gradient shader | `.glassEffect()` / `.ultraThinMaterial` | System APIs handle dark/light adaption, vibrancy, and performance |
| iOS version branching | Runtime `UIDevice` OS version string parsing | `#available(iOS 26, *)` | Compiler-safe, optimized, idiomatic Swift |
| Grouped glass rendering | Multiple overlapping glass views | `GlassEffectContainer` | Prevents visual glitching from glass sampling glass |
| Zoom active state from pinch | Timer-based polling of zoom value | Read `cameraManager.backZoomFactor` directly in view body | Already reactive via `@Observable` pattern |

---

## Common Pitfalls

### Pitfall 1: Stale `activeZoomBase` After Preset Tap
**What goes wrong:** User taps 2x preset, then pinches. Pinch multiplies from `activeZoomBase` which is still 1.0, so small pinch immediately snaps to an incorrect zoom.
**Why it happens:** `activeZoomBase` in `CameraContentView` is only updated in the `MagnificationGesture.onEnded` handler, not in the preset button action.
**How to avoid:** In `ZoomPresetView`'s `onPresetSelected` closure, pass the selected factor up and also update `activeZoomBase`.
**Warning signs:** After a tap preset, the first pinch gesture jumps discontinuously.

### Pitfall 2: `GlassEffectContainer` Not Available on iOS 18–25
**What goes wrong:** Wrapping the zoom button row in `GlassEffectContainer` without an `#available` check causes a compile-time error with iOS 18 deployment target.
**Why it happens:** `GlassEffectContainer` is an iOS 26-only API.
**How to avoid:** Always guard with `if #available(iOS 26, *)` or use a `@ViewBuilder` helper.
**Warning signs:** Build fails with "unavailable" error in Debug/Release for iOS 18 target.

### Pitfall 3: `.glassEffect()` Modifier Ordering Causes Invisible Buttons
**What goes wrong:** Glass renders but the button's tap area is outside the glass shape, or the glass clips the content.
**Why it happens:** On iOS 26, `.glassEffect()` should be applied to the full Button view after its content is sized, not nested inside the label.
**How to avoid:** Apply the modifier at the `Button` level (or just outside it), not inside the label's child views.
**Warning signs:** Button appears glass-styled but is not tappable; or content overflows the glass shape.

### Pitfall 4: Glass Sheet Presenting as Opaque
**What goes wrong:** `QualitySettingsSheet` still shows solid system sheet background after adding glass modifiers.
**Why it happens:** The system sheet background is drawn by the presentation layer, not the SwiftUI view tree. Internal modifiers don't override it.
**How to avoid:** Use `.presentationBackground(.ultraThinMaterial)` on the sheet call site in `CameraContentView`, not inside `QualitySettingsSheet` itself.
**Warning signs:** Sheet appears opaque white/dark regardless of any `.background()` modifier inside.

### Pitfall 5: Zoom Preset Active Highlight Fights with Glass Tinting
**What goes wrong:** Using `.glassEffect(.regular.tint(...))` for active state causes both glass render AND tint, but on iOS 18 `.ultraThinMaterial` has no equivalent tint mechanism — active and inactive buttons look identical.
**Why it happens:** `ultraThinMaterial` does not accept tint parameters.
**How to avoid:** Use **foreground/font changes** (bold weight, primary color) for active state, so the active indicator is always visible regardless of glass API. Reserve glass background as purely structural (same for all three buttons); active state is expressed through text styling only.

---

## Code Examples

### Shared Glass Background Extension (Pattern 1)
```swift
// Source: livsycode.com — adapted for project
// Place in DualVideo/Shared/GlassBackground.swift
extension View {
    @ViewBuilder
    func cameraGlassBackground<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
```

### TorchToggleButton — Before/After
```swift
// BEFORE:
.background(Color.black.opacity(0.4))
.clipShape(Circle())

// AFTER:
.cameraGlassBackground(in: Circle())
```

### "Saved to Photos" Capsule — Before/After
```swift
// BEFORE (in CameraContentView):
.background(.black.opacity(0.6))
.clipShape(Capsule())

// AFTER:
.cameraGlassBackground(in: Capsule())
```

### RecordingStatusOverlay — Already Correct
```swift
// Source: [VERIFIED: codebase — RecordingStatusOverlay.swift line 32]
// No change needed; this IS the reference pattern
.background(.ultraThinMaterial, in: Capsule())
```

### GlassEffectContainer for Zoom Preset Row (iOS 26 only)
```swift
// Source: [CITED: dev.to/diskcleankit]
if #available(iOS 26, *) {
    GlassEffectContainer(spacing: 8) {
        zoomButtonRow
    }
} else {
    zoomButtonRow
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.background(Color.black.opacity(0.4))` | `.glassEffect()` / `.ultraThinMaterial` | iOS 26 (WWDC 2025) | Adaptive material that reacts to content behind it |
| Single zoom label (display only) | Three tappable preset buttons | This phase | Matches iOS Camera app UX |
| Grouped controls in left column | Controls at semantic screen positions | This phase | Bottom-center for zoom (above record), bottom-trailing for quality |

**Deprecated patterns in this codebase after Phase 5:**
- `ZoomLabelView.swift` — replaced by `ZoomPresetView.swift`
- All `Color.black.opacity(0.4)` control backgrounds — replaced by glass modifier

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `.presentationBackground(.ultraThinMaterial)` works on the sheet call site to glass the QualitySettingsSheet background | Architecture Patterns — Pattern 5 | Sheet may still appear opaque; fallback: apply background modifier inside QualitySettingsSheet's root VStack |
| A2 | `GlassEffectContainer(spacing: 8)` with 8pt spacing between buttons achieves the merged-pill appearance at close proximity | ZoomPresetView pattern | Spacing param may need tuning; visual check required on device |
| A3 | `cameraManager.backZoomFactor` is `@Observable`-tracked and causes the ZoomPresetView body to re-evaluate on pinch changes without explicit binding | Pattern 2 — ZoomPresetView | If not reactive, zoom preset active highlight won't update during pinch; fix: pass as a `@Binding` or use `@State` mirror |

---

## Open Questions

1. **Is `backZoomFactor` on `CameraManager` published/observable?**
   - What we know: `CameraManager` is passed as `let cameraManager: CameraManager` in `CameraContentView`; `backZoomFactor` is accessed directly (`cameraManager.backZoomFactor`).
   - What's unclear: Whether `CameraManager` uses `@Observable` or `ObservableObject`; if only `setZoom` is called and the property is not `@Published` / `@Observable`, `ZoomPresetView` won't re-render during pinch.
   - Recommendation: Read `CameraManager.swift` during implementation; add `@Observable` or `@Published` to `backZoomFactor` if needed. [Investigate at Wave 0]

2. **`presentationBackground` + glassEffect on sheets**
   - What we know: `.presentationBackground(.ultraThinMaterial)` is available iOS 16.4+ [ASSUMED].
   - What's unclear: Whether `.glassEffect()` is a valid argument to `presentationBackground` on iOS 26, or whether it must be applied to the sheet content view directly.
   - Recommendation: Test both approaches on iOS 26 simulator; fall back to `.presentationBackground(.ultraThinMaterial)` universally if the glassEffect variant is unavailable.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 5 is purely SwiftUI code/layout changes. No external tools, databases, CLI utilities, or services are required. All APIs are system-provided on the existing iOS 18+ deployment target.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None detected (no test targets found in project) |
| Config file | None |
| Quick run command | Build in Xcode — `xcodebuild -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` |
| Full suite command | Same (no automated tests exist) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LAYOUT-01 | Zoom preset row renders above record button | visual/manual | Launch on simulator, verify position | N/A |
| LAYOUT-02 | Quality button at bottom-right | visual/manual | Launch on simulator, verify position | N/A |
| GLASS-01 | Controls show glass background (no black rectangle) | visual/manual | Launch on simulator over camera feed | N/A |
| GLASS-02 | iOS 26 uses glassEffect, iOS 18–25 uses ultraThinMaterial | visual/manual | Test on iOS 26 sim + iOS 18 sim | N/A |
| GLASS-03 | RecordingStatusOverlay consistent with other glass controls | visual/manual | Start recording, compare overlay vs other controls | N/A |

### Wave 0 Gaps
- No automated test infrastructure exists. All validation is visual/manual on-device or simulator.
- For GLASS-02: verify on both iOS 26 simulator and iOS 18 simulator during implementation.

*(No test files to create — project has no test target.)*

---

## Security Domain

Security enforcement: not applicable to this phase. Phase 5 is a pure UI polish pass — no network requests, no user data handling, no authentication flows, no cryptographic operations. No ASVS categories apply.

---

## Sources

### Primary (HIGH confidence)
- [VERIFIED: codebase] — `CameraContentView.swift`, `TorchToggleButton.swift`, `QualitySettingsButton.swift`, `ZoomLabelView.swift`, `RecordingStatusOverlay.swift`, `QualitySettingsSheet.swift`, `RecordButton.swift` — read directly
- [VERIFIED: codebase] — `RecordingStatusOverlay.swift:32` — `.background(.ultraThinMaterial, in: Capsule())` is the existing reference pattern
- [VERIFIED: Xcode project] — `IPHONEOS_DEPLOYMENT_TARGET = 18.0` — deployment target confirmed

### Secondary (MEDIUM confidence — cited from official/trusted sources)
- [CITED: dev.to/diskcleankit] — `GlassEffectContainer`, shape variants, `#available(iOS 26, *)` pattern
- [CITED: atelier-socle.com] — `#available(iOS 26, *)` + `ultraThinMaterial` fallback, known `.glassProminent + .circle` artifact
- [CITED: livsycode.com] — `ViewModifier`/extension pattern for shared glass modifier
- [CITED: donnywals.com] — `GlassEffectContainer` grouping rationale, glass design philosophy
- [CITED: artemnovichkov/xcode-26-system-prompts] — Xcode 26 system documentation for `GlassEffectContainer(spacing:)`

### Tertiary (LOW confidence — for awareness only)
- [ASSUMED] — `.presentationBackground(.ultraThinMaterial)` availability on iOS 16.4+ and whether it accepts `.glassEffect()` on iOS 26

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are system-provided; codebase verified
- Architecture: HIGH — existing code patterns are clear; glass API well-documented via multiple sources
- Pitfalls: HIGH — confirmed from official docs, community sources, and direct codebase analysis
- Sheet glass (D-10): MEDIUM — `presentationBackground` approach is assumed; needs verification at build time

**Research date:** 2026-05-18
**Valid until:** 2026-08-18 (stable APIs — SwiftUI glass API shipped with iOS 26 and is not in beta)
