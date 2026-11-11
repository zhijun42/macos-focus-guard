#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:?Usage: scripts/build.sh OUTPUT_DIRECTORY [EXISTING_LAUNCHER]}"
existing="${2:-}"

/bin/mkdir -p "$output"
output="$(cd "$output" && pwd)"
app="$output/The Opera.app"
scratch="$output/swift-build"

/usr/bin/xcrun swift build --package-path "$repo" --scratch-path "$scratch" \
    -c release --product opera-guard
/usr/bin/xcrun swift build --package-path "$repo" --scratch-path "$scratch" \
    -c release --product focus-guard
bin_dir="$(/usr/bin/xcrun swift build --package-path "$repo" --scratch-path "$scratch" \
    -c release --show-bin-path)"
/usr/bin/install -m 700 "$bin_dir/opera-guard" "$output/opera-guard"
/usr/bin/install -m 700 "$bin_dir/focus-guard" "$output/focus-guard"

if [ -n "$existing" ]; then
    /usr/bin/ditto "$existing" "$app"
    /usr/bin/osacompile -o "$app/Contents/Resources/Scripts/main.scpt" \
        "$repo/Resources/OperaLauncher.applescript"
else
    /usr/bin/osacompile -o "$app" "$repo/Resources/OperaLauncher.applescript"
    /usr/bin/plutil -replace CFBundleIdentifier -string com.zhijun.opera-guard "$app/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleName -string "The Opera" "$app/Contents/Info.plist"
fi
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
