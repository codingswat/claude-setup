#!/bin/bash
# SessionStart hook — two jobs:
#   1. EVERY session, anywhere on disk: inject a short reminder that the
#      "## PROCESS RULES (enforced)" section of ~/.claude/CLAUDE.md (auto-loaded
#      by Claude Code) is ENFORCED — re-asserted live without duplicating its text
#      (the verbatim body was ~1,300 duplicated tokens per fire; changed 2026-08-18).
#   2. ONLY inside your configured project roots, when no CLAUDE.md exists in
#      the project (or any parent up to the root folder): additionally inject
#      the new-project interview, read from ~/.claude/hooks/interview.md.
#      Roots are listed in ~/.claude/hooks/project-roots.conf (written by
#      install.sh) — no paths are hardcoded in this script.
#      Outside those roots, never interview and never create files — the
#      session may be a one-time task or a non-coding folder.
# The rules section is READ AT RUNTIME from ~/.claude/CLAUDE.md and the
# interview from hooks/interview.md — edit them there and every future session
# picks it up; do not copy rule text into this script.
# If a section's heading is missing/renamed, degrade LOUDLY with a warning.
# Every branch also injects the rule-capture instruction.
# No jq — plain bash/sed/awk/tr only.

GLOBAL_MD="$HOME/.claude/CLAUDE.md"

input=$(cat 2>/dev/null)
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$cwd" ] && cwd="$PWD"

# Resolve symlinks on both sides so a symlinked path to (or from) a project
# root still matches. If a dir doesn't exist, fall back to the raw string.
phys=$(cd "$cwd" 2>/dev/null && pwd -P) && [ -n "$phys" ] && cwd="$phys"

# Project roots: one absolute path per line in project-roots.conf. Blank
# lines and "#" comments ignored; leading ~/ or $HOME/ expanded. No file (or
# an empty one) means no roots, so the interview simply never fires — the
# safe default for a fresh install.
ROOTS_CONF="$HOME/.claude/hooks/project-roots.conf"

