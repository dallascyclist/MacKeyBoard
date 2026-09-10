#!/usr/bin/env bash
# Zellij: KDL config. Two managed blocks:
#   1. option nodes appended at the end of the file;
#   2. a keybind that toggles Zellij's mouse capture, inserted INSIDE the
#      existing top-level `keybinds` node. Zellij only reads the first
#      `keybinds` node, so a second top-level one would be silently ignored.
#      When the file has no `keybinds` node the bind is written as a new
#      top-level node inside block 1 and merges with Zellij's defaults.
MK_TARGET=zellij
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

FILE="${ZELLIJ_CONFIG_FILE:-${XDG_CONFIG_HOME:-$MK_HOME/.config}/zellij/config.kdl}"
PREFIX="//"
TOGGLE_KEY="${MACKEYBOARD_ZELLIJ_TOGGLE_KEY:-Alt m}"
KEYBINDS_RE='^keybinds([[:space:]][^{]*)?[{][[:space:]]*$'

options_block() {
    cat <<'BLOCK'
// Zellij owns the mouse: the wheel scrolls its scrollback, a drag selects a region.
mouse_mode true
// Hand selections to macOS directly instead of relying on OSC 52 support
// in whichever emulator happens to be hosting this session.
copy_command "pbcopy"
// A mouse selection lands on the clipboard without a keystroke.
copy_on_select true
BLOCK
}

# Body for placement inside `keybinds { ... }` (indented one level).
keybind_block() {
    cat <<BLOCK
    // $TOGGLE_KEY flips Zellij's mouse capture off and on. With it off, a drag is a
    // native emulator selection and Cmd+C copies, even inside programs that grab
    // the mouse themselves (Claude Code, vim, htop). Press again to get wheel
    // scrollback and copy-on-select back. The toggle is per client (window).
    shared_except "locked" {
        bind "$TOGGLE_KEY" { ToggleMouseMode; }
    }
BLOCK
}

# Same bind as its own top-level node, for files with no `keybinds` node.
keybind_toplevel_block() { printf 'keybinds {\n'; keybind_block; printf '}\n'; }

has_keybinds_node() { [ -f "$FILE" ] && grep -qE "$KEYBINDS_RE" "$FILE"; }
has_toggle() { has_block "$FILE" && grep -q 'ToggleMouseMode' "$FILE"; }

cmd_diff() {
    log "file: $FILE"
    log "appended at end of file:"; options_block
    if has_keybinds_node; then
        log "inserted inside the existing 'keybinds' node:"; keybind_block
    else
        log "appended (no 'keybinds' node in file; merges with Zellij defaults):"; keybind_toplevel_block
    fi
}

cmd_status() {
    if has_toggle; then print_status_line APPLIED "$FILE"
    elif has_block "$FILE"; then print_status_line "PARTIAL (re-run apply)" "$FILE"
    else print_status_line "NOT APPLIED" "$FILE"; fi
}

cmd_apply() {
    if has_toggle; then log "already applied: $FILE"; return 0; fi
    if ! has_block "$FILE"; then
        find_conflicts "$FILE" "$PREFIX" 'mouse_mode[[:space:]]' 'copy_command[[:space:]]' 'copy_on_select[[:space:]]' \
            || die "resolve the conflicting keys in $FILE first (comment them out), then re-run apply"
    fi
    find_conflicts "$FILE" "$PREFIX" "bind \"$TOGGLE_KEY\"" '.*ToggleMouseMode' \
        || die "a '$TOGGLE_KEY' or ToggleMouseMode binding already exists in $FILE; remove it or set MACKEYBOARD_ZELLIJ_TOGGLE_KEY"
    note_created_if_missing "$FILE"
    backup_once "$FILE"
    if ! has_block "$FILE"; then
        { options_block; has_keybinds_node || keybind_toplevel_block; } | append_block "$FILE" "$PREFIX"
    fi
    if ! has_toggle; then
        if has_keybinds_node; then
            keybind_block | insert_block_after_match "$FILE" "$PREFIX" "$KEYBINDS_RE" \
                || die "could not find the 'keybinds' node header in $FILE"
        else
            keybind_toplevel_block | append_block "$FILE" "$PREFIX"
        fi
    fi
    log "applied: $FILE"
    log "running zellij sessions reload the config automatically; $TOGGLE_KEY toggles Zellij's mouse capture"
}

cmd_revoke() {
    if ! has_block "$FILE"; then log "nothing to revoke"; else remove_blocks "$FILE"; log "blocks removed: $FILE"; fi
    finish_revoke_file "$FILE"
    state_clear
}

cmd_check() {
    [ -f "$FILE" ] || { log "no config file; nothing to check"; return 0; }
    command -v zellij >/dev/null || { warn "zellij not on PATH; skipping validation"; return 0; }
    zellij --config "$FILE" setup --check | grep -E 'CONFIG FILE' && log "valid: $FILE"
}

dispatch "$@"
