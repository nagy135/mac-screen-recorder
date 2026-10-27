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

## Manual checks still required

- First-launch permission grant from the app's permanent install location.
- Stop by clicking the menu bar dot.
- Stop with **⌘⌥⇧S** while another application is active, including confirmation on non-QWERTY layouts.

The available UI automation did not expose this windowless app's status item and did not trigger the global hotkey through its application-targeted keyboard input. Those interactions are implemented but have not been verified by physical input. A successful hotkey registration alone is not a complete end-to-end shortcut test.
