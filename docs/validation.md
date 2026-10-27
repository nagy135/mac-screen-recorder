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

## Manual checks still required

- First-launch permission grant from the app's permanent install location.
- Stop by clicking the menu bar dot.
- Stop with **⌘⌥⇧S** while another application is active, including confirmation on non-QWERTY layouts.

The available UI automation did not expose this windowless app's status item and did not trigger the global hotkey through its application-targeted keyboard input. Those interactions are implemented but have not been verified by physical input. A successful hotkey registration alone is not a complete end-to-end shortcut test.
