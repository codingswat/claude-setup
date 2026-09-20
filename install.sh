#!/bin/bash
# install.sh — set up this Claude Code configuration on your machine.
#
# What it touches (and nothing else):
#   ~/.claude/CLAUDE.md            your standing rulebook (only if you have none)
#   ~/.claude/hooks/               the hook scripts + their config files
#   ~/.claude/git-hooks/           commit-msg, pre-commit, pre-merge-commit, pre-push
#                                  (opt-in to run them machine-wide — see that step)
#   ~/.claude/project-template/    starter files for new projects
#   ~/.claude/skills/              the cherry-picked skills (never overwrites)
#   ~/.claude/settings.json        adds hook registrations, keeps everything else
#   ~/.claude/.redaction-names.local   created empty if missing, so the privacy check
#                                  (git-hooks/pre-commit) has a names list to read at all
#
# Anything it would overwrite is copied to ~/.claude/.setup-backup-<timestamp>/
# first. Nothing of yours is ever deleted (the installer removes only its own empty
# backup folder). Re-running it is safe.
#
# Usage:  ./install.sh          interactive (recommended)
#         ./install.sh --yes    accept safe defaults, ask nothing
#
set -u

SRC="$(cd "$(dirname "$0")" && pwd -P)"
DEST="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$DEST/.setup-backup-$STAMP"
ASSUME_YES=0
[ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ] && ASSUME_YES=1

