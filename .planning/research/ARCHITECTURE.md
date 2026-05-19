# Architecture Research — iOS Localization (v1.4)

**Researched:** 2026-05-19
**Milestone:** v1.4 — Language / Localization
**Confidence:** HIGH for SwiftUI Text() behavior, String Catalog mechanics, and component integration (Apple documentation + current sources). MEDIUM for ViewModel string return patterns (community consensus, no single authoritative Apple reference).

---

## Scope

This document answers six specific questions for adding English + Spanish localization to an existing SwiftUI MVVM app:

1. Where do localized strings live, and which format to use?
2. How does `SwiftUI.Text()` automatic localization work?
3. What needs to change in Views vs ViewModels?
4. Where does `InfoPlist.strings` fit?
5. What new files and folders get created?
6. What is the correct build order for this app?

---

## String Storage: String Catalog (Localizable.xcstrings)

**Use String Catalogs. Do not use `.strings` files.**

Rationale:
- This project targets iOS 18.0+, Xcode 15+ is the build tool. String Catalogs are the current Apple-recommended format (WWDC 2023).
- A single `Localizable.xcstrings` JSON file holds all languages. No per-language files to sync manually.
- Xcode auto-extracts keys from SwiftUI `Text("literal")` and `String(localized:)` calls during each build when **"Use Compiler to Extract Swift Strings"** build setting is enabled.
- At build time Xcode compiles `.xcstrings` down to `.strings` / `.stringsdict` files inside each `.lproj` folder, so the compiled output is backward-compatible with any iOS version. The file format itself only requires Xcode 15+ to edit — the deployment target is unaffected.
- Missing translations are automatically flagged as "New" in the catalog editor, giving visibility into untranslated strings at a glance.

**One file covers all surface types except `InfoPlist` keys.** System permission strings (`NSCameraUsageDescription`, etc.) require a separate `InfoPlist.xcstrings` (Xcode 15+) or, equivalently, per-language `InfoPlist.strings` files. These live in the same `.lproj` folders but are a separate catalog.

---

## New Files and Folder Structure

Starting from zero localization infrastructure, the following get created:

```
DualVideo/
  App/
    Info.plist                       [MODIFIED — keys moved to InfoPlist.xcstrings]
    InfoPlist.xcstrings              [NEW — permission description strings, en + es]
  Resources/                         [NEW folder, or placed alongside App/]
    Localizable.xcstrings            [NEW — all UI strings, en + es]
```

Xcode adds the language reference in the project file. At build time it synthesizes:

```
DualVideo.app/
  en.lproj/
    Localizable.strings              [compiled from xcstrings]
    InfoPlist.strings                [compiled from InfoPlist.xcstrings]
  es.lproj/
    Localizable.strings
    InfoPlist.strings
```

You never create or edit these `.lproj` folders or `.strings` files manually. They are build artifacts.

**How to add languages in Xcode:** Project settings → Info tab → Localizations → "+" → Spanish. This enables Xcode to extract Spanish slots in the catalog editor.

---

## How SwiftUI Text() Automatic Localization Works

This is the most important architectural fact for this milestone. It determines which strings get localization "for free" and which need explicit work.

### The Rule

`Text()` accepts two distinct initializer overloads:

```swift
// Overload 1: string literal → LocalizedStringKey → catalog lookup
Text("Save Failed")            // ✅ localizes automatically

// Overload 2: String variable → displayed verbatim, no lookup
let msg: String = "Save Failed"
Text(msg)                      // ❌ displays the raw String, no catalog lookup
```

SwiftUI converts string literals to `LocalizedStringKey` at compile time via `ExpressibleByStringLiteral`. The key is the literal text itself. At runtime, `LocalizedStringKey` triggers a lookup in `Localizable.strings` (compiled from the catalog) for the current device locale.

