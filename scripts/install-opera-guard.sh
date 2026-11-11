#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
app="$HOME/Applications/The Opera.app"
support="$HOME/Library/Application Support/The Opera"
binary="$support/opera-guard"
label="com.zhijun.video_watch_guard"
agent="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(/usr/bin/id -u)"
job="$domain/$label"

if [ ! -d /Applications/Opera.app ]; then
    printf '%s\n' '请先把 Opera 安装到 /Applications/Opera.app。' >&2
    exit 1
fi

check_idle() {
    if /usr/bin/pgrep -x Opera >/dev/null; then
        printf '%s\n' '请退出 Opera 后重新运行安装命令。' >&2
        return 75
    else
        local result=$?
        if [ "$result" -ne 1 ]; then return "$result"; fi
    fi
}
check_idle

stage="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/opera-guard-install.XXXXXXXX")"
backup=""
original_unloaded=false
replacement_loaded=false
app_touched=false
agent_touched=false
binary_touched=false

restore() {
    local destination="$1" original="$2" failed="$3"
    if [ -e "$destination" ]; then /bin/mv "$destination" "$backup/$failed"; fi
    if [ -e "$backup/$original" ]; then /bin/mv "$backup/$original" "$destination"; fi
}

cleanup() {
    local result=$?
    set +e
    if [ "$result" -ne 0 ] && [ -n "$backup" ]; then
        printf '安装失败，正在恢复此前的安装。备份目录 %s\n' "$backup" >&2
        if "$replacement_loaded"; then /bin/launchctl bootout "$job"; fi
        if "$binary_touched"; then restore "$binary" opera-guard failed-opera-guard; fi
        if "$app_touched"; then restore "$app" "The Opera.app" "Failed The Opera.app"; fi
        if "$agent_touched"; then restore "$agent" LaunchAgent.plist FailedLaunchAgent.plist; fi
        if "$original_unloaded"; then /bin/launchctl bootstrap "$domain" "$agent"; fi
    fi
    /bin/rm -rf "$stage"
    exit "$result"
}
trap cleanup EXIT

if [ -e "$app" ]; then
    identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")"
    if [ "$identifier" != "com.zhijun.opera-guard" ]; then
        printf '已存在同名应用 %s\n' "$app" >&2
        exit 1
    fi
    "$repo/scripts/build.sh" "$stage" "$app"
else
    "$repo/scripts/build.sh" "$stage"
fi

staged_agent="$stage/LaunchAgent.plist"
/usr/bin/plutil -create xml1 "$staged_agent"
/usr/bin/plutil -insert Label -string "$label" "$staged_agent"
/usr/bin/plutil -insert KeepAlive -bool YES "$staged_agent"
/usr/bin/plutil -insert ProgramArguments -array "$staged_agent"
/usr/bin/plutil -insert ProgramArguments.0 -string "$binary" "$staged_agent"
/usr/bin/plutil -insert ProgramArguments.1 -string monitor "$staged_agent"
/usr/bin/plutil -insert StandardErrorPath -string "$support/guard.log" "$staged_agent"
/usr/bin/plutil -lint "$staged_agent"

check_idle
/bin/mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
/bin/mkdir -m 700 -p "$support"
backup="$(/usr/bin/mktemp -d "$support/Backup.XXXXXXXX")"
if [ -e "$app" ]; then /usr/bin/ditto "$app" "$backup/The Opera.app"; fi
if [ -e "$agent" ]; then /bin/cp -p "$agent" "$backup/LaunchAgent.plist"; fi
if [ -e "$binary" ]; then /bin/cp -p "$binary" "$backup/opera-guard"; fi

if /bin/launchctl print "$job" >/dev/null 2>&1; then
    /bin/launchctl bootout "$job"
    original_unloaded=true
fi
binary_touched=true
/usr/bin/install -m 700 "$stage/opera-guard" "$binary"
app_touched=true
/usr/bin/ditto "$stage/The Opera.app" "$app"
/usr/bin/codesign --verify --strict "$app"
agent_touched=true
/usr/bin/install -m 644 "$staged_agent" "$agent"
/bin/launchctl bootstrap "$domain" "$agent"
replacement_loaded=true

for attempt in 1 2 3 4 5; do
    status="$(/bin/launchctl print "$job")"
    state="$(/usr/bin/awk '/^\tstate = / { print; exit }' <<< "$status")"
    printf 'LaunchAgent check %d: %s\n' "$attempt" "$state"
    if [ "$state" = $'\tstate = running' ]; then
        "$binary" status
        printf '已安装 %s\n备份目录 %s\n' "$app" "$backup"
        exit 0
    fi
    /bin/sleep 1
done
exit 1