# --- output helpers --------------------------------------------------------
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else B=''; G=''; Y=''; R=''; N=''; fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
skip() { printf '  %s·%s %s\n' "$Y" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%sStopped:%s %s\n' "$R" "$N" "$*"; exit 1; }
head2(){ printf '\n%s%s%s\n' "$B" "$*" "$N"; }

# ask "question" "default(y/n)" -> returns 0 for yes
ask() {
  local q="$1" def="$2" reply
  if [ "$ASSUME_YES" = "1" ]; then [ "$def" = "y" ]; return; fi
  if [ ! -t 0 ]; then [ "$def" = "y" ]; return; fi
  local hint="[y/N]"; [ "$def" = "y" ] && hint="[Y/n]"
  printf '  %s %s ' "$q" "$hint"
  read -r reply || reply=""
  reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
  [ -z "$reply" ] && reply="$def"
  [ "$reply" = "y" ] || [ "$reply" = "yes" ]
}

# askval "question" "default" -> echoes the answer
askval() {
  local q="$1" def="${2:-}" reply
  if [ "$ASSUME_YES" = "1" ] || [ ! -t 0 ]; then printf '%s' "$def"; return; fi
  if [ -n "$def" ]; then printf '  %s [%s] ' "$q" "$def" >&2
  else printf '  %s ' "$q" >&2; fi
  read -r reply || reply=""
  [ -z "$reply" ] && reply="$def"
  printf '%s' "$reply"
}

# Copy a file, backing up any existing different version first.
backup_then_copy() {
  local from="$1" to="$2" label="$3"
  if [ -f "$to" ]; then
    if cmp -s "$from" "$to"; then skip "$label — already current"; return; fi
    mkdir -p "$(dirname "$BACKUP/${to#"$DEST/"}")"
    cp -p "$to" "$BACKUP/${to#"$DEST/"}" || die "could not back up $to"
    cp "$from" "$to" || die "could not write $to"
    ok "$label — updated (old copy in ${BACKUP##*/}/)"
  else
    mkdir -p "$(dirname "$to")"
    cp "$from" "$to" || die "could not write $to"
    ok "$label — installed"
  fi
}

# --- preflight -------------------------------------------------------------
say ""
say "${B}Claude Code setup${N}"
say "Installing into $DEST"

[ -f "$SRC/hooks/check-claude-md.sh" ] || die "run this from inside the repo folder (hooks/ not found)."

JSONTOOL=""
command -v node    >/dev/null 2>&1 && JSONTOOL="node"
[ -z "$JSONTOOL" ] && command -v python3 >/dev/null 2>&1 && JSONTOOL="python3"

# have <binary> — "is it on PATH?", with one test seam: INSTALL_PRETEND_MISSING is a
# space-separated list of binaries to treat as absent, so hooks/test-hooks.sh can prove
# the "skip that guard" branch without rebuilding PATH. Empty in every real run.
have() {
  case " ${INSTALL_PRETEND_MISSING:-} " in *" $1 "*) return 1 ;; esac
  command -v "$1" >/dev/null 2>&1
}

mkdir -p "$DEST/hooks" "$DEST/skills" "$DEST/project-template" "$DEST/git-hooks" || die "cannot create $DEST"

# Copy a hook. $4 = "required" means this hook gets registered in settings.json below —
# a checkout missing it would silently register a hook that can never fire, so refuse
# instead of a warn-and-continue: this checkout is missing files a clean clone has,
# meaning the clone itself is probably incomplete. Anything else (not registered, e.g.
# test-hooks.sh) still just warns and continues.
copy_if_present() {
  local from="$1" to="$2" label="$3" required="${4:-}"
  if [ -f "$from" ]; then
    backup_then_copy "$from" "$to" "$label"
  elif [ "$required" = "required" ]; then
    die "$label is missing from this checkout — your clone may be incomplete; re-clone before continuing (${from#"$SRC/"})"
  else
    warn "$label — missing from this checkout — your clone may be incomplete; re-clone before continuing (${from#"$SRC/"})"
  fi
}

# --- 1. hooks --------------------------------------------------------------
head2 "1. Hook scripts"
backup_then_copy "$SRC/hooks/check-claude-md.sh" "$DEST/hooks/check-claude-md.sh" "check-claude-md.sh (SessionStart)"
backup_then_copy "$SRC/hooks/auto-backup.sh"     "$DEST/hooks/auto-backup.sh"     "auto-backup.sh (Stop)"
backup_then_copy "$SRC/hooks/interview.md"       "$DEST/hooks/interview.md"       "interview.md (new-project questions)"
copy_if_present  "$SRC/hooks/clock-in-context.sh"      "$DEST/hooks/clock-in-context.sh"      "clock-in-context.sh (SessionStart + UserPromptSubmit)" required
copy_if_present  "$SRC/hooks/guard-lib.sh"             "$DEST/hooks/guard-lib.sh"             "guard-lib.sh (shared command-reading helpers; the four Bash guards REFUSE without it)" required
copy_if_present  "$SRC/hooks/block-dangerous-git.sh"   "$DEST/hooks/block-dangerous-git.sh"   "block-dangerous-git.sh (PreToolUse: Bash)" required
copy_if_present  "$SRC/hooks/commit-pathspec-guard.sh" "$DEST/hooks/commit-pathspec-guard.sh" "commit-pathspec-guard.sh (PreToolUse: Bash)" required
copy_if_present  "$SRC/hooks/heavy-suite-guard.sh"     "$DEST/hooks/heavy-suite-guard.sh"     "heavy-suite-guard.sh (PreToolUse: Bash)" required
copy_if_present  "$SRC/hooks/override-ledger.sh"       "$DEST/hooks/override-ledger.sh"       "override-ledger.sh (used by the guards below)" required
copy_if_present  "$SRC/hooks/gate-guard.sh"            "$DEST/hooks/gate-guard.sh"            "gate-guard.sh (PreToolUse: Bash)" required
copy_if_present  "$SRC/hooks/channel-size-guard.sh"    "$DEST/hooks/channel-size-guard.sh"    "channel-size-guard.sh (PreToolUse: Write|Edit|MultiEdit|Bash)" required
copy_if_present  "$SRC/hooks/channel-size-post.sh"     "$DEST/hooks/channel-size-post.sh"     "channel-size-post.sh (PostToolUse: Write|Edit|MultiEdit|Bash)" required
copy_if_present  "$SRC/hooks/helper-ledger.py"         "$DEST/hooks/helper-ledger.py"         "helper-ledger.py (Stop)" required
# The multi-chat coordination group (opt-in, step 6 below) — copied unconditionally so the
# question can be asked, but only registered in settings.json on a yes.
copy_if_present  "$SRC/hooks/channel-provenance-pre.sh"  "$DEST/hooks/channel-provenance-pre.sh"  "channel-provenance-pre.sh (PreToolUse, opt-in)"
copy_if_present  "$SRC/hooks/channel-provenance-post.sh" "$DEST/hooks/channel-provenance-post.sh" "channel-provenance-post.sh (PostToolUse, opt-in)"
copy_if_present  "$SRC/hooks/provenance.py"              "$DEST/hooks/provenance.py"              "provenance.py (used by the provenance hooks, opt-in)"
copy_if_present  "$SRC/hooks/doorman.sh"                 "$DEST/hooks/doorman.sh"                 "doorman.sh (UserPromptSubmit, opt-in)"
copy_if_present  "$SRC/hooks/stop-state-check.sh"        "$DEST/hooks/stop-state-check.sh"        "stop-state-check.sh (Stop, opt-in)"
copy_if_present  "$SRC/hooks/test-hooks.sh"            "$DEST/hooks/test-hooks.sh"            "test-hooks.sh (run it yourself to check the hooks)"
# The next two are not hooks — test-hooks.sh runs them as subprocesses and folds their
# counts into its own RESULT line, so they need to sit alongside it to make that promise true.
copy_if_present  "$SRC/hooks/test-helper-ledger.sh"    "$DEST/hooks/test-helper-ledger.sh"    "test-helper-ledger.sh (run by test-hooks.sh)"
copy_if_present  "$SRC/hooks/test-rules-cap.sh"        "$DEST/hooks/test-rules-cap.sh"        "test-rules-cap.sh (run by test-hooks.sh)"
chmod +x "$DEST/hooks/check-claude-md.sh" "$DEST/hooks/auto-backup.sh" "$DEST/hooks/clock-in-context.sh" \
         "$DEST/hooks/guard-lib.sh" \
         "$DEST/hooks/block-dangerous-git.sh" "$DEST/hooks/commit-pathspec-guard.sh" \
         "$DEST/hooks/heavy-suite-guard.sh" "$DEST/hooks/override-ledger.sh" "$DEST/hooks/gate-guard.sh" \
         "$DEST/hooks/channel-size-guard.sh" "$DEST/hooks/channel-size-post.sh" "$DEST/hooks/helper-ledger.py" \
         "$DEST/hooks/channel-provenance-pre.sh" "$DEST/hooks/channel-provenance-post.sh" \
         "$DEST/hooks/provenance.py" "$DEST/hooks/doorman.sh" "$DEST/hooks/stop-state-check.sh" \
         "$DEST/hooks/test-hooks.sh" "$DEST/hooks/test-helper-ledger.sh" "$DEST/hooks/test-rules-cap.sh" 2>/dev/null

# .conf.example files for the new guards — copied as EXAMPLES only, never as a live conf:
# each guard stays inert until you copy one to its live name yourself and fill it in (the
# one exception, heavy-suite.conf above, predates this stage). See INSTALL.md.
for ex in gate-guard.conf.example channel-ceiling.conf.example allowed-email-domains.conf.example \
          block-dangerous-git.conf.example state-check.conf.example; do
  copy_if_present "$SRC/hooks/$ex" "$DEST/hooks/$ex" "$ex (example — copy it to enable)"
done

# The redaction names list — git-hooks/pre-commit's privacy check fails CLOSED (refuses
# every commit) with none at all, so a fresh machine needs at least an empty one to unblock
# ordinary commits. Never overwritten once it exists — it's the one file with names in it.
if [ -f "$DEST/.redaction-names.local" ]; then
  skip ".redaction-names.local — already present, left untouched"
else
  {
    printf '# ~/.claude/.redaction-names.local — names git-hooks/pre-commit refuses to see in\n'
    printf '# an ADDED line of a staged commit (an absolute home path is caught separately,\n'
    printf '# always). One name per line; blank lines and lines starting with # are ignored —\n'
    printf '# so every line below is a comment and this file has NO names configured yet. An\n'
    printf '# empty (or comment-only) file like this one is enough to proceed.\n'
    printf '#\n'
    printf '# Two sections, for your own reading:\n'
    printf '#   [guard]        real names/handles that must never reach a public commit —\n'
    printf '#                  finding one here REFUSES the commit.\n'
    printf '#   [redact-only]  names you want a heads-up on but would rather flag than hard\n'
    printf '#                  stop. As shipped, pre-commit enforces every entry the same way\n'
    printf '#                  (a match refuses the commit either way) — kept as two headings\n'
    printf '#                  so you can tell them apart if you later split the enforcement.\n'
    printf '#\n'
    printf '# Fill in your own real name, handle, or employer below the matching heading —\n'
    printf '# on its own line, with no leading #. Example (delete the # before using it):\n'
    printf '#   Jane Example\n'
    printf '\n# --- [guard] — add names below this line ---\n'
    printf '\n# --- [redact-only] — add names below this line ---\n'
  } > "$DEST/.redaction-names.local" \
    && ok ".redaction-names.local — installed empty, with the two sections explained (fill it in — see \"Next\" below)" \
    || warn "could not write $DEST/.redaction-names.local"
fi

# owner-card.md is a template you personalise — copied only if you don't have one.
if [ -f "$DEST/hooks/owner-card.md" ]; then
  skip "owner-card.md — already present, left untouched (it's yours to edit)"
elif [ -f "$SRC/hooks/owner-card.md" ]; then
  cp "$SRC/hooks/owner-card.md" "$DEST/hooks/owner-card.md" \
    && ok "owner-card.md — installed (personalise it any time)" \
    || warn "could not write owner-card.md"
else
  warn "owner-card.md — not found in this checkout yet, skipped"
fi

# heavy-suite.conf is a settings file you tune — same treatment: only if missing.
if [ -f "$DEST/hooks/heavy-suite.conf" ]; then
  skip "heavy-suite.conf — already present, left untouched"
elif [ -f "$SRC/hooks/heavy-suite.conf.example" ]; then
  cp "$SRC/hooks/heavy-suite.conf.example" "$DEST/hooks/heavy-suite.conf" \
    && ok "heavy-suite.conf — installed from the example (edit it to tune the guard)" \
    || warn "could not write heavy-suite.conf"
else
  warn "heavy-suite.conf.example — not found in this checkout yet, skipped"
fi

# The four git hooks (commit-msg, pre-commit, pre-merge-commit, pre-push) — copied in
# always, but they only run in every repo once you opt in at the "git hooks" step below.
# pre-merge-commit is pre-commit's privacy check on a MERGE commit, which no pre-commit
# hook ever sees; it calls pre-commit back, so the two belong together.
copy_if_present "$SRC/git-hooks/commit-msg"       "$DEST/git-hooks/commit-msg"       "commit-msg (git hook)"
copy_if_present "$SRC/git-hooks/pre-commit"       "$DEST/git-hooks/pre-commit"       "pre-commit (git hook)"
copy_if_present "$SRC/git-hooks/pre-merge-commit" "$DEST/git-hooks/pre-merge-commit" "pre-merge-commit (git hook)"
copy_if_present "$SRC/git-hooks/pre-push"         "$DEST/git-hooks/pre-push"         "pre-push (git hook)"
chmod +x "$DEST/git-hooks/commit-msg" "$DEST/git-hooks/pre-commit" \
         "$DEST/git-hooks/pre-merge-commit" "$DEST/git-hooks/pre-push" 2>/dev/null

# --- 2. rulebook -----------------------------------------------------------
head2 "2. Your standing rulebook (~/.claude/CLAUDE.md)"
if [ -f "$DEST/CLAUDE.md" ]; then
  # Never clobber this either — a user merging rules across may have edited it.
  [ -f "$DEST/CLAUDE-template-from-setup.md" ] \
    || cp "$SRC/TEMPLATE-CLAUDE.md" "$DEST/CLAUDE-template-from-setup.md" 2>/dev/null
  skip "You already have one — left untouched."
  say  "     The blank template is at ~/.claude/CLAUDE-template-from-setup.md if you"
  say  "     want to merge pieces in. Your rules stay yours."
else
  cp "$SRC/TEMPLATE-CLAUDE.md" "$DEST/CLAUDE.md" || die "could not write $DEST/CLAUDE.md"
  ok "Installed the starter rulebook — open it and fill in the marked sections."
  warn "It is a form, but it is NOT empty: 17 starter rules are active from your"
  say  "     next session. Rules 1 and 2 let Claude commit, push, merge to main"
  say  "     and delete leftover branches on its own, in every project, without"
  say  "     asking again. That is deliberate — it is what stops work getting"
  say  "     lost — but read them now and edit them if you would rather approve"
  say  "     each push yourself."
fi

# --- 3. project template + skills -----------------------------------------
head2 "3. Project starter files and skills"
tcount=0
while IFS= read -r f; do
  rel="${f#"$SRC/project-template/"}"
  target="$DEST/project-template/$rel"
  mkdir -p "$(dirname "$target")"
  [ -f "$target" ] || { cp "$f" "$target" && tcount=$((tcount+1)); }
done < <(find "$SRC/project-template" -type f 2>/dev/null)
[ "$tcount" -gt 0 ] && ok "project-template/ — $tcount file(s) added" || skip "project-template/ — already present"

# The per-project rulebook form: not part of project-template/ (it's a form you fill in,
# not a starter file dropped as-is), so it gets its own copy — backed up like the hooks,
# never silently skipped the way the starter files above are.
backup_then_copy "$SRC/TEMPLATE-project-CLAUDE.md" "$DEST/project-template/CLAUDE-template.md" "CLAUDE-template.md (per-project rulebook form)"

scount=0; sskip=0
while IFS= read -r d; do
  name="$(basename "$d")"
  if [ -e "$DEST/skills/$name" ]; then sskip=$((sskip+1)); continue; fi
  cp -R "$d" "$DEST/skills/$name" && scount=$((scount+1))
done < <(find "$SRC/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
# The skills are third-party MIT files; their notices travel with them.
for lic in ATTRIBUTION.md LICENSE-mattpocock LICENSE-ponytail; do
  [ -f "$SRC/skills/$lic" ] && [ ! -f "$DEST/skills/$lic" ] \
    && cp "$SRC/skills/$lic" "$DEST/skills/$lic"
done
[ "$scount" -gt 0 ] && ok "skills/ — $scount installed (with their licences)"
[ "$sskip" -gt 0 ] && skip "skills/ — $sskip already existed, left alone"

# --- 4. project roots ------------------------------------------------------
head2 "4. Where do you keep your projects?"
say "  When a session starts in a folder under one of these paths and that project"
say "  has no CLAUDE.md, Claude interviews you and writes one. Outside them it does"
say "  nothing. Type - to switch this off."
ROOTS_CONF="$DEST/hooks/project-roots.conf"
if [ -f "$ROOTS_CONF" ]; then
  skip "Already configured — keeping $(grep -cvE '^[[:space:]]*(#|$)' "$ROOTS_CONF" 2>/dev/null || true) path(s)."
else
  roots="$(askval "Projects folder (- to switch off):" "$HOME/projects")"
  [ "$roots" = "-" ] && roots=""
  {
    printf '# One project-root folder per line. Blank lines and # comments ignored.\n'
    printf '# The new-project interview only fires inside these folders.\n'
    [ -n "$roots" ] && printf '%s\n' "$roots"
  } > "$ROOTS_CONF"
  if [ -n "$roots" ]; then
    ok "Interview enabled for: $roots"
    [ -d "$roots" ] || warn "that folder doesn't exist yet — fine, it'll work once it does"
  else
    ok "Interview switched off (edit $ROOTS_CONF to enable later)"
  fi
fi

# --- 5. register the SessionStart hook -------------------------------------
head2 "5. Turning the hooks on (~/.claude/settings.json)"
# Back up an EXISTING settings.json before touching it. A file we are about
# to create ourselves is not a replacement and must not be reported as one.
SETTINGS_PREEXISTED=0
if [ -f "$DEST/settings.json" ]; then
  SETTINGS_PREEXISTED=1
  if [ ! -f "$BACKUP/settings.json" ]; then
    mkdir -p "$BACKUP" || die "could not create the backup folder"
    # No 2>/dev/null here: if we cannot back it up we must not edit it.
    cp -p "$DEST/settings.json" "$BACKUP/settings.json" \
      || die "could not back up settings.json — refusing to modify it"
  fi
else
  printf '{}\n' > "$DEST/settings.json"
fi

register_hook() {   # event  command  timeout  statusMessage  [matcher]
  local ev="$1" cmd="$2" to="$3" sm="$4" mt="${5:-}" out=""
  case "$JSONTOOL" in
    node)
      out=$(node -e '
        const fs=require("fs");
        let [p,ev,cmd,to,sm,mt]=process.argv.slice(1);
        // Resolve first: a dotfiles setup symlinks settings.json into its own
        // repo, and renaming onto the LINK would replace it with a regular
        // file, silently detaching the real source of truth.
        try { p = fs.realpathSync(p); } catch(e) { /* file may not exist yet */ }
        let s={}; const raw=fs.readFileSync(p,"utf8").trim();
        try{ s=raw?JSON.parse(raw):{}; }catch(e){ console.log("PARSE_FAIL"); process.exit(0); }
        if(s.hooks===undefined) s.hooks={};
        if(s.hooks===null || typeof s.hooks!=="object" || Array.isArray(s.hooks)){
          console.log("SHAPE_FAIL"); process.exit(0); }
        if(s.hooks[ev]===undefined) s.hooks[ev]=[];
        if(!Array.isArray(s.hooks[ev])){ console.log("SHAPE_FAIL"); process.exit(0); }
        const dup = s.hooks[ev].some(g =>
          (g && Array.isArray(g.hooks) ? g.hooks : []).some(h => h && h.command === cmd));
        if(dup){ console.log("ALREADY"); process.exit(0); }
        const h={type:"command",command:cmd};
        if(to) h.timeout=Number(to);
        if(sm) h.statusMessage=sm;
        const grp={hooks:[h]};
        if(mt) grp.matcher=mt;
        s.hooks[ev].push(grp);
        // Write to a temp file in the same directory and rename over the
        // target, so a failed or partial write can never truncate the
        // original settings.json.
        const tmp=p+".setup-tmp";
        fs.writeFileSync(tmp, JSON.stringify(s,null,2)+"\n");
        fs.renameSync(tmp, p);
        console.log("ADDED");
      ' "$DEST/settings.json" "$ev" "$cmd" "$to" "$sm" "$mt" 2>/dev/null) ;;
    python3)
      out=$(python3 - "$DEST/settings.json" "$ev" "$cmd" "$to" "$sm" "$mt" <<'PYEOF' 2>/dev/null
import json,os,sys
p,ev,cmd,to,sm,mt = sys.argv[1:7]
# Resolve first — see the note in the node branch above.
p = os.path.realpath(p)
try:
    raw=open(p).read().strip()
    s=json.loads(raw) if raw else {}
except Exception:
    print("PARSE_FAIL"); sys.exit(0)
if "hooks" not in s: s["hooks"] = {}
if not isinstance(s.get("hooks"), dict):
    print("SHAPE_FAIL"); sys.exit(0)
if ev not in s["hooks"]: s["hooks"][ev] = []
if not isinstance(s["hooks"][ev], list):
    print("SHAPE_FAIL"); sys.exit(0)
dup = any(h.get("command") == cmd
          for g in s["hooks"][ev] if isinstance(g, dict)
          for h in g.get("hooks", []) if isinstance(h, dict))
if dup:
    print("ALREADY"); sys.exit(0)
h={"type":"command","command":cmd}
if to: h["timeout"]=int(to)
if sm: h["statusMessage"]=sm
grp={"hooks":[h]}
if mt: grp["matcher"]=mt
s["hooks"][ev].append(grp)
# Atomic: write beside the target, then rename over it.
tmp = p + ".setup-tmp"
with open(tmp,"w") as fh: fh.write(json.dumps(s,indent=2)+"\n")
os.replace(tmp, p)
print("ADDED")
PYEOF
) ;;
    *) out="NOTOOL" ;;
  esac
  printf '%s' "$out"
}

