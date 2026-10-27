# Initial validation

Validated locally on an Apple Silicon Mac with Swift 6.4 and the installed Xcode SDK.

- `swift test`: filename generation, existing-file preservation, invalid destination handling, and seven capture dimension cases passed.
- `swift build -Xswiftc -warnings-as-errors`: passed.
- `./scripts/build.sh`: release build, Info.plist lint, and strict code-signature verification passed.
- Native `--smoke-test`: captured and finalized a three-second MP4 in `~/Documents/Videos`, then exited normally.
- `ffprobe`: H.264, 3024 × 1964, `yuv420p`, 3.075-second duration. No audio stream, as configured.
- `ffmpeg -v error -i <test-clip.mp4> -f null -`: decoded the whole recording without errors. ffmpeg was used only to validate the file, not by the app.
- A normal recording followed by an OS graceful-quit request finalized its MP4 and exited, exercising deferred application termination.

Both capture checks launched the binary from the development session, which already reported screen-capture access. A Finder launch can have a different macOS permission attribution.

## Installation and signing update

- Generated a camera `.icns` at standard macOS icon resolutions and visually inspected its 1024-pixel PNG source.
- Installed the app into `/Applications/Mac Screen Recorder.app` with its camera icon and verified the installed code signature.
- Installed v0.1.0 with the persistent local certificate, then updated to v0.2.0. The installer verified that old and new apps satisfy each other's certificate-pinned designated requirements before replacing the app.
- Repeated the installation using the same certificate successfully, with the dedicated signing keychain removed from the normal search list again after signing.
- Attempted `SIGNING_IDENTITY=- ./scripts/install.sh`: the installer rejected the ad-hoc artifact and preserved the installed certificate-signed app. Restored the normal build afterward.
- Ran the installed v0.2.0 app's three-second smoke test: H.264, 3024 × 1964, 3.048-second MP4, normal completion.
- `swift test`, shell syntax checks, and strict signature verification passed after the installer changes.

The development-session capture checks do not prove that the installed app has received a separate first-use Finder permission grant. Certificate continuity is verified; first-use authorization and macOS-controlled reminders still require the normal system policy.

## Countdown and Finder reveal (v0.3.0)

- `swift test` passed; release build, installer update compatibility checks, and installed signature verification passed.
- Native accessibility inspection exposed the countdown HUD displaying `1` and `Starting recording`.
- Installed-app smoke test produced a 3.092-second H.264 MP4. Extracted and visually inspected its first frame: the countdown HUD was absent.
- Native Finder inspection confirmed that `~/Documents/Videos` was open with the newly completed MP4 selected after recording stopped.
- Requested graceful quit during the countdown: exit code 0, no save callback, and zero new MP4 files. The same countdown cancellation method is used by the dot and stop shortcut.

## Manual checks still required

- First-launch permission grant from the app's permanent install location.
- Stop by clicking the menu bar dot.
- Stop with **⌘⌥⇧S** while another application is active, including confirmation on non-QWERTY layouts.

## LosslessCut stop destination (v0.4.0)

- Confirmed the user's Homebrew installation completed: LosslessCut 3.70.1 at `/Applications/LosslessCut.app`, bundle identifier `no.mifi.losslesscut-mac`.
- `swift build -Xswiftc -warnings-as-errors`, `swift test`, release packaging, installed signature verification, and stable-signer installation passed.
- `scripts/test-shortcuts.swift` registered both exclusive hotkeys and dispatched app-local Carbon events for S/save and T/trim. Distinct actions were received; unknown signatures/IDs were ignored; unregistering allowed both hotkeys to be registered again. This checks routing and cleanup, not physical keyboard input.
- Installed-app `--smoke-test-trim` recorded a real MP4, finalized it, and opened it in LosslessCut through LaunchServices. The recorder exited normally.
- Native UI inspection confirmed the matching filename in LosslessCut, a 2.998-second timeline, start/end cut controls, and Export. Played the video through to 88 frames / 2.998 seconds and visually confirmed the recording's preview. No trim or export was applied to the original recording.

The available UI automation did not expose this windowless app's status item and did not trigger the global hotkey through its application-targeted keyboard input. Those interactions are implemented but have not been verified by physical input. A successful hotkey registration alone is not a complete end-to-end shortcut test.

## Hover audio controls (v0.5.0)

- Warnings-as-errors build, shell syntax checks, signed release packaging, stable-signer installation into `/Applications`, and installed signature verification passed. Verified the installed version is 0.5.0 and includes the audio-input entitlement and microphone usage description.
- Seven Swift tests passed, including countdown resets at the last second, hover/permission pause overlap, and ignoring late events after completion.
- `scripts/test-countdown.sh` exercised the actual HUD with app-local tracking events: 3 → 2 → 1, pause beyond three seconds, expansion, independent audio switches, retained choices on re-entry, a full countdown after each exit, cancellation while hovered and during the hide delay, and resetting choices for a new recording.
- The same HUD check simulated granted, denied, and cancelled microphone prompts. Leaving while permission was pending held the controls open; resolving permission restarted the countdown, and a stale response could not change the next run. These checks did not request or grant real macOS microphone access.
- Rendered both HUD states to PNG and visually inspected the labels, switches, spacing, and countdown number.
- The production Recorder created an audio-off H.264 MP4 (2.875 seconds, no audio stream) and a system-audio H.264/AAC MP4 (3.147 seconds). Played a generated tone during the system-audio check; the encoded track had mean volume −21.3 dB and peak −17.9 dB. Both files decoded fully with ffmpeg.
- A microphone-enabled request without permission failed explicitly before creating an output, with directions to the Microphone permission page.

Real microphone-only and combined-audio recording still require a user-approved microphone grant and an audible input check. App-local tracking events verify the widget handlers; physical pointer movement and clicking the inactive panel remain manual checks.

### Rounded backdrop and hover transition

- Added a stretchable rounded material mask so the behind-window blur and window shadow follow the same corners as the foreground; clipping only the layer had left a faint rectangular backdrop.
- Hover changes resize and crossfade over 220 ms, keep both layouts centered, ignore stale animation completions after reversal, and respect Reduce Motion.
- The native HUD check passed with rapid hover reversals. Ran `./scripts/test-countdown.sh --capture-window` to capture the composited windows with ScreenCaptureKit, verified fully transparent corner pixels, and visually inspected both rounded states. This optional flag requires existing screen-capture permission and does not create a recording.
