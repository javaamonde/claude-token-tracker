#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$HOME/.claude/scripts"
APP_PATH="$HOME/Applications/ClaudeTokens.app"
BINARY_PATH="$APP_PATH/Contents/MacOS/ClaudeTokens"
PLIST_PATH="$HOME/Library/LaunchAgents/com.claude.tokentracker.plist"

echo "=== Claude Token Tracker Installer ==="
echo ""

# ── Prerequisites ─────────────────────────────────────────────────────────────
if ! command -v swiftc &>/dev/null; then
    echo "✗ swiftc not found. Install Xcode Command Line Tools:"
    echo "    xcode-select --install"
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "✗ python3 not found."
    exit 1
fi

# ── 1. Python hook ────────────────────────────────────────────────────────────
echo "Installing token_tracker.py..."
mkdir -p "$SCRIPTS_DIR"
cp "$REPO_DIR/token_tracker.py" "$SCRIPTS_DIR/token_tracker.py"
echo "  ✓ Copied to $SCRIPTS_DIR/token_tracker.py"

# ── 2. Register Stop hook in settings.json ───────────────────────────────────
echo "Registering Claude Code Stop hook..."
python3 "$REPO_DIR/register_hook.py"

# ── 3. Compile the Swift app ─────────────────────────────────────────────────
echo "Compiling ClaudeTokens (this takes ~10s)..."
TMPBIN=$(mktemp /tmp/ClaudeTokens.XXXX)
swiftc "$REPO_DIR/main.swift" \
    -framework AppKit -framework Foundation \
    -o "$TMPBIN"
echo "  ✓ Compiled"

# ── 4. Build .app bundle ──────────────────────────────────────────────────────
echo "Building ClaudeTokens.app..."
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
cp "$TMPBIN" "$BINARY_PATH"
rm "$TMPBIN"

# ── 4a. Download Material Symbols font (needed for token icon) ────────────────
FONT_PATH="$APP_PATH/Contents/Resources/MaterialSymbolsRounded.ttf"
if [ ! -f "$FONT_PATH" ]; then
    echo "Downloading Material Symbols font..."
    WOFF2_URL="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=block"
    WOFF2_FILE=$(curl -sA "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15" \
        "$WOFF2_URL" | grep -o "url([^)]*)" | head -1 | tr -d "url()")
    curl -sL "$WOFF2_FILE" -o /tmp/MaterialSymbolsRounded.woff2
    # Convert WOFF2 → TTF using fonttools (install if needed)
    pip3 install -q fonttools brotli 2>/dev/null
    python3 -c "
from fontTools.ttLib import TTFont
font = TTFont('/tmp/MaterialSymbolsRounded.woff2')
font.flavor = None
font.save('$FONT_PATH')
"
    rm -f /tmp/MaterialSymbolsRounded.woff2
    echo "  ✓ Font installed"
fi

cat > "$APP_PATH/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>  <string>com.claude.tokentracker</string>
  <key>CFBundleName</key>        <string>ClaudeTokens</string>
  <key>CFBundleExecutable</key>  <string>ClaudeTokens</string>
  <key>CFBundlePackageType</key> <string>APPL</string>
  <key>CFBundleVersion</key>     <string>1.0</string>
  <key>LSUIElement</key>         <true/>
  <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF
echo "  ✓ Built at $APP_PATH"

# ── 5. launchd agent (auto-start on login) ───────────────────────────────────
echo "Installing launchd agent..."
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>              <string>com.claude.tokentracker</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BINARY_PATH</string>
  </array>
  <key>RunAtLoad</key>          <true/>
  <key>KeepAlive</key>          <true/>
  <key>StandardOutPath</key>    <string>$HOME/.claude/token_menubar.log</string>
  <key>StandardErrorPath</key>  <string>$HOME/.claude/token_menubar.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
echo "  ✓ Agent loaded"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✓ All done! ClaudeTokens is running in your menu bar."
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to activate the Stop hook"
echo "  2. Use Claude Code normally — the bar fills as you use tokens"
echo "  3. When you hit the rate limit, click the menu bar icon → 'My tokens ran out'"
echo "     (do this each time you hit the limit; the app self-calibrates from there)"