ANY_ADDED=0
report_hook_result() {   # $1 = result  $2 = human name of the hook
  case "$1" in
    ADDED)      ok "$2 registered"; ANY_ADDED=1 ;;
    ALREADY)    skip "$2 was already registered" ;;
    PARSE_FAIL) warn "settings.json isn't valid JSON — not touching it. Add $2 by hand (see INSTALL.md)." ;;
    SHAPE_FAIL) warn "settings.json is valid JSON but its \"hooks\" block has an unexpected shape — not touching it. Add $2 by hand (see INSTALL.md)." ;;
    NOTOOL)     warn "no node or python3 found — add $2 by hand (see INSTALL.md)." ;;
    *)          warn "could not register $2 — add it by hand (see INSTALL.md)." ;;
  esac
}

SESSION_CMD='/bin/bash "$HOME/.claude/hooks/check-claude-md.sh"'
res=$(register_hook "SessionStart" "$SESSION_CMD" "" "Checking for project CLAUDE.md...")
report_hook_result "$res" "the SessionStart hook (check-claude-md.sh)"
[ "$res" = "ADDED" ] && say "     Your rules now get re-asserted at the start of every session."

CLOCK_CMD='/bin/bash "$HOME/.claude/hooks/clock-in-context.sh"'
res=$(register_hook "SessionStart" "$CLOCK_CMD" "" "Loading the owner card...")
report_hook_result "$res" "the SessionStart hook (clock-in-context.sh)"