Xcode's build phase ("Use Compiler to Extract Swift Strings") scans source for string literals passed to `Text()`, `Button()`, `Label()`, `Picker()`, `Toggle()`, `.alert()`, and similar SwiftUI view constructors, and populates the `.xcstrings` catalog with those keys automatically.

### String Interpolation in Text()

`Text("Could not save recording: \(msg)")` works as a localized interpolated string. The key stored in the catalog is `"Could not save recording: %@"`. The translated Spanish entry replaces `%@` in the correct position for the target language's word order. This is critical: do not build these strings by concatenation.

### Text(verbatim:) to Opt Out

Any literal you intentionally do not want extracted (debug text, formatted values that are not translatable):

```swift
Text(verbatim: "02:34")         // never extracted, always displayed as-is
Text(String(format: "%02d:%02d", m, s))  // String variable → same, not extracted
```

The `RecordingStatusOverlay.formattedTime` computed property returns `String(format: "%02d:%02d", ...)`. This is displayed via `Text(formattedTime)` — a String variable — so it is never extracted and requires no localization work. Correct behavior.

### accessibilityLabel and accessibilityValue

`accessibilityLabel("Stop Recording")` accepts a string literal and behaves identically to `Text()` — it is extracted to the catalog automatically. String variable arguments are not localized.

---

## Integration Points: What Changes in Views vs ViewModels

### Views — What Changes

**Pattern: String literals already present in views localize automatically once the catalog is populated.** No code change to the view itself is needed for most cases. The work is adding translations to the catalog.

However, two view-side patterns require code changes:

**1. String variable arguments to Text() that contain user-facing copy.**

In `RootView.swift`, `PermissionsBlockedView.blockedMessage` is a computed `var` returning a `String`, passed as `Text(blockedMessage)`. This does NOT localize because it goes through the String-variable overload.

Fix: change the computed property to return `LocalizedStringKey` or inline the switch into the view body as `Text("camera.permission.denied")` with a separate helper. The cleanest pattern for this app's scale:

```swift
// Before — does not localize
private var blockedMessage: String {
    switch deniedPermission {
    case "camera": return "DualVideo needs camera access..."
    ...
    }
}
Text(blockedMessage)

// After — localizes correctly
private var blockedMessageKey: LocalizedStringKey {
    switch deniedPermission {
    case "camera": return "permission.denied.camera"
    ...
    }
}
Text(blockedMessageKey)
```

Catalog entries use the key `"permission.denied.camera"` with full translated sentences as values in both `en` and `es`.

**2. `QualitySettingsSheet.storageEstimate` computed String property.**

`storageEstimate` returns strings like `"~\(minutes) min remaining"`, `"Low storage"`, `"<1 min remaining"`. These are displayed via `Text(storageEstimate)` — the String-variable overload. They will not localize automatically.

Fix options in order of preference:
- Convert `storageEstimate` to return `LocalizedStringKey` using `String(localized:)` for each branch:

```swift
private var storageEstimateKey: LocalizedStringKey {
    if freeBytes < 1_000_000_000 { return "storage.low" }
    let minutes = Int(freeBytes / bitrateBytesPerSec) / 60
    if minutes == 0 { return "storage.less_than_one_min" }
    if minutes < 60 { return LocalizedStringKey("storage.minutes_remaining \(minutes)") }
    return LocalizedStringKey("storage.hours_remaining \(minutes / 60)")
}
```

Catalog entries use `%lld` interpolation placeholders for the numeric arguments. The Spanish translator receives the full sentence structure and can reorder "45 min restante" as the language requires.

**3. Alert message in CameraContentView.**

```swift
case .saveFailed(let msg):
    Text("Could not save recording: \(msg)")
```

`msg` is an error string from the system. The wrapping literal `"Could not save recording: \(msg)"` IS a LocalizedStringKey with interpolation. This extracts to key `"Could not save recording: %@"` and localizes the surrounding sentence correctly. The `msg` portion is a dynamic system error string that is not translated — acceptable.

