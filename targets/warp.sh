#!/usr/bin/env bash
# Warp: ~/.warp/settings.toml (keys verified against Warp's bundled
# settings_schema.json). Cmd+C / Cmd+V are native in Warp and not configurable
# here; this fixes mouse forwarding, OSC 52, copy-on-select and Option-as-Meta.
MK_TARGET=warp
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

FILE="$MK_HOME/.warp/settings.toml"

sec_terminal() {
cat <<'BLOCK'
# Mouse selection goes straight to the system clipboard.
copy_on_select = true
# Forward mouse clicks/drags and wheel events to zellij.
mouse_reporting_enabled = true
scroll_reporting_enabled = true
# Programs may write the clipboard via OSC 52, never read it.
osc52_clipboard_access = "write_only"
BLOCK
}
sec_input() {
cat <<'BLOCK'
# Both Option keys act as Meta/Alt so zellij Alt bindings work.
extra_meta_keys = { left_alt = true, right_alt = true }
BLOCK
}

cmd_diff() {
    log "file: $FILE"
    printf '[terminal]\n';       sec_terminal
    printf '[terminal.input]\n'; sec_input
}
cmd_status() { has_block "$FILE" && print_status_line APPLIED "$FILE" || print_status_line "NOT APPLIED" "$FILE"; }

cmd_apply() {
    if has_block "$FILE"; then log "already applied: $FILE"; return 0; fi
    local ok=0
    toml_conflicts "$FILE" terminal       copy_on_select mouse_reporting_enabled scroll_reporting_enabled osc52_clipboard_access || ok=1
    toml_conflicts "$FILE" terminal.input extra_meta_keys || ok=1
    [ $ok -eq 0 ] || die "resolve the conflicting keys in $FILE first, then re-run apply"
    note_created_if_missing "$FILE"
    backup_once "$FILE"
    sec_terminal | toml_put_section "$FILE" terminal
    sec_input    | toml_put_section "$FILE" terminal.input
    log "applied: $FILE"
    log "restart Warp to pick up the change"
}

cmd_revoke() {
    if ! has_block "$FILE"; then log "nothing to revoke"; else remove_blocks "$FILE"; log "blocks removed: $FILE"; fi
    finish_revoke_file "$FILE"
    state_clear
}

cmd_check() {
    [ -f "$FILE" ] || { log "no config file; nothing to check"; return 0; }
    toml_check "$FILE" && log "valid: $FILE"
}

dispatch "$@"
