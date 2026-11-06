#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:?Usage: scripts/build.sh OUTPUT_DIRECTORY [EXISTING_LAUNCHER]}"
existing="${2:-}"

/bin/mkdir -p "$output"
output="$(cd "$output" && pwd)"
app="$output/The Opera.app"

/usr/bin/swiftc -warnings-as-errors -module-cache-path "$output/module-cache" -O \
    "$repo/Sources/OperaGuard.swift" "$repo/Sources/main.swift" -o "$output/opera-guard"

if [ -n "$existing" ]; then
    /usr/bin/ditto "$existing" "$app"
    /usr/bin/osacompile -o "$app/Contents/Resources/Scripts/main.scpt" "$repo/Sources/Launcher.applescript"
else
    /usr/bin/osacompile -o "$app" "$repo/Sources/Launcher.applescript"
    /usr/bin/plutil -replace CFBundleIdentifier -string com.zhijun.opera-guard "$app/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleName -string "The Opera" "$app/Contents/Info.plist"
fi
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
