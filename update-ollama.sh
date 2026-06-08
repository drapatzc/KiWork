#!/bin/bash

set -e

DMG_URL="https://ollama.com/download/Ollama.dmg"
DMG_FILE="/tmp/Ollama.dmg"
MOUNT_POINT="/Volumes/Ollama"

echo "Beende Ollama..."
killall Ollama 2>/dev/null || true
killall ollama 2>/dev/null || true

echo "Lade aktuelle Ollama DMG..."
curl -L "$DMG_URL" -o "$DMG_FILE"

echo "Mounte DMG..."
hdiutil detach "$MOUNT_POINT" 2>/dev/null || true
hdiutil attach "$DMG_FILE" -nobrowse

echo "Installiere Ollama.app nach /Applications..."
sudo rm -rf "/Applications/Ollama.app"
sudo cp -R "$MOUNT_POINT/Ollama.app" "/Applications/Ollama.app"

echo "Entferne DMG..."
hdiutil detach "$MOUNT_POINT"
rm -f "$DMG_FILE"

echo "Starte Ollama neu..."
open -a Ollama

sleep 5

echo "Installierte Version:"
ollama --version

echo ""
echo "Fertig."
