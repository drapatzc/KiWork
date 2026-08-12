#!/usr/bin/env bash
# Startet den Ollama-Hintergrunddienst, falls er nicht bereits läuft.
set -euo pipefail

if pgrep -x "ollama" &>/dev/null || pgrep -x "Ollama" &>/dev/null; then
    echo "Ollama läuft bereits."
    exit 0
fi

echo "Starte Ollama ..."
open -ga "/Applications/Ollama.app"

for _ in $(seq 1 10); do
    curl -fsS http://127.0.0.1:11434 &>/dev/null && break
    sleep 1
done

echo "Ollama ist bereit."
