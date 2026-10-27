# Native macOS screen recording research

Researched 2026-10-27 against Apple documentation, WWDC24, and the installed Xcode SDK headers.

## Recommendation

Use **Swift + AppKit + ScreenCaptureKit**, targeting **macOS 15+**. Record straight to **H.264 MP4** with `SCRecordingOutput`. This is a supported native path; ffmpeg is unnecessary.

Apple's [WWDC24 ScreenCaptureKit session](https://developer.apple.com/videos/play/wwdc2024/10088/) introduces direct-to-file recording at 8:41 and walks through configuring the destination, file type, codec, and delegate callbacks. The installed `SCRecordingOutput.h` confirms availability starting in macOS 15.0, with H.264 and MPEG-4 as defaults.

## Recording and file readiness

1. Obtain the main display through `SCShareableContent` and construct a display `SCContentFilter`.
2. Configure an SDR `SCStream` with dimensions, cursor visibility, and a 30 fps maximum cadence.
3. Configure `SCRecordingOutputConfiguration` with the timestamped destination, `.mp4` file type, and `.h264` codec. Check reported format support at runtime.
4. Add the recording output **before** `startCapture()`, preserving the first sample.
5. On a stop request, call `stopCapture()` and wait for `recordingOutputDidFinishRecording`. Only that callback means the file is ready; then exit the app.

Apple explicitly describes the finish callback as the point at which recorded content is ready to use. MP4 still needs finalization, so “instant save” means a short container-finalization step rather than a second full encoding pass. A forced termination can damage an unfinished MP4.

The SDK also documents that changing an active stream's configuration stops its recording output. This first version fixes its display and configuration for the recording's lifetime.

Sources: [SCRecordingOutput](https://developer.apple.com/documentation/screencapturekit/screcordingoutput), [SCRecordingOutputConfiguration](https://developer.apple.com/documentation/screencapturekit/screcordingoutputconfiguration), [SCRecordingOutputDelegate](https://developer.apple.com/documentation/screencapturekit/screcordingoutputdelegate), and [Apple's recording demonstration and transcript](https://developer.apple.com/videos/play/wwdc2024/10088/).

## Minimal interface and global shortcut

AppKit's `NSStatusItem` provides a clickable menu bar item. `LSUIElement = true` makes the bundle an agent app with no Dock icon. A small non-template image preserves a red recording dot in either menu bar appearance; orange distinguishes startup and file finalization.

Use the system `RegisterEventHotKey` API for **Command + Option + Shift + S**. It registers a specific global shortcut rather than monitoring arbitrary keystrokes, and does not need an Accessibility event tap. Exclusive registration lets startup report a shortcut conflict before recording begins. Its virtual key code follows the physical ANSI S key position; non-QWERTY layouts may label that key differently.

Sources: [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem), [LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement), and the `RegisterEventHotKey` documentation in Apple's installed `CarbonEvents.h` SDK header.

## Permission and distribution constraints

macOS requires the user to authorize screen capture. The app checks with `CGPreflightScreenCaptureAccess`, requests with `CGRequestScreenCaptureAccess`, and explains how to grant access if capture is unavailable. It cannot promise immediate recording on the first launch or after permission is revoked. The operating system controls its additional capture indicators and reminders. Writing to Documents can separately trigger Files & Folders protection.

The app runs outside App Sandbox so it can use the requested fixed Documents destination. A sandboxed Mac App Store version would need a separate design for user-selected folder access and persistent security-scoped bookmarks.

Local development uses ad-hoc code signing with a stable bundle identifier. Reliable public binary distribution needs Developer ID signing and notarization; making the source repository public does not provide either.

Sources: [Apple's screen-recording privacy controls](https://support.apple.com/guide/mac-help/control-access-to-screen-and-system-audio-recording-mchld6aa7d23/mac), [CGPreflightScreenCaptureAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()), [CGRequestScreenCaptureAccess](https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess()), and [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Alternatives

- **macOS 12.3–14 support:** keep ScreenCaptureKit but send sample buffers to `AVAssetWriter` configured for `.mp4`. This also encodes during capture, but needs custom timestamp, backpressure, final-frame, and audio synchronization handling.
- **ffmpeg:** an optional fallback, with live H.264 encoding into MP4. It adds process lifecycle and dependency handling to an app that can already do this natively.
- **HEVC:** potentially smaller files, but H.264 is the conservative compatibility choice for sharing recordings.

Source for the older-native path: [AVAssetWriter](https://developer.apple.com/documentation/avfoundation/avassetwriter).
