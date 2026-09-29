#!/bin/bash
# Session provenance, half 1 of 2. PreToolUse on Edit|Write|MultiEdit|Bash: snapshot each
# shared channel file's working-tree hash and HEAD hash for THIS session before the call.
# Read-only; never blocks. Logic and config: hooks/provenance.py (inert with no
# hooks/channel-ceiling.conf naming any channel files). Tests: hooks/test-hooks.sh.
# The python3 that runs is the FIXED system one when it exists, else the first on PATH: a broken
# python3 earlier on PATH (a conda or pyenv shim that exits non-zero) must not silently stop
# the snapshot. Same rule as guard-lib.sh's guard_resolve_python. GUARD_PYTHON_PREFERRED is a
# TEST SEAM (leave it unset in real use). No python3 anywhere: do nothing, exit 0 — never blocks.
PY="${GUARD_PYTHON_PREFERRED:-/usr/bin/python3}"
[ -x "$PY" ] || PY="$(command -v python3 2>/dev/null)"
[ -n "$PY" ] && "$PY" "$(dirname "$0")/provenance.py" pre
exit 0
