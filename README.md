# Claude Token Tracker

A macOS menu bar app that shows your [Claude Code](https://claude.ai/code) token usage in real time.

## What it does

- Shows a **live progress bar** in your menu bar tracking token usage since your last rate limit
- **Self-calibrating** — tap "My tokens ran out" when you hit the limit; the app learns your quota over time and the bar becomes more accurate with each event
- Shows the Material Symbols token icon with your session count before calibration
- Updates every 3 seconds via Claude Code's built-in Stop hook

## Requirements

- macOS 12+
- [Claude Code](https://claude.ai/code) installed and working
- Xcode Command Line Tools — install with: `xcode-select --install`
- Python 3 (ships with macOS)

## Install

```bash
git clone https://github.com/javaamonde/claude-token-tracker
cd claude-token-tracker
chmod +x install.sh
./install.sh
```

Then **restart Claude Code** to activate the Stop hook.

The installer:
1. Copies `token_tracker.py` to `~/.claude/scripts/`
2. Registers a Stop hook in `~/.claude/settings.json` (non-destructively merges)
3. Compiles the Swift app (~10s)
4. Downloads the Material Symbols font and installs it into the app bundle
5. Installs it to `~/Applications/ClaudeTokens.app`
6. Sets up a launchd agent so it starts automatically on login

> **Gatekeeper warning?** Since the binary isn't notarised, macOS may block it on first run. Right-click the app → Open to allow it once.

## How it works

```
Claude Code finishes a response
  → Stop hook fires token_tracker.py
    → reads ~/.claude/projects/**/*.jsonl transcripts
    → sums tokens since last recorded limit event
    → writes ~/.claude/token_status.json
      → ClaudeTokens.app reads it every 3s
        → renders progress bar in menu bar
```

## Usage

| State | Menu bar |
|-------|----------|
| No limit recorded yet | Token icon + session count |
| Limit known | Progress bar (fills left→right) |

**When you hit the rate limit:**
1. Click the menu bar icon
2. Click **"My tokens ran out"**
3. The app records the current token count as your estimated limit
4. The progress bar resets and starts filling again from zero

The estimate improves with each event (the app uses the median of all recorded limits).

## Uninstall

```bash
./uninstall.sh
```

## Files

| File | Purpose |
|------|---------|
| `main.swift` | Native Swift/AppKit menu bar app |
| `token_tracker.py` | Claude Code Stop hook — reads transcripts, writes status JSON |
| `install.sh` | One-command installer |
| `uninstall.sh` | Removes the app and launchd agent |
| `register_hook.py` | Called by install.sh to safely merge into settings.json |
