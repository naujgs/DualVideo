# Features Research — DualVideo

**Domain:** iOS dual-camera simultaneous recording app (personal use, PiP compositor)
**Researched:** 2026-05-16
**Confidence:** MEDIUM-HIGH (iOS 18 API behavior verified; competitor feature sets from App Store listings and reviews, MEDIUM confidence)

---

## Table Stakes

Features users expect when they open any dual-camera recording app. Absence causes immediate abandonment or a 1-star review.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Live preview of both cameras simultaneously | Core premise — if you can't see what you're recording, the app is broken | Low | `AVCaptureMultiCamSession` handles this natively |
| Single tap to start/stop recording | Every camera app works this way; two separate buttons would feel broken | Low | Already in requirements |
| Result saved to Photos automatically | Users expect no manual export step; Files/iCloud storage feels like friction | Low | `PHPhotoLibrary` save; already in requirements |
| Elapsed recording time display | Users need to know how long they've been recording — no counter = anxiety | Low | Red dot + `MM:SS` counter; standard HIG pattern |
| Microphone permission prompt with explanation | iOS will reject the app silently otherwise; users also distrust apps that don't explain | Low | `NSMicrophoneUsageDescription` in Info.plist |
| Camera permission prompt with explanation | Same as above — required by system | Low | `NSCameraUsageDescription` |
| Photo Library permission prompt with explanation | Required to save output | Low | `NSPhotoLibraryAddUsageDescription` |
| Graceful "permissions denied" state | If any permission is denied, the app must explain what's broken and how to fix it (Settings deep-link) | Low | Tapping the message should open `UIApplication.openSettingsURLString` |
| Graceful "hardware not supported" state | A12 requirement means some users will hit this; silent crash = very bad | Low | Detect `AVCaptureMultiCamSession.isMultiCamSupported` before session setup |
| Countdown before recording starts | Standard pattern on every camera app with a timer; 3 s is the community norm. Without it, users miss the first second | Low | Already in requirements |
| Pinch-to-zoom on back camera | iOS Camera does this; users muscle-memory it | Low | Already in requirements |
| PiP overlay draggable to reposition | iPhone 17 native Dual Capture and every third-party app (DualCapture, MixCam, 2Camera) all do this | Medium | Already in requirements |
| Output as a single merged video file | Split-file output (separate front/back) is a differentiator, not table stakes for personal use | Low | Already in requirements |

---

## Differentiators

Features that move the app from "functional" to "notably better." Not universally expected, but add real value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Corner snapping for PiP overlay | Apple's own Dual Capture on iPhone 17 does NOT snap; it just lets you drag freely. A snap-to-corner behavior during drag reduces accidental mid-frame placement and makes the result look polished. MixCam and DualCapture offer 4-corner presets | Medium | Implement as UIKit gesture recognizer releasing to nearest corner; can use `UISnapBehavior` or manual threshold logic |
| Haptic feedback on record start/stop | DualCapture explicitly markets "perfected haptics." Most camera apps ignore this. Gives tactile confirmation that the session actually started — critical when holding phone at arm's length | Low | Use `UIImpactFeedbackGenerator(.medium)` on record start, `.heavy` on stop. Note: call `setAllowHapticsAndSystemSoundsDuringRecording(true)` on `AVAudioSession` to prevent haptic suppression |
| Audio level indicator during recording | Shows the user that both mics are picking up sound. Differentiates from apps that give no audio feedback whatsoever | Medium | `AVAudioSession.inputNode` metering; visualize as a simple VU bar on the PiP overlay or toolbar |
| Persistent PiP position across sessions | If the user always wants the front camera in the top-right, they should only position it once. No competitor documents this behavior | Low | `UserDefaults` store of last CGPoint; restore on launch |
| Orientation lock toggle | Final Cut Camera has it; the native Camera app lacks it. For walking or talking vlog-style content, screen rotation mid-recording is disorienting | Low | `AppDelegate.supportedInterfaceOrientations` + UI toggle; lock to current orientation on tap |
| Visible zoom level indicator | Apple Camera shows `0.5×`, `1×`, `2×` labels. Users want to know what zoom they're at, not just pinch blindly | Low | Bind to `AVCaptureDevice.videoZoom­Factor`; display as `1.0×` label near the back camera preview |
| Flash / torch toggle for video | Expected on any night/indoor capture scenario. DualCapture and 2Camera both include it | Low | `AVCaptureDevice.torchMode`; show a flash icon that toggles `.on`/`.off` |

