#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/opera-guard-test.XXXXXXXX")"
trap '/bin/rm -rf "$work"' EXIT
fixture="$work/Opera Guard Fixture.app"
identifier="com.zhijun.opera-guard.fixture.$(/usr/bin/uuidgen)"
scratch="$work/swift-build"

/bin/mkdir -p "$fixture/Contents/MacOS"
/bin/cp "$repo/IntegrationFixtures/OperaGuard/Info.plist" "$fixture/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$identifier" "$fixture/Contents/Info.plist"
/usr/bin/swiftc -warnings-as-errors -module-cache-path "$work/module-cache" -O \
    "$repo/IntegrationFixtures/OperaGuard/Fixture.swift" -o "$fixture/Contents/MacOS/fixture"
/usr/bin/codesign --force --sign - "$fixture"

/usr/bin/xcrun swift test --package-path "$repo" --scratch-path "$scratch"
/usr/bin/xcrun swift build --package-path "$repo" --scratch-path "$scratch" \
    --product opera-guard-integration-tests
bin_dir="$(/usr/bin/xcrun swift build --package-path "$repo" --scratch-path "$scratch" \
    --show-bin-path)"
"$bin_dir/opera-guard-integration-tests" "$work" "$identifier"
