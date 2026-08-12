#!/usr/bin/env bash
# Richtet den Alias "ki" in der ~/.zshrc ein, damit ki.sh von überall
# aufrufbar ist.
#
# Das Script ist idempotent und rechnerunabhängig: es ermittelt seinen
# eigenen Ordner selbst und schreibt einen markierten Block in die
# ~/.zshrc. Ein bereits vorhandener Block wird ersetzt, nicht verdoppelt.
# Auf einem neuen Rechner also einfach das Repo klonen und dieses Script
# ausführen.
set -euo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KI="$HIER/ki.sh"
ZSHRC="$HOME/.zshrc"
START="# >>> KiWork ki >>>"
ENDE="# <<< KiWork ki <<<"

if [[ -t 1 ]]; then
    B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[31m'
    G=$'\033[32m'; Y=$'\033[33m'; N=$'\033[0m'
else
    B=""; DIM=""; R=""; G=""; Y=""; N=""
fi

ok()      { printf '%s✓%s %s\n' "$G" "$N" "$1"; }
warnung() { printf '%s!%s %s\n' "$Y" "$N" "$1"; }
fehler()  { printf '%s✗%s %s\n' "$R" "$N" "$1"; }

printf '%s╔════════════════════════════════════════════════════════╗%s\n' "$B" "$N"
printf '%s║   Einrichtung: Alias "ki"                              ║%s\n' "$B" "$N"
printf '%s╚════════════════════════════════════════════════════════╝%s\n' "$B" "$N"
printf '\nOrdner: %s\n' "$HIER"

# ------------------------------------------------- 1. Scripte vorhanden?

printf '\n%s1. Scripte%s\n' "$B" "$N"

if [[ ! -f "$KI" ]]; then
    fehler "ki.sh nicht gefunden in $HIER"
    exit 1
fi

chmod +x "$HIER"/*.sh 2>/dev/null || true
ok "ki.sh gefunden und ausführbar"

if [[ -x "$HIER/ollama-mem.sh" ]]; then
    ok "ollama-mem.sh gefunden (Speicherverwaltung aktiv)"
else
    warnung "ollama-mem.sh fehlt – ki nutzt dann nur die einfache Anzeige"
fi

# ---------------------------------------------------- 2. Voraussetzungen

printf '\n%s2. Voraussetzungen%s\n' "$B" "$N"

fehlt=0

if command -v ollama &>/dev/null; then
    ok "ollama  $(ollama --version 2>/dev/null | head -1)"
else
    fehler "ollama fehlt  →  https://ollama.com/download"
    fehlt=1
fi

if command -v claude &>/dev/null; then
    ok "claude  $(claude --version 2>/dev/null | head -1)"
else
    fehler "claude fehlt  →  npm install -g @anthropic-ai/claude-code"
    fehlt=1
fi

if command -v jq &>/dev/null; then
    ok "jq      $(jq --version 2>/dev/null)"
else
    fehler "jq fehlt  →  brew install jq"
    fehlt=1
fi

if command -v python3 &>/dev/null; then
    ok "python3 $(python3 --version 2>&1 | awk '{print $2}')"
else
    warnung "python3 fehlt – Restlaufzeiten werden dann nicht angezeigt"
fi

# ------------------------------------------------------ 3. Alias in zshrc

printf '\n%s3. Alias in %s%s\n' "$B" "$ZSHRC" "$N"

touch "$ZSHRC"
cp "$ZSHRC" "$ZSHRC.backup-ki"

if grep -qF "$START" "$ZSHRC"; then
    # Alten Block entfernen, damit ein geänderter Pfad übernommen wird.
    awk -v s="$START" -v e="$ENDE" '
        $0 == s { drin = 1; next }
        $0 == e { drin = 0; next }
        !drin   { print }
    ' "$ZSHRC" > "$ZSHRC.tmp-ki" && mv "$ZSHRC.tmp-ki" "$ZSHRC"
    printf '   alter Block entfernt\n'
fi

# Kollidiert ein fremder ki-Alias ausserhalb unseres Blocks?
if grep -qE "^[[:space:]]*alias[[:space:]]+ki=" "$ZSHRC"; then
    warnung "Es gibt bereits einen anderen 'ki'-Alias in der ~/.zshrc:"
    grep -nE "^[[:space:]]*alias[[:space:]]+ki=" "$ZSHRC" | sed 's/^/     /'
    warnung "Unserer wird danach eingetragen und gewinnt."
fi

{
    printf '\n%s\n' "$START"
    printf '# Zentrales Startscript für die lokale KI-Umgebung.\n'
    printf "alias ki='%s'\n" "$KI"
    printf '%s\n' "$ENDE"
} >> "$ZSHRC"

ok "alias ki='$KI'"
printf '   %sSicherung der alten Datei: %s.backup-ki%s\n' "$DIM" "$ZSHRC" "$N"

# -------------------------------------------------------- 4. Modelle

printf '\n%s4. Modelle%s\n' "$B" "$N"

MODELLE=(qwen3-coder:30b nemotron-3.5-lightning gemma4:latest)

if command -v ollama &>/dev/null && ollama list &>/dev/null; then
    vorhanden=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')
    fehlende=()

    for m in "${MODELLE[@]}"; do
        if grep -qx "$m" <<<"$vorhanden" || grep -qx "${m%:latest}:latest" <<<"$vorhanden"; then
            ok "$m"
        else
            fehler "$m fehlt"
            fehlende+=("$m")
        fi
    done

    if (( ${#fehlende[@]} > 0 )); then
        printf '\n   Fehlende Modelle jetzt laden? Das lädt mehrere GB herunter.\n'
        read -r -p "   Herunterladen? (j/N): " antwort
        if [[ "$antwort" =~ ^[jJyY]$ ]]; then
            for m in "${fehlende[@]}"; do
                printf '\n   Lade %s ...\n' "$m"
                ollama pull "$m" || fehler "$m konnte nicht geladen werden"
            done
        else
            printf '   Übersprungen. Später mit:  ollama pull <modell>\n'
        fi
    fi
else
    warnung "Ollama antwortet nicht – Modelle nicht geprüft"
fi

# ------------------------------------------------------------ 5. Fertig

printf '\n%s╔════════════════════════════════════════════════════════╗%s\n' "$B" "$N"
printf '%s║   Fertig                                               ║%s\n' "$B" "$N"
printf '%s╚════════════════════════════════════════════════════════╝%s\n' "$B" "$N"

if (( fehlt > 0 )); then
    printf '\n%sEs fehlen noch Programme – siehe oben.%s\n' "$Y" "$N"
fi

cat <<EOF

Einmalig noch ausführen, damit der Alias aktiv wird:

    source ~/.zshrc

Danach überall im Terminal:

    ki              Hauptmenü
    ki code 1       Claude Code mit Qwen3-Coder 30B
    ki status       Was liegt im Arbeitsspeicher
    ki freeall      Arbeitsspeicher freigeben
    ki help         Alle Befehle

Auf einem neuen Rechner: Repo klonen und ./install-ki.sh ausführen.
EOF
