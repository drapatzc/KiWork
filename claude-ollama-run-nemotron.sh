#!/usr/bin/env bash
# Startet das Modell gemma4:12b in Ollama.
set -euo pipefail

MODEL="nemotron-3.5-lightning"

echo "Starting Claude Code with Ollama model: $MODEL"

ollama launch claude --model "$MODEL"