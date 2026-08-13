#!/bin/sh
# Shows the status of the OpenCode stack
# Compatible with zsh and bash

OLLAMA_URL="http://localhost:11434"
CONFIG="$HOME/.config/opencode/opencode.json"

echo "=============================="
echo " OpenCode — stack status"
echo "=============================="
echo ""

# opencode binary
if command -v opencode >/dev/null 2>&1; then
  VERSION="$(opencode --version 2>/dev/null | head -1)"
  echo " OpenCode:    installed ($VERSION)"
else
  echo " OpenCode:    NOT installed"
  echo "              Install: ./install-opencode.sh"
fi

# opencode.json
if [ -f "$CONFIG" ]; then
  MODEL="$(grep -E '"model"\s*:\s*"' "$CONFIG" | head -1 | sed 's/.*"model"[^"]*"\([^"]*\)".*/\1/')"
  echo " Config:      $CONFIG"
  [ -n "$MODEL" ] && echo " Model:       $MODEL"
else
  echo " Config:      MISSING ($CONFIG)"
fi

echo ""
echo "------------------------------"
echo " Services"
echo "------------------------------"
echo ""

# Ollama
if curl -s --max-time 2 "$OLLAMA_URL" >/dev/null 2>&1; then
  echo " Ollama:      running ($OLLAMA_URL)"
  MODELS=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')
  [ -n "$MODELS" ] && echo " Models:      $MODELS"
else
  echo " Ollama:      not running"
  echo "              Start: ./opencode-up.sh"
fi

echo ""
echo "=============================="
echo " Actions"
echo "=============================="
echo ""
echo " Start stack: ./opencode-up.sh"
echo " OpenCode:    ./opencode-start.sh"
echo " Stop stack:  ./opencode-down.sh"
echo ""
