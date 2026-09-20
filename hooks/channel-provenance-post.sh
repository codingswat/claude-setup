#!/bin/bash
# Session provenance, half 2 of 2. PostToolUse on Edit|Write|MultiEdit|Bash: compare with
# the pre snapshot; a channel file THIS session changed during the call opens or extends
# its provenance chain. Never blocks. Logic and config: hooks/provenance.py (inert with no
# hooks/channel-ceiling.conf naming any channel files). Tests: hooks/test-hooks.sh.
python3 "$(dirname "$0")/provenance.py" post
exit 0
