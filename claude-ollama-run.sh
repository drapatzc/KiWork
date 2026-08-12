#!/usr/bin/env bash

set -euo pipefail

clear

echo "=============================================="
echo "        Claude Code + Ollama Launcher"
echo "=============================================="
echo
echo "Bitte ein Modell auswählen:"
echo
echo "1) Qwen3-Coder 30B"
echo "   ⭐ Beste Wahl für Swift, SwiftUI, Xcode, Refactoring und große Projekte."
echo
echo "2) Nemotron 3.5 Lightning"
echo "   ⭐ Sehr gut für Agenten, MCP, Code Reviews und Tool Calling."
echo
echo "3) Gemma 4"
echo "   ⭐ Schnell für Dokumentation, Erklärungen und allgemeine Aufgaben."
echo
read -rp "Auswahl (1-3): " choice

case "$choice" in
    1)
        MODEL="qwen3-coder:30b"
        ;;
    2)
        MODEL="nemotron-3.5-lightning"
        ;;
    3)
        MODEL="gemma4:latest"
        ;;
    *)
        echo
        echo "Ungültige Auswahl."
        exit 1
        ;;
esac

echo
echo "----------------------------------------------"
echo "Starte Claude Code..."
echo "Modell : $MODEL"
echo "----------------------------------------------"
echo

# Optional: größerer Kontext
export OLLAMA_CONTEXT_LENGTH=65536

exec ollama launch claude --model "$MODEL"