The second alert message:

```swift
Text("DualVideo doesn't have permission to save to Photos. Open Settings to allow access.")
```

This is a plain string literal — it localizes automatically.

**4. `.alert("Save Failed", ...)` and `.alert` titles.**

Alert title `"Save Failed"` is a string literal → localizes automatically. Same for button labels `"Open Settings"`, `"Dismiss"`.

**5. `ProgressView("Starting…")` and `ProgressView("Requesting permissions…")`** in `RootView` — these are string literal arguments, extract automatically.

### ViewModels / Actors — What Changes

The ViewModels in this app (`CameraManager`, `RecordingManager`, `PermissionManager`, `PhotoSaveManager`, `MovieRecorder`) do not produce user-visible strings directly — they are data and session management layers.

The one exception is `PermissionDeniedReason.rawValue` used as a routing token:

```swift
enum PermissionDeniedReason: String, Sendable {
    case camera = "camera"
    case microphone = "microphone"
    case photos = "photos"
}
```

The raw value `"camera"` is used in `AppRoute.permissionsBlocked(which: String)` and then switched on in `PermissionsBlockedView.blockedMessage`. This is an internal routing identifier, not a display string. The display strings are in the view — follow the `LocalizedStringKey` fix above. The `PermissionDeniedReason` enum and its raw values do not need to change.

**General rule for this app:** ViewModels do not need changes for localization. All user-visible copy lives in Views. The one fix needed is promoting `blockedMessage` and `storageEstimate` from `String` properties to `LocalizedStringKey`-returning properties.

### AccessibilityLabel Changes

Two components have hardcoded accessibility labels as string literals — these localize automatically because string literals passed to `.accessibilityLabel()` are `LocalizedStringKey`:

- `RecordButton`: `.accessibilityLabel(isRecording ? "Stop Recording" : "Start Recording")` — ternary of literals, both literals are extracted. Localizes correctly.
- `TorchToggleButton`: `.accessibilityLabel(isTorchOn ? "Turn off torch" : "Turn on torch")` — same, localizes correctly.
- `RecordingStatusOverlay`: `.accessibilityLabel("Recording — \(formattedTime)")` — interpolated literal with String variable. The surrounding sentence `"Recording — %@"` is a localizable key. The time value is not translated. Correct behavior.

No changes needed to these accessibility labels.

---

## InfoPlist Strings: Permission Descriptions

`Info.plist` currently contains three system-displayed strings:

```
NSCameraUsageDescription
NSMicrophoneUsageDescription
NSPhotoLibraryAddUsageDescription
```

These strings appear in iOS system permission dialogs. iOS reads them from the compiled `InfoPlist.strings` in the matching `.lproj` folder at runtime.

**Approach:** Create `InfoPlist.xcstrings` (Xcode 15 format). Add `en` and `es` translations for all three keys. Remove the inline values from `Info.plist` (they become the fallback; keeping them is redundant but not harmful — removing them is cleaner).

Spanish translations for the three keys:

| Key | English | Spanish |
|-----|---------|---------|
| `NSCameraUsageDescription` | DualVideo uses your back and front cameras simultaneously to record a picture-in-picture video. | DualVideo usa las cámaras frontal y trasera simultáneamente para grabar un video en modo imagen en imagen. |
| `NSMicrophoneUsageDescription` | DualVideo records audio alongside your dual-camera video. | DualVideo graba audio junto con tu video de doble cámara. |
| `NSPhotoLibraryAddUsageDescription` | DualVideo saves your recordings directly to your Photo Library. | DualVideo guarda tus grabaciones directamente en tu Fototeca. |

---

## Complete String Inventory by Surface

This is every user-visible string in the app and its localization status under the current code:

### RootView / PermissionsBlockedView

