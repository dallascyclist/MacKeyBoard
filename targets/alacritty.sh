#!/usr/bin/env bash
# Alacritty: TOML config. Duplicate [tables] are illegal in TOML, so each piece
# is inserted under an existing section header when present.
MK_TARGET=alacritty
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

FILE="${XDG_CONFIG_HOME:-$MK_HOME/.config}/alacritty/alacritty.toml"

sec_window()    { printf '%s\n' '# Both Option keys act as Alt so zellij Alt bindings work.' 'option_as_alt = "Both"'; }
sec_selection() { printf '%s\n' '# Mouse selection goes straight to the system clipboard.' 'save_to_clipboard = true'; }
sec_terminal()  { printf '%s\n' '# Programs may write the clipboard via OSC 52, never read it.' 'osc52 = "OnlyCopy"'; }
sec_keyboard()  {
cat <<'BLOCK'
# Explicit Cmd+C / Cmd+V so nothing else can shadow them.
bindings = [
  { key = "C", mods = "Command", action = "Copy" },
  { key = "V", mods = "Command", action = "Paste" },
]
BLOCK
}

cmd_diff() {
    log "file: $FILE"
    printf '[window]\n';    sec_window
    printf '[selection]\n'; sec_selection
    printf '[terminal]\n';  sec_terminal
    printf '[keyboard]\n';  sec_keyboard
}
cmd_status() { has_block "$FILE" && print_status_line APPLIED "$FILE" || print_status_line "NOT APPLIED" "$FILE"; }

cmd_apply() {
    if has_block "$FILE"; then log "already applied: $FILE"; return 0; fi
    local ok=0
    toml_conflicts "$FILE" window    option_as_alt     || ok=1
    toml_conflicts "$FILE" selection save_to_clipboard || ok=1
    toml_conflicts "$FILE" terminal  osc52             || ok=1
    toml_conflicts "$FILE" keyboard  bindings          || ok=1
    [ $ok -eq 0 ] || die "resolve the conflicting keys in $FILE first, then re-run apply"
    note_created_if_missing "$FILE"
    backup_once "$FILE"
    sec_window    | toml_put_section "$FILE" window
    sec_selection | toml_put_section "$FILE" selection
    sec_terminal  | toml_put_section "$FILE" terminal
    sec_keyboard  | toml_put_section "$FILE" keyboard
    log "applied: $FILE"
    log "Alacritty live-reloads its config; no restart needed"
}

cmd_revoke() {
    if ! has_block "$FILE"; then log "nothing to revoke"; else remove_blocks "$FILE"; log "blocks removed: $FILE"; fi
    finish_revoke_file "$FILE"
    state_clear
}

cmd_check() {
    [ -f "$FILE" ] || { log "no config file; nothing to check"; return 0; }
    toml_check "$FILE"
    if command -v alacritty >/dev/null; then
        alacritty migrate --dry-run --config-file "$FILE" >/dev/null
    fi
    log "valid: $FILE"
}

dispatch "$@"
