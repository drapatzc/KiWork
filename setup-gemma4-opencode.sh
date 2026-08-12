#!/bin/bash

set -e

BASE_MODEL="gemma4:12b"
CUSTOM_MODEL="atomium-kasse"
OPENCODE_MODEL="ollama/${CUSTOM_MODEL}"

OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"

MODELFILE="/tmp/Modelfile.${CUSTOM_MODEL}"

echo "Prüfe Ollama..."

if ! command -v ollama >/dev/null 2>&1; then
    echo "Ollama ist nicht installiert."
    exit 1
fi

echo "Ollama Version:"
ollama --version

echo ""
echo "Starte Ollama, falls nötig..."

if ! pgrep -x "ollama" >/dev/null 2>&1; then
    ollama serve >/tmp/ollama.log 2>&1 &
    sleep 3
fi

echo ""
echo "Prüfe, ob Basis-Modell bereits installiert ist: $BASE_MODEL"

if ollama list | awk '{print $1}' | grep -Fxq "$BASE_MODEL"; then
    echo "Basis-Modell ist bereits installiert. Download wird übersprungen."
else
    echo "Lade Basis-Modell herunter: $BASE_MODEL"
    ollama pull "$BASE_MODEL"
fi

echo ""
echo "Erstelle eigenes Ollama-Modell: $CUSTOM_MODEL"

cat > "$MODELFILE" <<EOF
FROM $BASE_MODEL

PARAMETER temperature 0.2
PARAMETER num_ctx 32768

SYSTEM """
Du bist ein Assistent für ein fiktives Krankenkassen-System.

Regeln:
- Erfinde keine Versichertendaten.
- Nutze Stammdaten nur aus angebundenen Tools, APIs oder MCP.
- Nutze RAG/Qdrant nur für Dokumentenwissen.
- Bei fehlenden Daten sag klar, dass keine Information gefunden wurde.
- Gib kurze, sachliche und nachvollziehbare Antworten.
"""
EOF

ollama create "$CUSTOM_MODEL" -f "$MODELFILE"

echo ""
echo "Aktualisiere OpenCode-Konfiguration..."

mkdir -p "$OPENCODE_CONFIG_DIR"

if [ -f "$OPENCODE_CONFIG_FILE" ]; then
    cp "$OPENCODE_CONFIG_FILE" "$OPENCODE_CONFIG_FILE.backup.$(date +%Y%m%d-%H%M%S)"
else
    echo '{}' > "$OPENCODE_CONFIG_FILE"
fi

python3 <<PY
import json
from pathlib import Path

config_file = Path("$OPENCODE_CONFIG_FILE")
model = "$CUSTOM_MODEL"
opencode_model = "$OPENCODE_MODEL"

try:
    config = json.loads(config_file.read_text())
except Exception:
    config = {}

config["$schema"] = "https://opencode.ai/config.json"
config["model"] = opencode_model
config["small_model"] = opencode_model

provider = config.setdefault("provider", {})
ollama = provider.setdefault("ollama", {})

ollama["npm"] = "@ai-sdk/openai-compatible"
ollama["name"] = "Ollama (local)"
ollama["options"] = {
    "baseURL": "http://localhost:11434/v1"
}

models = ollama.setdefault("models", {})
models[model] = {
    "name": "Atomium Krankenkasse / Gemma 4 12B"
}

config_file.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\\n")
PY

echo ""
echo "Teste Modell..."
ollama run "$CUSTOM_MODEL" "Antworte kurz auf Deutsch: Welches Modell läuft?"

echo ""
echo "Fertig."
echo "Basis-Modell: $BASE_MODEL"
echo "Ollama Alias:  $CUSTOM_MODEL"
echo "OpenCode:      $OPENCODE_MODEL"
echo "Config:        $OPENCODE_CONFIG_FILE"
