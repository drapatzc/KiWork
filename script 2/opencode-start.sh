#!/bin/sh
# Starts OpenCode with pre-flight checks
# Compatible with zsh and bash

OLLAMA_URL="http://localhost:11434"
CONFIG="$HOME/.config/opencode/opencode.json"

# opencode on PATH?
if ! command -v opencode >/dev/null 2>&1; then
  echo "ERROR: opencode is not on the PATH."
  echo "Install: ./install-opencode.sh"
  echo "If installed: 'source ~/.zshrc' and open a new terminal."
  exit 1
fi

# Ollama reachable?
if ! curl -s --max-time 2 "$OLLAMA_URL" >/dev/null 2>&1; then
  echo "ERROR: Ollama is not running ($OLLAMA_URL)"
  echo "Start it with: ./opencode-up.sh"
  exit 1
fi

# opencode.json present?
if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG is missing."
  echo "Please run ./install-opencode.sh first."
  exit 1
fi

echo "----------------------------------------------"
echo " OpenCode -> local AI (gemma4)"
echo " Model:    gemma4:latest via Ollama"
echo " Privacy:  fully local, no internet needed"
echo " Cost:     none"
echo "----------------------------------------------"
echo ""

opencode "$@"