| String | Current Type | Localizes Automatically | Action Required |
|--------|-------------|-------------------------|-----------------|
| `"Starting…"` | Literal in ProgressView | Yes | Add to catalog |
| `"Requesting permissions…"` | Literal in ProgressView | Yes | Add to catalog |
| `"Permission Required"` | Literal in Text | Yes | Add to catalog |
| blockedMessage camera text | String variable | NO | Change to LocalizedStringKey |
| blockedMessage microphone text | String variable | NO | Change to LocalizedStringKey |
| blockedMessage photos text | String variable | NO | Change to LocalizedStringKey |
| blockedMessage default text | String variable | NO | Change to LocalizedStringKey |
| `"Open Settings"` (button) | Literal in Button | Yes | Add to catalog |

### UnsupportedDeviceView

| String | Current Type | Localizes Automatically | Action Required |
|--------|-------------|-------------------------|-----------------|
| `"Dual-Camera Recording Unavailable"` | Literal in Text | Yes | Add to catalog |
| Long body text | Literal in Text | Yes | Add to catalog |

### CameraContentView

| String | Current Type | Localizes Automatically | Action Required |
|--------|-------------|-------------------------|-----------------|
| `"Saved to Photos"` | Literal in Text | Yes | Add to catalog |
| `"Save Failed"` (alert title) | Literal | Yes | Add to catalog |
| `"Open Settings"` (alert button) | Literal | Yes | Add to catalog |
| `"Dismiss"` (alert button) | Literal | Yes | Add to catalog |
| `"DualVideo doesn't have permission…"` | Literal in Text | Yes | Add to catalog |
| `"Could not save recording: \(msg)"` | Interpolated literal | Yes (sentence localizes) | Add to catalog |

### QualitySettingsSheet

| String | Current Type | Localizes Automatically | Action Required |
|--------|-------------|-------------------------|-----------------|
| `"Video Quality"` | Literal in Text | Yes | Add to catalog |
| `"Applies to both cameras"` | Literal in Text | Yes | Add to catalog |
| `"Resolution"` (section header) | Literal in Text | Yes | Add to catalog |
| `"Resolution"` (Picker label) | Literal in Picker | Yes | Add to catalog |
| `r.rawValue` in ForEach ("720p", "1080p", "4K") | String variable | NO | Use Text(verbatim: r.rawValue) OR add explicit entries; these are unit labels, not sentences |
| `"Frame Rate"` (section header) | Literal in Text | Yes | Add to catalog |
| `"Frame Rate"` (Picker label) | Literal in Picker | Yes | Add to catalog |
| `fps.displayName` in ForEach ("30 FPS", etc.) | String variable | NO | displayName returns String; see below |
| storageEstimate strings | String variable | NO | Change to LocalizedStringKey |

**OutputResolution rawValues** (`"720p"`, `"1080p"`, `"4K"`) are technical unit labels. Two approaches:
- `Text(verbatim: r.rawValue)` — opt out of localization, display exactly as coded. Correct if these labels are universal (Spanish speakers understand "720p" and "4K").
- Add explicit catalog entries and return `LocalizedStringKey` — only needed if the label should translate. For video resolution labels, `Text(verbatim:)` is correct.

**FrameRatePreset.displayName** returns `"30 FPS"`, `"60 FPS"`, `"120 FPS"`. FPS is a universal abbreviation. `Text(verbatim: fps.displayName)` is correct. No catalog entries needed. Change `Text(fps.displayName)` to `Text(verbatim: fps.displayName)` to be explicit and silence the Xcode localization warning that will otherwise appear.

### RecordingStatusOverlay

| String | Current Type | Localizes Automatically | Action Required |
|--------|-------------|-------------------------|-----------------|
| `formattedTime` (e.g. "02:34") | String variable | No (and correct — time format is universal) | Use Text(verbatim: formattedTime) to suppress warning |
| `"Recording — \(formattedTime)"` (accessibilityLabel) | Interpolated literal | Yes (surrounding text) | Add to catalog |

