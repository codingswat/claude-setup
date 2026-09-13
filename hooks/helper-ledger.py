#!/usr/bin/env python3
"""Helper ledger — one line per finished subagent/workflow-agent, appended by a Stop hook.

Problem: subagents and workflow agents burn tokens with no record of what they cost. This
script scans their transcripts and appends one row per finished helper to a TSV ledger, so
spend is visible after the fact without slowing down every turn.

Where transcript files live (found by inspecting real Claude Code project folders):
  - plain subagent:    ~/.claude/projects/<project>/<session-id>/subagents/agent-<id>.jsonl
  - workflow agent:     ~/.claude/projects/<project>/<session-id>/subagents/workflows/wf_<id>/agent-<id>.jsonl
  Both are named `agent-<id>.jsonl`; a file is a "workflow" helper iff a `workflows`
  directory sits between `subagents` and the filename, else it is a plain "agent" helper.
  The parent session id is the directory that directly contains `subagents`.
  Each line is one JSON object. Assistant records have `type == "assistant"`,
  `message.id`, `message.model`, `message.usage` (input_tokens, cache_creation_input_tokens,
  cache_read_input_tokens, output_tokens) and a top-level `timestamp` (ISO-8601 UTC). One
  step (one turn) can appear as several lines sharing the same `message.id` while the
  response streams in — dedupe on that id, keep the max seen per field (output_tokens grows
  as it streams; the other fields are stable across the duplicate lines in every file
  inspected). No field for "subagent type" or "the parent's name for this helper" was found
  in either kind of transcript, so no such column is written.

Ledger: ~/.claude/ledgers/helpers.tsv (created with a header on first write). One row per
helper: date (first timestamp, local time, YYYY-MM-DD HH:MM) \t parent session id \t agent
id \t kind (agent|workflow) \t model (opus|sonnet|haiku|...) \t steps (unique message ids)
\t peak_context_tokens (max over steps of cache_read + cache_creation + input) \t
output_tokens (sum over steps) \t minutes (first-to-last timestamp, rounded) \t cost_usd
(2dp, see RATES below).

RATES — illustrative list prices, $ per million tokens, meant to be edited to whatever your
own provider actually charges; cache writes are billed at the 1-hour rate (the field
`cache_creation_input_tokens` is the total across both the 5-minute and 1-hour ephemeral
cache tiers; this script does not split them, it prices the whole total at the single
1-hour-rate number below):
    model    in    out   cache_read  cache_write(1h)
    opus      5    25    0.50        10
    sonnet    2    10    0.20         4
    haiku     1     5    0.10         2

Cost per helper = sum over steps of (input*in + output*out + cache_read*cache_read_rate +
cache_creation*cache_write_rate) / 1_000_000, rounded to 2dp.

Performance: with no arguments the script does a full scan, appends new rows, prints
nothing, and always exits 0 (it is wired as a Stop hook — a hook must never block the
session, so every path is wrapped in try/except and stays silent on error). Files modified
in the last 120s are treated as still-running and skipped (re-checked next Stop). After a
file is scanned and found stable (mtime older than 120s), its mtime feeds a watermark saved
at ~/.claude/ledgers/.helper-ledger.stamp; the next run skips any file with an older mtime
than the watermark without opening it. The first run against a large existing transcript
tree does a one-time cold backfill (opens and parses every historical file at least once);
every run after the watermark exists is a fast incremental pass over whatever finished since
the last Stop.
A non-blocking file lock (~/.claude/ledgers/.helper-ledger.lock) serializes concurrent
invocations — several Claude Code sessions on one machine can finish a turn at nearly the
same moment and fire this Stop hook together; a second overlapping invocation skips itself
rather than race the first.

`--tail N` prints the last N ledger lines plus one summary line per model (count, total
cost, median peak context) and exits without scanning.

Env overrides (used by the test suite to point the script at a throwaway tree):
  HOME                 — changes both the ledger location and the default projects dir
  CLAUDE_PROJECTS_DIR   — overrides the projects dir independently of HOME

Enforced by: hooks/test-hooks.sh (the helper-ledger section)
"""
import fcntl
import json
import os
import statistics
import sys
import time
from datetime import datetime

