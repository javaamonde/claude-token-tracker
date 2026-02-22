#!/usr/bin/env python3
"""Merges the ClaudeTokens Stop hook into ~/.claude/settings.json without clobbering other settings."""
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
script_path   = os.path.expanduser("~/.claude/scripts/token_tracker.py")

hook_entry = {
    "hooks": [{"type": "command", "command": f"python3 {script_path}"}]
}

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks     = settings.setdefault("hooks", {})
stop_list = hooks.setdefault("Stop", [])

already = any(
    any("token_tracker.py" in h.get("command", "")
        for h in entry.get("hooks", []))
    for entry in stop_list
)

if not already:
    stop_list.append(hook_entry)
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
    print("  ✓ Hook added to ~/.claude/settings.json")
else:
    print("  ✓ Hook already present in ~/.claude/settings.json")
