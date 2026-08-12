#!/usr/bin/env bash
# ki – zentrales Startscript für die lokale KI-Umgebung.
#
# Deckt alles ab: Ollama starten und beenden, Modelle laden, Claude Code
# gegen ein lokales Modell oder gegen die Cloud starten, sehen was im
# Arbeitsspeicher liegt und es dort wieder herauswerfen.
#
# WICHTIG: Kein Befehl dieses Scripts löscht ein Modell von der Festplatte.
#          "ki free" und "ki freeall" geben ausschliesslich RAM frei.
#
# Installation des Alias:  ./install-ki.sh

set -uo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
[[ "$HOST" != http* ]] && HOST="http://$HOST"

OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"

# Kontextgrösse für Claude Code gegen lokale Modelle.
KI_CONTEXT="${KI_CONTEXT:-65536}"

# ------------------------------------------------------- Modell-Registry
# Format:  id|Anzeigename|Empfehlung
MODELLE=(
    "qwen3-coder:30b|Qwen3-Coder 30B|Beste Wahl für Swift, SwiftUI, Xcode, Refactoring und große Projekte."
    "nemotron-3.5-lightning|Nemotron 3.5 Lightning|Sehr gut für Agenten, MCP, Code Reviews und Tool Calling."
    "gemma4:latest|Gemma 4|Schnell für Dokumentation, Erklärungen und allgemeine Aufgaben."
)

# ------------------------------------------------------------ Hilfsmittel

