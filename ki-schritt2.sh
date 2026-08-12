#!/usr/bin/env bash

#------------------------------------------------------------------------------
# ki – zentrales Startscript für die lokale KI-Umgebung.
#
# Dieses Script braucht KEIN anderes Script. Es prüft beim Gebrauch jeder
# Funktion selbst, ob die nötigen Programme auf der Festplatte sind
# (Homebrew, Node/npm, jq, Ollama, Claude Code, OpenCode, Codex) und die
# nötigen Modelle heruntergeladen sind – und installiert bzw. lädt sie bei
# Bedarf automatisch nach (mit Rückfrage, ausser bei "-y").
#
# Deckt alles ab: Komponenten installieren, Ollama starten/beenden, Modelle
# laden, Claude Code / OpenCode / Codex gegen ein lokales Modell oder
# Claude Code gegen die Cloud starten, sehen was im Arbeitsspeicher liegt
# und es dort wieder herauswerfen.
#
# WICHTIG: "ki free" und "ki freeall" geben ausschliesslich RAM frei und
#          löschen nie etwas von der Festplatte. Nur "ki uninstall <modell>"
#          löscht ein Modell endgültig von der Festplatte (mit Rückfrage).
#
# Alias einrichten (optional, nur Komfort):  ./install-ki.sh
# Vollständige Einrichtung (Pflicht-Komponenten + Modelle):  ./ki.sh setup
#------------------------------------------------------------------------------

set -uo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
[[ "$HOST" != http* ]] && HOST="http://$HOST"

OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"

# Kontextgrösse für Claude Code / Codex gegen lokale Modelle.
KI_CONTEXT="${KI_CONTEXT:-65536}"

# ------------------------------------------------------- Modell-Registry
# Format:  id|Anzeigename|Empfehlung
MODELLE=(
    "qwen3-coder:30b|Qwen3-Coder 30B|Beste Wahl für Swift, SwiftUI, Xcode, Refactoring und große Projekte."
    "nemotron-3.5-lightning|Nemotron 3.5 Lightning|Sehr gut für Agenten, MCP, Code Reviews und Tool Calling."
    "gemma4:latest|Gemma 4|Schnell für Dokumentation, Erklärungen und allgemeine Aufgaben."
)

