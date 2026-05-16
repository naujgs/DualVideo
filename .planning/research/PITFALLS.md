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

## Hardware / API Limitations to Accept

These are real constraints, not bugs. Document them and design around them.

### ISP Bandwidth: 1080p on Both Cameras Is Possible but Tight on A12

Dual 1080p simultaneous capture on iPhone XR (A12) works but is near the hardware budget ceiling. Using a binned 720p format for the front camera (which occupies a small PiP overlay) is the practical production approach. The 17 Pro Max has significantly more headroom.

**Design decision:** Use back camera at 1080p30 (unbinned), front camera at 720p (binned). The front camera output is scaled down to PiP size anyway; 720p is visually indistinguishable from 1080p at PiP scale.

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
