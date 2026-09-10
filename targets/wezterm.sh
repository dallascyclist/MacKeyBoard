#!/usr/bin/env bash
# WezTerm: Lua config. Settings live in a sibling module (mackeyboard.lua);
# the managed block in wezterm.lua is a require(...).apply(config) call
# inserted before the final `return <config>` line.
MK_TARGET=wezterm
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

XDG_FILE="${XDG_CONFIG_HOME:-$MK_HOME/.config}/wezterm/wezterm.lua"
DOT_FILE="$MK_HOME/.wezterm.lua"
if   [ -f "$XDG_FILE" ]; then FILE="$XDG_FILE"
elif [ -f "$DOT_FILE" ]; then FILE="$DOT_FILE"
else                          FILE="$XDG_FILE"; fi
DIR="$(dirname "$FILE")"
MODULE="$DIR/mackeyboard.lua"
PREFIX="--"
RETURN_RE='^[[:space:]]*return[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$'

module() {
cat <<'LUA'
-- MacKeyboard: consistent copy/paste, mouse and Option-key behaviour for
-- WezTerm. Managed by https://github.com/dallascyclist/MacKeyBoard —
-- remove with `mackeyboard revoke wezterm`.
local wezterm = require 'wezterm'
local act = wezterm.action
local M = {}

function M.apply(config)
  -- Both Option keys act as Alt so zellij Alt bindings work.
  config.send_composed_key_when_left_alt_is_pressed = false
  config.send_composed_key_when_right_alt_is_pressed = false
  -- Shift+drag selects natively even while zellij owns the mouse.
  config.bypass_mouse_reporting_modifiers = 'SHIFT'

  -- Explicit Cmd+C / Cmd+V so nothing else can shadow them.
  config.keys = config.keys or {}
  table.insert(config.keys, { key = 'c', mods = 'SUPER', action = act.CopyTo 'Clipboard' })
  table.insert(config.keys, { key = 'v', mods = 'SUPER', action = act.PasteFrom 'Clipboard' })

  -- Mouse selection goes straight to the system clipboard.
  config.mouse_bindings = config.mouse_bindings or {}
  table.insert(config.mouse_bindings, {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = act.CompleteSelection 'ClipboardAndPrimarySelection',
  })
  return config
end

return M
LUA
}

block() {
    local var="$1"
    printf "package.path = package.path .. ';%s/?.lua'\n" "$DIR"
    printf "%s = require('mackeyboard').apply(%s)\n" "$var" "$var"
}

new_config() {
cat <<'LUA'
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

return config
LUA
}

config_var() {
    grep -E "$RETURN_RE" "$FILE" | tail -n 1 | sed -E 's/^[[:space:]]*return[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/'
}

cmd_diff() {
    log "module: $MODULE"; module
    log "block in $FILE (before the final 'return <config>'):"; block "config"
}
cmd_status() { has_block "$FILE" && print_status_line APPLIED "$FILE" || print_status_line "NOT APPLIED" "$FILE"; }

cmd_apply() {
    if has_block "$FILE"; then log "already applied: $FILE"; return 0; fi
    note_created_if_missing "$FILE"
    if [ "$(state_get created)" = "1" ]; then new_config > "$FILE"; fi
    backup_once "$FILE"
    local var; var="$(config_var)"
    [ -n "$var" ] || die "$FILE has no final 'return <name>' line; add one (or use wezterm.config_builder()) and re-run"
    module > "$MODULE"
    block "$var" | insert_block_before_last_match "$FILE" "$PREFIX" "$RETURN_RE"
    log "applied: $FILE (+ $MODULE)"
    log "WezTerm live-reloads its config; no restart needed"
}

cmd_revoke() {
    if ! has_block "$FILE"; then log "nothing to revoke"; else remove_blocks "$FILE"; log "block removed: $FILE"; fi
    [ -f "$MODULE" ] && { rm -f "$MODULE"; log "removed: $MODULE"; }
    finish_revoke_file "$FILE"
    state_clear
}

cmd_check() {
    [ -f "$FILE" ] || { log "no config file; nothing to check"; return 0; }
    command -v wezterm >/dev/null || { warn "wezterm not on PATH; skipping validation"; return 0; }
    wezterm --config-file "$FILE" show-keys >/dev/null && log "valid: $FILE"
}

dispatch "$@"
