#!/bin/sh
# Shows the current Claude Code AI configuration status
# Compatible with zsh and bash

OLLAMA_URL="http://localhost:11434"
LITELLM_URL="http://localhost:4000"
PID_FILE="/tmp/litellm.pid"

echo "=============================="
echo " Claude Code — AI status"
echo "=============================="
echo ""

# Active configuration
if [ -z "$ANTHROPIC_BASE_URL" ]; then
  echo " Active AI:   Anthropic Cloud (Claude)"
  echo " Model:       Claude 3.5 / 4"
  echo " Privacy:     cloud - data leaves the Mac"
  if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo " API key:     NOT set"
  else
    KEY_PREVIEW="$(printf '%s' "$ANTHROPIC_API_KEY" | cut -c1-10)..."
    echo " API key:     $KEY_PREVIEW"
  fi
else
  echo " Active AI:   Local AI (gemma4 via Ollama)"
  echo " Base URL:    $ANTHROPIC_BASE_URL"
  echo " Privacy:     fully local"
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
  echo "              Start: ./localai-up.sh"
fi

echo ""

# LiteLLM
if curl -s --max-time 2 "$LITELLM_URL/health" >/dev/null 2>&1; then
  PID_INFO=""
  [ -f "$PID_FILE" ] && PID_INFO=" (PID $(cat "$PID_FILE"))"
  echo " LiteLLM:     running ($LITELLM_URL)$PID_INFO"
else
  echo " LiteLLM:     not running"
  echo "              Start: ./localai-up.sh"
fi

echo ""
echo "=============================="
echo " Switch backend"
echo "=============================="
echo ""
echo " Local: ./claude-local.sh"
echo " Sub:   ./claude-abo.sh"
echo " Cloud: ./claude-api.sh"
echo ""
