#!/bin/bash
# agent-model-guard.sh — PreToolUse hook on the Agent tool. A helper launched with no `model`
# field quietly inherits the parent session's model, which is usually the biggest and dearest
# one. This refuses such a launch, so every helper is given a model on purpose: the smallest
# that can do the job.
#
# Register (settings.json, PreToolUse):
#   { "matcher": "Agent", "hooks": [ { "type": "command",
#     "command": "/bin/bash \"$HOME/.claude/hooks/agent-model-guard.sh\"", "timeout": 10,
#     "statusMessage": "Agent launch names its model" } ] }
#
# Reads the PreToolUse JSON on stdin. Any tool other than "Agent" passes untouched (exit 0).
# For an Agent call, tool_input.model missing, empty or only whitespace refuses: exit 2, the
# reason on stderr (Claude Code shows PreToolUse stderr to the model and blocks the call on
# exit 2). Any non-empty string passes — the guard does not know model names, so a new model
# never needs an edit here. `subagent_type: "fork"` always passes: a fork inherits the parent
# model by design and the tool ignores a model given with it.
# No configuration. No jq and no python: sed only, so it cannot fail closed on a missing
# tool — a payload it cannot read carries no model, and the launch is refused.
# "model" is read straight off the raw JSON: no other top-level PreToolUse field carries that
# name, and text inside a prompt has its quotes escaped (\"), so it cannot forge the field.
# Tests: hooks/test-hooks.sh, "refresh 2026-09-29 (d1)", cases B1.
input=$(cat 2>/dev/null); [ -z "$input" ] && exit 0
field() { printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
[ "$(field tool_name)" = "Agent" ] || exit 0
[ "$(field subagent_type)" = "fork" ] && exit 0
model=$(field model)
# spaces, an escaped tab/newline (\t \n \r as JSON spells them) or a lone backslash are not a name
model="${model//\\t/}"; model="${model//\\n/}"; model="${model//\\r/}"
model="${model//[[:space:]]/}"; model="${model//\\/}"
if [ -z "$model" ]; then
  echo "agent-model-guard: REFUSED — name the model for this helper: the smallest that can do the job. Add \"model\" to the Agent call and launch again." >&2
  exit 2
fi
exit 0
