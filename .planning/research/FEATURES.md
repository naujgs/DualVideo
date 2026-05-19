# Feature Landscape: iOS Localization (Spanish + English)

**Domain:** SwiftUI iOS app localization — two-language (en/es), system-driven
**Researched:** 2026-05-19
**Scope:** Milestone v1.4 only — what must change to add Spanish alongside existing English

---

## What iOS Handles Automatically vs. What Requires Manual Work

Understanding this boundary is the single most important input for scoping this milestone.

### iOS / SwiftUI handles automatically (zero dev effort):

- **Language selection at runtime.** iOS reads the user's Settings > General > Language & Region preference and selects the correct `.lproj` bundle at launch. No in-app picker, no restart logic, no `UserDefaults` key needed.
- **`Text("literal")` and `Button("literal")` resolution.** SwiftUI infers `LocalizedStringKey` from any string literal passed to `Text`, `Button`, `Label`, `Picker` label argument, `Toggle`, etc. If a matching key exists in `Localizable.strings` (or the `.xcstrings` catalog), it is substituted automatically at render time.
- **RTL layout mirroring.** Spanish is LTR so this is irrelevant for this milestone, but it is handled by the framework with no extra code.
- **System UI chrome.** Sheet drag handles, navigation bars, `ProgressView` spinner chrome, `Alert` container borders — all system-provided visuals with no text to localize.
- **Xcode String Catalog auto-discovery.** When a `.xcstrings` file exists in the target, Xcode scans the codebase after each build and adds newly found string literal keys automatically. No manual audit needed after initial setup.

### Developer must provide manually:

| Surface | Why Manual | File |
|---------|-----------|------|
| Permission usage descriptions (camera, mic, photos) | Stored in `Info.plist`, not in Swift code; `NSCameraUsageDescription` etc. are not scanned by Xcode | `InfoPlist.strings` per language |
| App display name (`CFBundleDisplayName`) | Also in `Info.plist` | `InfoPlist.strings` per language |
| String variables (not literals) passed to `Text` | SwiftUI only auto-localizes string literals, not `String` variables | Wrap with `String(localized:)` or `Text(verbatim:)` pattern |
| Computed `String`-returning properties (e.g. `blockedMessage`, `storageEstimate`) | These return `String`, not `LocalizedStringKey`; the return values are not looked up | Rewrite to call `String(localized:)` |
| Format strings with interpolation (e.g. `"~\(minutes) min remaining"`) | Interpolation prevents compile-time extraction; needs explicit `String(localized:)` with positional args | `String(localized:)` with `%lld` specifiers |
| `accessibilityLabel` strings | These are `String` arguments, not `LocalizedStringKey` | Wrap with `String(localized:)` |

---

## Table Stakes

Features users expect for a localized app. Missing = product feels incomplete or broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| All visible UI labels translate automatically on system language change | Core promise of "localized app" | Low | `Text("literal")` already localizes if catalog exists; no code change required for these |
| Permission prompts appear in user's language | iOS system dialog shows the developer-provided usage description; if it's English-only, Spanish users see English in the system dialog | Low | Requires `InfoPlist.strings` for `es` with the three usage keys |
| Static label strings in `UnsupportedDeviceView` localized | The unsupported-device screen has two hardcoded English strings | Low | Both are `Text("literal")` — catalog entry only, no code change |
| Static label strings in `PermissionsBlockedView` localized | "Permission Required" title is a `Text("literal")` — free. The body message is computed from a `String`-returning function | Medium | Title: free. `blockedMessage` computed var must be rewritten to use `String(localized:)` with three keys |
| `QualitySettingsSheet` labels localized | "Video Quality", "Applies to both cameras", "Resolution", "Frame Rate" — all `Text("literal")`, free | Low | Four catalog entries only |
| `QualitySettingsSheet` storage estimate strings localized | "Storage unavailable", "Low storage", "min remaining", "hr remaining" computed in a `String`-returning property | Medium | Six string variants with numeric interpolation; requires `String(localized:)` and format specifiers |
| Save success banner localized | `Text("Saved to Photos")` — literal, free | Low | One catalog entry |
| Save failure alert localized | Title "Save Failed", buttons "Open Settings" / "Dismiss", two body variants (permission denial, generic error) | Medium | Title + buttons are `Text("literal")` / `Button("literal")` — free. Body variants are conditional `Text` with interpolation |
| `ProgressView` startup labels localized | "Starting…", "Requesting permissions…" | Low | Both are string literals passed to `ProgressView`; `ProgressView` accepts `LocalizedStringKey` (HIGH confidence per Apple docs) |
| `RootView` "Open Settings" button localized | `Button("Open Settings")` — literal, free | Low | One shared catalog entry (used in two places) |
| Accessibility labels localized | `accessibilityLabel` calls use `String` type, not `LocalizedStringKey` | Low | Four labels in existing code; wrap with `String(localized:)` |

