#!/bin/sh
# One-time installation of the OpenCode stack (Ollama + OpenCode + gemma4)
# Idempotent — can be run multiple times
# Compatible with zsh and bash

set -e

echo "==> Checking prerequisites"

if ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew is missing. See the manual, chapter 2."
  exit 1
fi

echo "==> Installing Ollama (official app via cask)"
# IMPORTANT: cask "ollama-app" (official app with the full runner),
# NOT the formula "brew install ollama" -- that ships only the MLX runner
# and cannot start GGUF models like gemma4 (llama-server is missing).
if [ ! -d "/Applications/Ollama.app" ]; then
  brew install --cask ollama-app
fi

echo "==> Installing OpenCode"
if ! command -v opencode >/dev/null 2>&1; then
  curl -fsSL https://opencode.ai/install | bash
fi

echo "==> Starting Ollama (official app)"
brew services stop ollama >/dev/null 2>&1
open -a Ollama >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -s --max-time 2 http://localhost:11434 >/dev/null 2>&1 && break
  sleep 1
done

echo "==> Downloading gemma4 (approx. 6-8 GB, one time)"
if ! ollama list 2>/dev/null | grep -q "gemma4:latest"; then
  ollama pull gemma4:latest
fi

echo "==> Creating ~/.config/opencode/opencode.json (if missing)"
CONFIG_DIR="$HOME/.config/opencode"
CONFIG_FILE="$CONFIG_DIR/opencode.json"
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "gemma4:latest": {
          "name": "Gemma 4",
          "tool_call": true
        }
      }
    }
  },
  "model": "ollama/gemma4:latest",
  "permission": {
    "bash": "allow",
    "read": "allow",
    "glob": "allow",
    "grep": "allow",
    "edit": "ask",
    "write": "ask",
    "task": "deny",
    "webfetch": "deny"
  }
}
EOF
  echo "   created: $CONFIG_FILE"
else
  echo "   already exists, unchanged"
fi

echo ""
echo "Done. Next steps:"
echo "  ./opencode-up.sh         # start Ollama"
echo "  ./opencode-start.sh      # start OpenCode"
