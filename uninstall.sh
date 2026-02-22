#!/bin/bash
PLIST_PATH="$HOME/Library/LaunchAgents/com.claude.tokentracker.plist"

echo "=== Claude Token Tracker Uninstaller ==="

launchctl unload "$PLIST_PATH" 2>/dev/null && echo "  ✓ Stopped launchd agent" || true
rm -f "$PLIST_PATH" && echo "  ✓ Removed plist"
rm -rf "$HOME/Applications/ClaudeTokens.app" && echo "  ✓ Removed ClaudeTokens.app"

echo ""
echo "Token history and settings left intact:"
echo "  ~/.claude/token_status.json"
echo "  ~/.claude/token_limits.json"
echo "  ~/.claude/scripts/token_tracker.py"
echo ""
echo "Remove those manually if you want a clean sweep."
echo "You'll also want to remove the Stop hook from ~/.claude/settings.json."
