#!/usr/bin/env bash
# End-to-end test in a throwaway HOME. Never touches real configs.
# Exercises: diff, apply, idempotent re-apply, check, status, revoke,
# byte-identical restore, created-file cleanup, and the iTerm2 defaults
# round-trip against a scratch preferences domain.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="${1:-$(mktemp -d)}"
export MACKEYBOARD_HOME="$SANDBOX/home"
export MACKEYBOARD_STATE_DIR="$SANDBOX/state"
export MACKEYBOARD_ITERM_DOMAIN="com.mackeyboard.test.$$"
unset XDG_CONFIG_HOME KITTY_CONFIG_DIRECTORY ZELLIJ_CONFIG_FILE
H="$MACKEYBOARD_HOME"
MK="$ROOT/bin/mackeyboard"
fail=0
ok()   { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }
step() { printf '\n== %s\n' "$*"; }

# ---------------------------------------------------------------- fixtures
step "seeding fixtures in $H"
mkdir -p "$H/.config/zellij" "$H/.config/alacritty" "$H/.config/wezterm" "$H/.warp" \
         "$H/Library/Application Support/com.mitchellh.ghostty" "$H/Library/Application Support/iTerm2/DynamicProfiles"
# Real-shaped configs
# Self-contained (never copy the real config: it may already carry our block)
printf 'keybinds clear-defaults=true {\n    normal {\n        bind "Alt h" { MoveFocusOrTab "left"; }\n    }\n}\ntheme "ansi"\n// mouse_mode false\n' > "$H/.config/zellij/config.kdl"
printf '# my ghostty config\ntheme = Adwaita Dark\n' > "$H/Library/Application Support/com.mitchellh.ghostty/config"
printf '[general]\ndefault_session_mode = "agent"\n\n[appearance]\n[appearance.vertical_tabs]\nenabled = true\n' > "$H/.warp/settings.toml"
# Alacritty with an existing [window] table (exercises insert-under-header)
printf '[window]\nopacity = 0.95\n\n[font]\nsize = 13\n' > "$H/.config/alacritty/alacritty.toml"
# WezTerm with a non-standard variable name and trailing comment
printf "local wezterm = require 'wezterm'\nlocal cfg = wezterm.config_builder()\ncfg.font_size = 13\n\nreturn cfg\n-- eof\n" > "$H/.config/wezterm/wezterm.lua"
# kitty: no file on purpose (exercises create + delete)

# iTerm2 scratch domain with a Default profile and one pre-existing bool
defaults write "$MACKEYBOARD_ITERM_DOMAIN" "Default Bookmark Guid" -string "ORIG-GUID-1234"
defaults write "$MACKEYBOARD_ITERM_DOMAIN" "New Bookmarks" -array '{ "Guid" = "ORIG-GUID-1234"; "Name" = "My Default"; }'
defaults write "$MACKEYBOARD_ITERM_DOMAIN" AllowClipboardAccess -bool false
# CopySelection intentionally left unset

snap="$SANDBOX/snap"; mkdir -p "$snap"
for f in .config/zellij/config.kdl .config/alacritty/alacritty.toml .config/wezterm/wezterm.lua .warp/settings.toml \
         "Library/Application Support/com.mitchellh.ghostty/config"; do
    mkdir -p "$snap/$(dirname "$f")"; cp "$H/$f" "$snap/$f"
done

# ---------------------------------------------------------------- diff / status before
step "diff (dry run) runs for every target"
$MK diff >/dev/null && ok "diff exits 0" || bad "diff failed"
step "status before apply"
$MK status | tee "$SANDBOX/status-before.txt"
grep -q APPLIED "$SANDBOX/status-before.txt" && ! grep -qE '^[a-z]+ +APPLIED' "$SANDBOX/status-before.txt" && ok "nothing applied yet" || bad "unexpected APPLIED before apply"

# ---------------------------------------------------------------- apply
step "apply"
$MK apply || bad "apply returned non-zero"
step "status after apply"
$MK status | tee "$SANDBOX/status-after.txt"
n=$(grep -cE '^[a-z0-9]+ +APPLIED ' "$SANDBOX/status-after.txt" || true)
[ "$n" -eq 7 ] && ok "all 7 targets report APPLIED" || bad "expected 7 APPLIED, got $n"

