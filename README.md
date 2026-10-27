# Mac Screen Recorder

A small native macOS menu bar app: open it to record, click the red dot or press **⌘⌥⇧S** to stop. The finished H.264 MP4 is saved in `~/Documents/Videos`, then the app quits.

No ffmpeg, conversion, countdown, recording window, Dock icon, or third-party dependencies.

## Use

Requires **macOS 15 or later**. Build with Xcode 16+ / Swift 6+ and its command line tools:

```sh
./scripts/install.sh
open "/Applications/Mac Screen Recorder.app"
```

The installer builds the camera-icon app, signs it with a persistent local certificate, and installs it into `/Applications`. It does not launch the app or start recording. Run the same script after pulling updates. Stop an active recording before installing.

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

The build script packages a standalone `.app` with a camera icon in `dist/`. No Xcode project generator is required; `Package.swift` can also be opened in Xcode.

## Permission continuity across updates

Local builds create a **persistent, app-specific signing certificate** once and reuse it. The private key is stored in a dedicated Keychain under `~/Library/Application Support/Mac Screen Recorder/Signing`, outside the repository. The directory and its password file are restricted to your user. The key's access controls authorize `/usr/bin/codesign` and configure the Apple signing partitions so subsequent builds do not need a Keychain approval dialog. Setup trusts this certificate for **code signing only**, in your user's trust settings. It does not change TLS trust, system roots, or Gatekeeper policy.

Every build keeps the same bundle identifier and a designated requirement pinned to that certificate. The installer checks that the installed app and update satisfy each other's requirements before replacing the app at its fixed `/Applications` path. It refuses a mismatched signer, leaves an active recording alone, and restores the old app if replacement fails.

Grant screen-recording permission once to the installed app. Updates installed with `./scripts/install.sh` preserve its signing identity, avoiding the changing-build identity that causes repeated authorization. Migrating from the old ad-hoc build may require one new grant. **Keep the Signing directory**: losing it or switching signing certificates can require permission again. Back it up securely with your Mac; never commit it or upload it to GitHub.

macOS retains control over first-use consent, revoked permissions, and periodic screen-recording reminders; the app cannot guarantee that the operating system will never show a prompt. See [Apple's designated-requirement explanation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Set `SIGNING_IDENTITY` to use your own existing certificate instead. `SIGNING_IDENTITY=- ./scripts/build.sh` produces an ad-hoc test artifact; the installer rejects it. Public binary distribution should use Developer ID signing and notarization. The default certificate is local to this Mac and is not an Apple Developer ID.

GitHub Actions runs tests, builds the app on macOS, and uploads a zipped app artifact. Downloaded ad-hoc builds may be blocked by Gatekeeper; building locally is the supported initial installation path.