### RecordButton / TorchToggleButton

| String | Current Type | Localizes Automatically | Action Required |
|--------|-------------|-------------------------|-----------------|
| `"Stop Recording"` | Literal (ternary) | Yes | Add to catalog |
| `"Start Recording"` | Literal (ternary) | Yes | Add to catalog |
| `"Turn off torch"` | Literal (ternary) | Yes | Add to catalog |
| `"Turn on torch"` | Literal (ternary) | Yes | Add to catalog |

### ZoomIndicatorView

| String | Current Type | Localizes Automatically | Action Required |
|--------|-------------|-------------------------|-----------------|
| `String(format: "%.1f×", zoomFactor)` | String variable | No (numeric + symbol, universal) | Use Text(verbatim:) or leave as String variable — no catalog entry needed |

---

## Data Flow: How Locale Selection Works

No code changes needed for locale selection. iOS handles this automatically:

1. User sets device language in iOS Settings → General → Language & Region.
2. At app launch, `Bundle.main` resolves which `.lproj` folder to use (e.g., `es.lproj`).
3. `LocalizedStringKey` lookups hit the compiled `Localizable.strings` in that folder.
4. No `UserDefaults`, no in-app language picker, no runtime locale management is needed.

This matches the milestone requirement: "System language detection via iOS locale — no manual override in settings."

---

## Build Order

Dependencies drive the order. Each step must complete before the next.

### Step 1: Xcode Project Setup

Enable localization infrastructure:
- Project settings → Info → Localizations: add "Spanish (es)".
- Build Settings → "Use Compiler to Extract Swift Strings" → Yes.

This is a one-time project configuration. No Swift files change.

### Step 2: Create Localizable.xcstrings

File → New → String Catalog → name it `Localizable`.

Add it to the DualVideo target. Build once — Xcode auto-populates the catalog with every string literal currently used in `Text()`, `Button()`, `Label()`, `Picker()`, `.alert()` across all Swift source files. This gives the English baseline.

### Step 3: Fix String Variable Leaks (Code Changes)

Before translating, close the two gaps where String variables bypass the catalog:

**3a. PermissionsBlockedView.blockedMessage** — change from `var blockedMessage: String` to `var blockedMessageKey: LocalizedStringKey`. Update the four switch branches to return symbolic keys (`"permission.denied.camera"`, etc.) rather than full sentences. Update the call site to `Text(blockedMessageKey)`. Rebuild — Xcode extracts the four new keys.

**3b. QualitySettingsSheet.storageEstimate** — change to `var storageEstimateKey: LocalizedStringKey`. Return `LocalizedStringKey("storage.low")`, `LocalizedStringKey("storage.less_than_one_min")`, `LocalizedStringKey(stringLiteral: "storage.minutes_remaining \(minutes)")`, etc. Rebuild — Xcode extracts keys with their interpolation signatures.

**3c. Opt-out verbatim literals** — change `Text(fps.displayName)` → `Text(verbatim: fps.displayName)` and `Text(formattedTime)` → `Text(verbatim: formattedTime)`. This suppresses Xcode's "untranslated" warnings for these intentional non-localized values. Build to confirm no new untranslated warnings.

### Step 4: Create InfoPlist.xcstrings

File → New → String Catalog → name it `InfoPlist`. Add the three permission keys with English and Spanish values. Remove (or leave, but prefer to remove) the inline values from `Info.plist` to avoid duplication confusion.

### Step 5: Translate All Keys to Spanish

In Xcode's catalog editor, every key now has an "English" value (auto-populated) and an empty "Spanish" slot. Fill in all Spanish translations. The complete key list is derivable from the inventory table above.

Key symbolic keys to define (not auto-extracted, must be added manually because they come from LocalizedStringKey return values):