step "content assertions"
g="$H/Library/Application Support/com.mitchellh.ghostty/config"
grep -q '^macos-option-as-alt = true' "$g" && grep -q 'keybind = super+c=copy_to_clipboard' "$g" && ok "ghostty block present" || bad "ghostty block missing"
head -n 2 "$g" | grep -q 'my ghostty config' && ok "ghostty original header intact" || bad "ghostty original content damaged"
k="$H/.config/kitty/kitty.conf"
[ -f "$k" ] && grep -q '^macos_option_as_alt both' "$k" && ok "kitty file created with block" || bad "kitty not created"
z="$H/.config/zellij/config.kdl"
grep -q '^copy_command "pbcopy"' "$z" && ok "zellij copy_command present" || bad "zellij block missing"
grep -q 'bind "Alt m" { ToggleMouseMode; }' "$z" && ok "zellij mouse toggle bound" || bad "zellij mouse toggle missing"
awk '/ToggleMouseMode/{t=NR} /^theme "ansi"/{th=NR} END{exit !(t && th && t<th)}' "$z" && ok "zellij toggle sits inside existing keybinds node" || bad "zellij toggle not inside keybinds node"
a="$H/.config/alacritty/alacritty.toml"
awk '/^\[window\]/{w=1;next} /^\[/{w=0} w && /option_as_alt/{found=1} END{exit !found}' "$a" && ok "alacritty option_as_alt inside existing [window]" || bad "alacritty option_as_alt not under [window]"
[ "$(grep -c '^\[window\]' "$a")" -eq 1 ] && ok "alacritty has exactly one [window] table" || bad "duplicate [window]"
w="$H/.config/wezterm/wezterm.lua"
grep -q "^cfg = require('mackeyboard').apply(cfg)" "$w" && ok "wezterm detected variable name 'cfg'" || bad "wezterm block wrong"
awk '/apply\(cfg\)/{seen=1} /^return cfg/{ if(seen) r=1 } END{exit !r}' "$w" && ok "wezterm block sits before final return" || bad "wezterm block after return"
[ -f "$H/.config/wezterm/mackeyboard.lua" ] && ok "wezterm module written" || bad "wezterm module missing"
wp="$H/.warp/settings.toml"
grep -q '^\[terminal.input\]' "$wp" && grep -q 'extra_meta_keys' "$wp" && ok "warp [terminal.input] added" || bad "warp block missing"
j="$H/Library/Application Support/iTerm2/DynamicProfiles/MacKeyboard.json"
[ -f "$j" ] && grep -q '"Dynamic Profile Parent Name": "My Default"' "$j" && ok "iterm2 profile inherits from 'My Default'" || bad "iterm2 parent wrong"
[ "$(defaults read "$MACKEYBOARD_ITERM_DOMAIN" 'Default Bookmark Guid')" = "A7C0F1E2-4B3D-4C5E-9F60-4D41434B4559" ] && ok "iterm2 default guid switched" || bad "iterm2 default guid not switched"
[ "$(defaults read "$MACKEYBOARD_ITERM_DOMAIN" CopySelection)" = "1" ] && ok "iterm2 CopySelection on" || bad "iterm2 CopySelection not set"
for f in .config/zellij/config.kdl .config/alacritty/alacritty.toml .config/wezterm/wezterm.lua .warp/settings.toml; do
    [ -f "$H/$f.mackeyboard.orig" ] && cmp -s "$H/$f.mackeyboard.orig" "$snap/$f" && ok "backup matches original: $f" || bad "backup wrong: $f"
done
[ ! -f "$k.mackeyboard.orig" ] && ok "no backup for created kitty file" || bad "spurious kitty backup"

# ---------------------------------------------------------------- validators
step "check (tool validators)"
$MK check && ok "all validators pass" || bad "a validator failed"

# ---------------------------------------------------------------- idempotence
step "apply again (idempotent)"
$MK apply >/dev/null || bad "second apply failed"
for f in "$g" "$k" "$z" "$a" "$w" "$wp"; do
    c=$(grep -c '>>> MacKeyboard managed block >>>' "$f")
    case "$f" in "$a") want=4;; "$wp") want=2;; "$z") want=2;; *) want=1;; esac
    [ "$c" -eq "$want" ] && ok "$(basename "$f"): $c block(s), unchanged" || bad "$(basename "$f"): $c blocks, expected $want"
done
$MK apply iterm2 >/dev/null
grep -q 'orig_Default Bookmark Guid=ORIG-GUID-1234' "$MACKEYBOARD_STATE_DIR/iterm2.state" && ok "iterm2 original guid still remembered after re-apply" || bad "iterm2 original overwritten on re-apply"

