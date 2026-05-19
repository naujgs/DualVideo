# Pitfalls Research — DualVideo v1.4 Localization

**Researched:** 2026-05-19
**Scope:** Adding Spanish + English localization to an existing SwiftUI MVVM app with zero prior localization infrastructure.
**Architecture:** MVVM with `@Observable` ViewModels, SwiftUI views, iOS 18.0+ minimum, Xcode String Catalogs (.xcstrings).

---

## Critical Pitfalls

### 1. Computed `String` Properties in the View Layer Bypass Localization Entirely

**What goes wrong:**
SwiftUI's `Text` view has two distinct initializers: one that accepts a `String` (displays as-is, no lookup) and one that accepts a `String` literal (implicitly converts to `LocalizedStringKey` and performs a bundle lookup). The distinction is compile-time: only string *literals* trigger localization. Any string that passes through a variable — including the result of a computed property — is treated as verbatim text.

This app has three computed `String` properties that return user-visible text:
- `QualitySettingsSheet.storageEstimate` — returns strings like `"~14 min remaining"`, `"Low storage"`, `"Storage unavailable"`, `"<1 min remaining"`, `"~2 hr remaining"`.
- `RootView.PermissionsBlockedView.blockedMessage` — returns three distinct permission-denied explanations via a `switch`.
- `RootView.checkCapabilityAndPermissions()` — passes `"unknown"` as a literal into `.permissionsBlocked(which:)` which then routes to `blockedMessage`.

All of these currently reach `Text(blockedMessage)` and `Text(storageEstimate)` as plain `String` variables. Even after adding a String Catalog with Spanish translations, these strings will remain in English at runtime.

**Why it happens:**
SwiftUI resolves the initializer overload at compile time based on whether the argument is a literal. A computed property that returns `String` resolves to `Text(_ content: String)` — no localization lookup — regardless of what is in the String Catalog.

**Consequences:**
The three computed properties cover some of the most user-visible error and status text in the entire app. The quality sheet storage estimate, every permission-denied explanation, and the "unknown" fallback will appear in English on Spanish-language devices even if every other string is correctly localized.

**Prevention:**
Convert each computed property to return `LocalizedStringResource` (iOS 16+) or use `String(localized:)` with a key at each return site. For `storageEstimate`, all five return values must each become a `String(localized:)` call with a unique key. For `blockedMessage`, each `switch` branch must use `String(localized:)`.

Example fix for `storageEstimate`:
```swift
private var storageEstimate: String {
    guard bitrateBytesPerSec > 0, freeBytes > 0 else {
        return String(localized: "storage.unavailable", defaultValue: "Storage unavailable")
    }
    if freeBytes < 1_000_000_000 {
        return String(localized: "storage.low", defaultValue: "Low storage")
    }
    let minutes = Int(freeBytes / bitrateBytesPerSec) / 60
    if minutes == 0 { return String(localized: "storage.less-than-one-minute", defaultValue: "<1 min remaining") }
    if minutes < 60 { return String(localized: "storage.minutes \(minutes)", defaultValue: "~\(minutes) min remaining") }
    return String(localized: "storage.hours \(minutes / 60)", defaultValue: "~\(minutes / 60) hr remaining")
}
```

**Detection:**
Enable `-NSShowNonLocalizedStrings YES` in the Xcode scheme's Launch Arguments. Any string returned from a variable that has no matching catalog entry will print a console warning. Run through all app screens in Spanish.

**Phase assignment:** Extraction phase (Phase 1 of the localization milestone). Fix before adding any translations — the architecture must be correct first.

---

### 2. String Interpolation in `Text` Views Uses `%@` for All Types — Format Mismatch Silently Breaks Keys

**What goes wrong:**
`ZoomIndicatorView` uses `Text(String(format: "%.1f×", zoomFactor))` — this bypasses localization entirely because `String(format:)` produces a `String`, not a `LocalizedStringKey`. The `×` multiplication sign and the format pattern `%.1f` are both baked in.

The deeper issue is that when you do use `Text("Zoom: \(factor)")` in SwiftUI with interpolation, Xcode's String Catalog extraction defaults the format specifier to `%@` for all interpolated values. If `factor` is a `Double`, the generated catalog entry uses `%@` but the runtime expects `%lf` for proper number formatting — this causes a type mismatch that silently renders the wrong output or uses the fallback string.

Additionally, `RecordingStatusOverlay.accessibilityLabel("Recording — \(formattedTime)")` is an interpolated string that will be extracted with a `%@` specifier. If the accessibility string changes for Spanish (different dash, different word order), the concatenation pattern prevents correct translation.

