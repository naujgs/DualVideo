# Phase 2: Recording Pipeline - Compositor, Writer, Audio - Research

**Researched:** 2026-05-17
**Domain:** AVFoundation recording pipeline — Metal/CIFilter compositing, AVAssetWriter state machine, AVCaptureMultiCamSession dual-mic audio, Swift 6 actor isolation
**Confidence:** MEDIUM-HIGH (core patterns well-established; dual-mic audio has known iOS 16.1+ caveats that need on-device validation)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Compositor reads `PiPOverlayState.offset` at each frame — PiP position is baked into recording at its live drag position.
- **D-02:** Record/Stop button is bottom-center, always visible, thumb-reachable, conventional iOS video app placement.
- **D-03:** During active recording, show a blinking red dot + elapsed MM:SS timer at the top of the screen. No border or full-screen overlay.
- **D-04:** No countdown — tapping Record starts recording immediately. Elapsed timer begins on Record tap. CAP-04 "3-second countdown" is explicitly dropped.
- **D-05:** Capture audio from both the back and front microphones, mixed into a single blended AAC audio track. Use `AVCaptureMultiCamSession` dual audio inputs; let AVFoundation blend them.
- **D-06:** When a phone call or app backgrounding interrupts recording, auto-stop and cleanly finalize the `AVAssetWriter`. The partial-but-valid `.mov` temp file is preserved. No data is discarded.

### Claude's Discretion

- Compositor implementation strategy (Metal shaders vs `CVPixelBuffer` copy via `vImageScale` — whichever is more reliable on A12 hardware at 1080p without exceeding `hardwareCost` constraints).
- Exact threading model for compositor ↔ `MovieRecorder` handoff (must stay consistent with established `sessionQueue`/`dataOutputQueue` pattern in `CameraManager`).
- Exact AVAudioSession configuration details for dual-mic input.
- Specific `AVAssetWriter` track configuration (bitrate, keyframe interval).
- Output resolution: 1080p (1920×1080), format: H.264/AAC `.mov` — from project requirements.

### Deferred Ideas (OUT OF SCOPE)

- Photos save flow — Phase 3 (`OUT-01`, `OUT-02`)
- PiP corner snapping — Phase 3 (D-08 from Phase 1)
- Resume-after-interruption (re-start recording after a phone call ends) — Phase 3 edge-case hardening
- Separate per-camera audio tracks — blended single track only
- 4K recording output — explicitly out of scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CAP-04 | App shows clear recording state (red-dot timer, elapsed MM:SS) — countdown dropped per D-04 | D-03 covers blinking red dot + timer; SwiftUI `TimelineView` or `Timer` drives elapsed |
| REC-01 | Single Record/Stop control starts and stops one synchronized recording pipeline | State machine pattern — `RecordingState` enum drives `MovieRecorder` and `PiPCompositor` |
| REC-02 | App composites both camera feeds into one PiP frame stream in real time | CIFilter compositor pattern: `CISourceOverCompositing` + `CILanczosScaleTransform` + `CIContext.render(to:)` |
| REC-03 | App writes a valid 1080p H.264/AAC video file to temporary storage | `AVAssetWriter` + `AVAssetWriterInput` (H.264 video) + `AVAssetWriterInput` (AAC audio) |
| REC-04 | Recording finalization is resilient to interruption/background transitions | `UIApplication.didEnterBackgroundNotification` + `beginBackgroundTask` + `finishWriting(completionHandler:)` |
</phase_requirements>

---

## Summary

Phase 2 requires three cooperating subsystems: (1) a frame compositor that reads pixel buffers from both cameras, composites them into a single 1080p PiP frame, and emits composited pixel buffers; (2) an `AVAssetWriter` state machine that accepts those pixel buffers plus blended audio sample buffers and writes a valid `.mov`; (3) a recording-control layer (state model, UI, interruption handling) that coordinates start/stop/finalize across the other two.

The compositor can use either Metal (highest GPU efficiency, full control) or Core Image (`CISourceOverCompositing`, simpler code, GPU-backed via `CIContext`). For this project — 30fps 1080p PiP on A12 hardware within `hardwareCost` budget — Core Image is the safer first implementation: no custom shaders, well-understood behavior, and adequate GPU throughput. Metal is available as an upgrade path if CI proves too slow under profiling.

