#!/bin/bash
set -euo pipefail

component="${1:-}"
case "$component" in
    opera|focus|all) ;;
    *)
        printf '%s\n' 'Usage: scripts/uninstall.sh opera|focus|all' >&2
        exit 64
        ;;
esac

domain="gui/$(/usr/bin/id -u)"
archive="$HOME/Library/Application Support/macOS Focus Guard/Uninstalled-$(/bin/date +%Y%m%d-%H%M%S)"
/bin/mkdir -m 700 -p "$archive"

archive_path() {
    local source="$1" name="$2"
    if [ -e "$source" ]; then /bin/mv "$source" "$archive/$name"; fi
}

unload() {
    local label="$1"
    if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
        /bin/launchctl bootout "$domain/$label"
    fi
}

if [ "$component" = opera ] || [ "$component" = all ]; then
    unload com.zhijun.video_watch_guard
    archive_path "$HOME/Library/LaunchAgents/com.zhijun.video_watch_guard.plist" OperaGuard.plist
    archive_path "$HOME/Library/Application Support/The Opera/opera-guard" opera-guard
    archive_path "$HOME/Applications/The Opera.app" "The Opera.app"
fi

if [ "$component" = focus ] || [ "$component" = all ]; then
    unload com.zhijun.focus_guard
    archive_path "$HOME/Library/LaunchAgents/com.zhijun.focus_guard.plist" FocusGuard.plist
    archive_path "$HOME/Library/Application Support/Focus Guard/focus-guard" focus-guard
fi

printf '已卸载；可恢复文件位于 %s\n' "$archive"
