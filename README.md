# MacKeyboard

Make every terminal emulator on a Mac behave the same way when Zellij is the
multiplexer inside it: **Cmd+C / Cmd+V copy and paste, mouse wheel scrolls,
mouse selection copies, the Option key is Alt, and one key (`Alt+m`) hands the
mouse back to the emulator for programs that grab it.** Each change is a clearly
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
| One key hands the mouse back to the emulator | Zellij binding `Alt+m` → `ToggleMouseMode`, for programs that grab the mouse |

## Copying inside Zellij

With Zellij owning the mouse there are two copy paths, and Cmd+C is not the
trigger for either of them:

- **Plain shell pane.** Drag to select and let go. Zellij hands the selection
  to `pbcopy` on mouse-up; Cmd+V pastes it anywhere. Cmd+C afterwards is a
  harmless no-op because the emulator has no selection of its own.
- **Program that grabs the mouse** (Claude Code, vim with `mouse=a`, htop,
  lazygit). Zellij forwards the drag to the program and never selects, so
  nothing is copied. Press `Alt+m` to hand the mouse back to the emulator: a
  drag is now a native selection and Cmd+C copies. Press `Alt+m` again to get
  wheel scrollback and copy-on-select back. The toggle is per client, so it
  only affects the window you press it in.

`Alt+m` reaches Zellij only because both Option keys are configured to act as
Alt, which is the same `apply` step. Set `MACKEYBOARD_ZELLIJ_TOGGLE_KEY` before
`apply` to bind a different key (Zellij syntax, e.g. `"Alt Shift m"`).

The emulators' own bypass still works without toggling: Option+drag in iTerm2,
Shift+drag in Ghostty, kitty, Alacritty and WezTerm.

## Usage

```bash
git clone https://github.com/dallascyclist/MacKeyBoard.git
cd MacKeyBoard

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
  the default, enables the two global clipboard preferences, and silences the
  "mouse reporting has prevented making a selection" alert (with Zellij owning
  the mouse, a drag in a shell pane was already copied via `pbcopy`, and in a
  mouse-grabbing program `Alt+m` is the answer, so the alert only nags). Every
  original value is recorded in `state/` and `revoke` restores it
  exactly.
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
