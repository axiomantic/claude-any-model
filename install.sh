#!/usr/bin/env bash
# ==============================================================================
# claude-threepio One-Liner Installer
# ==============================================================================
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/axiomantic/claude-threepio/main/install.sh)"
# ==============================================================================

set -euo pipefail

TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'claude-threepio-install')"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

SCRIPT_PATH="$TMP_DIR/claude-threepio"
RAW_URL="https://raw.githubusercontent.com/axiomantic/claude-threepio/main/claude-threepio"

echo -e "\033[1;36m[INSTALL]\033[0m Fetching latest claude-threepio installer..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW_URL" -o "$SCRIPT_PATH"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$SCRIPT_PATH" "$RAW_URL"
else
    echo -e "\033[1;31m[ERROR]\033[0m curl or wget is required to install claude-threepio." >&2
    exit 1
fi

chmod +x "$SCRIPT_PATH"

# Run the 9-step interactive setup wizard attached to TTY
if [ -t 0 ] || [ -e /dev/tty ]; then
    python3 "$SCRIPT_PATH" install < /dev/tty
else
    python3 "$SCRIPT_PATH" install
fi

# Ensure persistent binary install in ~/.claude-threepio/bin and ~/.local/bin
TARGET_DIR="$HOME/.claude-threepio/bin"
LOCAL_BIN="$HOME/.local/bin"

mkdir -p "$TARGET_DIR"
cp "$SCRIPT_PATH" "$TARGET_DIR/claude-threepio"
chmod +x "$TARGET_DIR/claude-threepio"

if [ -d "$LOCAL_BIN" ] || [ -w "$HOME" ]; then
    mkdir -p "$LOCAL_BIN"
    ln -sf "$TARGET_DIR/claude-threepio" "$LOCAL_BIN/claude-threepio"
fi
