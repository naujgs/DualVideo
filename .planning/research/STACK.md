# Stack Research — DualVideo

**Researched:** 2026-05-16 (v1 base) / 2026-05-19 (v1.1 4K addendum) / 2026-05-19 (v1.4 Localization addendum)
**Overall confidence:** HIGH for core capture stack (Apple-documented, sample code verified); MEDIUM for iOS 18-specific deltas (no breaking changes found, enhancements are incremental).

---

## v1.4 Addendum: Spanish / English Localization

This section documents the stack additions for milestone v1.4 (Language / Localization). All prior stack decisions remain valid and unchanged. No third-party dependencies are introduced.

**Confidence:** HIGH — all findings come from Apple documentation and Xcode-native tooling, no external libraries required.

---

### What the Localization Stack Consists Of

iOS localization for a SwiftUI app on iOS 18 uses nothing but Xcode-native tooling. The full stack is:

| Component | Technology | Why |
|-----------|------------|-----|
| String storage | `Localizable.xcstrings` (String Catalog) | Modern unified format; replaces both `.strings` and `.stringsdict`; JSON-based; Xcode 15+ native editor |
| Permission string storage | `InfoPlist.xcstrings` | Localizes `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription` without duplicating Info.plist |
| SwiftUI view strings | `LocalizedStringKey` (implicit) | `Text("…")`, `Button("…")`, `Label("…")` treat string literals as `LocalizedStringKey` automatically — zero code change required for most views |
| Non-view strings | `String(localized:)` | Modern Swift replacement for `NSLocalizedString`; required for strings computed outside a SwiftUI view (e.g. `blockedMessage` in `RootView`, `storageEstimate` in `QualitySettingsSheet`) |
| Automatic extraction | `SWIFT_EMIT_LOC_STRINGS = YES` build setting | Tells the compiler to populate the String Catalog automatically at build time from all `LocalizedStringKey` usages and `String(localized:)` calls |
| Language registration | Xcode Project Settings → Localizations | Adds `en` and `es` language targets; creates `en.lproj` / `es.lproj` at build time |

---

### File Format Decision: String Catalogs (.xcstrings) Over .strings

Use `Localizable.xcstrings`, not `Localizable.strings`. Here is why this is the correct choice for this project.

**String Catalogs were introduced in Xcode 15 and are the format Apple recommends for all new work.** The format combines what previously required three separate files — `Localizable.strings` (key-value pairs), `Localizable.stringsdict` (pluralization rules), and manual `.lproj` folder management — into one structured JSON file with a first-class Xcode editor.

Concrete advantages for this project:

- **Automatic extraction.** With `SWIFT_EMIT_LOC_STRINGS = YES`, building the project causes Xcode to scan Swift source and populate the catalog. New strings appear as "New" state; removed strings are marked "Stale". No manual registration of keys needed.
- **Translation state tracking.** The catalog records whether each string is "New", "Translated", or "Needs Review" per language. This surfaces gaps immediately in the Xcode editor.
- **Pluralization built in.** The `storageEstimate` string contains phrases like "~\(minutes) min remaining" which varies with count. String Catalogs handle `%lld minute` / `%lld minutes` plural variants natively without a separate `.stringsdict` file.
- **Single source of truth.** One file per module rather than one file per language. Adding Spanish does not create a parallel file tree.
- **Backward compatible at build time.** Xcode compiles `.xcstrings` down to `.strings` / `.stringsdict` in the built product, so runtime behavior on iOS 18 is identical to classic files.

The only scenario where `.strings` is still appropriate is when targeting Xcode 14 or earlier, or integrating with translation tools that do not yet support the JSON format. Neither applies here: Xcode 16 is the development environment, and this project has no translation service integration.

---

### Xcode Project Settings Required

Three settings changes are needed in Xcode. All are in existing Xcode UI, no xcconfig edits required.

**1. Add Spanish to project localizations**

`Project file → Info tab → Localizations → "+" → Spanish`

This creates `es.lproj` and registers the language. The app will then automatically match iOS system language "Spanish" at runtime.

**2. Enable compiler string extraction**

`Target → Build Settings → Localization → Use Compiler to Extract Swift Strings → YES`

