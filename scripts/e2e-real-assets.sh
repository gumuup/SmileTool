#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

swift test --filter realDeviceImagesSurviveCompleteBackupAndRestore
./script/build_and_run.sh --verify

for name in chromecast-voice-remote dji-mic-mini-2 mx-master-3s nut65-keyboard x6-remote; do
    source="Sources/SmileTool/Resources/$name.png"
    bundled="dist/SmileTool.app/Contents/Resources/$name.png"
    cmp "$source" "$bundled"
    /usr/bin/sips -g pixelWidth -g pixelHeight "$bundled" >/dev/null
done
codesign --verify --deep --strict dist/SmileTool.app
echo "Real-asset end-to-end regression passed: SQLite → ZIP → restore, 5 product images, bundled app launch."
