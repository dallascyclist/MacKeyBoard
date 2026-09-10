#!/usr/bin/env bash
# iTerm2: no text config. Apply installs a dynamic profile ("MacKeyboard")
# that inherits from the current default profile, makes it the default, and
# turns on the two global clipboard preferences. Every original value is
# recorded in state and restored exactly by revoke.
MK_TARGET=iterm2
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

DOMAIN="${MACKEYBOARD_ITERM_DOMAIN:-com.googlecode.iterm2}"
DYN_DIR="$MK_HOME/Library/Application Support/iTerm2/DynamicProfiles"
JSON="$DYN_DIR/MacKeyboard.json"
GUID="A7C0F1E2-4B3D-4C5E-9F60-4D41434B4559"   # stable so re-apply is idempotent
UNSET="__unset__"
# CopySelection: copy-on-select. AllowClipboardAccess: OSC 52 writes.
# NoSyncNeverAskAboutMouseReportingFrustration: with zellij owning the mouse,
# Cmd+C after a zellij drag finds no native selection and iTerm2 would offer
# to disable mouse reporting; the copy already happened via pbcopy.
GLOBAL_BOOLS=(CopySelection AllowClipboardAccess NoSyncNeverAskAboutMouseReportingFrustration)

profile_json() {
    local parent="$1"
    python3 - "$GUID" "$parent" <<'PY'
import json, sys
guid, parent = sys.argv[1], sys.argv[2]
print(json.dumps({"Profiles": [{
    "Name": "MacKeyboard",
    "Guid": guid,
    "Dynamic Profile Parent Name": parent,
    # Both Option keys send Esc+ so zellij Alt bindings work.
    "Option Key Sends": 2,
    "Right Option Key Sends": 2,
    # Forward clicks, drags and wheel to zellij.
    "Mouse Reporting": True,
    "Mouse Reporting allow mouse wheel": True,
    "Mouse Reporting allow clicks and drags": True,
}]}, indent=2))
PY
}

iterm_running() {
    [ -n "${MACKEYBOARD_ITERM_DOMAIN:-}" ] && return 1   # test domain: skip
    # pgrep can miss GUI apps from sandboxed shells; ps and AppleScript do not.
    ps -axo comm | grep -q '/iTerm.app/Contents/MacOS/iTerm2$' && return 0
    [ "$(osascript -e 'application "iTerm2" is running' 2>/dev/null)" = "true" ]
}

read_default() { defaults read "$DOMAIN" "$1" 2>/dev/null || printf '%s' "$UNSET"; }

default_profile_name() {
    local tmp; tmp="$(mktemp).plist"
    defaults export "$DOMAIN" "$tmp" 2>/dev/null || { printf 'Default'; rm -f "$tmp"; return; }
    python3 - "$tmp" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
guid = d.get("Default Bookmark Guid")
for p in d.get("New Bookmarks", []):
    if p.get("Guid") == guid:
        print(p.get("Name", "Default")); break
else:
    print("Default")
PY
    rm -f "$tmp"
}

remember_original() {   # only on first apply, never overwritten
    [ -n "$(state_get "orig_$1")" ] || state_set "orig_$1" "$(read_default "$1")"
}

cmd_diff() {
    log "dynamic profile: $JSON"
    profile_json "$(default_profile_name)"
    log "defaults ($DOMAIN):"
    printf '  "Default Bookmark Guid" = %s   (now: %s)\n' "$GUID" "$(read_default 'Default Bookmark Guid')"
    for k in "${GLOBAL_BOOLS[@]}"; do printf '  %s = true   (now: %s)\n' "$k" "$(read_default "$k")"; done
}

cmd_status() {
    if [ -f "$JSON" ] && [ "$(read_default 'Default Bookmark Guid')" = "$GUID" ]; then
        print_status_line APPLIED "$JSON (default profile)"
    elif [ -f "$JSON" ]; then
        print_status_line PARTIAL "$JSON present but not the default profile"
    else
        print_status_line "NOT APPLIED" "$JSON"
    fi
}

cmd_apply() {
    iterm_running && die "quit iTerm2 first (it rewrites its preferences on exit)"
    local parent; parent="$(default_profile_name)"
    [ "$parent" = "MacKeyboard" ] && parent="$(state_get parent)"
    remember_original "Default Bookmark Guid"
    for k in "${GLOBAL_BOOLS[@]}"; do remember_original "$k"; done
    state_set parent "$parent"
    mkdir -p "$DYN_DIR"
    profile_json "$parent" > "$JSON"
    defaults write "$DOMAIN" "Default Bookmark Guid" -string "$GUID"
    for k in "${GLOBAL_BOOLS[@]}"; do defaults write "$DOMAIN" "$k" -bool true; done
    log "applied: $JSON (parent profile: $parent) and set as default"
    log "start iTerm2; new windows use the MacKeyboard profile"
}

restore_default() {
    local key="$1" type="$2" val; val="$(state_get "orig_$key")"
    if [ -z "$val" ] || [ "$val" = "$UNSET" ]; then
        defaults delete "$DOMAIN" "$key" 2>/dev/null || true
    else
        if [ "$type" = -bool ]; then case "$val" in 1) val=true ;; 0) val=false ;; esac; fi
        defaults write "$DOMAIN" "$key" "$type" "$val"
    fi
}

cmd_revoke() {
    iterm_running && die "quit iTerm2 first (it rewrites its preferences on exit)"
    [ -f "$JSON" ] && { rm -f "$JSON"; log "removed: $JSON"; }
    if [ -f "$(state_file)" ]; then
        restore_default "Default Bookmark Guid" -string
        for k in "${GLOBAL_BOOLS[@]}"; do restore_default "$k" -bool; done
        log "defaults restored to recorded originals"
    else
        log "no state recorded; defaults left untouched"
    fi
    state_clear
}

cmd_check() {
    [ -f "$JSON" ] || { log "no dynamic profile; nothing to check"; return 0; }
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$JSON" \
        && plutil -convert xml1 -o /dev/null "$JSON" \
        && log "valid JSON plist: $JSON"
}

dispatch "$@"
