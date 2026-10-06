#!/usr/bin/env bash
#===============================================================================
# ki - zentrales Startscript für die lokale KI-Umgebung auf dem Mac.
#===============================================================================
#
# ÜBERBLICK
#
#   Dieses Script ist eigenständig und braucht KEIN anderes Script. Vor jeder
#   Aktion prüft es selbst, ob die dafür nötigen Programme auf der Festplatte
#   liegen (Homebrew, Node.js/npm, jq, Ollama, Claude Code, OpenCode, Codex)
#   und ob die gewünschten Modelle heruntergeladen sind. Fehlt etwas, wird es
#   nach einer Rückfrage automatisch nachinstalliert bzw. heruntergeladen.
#
#   Damit deckt es den kompletten Lebenszyklus ab:
#     - Komponenten und Modelle installieren und aktuell halten
#     - Ollama starten und beenden
#     - Modelle gezielt in den Arbeitsspeicher laden und wieder freigeben
#     - Claude Code, OpenCode oder Codex gegen ein lokales Modell starten
#     - Claude Code alternativ gegen die Cloud starten (Abo oder API-Key)
#     - jederzeit sehen, was gerade Arbeitsspeicher belegt
#
# WICHTIGE SICHERHEITSZUSAGE
#
#   "ki free" und "ki freeall" geben ausschliesslich Arbeitsspeicher frei und
#   löschen niemals etwas von der Festplatte. Ein Modell, das aus dem RAM
#   geworfen wurde, wird beim nächsten Start einfach wieder von der Platte
#   geladen. Nur "ki uninstall <modell>" löscht ein Modell endgültig von der
#   Festplatte, und auch das nur nach ausdrücklicher Rückfrage.
#
# AUFBAU DES SCRIPTS
#
#   Die Bezeichner (Funktions- und Variablennamen) sind bewusst englisch
#   gehalten, damit der Code der üblichen Shell-Konvention folgt. Die
#   Dokumentation ist durchgehend deutsch. Die Reihenfolge der Abschnitte:
#
#     1. Shell-Optionen und Grundeinstellungen
#     2. Modell-Registry (eingebaut + eigene Modelle)
#     3. Ausgabe-Hilfsmittel (Farben, Überschriften, Meldungen)
#     4. Allgemeine Hilfsfunktionen
#     5. Rückfragen (normal und für gefährliche Aktionen)
#     6. Komponenten sicherstellen (require_*)
#     7. Update-Prüfung (Homebrew und npm)
#     8. Modell-Verwaltung (vorhanden, Grösse, laden, löschen)
#     9. Eigene Modelle verwalten (Registry-Datei)
#    10. Ollama steuern (starten, beenden, Modelle laden)
#    11. KI-Assistenten starten (OpenCode, Codex, Claude Code)
#    12. Arbeitsspeicher beobachten und freigeben
#    13. Status, Information und Hilfe
#    14. Wartung (Gesundheitscheck, Selbst-Update)
#    15. Interaktives Hauptmenü
#    16. Befehlsverteilung (Kommandozeile)
#
# KOMPATIBILITÄT
#
#   Das Script läuft bewusst mit der Bash 3.2, die macOS mitliefert. Deshalb
#   werden neuere Bash-Funktionen wie "mapfile", "declare -A" oder Namerefs
#   ("local -n") nicht verwendet. Ebenso wird jedes möglicherweise leere Array
#   über das Muster ${arr[@]+"${arr[@]}"} expandiert, weil "${arr[@]}" in der
#   Bash 3.2 zusammen mit "set -u" bei einem leeren Array abbricht.
#
# EINRICHTUNG
#
#   Alias einrichten (optional, nur Komfort):                  ./install-ki.sh
#   Vollständige Einrichtung (Komponenten + Modelle):          ./ki.sh setup
#
#===============================================================================

#-------------------------------------------------------------------------------
# 1. Shell-Optionen und Grundeinstellungen
#-------------------------------------------------------------------------------
#
# "set -u"        bricht bei der Benutzung nicht gesetzter Variablen ab und
#                 verhindert damit Tippfehler, die sonst still zu leeren
#                 Werten führen würden.
# "set -o pipefail" sorgt dafür, dass eine Pipeline den Fehlercode des ersten
#                 fehlgeschlagenen Teils zurückgibt statt nur den des letzten.
#
# Bewusst NICHT gesetzt ist "set -e": Dieses Script ist interaktiv und soll
# bei einem fehlgeschlagenen Teilschritt eine verständliche Meldung ausgeben
# und im Menü bleiben, statt kommentarlos zu beenden. Jede Funktion prüft
# ihre Fehler daher selbst und gibt einen sprechenden Rückgabewert zurück.

set -uo pipefail

# Ordner, in dem dieses Script tatsächlich liegt (auch wenn es über einen
# Alias oder aus einem anderen Verzeichnis heraus aufgerufen wurde). Wird für
# das Selbst-Update gebraucht.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -z "$SCRIPT_DIR" ]]; then
    printf 'Fehler: Der Ordner dieses Scripts liess sich nicht bestimmen.\n' >&2
    exit 1
fi

# Adresse des Ollama-Servers. Über die Umgebungsvariable OLLAMA_HOST kann eine
# abweichende Adresse gesetzt werden; fehlt dort das Schema, wird "http://"
# ergänzt, damit curl damit umgehen kann.
API_URL="${OLLAMA_HOST:-http://127.0.0.1:11434}"
[[ "$API_URL" != http* ]] && API_URL="http://$API_URL"

# Konfigurationsdatei von OpenCode. Dort werden die lokalen Ollama-Modelle
# eingetragen, damit OpenCode sie über "-m ollama/<modell>" ansprechen kann.
OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"

# Kontextgrösse (in Token) für Claude Code und Codex gegen lokale Modelle.
# Grössere Werte erlauben längere Unterhaltungen, brauchen aber deutlich mehr
# Arbeitsspeicher. Kann von aussen über KI_CONTEXT überschrieben werden.
KI_CONTEXT="${KI_CONTEXT:-65536}"

# Sekunden, die beim Starten von Ollama maximal auf den Server gewartet wird.
OLLAMA_START_TIMEOUT=20

# Schwelle für die Speicherplatzwarnung, wenn die tatsächliche Modellgrösse
# nicht ermittelt werden konnte: Unterhalb dieses freien Platzes wird
# vorsichtshalber nachgefragt (10 GB).
MIN_FREE_BYTES=$(( 10 * 1024 * 1024 * 1024 ))

#-------------------------------------------------------------------------------
# 2. Modell-Registry
#-------------------------------------------------------------------------------
#
# Jeder Eintrag hat das Format:  id|Anzeigename|Empfehlung
#
#   id           So heisst das Modell bei Ollama ("ollama pull <id>").
#   Anzeigename  Was im Menü und in der Hilfe angezeigt wird.
#   Empfehlung   Ein Satz dazu, wofür sich das Modell besonders eignet.
#
# Die Position in dieser Liste bestimmt die Kurznummer: Das erste Modell ist
# überall als "1" ansprechbar, das zweite als "2" und so weiter.

MODELS=(
    "qwen3-coder:30b|Qwen3-Coder 30B|Beste Wahl für Swift, SwiftUI, Xcode, Refactoring und große Projekte."
    "nemotron-3.5-lightning|Nemotron 3.5 Lightning|Sehr gut für Agenten, MCP, Code Reviews und Tool Calling."
    "gemma4:latest|Gemma 4|Schnell für Dokumentation, Erklärungen und allgemeine Aufgaben."
)

# Eigene Modelle lassen sich ergänzen, ohne dieses Script zu bearbeiten: eine
# Zeile pro Modell im selben "id|Anzeigename|Empfehlung"-Format in der Datei
# unten. Leerzeilen und Zeilen, die mit "#" beginnen, werden übersprungen.
# Verwaltet wird die Datei bequem über "ki registry add|rm|list".
REGISTRY_FILE="$HOME/.ki/modelle.conf"