res=$(register_hook "UserPromptSubmit" "$CLOCK_CMD" "" "")
report_hook_result "$res" "the UserPromptSubmit hook (clock-in-context.sh)"

# The three PreToolUse guards below use jq to read the tool-call JSON AND python3 to
# normalise the command, and each one fails CLOSED (refuses everything) when either is
# missing — a silent no-op would be worse. So they are registered only when BOTH are on
# PATH: registering them with one of the two missing would install guards that refuse
# every Bash command on this machine.
if have jq && have python3; then
  BLOCK_GIT_CMD='/bin/bash "$HOME/.claude/hooks/block-dangerous-git.sh"'
  res=$(register_hook "PreToolUse" "$BLOCK_GIT_CMD" "" "" "Bash")
  report_hook_result "$res" "the PreToolUse hook (block-dangerous-git.sh)"

  PATHSPEC_CMD='/bin/bash "$HOME/.claude/hooks/commit-pathspec-guard.sh"'
  res=$(register_hook "PreToolUse" "$PATHSPEC_CMD" "" "" "Bash")
  report_hook_result "$res" "the PreToolUse hook (commit-pathspec-guard.sh)"

  HEAVY_CMD='/bin/bash "$HOME/.claude/hooks/heavy-suite-guard.sh"'
  res=$(register_hook "PreToolUse" "$HEAVY_CMD" "" "" "Bash")
  report_hook_result "$res" "the PreToolUse hook (heavy-suite-guard.sh)"
