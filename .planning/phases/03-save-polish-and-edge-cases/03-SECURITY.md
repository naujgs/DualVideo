---
phase: 03-save-polish-and-edge-cases
asvs_level: 1
audited: 2026-05-17
result: SECURED
threats_closed: 9
threats_total: 9
---

# Security Audit — Phase 03: Save Polish and Edge Cases

**Phase:** 03 — save-polish-and-edge-cases
**Threats Closed:** 9/9
**ASVS Level:** 1

## Threat Verification

| Threat ID  | Category               | Disposition | Status | Evidence |
|------------|------------------------|-------------|--------|----------|
| T-03-01-01 | Elevation of Privilege | mitigate    | CLOSED | PhotoSaveManager.swift:53-57 — `statusProvider()` result guarded before `performChanges`; `.permissionDenied` returned and completion dispatched to main on failure |
| T-03-01-02 | Information Disclosure | accept       | CLOSED | Accepted: file in app tmp dir, inaccessible to other apps; `cleanUpOrphanedTempFiles()` removes on next launch |
| T-03-01-03 | Denial of Service      | mitigate    | CLOSED | PhotoSaveManager.swift:63-76 — all state mutations inside `DispatchQueue.main.async` in `performChanges` completion handler; comment explicitly tags T-03-01-03 |
| T-03-02-01 | Tampering              | accept       | CLOSED | Accepted: PiPOverlayState.swift:125-130 — `switch index` with `default: targetOffset = .zero` sanitizes any out-of-range UserDefaults value |
| T-03-02-02 | Denial of Service      | accept       | CLOSED | Accepted: `restorePersistedCorner` called from `onAppear` with live GeometryReader values; portrait-only app eliminates stale-geometry risk |
| T-03-03-01 | Availability           | mitigate    | CLOSED | RecordingManager.swift:196-197 — `cameraManager?.turnTorchOff()` called before `stopRecording()` in `handleInterruption(cameraManager:)` |
| T-03-03-02 | Tampering              | mitigate    | CLOSED | CameraManager.swift:93-95 — `guard device.hasTorch, device.isTorchModeSupported(.on)` in `toggleTorch()`; CameraManager.swift:111-114 — same guard plus `device.torchMode == .on` in `turnTorchOff()` |
| T-03-03-03 | Denial of Service      | mitigate    | CLOSED | RecordingManager.swift:101 — `[weak cameraManager]` capture list; RecordingManager.swift:103 — `cameraManager?.syncSessionRunningState()` is no-op when nil |
| T-03-03-04 | Information Disclosure | accept       | CLOSED | Accepted: cosmetic stale `isTorchOn` after OOB hardware override; no security or data impact |

## Accepted Risks Log

| Threat ID  | Rationale |
|------------|-----------|
| T-03-01-02 | Temp .mov is in app-sandboxed `tmp/` directory, inaccessible to other apps or users. `cleanUpOrphanedTempFiles()` in `RecordingManager.init()` removes orphans on next launch. Low-value data; no PII exposure. |
| T-03-02-01 | UserDefaults `pip_corner_index` is an app-local UInt, not security-sensitive. `restorePersistedCorner()` sanitizes via `switch/default` — out-of-range values fall to corner 0 (.zero offset). No privilege impact. |
| T-03-02-02 | `restorePersistedCorner()` is called from `onAppear` with the then-current `GeometryReader` values. App enforces portrait-only orientation (Info.plist), eliminating geometry drift between writes and restores. |
| T-03-03-04 | iOS can override torch mode for thermal reasons without invoking the app's observer. `isTorchOn` may show stale state (on when LED is off). This is a cosmetic UI discrepancy with no data or security consequence. |

## Unregistered Flags

None — no unregistered threat flags were raised in any phase 03 SUMMARY.md.

## Files Audited

- `DualVideo/Features/Recording/PhotoSaveManager.swift`
- `DualVideo/Features/Recording/RecordingManager.swift`
- `DualVideo/Features/Camera/CameraManager.swift`
- `DualVideo/Features/Camera/PiPOverlayState.swift`
- `.planning/phases/03-save-polish-and-edge-cases/03-01-PLAN.md`
- `.planning/phases/03-save-polish-and-edge-cases/03-02-PLAN.md`
- `.planning/phases/03-save-polish-and-edge-cases/03-03-PLAN.md`
- `.planning/phases/03-save-polish-and-edge-cases/03-01-SUMMARY.md`
- `.planning/phases/03-save-polish-and-edge-cases/03-02-SUMMARY.md`
- `.planning/phases/03-save-polish-and-edge-cases/03-03-SUMMARY.md`
