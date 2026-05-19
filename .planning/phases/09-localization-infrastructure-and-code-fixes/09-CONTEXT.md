# Phase 9: Localization Infrastructure and Code Fixes - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Configure Xcode for Spanish + English localization, create `Localizable.xcstrings` and `InfoPlist.xcstrings` String Catalogs with all UI strings cataloged, fix two computed `String` properties so they appear in the catalog and localize correctly, and mark technical labels explicitly verbatim.

This phase does NOT add Spanish translations — that is Phase 10. Phase 9 delivers a complete, warning-free English catalog that Phase 10 can fill in.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation decisions are delegated to Claude. User's direction: "Do whatever you consider to make the app available to support Spanish & English." The decisions below are Claude's chosen approach with rationale.

### String Key Naming Convention
- **D-01:** Use **verbatim English keys** (Xcode default) — key = the English string literal (e.g., key `"Video Quality"` for `Text("Video Quality")`).
- Rationale: `SWIFT_EMIT_LOC_STRINGS = YES` auto-extraction uses verbatim keys natively. Semantic dot-notation keys require manual key assignment on every `Text()` call — more work, more error-prone, and no benefit for a 2-language personal app.

### Xcode Project Configuration
- **D-02:** Add `es` to `knownRegions` in `project.pbxproj` (currently only `en` and `Base`).
- **D-03:** `SWIFT_EMIT_LOC_STRINGS = YES` is already set for the main target (Debug + Release) — **no change needed**. The test target has `NO` — leave it (tests don't need loc strings).

### String Catalog Files
- **D-04:** Create `Localizable.xcstrings` in `DualVideo/App/` — all UI strings from `Text("literal")` and `Button("literal")` call sites.
- **D-05:** Create `InfoPlist.xcstrings` in `DualVideo/App/` — the three permission usage descriptions currently hardcoded in `Info.plist` (NSCameraUsageDescription, NSMicrophoneUsageDescription, NSPhotoLibraryAddUsageDescription).
- **D-06:** Both files use the standard xcstrings JSON format (Xcode 15+ String Catalog format).

### blockedMessage Fix (RootView.swift:86)
- **D-07:** Convert to **4 separate `String(localized:)` calls**, one per switch branch, each with a distinct verbatim English key and a `comment:` describing context for translators.
  - e.g., `String(localized: "DualVideo needs camera access to record video. Please enable Camera access in Settings.", comment: "Shown when camera permission is denied")`
- Rationale: Each message is a completely different sentence. A shared template with substitution would produce awkward Spanish translations. Separate keys give Phase 10 full per-message control.

### storageEstimate Fix (QualitySettingsSheet.swift:88)
- **D-08:** Convert to **`String(localized:)` with `String.LocalizationValue` interpolation** using the modern `\(count, specifier: "%lld")` form for the plural-sensitive variant.
  - `"Storage unavailable"` → separate key
  - `"Low storage"` → separate key
  - `"<1 min remaining"` → separate key
  - `"~\(minutes) min remaining"` → key with count substitution so Phase 10 can add `one`/`other` plural variants
  - `"~\(minutes / 60) hr remaining"` → key with count substitution
- Rationale: Using `String(localized:)` with interpolation creates a catalog entry with a substitution slot; Phase 10 adds Spanish plural variants without restructuring the Swift code.

### Technical Labels — Text(verbatim:) Scope
- **D-09:** Apply `Text(verbatim:)` explicitly to:
  - Resolution picker items: `Text(verbatim: r.rawValue)` — values "720p", "1080p", "4K"
  - Frame rate picker items: `Text(verbatim: fps.displayName)` — values "30 FPS", "60 FPS", "120 FPS"
  - Elapsed timer: `Text(verbatim: formattedTime)` in `RecordingStatusOverlay`
- Note: These already use the `String` init (verbatim by behavior), but explicit `Text(verbatim:)` makes intent unmistakable and prevents future regression if a variable type changes to `LocalizedStringKey`.
- **D-10:** `Picker("Resolution", ...)` and `Picker("Frame Rate", ...)` label arguments ARE localizable (they affect accessibility) — leave as localized `Text("Resolution")` / `Text("Frame Rate")`.

### Info.plist Handling
- **D-11:** Keep existing English strings in `Info.plist` as-is. Add `InfoPlist.xcstrings` alongside it — iOS uses the xcstrings file to override for Spanish, falls back to `Info.plist` for English. No need to remove permission strings from `Info.plist`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §v1.4 — L10N-02 through L10N-08 (the full set of Phase 9 requirements)

### Source Files to Modify
- `DualVideo/Features/Root/RootView.swift` — `blockedMessage` computed property (line ~86)
- `DualVideo/Features/Recording/UI/QualitySettingsSheet.swift` — `storageEstimate` computed property (line ~88), picker `Text()` calls (lines 40, 60)
- `DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift` — `Text(formattedTime)` (line ~26)
- `DualVideo/App/Info.plist` — English permission strings (reference only, not modified)
- `DualVideo.xcodeproj/project.pbxproj` — `knownRegions` array (add `es`)

### New Files to Create
- `DualVideo/App/Localizable.xcstrings` — main string catalog
- `DualVideo/App/InfoPlist.xcstrings` — permission description catalog

### Apple Documentation Patterns
- xcstrings format: JSON with `sourceLanguage`, `strings` dict, `localizations` per language
- `String(localized:comment:)` — modern Swift localization API (Swift 5.7+)
- `String(localized:)` with `String.LocalizationValue` interpolation for substitution/plural slots
- `SWIFT_EMIT_LOC_STRINGS = YES` causes build to auto-populate catalog entries from `Text("literal")` and `Button("literal")` call sites

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DualVideo/App/Info.plist` — already has all 3 permission descriptions in English; copy verbatim as `defaultValue` into `InfoPlist.xcstrings`
- `SWIFT_EMIT_LOC_STRINGS = YES` already configured (no change needed) — build will auto-populate catalog from `Text("literal")` call sites on first build after catalog creation

### Established Patterns
- Swift 6.0 is the language version in use — `String(localized:)` API is fully available
- `VideoQualitySettings` / `FrameRatePreset` — enums with `rawValue` and `displayName`; picker items come from these
- `RecordingStatusOverlay.formattedTime` — `private var formattedTime: String` computed via `String(format: "%02d:%02d", ...)` — already a `String` type so `Text(formattedTime)` is already verbatim-equivalent

### Integration Points
- `blockedMessage` is consumed as `Text(blockedMessage)` in `RootView.swift` — changing the property to use `String(localized:)` internally requires no change to the call site
- `storageEstimate` is consumed as `Text(storageEstimate)` in `QualitySettingsSheet.swift` — same pattern
- `knownRegions` modification is a text edit to `project.pbxproj`; adding `es,` to the array is sufficient
- Both new `.xcstrings` files must be added to the Xcode project's file reference list and the main target's resource build phase

</code_context>

<specifics>
## Specific Ideas

No specific design references — standard Apple xcstrings approach throughout.

Phase 9 success = zero "missing translation" warnings for English in Xcode after catalog creation and one build. Phase 10 then fills Spanish.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 09-localization-infrastructure-and-code-fixes*
*Context gathered: 2026-05-19*