# Liest die Datei mit den eigenen Modellen ein und hängt jede gültige Zeile an
# MODELS an. Kaputte Zeilen (ohne "|" oder ohne Modell-ID) werden bewusst
# übersprungen statt das ganze Script scheitern zu lassen - eine von Hand
# verunglückte Zeile soll die Umgebung nicht unbenutzbar machen.
load_user_registry() {
    [[ -f "$REGISTRY_FILE" ]] || return 0

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Leerzeilen und Kommentare überspringen.
        [[ -z "$line" || "$line" == \#* ]] && continue
        # Eine gültige Zeile muss mindestens eine ID vor dem ersten "|" haben.
        [[ "$line" != *"|"* || "${line%%|*}" == "" ]] && continue
        MODELS+=("$line")
    done < "$REGISTRY_FILE"
}
load_user_registry

#-------------------------------------------------------------------------------
# 3. Ausgabe-Hilfsmittel
#-------------------------------------------------------------------------------
#
# Farben werden nur gesetzt, wenn die Ausgabe wirklich an einem Terminal
# hängt. Wird die Ausgabe in eine Datei oder durch eine Pipe geleitet, bleiben
# alle Farbvariablen leer, damit dort keine Steuerzeichen landen.

if [[ -t 1 ]]; then
    BOLD=$'\033[1m';   DIM=$'\033[2m';    RED=$'\033[31m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'
    RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
fi

# Überschrift mit Trennlinie darunter.
print_heading() {
    printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"
    printf '%s%s%s\n' "$DIM" "$(printf '─%.0s' $(seq 1 62))" "$RESET"
}

# Eine Zeile im Kasten des Hauptmenüs. Der Inhalt wird auf 70 Zeichen
# aufgefüllt, damit der Rahmen (71 "═") unabhängig vom Terminal exakt
# ausgerichtet bleibt.
#
# Die Polsterung wird über ${#text} (Anzahl Zeichen) berechnet statt über
# printf "%-70s": printf polstert auf diesem System nach Bytes, nicht nach
# Zeichen. Jeder Umlaut (ü, ä, ö - ein Zeichen, aber zwei Bytes) würde den
# rechten Rand sonst um eine Spalte nach links verschieben.
print_box_line() {
    local text="$1" pad=$(( 70 - ${#1} ))
    (( pad < 0 )) && pad=0
    printf '%s║ %s%*s║%s\n' "$BOLD" "$text" "$pad" "" "$RESET"
}

# Fehlermeldung. Geht bewusst nach stderr, damit sie auch dann sichtbar ist,
# wenn die normale Ausgabe der Funktion weiterverarbeitet wird.
print_error() { printf '%sFehler: %s%s\n' "$RED" "$1" "$RESET" >&2; }

# Erfolgsmeldung mit Haken.
print_ok() { printf '%s✓ %s%s\n' "$GREEN" "$1" "$RESET"; }

# Warnung mit Ausrufezeichen.
print_warning() { printf '%s! %s%s\n' "$YELLOW" "$1" "$RESET"; }

#-------------------------------------------------------------------------------
# 4. Allgemeine Hilfsfunktionen
#-------------------------------------------------------------------------------

# Ist ein Programm im PATH aufrufbar? Kapselt "command -v", damit die Absicht
# an der Aufrufstelle lesbar bleibt.
have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Besteht die Eingabe ausschliesslich aus Ziffern? Wird gebraucht, bevor eine
# Benutzereingabe in einer Rechnung oder als Index verwendet wird.
is_number() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

# Ist ein Terminal für Rückfragen verfügbar? Ohne /dev/tty kann nicht sinnvoll
# nachgefragt werden (z.B. wenn das Script aus einem Cron-Job läuft).
have_tty() { [[ -r /dev/tty ]]; }

# Antwortet der Ollama-Server? Kurzer Timeout, damit das Menü nicht hängt,
# wenn der Server nicht läuft.
server_is_running() { curl -fsS --max-time 3 "$API_URL" >/dev/null 2>&1; }

# Holt Feld n aus einem Registry-Eintrag ("id|Name|Empfehlung").
field() { printf '%s' "$1" | cut -d'|' -f"$2"; }

# Formatiert eine Byte-Zahl als Gigabyte. Unbrauchbare Eingaben (leer oder
# keine Zahl) ergeben "?" statt einer irreführenden 0.0 GB.
format_gb() {
    if ! is_number "${1:-}"; then
        printf '?'
        return 0
    fi
    awk -v b="$1" 'BEGIN { printf "%.1f GB", b/1073741824 }'
}

# Sammelt temporäre Dateien, damit sie beim Beenden zuverlässig verschwinden -
# auch wenn das Script mit Strg-C abgebrochen wird.
TEMP_FILES=()

register_temp_file() { TEMP_FILES+=("$1"); }

cleanup_temp_files() {
    (( ${#TEMP_FILES[@]} == 0 )) && return 0
    local file
    for file in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do
        [[ -n "$file" && -e "$file" ]] && rm -f "$file"
    done
}
trap cleanup_temp_files EXIT

#-------------------------------------------------------------------------------
# 5. Rückfragen
#-------------------------------------------------------------------------------
#
# Mit "-y" oder "--yes" (oder KI_AUTO_YES=1) laufen alle Rückfragen
# automatisch durch. Das ist für unbeaufsichtigte Einrichtungen gedacht.

AUTO_YES=0
[[ "${KI_AUTO_YES:-0}" == "1" ]] && AUTO_YES=1

# "-y"/"--yes" aus den Argumenten herausfiltern, damit die eigentliche
# Befehlsverteilung weiter unten nur noch die echten Befehle sieht.
PARSED_ARGS=()
for _arg in "$@"; do
    case "$_arg" in
        -y|--yes) AUTO_YES=1 ;;
        *)        PARSED_ARGS+=("$_arg") ;;
    esac
done
if (( ${#PARSED_ARGS[@]} > 0 )); then
    set -- "${PARSED_ARGS[@]}"
else
    set --
fi

# Normale Ja/Nein-Rückfrage für harmlose Aktionen (installieren, laden ...).
#
# Verhalten:
#   - AUTO_YES gesetzt        -> ja, ohne zu fragen
#   - kein Terminal vorhanden -> ja, denn sonst würde das Script hängen
#   - sonst                   -> fragen; leere Eingabe bedeutet ja
#
# Rückgabe: 0 = ja, 1 = nein
confirm() {
    (( AUTO_YES )) && return 0
    have_tty || return 0

    local answer
    read -r -p "$1 (J/n): " answer < /dev/tty || return 1
    [[ -z "$answer" || "$answer" =~ ^[jJyY]$ ]]
}

# Rückfrage für Aktionen, die etwas unwiderruflich entfernen (Modell von der
# Festplatte löschen).
#
# Unterschied zu confirm(): Ohne Terminal wird hier NICHT automatisch
# zugestimmt, sondern abgelehnt. Ein versehentlich in einem Skript oder Cron-
# Job gelandeter Löschbefehl soll niemals stillschweigend Daten entfernen.
# Wer das bewusst automatisieren will, muss "-y" ausdrücklich angeben.
#
# Rückgabe: 0 = ja, 1 = nein
confirm_destructive() {
    (( AUTO_YES )) && return 0
    if ! have_tty; then
        print_error "Ohne Terminal wird nichts gelöscht. Für unbeaufsichtigtes Löschen \"-y\" angeben."
        return 1
    fi

    local answer
    read -r -p "$1 (j/N): " answer < /dev/tty || return 1
    # Bewusst umgekehrte Vorbelegung: Nur ein ausdrückliches "j"/"y" löscht.
    [[ "$answer" =~ ^[jJyY]$ ]]
}

#-------------------------------------------------------------------------------
# 6. Komponenten sicherstellen
#-------------------------------------------------------------------------------
#
# Jede require_*-Funktion arbeitet nach demselben Muster:
#
#   1. Ist das Programm schon da?  -> sofort fertig (Rückgabe 0)
#   2. Sonst: erklären, was fehlt und wofür es gebraucht wird
#   3. Nachfragen, ob installiert werden soll
#   4. Installieren und danach prüfen, ob es tatsächlich geklappt hat
#
# Dadurch kann jede Funktion, die z.B. "claude" braucht, einfach
# "require_claude" aufrufen und muss sich um die Installation nicht kümmern.
# Rückgabe überall: 0 = einsatzbereit, 1 = nicht verfügbar.

require_brew() {
    have_cmd brew && return 0

    print_error "Homebrew ist nicht installiert (wird für Ollama, Node, jq gebraucht)."
    confirm "Homebrew jetzt installieren" || return 1

    printf 'Installiere Homebrew ...\n'
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || { print_error "Homebrew-Installation fehlgeschlagen."; return 1; }

    # Homebrew liegt auf Apple Silicon unter /opt/homebrew, auf Intel-Macs
    # unter /usr/local. Damit brew sofort - ohne neues Terminal - benutzbar
    # ist, wird die passende Umgebung direkt geladen.
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    hash -r

    have_cmd brew || { print_error "brew nach der Installation nicht gefunden."; return 1; }
    print_ok "Homebrew installiert."
}

require_node() {
    have_cmd npm && return 0

    print_error "Node.js/npm ist nicht installiert (wird für Claude Code und Codex gebraucht)."
    confirm "Node.js jetzt installieren" || return 1

    require_brew || return 1
    printf 'Installiere Node.js ...\n'
    brew install node || { print_error "Node-Installation fehlgeschlagen."; return 1; }
    hash -r

    have_cmd npm || { print_error "npm nach der Installation nicht gefunden. Neues Terminal öffnen."; return 1; }
    print_ok "Node.js installiert."
}

require_jq() {
    have_cmd jq && return 0

    print_error "jq ist nicht installiert (wird für die Modell- und Konfig-Verwaltung gebraucht)."
    confirm "jq jetzt installieren" || return 1

    require_brew || return 1
    printf 'Installiere jq ...\n'
    brew install jq || { print_error "jq-Installation fehlgeschlagen."; return 1; }
    hash -r

    have_cmd jq || { print_error "jq nach der Installation nicht gefunden."; return 1; }
    print_ok "jq installiert."
}

require_ollama() {
    if [[ -d "/Applications/Ollama.app" ]] || have_cmd ollama; then
        return 0
    fi

    print_error "Ollama ist nicht installiert."
    confirm "Ollama jetzt installieren" || return 1

    require_brew || return 1
    printf 'Installiere Ollama (offizielle App, nicht die Formula) ...\n'
    # WICHTIG: Hier wird bewusst das Cask "ollama-app" installiert (die
    # offizielle App mit vollständigem Runner) und NICHT die Formula
    # "brew install ollama". Der Formula fehlt der llama-server, wodurch
    # GGUF-Modelle wie gemma4 nicht starten können.
    brew install --cask ollama-app || { print_error "Ollama-Installation fehlgeschlagen."; return 1; }

    # Die App muss einmal gelaufen sein, damit sie das Kommandozeilenwerkzeug
    # "ollama" einrichtet. Danach wird bis zu 20 Sekunden darauf gewartet.
    printf 'Starte Ollama einmal, damit die Kommandozeile eingerichtet wird ...\n'
    open -ga "/Applications/Ollama.app" >/dev/null 2>&1 || true
    local i
    for (( i = 0; i < OLLAMA_START_TIMEOUT; i++ )); do
        have_cmd ollama && break
        hash -r
        sleep 1
    done

    have_cmd ollama || { print_error "ollama nach der Installation nicht gefunden. Neues Terminal öffnen."; return 1; }
    print_ok "Ollama installiert."
}

require_claude() {
    have_cmd claude && return 0

    print_error "Claude Code ist nicht installiert."
    confirm "Claude Code jetzt installieren" || return 1

    require_node || return 1
    printf 'Installiere Claude Code ...\n'
    npm install -g @anthropic-ai/claude-code || { print_error "Claude-Code-Installation fehlgeschlagen."; return 1; }
    hash -r

    have_cmd claude || { print_error "claude nach der Installation nicht gefunden. Neues Terminal öffnen."; return 1; }
    print_ok "Claude Code installiert."
}

require_opencode() {
    have_cmd opencode && return 0

    print_error "OpenCode ist nicht installiert."
    confirm "OpenCode jetzt installieren" || return 1

    printf 'Installiere OpenCode ...\n'
    curl -fsSL https://opencode.ai/install | bash || { print_error "OpenCode-Installation fehlgeschlagen."; return 1; }
    # Der Installer legt das Programm unter ~/.local/bin ab. Dieser Ordner ist
    # in einer frischen Shell oft noch nicht im PATH, deshalb wird er hier für
    # die laufende Sitzung ergänzt.
    export PATH="$HOME/.local/bin:$PATH"
    hash -r

    have_cmd opencode || { print_error "opencode nach der Installation nicht gefunden. Neues Terminal öffnen oder 'source ~/.zshrc'."; return 1; }
    print_ok "OpenCode installiert."
}

require_codex() {
    have_cmd codex && return 0

    print_error "Codex ist nicht installiert."
    confirm "Codex jetzt installieren" || return 1

    require_node || return 1
    printf 'Installiere Codex ...\n'
    npm install -g @openai/codex || { print_error "Codex-Installation fehlgeschlagen."; return 1; }
    hash -r

    have_cmd codex || { print_error "codex nach der Installation nicht gefunden. Neues Terminal öffnen."; return 1; }
    print_ok "Codex installiert."
}

# Antigravity (Google) wird nicht automatisch installiert, weil es keine
# Homebrew-Formula gibt - stattdessen wird auf den Menüpunkt "CLI
# installieren" (install_antigravity_native) verwiesen.
require_agy() {
    have_cmd agy && return 0

    print_error "Antigravity-CLI (agy) ist nicht installiert."
    printf 'Installieren über "CLI installieren" oder:\n'
    printf '  curl -fsSL https://antigravity.google/cli/install.sh | bash\n'
    return 1
}

#-------------------------------------------------------------------------------
# 7. Update-Prüfung
#-------------------------------------------------------------------------------
#
# Beide Funktionen führen zwei Zähler mit:
#
#   upgrade_count    tatsächlich durchgeführte Updates
#   unchecked_count  Komponenten, die gar nicht geprüft werden konnten (weil
#                    sie nicht über Homebrew bzw. npm installiert sind oder
#                    keine Verbindung bestand)
#
# Beide werden in run_setup() als lokale Variablen angelegt; die Funktionen
# greifen über den dynamischen Geltungsbereich der Shell darauf zu. Wird eine
# der Funktionen ausserhalb von run_setup benutzt, müssen die Zähler dort
# ebenfalls vorhanden sein.

# Prüft eine per Homebrew installierte Formula oder ein Cask auf ein Update
# und aktualisiert es nach Rückfrage.
#
# Aufruf:  upgrade_brew_package <brew-paket> <ist_cask: 0|1> <anzeigename> <programm>
#
# Das vierte Argument ist der Name des eigentlichen Programms. Er wird nur
# gebraucht, um im Übersprungen-Fall anzuzeigen, woher das Programm
# stattdessen kommt (z.B. nvm oder das System).
#
# Rückgabe: 0 = nichts zu tun oder erfolgreich, 1 = Update fehlgeschlagen
upgrade_brew_package() {
    local package="$1" is_cask="$2" label="$3" cmd="${4:-}"
    have_cmd brew || return 0

    # Casks und Formulas brauchen unterschiedliche brew-Aufrufe. Das Flag wird
    # in einem Array gesammelt und weiter unten über das Muster
    # ${arr[@]+"${arr[@]}"} expandiert - ein schlichtes "${arr[@]}" würde in
    # der Bash 3.2 unter "set -u" bei leerem Array abbrechen.
    local flags=() is_installed=0
    if (( is_cask )); then
        flags=(--cask)
        brew list --cask "$package" >/dev/null 2>&1 && is_installed=1
    else
        brew list --formula "$package" >/dev/null 2>&1 && is_installed=1
    fi

    # Nicht über Homebrew installiert? Dann kann Homebrew hier auch nichts
    # aktualisieren. Das ist kein Fehler - z.B. kommt Node.js häufig von nvm
    # und jq bei neueren macOS-Versionen vom System selbst. Damit klar ist,
    # warum übersprungen wird, wird der tatsächliche Fundort mit angezeigt.
    if (( ! is_installed )); then
        local origin=""
        [[ -n "$cmd" ]] && origin="$(command -v "$cmd" 2>/dev/null)"
        printf '  %-14s kommt nicht von Homebrew%s – dort kein Update möglich\n' \
            "$label" "${origin:+ ($origin)}"
        (( unchecked_count++ ))
        return 0
    fi

    # Laufend anzeigen, was gerade geprüft wird: erst der Hinweis ohne
    # Zeilenumbruch, dann in derselben Zeile das Ergebnis dahinter. Bewusst
    # ohne Wagenrücklauf (\r), damit die Ausgabe auch in einer Datei oder
    # Pipe sauber bleibt.
    printf '  %-14s wird geprüft ...' "$label"

    local outdated
    outdated="$(brew outdated --quiet ${flags[@]+"${flags[@]}"} "$package" 2>/dev/null)"
    if [[ -z "$outdated" ]]; then
        printf ' ist aktuell\n'
        return 0
    fi
    printf ' Update verfügbar\n'

    print_warning "$label: Update verfügbar."
    confirm "$label jetzt aktualisieren" || return 0

    printf 'Aktualisiere %s ...\n' "$label"
    brew upgrade ${flags[@]+"${flags[@]}"} "$package" \
        || { print_error "$label-Update fehlgeschlagen."; return 1; }
    hash -r
    print_ok "$label aktualisiert."
    (( upgrade_count++ ))
}

# Ermittelt die installierte Version eines global installierten npm-Pakets.
#
# Bewusst OHNE sed: Paketnamen mit Namensraum enthalten einen Schrägstrich
# ("@anthropic-ai/claude-code"). In einem sed-Ausdruck "s/.../.../" würde
# dieser Schrägstrich als Trennzeichen gelesen und der Aufruf scheitern.
# Stattdessen wird die passende Zeile mit grep gesucht und die Version über
# Parameter-Expansion abgetrennt: "##*@" entfernt alles bis zum LETZTEN "@",
# sodass aus "├── @anthropic-ai/claude-code@2.1.228" sauber "2.1.228" wird.
#
# Ausgabe: die Versionsnummer, oder nichts wenn das Paket nicht installiert ist
npm_installed_version() {
    local package="$1" line version

    line="$(npm list -g --depth=0 2>/dev/null | grep -F -- "${package}@" | head -1)"
    [[ -z "$line" ]] && return 0

    version="${line##*@}"
    # Etwaige Anhängsel hinter der Version abschneiden (z.B. " deduped").
    version="${version%%[[:space:]]*}"
    # Nur zurückgeben, was auch wirklich wie eine Versionsnummer aussieht.
    [[ "$version" =~ ^[0-9] ]] || return 0

    printf '%s' "$version"
}

# Prüft ein global installiertes npm-Paket auf ein Update und aktualisiert es
# nach Rückfrage.
#
# Aufruf:  upgrade_npm_package <paketname> <anzeigename>
# Rückgabe: 0 = nichts zu tun oder erfolgreich, 1 = Update fehlgeschlagen
upgrade_npm_package() {
    local package="$1" label="$2"
    have_cmd npm || return 0

    # Ist das Paket nicht global installiert, gibt es nichts zu aktualisieren.
    local installed
    installed="$(npm_installed_version "$package")"
    if [[ -z "$installed" ]]; then
        printf '  %-14s kommt nicht von npm – dort kein Update möglich\n' "$label"
        (( unchecked_count++ ))
        return 0
    fi

    # Laufend anzeigen, was gerade geprüft wird. Die Abfrage geht über das
    # Netz und kann ein paar Sekunden dauern - ohne diesen Hinweis stünde der
    # Bildschirm scheinbar still. Das Ergebnis wird in dieselbe Zeile
    # angehängt (ohne Wagenrücklauf, damit auch Dateien und Pipes sauber
    # bleiben).
    printf '  %-14s wird geprüft ...' "$label"

    # Neueste veröffentlichte Version abfragen. Ohne Netz bleibt das leer.
    local latest
    latest="$(npm view "$package" version 2>/dev/null)"
    if [[ -z "$latest" ]]; then
        printf ' Version %s, nicht prüfbar (keine Verbindung)\n' "$installed"
        (( unchecked_count++ ))
        return 0
    fi
    if [[ "$latest" == "$installed" ]]; then
        printf ' ist aktuell (%s)\n' "$installed"
        return 0
    fi
    printf ' Update verfügbar\n'

    print_warning "$label: Update verfügbar ($installed → $latest)."
    confirm "$label jetzt aktualisieren" || return 0

    printf 'Aktualisiere %s ...\n' "$label"
    npm install -g "${package}@latest" || { print_error "$label-Update fehlgeschlagen."; return 1; }
    hash -r
    print_ok "$label aktualisiert."
    (( upgrade_count++ ))
}

#-------------------------------------------------------------------------------
# 8. Modell-Verwaltung
#-------------------------------------------------------------------------------

# Liegt ein Modell bereits auf der Festplatte?
#
# "ollama list" hängt häufig ":latest" an, auch wenn die Registry das Modell
# ohne Tag führt (z.B. "nemotron-3.5-lightning" gegenüber
# "nemotron-3.5-lightning:latest"). Deshalb wird gegen beide Schreibweisen
# geprüft statt nur exakt zu vergleichen.
#
# Rückgabe: 0 = vorhanden, 1 = nicht vorhanden
model_is_on_disk() {
    have_cmd ollama || return 1

    local model="$1" installed
    installed="$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')"
    [[ -z "$installed" ]] && return 1

    grep -qx "$model" <<<"$installed" && return 0
    grep -qx "${model%:latest}:latest" <<<"$installed" && return 0
    return 1
}

# Ermittelt die voraussichtliche Downloadgrösse eines Modells in Bytes, indem
# die Layer-Grössen aus dem Manifest der Ollama-Registry addiert werden.
#
# Funktioniert für offizielle Modelle ("gemma4") ebenso wie für Modelle mit
# Namensraum ("benutzer/modell"). Schlägt irgendetwas fehl (kein Netz, kein
# jq, unbekanntes Modell), wird nichts ausgegeben - der Aufrufer behandelt das
# als "Grösse unbekannt" und arbeitet mit einem Schätzwert weiter.
model_size_bytes() {
    have_cmd jq || return 0

    local model="$1" name tag="latest"
    name="$model"
    # Tag abtrennen, falls vorhanden (z.B. "qwen3-coder:30b" -> Tag "30b").
    if [[ "$model" == *:* ]]; then
        name="${model%%:*}"
        tag="${model##*:}"
    fi
    # Modelle ohne Namensraum liegen in der Registry unter "library/".
    [[ "$name" != */* ]] && name="library/$name"

    curl -fsS --max-time 5 "https://registry.ollama.ai/v2/${name}/manifests/${tag}" 2>/dev/null \
        | jq -r '[.layers[]?.size] | add // empty' 2>/dev/null
}

# Prüft vor einem Download, ob dort, wo Ollama seine Modelle ablegt, genügend
# freier Speicherplatz vorhanden ist.
#
# Ist die Modellgrösse bekannt, wird sie zuzüglich 10 % Reserve mit dem freien
# Platz verglichen. Ist sie unbekannt, greift die pauschale Schwelle
# MIN_FREE_BYTES. In beiden Fällen entscheidet am Ende der Benutzer.
#
# Rückgabe: 0 = weitermachen, 1 = abbrechen
check_disk_space() {
    local model="$1" dir="$HOME/.ollama/models"
    [[ -d "$dir" ]] || dir="$HOME"

    # Freien Platz in Kilobyte ermitteln ("df -Pk" liefert ein stabil
    # formatiertes Ergebnis). Klappt das nicht, wird die Prüfung übersprungen
    # statt den Download grundlos zu blockieren.
    local free_kb free_bytes
    free_kb="$(df -Pk "$dir" 2>/dev/null | awk 'NR==2 {print $4}')"
    is_number "$free_kb" || return 0
    free_bytes=$(( free_kb * 1024 ))

    local needed
    needed="$(model_size_bytes "$model")"

    if is_number "$needed" && (( needed > 0 )); then
        if (( free_bytes < needed + needed / 10 )); then
            print_warning "Nur $(format_gb "$free_bytes") frei, '$model' braucht aber rund $(format_gb "$needed")."
            confirm "Trotzdem versuchen" || return 1
        fi
    elif (( free_bytes < MIN_FREE_BYTES )); then
        print_warning "Nur $(format_gb "$free_bytes") frei auf der Platte - für ein mehrere-GB-Modell könnte das knapp werden."
        confirm "Trotzdem versuchen" || return 1
    fi
    return 0
}

# Stellt sicher, dass ein Modell auf der Festplatte liegt, und lädt es bei
# Bedarf nach Rückfrage herunter. Setzt einen laufenden Ollama-Server voraus.
#
# Rückgabe: 0 = Modell ist da, 1 = nicht vorhanden bzw. Download abgelehnt
ensure_model() {
    local model="$1"

    model_is_on_disk "$model" && return 0
    require_ollama || return 1

    print_warning "Modell '$model' ist noch nicht heruntergeladen."
    confirm "$model jetzt herunterladen (mehrere GB)" || return 1
    check_disk_space "$model" || return 1

    printf 'Lade %s%s%s herunter ...\n' "$CYAN" "$model" "$RESET"
    ollama pull "$model" || { print_error "Download von $model fehlgeschlagen."; return 1; }
    print_ok "$model heruntergeladen."
}

# Löscht ein Modell endgültig von der Festplatte.
#
# Dies ist der einzige Befehl im ganzen Script, der Daten von der Platte
# entfernt - im Gegensatz zu "free"/"freeall", die nur Arbeitsspeicher
# freigeben. Deshalb wird hier confirm_destructive() benutzt, das ohne
# Terminal nicht stillschweigend zustimmt.
#
# Rückgabe: 0 = gelöscht, 1 = nicht gelöscht
delete_model() {
    local model="$1"

    have_cmd ollama || { print_error "Ollama ist nicht installiert."; return 1; }
    model_is_on_disk "$model" || { print_error "'$model' ist nicht auf der Festplatte."; return 1; }

    print_warning "'$model' wird endgültig von der Festplatte gelöscht."
    confirm_destructive "'$model' jetzt löschen" || { printf 'Abgebrochen, es wurde nichts gelöscht.\n'; return 1; }

    ollama rm "$model" || { print_error "Löschen von $model fehlgeschlagen."; return 1; }
    print_ok "'$model' von der Festplatte gelöscht."
}

# Übersetzt eine Benutzereingabe in eine Modell-ID.
#
# Erlaubt sind:
#   - eine Kurznummer entsprechend der Position in MODELS ("1", "2", "3" ...)
#   - eine Modell-ID aus MODELS ("gemma4:latest")
#   - eine beliebige Modell-ID, die auf der Festplatte liegt
#
# Die aufgelöste ID wird nach stdout geschrieben, alle Meldungen gehen nach
# stderr - so kann der Aufrufer das Ergebnis sauber in einer Variablen
# einfangen: model="$(resolve_model "$eingabe")" || return 1
#
# Rückgabe: 0 = aufgelöst, 1 = unbekannt
resolve_model() {
    local input="${1:-}"

    if [[ -z "$input" ]]; then
        print_error "Kein Modell angegeben."
        return 1
    fi

    # Kurznummer aus der Registry.
    if is_number "$input"; then
        if (( input >= 1 && input <= ${#MODELS[@]} )); then
            field "${MODELS[input-1]}" 1
            return 0
        fi
        print_error "Es gibt nur die Modelle 1 bis ${#MODELS[@]}."
        return 1
    fi

    # Direkter Treffer in der Registry.
    local entry
    for entry in "${MODELS[@]+"${MODELS[@]}"}"; do
        if [[ "$(field "$entry" 1)" == "$input" ]]; then
            printf '%s' "$input"
            return 0
        fi
    done

    # Sonst: liegt das Modell überhaupt auf der Platte?
    if model_is_on_disk "$input"; then
        printf '%s' "$input"
        return 0
    fi

    print_error "Modell '$input' ist nicht installiert."
    printf '\nInstallierte Modelle:\n' >&2
    ollama list 2>/dev/null | sed 's/^/  /' >&2
    return 1
}

# Gibt die Registry als nummerierte Liste aus (Nummer, Anzeigename und
# darunter eingerückt die Empfehlung).
print_model_list() {
    local i=1 entry
    for entry in "${MODELS[@]+"${MODELS[@]}"}"; do
        printf '  %s%d%s  %s\n' "$CYAN" "$i" "$RESET" "$(field "$entry" 2)"
        printf '     %s%s%s\n' "$DIM" "$(field "$entry" 3)" "$RESET"
        i=$(( i + 1 ))
    done
}

# Fragt interaktiv nach einem Modell, wenn auf der Kommandozeile keins stand.
# Die Auswahlliste geht nach stderr, damit auf stdout nur die aufgelöste
# Modell-ID landet.
#
# Rückgabe: 0 = Modell aufgelöst, 1 = abgebrochen oder ungültig
ask_for_model() {
    if ! have_tty; then
        print_error "Kein Terminal für die Rückfrage verfügbar. Modell direkt angeben, z.B. \"ki load 1\"."
        return 1
    fi

    printf '%sWelches Modell?%s\n\n' "$BOLD" "$RESET" >&2
    print_model_list >&2
    printf '\n' >&2

    local choice
    read -r -p "Auswahl (1-${#MODELS[@]}): " choice < /dev/tty || return 1
    resolve_model "$choice"
}

# Ermittelt das zu verwendende Modell: entweder aus dem übergebenen Argument
# oder - falls leer - über eine interaktive Rückfrage. Fasst die Logik
# zusammen, die sonst in jedem Assistenten-Start wiederholt würde.
select_model() {
    if [[ -n "${1:-}" ]]; then
        resolve_model "$1"
    else
        ask_for_model
    fi
}

#-------------------------------------------------------------------------------
# 9. Eigene Modelle verwalten
#-------------------------------------------------------------------------------
#
# Die Registry-Datei ist eine schlichte Textdatei mit einer Zeile je Modell im
# Format "id|Anzeigename|Empfehlung". Änderungen wirken sich ab dem nächsten
# Start von ki aus, weil die Datei beim Start eingelesen wird.

# Trägt ein eigenes Modell in die Registry-Datei ein.
#
# Aufruf:  registry_add <id> [anzeigename] [empfehlung]
# Rückgabe: 0 = eingetragen, 1 = Eingabe ungültig oder schon vorhanden
registry_add() {
    local id="${1:-}" name="${2:-}" recommendation="${3:-}"

    if [[ -z "$id" ]]; then
        print_error 'Modell-ID fehlt. Beispiel: ki registry add mein-modell:8b "Mein Modell" "Wofür es gut ist."'
        return 1
    fi
    # Der senkrechte Strich ist das Trennzeichen des Dateiformats und darf
    # deshalb in keinem der drei Felder vorkommen.
    if [[ "$id$name$recommendation" == *"|"* ]]; then
        print_error 'Das Zeichen "|" ist nicht erlaubt, es trennt intern die Felder.'
        return 1
    fi
    # Ohne Anzeigenamen wird die ID selbst angezeigt.
    [[ -z "$name" ]] && name="$id"

    if grep -qF "$id|" "$REGISTRY_FILE" 2>/dev/null; then
        print_error "'$id' steht schon in $REGISTRY_FILE."
        return 1
    fi

    mkdir -p "$(dirname "$REGISTRY_FILE")" \
        || { print_error "Ordner für $REGISTRY_FILE liess sich nicht anlegen."; return 1; }
    printf '%s|%s|%s\n' "$id" "$name" "$recommendation" >> "$REGISTRY_FILE" \
        || { print_error "In $REGISTRY_FILE konnte nicht geschrieben werden."; return 1; }

    print_ok "'$id' zur Registry hinzugefügt. Erscheint ab dem nächsten Start von ki im Modell-Menü."
}

# Entfernt ein eigenes Modell wieder aus der Registry-Datei. Das Modell selbst
# bleibt dabei auf der Festplatte liegen.
#
# Rückgabe: 0 = entfernt, 1 = nicht gefunden oder Schreibfehler
registry_remove() {
    local id="${1:-}"

    [[ -z "$id" ]] && { print_error "Modell-ID fehlt."; return 1; }
    [[ -f "$REGISTRY_FILE" ]] || { print_error "Es gibt noch keine eigenen Modelle."; return 1; }

    if ! grep -qF "$id|" "$REGISTRY_FILE"; then
        print_error "'$id' steht nicht in $REGISTRY_FILE."
        return 1
    fi

    # Über eine temporäre Datei arbeiten, damit die Registry bei einem
    # Schreibfehler nicht halb beschrieben zurückbleibt.
    local tmp="$REGISTRY_FILE.tmp.$$"
    register_temp_file "$tmp"

    # "grep -v" liefert Rückgabewert 1, wenn keine Zeile übrig bleibt (also
    # beim Löschen des letzten Eintrags). Das ist hier kein Fehler, deshalb
    # "|| true".
    grep -vF "$id|" "$REGISTRY_FILE" > "$tmp" || true
    mv "$tmp" "$REGISTRY_FILE" || { print_error "$REGISTRY_FILE liess sich nicht aktualisieren."; return 1; }

    print_ok "'$id' aus der Registry entfernt (auf der Festplatte bleibt es, dafür 'ki uninstall $id')."
}

# Zeigt die eingetragenen eigenen Modelle an.
registry_list() {
    if [[ ! -s "$REGISTRY_FILE" ]]; then
        printf 'Keine eigenen Modelle eingetragen (%s).\n' "$REGISTRY_FILE"
        return 0
    fi

    printf 'Eigene Modelle in %s:\n' "$REGISTRY_FILE"
    local entry
    while IFS= read -r entry || [[ -n "$entry" ]]; do
        [[ -z "$entry" || "$entry" == \#* ]] && continue
        printf '  %-30s %s\n' "$(field "$entry" 1)" "$(field "$entry" 2)"
    done < "$REGISTRY_FILE"
}

#-------------------------------------------------------------------------------
# 10. Ollama steuern
#-------------------------------------------------------------------------------

# Startet den Ollama-Server, falls er noch nicht läuft, und wartet, bis er
# tatsächlich antwortet.
#
# Bevorzugt wird die App unter /Applications gestartet (sie bringt den
# vollständigen Runner mit). Nur wenn die App fehlt, wird auf "ollama serve"
# im Hintergrund ausgewichen.
#
# Rückgabe: 0 = Server ist bereit, 1 = Server antwortet nicht
start_ollama() {
    require_ollama || return 1

    if server_is_running; then
        print_ok "Ollama läuft bereits."
        return 0
    fi

    printf 'Starte Ollama ...\n'
    if [[ -d "/Applications/Ollama.app" ]]; then
        open -ga "/Applications/Ollama.app"
    else
        ollama serve >/dev/null 2>&1 &
    fi

    local i
    for (( i = 0; i < OLLAMA_START_TIMEOUT; i++ )); do
        server_is_running && { print_ok "Ollama ist bereit."; return 0; }
        sleep 1
    done

    print_error "Ollama antwortet nicht auf $API_URL."
    return 1
}

# Beendet Ollama vollständig und gibt damit auch allen belegten
# Arbeitsspeicher frei. Modelle auf der Festplatte bleiben unangetastet.
stop_ollama() {
    printf 'Gebe erst alle Modelle aus dem Speicher frei ...\n'
    free_memory >/dev/null 2>&1 || true

    printf 'Beende Ollama ...\n'
    # Erst die Modell-Runner, dann App und Server - in dieser Reihenfolge
    # bleiben keine verwaisten Prozesse zurück.
    pkill -f 'llama-server' >/dev/null 2>&1 || true
    pkill -x Ollama        >/dev/null 2>&1 || true
    pkill -x ollama        >/dev/null 2>&1 || true
    sleep 1

    if pgrep -x Ollama >/dev/null 2>&1 || pgrep -x ollama >/dev/null 2>&1; then
        print_warning "Es laufen noch Ollama-Prozesse."
    else
        print_ok "Ollama beendet, Speicher freigegeben."
    fi
}

# Lädt ein Modell in den Arbeitsspeicher, ohne einen Chat zu öffnen.
#
# Dazu wird eine leere Anfrage an die API geschickt; "keep_alive" hält das
# Modell danach 30 Minuten im Speicher. Der grosszügige Timeout von zehn
# Minuten ist nötig, weil grosse Modelle beim ersten Laden lange brauchen.
#
# Rückgabe: 0 = geladen, 1 = fehlgeschlagen
load_model() {
    local model
    model="$(select_model "${1:-}")" || return 1

    start_ollama || return 1
    require_jq || return 1
    ensure_model "$model" || return 1

    printf 'Lade %s%s%s in den Arbeitsspeicher ...\n' "$CYAN" "$model" "$RESET"
    if curl -fsS --max-time 600 "$API_URL/api/generate" \
            -d "$(jq -nc --arg m "$model" '{model:$m, prompt:"", keep_alive:"30m"}')" >/dev/null 2>&1; then
        print_ok "$model ist geladen."
        show_loaded_models
    else
        print_error "$model konnte nicht geladen werden."
        return 1
    fi
}

# Lädt alle Modelle der Registry nacheinander in den Arbeitsspeicher.
#
# Vorher wird aufgelistet, wie gross die Modelle sind, und ausdrücklich
# gewarnt: Auf den meisten Macs passen nicht alle gleichzeitig in den RAM.
# Ollama lagert dann auf die SSD aus und wird dadurch sehr langsam.
load_all_models() {
    local entry id size
    for entry in "${MODELS[@]+"${MODELS[@]}"}"; do
        id="$(field "$entry" 1)"
        size="$(ollama list 2>/dev/null \
            | awk -v m="$id" -v m2="${id%:latest}:latest" '$1 == m || $1 == m2 { print $3 }')"
        printf '  %-26s %s\n' "$id" "${size:-noch nicht heruntergeladen}"
    done

    printf '\n%sAlle Modelle zusammen sprengen auf den meisten Macs den RAM.%s\n' "$YELLOW" "$RESET"
    printf '%sOllama lagert dann auf die SSD aus und wird sehr langsam.%s\n\n' "$YELLOW" "$RESET"

    confirm "Trotzdem alle laden" || { printf 'Abgebrochen.\n'; return 0; }

    for entry in "${MODELS[@]+"${MODELS[@]}"}"; do
        load_model "$(field "$entry" 1)"
    done
}

#-------------------------------------------------------------------------------
# 11. KI-Assistenten starten
#-------------------------------------------------------------------------------
#
# Alle Start-Funktionen enden mit "exec": Das Script ersetzt sich selbst durch
# den Assistenten, statt ihn als Kindprozess zu starten. Dadurch verhält sich
# Strg-C so, wie der Benutzer es erwartet, und es bleibt kein überflüssiger
# Shell-Prozess im Hintergrund stehen.

# Trägt alle Registry-Modelle in die OpenCode-Konfiguration ein, damit sie
# dort als "ollama/<modell>" ansprechbar sind.
#
# Die vorhandene Konfiguration wird dabei nicht überschrieben, sondern mit jq
# ergänzt. Geschrieben wird über eine temporäre Datei, damit eine bestehende
# Konfiguration bei einem Fehler nicht beschädigt zurückbleibt.
#
# Rückgabe: 0 = Konfiguration steht, 1 = fehlgeschlagen
ensure_opencode_config() {
    require_jq || return 1

    mkdir -p "$(dirname "$OPENCODE_CONFIG")" \
        || { print_error "Konfigurationsordner für OpenCode liess sich nicht anlegen."; return 1; }
    [[ -f "$OPENCODE_CONFIG" ]] || printf '{}' > "$OPENCODE_CONFIG"

    # Modell-Liste als JSON-Objekt aufbauen: {"<id>": {name, tool_call}, ...}
    local models_json="{}" entry id name
    for entry in "${MODELS[@]+"${MODELS[@]}"}"; do
        id="$(field "$entry" 1)"
        name="$(field "$entry" 2)"
        models_json="$(jq -c --arg id "$id" --arg name "$name" \
            '. + {($id): {name: $name, tool_call: true}}' <<<"$models_json")" || {
            print_error "OpenCode-Modelliste liess sich nicht aufbauen."
            return 1
        }
    done

    local tmp
    tmp="$(mktemp)" || { print_error "Temporäre Datei liess sich nicht anlegen."; return 1; }
    register_temp_file "$tmp"

    if ! jq --argjson models "$models_json" '
            ."$schema" = "https://opencode.ai/config.json"
            | .provider.ollama.npm = "@ai-sdk/openai-compatible"
            | .provider.ollama.options.baseURL = "http://127.0.0.1:11434/v1"
            | .provider.ollama.models = ((.provider.ollama.models // {}) + $models)
        ' "$OPENCODE_CONFIG" > "$tmp"; then
        print_error "OpenCode-Konfiguration ($OPENCODE_CONFIG) ist beschädigt oder nicht lesbar."
        return 1
    fi

    mv "$tmp" "$OPENCODE_CONFIG" || { print_error "OpenCode-Konfiguration liess sich nicht schreiben."; return 1; }
}

# Startet OpenCode gegen ein lokales Ollama-Modell.
run_opencode() {
    local model
    model="$(select_model "${1:-}")" || return 1

    start_ollama || return 1
    ensure_model "$model" || return 1
    require_opencode || return 1
    ensure_opencode_config || return 1

    print_heading "OpenCode – lokal"
    printf 'Modell:    %s%s%s\n' "$CYAN" "$model" "$RESET"
    printf 'Kosten:    keine, alles bleibt auf diesem Mac\n\n'

    exec opencode --model "ollama/$model"
}

# Startet Codex (OpenAI) gegen ein lokales Ollama-Modell.
run_codex() {
    local model
    model="$(select_model "${1:-}")" || return 1

    start_ollama || return 1
    ensure_model "$model" || return 1
    require_codex || return 1

    print_heading "Codex – lokal"
    printf 'Modell:    %s%s%s\n' "$CYAN" "$model" "$RESET"
    printf 'Kontext:   %s\n' "$KI_CONTEXT"
    printf 'Kosten:    keine, alles bleibt auf diesem Mac\n\n'

    export OLLAMA_CONTEXT_LENGTH="$KI_CONTEXT"
    exec ollama launch codex --model "$model"
}

# Startet Claude Code gegen ein lokales Ollama-Modell.
run_claude_local() {
    local model
    model="$(select_model "${1:-}")" || return 1

    start_ollama || return 1
    ensure_model "$model" || return 1
    require_claude || return 1

    print_heading "Claude Code – lokal"
    printf 'Modell:    %s%s%s\n' "$CYAN" "$model" "$RESET"
    printf 'Kontext:   %s\n' "$KI_CONTEXT"
    printf 'Kosten:    keine, alles bleibt auf diesem Mac\n\n'

    export OLLAMA_CONTEXT_LENGTH="$KI_CONTEXT"
    exec ollama launch claude --model "$model"
}

# Startet Claude Code über das Claude-Abo (OAuth-Anmeldung im Schlüsselbund).
#
# ANTHROPIC_API_KEY und ANTHROPIC_BASE_URL werden vorher entfernt: Wären sie
# gesetzt, würde Claude Code sie bevorzugen und statt über das Abo über die
# kostenpflichtige API abrechnen.
run_claude_subscription() {
    require_claude || return 1
    unset ANTHROPIC_API_KEY
    unset ANTHROPIC_BASE_URL

    if ! security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then
        print_error "Kein Claude-Abo-Login gefunden."
        printf 'Anmelden mit:  claude  → dann /login\n'
        return 1
    fi

    print_heading "Claude Code – Abo"
    printf 'Auth:      OAuth-Login aus dem Schlüsselbund\n'
    printf 'Kosten:    über dein Abo, keine API-Kosten\n\n'

    exec claude "$@"
}

# Startet Claude Code gegen die Anthropic-Cloud mit API-Key.
#
# ANTHROPIC_BASE_URL wird entfernt, damit ein von einem lokalen Lauf noch
# gesetzter Wert nicht versehentlich auf den Ollama-Server zeigt.
run_claude_api() {
    require_claude || return 1
    unset ANTHROPIC_BASE_URL

    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        print_error "ANTHROPIC_API_KEY ist nicht gesetzt."
        printf 'Setzen mit:  export ANTHROPIC_API_KEY="sk-ant-..."\n'
        return 1
    fi

    print_heading "Claude Code – Anthropic Cloud"
    printf 'Auth:      API-Key\n'
    printf 'Achtung:   Daten verlassen den Mac, Abrechnung pro Token\n\n'

    exec claude "$@"
}

# Startet Codex direkt gegen die OpenAI-Cloud (eigenes ChatGPT-/API-Login),
# nicht gegen ein lokales Ollama-Modell.
run_codex_cloud() {
    require_codex || return 1

    print_heading "Codex – Cloud"
    printf 'Kosten:    über dein ChatGPT-Abo bzw. deinen API-Key\n\n'

    exec codex "$@"
}

# Startet Antigravity (Google) über sein CLI-Kommando "agy".
run_antigravity() {
    require_agy || return 1

    print_heading "Antigravity"
    exec agy "$@"
}

# Öffnet eine URL im Standard-Browser Safari, für die "Hilfe"-Menüpunkte der
# einzelnen Assistenten.
#
# Rückgabe: 0 = geöffnet, 1 = Safari liess sich nicht starten
open_in_safari() {
    local url="$1"
    open -a Safari "$url" 2>/dev/null || { print_error "Safari liess sich nicht öffnen. URL: $url"; return 1; }
}

# Installiert Claude Code über den offiziellen nativen Installer. Alternative
# zu require_claude() (das über npm installiert) für alle, die die
# eigenständige CLI statt des npm-Pakets bevorzugen.
install_claude_native() {
    print_warning "Installiert Claude Code über den offiziellen Installer (claude.ai/install.sh)."
    confirm "Jetzt ausführen" || return 1

    curl -fsSL https://claude.ai/install.sh | bash || { print_error "Installation fehlgeschlagen."; return 1; }
    hash -r
    print_ok "Claude Code installiert."
}

# Installiert Codex über den offiziellen nativen Installer von OpenAI.
install_codex_native() {
    print_warning "Installiert Codex über den offiziellen Installer (chatgpt.com/codex/install.sh)."
    confirm "Jetzt ausführen" || return 1

    curl -fsSL https://chatgpt.com/codex/install.sh | sh || { print_error "Installation fehlgeschlagen."; return 1; }
    hash -r
    print_ok "Codex installiert."
}

# Installiert die Antigravity-CLI (agy) über den offiziellen Installer.
install_antigravity_native() {
    print_warning "Installiert die Antigravity-CLI (antigravity.google/cli/install.sh)."
    confirm "Jetzt ausführen" || return 1

    curl -fsSL https://antigravity.google/cli/install.sh | bash || { print_error "Installation fehlgeschlagen."; return 1; }
    hash -r
    print_ok "Antigravity-CLI installiert."
}

#-------------------------------------------------------------------------------
# 12. Arbeitsspeicher beobachten und freigeben
#-------------------------------------------------------------------------------
#
# Die vollständige Speicherkontrolle ist hier eingebaut, ein zusätzliches
# ollama-mem.sh wird nicht gebraucht. Keine Funktion in diesem Abschnitt
# löscht jemals ein Modell von der Festplatte - es wird ausschliesslich
# Arbeitsspeicher freigegeben.

# Fragt die Ollama-API ab, welche Modelle gerade geladen sind (Rohdaten).
api_ps() { curl -fsS --max-time 5 "$API_URL/api/ps" 2>/dev/null; }

# Namen aller aktuell geladenen Modelle, einer je Zeile. Ohne jq oder ohne
# laufenden Server bleibt die Ausgabe leer.
loaded_models() {
    have_cmd jq || return 0
    api_ps | jq -r '.models[]?.name' 2>/dev/null
}

# Zeigt alle laufenden Ollama-Prozesse mit Speicherverbrauch und CPU-Last.
#
# Rückgabe: 0 = es läuft etwas, 1 = Ollama läuft nicht
show_processes() {
    print_heading "Prozesse"

    local app helper server runner
    app=$(pgrep -x Ollama 2>/dev/null || true)
    helper=$(pgrep -f 'Ollama.app/Contents/Resources/ollama' 2>/dev/null || true)
    server=$(pgrep -x ollama 2>/dev/null || true)
    runner=$(pgrep -f 'llama-server|ollama[- ]runner' 2>/dev/null || true)

    if [[ -z "$app$helper$server$runner" ]]; then
        printf '%sOllama läuft nicht.%s\n' "$RED" "$RESET"
        return 1
    fi

    printf '%-8s %10s %7s  %s\n' "PID" "RSS" "CPU%" "PROZESS"
    # RSS liefert ps in Kilobyte, deshalb die Umrechnung durch 1048576 auf GB.
    ps -Ao pid,rss,pcpu,comm | awk '
        NR > 1 && tolower($0) ~ /ollama|llama-server/ {
            total += $2
            path = $4; for (i = 5; i <= NF; i++) path = path " " $i
            printf "%-8s %7.2f GB %7s  %s\n", $1, $2/1048576, $3, path
        }
        END { if (total) printf "%-8s %7.2f GB %7s  %s\n", "gesamt", total/1048576, "", "" }
    '

    if server_is_running; then
        printf '\nAPI:    %s%s erreichbar%s\n' "$GREEN" "$API_URL" "$RESET"
    else
        printf '\nAPI:    %s%s NICHT erreichbar%s\n' "$YELLOW" "$API_URL" "$RESET"
    fi
    return 0
}

# Rechnet einen ISO-8601-Zeitstempel in eine verbleibende Restzeit um.
#
# macOS bringt kein "date -d" mit, das ISO-8601 samt Zeitzone zuverlässig
# versteht, deshalb übernimmt das python3. Fehlt python3 oder ist der
# Zeitstempel unbrauchbar, wird "-" ausgegeben statt eine Fehlermeldung.
format_remaining_time() {
    local timestamp="${1:-}"
    [[ -z "$timestamp" ]] && { printf '-'; return 0; }
    have_cmd python3 || { printf '-'; return 0; }

    python3 - "$timestamp" <<'PY' 2>/dev/null || printf '-'
import sys, datetime
try:
    t = datetime.datetime.fromisoformat(sys.argv[1])
    s = int((t - datetime.datetime.now(t.tzinfo)).total_seconds())
    print("abgelaufen" if s <= 0 else (f"{s}s" if s < 90 else f"{s//60}min"))
except Exception:
    print("-")
PY
}

# Zeigt tabellarisch, welche Modelle gerade im Arbeitsspeicher liegen: Grösse
# gesamt, davon im Grafikspeicher, Kontextlänge und Restlaufzeit.
show_loaded_models() {
    print_heading "Im Speicher geladene Modelle"

    if ! server_is_running; then
        printf '%sServer nicht erreichbar – nichts geladen.%s\n' "$DIM" "$RESET"
        return 0
    fi
    require_jq || { print_error "jq wird gebraucht, um das anzuzeigen."; return 1; }

    local json count
    json="$(api_ps)"
    count="$(jq -r '.models | length' <<<"$json" 2>/dev/null || echo 0)"

    if ! is_number "$count" || (( count == 0 )); then
        printf '%sKeine Modelle im Speicher – RAM ist frei.%s\n' "$GREEN" "$RESET"
        return 0
    fi

    printf '%-34s %10s %10s %8s %s\n' "MODELL" "GESAMT" "VRAM" "CTX" "BIS"
    jq -r '.models[] | [
             .name,
             (.size // 0),
             (.size_vram // 0),
             (.context_length // 0),
             (.expires_at // "")
           ] | @tsv' <<<"$json" |
    while IFS=$'\t' read -r name size vram ctx expires; do
        # Wo liegt das Modell? Deckt sich der Grafikspeicher mit der
        # Gesamtgrösse, läuft es vollständig auf der GPU.
        local location remaining
        if [[ "$vram" == "$size" && "$size" != "0" ]]; then location="100% GPU"
        elif [[ "$vram" == "0" ]];                     then location="100% CPU"
        else                                                location="CPU+GPU"; fi

        remaining="$(format_remaining_time "$expires")"

        printf '%-34s %10s %10s %8s %s %s(%s)%s\n' \
            "$name" "$(format_gb "$size")" "$(format_gb "$vram")" "$ctx" \
            "$remaining" "$DIM" "$location" "$RESET"
    done

    local total
    total="$(jq -r '[.models[].size] | add' <<<"$json" 2>/dev/null)"
    printf '\n%sBelegt durch Modelle: %s%s\n' "$BOLD" "$(format_gb "$total")" "$RESET"
}

# Zeigt den Zustand des Systemspeichers: Gesamtgrösse, wirklich freier Anteil,
# benutzter Auslagerungsspeicher und der von macOS gemeldete Speicherdruck.
show_system_memory() {
    print_heading "Systemspeicher"

    local total page_size free_pages free_percent
    total="$(sysctl -n hw.memsize 2>/dev/null)"
    page_size="$(vm_stat 2>/dev/null | awk 'NR==1 { gsub(/[^0-9]/,"",$8); print $8 }')"
    free_pages="$(vm_stat 2>/dev/null | awk '/Pages free/ { gsub(/\./,""); print $3 }')"
    free_percent="$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/ { gsub(/%/,"",$2); print $2 }')"

    printf 'Gesamt:            %s\n' "$(format_gb "${total:-}")"

    # Freien Speicher nur ausrechnen, wenn beide Werte brauchbar sind.
    if is_number "${free_pages:-}" && is_number "${page_size:-}"; then
        printf 'Frei (echt frei):  %s\n' "$(format_gb $(( free_pages * page_size )))"
    else
        printf 'Frei (echt frei):  ?\n'
    fi

    local swap
    swap="$(sysctl -n vm.swapusage 2>/dev/null | sed 's/.*used = \([^ ]*\).*/\1/')"
    printf 'Swap benutzt:      %s\n' "${swap:-?}"

    if is_number "${free_percent:-}"; then
        # Ampelfarbe: unter 30 % gelb, unter 10 % rot.
        local color="$GREEN"
        (( free_percent < 30 )) && color="$YELLOW"
        (( free_percent < 10 )) && color="$RED"
        printf 'Speicherdruck:     %sfrei %s%%%s\n' "$color" "$free_percent" "$RESET"
    fi
}

# Gesamtübersicht: Prozesse, geladene Modelle und Systemspeicher zusammen.
show_memory_status() {
    show_processes
    show_loaded_models
    show_system_memory
    printf '\n'
}

# Wirft ein einzelnes Modell aus dem Arbeitsspeicher. Die Modelldatei auf der
# Festplatte bleibt dabei unangetastet.
#
# Bevorzugt wird die API benutzt ("keep_alive: 0" entlädt sofort). Steht jq
# nicht zur Verfügung oder antwortet die API nicht, wird auf "ollama stop"
# ausgewichen.
#
# Rückgabe: 0 = entladen, 1 = fehlgeschlagen
unload_model() {
    local model="$1"
    printf 'Entlade %s%s%s aus dem Speicher ...\n' "$CYAN" "$model" "$RESET"

    if have_cmd jq && curl -fsS --max-time 10 "$API_URL/api/generate" \
            -d "$(jq -nc --arg m "$model" '{model:$m, keep_alive:0}')" >/dev/null 2>&1; then
        print_ok "$model entladen."
    elif have_cmd ollama && ollama stop "$model" >/dev/null 2>&1; then
        print_ok "$model entladen."
    else
        print_error "$model konnte nicht entladen werden."
        return 1
    fi
}

# Gibt Arbeitsspeicher frei: mit Argument ein bestimmtes Modell, ohne Argument
# alle geladenen Modelle. Löscht niemals etwas von der Festplatte.
free_memory() {
    if [[ -n "${1:-}" ]]; then
        local model
        model="$(resolve_model "$1")" || return 1
        unload_model "$model"
        return
    fi

    local models
    models="$(loaded_models)"
    if [[ -z "$models" ]]; then
        print_ok "Es ist kein Modell geladen."
        return 0
    fi

    local model
    while IFS= read -r model; do
        [[ -n "$model" ]] && unload_model "$model"
    done <<<"$models"
}

# Laufende Speicherüberwachung: aktualisiert die Anzeige alle paar Sekunden,
# bis der Benutzer Strg-C drückt.
#
# Aufruf:  watch_memory [sekunden]   (Vorgabe: 3)
watch_memory() {
    local interval="${1:-3}"
    # Eine unsinnige Angabe würde sleep bei jedem Durchlauf scheitern lassen
    # und die Schleife zur CPU-Bremse machen - deshalb vorher prüfen.
    if ! is_number "$interval" || (( interval < 1 )); then
        print_error "Ungültiges Intervall '$interval'. Erlaubt sind ganze Sekunden ab 1."
        return 1
    fi

    # Strg-C setzt nur ein Abbruchmerkmal, damit die Funktion geordnet endet
    # und der Trap danach wieder zurückgesetzt werden kann.
    local stop=0
    trap 'stop=1' INT

    while (( ! stop )); do
        clear
        printf '%sOllama Speicher – Live (Strg-C beendet)%s   %s\n' \
            "$BOLD" "$RESET" "$(date '+%H:%M:%S')"
        show_memory_status
        sleep "$interval"
    done

    trap - INT
    printf '\n'
    return 0
}

#-------------------------------------------------------------------------------
# 13. Status, Information und Hilfe
#-------------------------------------------------------------------------------

# Zeigt, welche Modelle auf der Festplatte liegen, und darunter die für ki
# eingerichteten Modelle mit ihrer Kurznummer.
show_disk_models() {
    print_heading "Modelle auf der Festplatte"
    printf '%sWird nur mit "ki uninstall <modell>" gelöscht, sonst nie.%s\n\n' "$DIM" "$RESET"

    if have_cmd ollama; then
        ollama list 2>/dev/null || print_error "Ollama antwortet nicht."
    else
        print_error "Ollama ist nicht installiert."
    fi

    print_heading "Eingerichtete Modelle für ki"
    print_model_list
}

# Kurzer, kostenloser Check ohne Netzwerkzugriff: Welche der vier Programme
# fehlen noch? Wird im Hauptmenü und beim Erststart benutzt.
#
# Ausgabe: Namen der fehlenden Programme, durch Leerzeichen getrennt (leer,
# wenn alles vorhanden ist).
missing_components() {
    local missing=()
    have_cmd ollama   || missing+=("Ollama")
    have_cmd claude   || missing+=("Claude Code")
    have_cmd opencode || missing+=("OpenCode")
    have_cmd codex    || missing+=("Codex")
    printf '%s\n' "${missing[*]:-}"
}

# Kurzbeschreibung aller Komponenten und Modelle - erreichbar über "h" im
# Hauptmenü. Die Zeilen sind bewusst so umbrochen, dass sie in ein normal
# breites Terminalfenster passen.
show_info() {
    printf '%s Vorbedingung:%s\n' "$BOLD" "$RESET"
    printf '  Auf einem frisch installierten Mac fehlen die Xcode Command Line Tools (inklusive git).\n'
    printf '  Homebrew installiert sie beim allerersten "setup" automatisch mit.\n'
    printf '  Dabei erscheint einmalig ein macOS-Popup, das manuell bestätigt werden muss.\n'
    printf '  Das dauert je nach Internetverbindung ein paar Minuten, danach läuft "setup" automatisch weiter.\n'
    printf '\n%s Einrichtung:%s\n' "$BOLD" "$RESET"
    printf '  "setup" bzw. Menüpunkt [00] installiert bei Bedarf Homebrew, Node.js (inklusive npm), jq und Ollama,\n'
    printf '  außerdem Claude Code, OpenCode und Codex sowie alle drei LLM-Modelle (Qwen3-Coder 30B,\n'
    printf '  Nemotron 3.5 Lightning und Gemma 4).\n'
    printf '  Bereits installierte Komponenten werden dabei zusätzlich auf verfügbare Updates geprüft.\n'
    printf '\n%s Befehle im Terminal (ki.sh <befehl>):%s\n' "$BOLD" "$RESET"
    printf '  setup                    alles prüfen / installieren\n'
    printf '  code|opencode|codex [1|2|3|modell]  lokal starten\n'
    printf '  claude | api             Claude Code Cloud (Abo / API-Key)\n'
    printf '  codexcloud | agy         Codex bzw. Antigravity direkt ausführen\n'
    printf '  install-claude|-codex|-agy  jeweilige CLI über den nativen Installer\n'
    printf '  help-claude|-codex|-agy  Hilfe-Seite in Safari öffnen\n'
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
    printf '\n%s Information:%s\n' "$BOLD" "$RESET"
    printf ' 🦙 Ollama: Führt KI-Modelle vollständig lokal auf deinem Rechner aus.\n'
    printf ' 🖥️  OpenCode: Open-Source KI-Coding-Assistent, der ebenfalls mit lokalen Ollama-Modellen genutzt werden kann.\n'
    printf ' 🧭 Codex: KI-Coding-Assistent von OpenAI, der ebenfalls mit lokalen Ollama-Modellen genutzt werden kann.\n'
    printf ' 🤖 Claude Code: KI-Entwicklungsassistent von Anthropic, der auch mit lokalen Ollama-Modellen genutzt werden kann.\n'
    printf ' 🌐 Antigravity: KI-Coding-Assistent von Google, gesteuert über sein eigenes CLI-Kommando "agy".\n'
    printf ' 🧠 Qwen3-Coder 30B: Ideal für Softwareentwicklung, Refactoring und große Codeprojekte.\n'
    printf ' ⚡ Nemotron 3.5 Lightning: Ideal für Agenten, Tool-Calling und komplexe Analyseaufgaben.\n'
    printf ' 💎 Gemma 4: Ideal für Dokumentation, Erklärungen und allgemeine Entwicklungsaufgaben.\n'
}

# Ausführliche Hilfe für die Kommandozeile.
show_help() {
    cat <<EOF
${BOLD}ki${RESET} – zentrales Startscript für die lokale KI-Umgebung

Braucht kein anderes Script. Fehlende Programme (Homebrew, Node, jq,
Ollama, Claude Code, OpenCode, Codex) und fehlende Modelle werden bei
Bedarf automatisch installiert bzw. heruntergeladen (mit Rückfrage).
Mit "-y" oder "--yes" laufen alle Rückfragen automatisch durch.

${BOLD}Einrichtung${RESET}
  ki setup [-y]             Alle Komponenten & Modelle prüfen/installieren

${BOLD}Claude Code${RESET}
  ki code [1|2|3|modell]   Mit lokalem Ollama-Modell
  ki claude                claude ausführen (Cloud, eigenes Abo)
  ki api                   claude ausführen mit Anthropic API-Key
  ki install-claude        CLI installieren (offizieller Installer)
  ki help-claude           Hilfe-Seite in Safari öffnen

${BOLD}Codex${RESET}
  ki codex [1|2|3|modell]  Mit lokalem Ollama-Modell
  ki codexcloud            codex ausführen (Cloud, eigenes Login)
  ki install-codex         CLI installieren (offizieller Installer)
  ki help-codex            Hilfe-Seite in Safari öffnen

${BOLD}Antigravity${RESET}
  ki agy                   agy ausführen
  ki install-agy           CLI installieren (offizieller Installer)
  ki help-agy              Hilfe-Seite in Safari öffnen

${BOLD}OpenCode${RESET}
  ki opencode [1|2|3|modell]  Mit lokalem Ollama-Modell

${BOLD}Ollama steuern${RESET}
  ki start                 Ollama starten (installiert es bei Bedarf)
  ki stop                  Ollama beenden, gibt allen Speicher frei
  ki load [1|2|3|modell]   Modell in den Arbeitsspeicher laden
  ki loadall               Alle drei Modelle laden (fragt vorher nach)

${BOLD}Speicher verwalten${RESET}
  ki status                Was läuft, was liegt im RAM, wie voll ist er
  ki ps                    Nur die geladenen Modelle
  ki free [1|2|3|modell]   Modell aus dem Arbeitsspeicher werfen
  ki freeall               Alle Modelle aus dem Arbeitsspeicher werfen
  ki watch [sekunden]      Laufende Speicherüberwachung
  ki models                Modelle auf der Festplatte ansehen
  ki uninstall [1|2|3|modell]  Modell endgültig von der Festplatte löschen

${BOLD}Eigene Modelle (Registry)${RESET}
  ki registry list         Eigene Modelle anzeigen
  ki registry add <id> [Name] [Empfehlung]  Eigenes Modell hinzufügen
  ki registry rm <id>      Eigenes Modell wieder entfernen

${BOLD}Wartung${RESET}
  ki doctor                Gesundheitscheck: installierte Versionen, Server
  ki selfupdate            ki.sh selbst aktualisieren (git pull im Repo)

${BOLD}Sonstiges${RESET}
  ki                       Interaktives Hauptmenü
  ki help                  Diese Hilfe

${BOLD}Modelle${RESET}
$(print_model_list)

"free" und "freeall" geben nur den Arbeitsspeicher frei – beim nächsten
Start wird das Modell einfach wieder von der Platte geladen. Nur "ki
uninstall <modell>" löscht ein Modell endgültig von der Festplatte (mit
Rückfrage).
EOF
}

#-------------------------------------------------------------------------------
# 14. Einrichtung und Wartung
#-------------------------------------------------------------------------------

# Prüft eine einzelne Komponente und meldet dabei ausdrücklich, wenn sie schon
# vorhanden war. Die require_*-Funktionen schweigen in diesem Fall nämlich
# bewusst - beim Setup will man aber Zeile für Zeile sehen, was in Ordnung ist,
# statt einen leeren Abschnitt vor sich zu haben.
#
# Aufruf:  setup_component <anzeigename> <programm> <require-funktion>
# Rückgabe: 0 = einsatzbereit, 1 = fehlt weiterhin
setup_component() {
    local label="$1" cmd="$2" require_fn="$3"

    local was_present=0
    have_cmd "$cmd" && was_present=1

    "$require_fn" || return 1

    # Wurde gerade installiert, hat die require_*-Funktion das bereits
    # gemeldet - dann hier nicht noch einmal.
    (( was_present )) && print_ok "$label ist vorhanden."
    return 0
}

# Prüft und installiert alles auf einmal: Grundprogramme, die drei
# Kommandozeilen-Assistenten und alle Registry-Modelle. Bereits installierte
# Komponenten werden zusätzlich auf Updates geprüft.
#
# Rückgabe: 0 = alles einsatzbereit, 1 = es fehlt noch etwas
run_setup() {
    print_heading "Setup – Grundprogramme"

    # "missing" sammelt alles, was am Ende noch fehlt. Die beiden Zähler
    # werden von den upgrade_*-Funktionen über den dynamischen
    # Geltungsbereich hochgezählt (siehe deren Beschreibung oben).
    local missing=() upgrade_count=0 unchecked_count=0

    setup_component "Homebrew" brew   require_brew   || missing+=("Homebrew")
    setup_component "Node.js"  npm    require_node   || missing+=("Node.js")
    setup_component "jq"       jq     require_jq     || missing+=("jq")
    setup_component "Ollama"   ollama require_ollama || missing+=("Ollama")

    if have_cmd brew; then
        printf '\n%sPrüfe auf Updates%s\n' "$BOLD" "$RESET"
        # "brew update" holt die Paketlisten und dauert oft mehrere Sekunden.
        # Ohne Hinweis sähe der Bildschirm in dieser Zeit aus, als hänge er.
        printf '  %-14s werden geholt ...' "Paketlisten"
        brew update >/dev/null 2>&1 || true
        printf ' fertig\n'

        upgrade_brew_package node       0 "Node.js" node
        upgrade_brew_package jq         0 "jq"      jq
        upgrade_brew_package ollama-app 1 "Ollama"  ollama
    fi

    print_heading "Setup – Ollama-Server"
    start_ollama || missing+=("Ollama-Server")

    print_heading "Setup – KI-Coding-Assistenten"
    setup_component "Claude Code" claude   require_claude   || missing+=("Claude Code")
    setup_component "OpenCode"    opencode require_opencode || missing+=("OpenCode")
    setup_component "Codex"       codex    require_codex    || missing+=("Codex")

    printf '\n%sPrüfe auf Updates%s\n' "$BOLD" "$RESET"
    upgrade_npm_package "@anthropic-ai/claude-code" "Claude Code"
    upgrade_npm_package "@openai/codex"             "Codex"

    print_heading "Setup – Modelle"
    local entry id was_present
    for entry in "${MODELS[@]+"${MODELS[@]}"}"; do
        id="$(field "$entry" 1)"

        # Vorher merken, ob das Modell schon da war: ensure_model lädt bei
        # Bedarf herunter und meldet das selbst, schweigt aber, wenn nichts
        # zu tun war.
        was_present=0
        model_is_on_disk "$id" && was_present=1

        if ensure_model "$id"; then
            (( was_present )) && print_ok "$id ist heruntergeladen."
        else
            missing+=("$id")
        fi
    done

    print_heading "Ergebnis"
    if (( ${#missing[@]} == 0 )); then
        if (( upgrade_count > 0 )); then
            print_ok "Alles installiert, $upgrade_count Update(s) durchgeführt."
        else
            print_ok "Alles installiert und aktuell – keine Updates nötig."
        fi
        # Ehrlich bleiben: Wurde etwas gar nicht geprüft, darf oben nicht der
        # Eindruck entstehen, es sei nachweislich aktuell.
        if (( unchecked_count > 0 )); then
            print_warning "$unchecked_count Komponente(n) konnten nicht auf Updates geprüft werden (siehe oben)."
        fi
        return 0
    fi

    print_error "Noch nicht bereit: ${missing[*]}"
    printf '"%s setup" erneut ausführen, sobald das behoben ist.\n' "$0"
    return 1
}

# Kompakter Gesundheitscheck: Welche Programme sind in welcher Version
# installiert, antwortet der Ollama-Server, ist der Script-Ordner ein
# Git-Repository (Voraussetzung für das Selbst-Update)?
run_doctor() {
    print_heading "ki doctor"

    # Kleine Hilfsfunktion, damit die acht Prüfungen nicht achtmal denselben
    # if/else-Block wiederholen. Der Versionsbefehl wird als Zeichenkette
    # übergeben und nur ausgeführt, wenn das Programm überhaupt existiert.
    check_version() {
        local cmd="$1" label="$2" version_cmd="$3"
        if have_cmd "$cmd"; then
            local version
            version="$(eval "$version_cmd" 2>/dev/null | head -1)"
            print_ok "$label: ${version:-installiert}"
        else
            print_error "$label: nicht installiert"
        fi
    }

    check_version brew     "Homebrew"    "brew --version"
    check_version node     "Node.js"     "node --version"
    check_version npm      "npm"         "npm --version"
    check_version jq       "jq"          "jq --version"
    check_version ollama   "Ollama"      "ollama --version"
    check_version claude   "Claude Code" "claude --version"
    check_version opencode "OpenCode"    "opencode --version"
    check_version codex    "Codex"       "codex --version"

    printf '\n'
    if server_is_running; then
        print_ok "Ollama-Server: erreichbar unter $API_URL"
    else
        print_warning "Ollama-Server: nicht erreichbar unter $API_URL"
    fi

    printf '\n'
    if [[ -d "$SCRIPT_DIR/.git" ]]; then
        print_ok "Script-Ordner: Git-Repository ($SCRIPT_DIR)"
    else
        print_warning "Script-Ordner: kein Git-Repository, \"ki selfupdate\" nicht möglich ($SCRIPT_DIR)"
    fi

    printf '\n'
    if [[ -s "$REGISTRY_FILE" ]]; then
        print_ok "Eigene Modelle: $REGISTRY_FILE"
    else
        print_ok "Eigene Modelle: keine eingetragen"
    fi
}

# Aktualisiert dieses Script per "git pull" im eigenen Repo-Ordner.
#
# Bricht bewusst ab, statt etwas zu überschreiben, wenn der Ordner kein
# Git-Repository ist, git fehlt oder dort noch unkommittete Änderungen liegen.
# "--ff-only" verhindert, dass bei abweichenden Ständen ein Merge-Commit
# entsteht, den niemand erwartet hat.
#
# Rückgabe: 0 = aktuell, 1 = nicht möglich
self_update() {
    if ! have_cmd git; then
        print_error "git ist nicht installiert, Selbst-Update nicht möglich."
        return 1
    fi
    if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
        print_error "$SCRIPT_DIR ist kein Git-Repository, Selbst-Update nicht möglich."
        return 1
    fi
    if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain 2>/dev/null)" ]]; then
        print_error "Unkommittete Änderungen in $SCRIPT_DIR - erst committen oder sichern, dann erneut versuchen."
        return 1
    fi

    print_heading "Selbst-Update"
    printf 'Hole Änderungen für %s ...\n' "$SCRIPT_DIR"
    git -C "$SCRIPT_DIR" pull --ff-only \
        || { print_error "git pull fehlgeschlagen (Netzwerk oder abweichender Stand?)."; return 1; }
    print_ok "ki.sh ist aktuell."
}

#-------------------------------------------------------------------------------
# 15. Interaktives Hauptmenü
#-------------------------------------------------------------------------------

# Wartet auf die Eingabetaste, damit eine Ausgabe gelesen werden kann, bevor
# das Menü den Bildschirm wieder löscht.
press_enter() {
    printf '\n'
    have_tty || return 0
    read -r -p "Weiter mit Enter ..." _ < /dev/tty || true
}

# Lässt den Benutzer aus einer nummerierten Liste auswählen und gibt den
# gewählten Eintrag nach stdout aus. Wird für die beiden Menüpunkte gebraucht,
# die ein Modell aus einer Liste auswählen lassen (RAM und Festplatte).
#
# Aufruf:  choose_from_list <eintrag> [<eintrag> ...]
# Rückgabe: 0 = Auswahl getroffen, 1 = ungültig oder abgebrochen
choose_from_list() {
    (( $# == 0 )) && return 1

    local i=1 item
    for item in "$@"; do
        printf '  %d  %s\n' "$i" "$item" >&2
        i=$(( i + 1 ))
    done

    local choice
    read -r -p $'\nNummer: ' choice < /dev/tty || return 1
    if is_number "$choice" && (( choice >= 1 && choice <= $# )); then
        # Über die Argumentliste indizieren: das n-te Argument ausgeben.
        printf '%s' "${!choice}"
        return 0
    fi

    print_error "Ungültige Auswahl."
    return 1
}

# Das interaktive Hauptmenü. Läuft in einer Schleife, bis "q" gewählt wird
# oder einer der Assistenten per "exec" übernimmt.
#
# Jeder Assistent (Claude Code, Codex, Antigravity) hat einen eigenen
# Abschnitt mit vier gleich aufgebauten Punkten: lokales Modell, Cloud-CLI
# direkt ausführen, CLI installieren, Hilfe-Link.
main_menu() {
    while true; do
        clear
        printf '%s╔═══════════════════════════════════════════════════════════════════════╗%s\n' "$BOLD" "$RESET"
        print_box_line "Lokale KI-Umgebung (Ollama, OpenCode, Codex & Claude Code)"
        print_box_line "by Christian Drapatz (8/2026)"
        printf '%s╚═══════════════════════════════════════════════════════════════════════╝%s\n' "$BOLD" "$RESET"

        # Kopfzeile mit dem aktuellen Zustand von Ollama.
        if server_is_running; then
            local count
            count="$(api_ps | jq -r '.models | length' 2>/dev/null)"
            is_number "${count:-}" || count=0
            printf '\nOllama: %släuft%s, %s Modell(e) im Speicher\n' "$GREEN" "$RESET" "$count"
        else
            printf '\nOllama: %sgestoppt%s\n' "$RED" "$RESET"
        fi

        local missing
        missing="$(missing_components)"
        if [[ -n "$missing" ]]; then
            printf 'Fehlt noch: %s%s%s  →  Option [00]\n' "$YELLOW" "$missing" "$RESET"
        fi

        printf '\n%s Einrichtung%s\n' "$BOLD" "$RESET"
        printf '  [00] 🛠️  Alle Komponenten & Modelle prüfen / installieren\n'

        printf '\n%s Claude Code%s\n' "$BOLD" "$RESET"
        printf '  [01] 🟢 Mit lokalem Modell (kostenlos, privat, Datenschutz)\n'
        printf '  [02] claude ausführen\n'
        printf '  [03] CLI installieren\n'
        printf '  [04] Hilfe\n'

        printf '\n%s Codex%s\n' "$BOLD" "$RESET"
        printf '  [05] 🟢 Mit lokalem Modell (kostenlos, privat, Datenschutz)\n'
        printf '  [06] codex ausführen\n'
        printf '  [07] CLI installieren\n'
        printf '  [08] Hilfe\n'

        printf '\n%s Antigravity%s\n' "$BOLD" "$RESET"
        printf '  [09] agy ausführen\n'
        printf '  [10] CLI installieren\n'
        printf '  [11] Hilfe\n'

        printf '\n%s OpenCode%s\n' "$BOLD" "$RESET"
        printf '  [12] 🟢 Mit lokalem Modell (kostenlos, privat, Datenschutz)\n'

        printf '\n%s Ollama%s\n' "$BOLD" "$RESET"
        printf '  [13] ▶️  Starten\n'
        printf '  [14] 📥 Modell in den Speicher laden\n'
        printf '  [15] ⏹️. Beenden (gibt allen Speicher frei)\n'
        printf '\n%s Speicher%s\n' "$BOLD" "$RESET"
        printf '  [16] 📊 Status: was liegt im Arbeitsspeicher\n'
        printf '  [17] 🗑️  Einzelnes Modell aus dem Speicher werfen\n'
        printf '  [18] 🧹 Alle Modelle aus dem Speicher werfen\n'
        printf '  [19] 💿 Modelle auf der Festplatte ansehen\n'
        printf '  [20] 🗑️  Modell von der Festplatte löschen\n'
        printf '\n%s Wartung%s\n' "$BOLD" "$RESET"
        printf '  [21] 🩺 Gesundheitscheck (doctor)\n'
        printf '  [22] 🔄 ki.sh selbst aktualisieren\n'
        printf '\n  h  ℹ️  Info zu allen Komponenten & Modellen\n'
        printf '  q  ❌ Beenden\n\n'

        local choice
        read -r choice < /dev/tty || exit 0

        # Vor jeder Aktion den Bildschirm löschen, damit die Ausgabe nicht
        # unter dem Menü klebt. Bei leerer Eingabe (nur Enter) wird das Menü
        # einfach neu gezeichnet.
        [[ -n "$choice" ]] && clear

        case "$choice" in
            0|00) run_setup; press_enter ;;

            1) run_claude_local ;;
            2) run_claude_subscription ;;
            3) install_claude_native; press_enter ;;
            4) open_in_safari "https://code.claude.com/docs/en/quickstart"; press_enter ;;

            5) run_codex ;;
            6) run_codex_cloud ;;
            7) install_codex_native; press_enter ;;
            8) open_in_safari "https://learn.chatgpt.com/docs/quickstart"; press_enter ;;

            9) run_antigravity ;;
            10) install_antigravity_native; press_enter ;;
            11) open_in_safari "https://antigravity.google/docs/getting-started"; press_enter ;;

            12) run_opencode ;;

            13) start_ollama; press_enter ;;
            14) local model
                model="$(ask_for_model)" && load_model "$model"
                press_enter ;;
            15) stop_ollama; press_enter ;;

            16) show_memory_status; press_enter ;;

            17) # Ein Modell aus dem Arbeitsspeicher werfen.
                local ram_models=() ram_entry picked
                while IFS= read -r ram_entry; do
                    [[ -n "$ram_entry" ]] && ram_models+=("$ram_entry")
                done < <(loaded_models)

                if (( ${#ram_models[@]} == 0 )); then
                    print_ok "Kein Modell geladen."
                elif picked="$(choose_from_list "${ram_models[@]}")"; then
                    unload_model "$picked"
                fi
                press_enter ;;

            18) free_memory; press_enter ;;
            19) show_disk_models; press_enter ;;

            20) # Ein Modell endgültig von der Festplatte löschen.
                local disk_models=() disk_entry picked
                while IFS= read -r disk_entry; do
                    [[ -n "$disk_entry" ]] && disk_models+=("$disk_entry")
                done < <(ollama list 2>/dev/null | awk 'NR>1 {print $1}')

                if (( ${#disk_models[@]} == 0 )); then
                    print_ok "Keine Modelle auf der Festplatte."
                elif picked="$(choose_from_list "${disk_models[@]}")"; then
                    delete_model "$picked"
                fi
                press_enter ;;

            21) run_doctor; press_enter ;;
            22) self_update; press_enter ;;

            h|H) show_info; press_enter ;;
            q|Q) exit 0 ;;
            *) ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# 16. Befehlsverteilung