This corresponds to build setting key `SWIFT_EMIT_LOC_STRINGS`. On a new Xcode 15+ project this may already be `YES`. On an existing project (like DualVideo, which predates the localization milestone), verify explicitly — it may be unset.

**3. Set development region**

`Project → Info tab → Development Region → English (en)`

`CFBundleDevelopmentRegion = en` should already be set in Info.plist. This tells iOS which language to fall back to when no translation exists for the device language. Verify it is `en` not the legacy string `"English"`.

---

### API Choices for String Lookup

**In SwiftUI views — no change needed for most strings.**

SwiftUI's `Text`, `Button`, `Label`, `Toggle`, `Picker`, and `.alert` modifiers all accept `LocalizedStringKey` when passed a string literal. This means:

```swift
Text("Video Quality")          // Already localizable — reads from Localizable.xcstrings
Button("Open Settings") { }   // Already localizable
```

These require no code modification. Once the strings are in the catalog and Spanish translations are provided, SwiftUI resolves them at runtime based on `Locale.current`.

**In computed String properties — use `String(localized:)`.**

`String(localized:)` is the modern Swift successor to `NSLocalizedString`, available since iOS 15 (confirmed available on iOS 18). It must be used wherever a `String` value — not a view — is produced:

```swift
// RootView.blockedMessage — currently returns hardcoded String
private var blockedMessage: String {
    switch deniedPermission {
    case "camera":
        return String(localized: "permission.camera.blocked",
                      defaultValue: "DualVideo needs camera access…")
    ...
    }
}
```

```swift
// QualitySettingsSheet.storageEstimate — contains interpolated values
String(localized: "storage.estimate.minutes \(minutes)",
       defaultValue: "~\(minutes) min remaining")
```

**Do not use `NSLocalizedString`.** It is the Objective-C era API, still functional but not compiler-extractable into String Catalogs in all usage patterns. `String(localized:)` is the direct Swift replacement and integrates correctly with `SWIFT_EMIT_LOC_STRINGS`.

**Do not use `LocalizedStringKey` directly in non-SwiftUI code.** `LocalizedStringKey` is a SwiftUI type. Outside view bodies it does not resolve to a `String` without explicit conversion. Use `String(localized:)` instead.

---

### Info.plist Permission Descriptions

The three permission usage descriptions in `Info.plist` must be localized. These strings appear in iOS system permission dialogs — they are the first Spanish text a Spanish-speaking user sees.

**The correct approach for iOS 18 / Xcode 15+:**

Create `InfoPlist.xcstrings` (a second String Catalog, distinct from `Localizable.xcstrings`). Add it to the app target. After the first build, Xcode automatically populates it with the known localizable Info.plist keys, including:

- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSPhotoLibraryAddUsageDescription`

The values in `Info.plist` become the English (development region) source strings. Spanish translations are added in `InfoPlist.xcstrings` for the `es` locale.

**Do not** create `InfoPlist.strings` files manually — that is the legacy approach requiring per-language files. The `.xcstrings` approach is unified and auto-populated by Xcode.

---

### Surfaces to Localize in This Codebase

Based on code inspection, the following strings require localization. All are currently hardcoded English literals.

**`RootView.swift`**

| String | Location | API Needed |
|--------|----------|------------|
| `"Starting…"` | `ProgressView` init | Implicit (LocalizedStringKey) |
| `"Requesting permissions…"` | `ProgressView` init | Implicit (LocalizedStringKey) |
| `"Permission Required"` | `Text` | Implicit (LocalizedStringKey) |
| `"Open Settings"` | `Button` | Implicit (LocalizedStringKey) |
| `"DualVideo needs camera access…"` | `blockedMessage` computed var | `String(localized:)` |
| `"DualVideo needs microphone access…"` | `blockedMessage` computed var | `String(localized:)` |
| `"DualVideo needs Photo Library access…"` | `blockedMessage` computed var | `String(localized:)` |
| `"DualVideo needs camera, microphone…"` | `blockedMessage` default case | `String(localized:)` |

**`UnsupportedDeviceView.swift`**

| String | Location | API Needed |
|--------|----------|------------|
| `"Dual-Camera Recording Unavailable"` | `Text` | Implicit (LocalizedStringKey) |
| `"DualVideo requires an iPhone with an A12 Bionic chip…"` | `Text` | Implicit (LocalizedStringKey) |

**`CameraContentView.swift`**

| String | Location | API Needed |
|--------|----------|------------|
| `"Saved to Photos"` | `Text` | Implicit (LocalizedStringKey) |
| `"Open Settings"` | `Button` in alert | Implicit (LocalizedStringKey) |
| `"Dismiss"` | `Button` in alert | Implicit (LocalizedStringKey) |
| `"DualVideo doesn't have permission to save to Photos…"` | `Text` in alert | Implicit (LocalizedStringKey) |
| `"Could not save recording: \(msg)"` | `Text` in alert (interpolated) | `String(localized:)` with `\(msg)` substitution |
| `"Recording — \(formattedTime)"` | `.accessibilityLabel` | `String(localized:)` |

**`QualitySettingsSheet.swift`**

| String | Location | API Needed |
|--------|----------|------------|
| `"Video Quality"` | `Text` | Implicit (LocalizedStringKey) |
| `"Applies to both cameras"` | `Text` | Implicit (LocalizedStringKey) |
| `"Resolution"` | `Text` and `Picker` label | Implicit (LocalizedStringKey) |
| `"Frame Rate"` | `Text` and `Picker` label | Implicit (LocalizedStringKey) |
| `"Storage unavailable"` | `storageEstimate` computed var | `String(localized:)` |
| `"Low storage"` | `storageEstimate` computed var | `String(localized:)` |
| `"<1 min remaining"` | `storageEstimate` computed var | `String(localized:)` |
| `"~\(minutes) min remaining"` | `storageEstimate` (interpolated) | `String(localized:)` with plural variant |
| `"~\(minutes / 60) hr remaining"` | `storageEstimate` (interpolated) | `String(localized:)` |

**`Info.plist`** (via `InfoPlist.xcstrings`)

| Key | Current English Value |
|-----|-----------------------|
| `NSCameraUsageDescription` | `"DualVideo uses your back and front cameras simultaneously to record a picture-in-picture video."` |
| `NSMicrophoneUsageDescription` | `"DualVideo records audio alongside your dual-camera video."` |
| `NSPhotoLibraryAddUsageDescription` | `"DualVideo saves your recordings directly to your Photo Library."` |

**Picker option labels from model types**

`OutputResolution.rawValue` (e.g. `"720p"`, `"1080p"`, `"4K"`) and `FrameRatePreset.displayName` (e.g. `"30 fps"`, `"60 fps"`) are used directly in `Text(r.rawValue)` and `Text(fps.displayName)`. These are technical abbreviations that are internationally understood and do not require translation. Leave them as-is.

---

### What NOT to Add

**No third-party localization services (Lokalise, Phrase, Crowdin).** These platforms exist for team-based, continuous translation workflows with multiple translators, translation memory, and CI integration. For a two-language personal project with a single developer writing both translations, they introduce unnecessary account setup, cost, and file format round-trips. Xcode's built-in String Catalog editor is sufficient.

**No in-app language picker.** The PROJECT.md requirement is explicit: system language detection only, no manual override. iOS handles this automatically via `Locale.current` — no `environmentObject`, `AppStorage`, or `@AppStorage("language")` hack needed.

**No `NSLocalizedString`.** It is the legacy Objective-C API. `String(localized:)` is the correct replacement for all non-view code.

**No `SwiftGen` or code-generation tools.** These generate type-safe string accessors to prevent typos in key names. They are valuable in large codebases with many contributors. With fewer than 30 strings and a single developer, String Catalog's compiler extraction (which warns on missing translations at build time) provides adequate safety.

**No `.strings` files.** Do not create `en.lproj/Localizable.strings` or `es.lproj/Localizable.strings`. The String Catalog (`.xcstrings`) approach manages all language variants in one file and renders the per-language file tree unnecessary.

---

### Integration with Existing MVVM Architecture

The MVVM architecture requires no structural changes for localization. String lookup is a pure presentation concern.

- **`CameraManager` / `RecordingManager` / `PermissionManager`** — these actors contain no user-facing strings. No changes needed.
- **`AppState`** — no localization-related state needed; system locale is read automatically by SwiftUI.
- **SwiftUI views** — implicit `LocalizedStringKey` resolution handles all `Text(literal)`, `Button(literal)` cases without code change. Only computed `String` properties (4 locations) require switching to `String(localized:)`.
- **`@Observable` pattern** — unaffected; localization resolution happens at render time, not at model layer.

The localization work is entirely additive: add two catalog files, update four computed string properties, register Spanish in project settings, and supply translations.

---

### Runtime Behavior

**Language selection:** iOS reads `[NSLocale preferredLanguages]` at app launch and resolves the best-match locale from the app's supported languages. With `en` and `es` registered, an iPhone set to Spanish will display Spanish strings; any other language falls back to English (the development region). No app code is involved in this resolution.

**Dynamic language change:** If the user changes device language while the app is running, iOS terminates and relaunches the app. SwiftUI views rebuild with the new locale. No reactive language-change handling is needed.

**Format locale sensitivity:** `Text` with `Date` and `Number` format arguments automatically uses `Locale.current` for number separators, date order, and similar formatting. No additional configuration needed.

---

### Sources

- Apple Developer Documentation — Localizing and varying text with a string catalog: https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog
- Apple Developer Documentation — Adding support for languages and regions: https://developer.apple.com/documentation/xcode/adding-support-for-languages-and-regions
- Apple Developer Documentation — Preparing views for localization (SwiftUI): https://developer.apple.com/documentation/SwiftUI/Preparing-views-for-localization
- Apple Developer Documentation — LocalizedStringKey: https://developer.apple.com/documentation/swiftui/localizedstringkey
- Jacob Bartlett — Localisation in Xcode 15 (String Catalog setup steps): https://blog.jacobstechtavern.com/p/localisation-in-xcode-15
- Tanaschita — Understanding localization with LocalizedStringKey in SwiftUI: https://tanaschita.com/swiftui-localization/
- SimpleLocalize — iOS localization 2026 guide (.strings vs .xcstrings): https://simplelocalize.io/blog/posts/manage-ios-translation-files/

---

## Prior Milestones

---

## v1.1 Addendum: 4K Detection and Recording

This section supersedes any v1 claims about resolution limits. All v1 stack decisions remain valid; the sections below document what changes or is added for 4K support.

### What Changes for 4K

| Component | v1 State | v1.1 Change | Why |
|-----------|----------|-------------|-----|
| `OutputResolution` enum | `.hd720p`, `.hd1080p` | Add `.uhd4K` | New resolution case required |
| `VideoQualitySettings` | Default `.hd1080p` | No default change | 4K is hardware-gated, not default |
| `MovieRecorder` codec | `AVVideoCodecType.h264` | Use HEVC for 4K, H.264 for ≤1080p | H.264 encoder cannot sustain 4K30 on A-series within practical bitrate |
| `MovieRecorder` bitrate | Not set (uses encoder default for H.264) | Explicit `AVVideoAverageBitRateKey` for HEVC 4K | Default HEVC encoding is too conservative at 4K |
| `PiPCompositor` output dimensions | `1080×1920` (portrait) | Set to `2160×3840` when 4K selected | Buffer pool and CI render target must match output |
| `CameraManager.applyFormat` | Matches on `landscapeWidth == 1920` | Matches on `landscapeWidth == 3840` for 4K | Existing filter pattern extends naturally |
| 4K capability detection | Not present | New function: enumerate back camera formats, find 4K `isMultiCamSupported == true` | Gate UI option on hardware capability |

### 4K Capability Detection

**API to use:** `AVCaptureDevice.formats` + `AVCaptureDeviceFormat.isMultiCamSupported` + `CMVideoFormatDescriptionGetDimensions`

**The correct detection pattern:**

```swift
func deviceSupports4KMultiCam(for device: AVCaptureDevice) -> Bool {
    return device.formats.contains { fmt in
        guard fmt.isMultiCamSupported else { return false }
        let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        return dims.width == 3840
    }
}
```

**Where to call it:** In `CameraManager.configureAndStart()` after `backDevice` is assigned, before `commitConfiguration()`. Publish a `Bool` observable property (e.g., `supports4K`) to `@Observable CameraManager`. `QualitySettingsSheet` reads this property to conditionally show the 4K option.
