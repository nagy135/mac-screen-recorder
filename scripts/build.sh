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
xcrun swift scripts/generate-icon.swift "$(pwd)/dist/AppIcon.iconset"
iconutil -c icns "$(pwd)/dist/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
plutil -lint "$app/Contents/Info.plist"
plutil -lint Resources/MacScreenRecorder.entitlements
# Local builds reuse a real certificate, not a different ad-hoc identity each time.
# CI explicitly sets SIGNING_IDENTITY=-; Developer ID builds can supply their identity.
signing_identity="${SIGNING_IDENTITY:-}"
if [ -z "$signing_identity" ]; then
    signing_identity="$(./scripts/setup-signing.sh)"
    signing_keychain="$HOME/Library/Application Support/Mac Screen Recorder/Signing/local-signing.keychain-db"
    # codesign requires even an explicitly selected keychain to be on its search
    # list. Include this app-only keychain while signing, then restore the list.
    original_keychains=()
    while IFS= read -r keychain; do
        original_keychains+=("$keychain")
    done < <(security list-keychains -d user | sed 's/^[[:space:]]*"//; s/"$//')
    trap 'security list-keychains -d user -s "${original_keychains[@]}"' EXIT
    security list-keychains -d user -s "${original_keychains[@]}" "$signing_keychain"
    codesign --force --sign "$signing_identity" --keychain "$signing_keychain" \
        --entitlements Resources/MacScreenRecorder.entitlements \
        --timestamp=none --identifier com.nagy135.mac-screen-recorder \
        --requirements "=designated => identifier \"com.nagy135.mac-screen-recorder\" and certificate leaf = H\"$signing_identity\"" \
        "$app"
    security list-keychains -d user -s "${original_keychains[@]}"
    trap - EXIT
elif [ "$signing_identity" = "-" ]; then
    codesign --force --sign - --entitlements Resources/MacScreenRecorder.entitlements \
        --identifier com.nagy135.mac-screen-recorder "$app"
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" \
        --entitlements Resources/MacScreenRecorder.entitlements "$app"
fi
codesign --verify --strict "$app"
printf '\nBuilt %s\n' "$app"