#-------------------------------------------------------------------------------
#
# Ohne Argument startet das interaktive Hauptmenü, sonst wird der angegebene
# Befehl ausgeführt. Für die gängigen Befehle gibt es jeweils Zweitnamen
# (z.B. "start" und "up"), damit man nicht raten muss.

case "${1:-menu}" in
    menu|"")
        clear
        # Beim allerersten Start freundlich anbieten, alles einzurichten.
        first_run_missing="$(missing_components)"
        if [[ -n "$first_run_missing" ]]; then
            print_heading "Erststart erkannt"
            printf 'Es fehlen noch Programme für die lokale KI-Umgebung: %s%s%s\n' \
                "$YELLOW" "$first_run_missing" "$RESET"
            if confirm "Jetzt automatisch einrichten"; then
                run_setup
                press_enter
            fi
        fi
        main_menu
        ;;

    # --- Einrichtung -----------------------------------------------------
    setup|install)    run_setup ;;

    # --- Assistenten starten ---------------------------------------------
    code|lokal|local) shift || true; run_claude_local "${1:-}" ;;
    claude|abo)       shift || true; run_claude_subscription "$@" ;;
    api|cloud)        shift || true; run_claude_api "$@" ;;
    opencode|oc)      shift || true; run_opencode "${1:-}" ;;
    codex)            shift || true; run_codex "${1:-}" ;;
    codexcloud)       shift || true; run_codex_cloud "$@" ;;
    agy)              shift || true; run_antigravity "$@" ;;

    # --- CLI-Installer & Hilfe --------------------------------------------
    install-claude)      install_claude_native ;;
    install-codex)       install_codex_native ;;
    install-agy)         install_antigravity_native ;;
    help-claude)         open_in_safari "https://code.claude.com/docs/en/quickstart" ;;
    help-codex)          open_in_safari "https://learn.chatgpt.com/docs/quickstart" ;;
    help-agy)            open_in_safari "https://antigravity.google/docs/getting-started" ;;

    # --- Ollama steuern ---------------------------------------------------
    start|up)         start_ollama ;;
    stop|down)        stop_ollama ;;
    load)             shift || true; load_model "${1:-}" ;;
    loadall)          load_all_models ;;

    # --- Speicher ---------------------------------------------------------
    status)           show_memory_status ;;
    ps)               show_loaded_models ;;
    free|unload)      shift || true; free_memory "${1:-}" ;;
    freeall)          free_memory ;;
    watch)            shift || true; watch_memory "${1:-3}" ;;

    # --- Modelle auf der Festplatte ---------------------------------------
    models|list)      show_disk_models ;;
    uninstall|rm)     shift || true
                      model="$(select_model "${1:-}")" && delete_model "$model" ;;

    # --- Eigene Modelle ---------------------------------------------------
    registry)         shift || true
                      case "${1:-list}" in
                          add)              shift || true; registry_add "${1:-}" "${2:-}" "${3:-}" ;;
                          rm|remove|delete) shift || true; registry_remove "${1:-}" ;;
                          list|"")          registry_list ;;
                          *) print_error "Unbekannt: ki registry ${1:-}. Nutze add|rm|list."; exit 1 ;;
                      esac ;;

    # --- Wartung ----------------------------------------------------------
    doctor)               run_doctor ;;
    selfupdate|update-ki) self_update ;;

    # --- Hilfe ------------------------------------------------------------
    help|-h|--help)   show_help ;;
    *)                print_error "Unbekannter Befehl: $1"; printf '\n'; show_help; exit 1 ;;
esac
