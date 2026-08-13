#!/bin/sh
# One-time installation of the local AI stack (Ollama + LiteLLM + gemma4)
# Idempotent — can be run multiple times
# Compatible with zsh and bash

set -e

echo "==> Checking prerequisites"

if ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew is missing. See the manual, chapter 2."
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "==> Installing Node.js"
  brew install node
fi

echo "==> Installing Claude Code"
if ! command -v claude >/dev/null 2>&1; then
  npm install -g @anthropic-ai/claude-code
fi

echo "==> Installing Ollama (official app via cask)"
# IMPORTANT: cask "ollama-app" (official app with the full runner),
# NOT the formula "brew install ollama" -- that ships only the MLX runner
# and cannot start GGUF models like gemma4 (llama-server is missing).
if [ ! -d "/Applications/Ollama.app" ]; then
  brew install --cask ollama-app
fi

echo "==> Installing Python 3.13 (LiteLLM needs Python 3.13 max.)"
if ! brew list python@3.13 >/dev/null 2>&1; then
  brew install python@3.13
fi
PYTHON313="$(brew --prefix python@3.13)/bin/python3.13"

echo "==> Installing pipx"
if ! brew list pipx >/dev/null 2>&1; then
  brew install pipx
  pipx ensurepath
fi

echo "==> Installing LiteLLM"
if ! pipx list 2>/dev/null | grep -q litellm; then
  pipx install --python "$PYTHON313" 'litellm[proxy]'
fi

echo "==> Starting Ollama (official app)"
open -a Ollama >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -s --max-time 2 http://localhost:11434 >/dev/null 2>&1 && break
  sleep 1
done

echo "==> Downloading gemma4:latest (approx. 9.6 GB, one time)"
# Identical to OpenCode -> both tools use the same model (one shared Ollama
# instance). 8B, 131k context, structured tool calling.
# On M4/32 GB Claude Code is slow with it; on a Mac Ultra it's fast.
if ! ollama list 2>/dev/null | grep -q "gemma4:latest"; then
  ollama pull gemma4:latest
fi

echo "==> Creating ~/litellm_config.yaml (if missing)"
if [ ! -f "$HOME/litellm_config.yaml" ]; then
  cat > "$HOME/litellm_config.yaml" <<'EOF'
litellm_settings:
  drop_params: true

model_list:
  # Current Claude Code model names
  - model_name: claude-opus-4-8
    litellm_params:
      model: ollama_chat/gemma4:latest
      api_base: http://localhost:11434
      num_ctx: 32768
      additional_drop_params: ["thinking", "reasoning_effort"]

  - model_name: claude-haiku-4-5-20251001
    litellm_params:
      model: ollama_chat/gemma4:latest
      api_base: http://localhost:11434
      num_ctx: 32768
      additional_drop_params: ["thinking", "reasoning_effort"]

  - model_name: claude-sonnet-4-6
    litellm_params:
      model: ollama_chat/gemma4:latest
      api_base: http://localhost:11434
      num_ctx: 32768
      additional_drop_params: ["thinking", "reasoning_effort"]

  - model_name: claude-opus-4-7
    litellm_params:
      model: ollama_chat/gemma4:latest
      api_base: http://localhost:11434
      num_ctx: 32768
      additional_drop_params: ["thinking", "reasoning_effort"]

  # Older model names (fallback)
  - model_name: claude-3-5-sonnet-20241022
    litellm_params:
      model: ollama_chat/gemma4:latest
      api_base: http://localhost:11434
      num_ctx: 32768
      additional_drop_params: ["thinking", "reasoning_effort"]

  - model_name: claude-3-opus-20240229
    litellm_params:
      model: ollama_chat/gemma4:latest
      api_base: http://localhost:11434
      num_ctx: 32768
      additional_drop_params: ["thinking", "reasoning_effort"]

  # Catch-all: ANY other (incl. future) model name -> gemma4.
  # Prevents "Invalid model name" errors on Claude Code updates.
  - model_name: "*"
    litellm_params:
      model: ollama_chat/gemma4:latest
      api_base: http://localhost:11434
      num_ctx: 32768
      additional_drop_params: ["thinking", "reasoning_effort"]
EOF
  echo "   created"
else
  echo "   already exists, unchanged"
fi

echo ""
echo "Done. Next steps:"
echo "  ./localai-up.sh        # start the stack"
echo "  ./claude-local.sh      # Claude Code with gemma4"
