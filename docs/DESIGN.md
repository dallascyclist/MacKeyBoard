# MacKeyboard — design

Date: 2026-09-10

## Problem

Several terminal emulators are installed on one Mac (Ghostty, iTerm2, Alacritty,
kitty, WezTerm, Warp) and Zellij is used as the multiplexer inside all of them.
Cmd+Tab switches between them freely, but copy, paste, mouse selection, mouse
scrolling and the Option key behave differently in each one. The differences
come from three places:

1. Zellij captures the mouse. Selection and scrolling happen inside Zellij, and
   Zellij needs a way to place text on the macOS clipboard. With no
   `copy_command` set it falls back to the OSC 52 escape sequence, which each
   emulator allows, prompts for, or blocks differently.
2. The Option key is "macOS Option" in some emulators and "Alt" in others, so
   Zellij's `Alt+h/j/k/l` and `Alt+arrow` bindings work in some terminals and
   type accented characters in others.
3. Cmd+C / Cmd+V are defaults everywhere but are easy to shadow; making them
   explicit removes doubt.

## Behavior contract

Every target is configured so that:

- Cmd+C copies the current selection, Cmd+V pastes from the clipboard.
- Mouse wheel scrolls Zellij's scrollback (events forwarded to the app).
- Shift+drag selects natively in the emulator, bypassing Zellij's mouse capture.
- Copy-on-select is on: a mouse selection lands on the clipboard by itself.
- Terminal programs may write the clipboard via OSC 52 (never read it).
- Both Option keys act as Alt.
- Zellij uses `pbcopy`, copies on select, and has mouse mode on.

## Repository layout

    bin/mackeyboard       dispatcher: apply | revoke | status | diff | check [target...]
    lib/common.sh         managed-block insert/remove, backups, state, conflict checks
    targets/<name>.sh     one script per emulator plus zellij; each implements
                          apply / revoke / status / diff / check
    tests/run.sh          sandboxed end-to-end test against a throwaway HOME
    state/                gitignored; what apply created or changed, for revoke
    docs/DESIGN.md        this file

## Mechanism

**Text configs** (Ghostty, kitty, Zellij, Alacritty, Warp, WezTerm) receive a
clearly delimited managed block:

    # >>> MacKeyboard managed block >>> (remove with: mackeyboard revoke <target>)
    ...settings...
    # <<< MacKeyboard managed block <<<

`revoke` deletes only lines between and including the markers. Nothing else in
the file is touched.

- Last-wins formats (Ghostty, kitty, Zellij KDL): the block is appended.
- TOML (Alacritty, Warp): duplicate tables are illegal in TOML, so the block is
  inserted directly under an existing `[section]` header when one exists, and
  otherwise appended together with the header. A key already set by the user in
  that file is a conflict; apply aborts and names the key rather than guessing.
- Lua (WezTerm): settings live in a sibling module `mackeyboard.lua`. The
  managed block in `wezterm.lua` is a `require(...).apply(config)` call inserted
  before the final `return <config>` line. If no config exists, a minimal one is
  created.

**iTerm2** has no text config. Apply drops a dynamic profile file named
`MacKeyboard.json` whose parent is the current default profile, then points
`Default Bookmark Guid` at it and enables the two global clipboard preferences.
Every original value is recorded in state, and revoke restores each one exactly
(or deletes it if it was unset). iTerm2 rewrites its plist on quit, so apply and
revoke refuse to run while iTerm2 is open.

**Safety**

- Before a file is first modified a one-time copy is saved next to it as
  `<file>.mackeyboard.orig`. It is never overwritten.
- If apply created the file, revoke deletes it (and the `.orig` is not needed).
- Apply is idempotent: running it twice leaves one block.
- After revoke, the file is compared to the `.orig`; a byte-identical match is
  reported and the `.orig` is removed. A mismatch is reported and the `.orig`
  is kept.
- `check` runs the tool's own validator where one exists (Ghostty
  `+validate-config`, `zellij setup --check`, `wezterm show-keys`, kitty's
  config loader, Python `tomllib` for TOML).

## Out of scope

- Terminal.app (not requested), tmux (not used), Warp keybinding overrides
  beyond the settings file.
- Pushing to GitHub. The repo is initialized and committed locally; publishing
  is a manual step.
