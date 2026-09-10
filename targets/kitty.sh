#!/usr/bin/env bash
# kitty: last-wins config; block is appended.
MK_TARGET=kitty
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

FILE="${KITTY_CONFIG_DIRECTORY:-${XDG_CONFIG_HOME:-$MK_HOME/.config}/kitty}/kitty.conf"
PREFIX="#"

block() {
cat <<'BLOCK'
# Both Option keys act as Alt so zellij's Alt+hjkl / Alt+arrow bindings work.
macos_option_as_alt both
# Mouse selection goes straight to the system clipboard.
copy_on_select clipboard
# Let zellij / vim / ssh write the clipboard via OSC 52; reads must be confirmed.
clipboard_control write-clipboard write-primary read-clipboard-query read-primary-query
# Explicit, so nothing else can shadow them.
map cmd+c copy_to_clipboard
map cmd+v paste_from_clipboard
BLOCK
}

cmd_diff()   { log "file: $FILE"; block; }
cmd_status() { has_block "$FILE" && print_status_line APPLIED "$FILE" || print_status_line "NOT APPLIED" "$FILE"; }

cmd_apply() {
    if has_block "$FILE"; then log "already applied: $FILE"; return 0; fi
    find_conflicts "$FILE" "$PREFIX" 'macos_option_as_alt' 'copy_on_select' 'clipboard_control' \
        || warn "our block is appended last, so it overrides the keys above"
    note_created_if_missing "$FILE"
    backup_once "$FILE"
    block | append_block "$FILE" "$PREFIX"
    log "applied: $FILE"
    log "reload kitty with Cmd+Ctrl+, (or open a new window)"
}

cmd_revoke() {
    if ! has_block "$FILE"; then log "nothing to revoke"; else remove_blocks "$FILE"; log "block removed: $FILE"; fi
    finish_revoke_file "$FILE"
    state_clear
}

cmd_check() {
    [ -f "$FILE" ] || { log "no config file; nothing to check"; return 0; }
    command -v kitty >/dev/null || { warn "kitty not on PATH; skipping validation"; return 0; }
    kitty +runpy '
import sys
from kitty.config import load_config
bad = []
opts = load_config(sys.argv[1], accumulate_bad_lines=bad)
for b in bad:
    print("bad line:", b, file=sys.stderr)
print("macos_option_as_alt =", opts.macos_option_as_alt)
sys.exit(1 if bad else 0)
' "$FILE" && log "valid: $FILE"
}

dispatch "$@"