root=""
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%%#*}
  line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -z "$line" ] && continue
  case "$line" in
    '~/'*)     line="$HOME/${line#\~/}" ;;
    '$HOME/'*) line="$HOME/${line#\$HOME/}" ;;
  esac
  rr=$(cd "$line" 2>/dev/null && pwd -P) || rr="$line"
  [ -z "$rr" ] && rr="$line"
  case "$cwd" in
    "$rr"/*) root="$rr"; break ;;
  esac
done < <(cat "$ROOTS_CONF" 2>/dev/null)

# Inside a project root: does the project (or any parent up to the root)
# already have a CLAUDE.md?
found=""
if [ -n "$root" ]; then
  dir="$cwd"
  while :; do
    if [ -f "$dir/CLAUDE.md" ]; then found="yes"; break; fi
    [ "$dir" = "$root" ] && break
    dir=$(dirname "$dir")
  done
fi

RULE_CAPTURE="Rule capture is itself a process rule: whenever the user corrects you, states a preference, or sets a new way of working during this session, immediately propose saving it — workflow rules to the PROCESS RULES section of the global CLAUDE.md, project-specific facts to this project's CLAUDE.md. Ask before writing. Do this at the moment it happens, not at the end."

# Extract one "## <heading>" section: from the heading line to the line
# before the next "## " heading. Fenced ``` code blocks are tracked so a
# "## comment" line inside one neither starts nor ends the section. "---"
# separators are skipped. The heading is matched as a literal line prefix
# (no regex), so parentheses etc. need no escaping.
extract_section() {
  awk -v h="## $1" '
    /^```/ { fence = !fence }
    flag && !fence && /^## / { exit }
    !fence && index($0, h) == 1 { flag = 1 }
    flag && !fence && /^---$/ { next }
    flag { print }
  ' "$GLOBAL_MD" 2>/dev/null
}

# Section not found (file missing, or heading edited/renamed): degrade
# LOUDLY so the user hears about it instead of rules silently vanishing.
missing_warning() {
  printf '%s' "WARNING: the section '## $1' was not found in ~/.claude/CLAUDE.md, so its instructions could NOT be injected this session. Tell the user about this at the start of your first reply so they can restore the section or fix its heading."
}

# 1. Process rules: every session, everywhere. The global CLAUDE.md is auto-loaded
#    by Claude Code, so the full rules text is ALREADY in context — re-injecting it
#    was measured at ~1,300 duplicated tokens per fire (2026-08-18 cleanup round).
#    Inject a short enforcement reminder instead. extract_section still runs as an
#    existence check, so a renamed or deleted heading degrades LOUDLY, not silently.
rules=$(extract_section "PROCESS RULES (enforced)")
if [ -n "$rules" ]; then
  msg="ENFORCED: the '## PROCESS RULES (enforced)' section of the global CLAUDE.md — already loaded in your context — contains hard rules for this session, not guidance. Re-read that section now, before your first action, and apply every rule without being asked, wherever it is relevant (e.g. git rules apply only in a git repository). Style/communication sections of the CLAUDE.md files are guidance only. Anything the user says in chat overrides everything. If that section is NOT in your context, say so in your first reply so the user can restore it."
else
  msg=$(missing_warning "PROCESS RULES (enforced)")
fi

# 2. New-project interview: only inside a project root with no CLAUDE.md.
if [ -n "$root" ] && [ -z "$found" ]; then
  # Interview text lives in its own file (moved out of CLAUDE.md 2026-08-18
  # so it stops loading into every session's context).
  interview=$(cat "$HOME/.claude/hooks/interview.md" 2>/dev/null)
  if [ -n "$interview" ]; then
    msg="$msg

This project directory has no CLAUDE.md yet. Follow these instructions before doing anything else this session:

$interview"
  else
    msg="$msg

WARNING: ~/.claude/hooks/interview.md is missing or empty, so the new-project interview could NOT be injected this session. Tell the user about this at the start of your first reply so they can restore the file."
  fi
fi

msg="$msg

$RULE_CAPTURE"

# Claude Code caps injected hook context at 10,000 characters and truncates
# silently past that. Warn before this stops fitting — but on the actual
# injected text (this same $msg), never on the "## PROCESS RULES (enforced)"
# section, which is NOT part of $msg (only a short enforcement reminder is;
# see the comment at "1. Process rules" above). The one piece of $msg that
# can genuinely grow is ~/.claude/hooks/interview.md, so that is what a
# warning here should point at.
if [ "${#msg}" -gt 9000 ]; then
  msg="WARNING: the context this hook is injecting is ${#msg} characters, close to Claude Code's 10,000-character cap on hook context — past that, it is silently cut off. The '## PROCESS RULES (enforced)' section is NOT part of this text (only a short reminder is); the part that grows with your edits is ~/.claude/hooks/interview.md. Tell the user at the start of your first reply to shorten that file.

$msg"
fi

# JSON-escape: drop CR + all other control bytes (keep newline; tab -> space),
# escape backslash and double quote, join lines with literal \n.
#
# LC_ALL=C makes the whole pipeline byte-wise. Without it, one invalid UTF-8
# byte anywhere in the user's CLAUDE.md or interview.md makes tr abort, which
# silently truncated the injected context — losing the rule-capture
# instruction with no warning, in the one script whose stated contract is to
# degrade loudly. iconv -c drops invalid bytes first where it is available.
# All UTF-8 lead and continuation bytes are >= 0x80, so the 0x00-0x1F ranges
# below are unaffected and real multibyte characters pass through untouched.
# NOTE: iconv -c strips the invalid bytes but still exits non-zero to report
# that it found some, so its status must be ignored — an `|| original` fallback
# here appends the dirty text back onto the clean text. Use the output when it
# is non-empty; fall back to the original only if nothing came out at all.
if command -v iconv >/dev/null 2>&1; then
  cleaned=$(printf '%s' "$msg" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
  [ -n "$cleaned" ] && msg="$cleaned"
fi
esc=$(printf '%s' "$msg" | LC_ALL=C tr '\t' ' ' | LC_ALL=C tr -d '\000-\010\013-\037' \
  | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
  | LC_ALL=C awk 'BEGIN{ORS=""} NR>1{printf "\\n"} {printf "%s", $0}')

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