if [[ -t 1 ]]; then
    B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[31m'; G=$'\033[32m'
    Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
else
    B=""; DIM=""; R=""; G=""; Y=""; C=""; N=""
fi

titel() {
    printf '\n%s%s%s\n' "$B" "$1" "$N"
    printf '%s%s%s\n' "$DIM" "$(printf '─%.0s' $(seq 1 62))" "$N"
}

fehler() { printf '%sFehler: %s%s\n' "$R" "$1" "$N" >&2; }
ok()     { printf '%s✓ %s%s\n' "$G" "$1" "$N"; }

server_laeuft() { curl -fsS --max-time 3 "$HOST" &>/dev/null; }

# Speicher-Befehle laufen über ollama-mem.sh, wenn es daneben liegt.
MEM="$HIER/ollama-mem.sh"
hat_mem() { [[ -x "$MEM" ]]; }

# Feld n aus einem Registry-Eintrag holen.
feld() { printf '%s' "$1" | cut -d'|' -f"$2"; }

# Nimmt "1", "2", "3" oder einen Modellnamen und gibt die Modell-ID aus.
modell_aufloesen() {
    local eingabe="$1"

    if [[ "$eingabe" =~ ^[0-9]+$ ]]; then
        if (( eingabe >= 1 && eingabe <= ${#MODELLE[@]} )); then
            feld "${MODELLE[eingabe-1]}" 1
            return 0
        fi
        fehler "Es gibt nur die Modelle 1 bis ${#MODELLE[@]}."
        return 1
    fi

    # Direkter Treffer in der Registry
    local eintrag
    for eintrag in "${MODELLE[@]}"; do
        if [[ "$(feld "$eintrag" 1)" == "$eingabe" ]]; then
            printf '%s' "$eingabe"
            return 0
        fi
    done

    # Sonst: existiert das Modell überhaupt auf der Platte?
    if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$eingabe"; then
        printf '%s' "$eingabe"
        return 0
    fi

    fehler "Modell '$eingabe' ist nicht installiert."
    printf '\nInstallierte Modelle:\n' >&2
    ollama list 2>/dev/null | sed 's/^/  /' >&2
    return 1
}

modell_menue() {
    local i=1 eintrag
    for eintrag in "${MODELLE[@]}"; do
        printf '  %s%d%s  %s\n' "$C" "$i" "$N" "$(feld "$eintrag" 2)"
        printf '     %s%s%s\n' "$DIM" "$(feld "$eintrag" 3)" "$N"
        ((i++))
    done
}

# Fragt nach einem Modell, wenn keins auf der Kommandozeile stand.
modell_erfragen() {
    printf '%sWelches Modell?%s\n\n' "$B" "$N" >&2
    modell_menue >&2
    printf '\n' >&2
    local wahl
    read -r -p "Auswahl (1-${#MODELLE[@]}): " wahl
    modell_aufloesen "$wahl"
}

# ------------------------------------------------------------- Ollama

ollama_starten() {
    if server_laeuft; then
        ok "Ollama läuft bereits."
        return 0
    fi

    printf 'Starte Ollama ...\n'
    if [[ -d "/Applications/Ollama.app" ]]; then
        open -ga "/Applications/Ollama.app"
    else
        ollama serve &>/dev/null &
    fi

    local i
    for i in $(seq 1 20); do
        server_laeuft && { ok "Ollama ist bereit."; return 0; }
        sleep 1
    done

    fehler "Ollama antwortet nicht auf $HOST."
    return 1
}

ollama_beenden() {
    if hat_mem; then
        "$MEM" stop
    else
        printf 'Beende Ollama ...\n'
        pkill -f 'llama-server' &>/dev/null || true
        pkill -x Ollama &>/dev/null || true
        pkill -x ollama &>/dev/null || true
        ok "Ollama beendet."
    fi
}

# Lädt ein Modell in den Arbeitsspeicher, ohne einen Chat zu öffnen.
modell_laden() {
    local modell
    modell="$(modell_aufloesen "$1")" || return 1

    ollama_starten || return 1

    printf 'Lade %s%s%s in den Arbeitsspeicher ...\n' "$C" "$modell" "$N"
    if curl -fsS --max-time 600 "$HOST/api/generate" \
            -d "$(jq -nc --arg m "$modell" '{model:$m, prompt:"", keep_alive:"30m"}')" &>/dev/null; then
        ok "$modell ist geladen."
        speicher_status
    else
        fehler "$modell konnte nicht geladen werden."
        return 1
    fi
}

# Lädt alle drei Modelle nacheinander. Achtung: braucht sehr viel RAM.
alle_laden() {
    local gesamt=0 eintrag id
    for eintrag in "${MODELLE[@]}"; do
        id="$(feld "$eintrag" 1)"
        local groesse
        groesse=$(ollama list 2>/dev/null | awk -v m="$id" '$1 == m { print $3 }')
        printf '  %-26s %s\n' "$id" "${groesse:-?} GB"
    done

    printf '\n%sAlle Modelle zusammen sprengen auf den meisten Macs den RAM.%s\n' "$Y" "$N"
    printf '%sOllama lagert dann auf die SSD aus und wird sehr langsam.%s\n\n' "$Y" "$N"

    local antwort
    read -r -p "Trotzdem alle laden? (j/N): " antwort
    [[ "$antwort" =~ ^[jJyY]$ ]] || { printf 'Abgebrochen.\n'; return 0; }

    for eintrag in "${MODELLE[@]}"; do
        modell_laden "$(feld "$eintrag" 1)"
    done
}

# ------------------------------------------------------------ OpenCode

hat_opencode() { command -v opencode &>/dev/null; }

# Trägt alle Registry-Modelle in die OpenCode-Konfiguration ein, damit
# sie dort per "-m ollama/<modell>" ansprechbar sind.
opencode_konfig_sicherstellen() {
    mkdir -p "$(dirname "$OPENCODE_CONFIG")"
    [[ -f "$OPENCODE_CONFIG" ]] || printf '{}' > "$OPENCODE_CONFIG"

    local modelle_json="{}" eintrag id name
    for eintrag in "${MODELLE[@]}"; do
        id="$(feld "$eintrag" 1)"
        name="$(feld "$eintrag" 2)"
        modelle_json="$(jq -c --arg id "$id" --arg name "$name" \
            '. + {($id): {name: $name, tool_call: true}}' <<<"$modelle_json")"
    done

    local tmp
    tmp="$(mktemp)"
    jq --argjson models "$modelle_json" '
        ."$schema" = "https://opencode.ai/config.json"
        | .provider.ollama.npm = "@ai-sdk/openai-compatible"
        | .provider.ollama.options.baseURL = "http://127.0.0.1:11434/v1"
        | .provider.ollama.models = ((.provider.ollama.models // {}) + $models)
    ' "$OPENCODE_CONFIG" > "$tmp" && mv "$tmp" "$OPENCODE_CONFIG"
}

# OpenCode gegen ein lokales Ollama-Modell.
code_opencode() {
    local modell
    if [[ -n "${1:-}" ]]; then
        modell="$(modell_aufloesen "$1")" || return 1
    else
        modell="$(modell_erfragen)" || return 1
    fi

    if ! hat_opencode; then
        fehler "OpenCode ist nicht installiert."
        printf 'Installieren mit:  ./install-opencode.sh\n'
        return 1
    fi

    ollama_starten || return 1
    opencode_konfig_sicherstellen

    titel "OpenCode – lokal"
    printf 'Modell:    %s%s%s\n' "$C" "$modell" "$N"
    printf 'Kosten:    keine, alles bleibt auf diesem Mac\n\n'

    exec opencode --model "ollama/$modell"
}

# --------------------------------------------------------------- Codex

# Codex (OpenAI) gegen ein lokales Ollama-Modell.
code_codex() {
    local modell
    if [[ -n "${1:-}" ]]; then
        modell="$(modell_aufloesen "$1")" || return 1
    else
        modell="$(modell_erfragen)" || return 1
    fi

    ollama_starten || return 1

    titel "Codex – lokal"
    printf 'Modell:    %s%s%s\n' "$C" "$modell" "$N"
    printf 'Kontext:   %s\n' "$KI_CONTEXT"
    printf 'Kosten:    keine, alles bleibt auf diesem Mac\n\n'

    export OLLAMA_CONTEXT_LENGTH="$KI_CONTEXT"
    exec ollama launch codex --model "$modell"
}

# ---------------------------------------------------------- Claude Code

# Claude Code gegen ein lokales Ollama-Modell.
code_lokal() {
    local modell
    if [[ -n "${1:-}" ]]; then
        modell="$(modell_aufloesen "$1")" || return 1
    else
        modell="$(modell_erfragen)" || return 1
    fi

    ollama_starten || return 1

    titel "Claude Code – lokal"
    printf 'Modell:    %s%s%s\n' "$C" "$modell" "$N"
    printf 'Kontext:   %s\n' "$KI_CONTEXT"
    printf 'Kosten:    keine, alles bleibt auf diesem Mac\n\n'

    export OLLAMA_CONTEXT_LENGTH="$KI_CONTEXT"
    exec ollama launch claude --model "$modell"
}

# Claude Code über das Claude-Abo (OAuth-Login im Schlüsselbund).
code_abo() {
    unset ANTHROPIC_API_KEY
    unset ANTHROPIC_BASE_URL

    if ! security find-generic-password -s "Claude Code-credentials" &>/dev/null; then
        fehler "Kein Claude-Abo-Login gefunden."
        printf 'Anmelden mit:  claude  → dann /login\n'
        return 1
    fi

    titel "Claude Code – Abo"
    printf 'Auth:      OAuth-Login aus dem Schlüsselbund\n'
    printf 'Kosten:    über dein Abo, keine API-Kosten\n\n'

    exec claude "$@"
}

# Claude Code über die Anthropic-Cloud mit API-Key.
code_api() {
    unset ANTHROPIC_BASE_URL

    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        fehler "ANTHROPIC_API_KEY ist nicht gesetzt."
        printf 'Setzen mit:  export ANTHROPIC_API_KEY="sk-ant-..."\n'
        return 1
    fi

    titel "Claude Code – Anthropic Cloud"
    printf 'Auth:      API-Key\n'
    printf 'Achtung:   Daten verlassen den Mac, Abrechnung pro Token\n\n'

    exec claude "$@"
}

# ------------------------------------------------------------- Speicher

speicher_status() {
    if hat_mem; then
        "$MEM" status
    else
        titel "Geladene Modelle"
        ollama ps 2>/dev/null || fehler "Ollama antwortet nicht."
    fi
}

speicher_frei() {
    if [[ -z "${1:-}" ]]; then
        hat_mem && { "$MEM" freeall; return; }
        local m
        while read -r m; do
            [[ -n "$m" ]] && ollama stop "$m" && ok "$m entladen."
        done < <(ollama ps 2>/dev/null | awk 'NR>1 {print $1}')
        return
    fi

    local modell
    modell="$(modell_aufloesen "$1")" || return 1
    if hat_mem; then
        "$MEM" free "$modell"
    else
        ollama stop "$modell" && ok "$modell entladen."
    fi
}

modelle_zeigen() {
    titel "Modelle auf der Festplatte"
    printf '%sWird von diesem Script nie gelöscht.%s\n\n' "$DIM" "$N"
    ollama list 2>/dev/null || fehler "Ollama antwortet nicht."

    titel "Eingerichtete Modelle für ki"
    modell_menue
}

# ------------------------------------------------------------ Hauptmenü

hauptmenue() {
    local zeige_cloud=0
    while true; do
        clear
        printf '%s╔═══════════════════════════════════════════════════════════════════════╗%s\n' "$B" "$N"
        printf '%s║ Lokale KI-Umgebung (Ollama, OpenCode, Codex & Claude Code)	║%s\n' "$B" "$N"
        printf '%s║    				                             		║%s\n' "$B" "$N"
        printf '%s║ - Qwen3-Coder 30B		                           		║%s\n' "$B" "$N"
        printf '%s║   Beste Wahl für Swift, SwiftUI, Xcode, Refactoring   		║%s\n' "$B" "$N"
        printf '%s║ - Nemotron 3.5 Lightning	                          		║%s\n' "$B" "$N"
        printf '%s║   Sehr gut für Agenten, MCP, Code Reviews und Tool Calling.		║%s\n' "$B" "$N"
        printf '%s║ - Gemma 4			                          		║%s\n' "$B" "$N"
        printf '%s║   Schnell für Dokumentation, Erklärungen und allg. Aufgaben		║%s\n' "$B" "$N"
        printf '%s║    				                             		║%s\n' "$B" "$N"
        printf '%s║ by Christian Drapatz (8/2026)                              		║%s\n' "$B" "$N"
        printf '%s╚═══════════════════════════════════════════════════════════════════════╝%s\n' "$B" "$N"

        if server_laeuft; then
            local anzahl
            anzahl=$(curl -fsS --max-time 3 "$HOST/api/ps" 2>/dev/null | jq -r '.models | length' 2>/dev/null)
            printf '\nOllama: %släuft%s, %s Modell(e) im Speicher\n' "$G" "$N" "${anzahl:-0}"
        else
            printf '\nOllama: %sgestoppt%s\n' "$R" "$N"
        fi

	printf '\n%s Information:%s' "$B" "$N"
        printf '\n%s 🦙 Ollama: Führt KI-Modelle vollständig lokal auf deinem Rechner aus.%s' "$B" "$N"
        printf '\n%s 🖥️  OpenCode: Open-Source KI-Coding-Assistent, der ebenfalls mit lokalen Ollama-Modellen genutzt werden kann.%s' "$B" "$N"
        printf '\n%s 🧭 Codex: KI-Coding-Assistent von OpenAI, der ebenfalls mit lokalen Ollama-Modellen genutzt werden kann.%s' "$B" "$N"
        printf '\n%s 🤖 Claude Code: KI-Entwicklungsassistent von Anthropic, der auch mit lokalen Ollama-Modellen genutzt werden kann.%s' "$B" "$N"
        printf '\n%s 🧠 Qwen3-Coder 30B: Ideal für Softwareentwicklung, Refactoring und große Codeprojekte.%s' "$B" "$N"
        printf '\n%s ⚡ Nemotron 3.5 Lightning: Ideal für Agenten, Tool-Calling und komplexe Analyseaufgaben.%s' "$B" "$N"
        printf '\n%s 💎 Gemma 4: Ideal für Dokumentation, Erklärungen und allgemeine Entwicklungsaufgaben.%s\n' "$B" "$N"

        printf '\n%s OpenCode starten%s\n' "$B" "$N"
        printf '  [01] 🟢 Mit lokalem Modell (kostenlos, privat, Datenschutz)\n'
        printf '\n%s Codex starten%s\n' "$B" "$N"
        printf '  [02] 🟢 Mit lokalem Modell (kostenlos, privat, Datenschutz)\n'
        printf '\n%s Claude Code starten%s\n' "$B" "$N"
        printf '  [03] 🟢 Mit lokalem Modell (kostenlos, privat, Datenschutz)\n'
        if [[ "$zeige_cloud" == "1" ]]; then
            printf '  [04] 🔴 Mit Claude-Abo (Cloud, Abo erforderlich)\n'
            printf '  [05] 🔴 Mit Anthropic API-Key (Cloud, nutzungsabhängige Abrechnung)\n'
            printf '  %sC  #  Cloud-Optionen ausblenden%s\n' "$DIM" "$N"
        else
            printf '  %sC  #  Cloud-Optionen anzeigen (GEHEIM)%s\n' "$DIM" "$N"
        fi
        printf '\n%s Ollama%s\n' "$B" "$N"
        printf '  [06] ▶️  Starten\n'
        printf '  [07] 📥 Modell in den Speicher laden\n'
        printf '  [08] ⏹️. Beenden (gibt allen Speicher frei)\n'
        printf '\n%s Speicher%s\n' "$B" "$N"
        printf '  [09] 📊 Status: was liegt im Arbeitsspeicher\n'
        printf '  [10] 🗑️  Einzelnes Modell aus dem Speicher werfen\n'
        printf '  [11] 🧹 Alle Modelle aus dem Speicher werfen\n'
        printf '  [12] 💿 Modelle auf der Festplatte ansehen\n'
        printf '\n  q  ❌ Beenden\n\n'

        local wahl
        read -r wahl < /dev/tty || exit 0

        case "$wahl" in
            1)  code_opencode ;;
            2)  code_codex ;;
            3)  code_lokal ;;
            4)  code_abo ;;
            5)  code_api ;;
            6)  ollama_starten;  weiter ;;
            7)  local m; m="$(modell_erfragen)" && modell_laden "$m"; weiter ;;
            8)  ollama_beenden;  weiter ;;
            9)  speicher_status; weiter ;;
            10) if hat_mem; then "$MEM" menu; else speicher_frei; fi; weiter ;;
            11) speicher_frei;   weiter ;;
            12) modelle_zeigen;  weiter ;;
            C)  if [[ "$zeige_cloud" == "1" ]]; then zeige_cloud=0; else zeige_cloud=1; fi ;;
            q|Q) exit 0 ;;
            *)  ;;
        esac
    done
}

