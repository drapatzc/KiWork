#!/usr/bin/env bash
# Startet das Modell gemma4:12b in Ollama.
set -euo pipefail

MODEL="qwen3-coder:30b"

echo "Starting Claude Code with Ollama model: $MODEL"

ollama launch claude --model "$MODEL"