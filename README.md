# MacKeyboard

Make every terminal emulator on a Mac behave the same way when Zellij is the
multiplexer inside it: **Cmd+C / Cmd+V copy and paste, mouse wheel scrolls,
mouse selection copies, and the Option key is Alt.** Each change is a clearly
marked block that a single `revoke` removes, leaving the rest of your config
exactly as it was.

Targets: Ghostty, iTerm2, Alacritty, kitty, WezTerm, Warp, and Zellij itself.

## Why the terminals disagree

Zellij captures the mouse, so selecting and scrolling happen inside Zellij.
Zellij then has to hand the selected text to macOS. Without a `copy_command`
it falls back to the OSC 52 escape sequence, which every emulator allows,
prompts for, or blocks differently. Separately, some emulators treat Option
as macOS Option (typing `∫` for Option+B) and others treat it as Alt, so
Zellij's `Alt+h/j/k/l` pane navigation works in one window and types accents
in the next.

## What `apply` sets everywhere

| Behaviour | How |
|---|---|
| Cmd+C copies, Cmd+V pastes | explicit bindings in each emulator |
| Wheel scrolls Zellij scrollback | mouse and scroll events forwarded to the app |
| Shift+drag selects natively | bypasses Zellij's mouse capture when you need it |
| Mouse selection lands on the clipboard | copy-on-select in the emulator and in Zellij |
| Programs may write the clipboard (OSC 52) | write allowed, read denied |
| Both Option keys act as Alt | per-emulator Option/Meta setting |
| Zellij copies via `pbcopy` | `copy_command "pbcopy"`, `copy_on_select true`, `mouse_mode true` |

## Usage

```bash
git clone https://github.com/dallascyclist/MacKeyBoard.git
cd MacKeyboard

bin/mackeyboard diff            # show exactly what would be written
bin/mackeyboard apply           # all targets
bin/mackeyboard apply zellij    # one target
bin/mackeyboard check           # run each tool's own config validator
bin/mackeyboard status          # one line per target
bin/mackeyboard revoke          # remove everything apply added (alias: --revoke)
```

Quit iTerm2 before `apply` or `revoke`; it rewrites its preferences on exit and
the script refuses to run while it is open. Restart Warp after `apply`. The
other emulators reload their config live or on Cmd+Shift+, (Ghostty) and
Cmd+Ctrl+, (kitty).

## How it stays reversible

- Text configs get a delimited block:

  ```
  # >>> MacKeyboard managed block >>> (remove with: mackeyboard revoke ghostty)
  ...
  # <<< MacKeyboard managed block <<<
  ```

  `revoke` deletes only those lines. If the file did not exist, `apply`
  creates it and `revoke` deletes it again.
- Before a file is first touched, a copy is saved beside it as
  `<file>.mackeyboard.orig`. After `revoke` the file is compared to that copy;
  a byte-identical match is reported and the copy removed, a mismatch is
  reported and the copy kept.
- TOML files (Alacritty, Warp) get their settings inserted under an existing
  `[section]` header when there is one, because duplicate tables are illegal
  in TOML. A key you already set yourself is a conflict; `apply` stops and
  names it rather than guessing.
- WezTerm gets a sibling `mackeyboard.lua` module and a one-line
  `require('mackeyboard').apply(config)` before your final `return`.
- iTerm2 has no text config. `apply` installs a dynamic profile named
  **MacKeyboard** that inherits from your current default profile, makes it
  the default, and enables the two global clipboard preferences. Every
  original value is recorded in `state/` and `revoke` restores it exactly.
- `apply` is idempotent.

## Tests

```bash
tests/run.sh
```

Runs the whole apply / re-apply / check / revoke cycle in a throwaway HOME,
including a scratch iTerm2 preferences domain, and asserts byte-identical
restores. Your real configs are never touched.

## Layout

```
bin/mackeyboard     dispatcher
lib/common.sh       managed-block insert/remove, backups, state, conflict checks
targets/*.sh        one script per emulator plus zellij (apply/revoke/status/diff/check)
tests/run.sh        sandboxed end-to-end test
docs/DESIGN.md      design notes
state/              gitignored; what apply changed, for revoke
```

## Requirements

macOS, bash 3.2+, python3 (3.11+ for exact TOML conflict detection; older
versions fall back to a regex scan). Validators are used only if the tool is
installed.

## License

MIT
