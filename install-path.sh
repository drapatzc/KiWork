#!/bin/sh
# Adds this KiWork folder to the PATH in ~/.zshrc so all its scripts
# can be called from anywhere by filename (e.g. "ollama-start.sh").
# Idempotent -- can be run multiple times, only appends if missing.
# Compatible with zsh and bash

set -e

KIWORK_DIR="$(cd "$(dirname "$0")" && pwd)"
ZSHRC="$HOME/.zshrc"
MARKER="# KiWork Scripte"
PATH_LINE="export PATH=\"$KIWORK_DIR:\$PATH\""

echo "==> Checking $ZSHRC for KiWork PATH entry"

if [ ! -f "$ZSHRC" ]; then
  echo "ERROR: $ZSHRC not found."
  exit 1
fi

if grep -qF "$MARKER" "$ZSHRC"; then
  echo "   already present, unchanged"
else
  {
    echo ""
    echo "$MARKER"
    echo "$PATH_LINE"
  } >> "$ZSHRC"
  echo "   added to $ZSHRC"
fi

echo "==> Making sure all .sh scripts here are executable"
chmod +x "$KIWORK_DIR"/*.sh

echo ""
echo "Done. Open a new terminal (or: source ~/.zshrc) so the scripts"
echo "are on the PATH."
