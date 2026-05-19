# Pitfalls Research — DualVideo

**Researched:** 2026-05-16
**Scope:** AVCaptureMultiCamSession + PiP compositor + AVAssetWriter pipeline on iOS 18, iPhone XR (A12) minimum

---

## Critical Pitfalls

### 1. Hardware Cost Budget Exceeded at 1080p on A12

**Risk level:** High

AVCaptureMultiCamSession enforces a hard ISP (Image Signal Processor) bandwidth budget expressed as `session.hardwareCost`. This is not a suggestion — if the value reaches or exceeds 1.0, the session stops with a runtime error. The ISP is a single chip processing all sensors; two 1080p streams at their native maximum frame rates can exhaust it on A12 (iPhone XR).

The critical non-obvious trap: **lowering the active frame rate does not reduce hardware cost.** The system charges cost based on the *maximum* frame rate the format supports, not what you actually set. A format capable of 60 fps costs the same whether you use 30 fps or 60 fps, because `AVCaptureDevice.activeVideoMinFrameDuration` can be changed at runtime without stopping the session.

The correct levers to reduce cost are:
- Select a **binned** format at the same resolution (lower bandwidth, slightly lower quality)
- Reduce **resolution** on one or both cameras
- Use `videoMinFrameDurationOverride` on `AVCaptureDeviceInput` *before* starting the session (this does lock in the rate at a hardware level and can reduce cost, unlike the runtime property)

1080p 30fps on both cameras simultaneously is achievable on A12 using the unbinned 1920x1080 format, but it is close to budget. Adding a third output (e.g., a preview layer) pushes cost higher. The front camera is the better candidate for a lower-resolution binned format (e.g., 1280x720 binned) since it appears small in the PiP overlay.

**Warning signs:** Session stops unexpectedly at runtime; `session.hardwareCost >= 1.0` printed in debug logs; no crash, just a notification posted.

**Prevention:**
1. Log `session.hardwareCost` immediately after `commitConfiguration()` before calling `startRunning()`.
2. If cost >= 0.9, switch front camera to a binned 720p format.
3. Do not add `AVCaptureVideoPreviewLayer` directly to the multi-cam session for both cameras if the composite Metal preview covers both anyway — each layer output adds cost.
4. Use `AVCaptureDevice.formats` to enumerate and explicitly select the lowest-cost format that meets quality requirements rather than relying on session presets.

**Phase:** Camera session setup phase (Phase 1). Validate on iPhone XR before building any compositor.

---

### 2. startRunning / stopRunning Called on Main Thread

**Risk level:** High

`AVCaptureSession.startRunning()` and `stopRunning()` are blocking, long-running calls. If called on the main thread they block the UI, cause watchdog warnings, and can trigger ANR-style terminations. This is documented but consistently violated.

