#!/usr/bin/env python3
"""
Claude Code token usage tracker — Stop hook.
Reads transcripts, writes ~/.claude/token_status.json.
Window is measured from last rate-limit event (stored in token_limits.json).
"""

import json
import sys
import os
import glob
from datetime import datetime, timezone


LIMITS_FILE = os.path.expanduser("~/.claude/token_limits.json")


def load_limits():
    try:
        with open(LIMITS_FILE) as f:
            return json.load(f)
    except Exception:
        return {"events": []}


def parse_transcript(path, cutoff_time=None):
    totals = {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if entry.get("type") != "assistant":
                    continue
                if cutoff_time:
                    ts = entry.get("timestamp")
                    if ts:
                        try:
                            entry_time = datetime.fromisoformat(
                                ts.replace("Z", "+00:00")
                            )
                            if entry_time < cutoff_time:
                                continue
                        except ValueError:
                            pass
                usage = entry.get("message", {}).get("usage", {})
                totals["input"] += usage.get("input_tokens", 0)
                totals["output"] += usage.get("output_tokens", 0)
                totals["cache_write"] += usage.get("cache_creation_input_tokens", 0)
                totals["cache_read"] += usage.get("cache_read_input_tokens", 0)
    except (OSError, IOError):
        pass
    return totals


def sum_all_since(cutoff_time=None):
    totals = {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}
    projects_dir = os.path.expanduser("~/.claude/projects")
    for jsonl_file in glob.glob(
        os.path.join(projects_dir, "**", "*.jsonl"), recursive=True
    ):
        ft = parse_transcript(jsonl_file, cutoff_time)
        for key in totals:
            totals[key] += ft[key]
    return totals


def main():
    hook_data = {}
    try:
        raw = sys.stdin.read()
        if raw.strip():
            hook_data = json.loads(raw)
    except Exception:
        pass

    transcript_path = hook_data.get("transcript_path", "")

    # Current session tokens (no cutoff — full session)
    session = (
        parse_transcript(transcript_path)
        if transcript_path and os.path.exists(transcript_path)
        else {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}
    )
    # Cache reads cost ~10% of regular tokens; weight accordingly so the total
    # correlates with Anthropic's actual rate-limit accounting.
    session["total"] = (
        session["input"] + session["output"] +
        session["cache_write"] + int(session["cache_read"] * 0.1)
    )

    # Load limit event history
    limits_data = load_limits()
    events = limits_data.get("events", [])

    # Tokens since last rate-limit event (or all time if none recorded)
    cutoff = None
    if events:
        last_event_ts = events[-1]["timestamp"]
        try:
            cutoff = datetime.fromisoformat(last_event_ts.replace("Z", "+00:00"))
        except ValueError:
            pass

    window = sum_all_since(cutoff)
    window["total"] = (
        window["input"] + window["output"] +
        window["cache_write"] + int(window["cache_read"] * 0.1)
    )

    # Estimated limit: median of recorded limit values
    observed = [e["tokens_at_limit"] for e in events if "tokens_at_limit" in e]
    estimated_limit = None
    if observed:
        s = sorted(observed)
        mid = len(s) // 2
        estimated_limit = s[mid] if len(s) % 2 != 0 else (s[mid - 1] + s[mid]) // 2

    status = {
        "updated_ts": datetime.now().isoformat(),
        "session": session,
        "window": window,
        "window_start": events[-1]["timestamp"] if events else None,
        "estimated_limit": estimated_limit,
        "limit_event_count": len(events),
    }

    status_path = os.path.expanduser("~/.claude/token_status.json")
    with open(status_path, "w") as f:
        json.dump(status, f)


if __name__ == "__main__":
    main()
