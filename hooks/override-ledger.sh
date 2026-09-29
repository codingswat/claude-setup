#!/bin/bash
# override-ledger.sh NAME "command…" ["matched pattern"] — appends one line to a shared
# ledger every time a hook's override word is honoured (GITGUARD, SWEEP, SUITE_OK, GATE_OK,
# RULES_CAP_OK, or any other override word a hook defines).
# One tab-separated line: date time | folder (the git TOPLEVEL basename — never a home
# path) | NAME | the pattern the override bypassed, as the calling hook names it | an
# excerpt of the command, newlines and tabs flattened.
# WHY the third column and the excerpt shape: the ledger is read to answer "what was
# actually waved through?". A fixed 200-character cut answered that with whatever the
# command STARTED with, so 210 characters of padding in front of a force-push logged a
# line with no sign of the force-push in it — the act was invisible in the record of the
# act. So: the pattern the hook matched is logged as its own column, and a command longer
# than 240 characters is logged as its first 120 characters, " ... ", and its LAST 120 —
# the tail, where the dangerous part usually sits, can no longer be pushed out of the line.
# EXIT STATUS IS PART OF THE CONTRACT: 0 only when the line was actually written. A ledger
# path that cannot be created or appended to exits 1 (quietly — no shell error is leaked),
# and every calling hook must then REFUSE the override instead of honouring it: an
# override nobody can see is not an approved act.
# Config: none required. Test/override seam: OVERRIDE_LEDGER (path), default
# $HOME/.claude/ledgers/overrides.tsv.
# Tests: hooks/test-hooks.sh (sections 20, 24, 28).
L="${OVERRIDE_LEDGER:-$HOME/.claude/ledgers/overrides.tsv}"
mkdir -p "${L%/*}" 2>/dev/null
# The folder column is the git TOPLEVEL basename, so a call three folders deep inside a
# worktree still logs the repo's own name, not the deep folder's. Outside any repo, fall
# back to $PWD's own basename.
toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
folder="${toplevel:+${toplevel##*/}}"
folder="${folder:-${PWD##*/}}"
# A ledger is a file to be read and reviewed, so it never holds a secret in clear text: the
# value of any NAME=value whose NAME holds KEY, TOKEN, SECRET, PASSWORD or PASS, and the
# credentials in a URL (user, colon, password, then @host after the scheme; or a long bare token as the user), are replaced by *** before
# the line is cut and written. Tests: hooks/test-hooks.sh, `attack fixes (1)` (F9).
mask_secrets() {
  sed -E \
    -e "s/([-A-Za-z0-9_]*([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss])[A-Za-z0-9_]*)=(\"[^\"]*\"|'[^']*'|[^ ]*)/\\1=***/g" \
    -e 's#(://[^/: @]*):[^@ /]*@#\1:***@#g' \
    -e 's#(://)[^/:@ ]{20,}@#\1***@#g'
}
flat="$(printf '%s' "$2" | tr '\n\t' '  ' | mask_secrets)"
if [ "${#flat}" -gt 240 ]; then
  excerpt="${flat:0:120} ... ${flat: -120}"
else
  excerpt="$flat"
fi
pattern="$(printf '%s' "$3" | tr '\n\t' '  ' | mask_secrets)"
{ printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$folder" "$1" "$pattern" "$excerpt" >> "$L"; } 2>/dev/null || exit 1
exit 0
