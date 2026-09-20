#!/bin/bash
# Session provenance, half 1 of 2. PreToolUse on Edit|Write|MultiEdit|Bash: snapshot each
# shared channel file's working-tree hash and HEAD hash for THIS session before the call.
# Read-only; never blocks. Logic and config: hooks/provenance.py (inert with no
# hooks/channel-ceiling.conf naming any channel files). Tests: hooks/test-hooks.sh.
python3 "$(dirname "$0")/provenance.py" pre
exit 0
