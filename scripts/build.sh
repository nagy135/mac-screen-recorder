#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${CONFIGURATION:-release}"
swift build -c "$configuration"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
app="$(pwd)/dist/Mac Screen Recorder.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_directory/MacScreenRecorder" "$app/Contents/MacOS/MacScreenRecorder"
cp Resources/Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
# A stable bundle identifier and designated requirement help retain screen permissions
# across local rebuilds. Set SIGNING_IDENTITY to a Developer ID for distribution.
signing_identity="${SIGNING_IDENTITY:--}"
if [ "$signing_identity" = "-" ]; then
    codesign --force --sign - \
        --identifier com.nagy135.mac-screen-recorder \
        --requirements '=designated => identifier "com.nagy135.mac-screen-recorder"' \
        "$app"
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$app"
fi
codesign --verify --strict "$app"
printf '\nBuilt %s\n' "$app"