The dual-mic audio situation has a known bug on iOS 16.1+ involving `AVCaptureMultiCamSession` and `usesApplicationAudioSession`. The safest configuration tested in the community is to add a single `AVCaptureAudioDataOutput` connected to both the front-beam and back-beam ports through one microphone input, relying on AVFoundation's beam-former to blend; alternatively, accept that one of the two beams may drop silently on some OS versions and treat this as a best-effort feature validated on device.

The `AVAssetWriter` state machine must guard every append with `isReadyForMoreMediaData` and `writer.status == .writing` checks. Finalization on interruption uses `UIApplication.didEnterBackgroundNotification` and a `beginBackgroundTask` extension to get up to 30 seconds to call `finishWriting(completionHandler:)`.

**Primary recommendation:** Implement compositor as `PiPCompositor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate` using Core Image; implement `MovieRecorder` as a Swift 6–compatible class with `nonisolated(unsafe)` AVFoundation internals serialized on `dataOutputQueue`; wire audio with a single `AVCaptureAudioDataOutput` using front-beam and back-beam ports.

---

## Standard Stack

### Core

| Library/API | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| `AVFoundation` | iOS 18.0+ | Session, outputs, asset writer | Native Apple; no alternative for capture pipeline |
| `AVCaptureVideoDataOutput` | iOS 13+ | Pixel buffer delegate for both cameras | Already wired in Phase 1 `CameraManager` |
| `AVCaptureAudioDataOutput` | iOS 13+ | Audio sample buffer delegate for mic beams | Standard approach for raw audio capture in `AVCaptureMultiCamSession` |
| `AVAssetWriter` | iOS 4+ | Write `.mov` file from sample buffers | Standard for programmatic video recording on iOS |
| `AVAssetWriterInput` | iOS 4+ | Video track (H.264) and audio track (AAC) | Required by `AVAssetWriter` |
| `AVAssetWriterInputPixelBufferAdaptor` | iOS 6+ | Append `CVPixelBuffer` composited frames | Needed when compositor produces pixel buffers rather than sample buffers |
| `Core Image` | iOS 5+ | `CISourceOverCompositing`, `CILanczosScaleTransform`, `CIContext` | GPU-backed compositing without custom shaders |
| `SwiftUI` | iOS 18.0+ | Record button, blinking red dot overlay, MM:SS timer | Consistent with existing codebase UI layer |

[VERIFIED: Apple documentation, existing Phase 1 codebase]

### Supporting

| Library/API | Purpose | When to Use |
|-------------|---------|-------------|
| `Metal` / `MTLDevice` | Hardware-accelerated texture compositing | If Core Image proves too slow under Instruments profiling on iPhone XR |
| `UIApplication.beginBackgroundTask` | Extend background execution time for finalization | Always — required for D-06 interruption handling |
| `NotificationCenter` | `AVCaptureSessionWasInterruptedNotification`, `didEnterBackgroundNotification` | Required for D-06 auto-stop on interruption |
| `CMTime` | Presentation timestamp management | Required for sample buffer timing |

[VERIFIED: Apple documentation, WWDC 2019 session 249 transcripts]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Core Image compositor | Metal compute shader | Metal is more efficient but requires GLSL/MSL authoring; CI sufficient for 30fps 1080p |
| `AVAssetWriterInputPixelBufferAdaptor` | Direct `CMSampleBuffer` passthrough | Adaptor required because compositor produces raw `CVPixelBuffer`, not `CMSampleBuffer` |
| Single blended audio output | Two separate `AVAssetWriterInput` audio tracks | Two-track approach deferred per project requirements |

**Installation:** No new dependencies — all APIs are built into the iOS SDK.

---

## Architecture Patterns

### Recommended Project Structure

```
DualVideo/Features/Recording/
├── PiPCompositor.swift        # AVCaptureVideoDataOutputSampleBufferDelegate, Core Image pipeline
├── MovieRecorder.swift        # AVAssetWriter state machine + audio track
├── RecordingManager.swift     # Coordinates compositor + recorder + interruption handling
DualVideo/Features/Camera/
├── CameraManager.swift        # (existing) — Phase 2 adds delegate wiring in startSession()
DualVideo/Shared/
├── AppState.swift             # (existing) — RecordingState enum added here or in RecordingManager
DualVideo/Features/Recording/UI/
├── RecordButton.swift         # SwiftUI bottom-center Record/Stop button (D-02)
├── RecordingStatusOverlay.swift # Blinking red dot + MM:SS timer (D-03)
```

### Pattern 1: Core Image PiP Compositor