# ---------------------------------------------------------------- revoke
step "revoke"
$MK --revoke || bad "revoke returned non-zero"
step "status after revoke"
$MK status | tee "$SANDBOX/status-revoked.txt"
grep -qE '^[a-z0-9]+ +APPLIED ' "$SANDBOX/status-revoked.txt" && bad "something still APPLIED" || ok "nothing APPLIED"
for f in .config/zellij/config.kdl .config/alacritty/alacritty.toml .config/wezterm/wezterm.lua .warp/settings.toml \
         "Library/Application Support/com.mitchellh.ghostty/config"; do
    cmp -s "$H/$f" "$snap/$f" && ok "byte-identical restore: $f" || { bad "restore differs: $f"; diff "$snap/$f" "$H/$f" || true; }
    [ ! -f "$H/$f.mackeyboard.orig" ] && ok "backup cleaned: $f" || bad "backup left behind: $f"
done
[ ! -f "$k" ] && ok "kitty created file deleted" || bad "kitty file left behind"
[ ! -f "$H/.config/wezterm/mackeyboard.lua" ] && ok "wezterm module deleted" || bad "wezterm module left behind"
[ ! -f "$j" ] && ok "iterm2 profile deleted" || bad "iterm2 profile left behind"
[ "$(defaults read "$MACKEYBOARD_ITERM_DOMAIN" 'Default Bookmark Guid')" = "ORIG-GUID-1234" ] && ok "iterm2 default guid restored" || bad "iterm2 guid not restored"
[ "$(defaults read "$MACKEYBOARD_ITERM_DOMAIN" AllowClipboardAccess)" = "0" ] && ok "iterm2 AllowClipboardAccess restored to false" || bad "AllowClipboardAccess not restored"
defaults read "$MACKEYBOARD_ITERM_DOMAIN" CopySelection >/dev/null 2>&1 && bad "CopySelection should be unset again" || ok "iterm2 CopySelection deleted (was unset)"
[ -z "$(ls -A "$MACKEYBOARD_STATE_DIR" 2>/dev/null)" ] && ok "state dir empty" || bad "state left behind: $(ls "$MACKEYBOARD_STATE_DIR")"

# ---------------------------------------------------------------- conflict path
step "conflict detection"
printf '\nmouse_mode false\n' >> "$z"
if bash "$ROOT/targets/zellij.sh" apply 2>"$SANDBOX/conflict.txt"; then bad "zellij apply should refuse on conflict"; else grep -q 'mouse_mode' "$SANDBOX/conflict.txt" && ok "zellij refused and named mouse_mode" || bad "zellij refused without naming key"; fi
# Zellij config with no keybinds node at all: the toggle must become a top-level keybinds node
nk="$SANDBOX/no-keybinds.kdl"; printf 'theme "ansi"\n' > "$nk"
if ZELLIJ_CONFIG_FILE="$nk" bash "$ROOT/targets/zellij.sh" apply >/dev/null 2>&1 && grep -q '^keybinds {' "$nk" && grep -q 'ToggleMouseMode' "$nk"; then ok "zellij no-keybinds: toggle added as top-level keybinds node"; else bad "zellij no-keybinds: apply failed or node missing"; fi
[ "$(grep -c '>>> MacKeyboard managed block >>>' "$nk")" -eq 1 ] && ok "zellij no-keybinds: single block" || bad "zellij no-keybinds: $(grep -c '>>> MacKeyboard managed block >>>' "$nk") blocks"
ZELLIJ_CONFIG_FILE="$nk" bash "$ROOT/targets/zellij.sh" check >/dev/null 2>&1 && ok "zellij no-keybinds: config validates" || bad "zellij no-keybinds: config invalid"
ZELLIJ_CONFIG_FILE="$nk" bash "$ROOT/targets/zellij.sh" revoke >/dev/null 2>&1
[ "$(cat "$nk")" = 'theme "ansi"' ] && ok "zellij no-keybinds: revoke restored original" || bad "zellij no-keybinds: revoke left: $(cat "$nk")"
printf '[terminal]\nosc52 = "Disabled"\n' >> "$a"
if bash "$ROOT/targets/alacritty.sh" apply 2>"$SANDBOX/conflict2.txt"; then bad "alacritty apply should refuse on conflict"; else grep -q 'osc52' "$SANDBOX/conflict2.txt" && ok "alacritty refused and named osc52" || bad "alacritty refused without naming key"; fi

# ---------------------------------------------------------------- cleanup
defaults delete "$MACKEYBOARD_ITERM_DOMAIN" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$MACKEYBOARD_ITERM_DOMAIN.plist"
printf '\n'
if [ $fail -eq 0 ]; then printf 'ALL TESTS PASSED  (sandbox: %s)\n' "$SANDBOX"; else printf 'TESTS FAILED  (sandbox kept at: %s)\n' "$SANDBOX"; exit 1; fi