On iOS 18, there is an additionally confirmed issue specific to `AVCaptureMultiCamSession`: calling `session.startRunning()` followed immediately by `session.addOutput()` or `session.commitConfiguration()` that includes an audio attachment can cause a **10-second main-thread freeze**. This appears to be a framework-level bug in iOS 18.0 and 18.1. The workaround is to never auto-trigger `startRunning()` at init time — defer it to an explicit user action (e.g., the app's first screen tap or a "Ready to record" button).

**Warning signs:** App feels frozen for several seconds after launch; Instruments shows main thread blocked in AVFoundation internals; Xcode console prints "This method should not be called on the main thread."

**Prevention:**
- Create a dedicated serial `DispatchQueue` named `"com.dualvideo.session"` and always dispatch `startRunning`, `stopRunning`, `beginConfiguration/commitConfiguration` onto it.
- Never call session methods from a `@MainActor` context without explicit dispatch.
- Defer session startup to the first explicit user gesture.

**Phase:** Camera session setup (Phase 1). Must be architecturally correct from first implementation.

---

### 3. beginConfiguration Without a Guaranteed commitConfiguration

**Risk level:** High

Every call to `session.beginConfiguration()` must be paired with `session.commitConfiguration()`. If an error path returns early, throws, or if an exception is not handled, the session is left in an uncommitted state. Subsequent `startRunning()` or `stopRunning()` calls crash with:

> "AVCaptureSession startRunning may not be called between calls to beginConfiguration and commitConfiguration"

This is one of the most commonly reported AVFoundation crashes across open-source projects.

**Warning signs:** App crashes when switching cameras or restarting recording; crash callstack mentions `startRunning` inside AVFoundation internals.

**Prevention:**
- Always wrap the begin/commit pair in a `defer` block:
  ```swift
  session.beginConfiguration()
  defer { session.commitConfiguration() }
  // ... configuration work that may throw or early-return
  ```
- Never `return` or `throw` inside a configuration block without the defer.

**Phase:** Camera session setup (Phase 1). Architecture review required before wiring up any dynamic reconfiguration.

---

### 4. AVAssetWriter Lifecycle Sequencing Errors

**Risk level:** High

`AVAssetWriter` has a strict state machine: `.unknown` → `.writing` → `.completed`/`.failed`. Violating sequence causes silent failures or crashes. The most common mistakes are:

**4a. Appending buffers before `startSessionAtSourceTime:`**
Calling `appendPixelBuffer(_:withPresentationTime:)` before `assetWriter.startSession(atSourceTime:)` throws `NSInternalInconsistencyException`. This crash is especially common after app backgrounding and resumption because the writer transitions to `.failed` in the background, and code paths that try to resume recording fail to create a fresh writer instance.

**4b. Trailing audio/video mismatch causing black frames**
Calling `finishWriting(completionHandler:)` directly, without first calling `endSession(atSourceTime: lastVideoFrameTime)`, results in the writer padding the end with black frames to match audio duration. The file is valid but ends badly.

**4c. Calling finishWriting concurrently with appendSampleBuffer**
Not safe. Must drain all append calls before invoking `finishWriting`.

**4d. Forgetting `markAsFinished()` on inputs before finishWriting**
Each `AVAssetWriterInput` must have `markAsFinished()` called before `finishWriting` is invoked, otherwise the writer may hang waiting for more samples.

**Warning signs:** Corrupt or truncated video files; silent `.failed` status on the writer; video ends with black frames; assertion failures in AVFoundation internals.

**Prevention:**
- Use a state flag (`isRecording: Bool`) gated by the session queue to prevent concurrent appends.
- Stop sequence: stop buffer flow → `markAsFinished()` on all inputs → `endSession(atSourceTime: lastTimestamp)` → `finishWriting(completionHandler:)`.
- After backgrounding, always check `assetWriter.status` before attempting to append; if `.failed`, tear down and recreate.
- Wrap the entire writer in a dedicated `actor Recorder` to serialize all state transitions.

**Phase:** Recording pipeline (Phase 2).

---

### 5. Pixel Buffer Synchronization Between Two Cameras

**Risk level:** High

The two `AVCaptureVideoDataOutput` instances deliver frames on separate queues. Their `CMSampleBuffer` presentation timestamps come from the same hardware clock, but frames are not delivered synchronously — one camera may deliver frame N while the other is still delivering frame N-1. Naively pairing the most recently received buffer from each camera before compositing produces temporal mismatches (visible stuttering or a ghosted overlay that is 1-2 frames behind).

Additionally, the back camera at 1080p30 and the front camera (even at a lower resolution) do not guarantee aligned timestamps. Small phase differences (< 33ms) accumulate over a long recording and cause audio/video drift.

**Warning signs:** PiP overlay visually "lags" behind main view; audio slowly drifts from video over multi-minute recordings; frame timestamps in the output file are non-monotonic.

**Prevention:**
- Use a synchronizer: `AVCaptureDataOutputSynchronizer` with both `AVCaptureVideoDataOutput` instances. This API was introduced exactly for multi-camera synchronization; it holds back delivery until paired frames from both outputs are ready, then delivers them together via `dataOutputSynchronizer(_:didOutput:)`.
- For the compositor, always use the `presentationTimeStamp` from the primary (back) camera buffer as the authoritative timestamp for the composited output buffer written to `AVAssetWriter`.
- Never use `CACurrentMediaTime()` or `Date()` to manufacture timestamps.

**Phase:** Compositor / recording pipeline (Phase 2).

---

### 6. Compositor Backpressure and Buffer Pool Exhaustion

**Risk level:** High

Each `AVCaptureVideoDataOutput` has an internal pool of `CVPixelBuffer` objects. If the delegate callback (`captureOutput(_:didOutputSampleBuffer:from:)`) holds a `CMSampleBuffer` longer than one frame interval (~33ms at 30fps), the pool drains. Once exhausted, the system drops frames and posts `captureOutput(_:didDrop:from:)` with reason `.outOfBuffers`.

With two cameras plus a Metal compositor plus an `AVAssetWriter`, four components compete for CPU/GPU time within that 33ms window. On A12 this is tight.

**Warning signs:** `didDrop` delegate called repeatedly; recorded video has visible frame drops or stuttering; memory usage spikes unexpectedly; `outOfBuffers` drop reason in logs.

**Prevention:**
- Keep `captureOutput(_:didOutputSampleBuffer:from:)` extremely fast. Do not perform any Metal rendering, compression, or file I/O inside this callback.
- Copy the `CVPixelBuffer` out of the `CMSampleBuffer` immediately and release the `CMSampleBuffer`, then dispatch compositing to a separate queue.
- Set `alwaysDiscardsLateVideoFrames = false` only during active recording (where you cannot afford gaps); set it back to `true` during preview-only mode.
- Use `AVAssetWriterInputPixelBufferAdaptor`'s `pixelBufferPool` to allocate output composite buffers — do not allocate fresh `CVPixelBuffer`s per frame; pool allocation is ~10x cheaper.
- Monitor `session.systemPressureCost` and react to thermal pressure by dropping compositor quality (e.g., skip overlay rendering temporarily) before the OS terminates the app.

**Phase:** Compositor / recording pipeline (Phase 2). Load-test on iPhone XR specifically.

---

### 7. Audio Session and Dual Microphone Configuration

**Risk level:** Medium

`AVCaptureMultiCamSession` automatically configures the `AVAudioSession` unless told not to. By default, when a front-facing camera is added, the session selects the front-facing microphone (TrueDepth side on modern iPhones). This behavior is automatic and opaque.

The project requires mixing both front and back microphones. The pitfalls here are:

**7a. AVCaptureSession owns the audio session**
You cannot independently configure `AVAudioSession.sharedInstance()` after the capture session has started managing it without explicitly opting out. Calling `setCategory` on the audio session after the capture session is running can silently fail or disrupt recording.

**7b. Only one audio track in a single-output AVAssetWriter**
`AVAssetWriter` supports one audio track. You cannot route two microphone inputs as separate channels unless you use `AVAudioEngine` to mix them into a single stereo/mono stream before feeding to the writer. Alternatively, `AVCaptureMultiCamSession` routes audio to a single `AVCaptureAudioDataOutput` — not two separate ones — meaning dual-mic mixing must be done at the `AVCaptureDevice` level (setting a preferred microphone polar pattern) rather than with two discrete audio inputs to the writer.

**7c. Audio session category conflicts**
If any other part of the app activates `AVAudioSession` with `.playback` or `.ambient` before the capture session starts, the session will not be able to use `.record` or `.playAndRecord`, causing audio to silently not record.

**Warning signs:** Recorded video has no audio; audio recorded from only one direction; audio session category mismatch errors in console; Siri/CallKit audio taking over.

**Prevention:**
- Explicitly configure `AVAudioSession` with `.playAndRecord` category, `.videoRecording` mode, and `.defaultToSpeaker` option *before* adding inputs to the session, then opt the session into manual audio management with `session.automaticallyConfiguresApplicationAudioSession = false`.
- Use `AVCaptureDevice` APIs to select microphone polar pattern (e.g., `.stereo` or `.cardioid`) rather than adding multiple audio inputs to the writer.
- Observe `AVAudioSessionInterruptionNotification` to detect when audio is yanked by a phone call or system event.

**Phase:** Audio pipeline (Phase 2).

---

### 8. Permission Handling Incompleteness

**Risk level:** Medium

Three permissions are required: camera (`NSCameraUsageDescription`), microphone (`NSMicrophoneUsageDescription`), and photo library write access (`NSPhotoLibraryAddUsageDescription`). Each must have a purpose string in `Info.plist`. Missing any one causes a hard crash on first access — the OS terminates the process without a catchable error.

The less obvious traps:

- Requesting camera permission does not grant microphone permission. They must be requested separately.
- `AVCaptureDevice.authorizationStatus(for: .video)` returns `.notDetermined` on first launch — you must call `requestAccess(for:)` and await the result before configuring the session, even if the user has previously been asked (on reinstall, status resets).
- `PHPhotoLibrary.authorizationStatus(for: .addOnly)` is distinct from `.readWrite`. Use `.addOnly` so you do not request broader access than needed.
- The permission dialog only appears once. If the user denies it, your app receives `.denied` on all subsequent calls. You must direct them to Settings; there is no re-request API.
- Accessing `AVCaptureDevice` on a device where the user revoked camera access (Settings > Privacy) returns `nil` from `AVCaptureDevice.default(for:)` — not an error, just `nil`. Unwrapping without checking crashes immediately.

**Warning signs:** Crash on first launch with no useful stack; session fails to start silently; test on device passes but tester device had previously granted permission so denial path is untested.

**Prevention:**
- Check and request all three permissions in sequence at app startup, before displaying any camera UI.
- Treat `.denied` and `.restricted` as permanent states; surface a clear "Go to Settings" prompt.
- Force-test the denial path by resetting permissions in Settings > General > Transfer or Reset iPhone > Reset Location & Privacy before each test.
- Never force-unwrap `AVCaptureDevice.default(for:)`.

**Phase:** Permissions / onboarding (Phase 1). Must be completed before any hardware testing.

---

### 9. PHPhotoLibrary Save — Temp File Race and Threading

**Risk level:** Medium

After `AVAssetWriter.finishWriting(completionHandler:)` completes, the `.mov` file exists at a temporary URL in the app's sandbox. The save to Photos involves:

1. Calling `PHPhotoLibrary.shared().performChanges(_:completionHandler:)`
2. Inside the change block, calling `PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)`

Common mistakes:

**9a. Deleting the temp file before PHPhotoLibrary finishes copying it**
`performChanges` is asynchronous. If you delete the temp file in the `finishWriting` completion handler before `performChanges` completes, the save fails silently (or with a non-descriptive error). The Photos library must be able to read the file throughout the entire save operation.

**9b. UI updates in the performChanges completion handler without dispatching to main**
`performChanges` completion handler is not called on the main thread. Updating UI (showing a success banner, enabling buttons) directly in that handler crashes with a main-thread checker violation.

**9c. File URL still locked by AVAssetWriter**
There is a brief window after `finishWriting` is called but before the completion block fires where the file may still be held open by the writer. Passing the URL to `performChanges` before receiving the completion callback can produce an empty or corrupt video in Photos.

**Warning signs:** Videos appear in Photos but are 0 seconds long or fail to play; save "succeeds" (no error in completion handler) but file does not appear; UI freezes after save.

**Prevention:**
- Never delete or move the temp file until `performChanges` completion handler fires with `success == true`.
- Always dispatch UI updates from the `performChanges` completion handler to `DispatchQueue.main.async`.
- Only call `performChanges` from inside the `finishWriting` completion handler, not concurrently.
- Store the temp file in `FileManager.default.temporaryDirectory` with a UUID filename to avoid collisions across multiple recordings.

**Phase:** File output / Photos save (Phase 3).

---

### 10. Background Interruption During Active Recording

**Risk level:** Medium

When an incoming phone call arrives, or when the user presses the home button, the app moves to the background. iOS policy forbids camera use in the background — AVCaptureSession stops immediately. The specific behaviors:

- `AVCaptureMovieFileOutput` recordings in progress are **stopped and truncated**. The file may be incomplete.
- `AVCaptureVideoDataOutput` callbacks stop being delivered.
- If you are using a custom `AVAssetWriter` pipeline, the writer transitions to `.failed` status while backgrounded. Any further append calls after resuming will crash unless the writer is fully torn down and recreated.
- An incoming call interrupts `AVAudioSession` — the `.interrupted` notification is posted. After the call ends, the session does not automatically resume. You must observe `AVAudioSessionInterruptionNotification` with `AVAudioSessionInterruptionTypeEnded` and explicitly restart the session.

**Warning signs:** Recording stops mid-session without user action; no video saved after a phone call interruption; `assetWriter.status == .failed` after resuming from background; no audio in resumed recording.

**Prevention:**
- Observe `AVCaptureSessionWasInterruptedNotification` and `AVCaptureSessionInterruptionEndedNotification`.
- On interruption: immediately stop recording (attempt to save what's been written so far), surface a clear "Recording stopped" message.
- Do not attempt to resume a failed `AVAssetWriter` — recreate the entire writer on resume.
- Observe `UIApplication.willResignActiveNotification` as an earlier signal than the session notification; use it to finalize the current recording gracefully before the session is forcibly stopped.
- Treat every recording stop as potentially unclean: always check file integrity (non-zero duration) before passing to PHPhotoLibrary.

**Phase:** Recording lifecycle management (Phase 2–3).

---

### 11. Swift 6 Concurrency vs. AVFoundation GCD Architecture

**Risk level:** Medium

AVFoundation is entirely GCD-based. Swift 6 strict concurrency checking (`SWIFT_STRICT_CONCURRENCY = complete`) raises errors for most natural patterns:

- `AVCaptureSession` is not `Sendable`. Holding it on a `@MainActor` class while dispatching operations to a background queue produces "non-sendable type in asynchronous access" errors.
- Camera delegate callbacks (`captureOutput(_:didOutputSampleBuffer:)`) arrive on a GCD queue, not on any actor. Forwarding data from there to a `@MainActor` property causes data-race warnings.
- Marking the entire `CameraManager` as `@MainActor` eliminates the warnings but forces all session operations (including the blocking `startRunning`) onto the main thread — exactly what must not happen.

The clean architectural solution (confirmed by real-world migration reports) is:

1. Create a `@globalActor CameraActor` (a custom global actor backed by a serial queue) to own `AVCaptureSession`, `AVAssetWriter`, and the compositor.
2. Create a `@MainActor` `CameraViewModel` (or `ObservableObject`) that the SwiftUI view observes; this receives updates via `await` calls to the `CameraActor`.
3. Mark delegate classes as `nonisolated` for the delegate method itself, then explicitly `Task { await cameraActor.handleFrame(...) }` to cross into actor isolation.

Suppressing warnings with `@preconcurrency` or `nonisolated(unsafe)` works short-term but hides real data races.

**Warning signs:** Xcode concurrency warnings flood the build log; runtime data-race detected by Thread Sanitizer; main thread blocked when switching cameras.

**Prevention:**
- Design the actor boundary before writing any AVFoundation code. Retrofitting is painful.
- Enable Thread Sanitizer for the first device test run to catch queuing violations.
- Use `SWIFT_STRICT_CONCURRENCY = minimal` during initial development, then raise to `complete` before Phase 1 is done.

**Phase:** Architecture / Phase 1. Actor design must be settled before any AVFoundation code is written.

---

### 12. Simulator Cannot Test Any Camera Feature

**Risk level:** Low (known, not a surprise — but causes wasted time if not respected)

Xcode Simulator has no camera hardware. Any code path that touches `AVCaptureDevice`, `AVCaptureSession`, or `AVCaptureMultiCamSession` either returns nil, throws, or simply does nothing silently on the Simulator.

**Warning signs:** "Works in Simulator" but crashes on device; nil device inputs not caught because Simulator doesn't exercise the guard.

**Prevention:**
- From day one, build and run exclusively on device for all camera features.
- Add a compile-time or runtime guard that shows a clear "Simulator not supported" overlay so no time is wasted debugging Simulator behavior.
- Add `#if targetEnvironment(simulator)` guards only where absolutely necessary (e.g., SwiftUI previews); do not use them to paper over missing error handling.

**Phase:** Phase 1 setup. Establish device-only workflow immediately.

---

### 13. AVCaptureMultiCamSession sessionPreset Must Be .inputPriority

**Risk level:** Low

Unlike `AVCaptureSession`, setting a `sessionPreset` (e.g., `.hd1920x1080`) on `AVCaptureMultiCamSession` has no effect and the session silently ignores it or picks an unexpected format. The multi-cam session requires explicit `activeFormat` assignment on each `AVCaptureDevice`. If you set a preset, you may get an unexpected format on one camera or the hardware cost calculation will be based on the wrong format.

After manually setting `device.activeFormat`, the session's effective preset becomes `.inputPriority`. This is the expected state.

**Warning signs:** Camera running at unexpected resolution; `hardwareCost` higher than expected for your target formats; one camera silently falls back to a lower resolution than configured.

**Prevention:**
- Always enumerate `device.formats`, filter for the desired resolution + frame rate, and assign directly: `device.activeFormat = chosenFormat` inside a `beginConfiguration / commitConfiguration` block.
- Verify the format after committing by logging `device.activeFormat.formatDescription`.

**Phase:** Phase 1 camera setup.

---

## v1.1 Pitfalls — Adding 4K to the Existing MultiCam Pipeline

**Researched:** 2026-05-19
**Scope:** Mistakes specific to upgrading an existing AVCaptureMultiCamSession + PiPCompositor + AVAssetWriter app from 1080p to optional 4K (3840×2160) back-camera recording.

---

### 14. 4K + Front Camera Simultaneously Will Almost Always Exceed hardwareCost on Non-Pro Hardware

**Risk level:** Critical

This is the central constraint for v1.1. The ISP bandwidth budget does not scale with chip generation in the way most developers expect. The issue is not whether the *device* can record 4K — iPhone XR can record 4K fine in the stock Camera app, using a single-camera session. The issue is whether it can do so *simultaneously* with a front-camera feed in an `AVCaptureMultiCamSession`.

The WWDC 2019 session 249 transcript makes this explicit: the maximum supported MultiCam resolution was **1920×1440** for unbinned formats on the initial A12 implementation. A 4K (3840×2160) format carries roughly **4× the ISP bandwidth** of 1080p. Combining a 4K back camera with any front camera format on A12 will almost certainly push `session.hardwareCost` above 1.0, causing the session to stop at runtime with a hardware cost overage notification.

On newer SoCs (A15 Pro and later, specifically iPhone 13 Pro+, 14 Pro+, 15 Pro+, 16 Pro+, 17 Pro+), Apple has expanded MultiCam headroom. Whether a specific device can sustain 4K back + any front camera resolution is device-model-specific and must be tested at runtime — it cannot be assumed based on chip generation alone.

**The key trap:** A developer tests on iPhone 17 Pro Max (sufficient headroom), ships the feature, and iPhone XR (and perhaps iPhone 14 non-Pro) users get a runtime session-stopped error during recording with no graceful fallback.

**Warning signs:** `session.hardwareCost >= 1.0` after `commitConfiguration()`; session stops immediately after `startRunning()` with `AVCaptureSessionRuntimeErrorNotification` and reason `.hardwareCostExceeded`; session appears to start but fires the error within milliseconds.

**Prevention:**
1. After committing a 4K back + front camera configuration, read `session.hardwareCost` before calling `startRunning()`. If >= 0.95, abort the 4K path and fall back.
2. Implement a graduated front-camera degradation ladder:
   - Try: 4K back + 720p front (binned)
   - If hardwareCost >= 0.95: Try 4K back + 480p front (binned)
   - If hardwareCost still >= 0.95: Disable front camera entirely for 4K recording
3. Treat 4K as a "back camera only" feature on A12/A13 devices. The front camera PiP must be removed from the compositor output when hardware budget cannot accommodate it.
4. Never assume: always validate `hardwareCost` on each device model the first time a 4K configuration is attempted. Cache the result per device model for subsequent sessions.

**Phase:** v1.1 Phase 1 — capability detection and session configuration.

---

### 15. 4K Format Might Not Have isMultiCamSupported = true

**Risk level:** High

`AVCaptureDeviceFormat` has an `isMultiCamSupported` property. Apple explicitly whitelists formats that can participate in a MultiCam session. The whitelisted set was originally limited to binned formats up to 1920×1440 and the 1920×1080 unbinned format. Whether any 4K format on a given device model returns `isMultiCamSupported = true` is device- and iOS-version-dependent and is not documented with a clear compatibility matrix.

The practical failure mode: you query for a 3840×2160 format, find it in `device.formats`, and attempt to set `device.activeFormat` to it inside a MultiCam session configuration. The session commits without error, but `session.hardwareCost` immediately reports >= 1.0, or the session stops at runtime. Alternatively, on devices where 4K MultiCam *is* whitelisted, `isMultiCamSupported` returns `true` and the session runs.

**Warning signs:** Session commits cleanly but `hardwareCost` is already 1.0 after a single device's format is applied; no explicit API error during configuration; failure only surfaces at `startRunning()` time.

**Prevention:**
- When enumerating formats for 4K selection, filter by **both** conditions:
  ```swift
  device.formats.filter { format in
      let desc = format.formatDescription
      let dims = CMVideoFormatDescriptionGetDimensions(desc)
      let is4K = dims.width == 3840 && dims.height == 2160
      return is4K && format.isMultiCamSupported
  }
  ```
- If the filtered list is empty on the current device, 4K is not available in a MultiCam session. Surface this to the user as "4K not supported on this device in dual-camera mode" rather than attempting to run and failing.
- Do not rely on `AVCaptureSessionPreset3840x2160` — presets are silently ignored by `AVCaptureMultiCamSession`. Only `activeFormat` assignment matters.

**Phase:** v1.1 Phase 1 — format discovery and capability detection.

---

### 16. sessionPreset = .hd3840x2160 Breaks the MultiCam Session

**Risk level:** High

A common shortcut in single-camera apps is `session.sessionPreset = .hd3840x2160`. This works on `AVCaptureSession` but **does nothing useful and can corrupt the configuration on `AVCaptureMultiCamSession`**. The multi-cam session ignores preset changes or, in some configurations, sets the device's `activeFormat` to a 4K format that has `isMultiCamSupported = false`, producing:

> "The camera's active format is unsupported by this session."

This error appears when `AVCaptureDeviceInput` is added after the preset is set. The session may appear to configure without error but then fails when `startRunning()` is called, or it may throw during `addInput`.

**Warning signs:** `"The camera's active format is unsupported by this session"` in console; session fails to start after a preset change; `device.activeFormat.isMultiCamSupported` is false after committing configuration.

**Prevention:**
- Never set `sessionPreset` on `AVCaptureMultiCamSession`. The correct approach is always explicit `device.activeFormat` assignment.
- After committing any configuration, assert `device.activeFormat.isMultiCamSupported == true` in debug builds.
- The existing v1.0 architecture already avoids presets (Pitfall #13 above). Adding 4K must follow the same pattern: enumerate formats, filter by `isMultiCamSupported && dimensions == 3840×2160`, set `activeFormat` directly.

**Phase:** v1.1 Phase 1 — session reconfiguration for 4K.

---

### 17. CVPixelBufferPool Undersized for 4K Output Buffers

**Risk level:** High

The `AVAssetWriterInputPixelBufferAdaptor` creates an internal `CVPixelBufferPool` sized for the output dimensions specified in `sourcePixelBufferAttributes`. In the existing 1080p pipeline, the pool was configured for 1920×1080 buffers. Switching to 4K without updating `sourcePixelBufferAttributes` means either:

- **Wrong dimensions:** The pool still allocates 1080p-sized buffers. When the compositor tries to render a 3840×2160 frame into a pool buffer, the dimensions mismatch causes a silent render failure or a crash in the pixel buffer backing store.
- **Too few buffers:** 4K buffers are ~4× larger (approximately 32 MB each in 420YpCbCr8BiPlanarFullRange). The default pool depth (typically 3-5 buffers) stays the same, but the per-buffer GPU transfer time is longer. If the compositor or encoder is slightly slow, the pool drains and `CVPixelBufferPoolCreatePixelBuffer` returns `kCVReturnWouldExceedAllocationThreshold`.

**Warning signs:** Compositor produces black frames; `CVPixelBufferPoolCreatePixelBuffer` returns a non-zero error code; `didDrop` fires immediately on recording start; memory usage spikes disproportionately at start of 4K recording.

**Prevention:**
- When switching to 4K, tear down and recreate both `MovieRecorder` and its `AVAssetWriterInputPixelBufferAdaptor` with updated `sourcePixelBufferAttributes`:
  ```swift
  let pixelBufferAttributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      kCVPixelBufferWidthKey as String: 3840,
      kCVPixelBufferHeightKey as String: 2160,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:]
  ]
  ```
- Do not attempt to resize or reuse a pool configured for a different resolution. Recreate from scratch.
- Set `kCVPixelBufferPoolMinimumBufferCountKey` to at least 3 for 4K to ensure the pool does not starve under normal compositing latency.
- Always allocate output buffers from `adaptor.pixelBufferPool` — never create `CVPixelBuffer` instances ad hoc per frame. Pool reuse is critical at 4K frame sizes.

**Phase:** v1.1 — MovieRecorder reconfiguration.

---

### 18. Core Image Compositor Performance Degrades Non-Linearly at 4K

**Risk level:** High

The existing `PiPCompositor` uses `CISourceOverCompositing` to blend front-camera frames over back-camera frames. At 1080p (2,073,600 pixels per frame at 30fps = ~62 million pixels/second), Core Image runs comfortably within the 33ms frame budget on A12. At 4K (8,294,400 pixels per frame at 30fps = ~249 million pixels/second), the pixel throughput is 4× higher. On A12 this will exceed the frame budget, causing dropped frames during compositing.

There are two additional non-obvious traps specific to the existing architecture:

**18a. CIContext created per frame**
If `PiPCompositor` instantiates a new `CIContext` for each call to `mix(back:front:pipFrame:)`, the overhead at 4K will cause severe frame drops. `CIContext` initialization is expensive regardless of resolution; at 4K the initialization cost relative to frame budget increases.

**18b. Intermediate caching enabled (default)**
By default, `CIContext` caches intermediate render results. For video, where every frame differs, this cache consumes memory without benefit. At 4K, each cached intermediate is ~8–32 MB. After a few frames, memory pressure causes evictions that stall the render pipeline.

**18c. CPU fallback path**
If the `CIContext` is initialized without an explicit Metal device, Core Image may fall back to CPU rendering for certain filter graphs. At 4K this is catastrophically slow — CPU rendering of an 8MP frame is an order of magnitude slower than GPU.

**Warning signs:** Frame rate drops from 30fps to 10-15fps at start of 4K recording; Instruments GPU timeline shows idle periods between frames; memory footprint climbs steadily during recording; Instruments Time Profiler shows Core Image work on the main thread or CPU.

**Prevention:**
1. Ensure the `CIContext` is created **once** (in `PiPCompositor.init`) and reused for every frame. If the context is not already a singleton, fix this before enabling 4K.
2. Create the context with caching disabled and an explicit Metal device:
   ```swift
   let device = MTLCreateSystemDefaultDevice()!
   let context = CIContext(mtlDevice: device, options: [
       .cacheIntermediates: false,
       .name: "PiPCompositor"
   ])
   ```
3. Consider replacing `CISourceOverCompositing` with a custom Metal shader for 4K. Metal compute shaders run significantly faster than Core Image's generic filter graph at high resolutions because they avoid the Core Image graph compilation overhead and can be tuned for the specific PiP blend operation.
4. At 4K, reducing the composited front-camera overlay to a smaller fraction of the frame (the PiP is already small) provides minimal CPU savings because the back-camera background still dominates the pixel budget. The optimization is in the render pipeline, not the overlay size.

**Phase:** v1.1 — PiPCompositor upgrade. Benchmark on iPhone XR before declaring 4K viable.

---

### 19. AVAssetWriter Video Settings Must Be Updated for 4K HEVC

**Risk level:** Medium

The existing `MovieRecorder` configures `AVAssetWriterInput` with video settings appropriate for 1080p H.264 (or HEVC). These settings hardcode the output dimensions. If the settings are not updated when switching to 4K, one of two silent failures occurs:

- **Dimension mismatch:** The writer encodes at 1080p even though pixel buffers contain 4K content. The encoder silently rescales, producing a 1080p file labeled as 4K in metadata, or it crashes with a dimension assertion.
- **Wrong codec:** H.264 is not practical for 4K recording due to bitrate requirements. At 4K30, H.264 needs ~45–60 Mbps for comparable quality to what HEVC achieves at ~25–30 Mbps. The resulting file is larger and encoding is slower, potentially causing encoder backpressure.

**Prevention:**
- Use `AVCaptureVideoDataOutput.recommendedVideoSettings(forVideoCodecType: .hevc, assetWriterOutputFileType: .mov)` to get Apple-recommended settings, then override the width and height:
  ```swift
  var settings = videoDataOutput.recommendedVideoSettings(
      forVideoCodecType: .hevc,
      assetWriterOutputFileType: .mov
  ) ?? [:]
  settings[AVVideoWidthKey] = 3840
  settings[AVVideoHeightKey] = 2160
  ```
- Never hardcode `AVVideoWidthKey` / `AVVideoHeightKey` to 1920/1080 in a code path that may also serve 4K. Parameterize them from the selected resolution.
- Verify `assetWriter.inputs.first?.outputSettings` after setup to confirm dimensions match the expected output.
- HEVC hardware encoding is available on A9+ for the specific encode profiles used by the camera pipeline. On A12 it is fully hardware-accelerated. Do not use H.264 for 4K output.

**Phase:** v1.1 — MovieRecorder settings parameterization.

---

### 20. Devices Supporting MultiCam But Not 4K in MultiCam Mode

**Risk level:** Medium

The set of devices that support `AVCaptureMultiCamSession` and the set that support 4K in a MultiCam session are not identical. This creates a specific failure class:

- `AVCaptureMultiCamSession.isMultiCamSupported` → `true` (device supports multi-cam, A12+)
- No 4K back-camera format has `isMultiCamSupported = true` (device cannot sustain 4K ISP bandwidth simultaneously)
- OR: A 4K format has `isMultiCamSupported = true` but `session.hardwareCost` after configuration >= 1.0 when combined with any front camera format

Known category of devices in this situation: **iPhone XR, XS, XS Max** (A12) and likely **iPhone 11 series** (A13) — all can record 4K in single-camera mode but likely cannot in a MultiCam session with a front camera active. The primary test device (iPhone XR) falls squarely in this category.

**The trap for this project specifically:** The developer will test 4K on iPhone 17 Pro Max (plenty of headroom) and ship it. The QualitySettingsSheet shows a 4K option (because the back camera *can* do 4K), the user selects it, recording starts, and the session stops after a fraction of a second with a hardware cost error. The user has no 4K file and no clear error message.

**Prevention:**
1. The 4K capability detection must test the *combined* configuration, not just the back camera in isolation:
   ```swift
   // Wrong: asks if back camera can do 4K in single-camera use
   let can4K = backCamera.formats.contains { 
       CMVideoFormatDescriptionGetDimensions($0.formatDescription).width == 3840 
   }
   
   // Correct: asks if back camera can do 4K inside this MultiCam session
   let can4KMultiCam = backCamera.formats.contains {
       let dims = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
       return dims.width == 3840 && $0.isMultiCamSupported
   }
   ```
2. Even after passing `isMultiCamSupported`, do a trial configuration:
   - `beginConfiguration()`
   - Set back camera to 4K format
   - Set front camera to its lowest-cost binned format
   - `commitConfiguration()`
   - Check `session.hardwareCost`
   - If >= 0.95, mark 4K as unavailable and revert to 1080p configuration
3. Perform this trial at app startup (or first settings-panel open) so the UI reflects actual capability, not theoretical hardware support.
4. The `QualitySettingsSheet` must only present 4K as an option if the trial configuration succeeded on the current device.

**Phase:** v1.1 Phase 1 — capability detection at startup.

---

### 21. systemPressureCost Exceeds Safe Range During Long 4K Recordings

**Risk level:** Medium

`AVCaptureMultiCamSession.systemPressureCost` measures thermal and power load independently of ISP bandwidth. Even if `hardwareCost` is under 1.0, a 4K recording session sustains significantly higher power draw than 1080p, causing device temperature to rise. At `systemPressureCost` between 1.0 and 2.0, the session can run for ~15 minutes before the OS terminates it. Above 3.0, it terminates within seconds.

For a dual-camera PiP recording app, the compounding loads are:
- ISP processing two camera streams
- GPU compositing 4K frames at 30fps
- HEVC hardware encoder running at 4K
- Display rendering the live preview
- Audio capture

On iPhone XR this combination sustains a much higher thermal load than on A16/A17 chips which have more efficient ISPs and encoders.

**Warning signs:** `session.systemPressureCost` rises during long recordings; `AVCaptureSessionRuntimeErrorNotification` fires with `.systemPressureStateRestrictingCapturePerformance` reason; device becomes warm during recording; recording stops at approximately 10–15 minutes with no user action.

**Prevention:**
1. Observe `AVCaptureDevice.SystemPressureState` notifications:
   ```swift
   NotificationCenter.default.addObserver(
       forName: .AVCaptureDeviceSubjectAreaDidChange, ...
   )
   // Also observe session runtime errors for pressure-related stops
   ```
2. When `systemPressureCost` rises above 1.5, proactively reduce frame rate:
   ```swift
   device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 24) // 24fps
   device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 24)
   ```
3. As a last resort before session termination, drop the compositor to 1080p output (stop accepting 4K buffers, downscale in compositor) to relieve encoder pressure while keeping both cameras active.
4. Surface a non-alarming "Reducing quality to manage device temperature" message to the user rather than silently stopping.

**Phase:** v1.1 — recording quality management and error handling.

---

### 22. PiPCompositor Output Size Not Updated Causes Silent Dimension Mismatch

**Risk level:** Medium

`PiPCompositor.mix(back:front:pipFrame:)` currently computes the output buffer dimensions as a fixed constant (1920×1080 in the v1.0 implementation) or derives them from the back camera buffer dimensions. If the compositor's internal output size is not updated when switching to 4K mode, one of two failures occurs:

- **Fixed output size:** The compositor renders into a 1920×1080 buffer regardless of back camera input resolution. The resulting file is 1080p even when 4K was selected. No error is raised — the pipeline silently downscales.
- **Derived from input but not propagated to the pool:** The compositor changes its render target size, but the `CVPixelBufferPool` in `AVAssetWriterInputPixelBufferAdaptor` was created for 1080p. The compositor requests a 4K buffer from the adaptor's pool, which allocates a 1080p buffer, and then the 4K render target does not fit.

Additionally, the `pipFrame: CGRect` parameter that positions the front-camera overlay is typically expressed in 1080p coordinate space (0,0 to 1920,1080). If this is not scaled up to 4K coordinates (0,0 to 3840,2160) before compositing, the PiP overlay appears in the lower-left quadrant of the 4K frame rather than at the user's intended position.

**Warning signs:** Recorded 4K file reports 4K dimensions but detail is blurry (1080p content upscaled); PiP overlay appears in wrong position in 4K recordings; `CVPixelBufferGetWidth` of compositor output is 1920 when 3840 is expected.

**Prevention:**
- Make output resolution a constructor parameter of `PiPCompositor`, not a constant. Pass `CGSize(width: 3840, height: 2160)` when 4K mode is active.
- Scale all coordinate systems (pipFrame, overlay bounds, crop rects) proportionally when switching between output resolutions.
- Assert in debug builds that `CVPixelBufferGetWidth(outputBuffer) == expectedWidth` at the start of each `mix()` call.
- Teardown and recreate `PiPCompositor` when resolution changes, rather than mutating an existing instance — mutable state in a per-frame hot path is a source of race conditions.

**Phase:** v1.1 — PiPCompositor parameterization.

---

## Hardware / API Limitations to Accept

These are real constraints, not bugs. Document them and design around them.

### ISP Bandwidth: 1080p on Both Cameras Is Possible but Tight on A12

Dual 1080p simultaneous capture on iPhone XR (A12) works but is near the hardware budget ceiling. Using a binned 720p format for the front camera (which occupies a small PiP overlay) is the practical production approach. The 17 Pro Max has significantly more headroom.

**Design decision:** Use back camera at 1080p30 (unbinned), front camera at 720p (binned). The front camera output is scaled down to PiP size anyway; 720p is visually indistinguishable from 1080p at PiP scale.

### 4K in MultiCam Mode Is a Pro-Hardware Feature

Based on WWDC 2019 session 249 and the ISP bandwidth model, 4K + front camera simultaneously is not feasible on A12 and unlikely on A13. It is viable starting with A15 Pro (iPhone 13 Pro) and confidently on A16/A17 (iPhone 14 Pro and later). The v1.1 implementation must treat 4K as conditionally available, not as a universal upgrade.

### No Native Dual-Track Audio Output

`AVAssetWriter` writes a single audio track. iOS does not support simultaneously routing two discrete microphone streams to separate audio channels through the capture session alone. Mixed mono/stereo audio from a single `AVCaptureAudioDataOutput` is the practical output. True dual-mic matrix recording would require `AVAudioEngine` tap integration, which is out of scope.

### No Preset Support on AVCaptureMultiCamSession

As above: format selection is entirely manual. Presets are silently ignored. This is by design — presets are convenience wrappers for single-camera sessions.

### Frame Rate Reduction Does Not Reduce Hardware Cost Unless Using videoMinFrameDurationOverride Before Session Start

Setting `activeVideoMinFrameDuration` at runtime does not reduce the ISP hardware cost because the API allows dynamic frame rate changes. Only `videoMinFrameDurationOverride` set on `AVCaptureDeviceInput` before `startRunning` is respected by the cost calculation.

### AVCaptureMovieFileOutput Is Not Compatible with Custom PiP Compositing

`AVCaptureMovieFileOutput` writes raw camera output directly from one camera. It cannot accept composited pixel buffers from a Metal renderer. The correct pipeline for PiP output is `AVCaptureVideoDataOutput` (raw buffers) → Metal compositor → `AVAssetWriterInputPixelBufferAdaptor` → `AVAssetWriter`. `AVCaptureMovieFileOutput` is not usable for this project's core requirement.

### Camera Is Unavailable in Background

iOS will never permit camera use in a background app. Recording must stop when the app backgrounds. There is no exception for personal sideloads. Audio-only backgrounding is permitted, but video is not.

### A12 Is the Absolute Minimum — Older Devices Fail Gracefully

`AVCaptureMultiCamSession.isMultiCamSupported` returns `false` on pre-A12 devices. The app must check this at launch and display a clear unsupported-device message. Do not attempt to instantiate the session on unsupported hardware; the results are undefined.

---

## Phase-Specific Warning Summary (v1.1)

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| 4K capability detection | Using single-camera 4K check instead of MultiCam check (Pitfall 20) | Filter formats by `isMultiCamSupported`, do trial configuration, check `hardwareCost` |
| Session reconfiguration for 4K | `sessionPreset = .hd3840x2160` corrupts MultiCam format (Pitfall 16) | Always use `device.activeFormat` assignment; never use presets |
| hardwareCost with 4K | 4K back + any front camera exceeds 1.0 on A12/A13 (Pitfall 14) | Degradation ladder: try 4K+720p, then 4K+480p, then 4K back-only |
| CVPixelBufferPool | Pool still sized for 1080p when 4K buffers are appended (Pitfall 17) | Recreate MovieRecorder and adaptor with 3840×2160 `sourcePixelBufferAttributes` |
| Core Image compositor | CIContext recreated per frame; no GPU context; caching enabled (Pitfall 18) | Singleton CIContext with `mtlDevice`, `.cacheIntermediates: false` |
| Writer video settings | Width/height hardcoded to 1920/1080; H.264 at 4K (Pitfall 19) | Parameterize dimensions; use HEVC via `recommendedVideoSettings` |
| PiP position in 4K | pipFrame in 1080p coordinates applied to 4K compositor (Pitfall 22) | Scale coordinate space proportionally; parameterize output size in compositor |
| Thermal management | systemPressureCost rises above 2.0 during long 4K recording (Pitfall 21) | Observe pressure notifications; proactively reduce frame rate |

---

## Sources

- Apple WWDC 2019 Session 249 — Introducing Multi-Camera Capture for iOS: https://asciiwwdc.com/2019/sessions/249
- Apple Technical Note TN2445 — Handling Frame Drops: https://developer.apple.com/library/archive/technotes/tn2445/_index.html
- AVCaptureMultiCamSession.hardwareCost: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/hardwarecost
- AVCaptureMultiCamSession.systemPressureCost: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/systempressurecost
- AVCaptureOutput.DataDroppedReason.outOfBuffers: https://developer.apple.com/documentation/avfoundation/avcaptureoutput/datadroppedreason/outofbuffers
- AVAssetWriter.finishWriting(completionHandler:): https://developer.apple.com/documentation/avfoundation/avassetwriter/1390432-finishwriting
- AVCaptureMultiCamSession iOS 18 main thread freeze (community confirmed): https://github.com/shogo4405/HaishinKit.swift/discussions/1637
- Swift 6 camera app concurrency refactoring: https://fatbobman.com/en/posts/swift6-refactoring-in-a-camera-app/
- beginConfiguration/commitConfiguration crash across open-source projects: https://github.com/react-native-camera/react-native-camera/issues/2329
- AVMultiCamPiP Apple sample: https://developer.apple.com/documentation/AVFoundation/avmulticampip-capturing-from-multiple-cameras
- WWDC 2020 Session 10008 — Optimize the Core Image Pipeline for Your Video App: https://developer.apple.com/videos/play/wwdc2020/10008/
- AVCaptureDevice.Format.isMultiCamSupported: https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/ismulticamsupported
- AVCaptureVideoDataOutput.recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType:): https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/recommendedvideosettings(forvideocodectype:assetwriteroutputfiletype:)
- iPhone XR Technical Specifications (4K capable in single-camera mode): https://support.apple.com/en-us/111868
- AVCaptureSession setting preset — forum thread confirming 4K preset breaks MultiCam activeFormat: https://developer.apple.com/forums/thread/808363
- CVPixelBufferPool allocation threshold handling: https://developer.apple.com/documentation/corevideo/cvpixelbufferpool
