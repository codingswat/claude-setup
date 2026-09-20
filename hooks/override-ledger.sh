#!/bin/bash
# override-ledger.sh NAME "command…" — appends one line to a shared ledger every time a
# hook's override word is honoured (GITGUARD, SWEEP, SUITE_OK, GATE_OK, RULES_CAP_OK, or any
# other override word a hook defines). One tab-separated line: date time | folder (the git
# TOPLEVEL basename — never a home path) | NAME | the command's first 200 characters, with
# newlines and tabs flattened. Never refuses, and a missing or unwritable ledger must never
# break the hook that called it — this script only ever appends, and always exits 0.
# Config: none required. Test/override seam: OVERRIDE_LEDGER (path), default
# $HOME/.claude/ledgers/overrides.tsv.
L="${OVERRIDE_LEDGER:-$HOME/.claude/ledgers/overrides.tsv}"
mkdir -p "$(dirname "$L")" 2>/dev/null
# The folder column is the git TOPLEVEL basename, so a call three folders deep inside a
# worktree still logs the repo's own name, not the deep folder's. Outside any repo, fall
# back to $PWD's own basename.
toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
folder="${toplevel:+${toplevel##*/}}"
folder="${folder:-${PWD##*/}}"
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$folder" "$1" "$(printf '%s' "$2" | tr '\n\t' '  ' | cut -c1-200)" >> "$L" 2>/dev/null
exit 0
