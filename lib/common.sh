#!/usr/bin/env bash
# Shared helpers for MacKeyboard target scripts.
# Every target script sets MK_TARGET and sources this file.

set -euo pipefail

MK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MK_HOME="${MACKEYBOARD_HOME:-$HOME}"
MK_STATE_DIR="${MACKEYBOARD_STATE_DIR:-$MK_ROOT/state}"
MK_TAG="MacKeyboard managed block"
: "${MK_TARGET:?MK_TARGET must be set before sourcing common.sh}"

mkdir -p "$MK_STATE_DIR"

# ---------------------------------------------------------------- logging
log()  { printf '[%s] %s\n' "$MK_TARGET" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$MK_TARGET" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$MK_TARGET" "$*" >&2; exit 1; }

# ---------------------------------------------------------------- markers
# $1 = comment prefix for the file format ("#", "//", "--")
mk_begin() { printf '%s >>> %s >>> (remove with: mackeyboard revoke %s)' "$1" "$MK_TAG" "$MK_TARGET"; }
mk_end()   { printf '%s <<< %s <<<' "$1" "$MK_TAG"; }

has_block() { [ -f "$1" ] && grep -qF ">>> $MK_TAG >>>" "$1"; }

# Print file contents with every managed block removed.
strip_blocks() {
    # When MK_DROP_SEP=1, a blank line is held back one line so that the
    # separator append_block writes before a block is dropped with the block.
    awk -v tag="$MK_TAG" -v dropsep="${MK_DROP_SEP:-0}" '
        index($0, ">>> " tag " >>>") { skipping = 1; if (dropsep) pending = 0; next }
        index($0, "<<< " tag " <<<") { skipping = 0; next }
        skipping { next }
        /^$/ { if (pending) print ""; pending = 1; next }
        { if (pending) { print ""; pending = 0 } print }
        END { if (pending) print "" }
    ' "$1"
}

