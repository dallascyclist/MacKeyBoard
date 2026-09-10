#!/usr/bin/env bash
# Ghostty: last-wins key/value config; block is appended.
MK_TARGET=ghostty
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

XDG_FILE="${XDG_CONFIG_HOME:-$MK_HOME/.config}/ghostty/config"
APP_FILE="$MK_HOME/Library/Application Support/com.mitchellh.ghostty/config"
# Ghostty on macOS loads both; App Support is loaded last and wins.
if   [ -f "$APP_FILE" ]; then FILE="$APP_FILE"
elif [ -f "$XDG_FILE" ]; then FILE="$XDG_FILE"
else                          FILE="$XDG_FILE"; fi
PREFIX="#"

GHOSTTY_BIN="$(command -v ghostty || true)"
[ -n "$GHOSTTY_BIN" ] || [ ! -x /Applications/Ghostty.app/Contents/MacOS/ghostty ] || GHOSTTY_BIN=/Applications/Ghostty.app/Contents/MacOS/ghostty

block() {
cat <<'BLOCK'
# Both Option keys act as Alt so zellij's Alt+hjkl / Alt+arrow bindings work.
macos-option-as-alt = true
# Mouse selection goes straight to the system clipboard.
copy-on-select = clipboard
# Let zellij / vim / ssh write the clipboard via OSC 52 (never read it).
clipboard-write = allow
clipboard-read = deny
# Shift+drag selects natively even while zellij owns the mouse.
mouse-shift-capture = false
# Explicit, so nothing else can shadow them.
keybind = super+c=copy_to_clipboard
keybind = super+v=paste_from_clipboard
BLOCK
}

cmd_diff()   { log "file: $FILE"; block; }
cmd_status() { has_block "$FILE" && print_status_line APPLIED "$FILE" || print_status_line "NOT APPLIED" "$FILE"; }

cmd_apply() {
    if has_block "$FILE"; then log "already applied: $FILE"; return 0; fi
    find_conflicts "$FILE" "$PREFIX" 'macos-option-as-alt' 'copy-on-select' 'clipboard-write' 'clipboard-read' 'mouse-shift-capture' \
        || warn "our block is appended last, so it overrides the keys above"
    note_created_if_missing "$FILE"
    backup_once "$FILE"
    block | append_block "$FILE" "$PREFIX"
    log "applied: $FILE"
    log "reload Ghostty with Cmd+Shift+, (or open a new window)"
}

cmd_revoke() {
    if ! has_block "$FILE"; then log "nothing to revoke"; else remove_blocks "$FILE"; log "block removed: $FILE"; fi
    finish_revoke_file "$FILE"
    state_clear
}

cmd_check() {
    [ -f "$FILE" ] || { log "no config file; nothing to check"; return 0; }
    [ -n "$GHOSTTY_BIN" ] || { warn "ghostty binary not found; skipping validation"; return 0; }
    "$GHOSTTY_BIN" +validate-config --config-file="$FILE" && log "valid: $FILE"
}

dispatch "$@"