---

## Anti-Features (v1)

Deliberately excluded. Not worth the build cost for personal use or actively harmful to UX.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Split-screen layout option (50/50) | DoubleTake and DualCapture offer this. For DualVideo the PiP-with-draggable-overlay is the entire product thesis; adding layout modes adds picker UI and doubles compositor complexity | Hard-code PiP; back camera is always fullscreen |
| Camera swap (front becomes background) | Already listed in PROJECT.md as out of scope. Flipping the compositor requires re-wiring the entire `AVAssetWriter` pipeline. Large complexity, low personal value | Static layout: back = background, front = overlay |
| Separate file export (front + back as individual files) | DualCapture differentiates on this. For personal use a single merged file is the correct output — Photos handles it, AirDrop handles it | Single `.mov` only |
| 4K output | Already out of scope per PROJECT.md. 4K files on a personal device fill storage quickly and have no playback advantage on most screens. Dual 4K streams saturate even A15 thermal budget | 1080p only |
| Video trimming in-app | Photos.app does this. Building an editor is a separate product | Let Photos handle it |
| Filters / color grading | BeReal's stripped-down UX is a feature, not a bug. For personal documentary use, authentic > pretty | No filters |
| Social sharing / upload integration | Cloud sync explicitly out of scope per PROJECT.md | Save to Photos; user shares from there |
| Pause and resume recording | Adds session state complexity (pause = stop + restart + stitch?). No user story for this in personal use | Single continuous take only |
| Multiple PiP sizes / resize handles | DualCapture offers this but reviews cite it as complexity people don't use. Draggable position is enough | Fixed PiP size (approx 25-30% of screen width) |
| Watermarks / branding | Personal use; watermarks are for content creator monetization | No watermark |
| Subscription / paywall | Personal side-load; no commerce infrastructure needed | Free, no IAP |

---

## UX Patterns

Common patterns observed across comparable apps (BeReal, DoubleTake, DualCapture, MixCam, iPhone 17 native Dual Capture).

### PiP Overlay Drag Behavior

- All apps allow drag-to-reposition during live preview AND during recording. The iPhone 17 native Dual Capture explicitly warns users that repositioning during recording is permanent in the output — the same is true for DualVideo since compositing is real-time.
- Corner snapping: DualCapture uses 4-corner presets (tap to cycle). Apple's Dual Capture does NOT snap — free placement only. MixCam allows free placement with no snap. Snapping is a differentiator, not table stakes.
- Safe area: PiP overlay must not occlude the record button. Prevent dragging into the bottom ~100pt (safe area + controls) or implement collision detection with the record button.

### Recording State Feedback

- Red dot + elapsed timer (`00:00`) in top-right or center-top is universal across iOS camera apps (Apple Camera, FiLMiC, DualCapture). Users look for this automatically.
- The record button itself visually changes state: circle → square (stop icon), often with a red fill pulse. Apple HIG documents this as the expected pattern.
- Haptic on start/stop is a differentiator today but will become table stakes quickly given DualCapture's marketing emphasis on it.
- Audio waveform (full waveform animation): used in Waveform Camera (niche pro app) but not standard in consumer dual-cam apps. A simple VU bar or peak indicator is sufficient and far less complex.

### Countdown Timer Pattern

- Standard countdown display: large centered number, counts down 3... 2... 1... then transitions to recording state.
- Flash/blink of the number on each tick is common (Apple Camera does this).
- Cancelable: tapping anywhere during countdown cancels it. This is the Apple HIG expectation.
- Audio tick sound: Apple Camera plays a tick; for a personal app this is optional but expected. Can use system sound `AudioServicesPlaySystemSound(1057)` (camera shutter beep family).

### Permission UX