else
  warn "jq and python3 are BOTH needed by block-dangerous-git.sh, commit-pathspec-guard.sh"
  say  "     and heavy-suite-guard.sh, and one of them is missing — skipping all three."
  say  "     They fail closed without either, so registering them now would refuse every"
  say  "     Bash command. Install the missing one, then run this again."
fi

# The size pair needs jq only, and does nothing at all to a call it cannot read — so it
# gets its own check rather than riding on the group above. The PostToolUse half is what
# catches growth the PreToolUse half cannot see in the command text (a filename in a
# variable, an Edit whose one new "word" is 100,000 characters long): it re-measures the
# file on disk afterwards and says so loudly. They are registered together, always.
if have jq; then
  SIZE_CMD='/bin/bash "$HOME/.claude/hooks/channel-size-guard.sh"'
  res=$(register_hook "PreToolUse" "$SIZE_CMD" "" "" "Write|Edit|MultiEdit|Bash")
  report_hook_result "$res" "the PreToolUse hook (channel-size-guard.sh)"

  SIZE_POST_CMD='/bin/bash "$HOME/.claude/hooks/channel-size-post.sh"'
  res=$(register_hook "PostToolUse" "$SIZE_POST_CMD" "" "" "Write|Edit|MultiEdit|Bash")
  report_hook_result "$res" "the PostToolUse hook (channel-size-post.sh)"