**Why it happens:**
SwiftUI string interpolation inside `LocalizedStringKey` extracts as `%@` regardless of the actual argument type. This is a known Xcode limitation. Numbers, dates, and times all get `%@` in the generated entry, which may be incorrect.

**Consequences:**
Zoom display (`2.5×`) in Spanish either fails to localize the surrounding text or renders incorrectly. Accessibility labels for VoiceOver users are not translated. Format specifier mismatches can cause the key to not match at runtime (the catalog entry and the runtime-generated key differ), so the string falls back to the English default silently.

**Prevention:**
- For `ZoomIndicatorView`: Use `Text("\(zoomFactor, specifier: "%.1f")×")` — the `specifier:` parameter generates the correct `%lf`-style catalog entry. The `×` sign is part of the key and can be changed per locale.
- For `RecordingStatusOverlay`: Use `Text("recording.label \(formattedTime)")` with a catalog entry that allows the translator to reorder — or use `String(localized: "recording.label \(formattedTime)")`.
- For any `accessibilityLabel` using string interpolation, use `String(localized:)` with explicit specifier syntax.

**Detection:**
After extraction, inspect the generated `.xcstrings` file in a text editor. Any interpolated value should show the correct format specifier (`%lf` for Double, `%lld` for Int, `%@` for String). A mismatch indicates the extraction used the wrong specifier.

**Phase assignment:** Extraction phase. Audit every interpolated string before creating catalog entries.

---

### 3. Xcode's Automatic String Extraction Misses Non-Literal Strings — False Confidence That the Catalog Is Complete

**What goes wrong:**
Xcode's "Export Localizations" and String Catalog auto-extraction only detect strings that are expressed as string literals in recognized patterns (`Text("literal")`, `String(localized: "literal")`, `NSLocalizedString("literal", comment:)`). This app has multiple strings that will not be extracted automatically:

- `QualitySettingsSheet.storageEstimate` — 5 return strings, all from computed branches.
- `RootView.PermissionsBlockedView.blockedMessage` — 4 return strings, all from switch branches.
- `FrameRatePreset.displayName` — `"30 FPS"`, `"60 FPS"`, `"120 FPS"` from switch cases.
- `OutputResolution.rawValue` — `"720p"`, `"1080p"`, `"4K"` used directly as display text in the Picker.
- `RecordButton.accessibilityLabel` — ternary with two String literals in a modifier (may extract, but verify).
- `TorchToggleButton.accessibilityLabel` — same ternary pattern.

If you build with the String Catalog present and all these strings are absent from it, the catalog will appear to have everything extractable, but Xcode will not warn you about the non-extractable ones. The app ships with Spanish UI text missing in exactly the places the user encounters errors and core controls.

**Why it happens:**
The Xcode extractor does a static analysis pass over the source. It cannot evaluate runtime values or follow function return paths through conditional branches. Strings inside `switch` statements returning `String` are invisible to it.

**Consequences:**
False confidence. Running `-NSShowNonLocalizedStrings YES` catches missing *lookups* but does not catch strings that were never registered. The `FrameRatePreset.displayName` values will appear in Picker controls in English regardless of locale.

**Prevention:**
1. Convert `FrameRatePreset.displayName` to use `String(localized:)` at each case.
2. Convert `OutputResolution.rawValue` — the `rawValue` is `"720p"` etc., which is likely fine as a technical label, but confirm with the translator whether these need localization.
3. Convert `storageEstimate` and `blockedMessage` as described in Pitfall 1.
4. After extraction, manually add any remaining keys that Xcode could not find (they will appear as `extractionState: "manual"` in the JSON).
5. Do a manual text search for every hardcoded UI string using the pattern `grep -rn '"[^"]' Sources/ --include="*.swift"` filtered to non-logger strings.

**Phase assignment:** Extraction phase (before any translation work begins).

---

### 4. `InfoPlist.strings` Is a Separate File — Permission Prompts Stay in English Without It

