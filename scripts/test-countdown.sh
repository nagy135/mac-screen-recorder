#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
binary_directory="$(swift build --show-bin-path)"
if [ -f "$binary_directory/RecorderCore.o" ]; then
    core_objects=("$binary_directory/RecorderCore.o")
else
    core_objects=("$binary_directory/RecorderCore.build/"*.o)
fi
mkdir -p dist
xcrun swiftc -parse-as-library -I "$binary_directory" -I "$binary_directory/Modules" \
    "${core_objects[@]}" Sources/MacScreenRecorder/RecordingCountdown.swift \
    Sources/MacScreenRecorder/StartupTiming.swift scripts/test-countdown.swift -o dist/test-countdown
./dist/test-countdown "$@"