else
  warn "jq not found — skipping the size pair (channel-size-guard.sh and"
  say  "     channel-size-post.sh). Both read the tool call with jq and are inert without"
  say  "     it. Install jq, then run this again."
fi

# gate-guard.sh is different: unlike the four above, it degrades safely with NO jq (it
# falls back to a cruder text match instead of refusing everything), and with no python3 it
# now passes every command with a one-line warning instead of refusing them — it is the one
# guard that may fail OPEN, because it protects no data and only enforces a habit about
# exit codes. Registering it without python3 would therefore be harmless but useless: a
# subprocess per Bash call that can never say no. So it is still gated on python3, now for
# cost rather than for safety.
if command -v python3 >/dev/null 2>&1; then
  GATE_CMD='/bin/bash "$HOME/.claude/hooks/gate-guard.sh"'
  res=$(register_hook "PreToolUse" "$GATE_CMD" "" "" "Bash")
  report_hook_result "$res" "the PreToolUse hook (gate-guard.sh)"
else
  warn "python3 not found — skipping the PreToolUse hook (gate-guard.sh). It needs"
  say  "     python3 for its real check; without it it would pass every command with a"
  say  "     warning, so registering it now would only cost a subprocess per Bash call."
  say  "     Install python3, then run this again."
fi

# The helper ledger only reads transcripts and appends TSV rows — never blocks the
# session, and needs python3 (not jq) on PATH.
if command -v python3 >/dev/null 2>&1; then
  LEDGER_CMD='/usr/bin/env python3 "$HOME/.claude/hooks/helper-ledger.py"'
  res=$(register_hook "Stop" "$LEDGER_CMD" "" "")
  report_hook_result "$res" "the Stop hook (helper-ledger.py)"
else
  warn "python3 not found — skipping the Stop hook (helper-ledger.py). Install python3,"
  say  "     then run this again, or add it by hand (see INSTALL.md)."
fi

# --- 6. multi-chat coordination hooks (opt-in) ------------------------------
head2 "6. Multi-chat coordination hooks (optional, OFF by default)"
say "  Only useful once more than one Claude Code session works in the same repo at a"
say "  time. Four hooks, one question:"
say "    - channel-provenance-pre.sh / -post.sh: record, per session, which lines of a"
say "      shared file (NOTES, a plan, a changelog) THIS session wrote, so a later commit"
say "      can't accidentally sweep in another session's uncommitted change. Needs python3"
say "      — inert without it."
say "    - doorman.sh: bounces a new prompt to a session already marked retired, or gone"
say "      idle for a while at a high context, saving the message for the next session"
say "      instead of losing it."
say "    - stop-state-check.sh: marks a session retired past a configured context floor,"
say "      and won't let a turn end having changed tracked files unless that role's own"
say "      state file is among them."
say "  All four read one shared config, hooks/state-check.conf (see"
say "  hooks/state-check.conf.example) — none of it exists yet, so all four stay inert"
say "  until you write it by hand. Nothing here talks to the network."
if ask "Register the multi-chat coordination hooks?" "n"; then
  DOORMAN_CMD='/bin/bash "$HOME/.claude/hooks/doorman.sh"'
  res=$(register_hook "UserPromptSubmit" "$DOORMAN_CMD" "" "" )
  report_hook_result "$res" "the UserPromptSubmit hook (doorman.sh)"

  STATECHK_CMD='/bin/bash "$HOME/.claude/hooks/stop-state-check.sh"'
  res=$(register_hook "Stop" "$STATECHK_CMD" "" "")
  report_hook_result "$res" "the Stop hook (stop-state-check.sh)"

  if command -v python3 >/dev/null 2>&1; then
    PROV_PRE_CMD='/bin/bash "$HOME/.claude/hooks/channel-provenance-pre.sh"'
    res=$(register_hook "PreToolUse" "$PROV_PRE_CMD" "" "" "Write|Edit|MultiEdit|Bash")
    report_hook_result "$res" "the PreToolUse hook (channel-provenance-pre.sh)"

    PROV_POST_CMD='/bin/bash "$HOME/.claude/hooks/channel-provenance-post.sh"'
    res=$(register_hook "PostToolUse" "$PROV_POST_CMD" "" "" "Write|Edit|MultiEdit|Bash")
    report_hook_result "$res" "the PostToolUse hook (channel-provenance-post.sh)"
  else
    warn "python3 not found — skipping channel-provenance-pre.sh / -post.sh (they need it;"
    say  "     doorman.sh and stop-state-check.sh above don't, so those two are still on)."
  fi
  say  "  Next: write hooks/state-check.conf (copy state-check.conf.example) to turn any"
  say  "  of the four on for a real project — every one is inert with no conf."
else
  skip "Skipped — all four stay inert (no hooks/state-check.conf, nothing registered)."
fi

# #9: a backup copy only earns its place if we actually changed the file.
[ "$ANY_ADDED" = "1" ] || [ "$SETTINGS_PREEXISTED" = "0" ] || rm -f "$BACKUP/settings.json" 2>/dev/null