**What goes wrong:**
DualVideo requests camera, microphone, and Photo Library permissions. The usage description strings (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription`) live in `Info.plist` — not in `Localizable.strings` or the String Catalog. Adding Spanish translations to the main catalog does not affect the permission prompt text the OS shows.

The permission prompt is displayed by the OS using the value from `InfoPlist.strings` for the device's current language. If no `InfoPlist.strings` file exists, the OS falls back to the raw `Info.plist` string (English). A Spanish-language user sees English text in the permission dialog, which is the first and highest-stakes interaction in the app.

**Why it happens:**
`Info.plist` keys are localized through a separate file named exactly `InfoPlist.strings` (case-sensitive). This file is entirely separate from the String Catalog pipeline. It does not appear in the catalog, does not get extracted by Xcode's export, and is easy to forget entirely.

**Consequences:**
Permission dialogs appear in English on all non-English devices. This is the first text a new user sees. It may cause the user to deny permission because the prompt is unclear in their language.

**Prevention:**
Create `InfoPlist.strings` (separate from `Localizable.strings`) with localized versions of all three permission keys:
```
"NSCameraUsageDescription" = "DualVideo necesita acceso a la cámara para grabar vídeo con ambas cámaras.";
"NSMicrophoneUsageDescription" = "DualVideo necesita acceso al micrófono para grabar audio.";
"NSPhotoLibraryAddUsageDescription" = "DualVideo necesita acceso a Fotos para guardar las grabaciones.";
```

Also add `CFBundleDisplayName` to `InfoPlist.strings` if you want the app name to appear localized on the home screen.

**Detection:**
Change the test device's language to Spanish, reinstall the app, and trigger each permission prompt. If the dialog shows English text, the `InfoPlist.strings` file is missing or not correctly linked.

**Phase assignment:** Extraction phase, treated as a separate deliverable from the main catalog. Do not ship Spanish support without this file.

---

## Moderate Pitfalls

### 5. `accessibilityLabel` Ternary Strings Are Only Partially Extracted

**What goes wrong:**
`RecordButton` and `TorchToggleButton` both use ternary operators inside `.accessibilityLabel()`:
```swift
.accessibilityLabel(isRecording ? "Stop Recording" : "Start Recording")
.accessibilityLabel(isTorchOn ? "Turn off torch" : "Turn on torch")
```

Xcode's extractor may or may not pick up both branches of a ternary inside a view modifier. Even if it extracts both, the ternary pattern in a modifier is more fragile than `Text("key")`. If only one branch is extracted, VoiceOver in Spanish will speak a mix of Spanish (extracted branch) and English (missed branch).

**Prevention:**
Explicitly convert to `String(localized:)` for both branches:
```swift
.accessibilityLabel(isRecording
    ? String(localized: "button.stop-recording", defaultValue: "Stop Recording")
    : String(localized: "button.start-recording", defaultValue: "Start Recording"))
```
This guarantees extraction and correct runtime lookup regardless of Xcode version.

**Phase assignment:** Extraction phase. Low effort — two files, four strings.

---

### 6. Pluralization in Storage Estimate Breaks for Exact-One Cases

**What goes wrong:**
`storageEstimate` produces `"~\(minutes) min remaining"` and `"~\(minutes / 60) hr remaining"`. In English, "1 min remaining" and "14 min remaining" happen to use the same form. In Spanish, the distinction between singular (`minuto`) and plural (`minutos`) must be reflected. The current pattern `~\(minutes) min remaining` cannot express `~1 minuto restante` vs `~14 minutos restantes`.

Spanish plural rules are: `one` (exactly 1) and `other` (everything else) — the same two categories as English, but the word forms change. If the translated string is `"~%lld min restantes"`, it will be grammatically wrong for `~1 minuto`.

**Prevention:**
Use String Catalog's built-in plural support. In the catalog editor, right-click the key and choose "Vary by Plural." Provide two forms per language:
- `one`: `"~1 minuto restante"`
- `other`: `"~%lld minutos restantes"`

The format specifier must be `%lld` for `Int`. This requires restructuring `storageEstimate` to use `String(localized:)` with the count as the interpolated value, not building the string through concatenation.

**Phase assignment:** Translation phase. The plural structure must be set up in the catalog during extraction, even if the Spanish forms are filled in later.

---

### 7. `ProgressView` Label Strings Are Easy to Miss

**What goes wrong:**
`RootView` contains:
```swift
ProgressView("Starting…")
ProgressView("Requesting permissions…")
```

These are string literals passed to `ProgressView`, not `Text`. Xcode's extractor should detect them because `ProgressView.init(_ titleKey: LocalizedStringKey)` accepts a `LocalizedStringKey` — so these likely extract automatically. However, the ellipsis character `…` (U+2026, `HORIZONTAL ELLIPSIS`) must be preserved exactly in the catalog and in Spanish translations. If a translator uses three period characters `...` instead of `…`, the runtime key lookup will fail (key mismatch), and the English fallback displays.

**Prevention:**
When reviewing catalog entries and translations, verify that the `…` character is `U+2026` and not three ASCII periods. Add a translator note in the `comment` field of each key.

**Phase assignment:** Translation review phase.

---

### 8. Hardcoded `"unknown"` String Passed Through Enum Leaks into User-Facing Text

**What goes wrong:**
In `RootView`:
```swift
appState.route = .permissionsBlocked(which: "unknown")
```
This string propagates into `PermissionsBlockedView.blockedMessage`'s `default:` branch, which produces:
```
"DualVideo needs camera, microphone, and Photo Library access to function. Please enable all permissions in Settings."
```
The `"unknown"` literal is a routing key, not user-facing, but the rendered message is user-facing and is in a non-extractable computed property (see Pitfall 1 and 3). If someone attempts to localize `"unknown"` as a display string, it would be incorrect. The real risk is that the fallback message is simply forgotten because the "unknown" path seems like a developer path.

**Prevention:**
Treat the `default:` branch of `blockedMessage` as user-facing. Use `String(localized:)` like all other branches. The routing key `"unknown"` should remain an opaque internal value; never display it directly.

**Phase assignment:** Extraction phase.

---

### 9. Testing Localization in Simulator Requires Scheme Configuration — Physical Device Behavior May Differ

**What goes wrong:**
Localization can be tested in Simulator by changing the scheme's Application Language to Spanish. However, DualVideo requires a physical device for all camera features (Simulator has no camera). This means localization testing cannot be fully isolated — every localization check requires the test device (iPhone XR or iPhone 17 Pro Max) to have its system language set to Spanish.

Switching system language on a device is disruptive (all apps restart, keyboard changes). Developers tend to skip thorough language switching and test only in Simulator — missing any string that only appears during actual recording, save failures, or permission prompts.

**Consequences:**
Strings in `RecordingStatusOverlay` (appears only during active recording), the "Saved to Photos" toast, and the "Save Failed" alert are only exercised on a physical device in recording mode. They are the most likely to be missed in localization testing.

**Prevention:**
Add `-NSShowNonLocalizedStrings YES` and `-AppleLanguages (es)` as Xcode scheme launch arguments. This forces Spanish without changing device system language. Test every screen state: idle, recording, save success, save failure, permission denied, unsupported device. Create a testing checklist covering all screens and states.

**Phase assignment:** Validation phase. This is a process/testing pitfall, not a code pitfall — put it in the test plan.

---

## Minor Pitfalls

### 10. `OutputResolution.rawValue` Used as Picker Display Text — Technical Labels May Not Need Localization, But Must Be Decided Explicitly

**What goes wrong:**
`OutputResolution` has raw values `"720p"`, `"1080p"`, `"4K"`. These are used directly in the Picker: `Text(r.rawValue).tag(r)`. These are technical labels that are internationally recognized — `"4K"` means the same in Spanish as in English. However, treating `rawValue` as display text couples the storage representation to the display format. If a translator ever needs to change the display (e.g., `"1080p HD"` in Spanish), the `rawValue` (used as a `Codable` storage key) would also change, breaking stored user preferences.

**Prevention:**
Separate the display name from the `rawValue`. Add a `displayName` computed property (like `FrameRatePreset.displayName`) that returns the localized string. Keep `rawValue` as the stable storage key. For this milestone, the display name can be the same as the raw value (`"720p"` etc.) but the architectural separation prevents future coupling issues.

**Phase assignment:** Extraction phase. Low effort architectural improvement.

---

### 11. `String.Catalog` Extraction Happens at Build Time — Strings Added After Initial Build Are Not Auto-Synced

**What goes wrong:**
String Catalog extraction runs as part of the build. If you add a new hardcoded string after creating the catalog and do not rebuild, the catalog will not contain the new key. This is easy to miss during iterative development — a string added to fix a bug or add a feature is silently absent from the catalog. The String Catalog editor in Xcode marks catalog entries as `New` or `Stale`, but only after a build.

**Prevention:**
After any code change that adds or modifies a user-facing string, do a full build (`Cmd+B`) and immediately inspect the catalog for new or stale entries. Make this part of the PR review checklist: "Does this PR add/change UI strings? If yes, rebuild and verify catalog is updated."

**Phase assignment:** Ongoing development discipline. Especially relevant in the translation phase when new strings might be added to fix copy.

---

### 12. `"Saved to Photos"` Toast and `"Save Failed"` Alert Are Fire-and-Forget Strings That Only Appear in Recording Mode

**What goes wrong:**
`CameraContentView` shows a `"Saved to Photos"` toast and a `"Save Failed"` alert with the message `"DualVideo doesn't have permission to save to Photos. Open Settings to allow access."` and `"Could not save recording: \(msg)"`. These only appear after a successful or failed recording save. The `\(msg)` in the failure case is a dynamic error message from the system (an `AVFoundation` or `Photos` framework error).

Two problems:
1. The static strings (`"Saved to Photos"`, `"Save Failed"`, `"Open Settings"`, `"Dismiss"`, `"DualVideo doesn't have permission..."`) are extractable string literals but may be missed in manual audits because they only appear after a full recording cycle.
2. The `\(msg)` interpolated system error string is passed directly into `Text`. This is an `AVFoundation` error's `localizedDescription` — which iOS already localizes into the device language. Wrapping it in a `Text` that goes through the String Catalog would be incorrect. It should be passed through as a verbatim string: `Text(verbatim: msg)` or displayed as an auxiliary `Text(msg)` that bypasses catalog lookup.

**Prevention:**
- Ensure all static strings in the alert are in the catalog with Spanish translations.
- For `msg` (the dynamic system error), use `Text(verbatim: msg)` to explicitly opt out of catalog lookup. The system-provided `localizedDescription` is already localized by iOS — do not re-wrap it.
- For the `"Open Settings"` / `"Dismiss"` button labels, consider using system-provided strings via `Button(role:)` patterns or verify these are translated correctly in the catalog.

**Phase assignment:** Extraction phase (static strings), validation phase (verify system error strings display correctly in Spanish).

---

## Phase-Specific Warning Summary

| Phase | Topic | Pitfall | Mitigation |
|-------|-------|---------|------------|
| Extraction | Computed `String` properties | Pitfall 1: ViewModel/view-layer computed strings bypass lookup | Convert to `String(localized:)` at each return site |
| Extraction | String interpolation specifiers | Pitfall 2: `%@` used for all types, key mismatch | Use `specifier:` parameter, audit `.xcstrings` JSON |
| Extraction | Xcode auto-extraction gaps | Pitfall 3: switch/ternary branches not extracted | Manual grep + `extractionState: "manual"` audit |
| Extraction | `InfoPlist.strings` | Pitfall 4: permission prompts stay English | Create separate `InfoPlist.strings` for each locale |
| Extraction | Accessibility labels | Pitfall 5: ternary branches partially missed | Explicit `String(localized:)` for both branches |
| Extraction | `OutputResolution.rawValue` | Pitfall 10: display text coupled to storage key | Add `displayName` property, decouple from `rawValue` |
| Extraction | `"unknown"` routing string | Pitfall 8: fallback message not extracted | Treat `default:` branch as user-facing |
| Extraction | New strings during development | Pitfall 11: catalog not auto-synced | Rebuild after every string change |
| Translation | Pluralization | Pitfall 6: singular/plural forms for minutes/hours | Use catalog "Vary by Plural," `%lld` specifier |
| Translation | `…` character | Pitfall 7: ellipsis character must be U+2026 | Add translator note, verify in catalog JSON |
| Validation | Physical device testing | Pitfall 9: recording-mode strings only testable on device | Scheme launch args `-AppleLanguages (es)`, full recording cycle test |
| Validation | Save toast and alert | Pitfall 12: fire-and-forget strings in recording flow | Full recording + save test in Spanish on physical device |

---

## Sources

- [Understanding localization with LocalizedStringKey in SwiftUI — tanaschita.com](https://tanaschita.com/swiftui-localization/)
- [Localizing Dynamic Strings with String Catalogs in Swift — codebit-inc.com](https://codebit-inc.com/blog/localizing-dynamic-strings-swift/)
- [Xcode String Catalogs: Compile-Time Safety, Code Completion, and RTL Gotchas — Atomic Robot](https://atomicrobot.com/blog/lost-in-translation-understanding-ios-localization/)
- [The Missing String Catalogs FAQ for Localization in Xcode 15 — fline.dev](https://www.fline.dev/the-missing-string-catalogs-faq-for-xcode-15/)
- [Finding Non-localized Strings — Use Your Loaf](https://useyourloaf.com/blog/finding-non-localized-strings/)
- [How to localize plurals with Localizable.stringsdict files in iOS — tanaschita.com](https://tanaschita.com/ios-plurals-localization-strictdict/)
- [How to use String Catalogs for pluralization in Swift — tanaschita.com](https://tanaschita.com/20230710-pluralization-with-string-catalogs/)
- [Localizing permissions in iOS app — Medium](https://medium.com/@axmadxojaibrohimov/localizing-permissions-in-ios-app-ebe4ef72f3a0)
- [Localizable.strings guide — objc.io](https://www.objc.io/issues/9-strings/string-localization/)
- [Preparing views for localization — Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/Preparing-views-for-localization)
- [Discover String Catalogs — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10155/)