RATES = {
    "opus":   {"in": 5,  "out": 25, "cache_read": 0.50, "cache_write": 10},
    "sonnet": {"in": 2,  "out": 10, "cache_read": 0.20, "cache_write": 4},
    "haiku":  {"in": 1,  "out": 5,  "cache_read": 0.10, "cache_write": 2},
}
MODEL_ORDER = ("opus", "sonnet", "haiku")  # first substring match wins

STILL_RUNNING_S = 120
HEADER = "date\tparent_session_id\tagent_id\tkind\tmodel\tsteps\tpeak_context_tokens\toutput_tokens\tminutes\tcost_usd"


def projects_dir():
    return os.environ.get("CLAUDE_PROJECTS_DIR") or os.path.expanduser("~/.claude/projects")


def ledger_dir():
    return os.path.expanduser("~/.claude/ledgers")


def ledger_path():
    return os.path.join(ledger_dir(), "helpers.tsv")


def stamp_path():
    return os.path.join(ledger_dir(), ".helper-ledger.stamp")


def shorten_model(model):
    m = (model or "").lower()
    for name in MODEL_ORDER:
        if name in m:
            return name
    return m or "unknown"


def find_agent_files(root):
    """Every `agent-*.jsonl` under root, with its derived (parent_session_id, kind)."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        for fn in filenames:
            if fn.startswith("agent-") and fn.endswith(".jsonl"):
                out.append(os.path.join(dirpath, fn))
    return out


def parent_session_and_kind(path):
    parts = path.split(os.sep)
    if "subagents" in parts:
        idx = parts.index("subagents")
        session_id = parts[idx - 1] if idx - 1 >= 0 else ""
        kind = "workflow" if "workflows" in parts[idx + 1:-1] else "agent"
    else:
        session_id = ""
        kind = "agent"
    return session_id, kind


def agent_id_from_filename(path):
    fn = os.path.basename(path)
    return fn[len("agent-"):-len(".jsonl")]


def parse_file(path):
    """Returns None (nothing usable / corrupt) or a dict of computed fields."""
    steps = {}  # message id -> {"model":..., "in":,"cache_read":,"cache_write":,"out":, "ts": [...]}
    try:
        with open(path, "r", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if not isinstance(d, dict) or d.get("type") != "assistant":
                    continue
                message = d.get("message") or {}
                mid = message.get("id")
                if not mid:
                    continue
                usage = message.get("usage") or {}
                ts = d.get("timestamp")
                step = steps.setdefault(mid, {"model": None, "in": 0, "cache_read": 0, "cache_write": 0, "out": 0, "ts": []})
                if message.get("model"):
                    step["model"] = message.get("model")
                step["in"] = max(step["in"], usage.get("input_tokens") or 0)
                step["cache_read"] = max(step["cache_read"], usage.get("cache_read_input_tokens") or 0)
                step["cache_write"] = max(step["cache_write"], usage.get("cache_creation_input_tokens") or 0)
                step["out"] = max(step["out"], usage.get("output_tokens") or 0)
                if ts:
                    step["ts"].append(ts)
    except Exception:
        return None

    if not steps:
        return None

    all_ts = sorted(t for s in steps.values() for t in s["ts"])
    if not all_ts:
        return None

    models = [s["model"] for s in steps.values() if s["model"]]
    model_name = models[0] if models else ""

    peak_context = max(s["in"] + s["cache_read"] + s["cache_write"] for s in steps.values())
    output_tokens = sum(s["out"] for s in steps.values())

    rate = RATES.get(shorten_model(model_name), RATES["sonnet"])
    cost = 0.0
    for s in steps.values():
        cost += (s["in"] * rate["in"] + s["out"] * rate["out"]
                  + s["cache_read"] * rate["cache_read"] + s["cache_write"] * rate["cache_write"]) / 1_000_000.0

    try:
        first_dt = datetime.fromisoformat(all_ts[0].replace("Z", "+00:00"))
        last_dt = datetime.fromisoformat(all_ts[-1].replace("Z", "+00:00"))
    except Exception:
        return None
    minutes = round((last_dt - first_dt).total_seconds() / 60.0)
    date_local = first_dt.astimezone().strftime("%Y-%m-%d %H:%M")

    return {
        "date": date_local,
        "kind_model": model_name,
        "steps": len(steps),
        "peak_context": peak_context,
        "output_tokens": output_tokens,
        "minutes": minutes,
        "cost": round(cost, 2),
    }


def load_existing_ids(path):
    ids = set()
    try:
        with open(path, "r") as f:
            next(f, None)  # header
            for line in f:
                cols = line.rstrip("\n").split("\t")
                if len(cols) >= 3:
                    ids.add(cols[2])
    except Exception:
        pass
    return ids


def read_watermark():
    try:
        with open(stamp_path(), "r") as f:
            return float(f.read().strip())
    except Exception:
        return 0.0


def write_watermark(value):
    try:
        os.makedirs(ledger_dir(), exist_ok=True)
        with open(stamp_path(), "w") as f:
            f.write(repr(value))
    except Exception:
        pass


def lock_path():
    return os.path.join(ledger_dir(), ".helper-ledger.lock")


def scan_and_append():
    """A Stop hook can fire from several concurrent Claude Code sessions on one machine at
    once; without a lock, two invocations can both read the ledger's pre-write state and
    both append the same rows. A non-blocking file lock makes a second, overlapping
    invocation skip itself rather than race — it costs nothing (the next Stop tries again)."""
    os.makedirs(ledger_dir(), exist_ok=True)
    fd = os.open(lock_path(), os.O_CREAT | os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(fd)
        return  # another invocation is already scanning; this Stop's work happens next time
    try:
        _scan_and_append_locked()
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        except Exception:
            pass
        os.close(fd)


def _scan_and_append_locked():
    now = time.time()
    root = projects_dir()
    if not os.path.isdir(root):
        return
    lpath = ledger_path()
    os.makedirs(ledger_dir(), exist_ok=True)
    existing_ids = load_existing_ids(lpath)
    watermark = read_watermark()

    new_lines = []
    max_stable_mtime = watermark

    for path in find_agent_files(root):
        try:
            mtime = os.path.getmtime(path)
        except Exception:
            continue
        if now - mtime < STILL_RUNNING_S:
            continue  # still running; revisit next Stop
        if mtime <= watermark:
            continue  # already covered by a prior full pass
        agent_id = agent_id_from_filename(path)
        if agent_id in existing_ids:
            if mtime > max_stable_mtime:
                max_stable_mtime = mtime
            continue
        parsed = parse_file(path)
        if mtime > max_stable_mtime:
            max_stable_mtime = mtime
        if not parsed:
            continue
        session_id, kind = parent_session_and_kind(path)
        row = "\t".join(str(v) for v in [
            parsed["date"], session_id, agent_id, kind, shorten_model(parsed["kind_model"]),
            parsed["steps"], parsed["peak_context"], parsed["output_tokens"], parsed["minutes"],
            "%.2f" % parsed["cost"],
        ])
        new_lines.append(row)
        existing_ids.add(agent_id)

    if new_lines:
        write_header = not os.path.isfile(lpath) or os.path.getsize(lpath) == 0
        with open(lpath, "a") as f:
            if write_header:
                f.write(HEADER + "\n")
            for row in new_lines:
                f.write(row + "\n")

    if max_stable_mtime > watermark:
        write_watermark(max_stable_mtime)


def tail(n):
    lpath = ledger_path()
    try:
        with open(lpath, "r") as f:
            lines = f.read().splitlines()
    except Exception:
        print("(no ledger yet)")
        return
    if not lines:
        print("(no ledger yet)")
        return
    header = lines[0].split("\t")
    rows = [l.split("\t") for l in lines[1:] if l.strip()]
    for line in lines[1:][-n:]:
        print(line)

    by_model = {}
    idx_model = header.index("model") if "model" in header else 4
    idx_cost = header.index("cost_usd") if "cost_usd" in header else 9
    idx_peak = header.index("peak_context_tokens") if "peak_context_tokens" in header else 6
    for r in rows:
        if len(r) <= max(idx_model, idx_cost, idx_peak):
            continue
        m = r[idx_model]
        by_model.setdefault(m, {"count": 0, "cost": 0.0, "peaks": []})
        by_model[m]["count"] += 1
        try:
            by_model[m]["cost"] += float(r[idx_cost])
        except Exception:
            pass
        try:
            by_model[m]["peaks"].append(int(r[idx_peak]))
        except Exception:
            pass
    for m in sorted(by_model):
        d = by_model[m]
        med = statistics.median(d["peaks"]) if d["peaks"] else 0
        print("SUMMARY %s count=%d cost=%.2f median_peak=%s" % (m, d["count"], d["cost"], med))


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--tail":
        try:
            n = int(sys.argv[2])
        except Exception:
            n = 10
        tail(n)
        return
    scan_and_append()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