---

## Differentiators

Features beyond the minimum that add quality.

| Feature | Value Proposition | Complexity | Notes |
|---------|------------------|------------|-------|
| String Catalog (`.xcstrings`) over legacy `.strings` | Xcode 15+ native format; compile-time warnings for missing translations, auto-discovery, built-in plural handling, one file vs. many | Low | Strictly better than `Localizable.strings` for new projects; no migration cost since no existing strings file |
| Translator-facing comments on ambiguous strings | "Resolution" means screen resolution here, not conflict resolution; comments in the catalog help a future translator get it right | Low | Add via `.xcstrings` comment field or `String(localized:comment:)` |
| `FrameRatePreset.displayName` localization | "30 FPS" / "60 FPS" / "120 FPS" are probably fine as-is across languages, but the property currently returns `String`; making it use `String(localized:)` keeps the pattern consistent | Low | Debatable — numerals + "FPS" are internationally understood; treat as optional |

---

## Anti-Features

Features to explicitly avoid for this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| In-app language picker / manual override | PROJECT.md explicitly rules this out; iOS system locale is the source of truth | Let iOS handle it; no `@AppStorage("language")` or `Bundle` swapping |
| Adding a third language | Doubles translation effort for each new language; English + Spanish is the stated scope | Keep to two locales |
| Localizing internal log strings | `logger.info("CameraManager: ...")` strings are developer-facing only; translating them wastes effort and pollutes the catalog | Leave all `Logger` call strings as English literals |
| Localizing `OutputResolution.rawValue` ("720p", "1080p", "4K") | These are technical abbreviations used as picker labels and `Codable` keys; translating risks breaking serialization | Leave as-is; "720p" is understood globally |
| Localizing `precondition` / `fatalError` messages | These are developer assertions, never seen by users | Leave in English |

---

## Feature Dependencies (existing UI surfaces)

Map of which existing surfaces require what work:

```
InfoPlist.strings (NEW file, es + en)
  <- NSCameraUsageDescription
  <- NSMicrophoneUsageDescription
  <- NSPhotoLibraryAddUsageDescription

Localizable.xcstrings (NEW file)
  <- UnsupportedDeviceView: 2 strings (Text literals — catalog only)
  <- RootView / ProgressView: 2 strings (Text literals — catalog only)
  <- RootView / PermissionsBlockedView:
      "Permission Required" (literal — catalog only)
      "Open Settings" (literal — catalog only)
      blockedMessage computed var -> 4 String(localized:) keys + code change
  <- CameraContentView / success banner: 1 string (Text literal — catalog only)
  <- CameraContentView / save failure alert:
      "Save Failed" (literal — catalog only)
      "Open Settings" (literal — already shared)
      "Dismiss" (literal — catalog only)
      permission-denied body (Text literal with interpolation — catalog only if static)
      generic error body (Text with \(msg) interpolation -> code change)
  <- QualitySettingsSheet:
      "Video Quality" (literal — catalog only)
      "Applies to both cameras" (literal — catalog only)
      "Resolution" (literal — catalog only)
      "Frame Rate" (literal — catalog only)
      storageEstimate property -> 6 String(localized:) keys + code change
  <- TorchToggleButton accessibilityLabel -> 2 String(localized:) + code change
  <- RecordingStatusOverlay accessibilityLabel -> String(localized:) + code change
  <- RecordButton accessibilityLabel -> 2 String(localized:) + code change
  <- QualitySettingsButton accessibilityLabel -> 2 String(localized:) + code change
```

---

## String Count Inventory

Complete tally of user-visible strings requiring translation:

