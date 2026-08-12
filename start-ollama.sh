#!/usr/bin/env bash
# Startet Ollama auf macOS: prüft Installation, aktualisiert bei Bedarf und
# reicht alle übergebenen Parameter unverändert an den ollama-Befehl weiter.
# Beispiel: ./start-ollama.sh run nemotron-3.5-lightning
set -euo pipefail

APP_PATH="/Applications/Ollama.app"
DOWNLOAD_URL="https://ollama.com/download/Ollama-darwin.zip"
GITHUB_LATEST_API="https://api.github.com/repos/ollama/ollama/releases/latest"

# Lädt die aktuelle Ollama.app herunter und installiert/ersetzt sie unter /Applications.
install_or_update_app() {
    local tmp_zip
    tmp_zip="$(mktemp -t ollama-download).zip"
    echo "Lade aktuelle Ollama-Version herunter ..."
    curl -fsSL "$DOWNLOAD_URL" -o "$tmp_zip"
    echo "Installiere nach $APP_PATH ..."
    rm -rf "$APP_PATH"
    unzip -q -o "$tmp_zip" -d /Applications
    rm -f "$tmp_zip"
}

# Prüft, ob der ollama-Befehl verfügbar ist, und installiert Ollama.app sonst neu.
ensure_installed() {
    if command -v ollama &>/dev/null; then
        return
    fi

    echo "Ollama ist nicht installiert."
    install_or_update_app

    if ! command -v ollama &>/dev/null; then
        echo "Lege Symlink für die Kommandozeile an ..."
        sudo mkdir -p /usr/local/bin
        sudo ln -sf "$APP_PATH/Contents/Resources/ollama" /usr/local/bin/ollama
    fi
}

# Vergleicht die lokal installierte mit der neuesten veröffentlichten Version
# und aktualisiert Ollama bei Bedarf.
ensure_updated() {
    local current latest
    current="$(ollama --version 2>/dev/null | awk '{print $NF}')"
    latest="$(curl -fsSL "$GITHUB_LATEST_API" | grep '"tag_name"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')"

    if [[ -z "$latest" ]]; then
        echo "Konnte die neueste Version nicht ermitteln – Update-Prüfung übersprungen."
        return
    fi

    if [[ "$current" != "$latest" ]]; then
        echo "Update verfügbar: $current -> $latest. Aktualisiere ..."
        pkill -x Ollama &>/dev/null || true
        install_or_update_app
    else
        echo "Ollama ist aktuell (Version $current)."
    fi
}

# Stellt sicher, dass der Ollama-Hintergrunddienst läuft, bevor Befehle
# wie "run" oder "pull" ausgeführt werden.
ensure_server_running() {
    if pgrep -x "ollama" &>/dev/null || pgrep -x "Ollama" &>/dev/null; then
        return
    fi

    echo "Starte Ollama ..."
    open -ga "$APP_PATH"

    for _ in $(seq 1 10); do
        curl -fsS http://127.0.0.1:11434 &>/dev/null && break
        sleep 1
    done
}

ensure_installed
ensure_updated
ensure_server_running

if [[ $# -eq 0 ]]; then
    echo "Ollama ist bereit. Beispiel: $(basename "$0") run nemotron-3.5-lightning"
    exit 0
fi

exec ollama "$@"