**What:** `PiPCompositor` implements `AVCaptureVideoDataOutputSampleBufferDelegate` for both the back and front `AVCaptureVideoDataOutput`. It holds the latest `CVPixelBuffer` from each camera (front, back), and on each back-camera frame it composites both into a 1920×1080 output buffer using Core Image.

**When to use:** Primary implementation. Core Image's `CISourceOverCompositing` handles alpha blending; `CILanczosScaleTransform` handles front-camera downscale to PiP dimensions. `CIContext` (Metal-backed) renders the composited image into an output `CVPixelBuffer` from the adaptor's pool.

**Thread-safety for PiP offset (D-01 + specifics note):**
`PiPOverlayState.offset` is an `@Observable` main-thread property. The compositor runs on `dataOutputQueue`. The safe pattern is to snapshot the offset on main at each frame via a `@MainActor`-isolated property that is read atomically from `dataOutputQueue` using a cached value updated on main:

```swift
// [ASSUMED] — pattern consistent with established CameraManager threading model
// Snapshot offset on main; compositor reads cached value on dataOutputQueue
@MainActor private var cachedPiPOffset: CGSize = .zero

// On dataOutputQueue, compositor reads:
let offset = pipOffsetSnapshot  // nonisolated(unsafe) copy updated from main
```

Alternatively: protect with a `OSAllocatedUnfairLock` or read via `DispatchQueue.main.sync` (safe from dataOutputQueue, not from main itself).

**Example — Core Image compositor kernel:**

```swift
// Source: Core Image documentation + CISourceOverCompositing filter reference [ASSUMED pattern]
func composite(back: CVPixelBuffer, front: CVPixelBuffer, pipRect: CGRect) -> CVPixelBuffer? {
    let backCI = CIImage(cvPixelBuffer: back)
    let frontCI = CIImage(cvPixelBuffer: front)

    // Scale front camera to PiP size
    let scaleX = pipRect.width / CGFloat(CVPixelBufferGetWidth(front))
    let scaleY = pipRect.height / CGFloat(CVPixelBufferGetHeight(front))
    let scaledFront = frontCI
        .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        .transformed(by: CGAffineTransform(translationX: pipRect.minX, y: pipRect.minY))

    // Composite: front over back
    let compositor = CIFilter(name: "CISourceOverCompositing")!
    compositor.setValue(scaledFront, forKey: kCIInputImageKey)
    compositor.setValue(backCI, forKey: kCIInputBackgroundImageKey)
    let output = compositor.outputImage!

    // Render to pooled output buffer
    guard let outBuffer = acquireOutputBuffer() else { return nil }
    ciContext.render(output, to: outBuffer)
    return outBuffer
}
```

**CIContext creation — create once, reuse:**

```swift
// [ASSUMED] — standard iOS pattern; creating CIContext per frame is a known pitfall
let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
```

### Pattern 2: AVAssetWriter State Machine

**What:** `MovieRecorder` owns an `AVAssetWriter`, a video `AVAssetWriterInput`, an `AVAssetWriterInputPixelBufferAdaptor`, and an audio `AVAssetWriterInput`. It transitions through `.idle → .starting → .recording → .finalizing → .idle`.

**State enum:**

```swift
// Source: [VERIFIED: established pattern from gist.github.com/yusuke024/b5cd3909d9d7f9e919291491f6b381f0]
private enum RecordingState {
    case idle
    case starting      // writer created, not yet started
    case recording     // actively appending buffers
    case finalizing    // finishWriting() called, awaiting completion
}
```

**Key rules:**
- `startWriting()` + `startSession(atSourceTime:)` called once when first video frame arrives in `.starting` state.
- All appends guarded by: `state == .recording && writerInput.isReadyForMoreMediaData && writer.status == .writing`.
- `finishWriting(completionHandler:)` is asynchronous and non-blocking; call on `dataOutputQueue` or dedicated queue, never main.
- Do NOT call `endSessionAtSourceTime` — calling `finishWriting` without it is valid; the system uses the last sample's timestamp. [VERIFIED: Apple documentation]