| String (English) | Surface | Code Change Required? |
|-----------------|---------|----------------------|
| "DualVideo uses your back and front cameras simultaneously to record a picture-in-picture video." | InfoPlist camera | No (InfoPlist.strings) |
| "DualVideo records audio alongside your dual-camera video." | InfoPlist mic | No (InfoPlist.strings) |
| "DualVideo saves your recordings directly to your Photo Library." | InfoPlist photos | No (InfoPlist.strings) |
| "Dual-Camera Recording Unavailable" | UnsupportedDeviceView | No (literal) |
| "DualVideo requires an iPhone with an A12 Bionic chip or newer..." | UnsupportedDeviceView | No (literal) |
| "Starting..." | RootView ProgressView | No (literal) |
| "Requesting permissions..." | RootView ProgressView | No (literal) |
| "Permission Required" | PermissionsBlockedView | No (literal) |
| "Open Settings" | PermissionsBlockedView, alert | No (literal, shared key) |
| Camera blocked message | PermissionsBlockedView | YES — computed String |
| Microphone blocked message | PermissionsBlockedView | YES — computed String |
| Photos blocked message | PermissionsBlockedView | YES — computed String |
| Default blocked message | PermissionsBlockedView | YES — computed String |
| "Saved to Photos" | CameraContentView banner | No (literal) |
| "Save Failed" | CameraContentView alert title | No (literal) |
| "Dismiss" | CameraContentView alert button | No (literal) |
| Permission-denied save body | CameraContentView alert | No (literal — static) |
| "Could not save recording: \(msg)" | CameraContentView alert | YES — interpolation |
| "Video Quality" | QualitySettingsSheet | No (literal) |
| "Applies to both cameras" | QualitySettingsSheet | No (literal) |
| "Resolution" | QualitySettingsSheet | No (literal) |
| "Frame Rate" | QualitySettingsSheet | No (literal) |
| "Storage unavailable" | QualitySettingsSheet | YES — computed String |
| "Low storage" | QualitySettingsSheet | YES — computed String |
| "<1 min remaining" | QualitySettingsSheet | YES — computed String |
| "~X min remaining" | QualitySettingsSheet | YES — computed String + format |
| "~X hr remaining" | QualitySettingsSheet | YES — computed String + format |
| "Turn off torch" / "Turn on torch" | TorchToggleButton a11y | YES — String a11y label |
| "Recording — MM:SS" | RecordingStatusOverlay a11y | YES — String a11y label |
| "Stop Recording" / "Start Recording" | RecordButton a11y | YES — String a11y label |
| "Video quality settings, unavailable" / "Video quality settings" | QualitySettingsButton a11y | YES — String a11y label |

**Total strings requiring Spanish translation: ~32**
**Strings needing code changes (not just catalog entries): ~15**

---

## MVP Recommendation

Prioritize in this order:

1. **Create `Localizable.xcstrings` and add `es` locale** — Xcode project setting first; this unlocks everything else.
2. **`InfoPlist.strings`** — Affects the iOS permission dialogs, the first thing a new user sees. High visibility, low effort.
3. **Catalog-only strings** — All `Text("literal")` and `Button("literal")` surfaces. Add translations; zero code changes. Covers roughly half the string count.
4. **`blockedMessage` computed var in `PermissionsBlockedView`** — High user impact (error state), straightforward rewrite to `String(localized:)`.
5. **`storageEstimate` computed var in `QualitySettingsSheet`** — Requires format-specifier strings; slightly more involved due to numeric interpolation.
6. **Accessibility labels** — Lower visibility (VoiceOver only), but correct for completeness. All follow the same `String(localized:)` pattern.

Defer: Nothing in this milestone should be deferred — the scope is already narrow (two languages, existing surfaces only).

---

## Key Distinction: Catalog-Only vs. Code-Change Strings

**Catalog-only** (no Swift change, just add translations to `.xcstrings`):
- Any `Text("string literal")`, `Button("string literal")`, `Picker("label")`, `ProgressView("string literal")`
- These are already localizable; they just need translated values

**Code-change required** (Swift must be modified before translation can work):
- Computed properties returning `String` (must use `String(localized: "key", comment: "context")`)
- `accessibilityLabel("string")` calls (same fix — wrap with `String(localized:)`)
- Interpolated strings like `"~\(minutes) min remaining"` (must use format specifiers; simplest pattern: split into segments or use `String(format: NSLocalizedString("~%lld min remaining", comment: "..."), minutes)`)

---

## Sources

- Apple Developer Documentation: `NSCameraUsageDescription` — https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSCameraUsageDescription
- Apple Developer Documentation: `LocalizedStringKey` — https://developer.apple.com/documentation/swiftui/localizedstringkey
- WWDC25 Code-along: Explore localization with Xcode — https://developer.apple.com/videos/play/wwdc2025/225/
- Tanaschita: Understanding localization with LocalizedStringKey in SwiftUI — https://tanaschita.com/swiftui-localization/ (MEDIUM confidence)
- Medium: Localizing permissions in iOS app — https://medium.com/@axmadxojaibrohimov/localizing-permissions-in-ios-app-ebe4ef72f3a0 (MEDIUM confidence)
- Technostacks: Localization in SwiftUI — String Catalogs with Xcode 15 — https://technostacks.com/blog/localization-in-swiftui-string-catalogs-with-xcode-15/ (MEDIUM confidence)
- Sachin Khard: How to Localize the Plist file — https://sachinkhard.medium.com/how-to-localize-the-plist-file-ff2755d7a1cf (MEDIUM confidence)