```
permission.denied.camera
permission.denied.microphone
permission.denied.photos
permission.denied.unknown
storage.low
storage.less_than_one_min
storage.minutes_remaining   (with %lld placeholder)
storage.hours_remaining     (with %lld placeholder)
storage.unavailable
```

All remaining keys are auto-extracted literals.

### Step 6: Test

- iOS Simulator: Settings app → General → Language & Region → iPhone Language → Español. Relaunch. All strings should display in Spanish.
- Physical iPhone XR: same procedure.
- Verify permission dialogs display Spanish text (requires triggering a fresh permission request, or resetting permissions in iOS Settings → Privacy).
- Verify no "New" (untranslated) entries remain in the catalog editor.

---

## Component Summary: New vs Modified vs Unchanged

| File | Status | Change |
|------|--------|--------|
| `DualVideo/App/Info.plist` | MODIFIED | Remove three NSUsageDescription inline values |
| `DualVideo/App/InfoPlist.xcstrings` | NEW | Permission description strings, en + es |
| `DualVideo/Resources/Localizable.xcstrings` | NEW | All UI strings, en + es |
| `DualVideo/Features/Root/RootView.swift` | MODIFIED | `blockedMessage` → `blockedMessageKey: LocalizedStringKey` |
| `DualVideo/Features/Recording/UI/QualitySettingsSheet.swift` | MODIFIED | `storageEstimate` → `storageEstimateKey: LocalizedStringKey`; `Text(fps.displayName)` → `Text(verbatim:)`; `Text(r.rawValue)` → `Text(verbatim:)` |
| `DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift` | MODIFIED (minor) | `Text(formattedTime)` → `Text(verbatim: formattedTime)` |
| All other Swift source files | UNCHANGED | String literals in Text/Button/Label/alert already localize automatically |
| Xcode project file | MODIFIED | Add Spanish language, enable string extraction build setting |

---

## Key Architectural Constraints

**No ViewModel changes needed.** All user-visible strings in this app originate in Views. `CameraManager`, `RecordingManager`, `PermissionManager`, `MovieRecorder`, and `PiPCompositor` are correct as-is.

**The auto-extraction build setting is critical.** Without "Use Compiler to Extract Swift Strings" = Yes in Build Settings, the catalog will not self-populate from source. Manual key entry would be required for every string. Enable this setting in Step 1 and keep it on.

**Key naming strategy:** Use semantic keys (e.g., `"permission.denied.camera"`) for symbolic `LocalizedStringKey` return values. Use the English text itself as the key for auto-extracted literals (Xcode default). This means the catalog mixes two key styles. This is normal and correct — do not fight it by forcing all keys to be symbolic.

**String interpolation word order:** Spanish may require different argument positions than English. The catalog supports `%lld` positional arguments. When adding Spanish translations for interpolated keys, confirm the argument order is natural for the Spanish sentence.

---

## Confidence Assessment

| Area | Confidence | Basis |
|------|------------|-------|
| String Catalog format choice | HIGH | Apple WWDC23 documentation; iOS 18.0 target has no backward compat concern |
| Text() literal vs variable behavior | HIGH | Apple documentation on LocalizedStringKey; ExpressibleByStringLiteral protocol |
| String variable bypass gap | HIGH | Confirmed in Apple docs and multiple current sources |
| ViewModel no-change conclusion | HIGH | Direct code read — no user-visible strings originate in ViewModels |
| blockedMessage fix pattern | HIGH | Standard LocalizedStringKey return pattern, well-documented |
| storageEstimate fix pattern | MEDIUM | LocalizedStringKey interpolation with computed values is documented; exact syntax for the placeholder signatures warrants a compile-time check |
| InfoPlist.xcstrings approach | HIGH | Xcode 15 feature, documented by Apple; project is on iOS 18 / Xcode 15+ |
| Auto-extraction build setting | HIGH | Documented in WWDC23 String Catalog session |
| Spanish translations content | LOW | Provided as starting-point text only; a fluent Spanish speaker should review before shipping |
