#!/bin/bash
# Session provenance, half 2 of 2. PostToolUse on Edit|Write|MultiEdit|Bash: compare with
# the pre snapshot; a channel file THIS session changed during the call opens or extends
# its provenance chain. Never blocks. Logic and config: hooks/provenance.py (inert with no
# hooks/channel-ceiling.conf naming any channel files). Tests: hooks/test-hooks.sh.
# The python3 that runs is the FIXED system one when it exists, else the first on PATH: a broken
# python3 earlier on PATH (a conda or pyenv shim that exits non-zero) must not silently stop
# the snapshot. Same rule as guard-lib.sh's guard_resolve_python. GUARD_PYTHON_PREFERRED is a
# TEST SEAM (leave it unset in real use). No python3 anywhere: do nothing, exit 0 — never blocks.
PY="${GUARD_PYTHON_PREFERRED:-/usr/bin/python3}"
[ -x "$PY" ] || PY="$(command -v python3 2>/dev/null)"
[ -n "$PY" ] && "$PY" "$(dirname "$0")/provenance.py" post
exit 0