# --- 7. the backup hook (opt-in) -------------------------------------------
# The whole design rests on ~/.claude/.gitignore being a strict ALLOWLIST. A
# printed "please check this yourself" is not a safeguard, so we prove it with
# git instead: check-ignore applies exactly the rules `git add -A` will apply.
# Every sensitive path must be ignored. If any is not, the hook is NOT armed.
UNIGNORED=""
allowlist_proves_safe() {
  local t rc=0 pth
  UNIGNORED=""
  [ -f "$DEST/.gitignore" ] || return 1
  t="$(mktemp -d 2>/dev/null)" || return 1
  cp "$DEST/.gitignore" "$t/.gitignore" 2>/dev/null || { rm -rf "$t"; return 1; }
  git -C "$t" init -q >/dev/null 2>&1 || { rm -rf "$t"; return 1; }
  # The canary matters more than the named paths: only a file that ignores
  # EVERYTHING by default can ignore a name it has never seen. A denylist that
  # happens to name the paths below would otherwise pass this check while
  # leaving .claude.json, settings.local.json, mcp.json and friends exposed.
  for pth in zz-canary-never-seen-before.tmp \
             .credentials.json history.jsonl .env .claude.json \
             settings.local.json mcp.json statsig/x plugins/x \
             projects/a-project/session.jsonl \
             shell-snapshots/snapshot.sh sessions/s.json todos/t.json downloads/x; do
    git -C "$t" check-ignore -q "$pth" 2>/dev/null || { rc=1; UNIGNORED="$UNIGNORED
       - $pth"; }
  done
  rm -rf "$t"
  return $rc
}

# The allowlist proof above runs in a throwaway repo, so by construction it
# cannot see the user's real index — and a .gitignore has NO effect on a path
# git is already tracking. Someone who ran `git init` in ~/.claude before
# installing may already be tracking .credentials.json and their transcripts;
# adding the allowlist does not untrack them, and every future commit keeps
# pushing them. Ask git which tracked paths the ignore rules WOULD have
# excluded: that set is the live leak.
TRACKED_LEAKS=""
tracked_leaks_found() {
  TRACKED_LEAKS=""
  git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1 || return 1   # not a repo: nothing tracked
  TRACKED_LEAKS=$(git -C "$DEST" ls-files -z 2>/dev/null \
    | git -C "$DEST" check-ignore --no-index --stdin -z 2>/dev/null \
    | tr '\000' '\n' | sed '/^$/d')
  [ -n "$TRACKED_LEAKS" ]
}

head2 "7. Auto-backup of your config (optional, OFF by default)"
say "  This commits and PUSHES every change under ~/.claude to a git repo at the"
say "  end of every turn, without showing you a diff. Useful, but it means your"
say "  standing instructions live in a repo that must stay PRIVATE."
say "  Skip it now and turn it on later any time — nothing else depends on it."
if [ -f "$DEST/hooks/backup.conf" ]; then
  skip "Already configured (edit ~/.claude/hooks/backup.conf to change)."
elif ask "Set up the auto-backup hook?" "n"; then
  if [ -f "$DEST/.gitignore" ]; then
    skip "~/.claude/.gitignore already exists — not replacing it."
  else
    cp "$SRC/hooks/dot-claude.gitignore" "$DEST/.gitignore" \
      && ok "Installed the allowlist ~/.claude/.gitignore"
  fi

  if ! allowlist_proves_safe; then
    warn "NOT enabling the backup hook — your ~/.claude/.gitignore does not"
    say  "     ignore these, so they would be committed and pushed:$UNIGNORED"
    say  ""
    say  "     That file needs to be an allowlist (ignore everything, then"
    say  "     re-include named files). Merge hooks/dot-claude.gitignore from"
    say  "     this repo into it and run this installer again."
    say  "     Nothing has been changed — the hook stays off."
  elif tracked_leaks_found; then
    warn "NOT enabling the backup hook — ~/.claude is ALREADY a git repository"
    say  "     and these files are already being tracked in it:"
    printf '%s\n' "$TRACKED_LEAKS" | sed 's/^/       - /'
    say  ""
    say  "     A .gitignore does not apply to files git already tracks, so the"
    say  "     allowlist cannot protect these. Untrack them first:"
    say  ""
    printf '       cd ~/.claude && git rm --cached -r %s\n' "$(printf '%s' "$TRACKED_LEAKS" | head -3 | tr '\n' ' ')"
    say  ""
    say  "     Then commit that removal and run this installer again."
    say  ""
    warn "If this repo has ALREADY been pushed anywhere, treat every credential"
    say  "     in those files as exposed and rotate it. Removing a file from the"
    say  "     latest commit does not remove it from the history."
  else
    ok "Verified with git: it ignores everything by default, including a name"
    say  "     it has never seen — so new files are safe too, not just known ones."
    gname="$(askval "git name for the backup commits:" "$(git config --global user.name 2>/dev/null)")"
    gmail="$(askval "git email for the backup commits:" "$(git config --global user.email 2>/dev/null)")"
    # With no global git identity set, both defaults are empty and Enter twice
    # produces "AUTHOR= <>". That is non-empty, so it passes the hook's guard,
    # and then every single commit fails with "empty ident name" while the
    # installer has already reported success.
    if [ -z "$gname" ] || [ -z "$gmail" ]; then
      warn "NOT enabling the backup hook — a name and an email are both required,"
      say  "     and git has no global identity set on this machine to fall back on."
      say  "     Set one, then run this installer again:"
      say  ""
      say  "       git config --global user.name  \"your-handle\""
      say  "       git config --global user.email \"you@example.com\""
      gname=""; gmail=""
    fi
    if [ -n "$gname" ] && [ -n "$gmail" ]; then
      say  "  A mirror folder gets readable copies of your rules AND a copy of"
      say  "  settings.json — which can hold live API keys in its env block. Whatever"
      say  "  repo it lives in must be a PRIVATE repository. Blank to skip it."
      mirror="$(askval "optional folder for readable copies (blank = skip):" "")"
      if [ -n "$mirror" ]; then
        remote_url=""
        if git -C "$mirror" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          remote_url="$(git -C "$mirror" remote get-url origin 2>/dev/null)"
        fi
        case "$remote_url" in
          *github.com*)
            confirm="$(askval "That folder's repo remote is on github.com. Type 'private' to confirm this specific repository is PRIVATE and continue (anything else skips the mirror):" "")"
            if [ "$confirm" != "private" ]; then
              warn "Mirror folder NOT set — its repo's remote is on github.com and wasn't confirmed private."
              mirror=""
            fi
            ;;
        esac
      fi
      # Strip control bytes: these values land in a config file the hook reads.
      strip_ctl() { printf '%s' "$1" | tr -d '\000-\037'; }
      {
        printf '# Written by install.sh — settings for the auto-backup Stop hook.\n'
        printf '# Plain KEY=value. NOT a shell script: auto-backup.sh parses this\n'
        printf '# file line by line and never sources it, so nothing here executes.\n'
        printf 'AUTHOR=%s <%s>\n' "$(strip_ctl "$gname")" "$(strip_ctl "$gmail")"
        printf 'MIRROR_DIR=%s\n' "$(strip_ctl "$mirror")"
      } > "$DEST/hooks/backup.conf"
      ok "Wrote ~/.claude/hooks/backup.conf"
      res=$(register_hook "Stop" '/bin/bash "$HOME/.claude/hooks/auto-backup.sh"' "30" "Backing up config changes...")
      report_hook_result "$res" "the Stop hook"

      # Must be the ROOT of a repo, not merely inside one. If $HOME is a git
      # repo (the dotfiles pattern), --is-inside-work-tree says "true" for
      # ~/.claude and `git add -A` would stage the whole home directory —
      # somewhere the ~/.claude/.gitignore allowlist cannot reach.
      dest_top=$(git -C "$DEST" rev-parse --show-toplevel 2>/dev/null)
      if [ -n "$dest_top" ] && [ "$(cd "$dest_top" && pwd -P)" != "$(cd "$DEST" && pwd -P)" ]; then
        warn "~/.claude is inside a LARGER git repo ($dest_top), not its own."
        say  "     The backup hook will refuse to run there, on purpose: committing"
        say  "     from inside ~/.claude would stage that whole repository, and the"
        say  "     allowlist cannot protect files outside ~/.claude (~/.ssh, ~/.aws)."
        say  "     Make ~/.claude its own repo to use the backup hook."
      elif [ -z "$dest_top" ]; then
        warn "~/.claude is not a git repo yet. The hook stays quiet until it is."
        say  "     When ready, and looking before you leap:"
        say  "       cd ~/.claude && git init && git add -A && git status"
        say  "     Read that list. Only if it holds nothing you would not publish:"
        say  "       git commit -m init"
        say  "     then add a PRIVATE remote and push once by hand."
      fi
    fi
  fi
