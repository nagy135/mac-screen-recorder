# Mac Screen Recorder

A small native macOS menu bar app: open it to record, click the red dot or press **⌘⌥⇧S** to stop. The finished H.264 MP4 is saved in `~/Documents/Videos`, then the app quits.

No ffmpeg, conversion, countdown, recording window, Dock icon, or third-party dependencies.

## Use

Requires **macOS 15 or later**. Build with Xcode 16+ / Swift 6+ and its command line tools:

```sh
./scripts/build.sh
open "dist/Mac Screen Recorder.app"
```

You can copy `dist/Mac Screen Recorder.app` to `/Applications` or `~/Applications`. Choose its permanent location before granting screen-recording permission.

On first launch, allow **Screen & System Audio Recording** in System Settings → Privacy & Security. macOS may require you to quit and reopen the app after granting access. Documents access may also need approval. Later launches start recording as soon as macOS starts the capture stream.

- **Red dot:** recording. Click it (either mouse button) or press **Command + Option + Shift + S** anywhere to stop.
- **Orange dot:** starting or finalizing the MP4. A stop during startup cancels capture or stops it as soon as startup completes.
- **After saving:** the app quits automatically. Open it again for another recording.
- **Files:** local timestamps such as `2026-10-27_10-45-12-345.mp4`. Collisions receive `-2`, `-3`, etc.; existing videos are preserved.

The first version records the **main display and cursor**, with **no microphone or system audio**, at up to 30 fps in SDR. Retina resolution is preserved up to a 3840 × 2160 bounding box; larger, portrait, and ultrawide screens are scaled proportionally to fit. The menu bar is part of the captured display. macOS may also show its own capture indicator or permission reminders.

## How it saves MP4 directly

`SCStream` captures the display. On macOS 15+, `SCRecordingOutput` handles live encoding and file writing with `videoCodecType = .h264` and `outputFileType = .mp4`. It is attached **before** starting capture so the first frame is included.

Stopping calls `stopCapture()`. The app retains the capture objects until `recordingOutputDidFinishRecording`, which signals that the MP4 is ready. Finalization takes a short time; there is no post-recording transcode. Force Quit, a crash, or power loss can leave an incomplete MP4. On errors, any partial file is retained, and the app shows the error rather than claiming it saved successfully.

See [the research notes](docs/research.md) for API choices and Apple sources.

## Develop and verify

```sh
swift test
./scripts/build.sh
"dist/Mac Screen Recorder.app/Contents/MacOS/MacScreenRecorder" --check-permission
```

`--check-permission` prints the current permission status and exits without requesting access or recording. Permissions observed from a terminal can differ from a Finder launch; test the installed app as well.

Once permissions are granted, this records a three-second smoke-test clip into the normal destination and exits after finalization:

```sh
open -W "dist/Mac Screen Recorder.app" --args --smoke-test
```

Check the resulting `.mp4` in QuickTime or, optionally, with `ffprobe`. Also test a normal launch followed by the global shortcut and another launch followed by a dot click. Confirm that the dot disappears only after saving, each file plays through its end, and repeated stop presses do not interrupt finalization.

Swift tests cover filename collisions, folder errors, and encoder-safe capture dimensions for Retina, portrait, ultrawide, and odd-sized displays. They do not replace a real capture test with macOS permission granted.

The build script packages and ad-hoc signs a standalone `.app` in `dist/`. No Xcode project generator is required; `Package.swift` can also be opened in Xcode. Local rebuilds keep a stable bundle identifier and designated requirement, although macOS can still require permission again. Set `SIGNING_IDENTITY` to use a signing certificate. A public binary distribution should use Developer ID signing and notarization; the default local build is not notarized.

GitHub Actions runs tests, builds the app on macOS, and uploads a zipped app artifact. Downloaded ad-hoc builds may be blocked by Gatekeeper; building locally is the supported initial installation path.
