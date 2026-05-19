---
phase: 09-localization-infrastructure-and-code-fixes
reviewed: 2026-05-19T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - DualVideo/App/Localizable.xcstrings
  - DualVideo/App/InfoPlist.xcstrings
  - DualVideo.xcodeproj/project.pbxproj
  - DualVideo/Features/Root/RootView.swift
  - DualVideo/Features/Recording/UI/QualitySettingsSheet.swift
  - DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift
findings:
  critical: 1
  warning: 3
  info: 2
  total: 6
status: issues_found
---

# Phase 9: Code Review Report

**Reviewed:** 2026-05-19
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

This phase adds xcstrings-based localization infrastructure (Localizable.xcstrings, InfoPlist.xcstrings), registers both files in project.pbxproj, and updates three Swift views (RootView, QualitySettingsSheet, RecordingStatusOverlay) to consume the new string catalog. The Xcode project wiring and Swift source changes are structurally sound. However, there is one critical defect in InfoPlist.xcstrings that will produce blank iOS permission prompts, three logic/correctness warnings in the Swift views, and two informational items.

---

## Critical Issues

### CR-01: InfoPlist.xcstrings missing English source values — permission prompts will be blank

**File:** `DualVideo/App/InfoPlist.xcstrings:4-39`

**Issue:** `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, and `NSPhotoLibraryAddUsageDescription` each have only a Spanish (`es`) placeholder entry with an empty value. There is no `en` localization block for any of them. When iOS builds the Info.plist from this xcstrings catalog for an English locale, it will find no string to substitute and the system permission alert will show a blank description. Apple may also reject the app during review for missing usage descriptions.

**Fix:** Add an `en` localization entry with `"state": "translated"` and the actual usage string for each key:

```json
"NSCameraUsageDescription" : {
  "comment" : "Shown in iOS permission prompt when app first requests camera access",
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "DualVideo needs access to your camera to record video from both cameras simultaneously."
      }
    },
    "es" : {
      "stringUnit" : {
        "state" : "needs_review",
        "value" : ""
      }
    }
  }
}
```

Apply the same pattern for `NSMicrophoneUsageDescription` and `NSPhotoLibraryAddUsageDescription`.

---

## Warnings

### WR-01: QualitySettingsSheet — "Storage unavailable" label is permanently hidden

**File:** `DualVideo/Features/Recording/UI/QualitySettingsSheet.swift:46`

**Issue:** The storage estimate label is gated with `if freeBytes > 0`, so when `volumeAvailableCapacityForImportantUsage` returns `nil` (sandboxed simulator, entitlement issue, or genuine API failure) and `freeBytes` stays at its initial value of `0`, the entire label is suppressed. The `storageEstimate` computed property correctly handles this case and returns `String(localized: "Storage unavailable", ...)`, but that code path is never reached because the guard prevents body evaluation.

**Fix:** Remove the `freeBytes > 0` guard, and instead always render the label after `onAppear` has fired. Use a separate `@State private var storageLoaded: Bool = false` flag, or conditionally display after a dedicated load flag is set:

```swift
// Replace:
if freeBytes > 0 {
    Text(storageEstimate)
        ...
}

// With:
if storageLoaded {
    Text(storageEstimate)
        ...
}
```

And in `onAppear`, always set `storageLoaded = true` after the query, regardless of whether the result is `nil` or a positive value. This ensures `"Storage unavailable"` is displayed when the API fails.

### WR-02: QualitySettingsSheet — dead guard branch (`bitrateBytesPerSec > 0`)

**File:** `DualVideo/Features/Recording/UI/QualitySettingsSheet.swift:95`

**Issue:** The guard `guard bitrateBytesPerSec > 0, freeBytes > 0 else { return "Storage unavailable" }` contains a dead branch. All three `switch` arms assign strictly positive constants (1_000_000, 2_000_000, 5_625_000), so `bitrateBytesPerSec` is never zero. The compound guard misleads readers into thinking a zero-bitrate code path exists and can trigger the fallback. Because `freeBytes > 0` is the only live condition, the intent is obscured.

**Fix:** Remove the dead condition from the guard:

```swift
// Replace:
guard bitrateBytesPerSec > 0, freeBytes > 0 else {
    return String(localized: "Storage unavailable", ...)
}

// With:
guard freeBytes > 0 else {
    return String(localized: "Storage unavailable", ...)
}
```

### WR-03: RecordingStatusOverlay — accessibility label is not localizable

**File:** `DualVideo/Features/Recording/UI/RecordingStatusOverlay.swift:34`

**Issue:** The accessibility label is set via a raw string interpolation:

```swift
.accessibilityLabel("Recording — \(formattedTime)")
```

This string is a plain Swift `String` literal, not a `LocalizedStringKey` or `String(localized:)` call. It will not be picked up by the string extraction tool and cannot be translated. VoiceOver users on non-English locales will always hear the English phrase "Recording".

**Fix:** Wrap the label in `String(localized:)` with a `comment` and add an entry to `Localizable.xcstrings`. The time component is locale-agnostic (MM:SS digits), so the label string can be:

```swift
.accessibilityLabel(
    String(
        localized: "Recording — \(formattedTime)",
        comment: "VoiceOver label for the recording status indicator; formattedTime is MM:SS elapsed time"
    )
)
```

Add a corresponding key `"Recording — %@"` (or the interpolation-based key form the Swift compiler generates) to `Localizable.xcstrings`.

---

## Info

### IN-01: Localizable.xcstrings — all Spanish values are empty scaffolding

**File:** `DualVideo/App/Localizable.xcstrings:14-19` (and all 20 `es` entries)

**Issue:** Every Spanish (`es`) entry has `"value": ""` and `"state": "needs_review"`. This is structurally valid xcstrings and iOS will fall back to the English string when a localization value is empty — however, the exact fallback behavior depends on the iOS version and whether the xcstrings entry is present at all. Testing on a Spanish-locale device before Phase 10 is complete is advisable to confirm that fallback works as expected and no blank strings appear.

**Fix:** No code change required before Phase 10. Confirm empirically that iOS falls back to the `en` value for `needs_review` entries with empty values. If blank strings appear in testing, temporarily remove the empty `es` entries until translations are ready.

### IN-02: RootView.swift — magic string `"unknown"` used as permission category sentinel

**File:** `DualVideo/Features/Recording/UI/RootView.swift:55`

**Issue:** The `.notDetermined` fallback passes the raw string `"unknown"` to `permissionsBlocked(which:)`:

```swift
appState.route = .permissionsBlocked(which: "unknown")
```

The `blockedMessage` switch in `PermissionsBlockedView` hits the `default` arm for any unrecognized value and shows the generic message. This works today, but if `PermissionManager` is ever changed to return a typed enum rather than a raw string, this sentinel is easy to miss and the coupling is invisible at the call site.

**Fix:** Define a constant or use a dedicated sentinel that documents the intent:

```swift
// Instead of:
appState.route = .permissionsBlocked(which: "unknown")

// Use a named constant:
private let unknownPermissionSentinel = "unknown"
appState.route = .permissionsBlocked(which: unknownPermissionSentinel)
```

Or better, refactor `AppRoute.permissionsBlocked(which:)` to accept a typed enum rather than `String`.

---

_Reviewed: 2026-05-19_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
