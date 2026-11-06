#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/opera-guard-test.XXXXXXXX")"
trap '/bin/rm -rf "$work"' EXIT
fixture="$work/Opera Guard Fixture.app"
identifier="com.zhijun.opera-guard.fixture.$(/usr/bin/uuidgen)"

/bin/mkdir -p "$fixture/Contents/MacOS"
/bin/cp "$repo/Tests/Fixture-Info.plist" "$fixture/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$identifier" "$fixture/Contents/Info.plist"
/usr/bin/swiftc -warnings-as-errors -module-cache-path "$work/module-cache" -O \
    "$repo/Tests/Fixture.swift" -o "$fixture/Contents/MacOS/fixture"
/usr/bin/codesign --force --sign - "$fixture"

/usr/bin/swiftc -warnings-as-errors -module-cache-path "$work/module-cache" -O \
    "$repo/Sources/OperaGuard.swift" "$repo/Tests/main.swift" -o "$work/fixture-test"
"$work/fixture-test" "$work" "$identifier"
