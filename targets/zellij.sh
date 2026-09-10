#!/usr/bin/env bash
# Zellij: KDL config; top-level option nodes appended in a managed block.
MK_TARGET=zellij
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

FILE="${ZELLIJ_CONFIG_FILE:-${XDG_CONFIG_HOME:-$MK_HOME/.config}/zellij/config.kdl}"
PREFIX="//"

block() {
cat <<'BLOCK'
// Zellij owns the mouse: wheel scrolls its scrollback, drag selects a region.
mouse_mode true
// Hand selections to macOS directly instead of relying on OSC 52 support
// in whichever emulator happens to be hosting this session.
copy_command "pbcopy"
// A mouse selection lands on the clipboard without a keystroke.
copy_on_select true
BLOCK
}

cmd_diff()   { log "file: $FILE"; block; }
cmd_status() { has_block "$FILE" && print_status_line APPLIED "$FILE" || print_status_line "NOT APPLIED" "$FILE"; }

cmd_apply() {
    if has_block "$FILE"; then log "already applied: $FILE"; return 0; fi
    find_conflicts "$FILE" "$PREFIX" 'mouse_mode[[:space:]]' 'copy_command[[:space:]]' 'copy_on_select[[:space:]]' \
        || die "resolve the conflicting keys in $FILE first (comment them out), then re-run apply"
    note_created_if_missing "$FILE"
    backup_once "$FILE"
    block | append_block "$FILE" "$PREFIX"
    log "applied: $FILE"
    log "running zellij sessions reload config automatically; new sessions pick it up"
}

cmd_revoke() {
    if ! has_block "$FILE"; then log "nothing to revoke"; else remove_blocks "$FILE"; log "block removed: $FILE"; fi
    finish_revoke_file "$FILE"
    state_clear
}

cmd_check() {
    [ -f "$FILE" ] || { log "no config file; nothing to check"; return 0; }
    command -v zellij >/dev/null || { warn "zellij not on PATH; skipping validation"; return 0; }
    zellij --config "$FILE" setup --check | grep -E 'CONFIG FILE' && log "valid: $FILE"
}

dispatch "$@"