# Eigene Modelle, ohne dieses Script zu bearbeiten: eine Zeile pro Modell im
# selben "id|Anzeigename|Empfehlung"-Format wie oben, "#"-Kommentare und
# Leerzeilen werden übersprungen. Verwaltung über "ki registry add/rm/list".
REGISTRY_DATEI="$HOME/.ki/modelle.conf"
if [[ -f "$REGISTRY_DATEI" ]]; then
    while IFS= read -r _zeile; do
        [[ -z "$_zeile" || "$_zeile" == \#* ]] && continue
        MODELLE+=("$_zeile")
    done < "$REGISTRY_DATEI"
fi

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

# Eine Zeile im Kasten des Hauptmenüs, Inhalt auf 70 Zeichen aufgefüllt,
# damit der Rahmen (71 "═") unabhängig vom Terminal exakt ausgerichtet bleibt.
# Polsterung wird über ${#text} (Zeichenanzahl) berechnet statt über
# printf "%-70s" - das polstert auf diesem System nach Bytes, nicht nach
# Zeichen, wodurch jeder Umlaut (ü, ä, ö - 2 Bytes, aber 1 Zeichen) den
# rechten Rand um eine Spalte verschieben würde.
kzeile() {
    local text="$1" pad=$(( 70 - ${#1} ))
    (( pad < 0 )) && pad=0
    printf '%s║ %s%*s║%s\n' "$B" "$text" "$pad" "" "$N"
}

fehler() { printf '%sFehler: %s%s\n' "$R" "$1" "$N" >&2; }
ok()     { printf '%s✓ %s%s\n' "$G" "$1" "$N"; }
warnung(){ printf '%s! %s%s\n' "$Y" "$1" "$N"; }

server_laeuft() { curl -fsS --max-time 3 "$HOST" &>/dev/null; }

# Feld n aus einem Registry-Eintrag holen.
feld() { printf '%s' "$1" | cut -d'|' -f"$2"; }

# --------------------------------------------------- Auto-Ja (-y/--yes)

AUTO_YES=0
if [[ "${KI_AUTO_YES:-0}" == "1" ]]; then AUTO_YES=1; fi
_ARGS=()
for _a in "$@"; do
    case "$_a" in
        -y|--yes) AUTO_YES=1 ;;
        *)        _ARGS+=("$_a") ;;
    esac
done
set -- "${_ARGS[@]:-}"
[[ "${1:-}" == "" && $# -eq 1 ]] && set --

# Fragt nach, ausser AUTO_YES ist gesetzt. Ohne Terminal (kein /dev/tty)
# wird ebenfalls automatisch ja angenommen, sonst würde das Script hängen.
frage_ja() {
    (( AUTO_YES )) && return 0
    [[ -r /dev/tty ]] || return 0
    local antwort
    read -r -p "$1 (J/n): " antwort < /dev/tty || return 1
    [[ -z "$antwort" || "$antwort" =~ ^[jJyY]$ ]]
}

# ------------------------------------------------ Komponenten sicherstellen
#
# Jede brauche_* Funktion: schon da? -> fertig. Sonst fragen, installieren,
# prüfen ob es geklappt hat. Damit kann jede Funktion, die z.B. "claude"
# braucht, einfach "brauche_claude" aufrufen, ohne sich um Installation
# irgendwo anders kümmern zu müssen.

brauche_brew() {
    command -v brew &>/dev/null && return 0

    fehler "Homebrew ist nicht installiert (wird für Ollama, Node, jq gebraucht)."
    frage_ja "Homebrew jetzt installieren" || return 1

    printf 'Installiere Homebrew ...\n'
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || { fehler "Homebrew-Installation fehlgeschlagen."; return 1; }

    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    hash -r

    command -v brew &>/dev/null || { fehler "brew nach der Installation nicht gefunden."; return 1; }
    ok "Homebrew installiert."
}

brauche_node() {
    command -v npm &>/dev/null && return 0

    fehler "Node.js/npm ist nicht installiert (wird für Claude Code und Codex gebraucht)."
    frage_ja "Node.js jetzt installieren" || return 1

    brauche_brew || return 1
    printf 'Installiere Node.js ...\n'
    brew install node || { fehler "Node-Installation fehlgeschlagen."; return 1; }
    hash -r

    command -v npm &>/dev/null || { fehler "npm nach der Installation nicht gefunden. Neues Terminal öffnen."; return 1; }
    ok "Node.js installiert."
}

brauche_jq() {
    command -v jq &>/dev/null && return 0

    fehler "jq ist nicht installiert (wird für die Modell- und Konfig-Verwaltung gebraucht)."
    frage_ja "jq jetzt installieren" || return 1

    brauche_brew || return 1
    printf 'Installiere jq ...\n'
    brew install jq || { fehler "jq-Installation fehlgeschlagen."; return 1; }
    hash -r

    command -v jq &>/dev/null || { fehler "jq nach der Installation nicht gefunden."; return 1; }
    ok "jq installiert."
}

brauche_ollama() {
    if [[ -d "/Applications/Ollama.app" ]] || command -v ollama &>/dev/null; then
        return 0
    fi

    fehler "Ollama ist nicht installiert."
    frage_ja "Ollama jetzt installieren" || return 1

    brauche_brew || return 1
    printf 'Installiere Ollama (offizielle App, nicht die Formula) ...\n'
    # WICHTIG: cask "ollama-app" (offizielle App mit vollem Runner), NICHT
    # die Formula "brew install ollama" -- die kann keine GGUF-Modelle wie
    # gemma4 starten (llama-server fehlt).
    brew install --cask ollama-app || { fehler "Ollama-Installation fehlgeschlagen."; return 1; }

    printf 'Starte Ollama einmal, damit die Kommandozeile eingerichtet wird ...\n'
    open -ga "/Applications/Ollama.app" &>/dev/null || true
    local i
    for i in $(seq 1 20); do
        command -v ollama &>/dev/null && break
        hash -r
        sleep 1
    done

    command -v ollama &>/dev/null || { fehler "ollama nach der Installation nicht gefunden. Neues Terminal öffnen."; return 1; }
    ok "Ollama installiert."
}

brauche_claude() {
    command -v claude &>/dev/null && return 0

    fehler "Claude Code ist nicht installiert."
    frage_ja "Claude Code jetzt installieren" || return 1

    brauche_node || return 1
    printf 'Installiere Claude Code ...\n'
    npm install -g @anthropic-ai/claude-code || { fehler "Claude-Code-Installation fehlgeschlagen."; return 1; }
    hash -r

    command -v claude &>/dev/null || { fehler "claude nach der Installation nicht gefunden. Neues Terminal öffnen."; return 1; }
    ok "Claude Code installiert."
}

brauche_opencode() {
    command -v opencode &>/dev/null && return 0

    fehler "OpenCode ist nicht installiert."
    frage_ja "OpenCode jetzt installieren" || return 1

    printf 'Installiere OpenCode ...\n'
    curl -fsSL https://opencode.ai/install | bash || { fehler "OpenCode-Installation fehlgeschlagen."; return 1; }
    export PATH="$HOME/.local/bin:$PATH"
    hash -r

    command -v opencode &>/dev/null || { fehler "opencode nach der Installation nicht gefunden. Neues Terminal öffnen oder 'source ~/.zshrc'."; return 1; }
    ok "OpenCode installiert."
}

brauche_codex() {
    command -v codex &>/dev/null && return 0

    fehler "Codex ist nicht installiert."
    frage_ja "Codex jetzt installieren" || return 1

    brauche_node || return 1
    printf 'Installiere Codex ...\n'
    npm install -g @openai/codex || { fehler "Codex-Installation fehlgeschlagen."; return 1; }
    hash -r

    command -v codex &>/dev/null || { fehler "codex nach der Installation nicht gefunden. Neues Terminal öffnen."; return 1; }
    ok "Codex installiert."
}

# Ist ein Modell schon auf der Festplatte? "ollama list" hängt oft ":latest"
# an, auch wenn die Registry das Modell ohne Tag führt (z.B.
# "nemotron-3.5-lightning" vs. "nemotron-3.5-lightning:latest") - deshalb
# wird gegen beide Schreibweisen geprüft, statt nur exakt zu vergleichen.
modell_vorhanden() {
    local modell="$1" vorhanden
    vorhanden="$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')"
    grep -qx "$modell" <<<"$vorhanden" && return 0
    grep -qx "${modell%:latest}:latest" <<<"$vorhanden" && return 0
    return 1
}

# Versucht die Downloadgrösse eines Ollama-Modells zu ermitteln (Summe der
# Layer-Grössen aus dem Registry-Manifest). Gibt bei jedem Fehlschlag nichts
# aus - der Aufrufer behandelt das dann einfach als "Grösse unbekannt".
modell_groesse_bytes() {
    local modell="$1" name="$modell" tag="latest"
    [[ "$modell" == *:* ]] && { name="${modell%%:*}"; tag="${modell##*:}"; }
    curl -fsS --max-time 5 "https://registry.ollama.ai/v2/library/${name}/manifests/${tag}" 2>/dev/null \
        | jq -r '[.layers[]?.size] | add // empty' 2>/dev/null
}

# Prüft, ob dort, wo Ollama seine Modelle ablegt, genug freier Speicherplatz
# für den Download ist, und fragt bei knappem Platz vorher nach.
speicherplatz_pruefen() {
    local modell="$1" ordner="$HOME/.ollama/models"
    [[ -d "$ordner" ]] || ordner="$HOME"

    local frei_kb frei_bytes
    frei_kb="$(df -Pk "$ordner" 2>/dev/null | awk 'NR==2 {print $4}')"
    [[ -z "$frei_kb" ]] && return 0
    frei_bytes=$(( frei_kb * 1024 ))

    local benoetigt
    benoetigt="$(modell_groesse_bytes "$modell")"

    if [[ -n "$benoetigt" ]] && (( benoetigt > 0 )); then
        if (( frei_bytes < benoetigt + benoetigt / 10 )); then
            warnung "Nur $(gb "$frei_bytes") frei, '$modell' braucht aber rund $(gb "$benoetigt")."
            frage_ja "Trotzdem versuchen" || return 1
        fi
    else
        local mindest_bytes=$(( 10 * 1024 * 1024 * 1024 ))
        if (( frei_bytes < mindest_bytes )); then
            warnung "Nur $(gb "$frei_bytes") frei auf der Platte - für ein mehrere-GB-Modell könnte das knapp werden."
            frage_ja "Trotzdem versuchen" || return 1
        fi
    fi
    return 0
}

# Lädt ein Registry- oder beliebiges Modell herunter, falls es noch nicht
# auf der Festplatte liegt. Setzt einen laufenden Ollama-Server voraus.
modell_sicherstellen() {
    local modell="$1"

    modell_vorhanden "$modell" && return 0

    warnung "Modell '$modell' ist noch nicht heruntergeladen."
    frage_ja "$modell jetzt herunterladen (mehrere GB)" || return 1

    speicherplatz_pruefen "$modell" || return 1

    printf 'Lade %s%s%s herunter ...\n' "$C" "$modell" "$N"
    ollama pull "$modell" || { fehler "Download von $modell fehlgeschlagen."; return 1; }
    ok "$modell heruntergeladen."
}

# Löscht ein Modell endgültig von der Festplatte (im Gegensatz zu
# "free"/"freeall", die nur den Arbeitsspeicher freigeben).
modell_loeschen() {
    local modell="$1"
    modell_vorhanden "$modell" || { fehler "'$modell' ist nicht auf der Festplatte."; return 1; }
    warnung "'$modell' wird endgültig von der Festplatte gelöscht."
    frage_ja "'$modell' jetzt löschen" || return 1
    ollama rm "$modell" || { fehler "Löschen von $modell fehlgeschlagen."; return 1; }
    ok "'$modell' von der Festplatte gelöscht."
}

# Prüft ein per Homebrew installiertes Formula/Cask auf ein Update und
# aktualisiert es nach Rückfrage. Erhöht update_anzahl (dynamischer Scope
# aus setup_alles) bei einem tatsächlich durchgeführten Update.
aktualisiere_brew() {
    local formel="$1" ist_cask="$2" anzeige="$3"
    command -v brew &>/dev/null || return 0

    local flags=()
    if (( ist_cask )); then
        flags=(--cask)
        brew list --cask "$formel" &>/dev/null || return 0
    else
        brew list --formula "$formel" &>/dev/null || return 0
    fi

    local veraltet
    veraltet="$(brew outdated --quiet "${flags[@]}" "$formel" 2>/dev/null)"
    [[ -z "$veraltet" ]] && return 0

    warnung "$anzeige: Update verfügbar."
    frage_ja "$anzeige jetzt aktualisieren" || return 0
    printf 'Aktualisiere %s ...\n' "$anzeige"
    brew upgrade "${flags[@]}" "$formel" || { fehler "$anzeige-Update fehlgeschlagen."; return 1; }
    hash -r
    ok "$anzeige aktualisiert."
    (( update_anzahl++ ))
}

# Prüft ein global installiertes npm-Paket auf ein Update und aktualisiert
# es nach Rückfrage. Erhöht update_anzahl wie aktualisiere_brew.
aktualisiere_npm() {
    local paket="$1" anzeige="$2"
    command -v npm &>/dev/null || return 0

    local installiert
    installiert="$(npm list -g "$paket" --depth=0 2>/dev/null | sed -n "s/.*${paket}@//p")"
    [[ -z "$installiert" ]] && return 0

    local aktuell
    aktuell="$(npm view "$paket" version 2>/dev/null)"
    [[ -z "$aktuell" || "$aktuell" == "$installiert" ]] && return 0

    warnung "$anzeige: Update verfügbar ($installiert → $aktuell)."
    frage_ja "$anzeige jetzt aktualisieren" || return 0
    printf 'Aktualisiere %s ...\n' "$anzeige"
    npm install -g "${paket}@latest" || { fehler "$anzeige-Update fehlgeschlagen."; return 1; }
    hash -r
    ok "$anzeige aktualisiert."
    (( update_anzahl++ ))
}

# Prüft/installiert alles auf einmal: Grundprogramme, alle drei
# Kommandozeilen-Tools und alle Registry-Modelle. Prüft anschliessend auch
# auf Updates für alles, was per Homebrew oder npm installiert wurde.
setup_alles() {
    titel "Setup – Grundprogramme"
    local fehlend=() update_anzahl=0

    brauche_brew     || fehlend+=("Homebrew")
    brauche_node     || fehlend+=("Node.js")
    brauche_jq       || fehlend+=("jq")
    brauche_ollama   || fehlend+=("Ollama")

    if command -v brew &>/dev/null; then
        printf 'Prüfe auf Updates ...\n'
        brew update &>/dev/null
        aktualisiere_brew node 0 "Node.js"
        aktualisiere_brew jq 0 "jq"
        aktualisiere_brew ollama-app 1 "Ollama"
    fi

    titel "Setup – Ollama-Server"
    ollama_starten   || fehlend+=("Ollama-Server")

    titel "Setup – KI-Coding-Assistenten"
    brauche_claude   || fehlend+=("Claude Code")
    brauche_opencode || fehlend+=("OpenCode")
    brauche_codex    || fehlend+=("Codex")

    aktualisiere_npm "@anthropic-ai/claude-code" "Claude Code"
    aktualisiere_npm "@openai/codex" "Codex"

    titel "Setup – Modelle"
    local eintrag id
    for eintrag in "${MODELLE[@]}"; do
        id="$(feld "$eintrag" 1)"
        modell_sicherstellen "$id" || fehlend+=("$id")
    done

    titel "Ergebnis"
    if (( ${#fehlend[@]} == 0 )); then
        if (( update_anzahl > 0 )); then
            ok "Alles installiert und aktualisiert."
        else
            ok "Alles installiert und aktuell – keine Updates nötig."
        fi
    else
        fehler "Noch nicht bereit: ${fehlend[*]}"
        printf '"%s setup" erneut ausführen, sobald das behoben ist.\n' "$0"
        return 1
    fi
}

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
    if modell_vorhanden "$eingabe"; then
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
    read -r -p "Auswahl (1-${#MODELLE[@]}): " wahl < /dev/tty
    modell_aufloesen "$wahl"
}

# --------------------------------------------- Eigene Modelle (Registry)

registry_hinzufuegen() {
    local id="$1" name="${2:-$1}" empfehlung="${3:-}"
    [[ -z "$id" ]] && { fehler 'Modell-ID fehlt. Beispiel: ki registry add mein-modell:8b "Mein Modell" "Wofür es gut ist."'; return 1; }
    if grep -qF "$id|" "$REGISTRY_DATEI" 2>/dev/null; then
        fehler "'$id' steht schon in $REGISTRY_DATEI."
        return 1
    fi
    mkdir -p "$(dirname "$REGISTRY_DATEI")"
    printf '%s|%s|%s\n' "$id" "$name" "$empfehlung" >> "$REGISTRY_DATEI"
    ok "'$id' zur Registry hinzugefügt. Erscheint ab dem nächsten Start von ki im Modell-Menü."
}

registry_entfernen() {
    local id="$1"
    [[ -z "$id" ]] && { fehler "Modell-ID fehlt."; return 1; }
    [[ -f "$REGISTRY_DATEI" ]] || { fehler "Es gibt noch keine eigenen Modelle."; return 1; }
    if ! grep -qF "$id|" "$REGISTRY_DATEI"; then
        fehler "'$id' steht nicht in $REGISTRY_DATEI."
        return 1
    fi
    # "grep -v" gibt Exit-Code 1 zurück, wenn keine Zeile übrig bleibt (z.B.
    # letzter Eintrag gelöscht) - das ist hier kein Fehler, deshalb "|| true".
    grep -vF "$id|" "$REGISTRY_DATEI" > "$REGISTRY_DATEI.tmp" || true
    mv "$REGISTRY_DATEI.tmp" "$REGISTRY_DATEI"
    ok "'$id' aus der Registry entfernt (auf der Festplatte bleibt es, dafür 'ki uninstall $id')."
}

registry_auflisten() {
    if [[ ! -s "$REGISTRY_DATEI" ]]; then
        printf 'Keine eigenen Modelle eingetragen (%s).\n' "$REGISTRY_DATEI"
        return 0
    fi
    printf 'Eigene Modelle in %s:\n' "$REGISTRY_DATEI"
    local eintrag
    while IFS= read -r eintrag; do
        [[ -z "$eintrag" || "$eintrag" == \#* ]] && continue
        printf '  %-30s %s\n' "$(feld "$eintrag" 1)" "$(feld "$eintrag" 2)"
    done < "$REGISTRY_DATEI"
}

# ------------------------------------------------------------- Ollama

ollama_starten() {
    brauche_ollama || return 1

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
    printf 'Gebe erst alle Modelle aus dem Speicher frei ...\n'
    speicher_frei &>/dev/null || true

    printf 'Beende Ollama ...\n'
    pkill -f 'llama-server' &>/dev/null || true
    pkill -x Ollama &>/dev/null || true
    pkill -x ollama &>/dev/null || true
    sleep 1

    if pgrep -x Ollama &>/dev/null || pgrep -x ollama &>/dev/null; then
        warnung "Es laufen noch Ollama-Prozesse."
    else
        ok "Ollama beendet, Speicher freigegeben."
    fi
}

# Lädt ein Modell in den Arbeitsspeicher, ohne einen Chat zu öffnen.
modell_laden() {
    local modell
    modell="$(modell_aufloesen "$1")" || return 1

    ollama_starten || return 1
    brauche_jq || return 1
    modell_sicherstellen "$modell" || return 1

    printf 'Lade %s%s%s in den Arbeitsspeicher ...\n' "$C" "$modell" "$N"
    if curl -fsS --max-time 600 "$HOST/api/generate" \
            -d "$(jq -nc --arg m "$modell" '{model:$m, prompt:"", keep_alive:"30m"}')" &>/dev/null; then
        ok "$modell ist geladen."
        speicher_geladen
    else
        fehler "$modell konnte nicht geladen werden."
        return 1
    fi
}

# Lädt alle drei Modelle nacheinander. Achtung: braucht sehr viel RAM.
alle_laden() {
    local eintrag id
    for eintrag in "${MODELLE[@]}"; do
        id="$(feld "$eintrag" 1)"
        local groesse
        groesse=$(ollama list 2>/dev/null | awk -v m="$id" -v m2="${id%:latest}:latest" '$1 == m || $1 == m2 { print $3 }')
        printf '  %-26s %s\n' "$id" "${groesse:-noch nicht heruntergeladen}"
    done

    printf '\n%sAlle Modelle zusammen sprengen auf den meisten Macs den RAM.%s\n' "$Y" "$N"
    printf '%sOllama lagert dann auf die SSD aus und wird sehr langsam.%s\n\n' "$Y" "$N"

    frage_ja "Trotzdem alle laden" || { printf 'Abgebrochen.\n'; return 0; }

    for eintrag in "${MODELLE[@]}"; do
        modell_laden "$(feld "$eintrag" 1)"
    done
}

# ------------------------------------------------------------ OpenCode

# Trägt alle Registry-Modelle in die OpenCode-Konfiguration ein, damit
# sie dort per "-m ollama/<modell>" ansprechbar sind.
opencode_konfig_sicherstellen() {
    brauche_jq || return 1

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

    ollama_starten || return 1
    modell_sicherstellen "$modell" || return 1
    brauche_opencode || return 1
    opencode_konfig_sicherstellen || return 1

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
    modell_sicherstellen "$modell" || return 1
    brauche_codex || return 1

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
    modell_sicherstellen "$modell" || return 1
    brauche_claude || return 1

    titel "Claude Code – lokal"
    printf 'Modell:    %s%s%s\n' "$C" "$modell" "$N"
    printf 'Kontext:   %s\n' "$KI_CONTEXT"
    printf 'Kosten:    keine, alles bleibt auf diesem Mac\n\n'

    export OLLAMA_CONTEXT_LENGTH="$KI_CONTEXT"
    exec ollama launch claude --model "$modell"
}

# Claude Code über das Claude-Abo (OAuth-Login im Schlüsselbund).
code_abo() {
    brauche_claude || return 1
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
    brauche_claude || return 1
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
#
# Volle Speicherkontrolle direkt eingebaut (kein ollama-mem.sh nötig).
# Löscht NIE ein Modell von der Festplatte, gibt ausschliesslich RAM frei.

gb() { awk -v b="$1" 'BEGIN { printf "%.1f GB", b/1073741824 }'; }

api_ps() { curl -fsS --max-time 5 "$HOST/api/ps" 2>/dev/null; }

geladene_modelle() {
    brauche_jq &>/dev/null || return 0
    api_ps | jq -r '.models[]?.name' 2>/dev/null
}

speicher_prozesse() {
    titel "Prozesse"

    local app helper server runner
    app=$(pgrep -x Ollama || true)
    helper=$(pgrep -f 'Ollama.app/Contents/Resources/ollama' || true)
    server=$(pgrep -x ollama || true)
    runner=$(pgrep -f 'llama-server|ollama[- ]runner' || true)

    if [[ -z "$app$helper$server$runner" ]]; then
        printf '%sOllama läuft nicht.%s\n' "$R" "$N"
        return 1
    fi

    printf '%-8s %10s %7s  %s\n' "PID" "RSS" "CPU%" "PROZESS"
    ps -Ao pid,rss,pcpu,comm | awk '
        NR > 1 && tolower($0) ~ /ollama|llama-server/ {
            summe += $2
            pfad = $4; for (i = 5; i <= NF; i++) pfad = pfad " " $i
            printf "%-8s %7.2f GB %7s  %s\n", $1, $2/1048576, $3, pfad
        }
        END { if (summe) printf "%-8s %7.2f GB %7s  %s\n", "gesamt", summe/1048576, "", "" }
    '

    if server_laeuft; then
        printf '\nAPI:    %s%s erreichbar%s\n' "$G" "$HOST" "$N"
    else
        printf '\nAPI:    %s%s NICHT erreichbar%s\n' "$Y" "$HOST" "$N"
    fi
    return 0
}

speicher_geladen() {
    titel "Im Speicher geladene Modelle"

    if ! server_laeuft; then
        printf '%sServer nicht erreichbar – nichts geladen.%s\n' "$DIM" "$N"
        return
    fi
    brauche_jq || { fehler "jq wird gebraucht, um das anzuzeigen."; return 1; }

    local json anzahl
    json=$(api_ps)
    anzahl=$(jq -r '.models | length' <<<"$json" 2>/dev/null || echo 0)

    if [[ "$anzahl" == "0" || -z "$anzahl" ]]; then
        printf '%sKeine Modelle im Speicher – RAM ist frei.%s\n' "$G" "$N"
        return
    fi

    printf '%-34s %10s %10s %8s %s\n' "MODELL" "GESAMT" "VRAM" "CTX" "BIS"
    jq -r '.models[] | [
             .name,
             (.size // 0),
             (.size_vram // 0),
             (.context_length // 0),
             (.expires_at // "")
           ] | @tsv' <<<"$json" |
    while IFS=$'\t' read -r name size vram ctx exp; do
        local ort rest
        if [[ "$vram" == "$size" && "$size" != "0" ]]; then ort="100% GPU"
        elif [[ "$vram" == "0" ]];                    then ort="100% CPU"
        else                                                ort="CPU+GPU"; fi

        rest=$(python3 - "$exp" <<'PY' 2>/dev/null || echo "-"
import sys, datetime
try:
    t = datetime.datetime.fromisoformat(sys.argv[1])
    s = int((t - datetime.datetime.now(t.tzinfo)).total_seconds())
    print("abgelaufen" if s <= 0 else (f"{s}s" if s < 90 else f"{s//60}min"))
except Exception:
    print("-")
PY
)
        printf '%-34s %10s %10s %8s %s %s(%s)%s\n' \
            "$name" "$(gb "$size")" "$(gb "$vram")" "$ctx" "$rest" "$DIM" "$ort" "$N"
    done

    local summe
    summe=$(jq -r '[.models[].size] | add' <<<"$json")
    printf '\n%sBelegt durch Modelle: %s%s\n' "$B" "$(gb "$summe")" "$N"
}

speicher_ram() {
    titel "Systemspeicher"

    local total frei_prozent seiten_frei pgsize
    total=$(sysctl -n hw.memsize)
    pgsize=$(vm_stat | awk 'NR==1 { gsub(/[^0-9]/,"",$8); print $8 }')
    seiten_frei=$(vm_stat | awk '/Pages free/ { gsub(/\./,""); print $3 }')
    frei_prozent=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/ { gsub(/%/,"",$2); print $2 }')

    printf 'Gesamt:            %s\n' "$(gb "$total")"
    printf 'Frei (echt frei):  %s\n' "$(gb $((seiten_frei * pgsize)))"

    local swap
    swap=$(sysctl -n vm.swapusage 2>/dev/null | sed 's/.*used = \([^ ]*\).*/\1/')
    printf 'Swap benutzt:      %s\n' "${swap:-?}"

    if [[ -n "${frei_prozent:-}" ]]; then
        local farbe="$G"
        (( frei_prozent < 30 )) && farbe="$Y"
        (( frei_prozent < 10 )) && farbe="$R"
        printf 'Speicherdruck:     %sfrei %s%%%s\n' "$farbe" "$frei_prozent" "$N"
    fi
}

speicher_status() {
    speicher_prozesse
    speicher_geladen
    speicher_ram
    printf '\n'
}

# Entlädt ein Modell aus dem Speicher. Die Modelldatei bleibt unangetastet.
entlade() {
    local modell="$1"
    printf 'Entlade %s%s%s aus dem Speicher ...\n' "$C" "$modell" "$N"

    if brauche_jq &>/dev/null && curl -fsS --max-time 10 "$HOST/api/generate" \
            -d "$(jq -nc --arg m "$modell" '{model:$m, keep_alive:0}')" &>/dev/null; then
        ok "$modell entladen."
    elif ollama stop "$modell" &>/dev/null; then
        ok "$modell entladen."
    else
        fehler "$modell konnte nicht entladen werden."
        return 1
    fi
}

speicher_frei() {
    if [[ -n "${1:-}" ]]; then
        local modell
        modell="$(modell_aufloesen "$1")" || return 1
        entlade "$modell"
        return
    fi

    local modelle
    modelle=$(geladene_modelle)
    if [[ -z "$modelle" ]]; then
        ok "Es ist kein Modell geladen."
        return
    fi

    while read -r m; do
        [[ -n "$m" ]] && entlade "$m"
    done <<<"$modelle"
}

speicher_watch() {
    trap 'printf "\n"; return 0' INT
    while true; do
        clear
        printf '%sOllama Speicher – Live (Strg-C beendet)%s   %s\n' \
            "$B" "$N" "$(date '+%H:%M:%S')"
        speicher_status
        sleep "${1:-3}"
    done
}

modelle_zeigen() {
    titel "Modelle auf der Festplatte"
    printf '%sWird nur mit "ki uninstall <modell>" gelöscht, sonst nie.%s\n\n' "$DIM" "$N"
    ollama list 2>/dev/null || fehler "Ollama antwortet nicht."

    titel "Eingerichtete Modelle für ki"
    modell_menue
}

# --------------------------------------------------------- Status-Check

# Kurzer, kostenloser Check (keine Netzwerkzugriffe) für Menü & Erststart.
komponenten_status() {
    local name cmd fehlend=()
    for name in ollama:claude:opencode:codex; do :; done
    command -v ollama  &>/dev/null || fehlend+=("Ollama")
    command -v claude  &>/dev/null || fehlend+=("Claude Code")
    command -v opencode &>/dev/null || fehlend+=("OpenCode")
    command -v codex   &>/dev/null || fehlend+=("Codex")
    printf '%s\n' "${fehlend[*]:-}"
}

# Kurzbeschreibung aller Komponenten & Modelle - per Befehl "h" im Menü.
info_zeigen() {
    printf '%s Vorbedingung:%s\n' "$B" "$N"
    printf '  Auf einem frisch installierten Mac fehlen die Xcode Command Line Tools (inklusive git).\n'
    printf '  Homebrew installiert sie beim allerersten "setup" automatisch mit.\n'
    printf '  Dabei erscheint einmalig ein macOS-Popup, das manuell bestätigt werden muss.\n'
    printf '  Das dauert je nach Internetverbindung ein paar Minuten, danach läuft "setup" automatisch weiter.\n'
    printf '\n%s Einrichtung:%s\n' "$B" "$N"
    printf '  "setup" bzw. Menüpunkt [00] installiert bei Bedarf Homebrew, Node.js (inklusive npm), jq und Ollama,\n'
    printf '  außerdem Claude Code, OpenCode und Codex sowie alle drei LLM-Modelle (Qwen3-Coder 30B,\n'
    printf '  Nemotron 3.5 Lightning und Gemma 4).\n'
    printf '  Bereits installierte Komponenten werden dabei zusätzlich auf verfügbare Updates geprüft.\n'
    printf '\n%s Befehle im Terminal (ki.sh <befehl>):%s\n' "$B" "$N"
    printf '  setup                    alles prüfen / installieren\n'
    printf '  code|opencode|codex [1|2|3|modell]  lokal starten\n'
    printf '  claude | api             Cloud (Abo / API-Key)\n'
    printf '  start | stop             Ollama starten / beenden\n'
    printf '  load | loadall           Modell(e) in den RAM laden\n'
    printf '  status | ps              RAM-Status anzeigen\n'
    printf '  free | freeall | watch   RAM freigeben / live-Ansicht\n'
    printf '  models                   Modelle auf der Festplatte\n'
    printf '  uninstall [1|2|3|modell] Modell von der Festplatte löschen\n'
    printf '  registry add|rm|list     Eigene Modelle verwalten\n'
    printf '  doctor                   Gesundheitscheck aller Komponenten\n'
    printf '  selfupdate               ki.sh selbst aktualisieren\n'
    printf '  help                     ausführliche Hilfe.\n'
    printf '\n%s Information:%s\n' "$B" "$N"
    printf ' 🦙 Ollama: Führt KI-Modelle vollständig lokal auf deinem Rechner aus.\n'
    printf ' 🖥️  OpenCode: Open-Source KI-Coding-Assistent, der ebenfalls mit lokalen Ollama-Modellen genutzt werden kann.\n'
    printf ' 🧭 Codex: KI-Coding-Assistent von OpenAI, der ebenfalls mit lokalen Ollama-Modellen genutzt werden kann.\n'
    printf ' 🤖 Claude Code: KI-Entwicklungsassistent von Anthropic, der auch mit lokalen Ollama-Modellen genutzt werden kann.\n'
    printf ' 🧠 Qwen3-Coder 30B: Ideal für Softwareentwicklung, Refactoring und große Codeprojekte.\n'
    printf ' ⚡ Nemotron 3.5 Lightning: Ideal für Agenten, Tool-Calling und komplexe Analyseaufgaben.\n'
    printf ' 💎 Gemma 4: Ideal für Dokumentation, Erklärungen und allgemeine Entwicklungsaufgaben.\n'
}

# ------------------------------------------------------------ Hauptmenü

hauptmenue() {
    local zeige_cloud=0
    while true; do
        clear
        printf '%s╔═══════════════════════════════════════════════════════════════════════╗%s\n' "$B" "$N"
        kzeile "Lokale KI-Umgebung (Ollama, OpenCode, Codex & Claude Code)"
        kzeile "by Christian Drapatz (8/2026)"
        printf '%s╚═══════════════════════════════════════════════════════════════════════╝%s\n' "$B" "$N"

        if server_laeuft; then
            local anzahl
            anzahl=$(curl -fsS --max-time 3 "$HOST/api/ps" 2>/dev/null | jq -r '.models | length' 2>/dev/null)
            printf '\nOllama: %släuft%s, %s Modell(e) im Speicher\n' "$G" "$N" "${anzahl:-0}"
        else
            printf '\nOllama: %sgestoppt%s\n' "$R" "$N"
        fi

        local fehlend
        fehlend="$(komponenten_status)"
        if [[ -n "$fehlend" ]]; then
            printf 'Fehlt noch: %s%s%s  →  Option [00]\n' "$Y" "$fehlend" "$N"
        fi

        printf '\n%s Einrichtung%s\n' "$B" "$N"
        printf '  [00] 🛠️  Alle Komponenten & Modelle prüfen / installieren\n'
        printf '\n%s OpenCode starten%s\n' "$B" "$N"
        printf '  [01] 🟢 Mit lokalem Modell (kostenlos, privat, Datenschutz)\n'
        printf '\n%s Codex starten%s\n' "$B" "$N"
        printf '  [02] 🟢 Mit lokalem Modell (kostenlos, privat, Datenschutz)\n'
        printf '\n%s Claude Code starten%s\n' "$B" "$N"
        printf '  [03] 🟢 Mit lokalem Modell (kostenlos, privat, Datenschutz)\n'
        if (( zeige_cloud )); then
            printf '  [04] 🔴 Mit Claude-Abo (Cloud, Abo erforderlich)\n'
            printf '  [05] 🔴 Mit Anthropic API-Key (Cloud, nutzungsabhängige Abrechnung)\n'
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
        printf '  [13] 🗑️  Modell von der Festplatte löschen\n'
        printf '\n%s Wartung%s\n' "$B" "$N"
        printf '  [14] 🩺 Gesundheitscheck (doctor)\n'
        printf '  [15] 🔄 ki.sh selbst aktualisieren\n'
        printf '\n  h  ℹ️  Info zu allen Komponenten & Modellen\n'
        printf '  q  ❌ Beenden\n\n'

        local wahl
        read -r wahl < /dev/tty || exit 0

        [[ -n "$wahl" ]] && clear

        case "$wahl" in
            0|00) setup_alles; weiter ;;
            1)  code_opencode ;;
            2)  code_codex ;;
            3)  code_lokal ;;
            4)  (( zeige_cloud )) && code_abo ;;
            5)  (( zeige_cloud )) && code_api ;;
            6)  ollama_starten;  weiter ;;
            7)  local m; m="$(modell_erfragen)" && modell_laden "$m"; weiter ;;
            8)  ollama_beenden;  weiter ;;
            9)  speicher_status; weiter ;;
            10) local liste=() m2
                while IFS= read -r m2; do [[ -n "$m2" ]] && liste+=("$m2"); done < <(geladene_modelle)
                if (( ${#liste[@]} == 0 )); then
                    ok "Kein Modell geladen."
                else
                    local i=1
                    for m2 in "${liste[@]}"; do printf '  %d  %s\n' "$i" "$m2"; ((i++)); done
                    read -r -p $'\nNummer: ' nr < /dev/tty
                    if [[ "$nr" =~ ^[0-9]+$ ]] && (( nr >= 1 && nr <= ${#liste[@]} )); then
                        entlade "${liste[nr-1]}"
                    else
                        fehler "Ungültige Auswahl."
                    fi
                fi
                weiter ;;
            11) speicher_frei;   weiter ;;
            12) modelle_zeigen;  weiter ;;
            13) local diskliste=() d
                while IFS= read -r d; do [[ -n "$d" ]] && diskliste+=("$d"); done < <(ollama list 2>/dev/null | awk 'NR>1 {print $1}')
                if (( ${#diskliste[@]} == 0 )); then
                    ok "Keine Modelle auf der Festplatte."
                else
                    local i=1
                    for d in "${diskliste[@]}"; do printf '  %d  %s\n' "$i" "$d"; ((i++)); done
                    read -r -p $'\nNummer: ' nr < /dev/tty
                    if [[ "$nr" =~ ^[0-9]+$ ]] && (( nr >= 1 && nr <= ${#diskliste[@]} )); then
                        modell_loeschen "${diskliste[nr-1]}"
                    else
                        fehler "Ungültige Auswahl."
                    fi
                fi
                weiter ;;
            14) doctor; weiter ;;
            15) selfupdate; weiter ;;
            h|H) info_zeigen; weiter ;;
            C)  (( zeige_cloud = !zeige_cloud )) ;;
            q|Q) exit 0 ;;
            *)  ;;
        esac
    done
}

weiter() { printf '\n'; read -r -p "Weiter mit Enter ..." _ < /dev/tty || true; }

# --------------------------------------------------------------- Wartung

# Aktualisiert dieses Script per "git pull" im eigenen Repo-Ordner. Bricht
# ab, statt zu überschreiben, wenn es kein Git-Repo ist oder dort noch
# unkommittete Änderungen liegen.
selfupdate() {
    if [[ ! -d "$HIER/.git" ]]; then
        fehler "$HIER ist kein Git-Repository, Selbst-Update nicht möglich."
        return 1
    fi
    if [[ -n "$(git -C "$HIER" status --porcelain 2>/dev/null)" ]]; then
        fehler "Unkommittete Änderungen in $HIER - erst committen oder sichern, dann erneut versuchen."
        return 1
    fi

    titel "Selbst-Update"
    printf 'Hole Änderungen für %s ...\n' "$HIER"
    git -C "$HIER" pull --ff-only || { fehler "git pull fehlgeschlagen (Netzwerk oder Merge-Konflikt?)."; return 1; }
    ok "ki.sh ist aktuell."
}

# Kompakter Gesundheitscheck: welche Programme sind installiert (mit
# Version), läuft der Ollama-Server, ist der Script-Ordner ein Git-Repo.
doctor() {
    titel "ki doctor"

    if command -v brew &>/dev/null; then ok "Homebrew: $(brew --version 2>/dev/null | head -1)"
    else fehler "Homebrew: nicht installiert"; fi

    if command -v node &>/dev/null; then ok "Node.js: $(node --version 2>/dev/null)"
    else fehler "Node.js: nicht installiert"; fi

    if command -v npm &>/dev/null; then ok "npm: $(npm --version 2>/dev/null)"
    else fehler "npm: nicht installiert"; fi

    if command -v jq &>/dev/null; then ok "jq: $(jq --version 2>/dev/null)"
    else fehler "jq: nicht installiert"; fi

    if command -v ollama &>/dev/null; then ok "Ollama: $(ollama --version 2>/dev/null)"
    else fehler "Ollama: nicht installiert"; fi

    if command -v claude &>/dev/null; then ok "Claude Code: $(claude --version 2>/dev/null)"
    else fehler "Claude Code: nicht installiert"; fi

    if command -v opencode &>/dev/null; then ok "OpenCode: $(opencode --version 2>/dev/null)"
    else fehler "OpenCode: nicht installiert"; fi

    if command -v codex &>/dev/null; then ok "Codex: $(codex --version 2>/dev/null)"
    else fehler "Codex: nicht installiert"; fi

    printf '\n'
    if server_laeuft; then ok "Ollama-Server: erreichbar unter $HOST"
    else warnung "Ollama-Server: nicht erreichbar unter $HOST"; fi

    printf '\n'
    if [[ -d "$HIER/.git" ]]; then ok "Script-Ordner: Git-Repository ($HIER)"
    else warnung "Script-Ordner: kein Git-Repository, \"ki selfupdate\" nicht möglich ($HIER)"; fi
}

# ----------------------------------------------------------------- Hilfe

hilfe() {
    cat <<EOF
${B}ki${N} – zentrales Startscript für die lokale KI-Umgebung

Braucht kein anderes Script. Fehlende Programme (Homebrew, Node, jq,
Ollama, Claude Code, OpenCode, Codex) und fehlende Modelle werden bei
Bedarf automatisch installiert bzw. heruntergeladen (mit Rückfrage).
Mit "-y" oder "--yes" laufen alle Rückfragen automatisch durch.

${B}Einrichtung${N}
  ki setup [-y]             Alle Komponenten & Modelle prüfen/installieren

${B}OpenCode starten${N}
  ki opencode [1|2|3|modell]  OpenCode mit lokalem Ollama-Modell

${B}Codex starten${N}
  ki codex [1|2|3|modell]     Codex (OpenAI) mit lokalem Ollama-Modell

${B}Claude Code starten${N}
  ki code [1|2|3|modell]   Claude Code mit lokalem Ollama-Modell
  ki claude                Claude Code mit deinem Claude-Abo
  ki api                   Claude Code mit Anthropic API-Key

${B}Ollama steuern${N}
  ki start                 Ollama starten (installiert es bei Bedarf)
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
  ki uninstall [1|2|3|modell]  Modell endgültig von der Festplatte löschen

${B}Eigene Modelle (Registry)${N}
  ki registry list         Eigene Modelle anzeigen
  ki registry add <id> [Name] [Empfehlung]  Eigenes Modell hinzufügen
  ki registry rm <id>      Eigenes Modell wieder entfernen

${B}Wartung${N}
  ki doctor                Gesundheitscheck: installierte Versionen, Server
  ki selfupdate            ki.sh selbst aktualisieren (git pull im Repo)

${B}Sonstiges${N}
  ki                       Interaktives Hauptmenü
  ki help                  Diese Hilfe

${B}Modelle${N}
$(modell_menue)

"free" und "freeall" geben nur den Arbeitsspeicher frei – beim nächsten
Start wird das Modell einfach wieder von der Platte geladen. Nur "ki
uninstall <modell>" löscht ein Modell endgültig von der Festplatte (mit
Rückfrage).
EOF
}

# ----------------------------------------------------------------- Start

case "${1:-menu}" in
    menu|"")
        clear
        fehlend="$(komponenten_status)"
        if [[ -n "$fehlend" ]]; then
            titel "Erststart erkannt"
            printf 'Es fehlen noch Programme für die lokale KI-Umgebung: %s%s%s\n' "$Y" "$fehlend" "$N"
            if frage_ja "Jetzt automatisch einrichten"; then
                setup_alles
                weiter
            fi
        fi
        hauptmenue ;;

    setup|install)     shift || true; setup_alles ;;

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
    ps)             speicher_geladen ;;
    free|unload)    shift || true; speicher_frei "${1:-}" ;;
    freeall)        speicher_frei ;;
    watch)          shift || true; speicher_watch "${1:-3}" ;;
    models|list)    modelle_zeigen ;;
    uninstall|rm)   shift || true
                    if [[ -n "${1:-}" ]]; then m="$(modell_aufloesen "$1")" && modell_loeschen "$m"
                    else m="$(modell_erfragen)" && modell_loeschen "$m"; fi ;;

    registry)       shift || true
                    case "${1:-list}" in
                        add)              shift || true; registry_hinzufuegen "${1:-}" "${2:-}" "${3:-}" ;;
                        rm|remove|delete) shift || true; registry_entfernen "${1:-}" ;;
                        list|"")          registry_auflisten ;;
                        *) fehler "Unbekannt: ki registry ${1:-}. Nutze add|rm|list."; exit 1 ;;
                    esac ;;

    doctor)         doctor ;;
    selfupdate|update-ki) selfupdate ;;

    help|-h|--help) hilfe ;;
    *)  fehler "Unbekannter Befehl: $1"; printf '\n'; hilfe; exit 1 ;;
esac
