---
phase: 09-localization-infrastructure-and-code-fixes
reviewed: 2026-05-19T21:42:39Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - DualVideo.xcodeproj/project.pbxproj
  - DualVideo/App/InfoPlist.xcstrings
  - DualVideo/App/Localizable.xcstrings
  - DualVideo/Features/Recording/UI/QualitySettingsSheet.swift
  - DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift
  - DualVideo/Features/Root/RootView.swift
findings:
  critical: 0
  warning: 2
  info: 1
  total: 3
status: issues_found
---

# Phase 09: Code Review Report

**Reviewed:** 2026-05-19T21:42:39Z
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Reviewed the localization infrastructure (xcstrings catalogs, project.pbxproj) and three Swift UI files that consume it. The project structure is sound: both `.xcstrings` files are correctly registered in the Resources build phase, `SWIFT_EMIT_LOC_STRINGS = YES` is set on the main target only (test target correctly uses `NO`), and `knownRegions` declares `en`, `es`, and `Base`. InfoPlist.xcstrings has complete, well-formed English translations for all three permission keys.

One localization correctness bug was found in `RecordingStatusOverlay.swift`: the VoiceOver label uses plain Swift string interpolation inside `String(localized:)`, which produces a runtime-unique lookup key that can never match the catalog entry, causing silent English fallback on non-English locales. A second warning covers comment string mismatches in `QualitySettingsSheet.swift` that risk catalog drift under `SWIFT_EMIT_LOC_STRINGS`. `RootView.swift` is clean.

## Warnings

### WR-01: VoiceOver accessibility label key never matches catalog entry — localization silently fails at runtime

**File:** `DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift:34-39`

**Issue:** The accessibility label uses `String(localized:)` with plain Swift string interpolation:

```swift
String(
    localized: "Recording \u{2014} \(formattedTime)",
    comment: "..."
)
```

Plain interpolation (`\(formattedTime)` without a `specifier:` argument) bakes the current runtime value into the lookup key. The resulting key is `"Recording — 00:01"`, `"Recording — 01:23"`, etc. — a unique key every second. The catalog entry `"Recording — %@"` is never matched. On a Spanish-locale device VoiceOver always speaks the English literal fallback, defeating the localization.

The `specifier:` argument to string interpolation is what signals to `String(localized:)` that the interpolation site is a format argument, causing the runtime to look up by the template key `"Recording — %@"` and substitute the argument after lookup.

**Fix:**
```swift
// Replace (lines 34-39):
.accessibilityLabel(
    String(
        localized: "Recording \u{2014} \(formattedTime)",
        comment: "VoiceOver label for the recording status indicator; formattedTime is MM:SS elapsed time"
    )
)

// With:
.accessibilityLabel(
    String(
        localized: "Recording \u{2014} \(formattedTime, specifier: "%@")",
        comment: "VoiceOver label for the recording status indicator; formattedTime is MM:SS elapsed time"
    )
)
```

This matches the catalog key `"Recording — %@"` and correctly substitutes `formattedTime` at the format argument site after the localized template is retrieved.

---

### WR-02: `storageEstimate` comment strings diverge from catalog entries — risk of duplicate keys under string extraction

**File:** `DualVideo/Features/Recording/UI/QualitySettingsSheet.swift:98-110`

**Issue:** With `SWIFT_EMIT_LOC_STRINGS = YES`, Xcode's string extractor uses the `comment:` parameter to correlate source-code `String(localized:)` calls to catalog entries. Three calls in `storageEstimate` have comment text that does not match the catalog `comment` field, which can cause the extractor to treat them as new/different entries on subsequent builds, producing duplicate or orphaned catalog keys.

Mismatches:
- Line 99: source `"Shown when free storage cannot be determined"` vs catalog `"Shown when freeBytes cannot be determined"`
- Line 103: source `"Shown when device has less than 1 GB free storage"` vs catalog `"Shown when device has less than 1 GB free"`
- Line 109: source `"Shown when less than one minute of recording time remains"` vs catalog `"Shown when less than one minute of recording time is available"`

Note: the format-specifier calls on lines 113 and 117 (`\(count, specifier: "%lld")` and `\(hours, specifier: "%lld")`) are correct — the `specifier:` form produces template key lookup against `"~%lld min remaining"` and `"~%lld hr remaining"` as expected.

**Fix:** Align `comment:` strings in source to exactly match `Localizable.xcstrings`:
```swift
// Line 98-99:
return String(localized: "Storage unavailable",
              comment: "Shown when freeBytes cannot be determined")

// Lines 101-103:
return String(localized: "Low storage",
              comment: "Shown when device has less than 1 GB free")

// Lines 108-110:
return String(localized: "<1 min remaining",
              comment: "Shown when less than one minute of recording time is available")
```

---

## Info

### IN-01: All Spanish translations are empty placeholder stubs

**File:** `DualVideo/App/Localizable.xcstrings` (all `es` entries), `DualVideo/App/InfoPlist.xcstrings` (all `es` entries)

**Issue:** Every `es` entry in both catalogs has `"state": "needs_review"` and `"value": ""`. If the app is distributed with the `es` locale in the bundle (it will be, since `knownRegions` includes `es` in `project.pbxproj` line 329), iOS on a Spanish-language device will fall back to the English source string for all strings. This is expected scaffolding for a future translation pass, and the catalog comments note this is deferred to Phase 10. No action required before Phase 10, but confirm on a Spanish-locale device before shipping that iOS falls back gracefully and no blank strings appear.

---

_Reviewed: 2026-05-19T21:42:39Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
