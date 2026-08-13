#!/bin/sh
# Claude Code with local AI (gemma4 via Ollama + LiteLLM proxy)
# Compatible with zsh and bash

OLLAMA_URL="http://localhost:11434"
LITELLM_URL="http://localhost:4000"

# Check Ollama
if ! curl -s --max-time 2 "$OLLAMA_URL" >/dev/null 2>&1; then
  echo "ERROR: Ollama is not running ($OLLAMA_URL)"
  echo "Start it with: ./localai-up.sh"
  exit 1
fi

# Check LiteLLM (/health/liveliness responds immediately, no model test)
if ! curl -s --max-time 5 "$LITELLM_URL/health/liveliness" >/dev/null 2>&1; then
  echo "ERROR: LiteLLM proxy is not running ($LITELLM_URL)"
  echo "Start it with: ./localai-up.sh"
  exit 1
fi

# Point Claude Code at the local proxy.
# Note: BASE_URL + API_KEY together can trigger a "Custom API key found?"
# dialog on the FIRST start if an additional subscription login (OAuth)
# exists in the keychain. Confirming once is enough -- the choice is
# remembered and the dialog won't appear again.
# There is no way to suppress it via a variable in interactive mode
# (only "claude -p" would bypass it, but that disables the chat).
# All requests are still guaranteed to go to the local proxy.
export ANTHROPIC_BASE_URL="$LITELLM_URL"
export ANTHROPIC_API_KEY="local"

# Limit output tokens. Otherwise Claude Code requests up to 64000 output
# tokens -- that blows the local context window (num_ctx in litellm_config)
# and leads to "response exceeded the ... output token maximum".
# 8192 fits within num_ctx: 32768 (the rest is left for the large system prompt).
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   LOCAL MODE — gemma4 via Ollama             ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Privacy: fully local                        ║"
echo "║  Cost:    none                               ║"
echo "║  ⚠  Slow on M4/32 GB (Mac Ultra: fast)       ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  ⚠  Claude Code shows 'Sonnet 4.6' —         ║"
echo "║     that's only the internal routing name.   ║"
echo "║     Actually running: gemma4 (local).        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

claude "$@"
