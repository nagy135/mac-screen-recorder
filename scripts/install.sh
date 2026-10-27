#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

destination='/Applications/Mac Screen Recorder.app'
bundle_id='com.nagy135.mac-screen-recorder'

ensure_not_recording() {
    if pgrep -u "$(id -u)" -f '/MacScreenRecorder([[:space:]]|$)' >/dev/null; then
        printf 'Stop the current recording before installing an update.\n' >&2
        exit 1
    fi
}
ensure_not_recording
if [ -L "$destination" ]; then
    printf 'Refusing to replace a symbolic link at %s.\n' "$destination" >&2
    exit 1
fi
if [ -e "$destination" ]; then
    installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")"
    if [ "$installed_id" != "$bundle_id" ]; then
        printf 'Refusing to replace a different app at %s.\n' "$destination" >&2
        exit 1
    fi
fi
if [ ! -w /Applications ]; then
    printf '/Applications is not writable by this user. Run as a user with installation access; do not run the build with sudo.\n' >&2
    exit 1
fi

./scripts/build.sh
source_app="$(pwd)/dist/Mac Screen Recorder.app"
if codesign -dvv "$source_app" 2>&1 | grep 'Signature=adhoc' >/dev/null; then
    printf 'Installation requires a persistent signing certificate. Unset SIGNING_IDENTITY=- and retry.\n' >&2
    exit 1
fi
if [ -e "$destination" ]; then
    if codesign -dvv "$destination" 2>&1 | grep 'Signature=adhoc' >/dev/null; then
        printf 'Migrating the previous ad-hoc build to a persistent certificate; macOS may request permission once.\n'
    else
        installed_requirement="$(codesign -d -r- "$destination" 2>&1 | sed -n 's/^\(# \)\{0,1\}designated => //p')"
        new_requirement="$(codesign -d -r- "$source_app" 2>&1 | sed -n 's/^\(# \)\{0,1\}designated => //p')"
        if [ -z "$installed_requirement" ] || [ -z "$new_requirement" ]; then
            printf 'Could not read signing requirements; leaving the installed app unchanged.\n' >&2
            exit 1
        fi
        # Check both directions: the new build must be the same signer, not a weaker identity.
        codesign --verify --strict -R "=$installed_requirement" "$source_app"
        codesign --verify --strict -R "=$new_requirement" "$destination"
    fi
fi

staging_directory="$(mktemp -d '/Applications/.mac-screen-recorder-install.XXXXXX')"
cleanup() {
    result=$?
    if [ "$result" -ne 0 ] && [ -d "$staging_directory/previous.app" ]; then
        if [ -e "$destination" ]; then
            mv "$destination" "$staging_directory/failed.app"
        fi
        mv "$staging_directory/previous.app" "$destination"
    fi
    rm -rf "$staging_directory"
}
trap cleanup EXIT
ditto "$source_app" "$staging_directory/Mac Screen Recorder.app"
codesign --verify --strict "$staging_directory/Mac Screen Recorder.app"
ensure_not_recording
if [ -e "$destination" ]; then
    mv "$destination" "$staging_directory/previous.app"
fi
mv "$staging_directory/Mac Screen Recorder.app" "$destination"
codesign --verify --strict "$destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
printf '\nInstalled %s\nOpen it to start recording; installation does not launch it.\n' "$destination"