weiter() { printf '\n'; read -r -p "Weiter mit Enter ..." _ < /dev/tty || true; }

# ----------------------------------------------------------------- Hilfe

hilfe() {
    cat <<EOF
${B}ki${N} – zentrales Startscript für die lokale KI-Umgebung

${B}OpenCode starten${N}
  ki opencode [1|2|3|modell]  OpenCode mit lokalem Ollama-Modell

${B}Codex starten${N}
  ki codex [1|2|3|modell]     Codex (OpenAI) mit lokalem Ollama-Modell

${B}Claude Code starten$N
  ki code [1|2|3|modell]   Claude Code mit lokalem Ollama-Modell
  ki claude                Claude Code mit deinem Claude-Abo
  ki api                   Claude Code mit Anthropic API-Key

${B}Ollama steuern${N}
  ki start                 Ollama starten
  ki stop                  Ollama beenden, gibt allen Speicher frei
  ki load [1|2|3|modell]   Modell in den Arbeitsspeicher laden
  ki loadall               Alle drei Modelle laden (fragt vorher nach)

${B}Speicher verwalten${N}
  ki status                Was läuft, was liegt im RAM, wie voll ist er
  ki ps                    Nur die geladenen Modelle
  ki free [1|2|3|modell]   Modell aus dem Arbeitsspeicher werfen
  ki freeall               Alle Modelle aus dem Arbeitsspeicher werfen
  ki watch                 Laufende Speicherüberwachung
  ki models                Modelle auf der Festplatte ansehen

${B}Sonstiges${N}
  ki                       Interaktives Hauptmenü
  ki help                  Diese Hilfe

${B}Modelle${N}
$(modell_menue)

Kein Befehl löscht ein Modell von der Festplatte. "free" und "freeall"
geben nur den Arbeitsspeicher frei – beim nächsten Start wird das Modell
einfach wieder von der Platte geladen.
EOF
}