else
  skip "Skipped. The Stop hook stays inert until ~/.claude/hooks/backup.conf exists."
fi

# --- 8. git hooks, machine-wide (opt-in) ------------------------------------
head2 "8. Git hooks for every repo on this machine (optional, OFF by default)"
say "  This sets git's global hooksPath to ~/.claude/git-hooks, so commit-msg,"
say "  pre-commit, pre-merge-commit and pre-push (copied in step 1) run in EVERY repo on"
say "  this machine."
say "  The sharp edge: it REPLACES any hooks a repo already has in its own"
say "  .git/hooks/ — those stop running the moment this is on."
if ask "Set git's global core.hooksPath to ~/.claude/git-hooks?" "n"; then
  if git config --global core.hooksPath "$DEST/git-hooks"; then
    ok "Set — git now runs ~/.claude/git-hooks/* in every repository."
    say  "     To undo: git config --global --unset core.hooksPath"
  else
    warn "Could not set it — run by hand:"
    say  "       git config --global core.hooksPath ~/.claude/git-hooks"
  fi
else
  skip "Skipped — any hooks a repo already has keep running, untouched."
fi

# --- done ------------------------------------------------------------------
head2 "Done"
if [ -d "$BACKUP" ] && [ -n "$(ls -A "$BACKUP" 2>/dev/null)" ]; then
  say "  Files that were replaced are saved in ~/.claude/${BACKUP##*/}/"
else
  rmdir "$BACKUP" 2>/dev/null
fi
cat <<'NEXT'

  Next, in this order:
    1. Open ~/.claude/CLAUDE.md and fill it in. It is written as a
       fill-in-the-blanks form and explains why each part helps.
    2. Open ~/.claude/.redaction-names.local and add any real names, handles
       or employer names that must never reach a public commit — it was
       installed empty (with its two sections explained in its own comments)
       so the privacy check in git-hooks/pre-commit would have a file to
       read at all; it can't catch a name you haven't listed.
    3. Start a new Claude Code session (hooks load at session start, so an
       already-open session will not see them yet).
    4. Ask Claude: "what process rules are you working under?" — if it can
       list them back, the setup is live.

  Optional reading, in the repo you just ran this from:
    README.md            what this is and why it is shaped this way
    HOW-I-WORK.md        the daily way of working the rules serve
    LESSONS.md           the rules as lessons, each with the incident that taught it
    MULTI-CHAT-ROLES.md  running several Claude chats on one codebase
NEXT
say ""