- Best practice (NNGroup + Apple HIG): show a custom pre-permission dialog BEFORE triggering the system prompt. Explain benefit clearly: "To record video, DualVideo needs access to your cameras and microphones."
- Never ask for all permissions at launch. Ask for camera + microphone together at first camera preview attempt (they're coupled). Ask for Photos access only when the user stops a recording and the save is about to happen.
- Denial handling: show a non-dismissable overlay with a "Go to Settings" button that deep-links to `UIApplication.openSettingsURLString`. Do not show a generic alert — show exactly which permission is missing and what it enables.

### Post-Recording Flow

- Apple's Dual Capture, DualCapture, and MixCam all follow the same pattern: record → stop → auto-save to Photos → brief toast/confirmation. There is NO preview-before-save step in any of these apps.
- Preview-before-save adds complexity (requires `AVPlayer`, a second screen, explicit confirm/discard buttons) and is a friction point for personal documentary use where you always want the clip saved.
- Recommendation for DualVideo: auto-save on stop, show a brief success indicator (checkmark toast or green flash), no preview step. This matches the Apple native Dual Capture behavior exactly.

### Zoom Controls

- Pinch-to-zoom is universal and expected. The simultaneous pinch gesture on a touch screen does wobble the phone during video, but it is the only pattern users know.
- Displaying current zoom level as a label (e.g., `1.4×`) near the back camera preview prevents confusion and is shown in Apple Camera.
- Jumping to preset zoom levels (0.5×, 1×, 2×) via tap is an Apple Camera pattern. For v1, pinch + numeric display is sufficient; preset buttons can come later.

### Orientation and Layout

- All dual-camera apps default to portrait (9:16) for PiP/reaction-video use cases matching social media.
- Landscape mode is supported in DoubleTake and DualCapture but treated as secondary.
- For DualVideo (personal use, fullscreen back camera + overlay): portrait-first, and consider locking orientation once recording begins to prevent accidental rotations.

---

## Feature Dependencies

Which features require others to be implemented first.

```
AVCaptureMultiCamSession setup
    └── Hardware detection ("not supported" gate)
    └── Camera permission
    └── Microphone permission
        └── Live preview (back camera fullscreen + front camera feed)
            └── PiP overlay rendering (SwiftUI layer over preview)
                └── Drag-to-reposition gesture
                    └── Corner snapping
                    └── Persistent position (UserDefaults)
            └── Pinch-to-zoom (back camera)
            └── Zoom level label display
            └── Flash / torch toggle
            └── Orientation lock toggle
            └── Countdown timer UI
                └── Record button (start → countdown → recording)
                    └── Elapsed time display
                    └── Haptic feedback (start/stop)
                    └── AVAssetWriter compositor (pixel buffer pipeline)
                        └── Photos permission
                        └── Auto-save to Photos
                            └── Success toast
```

**Critical path for MVP:** Hardware detection → Permissions (camera + mic) → Live dual preview → Compositor pipeline → Record/stop → Auto-save.

Everything else (zoom label, haptics, corner snap, orientation lock, torch, persistent PiP position, audio VU indicator) can be layered on top of a working compositor.

---

## Sources

- [DualCapture: Dual Camera + PiP — App Store](https://apps.apple.com/us/app/dualcapture-dual-camera-pip/id6756251524)
- [DoubleTake by Filmic — App Store](https://apps.apple.com/us/app/doubletake-multicam-video/id1478041592)
- [iPhone 17 Dual Capture — MacRumors How-To](https://www.macrumors.com/how-to/iphone-17-dual-capture-video/)
- [Top 5 Dual Capture Video Apps for iPhone 17 — Mixcord](https://www.mixcord.co/blogs/content-creators/best-dual-capture-video-apps-iphone-17)
- [DoubleTake by Filmic review — Macworld](https://www.macworld.com/article/233916/doubletake-by-filmic-review.html)
- [MixCam: Front and Back Camera — App Store](https://apps.apple.com/us/app/mixcam-front-and-back-camera/id1477390597)
- [5 Ways Apps Ask for iOS Permissions — Medium / Product Breakdown](https://medium.com/product-breakdown/5-ways-to-ask-users-for-ios-permissions-a8e199cc83ad)
- [3 Design Considerations for Mobile Permission Requests — NNGroup](https://www.nngroup.com/articles/permission-requests/)
- [Haptic Feedback and AVAudioSession Conflicts in iOS — Medium](https://medium.com/@mi9nxi/haptic-feedback-and-avaudiosession-conflicts-in-ios-troubleshooting-recording-issues-666fae35bfc6)
- [iPhone 17 All Models Get Dual Capture — 9to5Mac](https://9to5mac.com/2025/09/10/iphone-17-video-dual-cam-recording/)