# ----------------------------------------------------------------- Start

case "${1:-menu}" in
    menu|"")        hauptmenue ;;

    code|lokal|local)  shift || true; code_lokal "${1:-}" ;;
    claude|abo)        shift || true; code_abo "$@" ;;
    api|cloud)         shift || true; code_api "$@" ;;
    opencode|oc)       shift || true; code_opencode "${1:-}" ;;
    codex)             shift || true; code_codex "${1:-}" ;;

    start|up)       ollama_starten ;;
    stop|down)      ollama_beenden ;;
    load)           shift || true
                    if [[ -n "${1:-}" ]]; then modell_laden "$1"
                    else m="$(modell_erfragen)" && modell_laden "$m"; fi ;;
    loadall)        alle_laden ;;

    status)         speicher_status ;;
    ps)             if hat_mem; then "$MEM" ps; else ollama ps; fi ;;
    free|unload)    shift || true; speicher_frei "${1:-}" ;;
    freeall)        speicher_frei ;;
    watch)          shift || true
                    if hat_mem; then "$MEM" watch "${1:-3}"; else fehler "ollama-mem.sh fehlt."; fi ;;
    models|list)    modelle_zeigen ;;

    help|-h|--help) hilfe ;;
    *)  fehler "Unbekannter Befehl: $1"; printf '\n'; hilfe; exit 1 ;;
esac
