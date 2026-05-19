---
phase: 07-4k-capability-detection-and-conditional-ui
verified: 2026-05-19T00:00:00Z
status: human_needed
score: 4/4 must-haves verified
overrides_applied: 0
human_verification:
  - test: "On an iPhone XR (A12 Bionic): launch app, tap quality settings button, confirm 4K is NOT present in the resolution picker"
    expected: "Resolution picker shows only '720p' and '1080p' segments. No '4K' segment."
    why_human: "supports4K=false branch confirmed by code logic, but AVFoundation isMultiCamSupported behavior on A12 cannot be verified without the device."
  - test: "On a 4K-capable device (A15 Pro or newer): launch app, tap quality settings button after session starts, confirm 4K IS present"
    expected: "Resolution picker shows '720p', '1080p', and '4K' segments. Selecting 4K persists across sheet open/close."
    why_human: "detect4KCapability() correctness on target hardware requires physical device. A-series chip behavior cannot be simulated."
  - test: "On any device: open quality settings sheet, verify storage estimate label is visible and shows a non-empty string"
    expected: "A label like '~33 min remaining' or '~2 hr remaining' appears below the resolution picker. Changes when resolution is changed."
    why_human: "volumeAvailableCapacityForImportantUsageKey returns 0 on Simulator — requires real device to confirm freeBytes > 0 path."
  - test: "Simulate stale .uhd4K setting on non-4K device: set qualitySettings.resolution = .uhd4K in UserDefaults, launch on non-capable device, verify it silently becomes .hd1080p"
    expected: "No crash, no error alert. After session startup, qualitySettings.resolution is .hd1080p."
    why_human: "The .onChange fallback guard fires at runtime based on actual supports4K value from AVFoundation — requires device execution."
---

# Phase 7: 4K Capability Detection and Conditional UI Verification Report

**Phase Goal:** Users on capable hardware see 4K as a selectable resolution in the quality panel, and users on all other hardware see no 4K option at all.
**Verified:** 2026-05-19
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | On iPhone XR (A12), quality panel contains no 4K option and `CameraManager.supports4K` is false after session startup | ✓ VERIFIED (code) / ? HUMAN (device) | Picker filter `{ $0 != .uhd4K \|\| supports4K }` excludes uhd4K when supports4K=false. Initial value is `false` (CameraManager.swift:54). detect4KCapability() uses `isMultiCamSupported && dims.width == 3840` — returns false on non-4K hardware. |
| 2 | On a 4K-capable device, quality panel shows 4K as selectable resolution after session startup | ✓ VERIFIED (code) / ? HUMAN (device) | detect4KCapability() runs before session.startRunning() (CameraManager.swift:466-468). When has4K=true, dispatches to main (line 513). Picker filter passes .uhd4K through when supports4K=true. |
| 3 | Quality panel displays a live recording-time estimate that updates when user switches resolution | ✓ VERIFIED (code) / ? HUMAN (device) | `storageEstimate` computed property re-evaluates on @Binding resolution change. freeBytes loaded in .onAppear via volumeAvailableCapacityForImportantUsageKey. Label shown only when freeBytes > 0 — needs real device to confirm non-zero result. |
| 4 | A saved 4K quality setting on a non-4K device silently falls back to 1080p before session start | ✓ VERIFIED (code) | `.onChange(of: appState.cameraManager.supports4K)` guard at CameraContentView.swift:252-257 checks `!supports4K && resolution == .uhd4K` and writes .hd1080p + saves. |

**Score:** 4/4 truths verified (code logic confirmed; 4 items need device execution)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `DualVideo/Features/Recording/VideoQualitySettings.swift` | OutputResolution.uhd4K enum case | ✓ VERIFIED | `case uhd4K = "4K"` with width=2160, height=3840, landscapeWidth=3840 at lines 10-41 |
| `DualVideo/Features/Camera/CameraManager.swift` | supports4K observable property + detect4KCapability() | ✓ VERIFIED | `var supports4K: Bool = false` at line 54; full detect4KCapability() method at lines 491-516 |
| `DualVideoTests/UnitTests/VideoQualitySettingsTests.swift` | Tests for uhd4K case and Codable round-trip | ✓ VERIFIED | 7 new test cases present: uhd4KRawValue, uhd4KWidth, uhd4KHeight, uhd4KLandscapeWidth, allCasesCountIsThree, uhd4KRoundTrip, unknownResolutionRawValueFallsBackToDefault |
| `DualVideo/Features/Recording/UI/QualitySettingsSheet.swift` | supports4K param, filtered picker, storage estimate, .height(320) detent | ✓ VERIFIED | All 4 elements confirmed at lines 13, 37, 46-50, 68 |
| `DualVideo/Features/Camera/CameraContentView.swift` | supports4K call site + fallback .onChange guard | ✓ VERIFIED | `supports4K: appState.cameraManager.supports4K` at line 297; `.onChange` guard at lines 252-257 |
| `DualVideoTests/UnitTests/QualitySettingsSheetTests.swift` | QualitySettingsPickerFilterTests + StorageEstimateTests | ✓ VERIFIED | Both suites present with 3 + 6 test cases covering K4-02 and K4-05 logic |

### Key Link Verification