# Remove all managed blocks from a file in place.
remove_blocks() {
    local file="$1" tmp
    has_block "$file" || return 0
    tmp="$(mktemp)"
    MK_DROP_SEP="$(state_get added_separator)" strip_blocks "$file" > "$tmp"
    if [ "$(state_get added_newline)" = "1" ]; then
        perl -pi -e 'chomp if eof' "$tmp"
    fi
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# ---------------------------------------------------------------- state
# Tiny key=value store per target. Values must not contain newlines.
state_file() { printf '%s/%s.state' "$MK_STATE_DIR" "$MK_TARGET"; }
state_set() {
    local key="$1" val="$2" f tmp
    f="$(state_file)"; tmp="$(mktemp)"
    [ -f "$f" ] && grep -v "^${key}=" "$f" > "$tmp" || true
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
    mv "$tmp" "$f"
}
state_get() {
    local f; f="$(state_file)"
    [ -f "$f" ] && sed -n "s/^$1=//p" "$f" | tail -n 1 || true
}
state_clear() { rm -f "$(state_file)"; }

# ---------------------------------------------------------------- files
ensure_parent() { mkdir -p "$(dirname "$1")"; }

# Save a one-time pristine copy next to the file. Never overwrites.
backup_once() {
    local file="$1" orig="$1.mackeyboard.orig"
    [ -f "$file" ] || return 0
    [ "$(state_get created)" = "1" ] && return 0
    [ -f "$orig" ] && return 0
    cp -p "$file" "$orig"
    log "backup saved: $orig"
}

# Record whether apply created the file, so revoke knows to delete it.
note_created_if_missing() {
    if [ -f "$1" ]; then
        state_set created 0
    else
        state_set created 1
        ensure_parent "$1"
        : > "$1"
        log "created: $1"
    fi
}

# After revoke: delete files we created; verify others match the .orig backup.
finish_revoke_file() {
    local file="$1" orig="$1.mackeyboard.orig"
    if [ "$(state_get created)" = "1" ]; then
        if [ -f "$file" ] && [ -z "$(tr -d '[:space:]' < "$file")" ]; then
            rm -f "$file"
            log "removed file we created: $file"
        elif [ -f "$file" ]; then
            warn "we created $file but it now has other content; left in place"
        fi
        return 0
    fi
    if [ -f "$orig" ]; then
        if cmp -s "$file" "$orig"; then
            rm -f "$orig"
            log "restored byte-identical to original; backup removed"
        else
            warn "content differs from $orig (edited outside MacKeyboard?); backup kept"
        fi
    fi
}

# ---------------------------------------------------------------- inserts
# All inserters read the block body from stdin.

# Append a managed block at end of file.
append_block() {
    local file="$1" prefix="$2" body
    body="$(cat)"
    if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then
        printf '\n' >> "$file"; state_set added_newline 1
    fi
    state_set added_separator 1
    {
        printf '\n'
        mk_begin "$prefix"; printf '\n'
        printf '%s\n' "$body"
        mk_end "$prefix"; printf '\n'
    } >> "$file"
}

# Insert a managed block immediately after the first line matching an
# extended regex. Exit 1 (writing nothing) if no line matches.
insert_block_after_match() {
    local file="$1" prefix="$2" regex="$3" body tmp
    body="$(cat)"
    grep -qE "$regex" "$file" || return 1
    tmp="$(mktemp)"
    MK_BODY="$body" MK_RE="$regex" awk -v begin="$(mk_begin "$prefix")" -v end="$(mk_end "$prefix")" '
        { print }
        !done && $0 ~ ENVIRON["MK_RE"] { print begin; print ENVIRON["MK_BODY"]; print end; done = 1 }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"; rm -f "$tmp"
}

# Insert a managed block immediately before the LAST line matching a regex.
# Exit 1 (writing nothing) if no line matches.
insert_block_before_last_match() {
    local file="$1" prefix="$2" regex="$3" body tmp last
    body="$(cat)"
    last="$(grep -nE "$regex" "$file" | tail -n 1 | cut -d: -f1)"
    [ -n "$last" ] || return 1
    tmp="$(mktemp)"
    MK_BODY="$body" awk -v n="$last" -v begin="$(mk_begin "$prefix")" -v end="$(mk_end "$prefix")" '
        NR == n { print begin; print ENVIRON["MK_BODY"]; print end }
        { print }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"; rm -f "$tmp"
}

# TOML helper: put `body` inside [section]. If the header exists, insert right
# under it; otherwise append header + body as one managed block.
toml_put_section() {
    local file="$1" section="$2" body
    body="$(cat)"
    local esc; esc="${section//./\\.}"
    if printf '%s\n' "$body" | insert_block_after_match "$file" "#" "^[[:space:]]*\\[${esc}\\][[:space:]]*$"; then
        return 0
    fi
    printf '[%s]\n%s\n' "$section" "$body" | append_block "$file" "#"
}

# ---------------------------------------------------------------- conflicts
# Report keys the user already sets (uncommented, outside our block).
# $1 = file, $2 = comment prefix, remaining = key regexes (anchored at line start).
# Returns 1 and prints the offenders if any are found.
find_conflicts() {
    local file="$1" prefix="$2"; shift 2
    local found=0 key
    [ -f "$file" ] || return 0
    for key in "$@"; do
        if strip_blocks "$file" | grep -vE "^[[:space:]]*${prefix}" | grep -qE "^[[:space:]]*${key}"; then
            printf '  already set outside MacKeyboard block: %s\n' "$key" >&2
            found=1
        fi
    done
    return $found
}

# ---------------------------------------------------------------- output
print_status_line() {
    # $1 = APPLIED|NOT APPLIED|N/A  $2 = detail
    printf '%-10s %-12s %s\n' "$MK_TARGET" "$1" "$2"
}

# Standard entry point: target scripts define cmd_apply, cmd_revoke,
# cmd_status, cmd_diff, cmd_check then call `dispatch "$@"`.
dispatch() {
    local cmd="${1:-status}"; cmd="${cmd#--}"
    case "$cmd" in
        apply|revoke|status|diff|check) "cmd_$cmd" ;;
        *) die "unknown command: $cmd (apply|revoke|status|diff|check)" ;;
    esac
}

# ---------------------------------------------------------------- TOML
# toml_conflicts FILE SECTION KEY...  -> 1 if the user already sets any KEY
# inside [SECTION] (outside our block). Uses tomllib when available (3.11+),
# otherwise a conservative regex scan.
toml_conflicts() {
    local file="$1" section="$2"; shift 2
    [ -f "$file" ] || return 0
    if python3 -c 'import tomllib' 2>/dev/null; then
        strip_blocks "$file" | python3 -c '
import sys, tomllib
section, keys = sys.argv[1], sys.argv[2:]
try:
    data = tomllib.loads(sys.stdin.read())
except Exception as e:
    print(f"  cannot parse existing TOML: {e}", file=sys.stderr); sys.exit(1)
node = data
for part in section.split("."):
    node = node.get(part, {}) if isinstance(node, dict) else {}
bad = [k for k in keys if isinstance(node, dict) and k in node]
for k in bad:
    print(f"  already set outside MacKeyboard block: [{section}] {k}", file=sys.stderr)
sys.exit(1 if bad else 0)
' "$section" "$@"
    else
        local regexes=() k
        for k in "$@"; do regexes+=("${k}[[:space:]]*="); done
        find_conflicts "$file" "#" "${regexes[@]}"
    fi
}

# toml_check FILE -> parse with tomllib if available, else no-op.
toml_check() {
    if python3 -c 'import tomllib' 2>/dev/null; then
        python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1"
    else
        warn "python3 lacks tomllib (needs 3.11+); skipping TOML parse check"
    fi
}
