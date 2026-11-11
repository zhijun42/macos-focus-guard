#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
support="$HOME/Library/Application Support/Focus Guard"
binary="$support/focus-guard"
label="com.zhijun.focus_guard"
agent="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(/usr/bin/id -u)"
job="$domain/$label"
focus_start="${FOCUS_START:-22:30}"
focus_end="${FOCUS_END:-10:30}"
focus_apps="${FOCUS_APPS:-com.tencent.xinWeChat,com.operasoftware.Opera,com.zhijun.opera-guard,com.apple.Photos}"
stage="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/focus-guard-install.XXXXXXXX")"
backup=""
original_loaded=false
replacement_loaded=false
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
        if "$binary_touched"; then restore "$binary" focus-guard failed-focus-guard; fi
        if "$agent_touched"; then restore "$agent" LaunchAgent.plist FailedLaunchAgent.plist; fi
        if "$original_loaded"; then /bin/launchctl bootstrap "$domain" "$agent"; fi
    fi
    /bin/rm -rf "$stage"
    exit "$result"
}
trap cleanup EXIT

"$repo/scripts/build.sh" "$stage"
FOCUS_START="$focus_start" FOCUS_END="$focus_end" FOCUS_APPS="$focus_apps" \
    "$stage/focus-guard" --check "$focus_start" "$focus_end"

staged_agent="$stage/LaunchAgent.plist"
/usr/bin/plutil -create xml1 "$staged_agent"
/usr/bin/plutil -insert Label -string "$label" "$staged_agent"
/usr/bin/plutil -insert KeepAlive -bool YES "$staged_agent"
/usr/bin/plutil -insert ProgramArguments -array "$staged_agent"
/usr/bin/plutil -insert ProgramArguments.0 -string "$binary" "$staged_agent"
/usr/bin/plutil -insert StandardErrorPath -string "$support/guard.log" "$staged_agent"
/usr/bin/plutil -insert EnvironmentVariables -dictionary "$staged_agent"
/usr/bin/plutil -insert EnvironmentVariables.FOCUS_START -string "$focus_start" "$staged_agent"
/usr/bin/plutil -insert EnvironmentVariables.FOCUS_END -string "$focus_end" "$staged_agent"
/usr/bin/plutil -insert EnvironmentVariables.FOCUS_APPS -string "$focus_apps" "$staged_agent"
/usr/bin/plutil -lint "$staged_agent"

/bin/mkdir -p "$HOME/Library/LaunchAgents"
/bin/mkdir -m 700 -p "$support"
backup="$(/usr/bin/mktemp -d "$support/Backup.XXXXXXXX")"
if [ -e "$agent" ]; then /bin/cp -p "$agent" "$backup/LaunchAgent.plist"; fi
if [ -e "$binary" ]; then /bin/cp -p "$binary" "$backup/focus-guard"; fi

if /bin/launchctl print "$job" >/dev/null 2>&1; then
    /bin/launchctl bootout "$job"
    original_loaded=true
fi
binary_touched=true
/usr/bin/install -m 700 "$stage/focus-guard" "$binary"
agent_touched=true
/usr/bin/install -m 644 "$staged_agent" "$agent"
/bin/launchctl bootstrap "$domain" "$agent"
replacement_loaded=true

for attempt in 1 2 3 4 5; do
    launch_status="$(/bin/launchctl print "$job")"
    state="$(/usr/bin/awk '/^\tstate = / { print; exit }' <<< "$launch_status")"
    printf 'LaunchAgent check %d: %s\n' "$attempt" "$state"
    if [ "$state" = $'\tstate = running' ]; then
        printf '已安装 %s\n备份目录 %s\n' "$binary" "$backup"
        exit 0
    fi
    /bin/sleep 1
done
exit 1