(gsd-tools key-link verifier reported "Source file not found" due to path resolution; verified manually from source.)

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `CameraManager.detect4KCapability()` | `CameraManager.supports4K` | `DispatchQueue.main.async` | ✓ WIRED | `self?.supports4K = has4K` at CameraManager.swift:513 |
| `CameraManager.configureAndStart()` | `detect4KCapability()` | direct call before `session.startRunning()` | ✓ WIRED | CameraManager.swift:466 calls `detect4KCapability()` immediately before `session.startRunning()` at line 468 |
| `CameraContentView QualitySettingsSheet call site` | `QualitySettingsSheet(supports4K:)` | `appState.cameraManager.supports4K` | ✓ WIRED | CameraContentView.swift:297 `supports4K: appState.cameraManager.supports4K` |
| `QualitySettingsSheet.storageEstimate` | `freeBytes @State + settings.resolution` | switch on resolution for bitrate constant | ✓ WIRED | QualitySettingsSheet.swift:88-101; switch covers all 3 cases with 8/16/45 Mbps constants |
| `CameraContentView .onChange(of: supports4K)` | `appState.qualitySettings.resolution` | downgrade guard + save() | ✓ WIRED | CameraContentView.swift:252-257 — guard fires on false + .uhd4K, writes .hd1080p + calls save() |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `QualitySettingsSheet.swift` | `freeBytes` | `.onAppear` → `URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])` | Real OS query (no stub return) | ✓ FLOWING (production path); returns 0 on Simulator |
| `QualitySettingsSheet.swift` | `storageEstimate` | Computed from `freeBytes` + `settings.resolution` | Derived from OS data | ✓ FLOWING |
| `CameraContentView.swift` | `supports4K` | `CameraManager.supports4K` (Observable) via `detect4KCapability()` → `isMultiCamSupported` AVFoundation query | Real AVFoundation format inspection | ✓ FLOWING |

### Behavioral Spot-Checks

Step 7b: SKIPPED — all key behaviors require a running iOS device session (AVFoundation, OS disk query). No runnable entry point testable without launching on hardware.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| K4-01 | Plan 01 | App determines at session startup whether the back camera supports 4K in MultiCam mode | ✓ SATISFIED | `detect4KCapability()` in CameraManager uses `isMultiCamSupported && dims.width == 3840` format filter; called after `commitConfiguration()` before `startRunning()` |
| K4-02 | Plan 01, Plan 02 | Quality settings panel shows 4K only on capable hardware; absent (not greyed) on others | ✓ SATISFIED | `OutputResolution.uhd4K` exists; QualitySettingsSheet uses `allCases.filter { $0 != .uhd4K \|\| supports4K }` — absence, not disabled |
| K4-05 | Plan 02 | Quality settings panel displays live estimate of available recording time | ✓ SATISFIED | `storageEstimate` computed property with `volumeAvailableCapacityForImportantUsageKey` query in `.onAppear`; bitrate constants 8/16/45 Mbps for 720p/1080p/4K |

No orphaned requirements. REQUIREMENTS.md maps K4-01, K4-02, K4-05 to Phase 7 and K4-03, K4-04 to Phase 8. All three Phase 7 requirements are satisfied.

### Anti-Patterns Found

No anti-patterns detected. grep for TODO, FIXME, HACK, placeholder, "not implemented" across all 6 modified files returned 0 matches.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | — |

### Human Verification Required

#### 1. Non-Capable Device: 4K Option Absent

**Test:** On an iPhone XR (A12 Bionic), launch the app, wait for session to start, tap the quality settings (gear/quality) button.
**Expected:** Resolution picker shows only two segments: "720p" and "1080p". No "4K" segment is visible.
**Why human:** `isMultiCamSupported` behavior on A12 for 3840-wide formats cannot be confirmed in Simulator. The code logic is correct but hardware response is the ground truth.

#### 2. Capable Device: 4K Option Present

**Test:** On an iPhone 15 Pro or newer (A17 Pro / A18 Pro), launch the app, wait for session to start (approximately 1 second), tap quality settings.
**Expected:** Resolution picker shows three segments: "720p", "1080p", "4K". Selecting "4K" persists after closing and reopening the sheet.
**Why human:** `detect4KCapability()` returns based on real AVFoundation format data. Only hardware execution confirms that A17 Pro/A18 Pro reports `isMultiCamSupported && width == 3840` for at least one format.

#### 3. Storage Estimate Label

**Test:** On any physical device with more than 1 GB free, open the quality settings sheet.
**Expected:** A storage estimate label appears below the resolution picker, e.g. "~33 min remaining" for 1080p with 4 GB free. Switching between resolutions updates the label immediately.
**Why human:** `volumeAvailableCapacityForImportantUsageKey` returns 0 on iOS Simulator, so `freeBytes > 0` is always false in Simulator, hiding the label. Real device required.

#### 4. Stale .uhd4K Setting Downgrade

**Test:** Using a debug build: set `UserDefaults.standard.set(jsonWith4K, forKey: "com.naujgs.DualVideo.videoQualitySettings")` where jsonWith4K encodes resolution="4K". Launch on a non-4K device. Observe quality settings sheet.
**Expected:** After session startup, quality settings show .hd1080p selected. No crash, no error dialog.
**Why human:** The `.onChange(of: supports4K)` guard fires only at runtime when AVFoundation session starts and `supports4K` transitions false→false (stays false, onChange fires on first value). Requires device execution to confirm no race condition.

### Gaps Summary

No gaps. All must-haves from both plans are verified at all four levels (exists, substantive, wired, data flowing). All 3 requirement IDs (K4-01, K4-02, K4-05) are satisfied. All 6 commits from both summaries exist in git history. No anti-patterns found.

Human verification is required for 4 device-specific behaviors. These cannot be tested programmatically because they depend on AVFoundation hardware responses and iOS system APIs that behave differently in Simulator.

---

_Verified: 2026-05-19_
_Verifier: Claude (gsd-verifier)_
