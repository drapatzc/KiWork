#!/usr/bin/env bash
# Beendet den Ollama-Hintergrunddienst.
set -euo pipefail

if pgrep -x "ollama" &>/dev/null || pgrep -x "Ollama" &>/dev/null; then
    echo "Beende Ollama ..."
    pkill -x Ollama &>/dev/null || true
    pkill -x ollama &>/dev/null || true
    echo "Ollama wurde beendet."
else
    echo "Ollama läuft nicht."
fi
