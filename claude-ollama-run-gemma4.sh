#!/usr/bin/env bash
# Startet das Modell gemma4:12b in Ollama.
set -euo pipefail

MODEL="gemma4:latest"

echo "Starting Claude Code with Ollama model: $MODEL"

ollama launch claude --model "$MODEL"