**Output file settings (Claude's Discretion):**

```swift
// [ASSUMED] — verified pattern is to use recommendedVideoSettingsForAssetWriter, then override
var videoSettings = backVideoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov) ?? [:]
// Override bitrate if desired; Apple's recommended settings produce ~8–12 Mbps H.264 for 1080p [ASSUMED]

let audioSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVNumberOfChannelsKey: 2,
    AVSampleRateKey: 44100.0,
    AVEncoderBitRateKey: 128_000
]
```

### Pattern 3: Dual-Mic Audio in AVCaptureMultiCamSession

**What:** Add one `AVCaptureDeviceInput` for the built-in microphone. Retrieve front-beam and back-beam ports via `ports(for:sourceDeviceType:sourceDevicePosition:)`. Connect each to a separate `AVCaptureAudioDataOutput` (or connect both to one output). Delegate callbacks deliver beam-formed audio sample buffers.

**WWDC 2019 session 249 pattern (conceptual):**

```swift
// [CITED: asciiwwdc.com/2019/sessions/249]
// One microphone input, two audio data outputs
let micDevice = AVCaptureDevice.default(for: .audio)!
let micInput = try! AVCaptureDeviceInput(device: micDevice)
session.addInputWithNoConnections(micInput)

let backAudioOutput = AVCaptureAudioDataOutput()
let frontAudioOutput = AVCaptureAudioDataOutput()
session.addOutputWithNoConnections(backAudioOutput)
session.addOutputWithNoConnections(frontAudioOutput)

// Retrieve beam ports by position
if let backPort = micInput.ports(for: .audio,
    sourceDeviceType: micDevice.deviceType,
    sourceDevicePosition: .back).first {
    session.addConnection(AVCaptureConnection(inputPorts: [backPort], output: backAudioOutput))
}
if let frontPort = micInput.ports(for: .audio,
    sourceDeviceType: micDevice.deviceType,
    sourceDevicePosition: .front).first {
    session.addConnection(AVCaptureConnection(inputPorts: [frontPort], output: frontAudioOutput))
}
```

**Blend strategy (D-05):** Rather than implementing a custom mix, pass both audio sample buffers to the **same `AVAssetWriterInput`** (or interleave them via `AVMutableAudioMix` in post). The simpler on-capture approach is to pick the back-mic beam as primary and front-beam as secondary, mixing via a simple additive mix before appending — or simply route only one beam and treat dual-mic as best-effort. This is Claude's Discretion (D-05 says "let AVFoundation blend them"). [ASSUMED — needs validation on iPhone XR]

**Known iOS 16.1+ issue:** Setting `session.usesApplicationAudioSession = true` and `automaticallyConfiguresApplicationAudioSession = false` on `AVCaptureMultiCamSession` can cause silent audio frames from both mics. The safe fallback is `automaticallyConfiguresApplicationAudioSession = true` (the default), which means AVFoundation manages the audio session. If dual-beam doesn't deliver samples on device, fall back to single back-mic beam. [CITED: developer.apple.com/forums/thread/717645 — content not directly verified due to JS-rendered page; MEDIUM confidence]

### Pattern 4: Interruption / Background Finalization (D-06)

```swift
// [ASSUMED pattern — consistent with Apple's beginBackgroundTask documentation]
func handleInterruption() {
    let bgTask = UIApplication.shared.beginBackgroundTask(withName: "finalize-recording") {
        // Expiration handler — called if 30-second budget exhausted
        self.movieRecorder.cancelAndDiscard()
        UIApplication.shared.endBackgroundTask(self.bgTaskID)
    }
    self.bgTaskID = bgTask
    movieRecorder.stopAndFinalize { [weak self] url in
        // url is valid partial-but-finalized .mov file
        self?.recordingManager.pendingFileURL = url
        UIApplication.shared.endBackgroundTask(bgTask)
    }
}
```

Subscribe to:
- `UIApplication.didEnterBackgroundNotification` — backgrounding
- `AVCaptureSession.wasInterruptedNotification` — phone call, FaceTime, etc.

### Anti-Patterns to Avoid

- **Creating `CIContext` per frame:** Extremely expensive — creates GPU resources every frame. Create once and reuse. [VERIFIED: Core Image documentation and known pitfall]
- **Appending without `isReadyForMoreMediaData` check:** Causes dropped frames or crashes — always guard appends. [VERIFIED: AVAssetWriterInput documentation]
- **Calling `finishWriting()` synchronously from the main thread:** Blocks UI; can cause finalization failure. Always call async or from `dataOutputQueue`. [VERIFIED: Apple documentation note + forum thread]
- **Reading `hardwareCost` before `commitConfiguration()`:** Gives stale value. (Already handled in Phase 1 `CameraManager`.)
- **Using `requestMediaDataWhenReady` with push-style sources:** Designed for pull-style `AVAssetReaderOutput`. Use direct append in delegate callbacks for `AVCaptureVideoDataOutput`. [VERIFIED: AVAssetWriterInput documentation]
- **Starting `AVAssetWriter` on main thread:** Use `sessionQueue` or `dataOutputQueue`. Never start on main.
- **Not setting `expectsMediaDataInRealTime = true`** on writer inputs: Required for live capture to avoid buffer accumulation.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Frame compositing | Custom pixel copy loop | `CISourceOverCompositing` + `CIContext` | CPU copy at 1080p/30fps will miss frame budget; CI is GPU-backed |
| H.264 encoding | Custom bitstream writer | `AVAssetWriterInput` with H.264 settings | Encoder handles keyframes, B-frames, CABAC — enormous complexity |
| AAC audio encoding | Custom codec wrapper | `AVAssetWriterInput` with AAC settings | Same as above; hardware codec available via AVFoundation |
| Audio mixing | Custom DSP mixer | AVFoundation audio beam forming | Beam forming is hardware/DSP-assisted; cannot replicate in pure Swift |
| Presentation timestamps | Manual clock | `CMSampleBuffer.presentationTimeStamp` from capture output | Capture-derived timestamps are already monotonic and correct |
| Background task management | Custom timer | `UIApplication.beginBackgroundTask` | OS-managed 30-second budget with expiration callback |

**Key insight:** Every component in this stack is a correctness problem, not just a performance problem. H.264 encoding, AAC muxing, and timestamp management all have specification-mandated behaviors that hand-rolled code will get wrong in edge cases.

---

## Common Pitfalls

### Pitfall 1: PiP Offset Thread Safety

**What goes wrong:** Compositor (on `dataOutputQueue`) reads `PiPOverlayState.offset` (a `@Observable` main-thread property), causing a Swift 6 data race warning or undefined behavior.

**Why it happens:** `@Observable` properties are not inherently thread-safe; accessing from `dataOutputQueue` violates actor isolation.

**How to avoid:** Maintain a `nonisolated(unsafe) var pipOffsetSnapshot: CGSize = .zero` on the compositor, updated from main via `DispatchQueue.main.async` whenever `PiPOverlayState.offset` changes. The compositor reads `pipOffsetSnapshot` on `dataOutputQueue` — safe because one-directional writes from main, reads from data queue (stale by at most one frame, which is acceptable).

**Warning signs:** Swift 6 concurrency warning on `pipState.offset` access from background queue.

### Pitfall 2: AVAssetWriter Status After Error

**What goes wrong:** Writer enters `.failed` state after a frame append error; subsequent appends silently drop or crash. Recording appears to work but produces a corrupt/empty file.

**Why it happens:** `appendSampleBuffer` returns `false` on failure; code ignores return value; writer transitions to `.failed` silently.

**How to avoid:** Check `writer.status` after every failed append. Log `writer.error` on failure. In `.failed` state, call `cancelWriting()` and surface error to user. Never treat `appendSampleBuffer` returning `false` as benign.

**Warning signs:** Output `.mov` plays but has no video track, or file is 0 bytes.

### Pitfall 3: First Frame Timestamp Drift

**What goes wrong:** `startSession(atSourceTime:)` called with `.zero` or an incorrect timestamp causes A/V sync issues in the output file — audio and video drift apart.

**Why it happens:** The source time establishes the clock origin for the session. Using `.zero` when the actual first sample has a different presentation timestamp causes a mismatch.

**How to avoid:** Call `startSession(atSourceTime: firstSampleBuffer.presentationTimeStamp)` using the actual first video sample's PTS. [VERIFIED: AVAssetWriter documentation — startSessionAtSourceTime sets the clock origin]

**Warning signs:** Audio and video play out of sync in the recorded `.mov`.

### Pitfall 4: Compositor Frame Drop on A12 (iPhone XR)

**What goes wrong:** Core Image compositor takes > 33ms (at 30fps) per frame, causing `alwaysDiscardsLateVideoFrames = true` to drop frames, resulting in choppy output video.

**Why it happens:** A12 (iPhone XR) has less GPU headroom than newer devices. CIContext creation per frame, or blocking the `dataOutputQueue` with CI rendering, can exceed the budget.

**How to avoid:** Create `CIContext` once with `[.useSoftwareRenderer: false]`. Render to pixel buffers from `pixelBufferPool` (avoid `CVPixelBufferCreate` per frame). Profile on iPhone XR early. If still slow, switch to Metal.

**Warning signs:** Instruments shows `dataOutputQueue` busy > 30ms per frame callback.

### Pitfall 5: Audio from Both Mics Silently Drops (iOS 16.1+)

**What goes wrong:** Adding two `AVCaptureAudioDataOutput` instances with front/back beam ports produces silent audio samples for one or both beams on iOS 16.1+.

**Why it happens:** Known AVCaptureMultiCamSession bug related to `usesApplicationAudioSession` interaction. [CITED: developer.apple.com/forums/thread/717645 — MEDIUM confidence, JS-rendered forum content]

**How to avoid:** Validate on device early (Plan 02-02 should include a validation step). Fallback: single back-mic beam only, dropped to one `AVCaptureAudioDataOutput`.

**Warning signs:** Audio sample buffers delivered but `CMSampleBufferGetDataBuffer` returns nil or zero-amplitude PCM.

### Pitfall 6: finishWriting Called Without startWriting

**What goes wrong:** If recording is stopped before the first frame arrived (e.g., user taps record then immediately stop), `finishWriting` is called on a writer that was never started, causing a crash or undefined behavior.

**Why it happens:** State machine transitions to `.finalizing` without verifying `.starting → .recording` completed.

**How to avoid:** In `.starting` state on stop: cancel and discard; never finalize a writer that never called `startWriting`. Use explicit state checks before finalization.

---

## Code Examples

### AVAssetWriter Setup

```swift
// [ASSUMED — standard pattern verified against Apple documentation and community gists]
// Create writer targeting temp directory
let outputURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .appendingPathExtension("mov")

let writer = try AVAssetWriter(url: outputURL, fileType: .mov)

// Video input — use recommended settings, then override
var videoSettings = backVideoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov) ?? [:]
let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
videoInput.expectsMediaDataInRealTime = true
videoInput.transform = .identity  // adjust for device orientation if needed

// Pixel buffer adaptor — use same pixel format as compositor output
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: videoInput,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 1920,
        kCVPixelBufferHeightKey as String: 1080
    ]
)

// Audio input
let audioSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVNumberOfChannelsKey: 2,
    AVSampleRateKey: 44100.0,
    AVEncoderBitRateKey: 128_000
]
let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
audioInput.expectsMediaDataInRealTime = true

writer.add(videoInput)
writer.add(audioInput)
writer.startWriting()
// Do NOT call startSession here — call on first sample buffer
```

### First Frame Start Pattern

```swift
// [ASSUMED — pattern from gist.github.com/yusuke024/b5cd3909d9d7f9e919291491f6b381f0]
func captureOutput(_ output: AVCaptureOutput,
                   didOutput sampleBuffer: CMSampleBuffer,
                   from connection: AVCaptureConnection) {
    guard state == .recording || state == .starting else { return }

    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

    if state == .starting {
        writer.startSession(atSourceTime: pts)  // use actual first PTS, not .zero
        state = .recording
    }

    guard writer.status == .writing,
          videoInput.isReadyForMoreMediaData else { return }

    if let pixelBuffer = compositeFrame(from: sampleBuffer) {
        adaptor.append(pixelBuffer, withPresentationTime: pts)
    }
}
```

### Finalization with Background Task

```swift
// [ASSUMED — consistent with UIApplication.beginBackgroundTask documentation]
func stopRecording(completion: @escaping (URL?) -> Void) {
    guard state == .recording else { completion(nil); return }
    state = .finalizing

    let bgTask = UIApplication.shared.beginBackgroundTask(withName: "finalize-recording") {
        // Budget exhausted — cancel to avoid corruption
        self.writer?.cancelWriting()
        UIApplication.shared.endBackgroundTask(.invalid)
    }

    videoInput.markAsFinished()
    audioInput.markAsFinished()

    writer.finishWriting { [weak self] in
        guard let self else { return }
        let url: URL? = self.writer.status == .completed ? self.outputURL : nil
        self.state = .idle
        UIApplication.shared.endBackgroundTask(bgTask)
        completion(url)
    }
}
```

### Recording State Model (AppState extension)

```swift
// [ASSUMED — consistent with established AppState @Observable pattern]
enum RecordingPhase {
    case idle
    case recording(startedAt: Date)
    case finalizing
}

// Added to AppState or RecordingManager
@Observable
final class RecordingManager {
    var phase: RecordingPhase = .idle
    var pendingFileURL: URL? = nil
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `AVCaptureMovieFileOutput` for recording | `AVAssetWriter` + `AVCaptureVideoDataOutput` | iOS 13+ MultiCam era | `AVCaptureMovieFileOutput` cannot be used with `AVCaptureMultiCamSession`; custom writer required |
| `@preconcurrency` for delegate conformance | `nonisolated func` delegate methods | Swift 6 | Explicit nonisolation is safer; avoids suppressing concurrency checks |
| Creating CIContext with software renderer | Metal-backed `CIContext` (default on iOS) | iOS 8+ | Hardware acceleration; `useSoftwareRenderer: false` is the default |
| `finishWriting()` (synchronous, deprecated) | `finishWriting(completionHandler:)` | iOS 6+ | Non-blocking; required for responsive UI during finalization |

**Deprecated/outdated:**
- `AVCaptureMovieFileOutput`: Cannot be added to `AVCaptureMultiCamSession`. [VERIFIED: AVCaptureMultiCamSession documentation] Do not use.
- `endSessionAtSourceTime`: Optional; not required before `finishWriting`. Calling it is harmless but unnecessary. [VERIFIED: Apple documentation]
- `CIContext(options: [.workingColorSpace: nil])`: Avoid nil color space — pass an explicit color space or use the default.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | PiP offset snapshot pattern (nonisolated copy updated from main) is safe and sufficient | Architecture Patterns — Pattern 1 | Minor: might need OSAllocatedUnfairLock or different sync primitive |
| A2 | `recommendedVideoSettingsForAssetWriter` produces ~8–12 Mbps H.264 for 1080p | Standard Stack | Low: actual bitrate may differ; easily adjusted |
| A3 | Single `AVCaptureAudioDataOutput` connected to both beam ports will deliver blended audio | Pattern 3 | HIGH if wrong: audio may be mono-sourced or silent; needs device validation |
| A4 | iOS 16.1+ dual-mic silent audio bug is still present in iOS 18 | Pitfall 5 | MEDIUM: may have been fixed; must test on iPhone XR running iOS 18 |
| A5 | CIContext compositor will meet 33ms/frame budget on iPhone XR at 1080p/30fps | Pitfall 4 | HIGH if wrong: will need Metal compositor, adding significant implementation complexity |
| A6 | `beginBackgroundTask` provides ~30 seconds for finalization | Code Examples — Finalization | Low: 30 seconds is documented; finalization of a few minutes of video should complete in < 5s |
| A7 | `nonisolated func` delegate methods in `PiPCompositor` and `MovieRecorder` are sufficient for Swift 6 compliance | Architecture | Low: consistent with cited Swift 6 refactoring article; established pattern |

---

## Open Questions

1. **Does dual-mic audio work on iPhone XR + iOS 18?**
   - What we know: WWDC 2019 introduced multi-beam audio for `AVCaptureMultiCamSession`; iOS 16.1 introduced a regression; unclear if iOS 18 fixes it.
   - What's unclear: Current behavior on the primary test device.
   - Recommendation: Plan 02-02 must include an explicit device-validation step for audio — record 10 seconds and inspect waveform in QuickTime. Have single-mic fallback coded.

2. **Will Core Image meet 33ms/frame on iPhone XR?**
   - What we know: A12 has adequate GPU for most CI workloads; 1080p PiP compositing is modest (one scale + one composite).
   - What's unclear: Actual frame time under `AVCaptureMultiCamSession` load (both cameras + composer + writer active simultaneously).
   - Recommendation: Profile on device in Plan 02-01. If > 25ms average, switch compositor to Metal immediately — don't wait for end-to-end integration.

3. **Does `AVCaptureMultiCamSession` affect `hardwareCost` after adding audio inputs?**
   - What we know: Phase 1 validates `hardwareCost < 0.9` after video-only configuration.
   - What's unclear: Whether adding audio outputs increases `hardwareCost` significantly.
   - Recommendation: Re-read `hardwareCost` after audio inputs are added in Plan 02-02. Log the value.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Physical iPhone XR | All camera/audio features | ✓ (per PROJECT.md) | A12, iOS 18 | None — Simulator has no camera |
| Xcode | Build and deploy | ✓ (per PROJECT.md) | Current | None |
| AVFoundation | Core recording pipeline | ✓ (iOS 18.0+) | iOS 18 | None — built-in |
| Metal | Optional CI acceleration / fallback compositor | ✓ (A12+) | Built-in | Core Image (primary) |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (built into Xcode) |
| Config file | Xcode scheme — no external config file |
| Quick run command | `xcodebuild test -scheme DualVideo -destination 'platform=iOS Simulator,name=iPhone 16'` (unit tests only; camera tests require device) |
| Full suite command | Run on physical device: `xcodebuild test -scheme DualVideo -destination 'id=<device-udid>'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CAP-04 | Elapsed timer increments from 0 after Record tap | Unit | `xcodebuild test -only-testing:DualVideoTests/RecordingManagerTests` | ❌ Wave 0 |
| REC-01 | RecordingState transitions idle→recording→idle on start/stop | Unit | `xcodebuild test -only-testing:DualVideoTests/RecordingManagerTests` | ❌ Wave 0 |
| REC-02 | PiP compositor output pixel buffer is non-nil for synthetic inputs | Unit | `xcodebuild test -only-testing:DualVideoTests/PiPCompositorTests` | ❌ Wave 0 |
| REC-03 | Output `.mov` file exists and is playable (non-zero duration) | Integration/Manual | Record on device, verify in Photos / QuickTime | Manual only (requires camera) |
| REC-04 | Finalize called on background notification; file URL non-nil after finalize | Unit (mock writer) | `xcodebuild test -only-testing:DualVideoTests/MovieRecorderTests` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** Unit test suite (`DualVideoTests` target, simulator)
- **Per wave merge:** Full unit suite + manual on-device smoke test: record 10 seconds, verify `.mov` plays
- **Phase gate:** All unit tests green + manual device validation of valid output file before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `DualVideoTests/PiPCompositorTests.swift` — covers REC-02 (compositor with synthetic CVPixelBuffers)
- [ ] `DualVideoTests/RecordingManagerTests.swift` — covers CAP-04 (timer), REC-01 (state transitions)
- [ ] `DualVideoTests/MovieRecorderTests.swift` — covers REC-04 (finalization under mock interruption)

*(No framework install needed — XCTest is available in Xcode project)*

---

## Security Domain

Phase 2 involves no authentication, sessions, user credentials, or network access. The only security-relevant surface is the temporary file written to `FileManager.default.temporaryDirectory`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | Minimal | Validate `writer.status` and `isReadyForMoreMediaData` before appends |
| V6 Cryptography | No | No encryption required for local temp file |

### Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Temp file persists if crash before finalize | Information disclosure | Use `FileManager` to clean up orphaned temp files on app launch |
| Invalid pixel buffer passed to adaptor | Tampering/crash | Guard with `isReadyForMoreMediaData` and nil checks |

---

## Sources

### Primary (HIGH confidence)
- `DualVideo/Features/Camera/CameraManager.swift` — existing threading model, queue names, `nonisolated(unsafe)` pattern
- `DualVideo/.planning/phases/02-recording-pipeline-compositor-writer-audio/02-CONTEXT.md` — locked decisions
- Apple AVAssetWriterInput documentation — `isReadyForMoreMediaData`, `expectsMediaDataInRealTime`, `appendSampleBuffer`
- Apple AVAssetWriter documentation — `finishWriting(completionHandler:)`, `startSession(atSourceTime:)`
- Apple AVAssetWriterInputPixelBufferAdaptor documentation — `append(_:withPresentationTime:)`, `pixelBufferPool`
- WWDC 2019 Session 249 transcript (asciiwwdc.com/2019/sessions/249) — dual-mic beam forming in AVCaptureMultiCamSession

### Secondary (MEDIUM confidence)
- fatbobman.com: "Swift 6 Refactoring in a Camera App" — `nonisolated func` delegate pattern, GlobalActor for AVFoundation
- gist.github.com/yusuke024 — AVAssetWriter recording state machine pattern
- Apple Developer Forums thread/717645 — iOS 16.1 dual-mic regression (content not directly verified due to JS-rendered page)

### Tertiary (LOW confidence)
- General web search results on CISourceOverCompositing, Core Image PiP — consistent with Apple docs but not directly verified against iOS 18 specifically

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are long-established AVFoundation; Phase 1 already uses the session
- Architecture patterns: MEDIUM-HIGH — patterns are well-known; PiP offset thread safety approach is assumed but consistent with codebase
- Dual-mic audio: MEDIUM — WWDC 2019 shows the pattern; iOS 16.1+ regression is real and may affect iOS 18; needs device validation
- Core Image compositor performance on A12: MEDIUM — adequate in theory; unknown without profiling
- Pitfalls: HIGH — all documented from Apple sources or established community knowledge

**Research date:** 2026-05-17
**Valid until:** 2026-06-17 (stable APIs; AVFoundation changes slowly; dual-mic issue may change with iOS updates)
