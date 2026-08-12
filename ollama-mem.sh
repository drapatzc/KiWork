#!/usr/bin/env bash
# Totale Speicherkontrolle über Ollama.
#
# Zeigt an, ob Ollama läuft, welche Modelle im RAM/VRAM liegen und erlaubt,
# diese gezielt aus dem Speicher zu entfernen.
#
# WICHTIG: Dieses Script löscht NIEMALS Modelle von der Festplatte.
#          Es wird ausschliesslich der Arbeitsspeicher freigegeben
#          (kein "ollama rm", keine Dateioperationen im Modellverzeichnis).
set -uo pipefail

HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
[[ "$HOST" != http* ]] && HOST="http://$HOST"

# ---------------------------------------------------------------- Hilfsmittel

if [[ -t 1 ]]; then
    B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[31m'; G=$'\033[32m'
    Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
else
    B=""; DIM=""; R=""; G=""; Y=""; C=""; N=""
fi

titel() { printf '\n%s%s%s\n' "$B" "$1" "$N"; printf '%s%s%s\n' "$DIM" "$(printf '─%.0s' $(seq 1 62))" "$N"; }
gb()    { awk -v b="$1" 'BEGIN { printf "%.1f GB", b/1073741824 }'; }

server_laeuft() { curl -fsS --max-time 3 "$HOST" &>/dev/null; }

api_ps() { curl -fsS --max-time 5 "$HOST/api/ps" 2>/dev/null; }

# Namen aller aktuell geladenen Modelle, einer pro Zeile.
geladene_modelle() { api_ps | jq -r '.models[]?.name' 2>/dev/null; }

# ------------------------------------------------------------------- Anzeigen

zeige_prozesse() {
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

zeige_geladene() {
    titel "Im Speicher geladene Modelle"

    if ! server_laeuft; then
        printf '%sServer nicht erreichbar – nichts geladen.%s\n' "$DIM" "$N"
        return
    fi

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

zeige_ram() {
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

zeige_platte() {
    titel "Modelle auf der Festplatte (nur Info – wird nie gelöscht)"

    local dir="${OLLAMA_MODELS:-$HOME/.ollama/models}"
    if [[ -d "$dir" ]]; then
        printf 'Verzeichnis:  %s\n' "$dir"
        printf 'Belegung:     %s\n\n' "$(du -sh "$dir" 2>/dev/null | cut -f1)"
    fi
    ollama list 2>/dev/null || printf '%sollama list nicht verfügbar.%s\n' "$DIM" "$N"
}

# ------------------------------------------------------------------- Aktionen

# Entlädt ein Modell aus dem Speicher. Die Modelldatei bleibt unangetastet.
entlade() {
    local modell="$1"
    printf 'Entlade %s%s%s aus dem Speicher ...\n' "$C" "$modell" "$N"

    # keep_alive 0 weist den Server an, das Modell sofort freizugeben.
    if curl -fsS --max-time 10 "$HOST/api/generate" \
            -d "$(jq -nc --arg m "$modell" '{model:$m, keep_alive:0}')" &>/dev/null; then
        printf '%s✓ %s entladen.%s\n' "$G" "$modell" "$N"
    elif ollama stop "$modell" &>/dev/null; then
        printf '%s✓ %s entladen.%s\n' "$G" "$modell" "$N"
    else
        printf '%s✗ %s konnte nicht entladen werden.%s\n' "$R" "$modell" "$N"
        return 1
    fi
}

entlade_alle() {
    local modelle
    modelle=$(geladene_modelle)

    if [[ -z "$modelle" ]]; then
        printf '%sEs ist kein Modell geladen.%s\n' "$G" "$N"
        return
    fi

    while read -r m; do
        [[ -n "$m" ]] && entlade "$m"
    done <<<"$modelle"

    sleep 1
    zeige_geladene
}

# Beendet den Server komplett – gibt allen Speicher frei, Modelle bleiben auf der Platte.
server_stoppen() {
    printf 'Gebe erst alle Modelle frei ...\n'
    entlade_alle &>/dev/null || true

    printf 'Beende Ollama ...\n'
    pkill -f 'llama-server' &>/dev/null || true
    pkill -x Ollama        &>/dev/null || true
    pkill -x ollama        &>/dev/null || true
    sleep 1

    if pgrep -x Ollama &>/dev/null || pgrep -x ollama &>/dev/null; then
        printf '%sEs laufen noch Ollama-Prozesse.%s\n' "$Y" "$N"
    else
        printf '%s✓ Ollama beendet, Speicher freigegeben.%s\n' "$G" "$N"
    fi
}

status() {
    zeige_prozesse
    zeige_geladene
    zeige_ram
    printf '\n'
}

live() {
    trap 'printf "\n"; exit 0' INT
    while true; do
        clear
        printf '%sOllama Speicher – Live (Strg-C beendet)%s   %s\n' \
            "$B" "$N" "$(date '+%H:%M:%S')"
        status
        sleep "${1:-3}"
    done
}

menue() {
    while true; do
        clear
        status
        printf '%s Aktionen (Arbeitsspeicher):%s\n' "$B" "$N"
        printf '  1  Einzelnes Modell aus dem Speicher entfernen\n'
        printf '  2  Alle Modelle aus dem Speicher entfernen\n'
        printf '  3  Ollama komplett beenden\n'
        printf '  4  Festplattenbelegung ansehen (löscht nichts)\n'
        printf '  5  Aktualisieren\n'
        printf '  q  Beenden\n\n'
        read -r -p "Auswahl: " wahl

        case "$wahl" in
            1)
                liste=()
                while IFS= read -r zeile; do
                    [[ -n "$zeile" ]] && liste+=("$zeile")
                done < <(geladene_modelle)
                if (( ${#liste[@]} == 0 )); then
                    printf '%sKein Modell geladen.%s\n' "$G" "$N"
                else
                    printf '\n'
                    local i=1
                    for m in "${liste[@]}"; do printf '  %d  %s\n' "$i" "$m"; ((i++)); done
                    read -r -p $'\nNummer: ' nr
                    if [[ "$nr" =~ ^[0-9]+$ ]] && (( nr >= 1 && nr <= ${#liste[@]} )); then
                        entlade "${liste[nr-1]}"
                    else
                        printf '%sUngültige Auswahl.%s\n' "$R" "$N"
                    fi
                fi
                read -r -p $'\nWeiter mit Enter ...' _ ;;
            2) entlade_alle;   read -r -p $'\nWeiter mit Enter ...' _ ;;
            3) server_stoppen; read -r -p $'\nWeiter mit Enter ...' _ ;;
            4) zeige_platte;   read -r -p $'\nWeiter mit Enter ...' _ ;;
            5) ;;
            q|Q) exit 0 ;;
            *) ;;
        esac
    done
}

hilfe() {
    cat <<EOF
${B}ollama-mem.sh${N} – totale Kontrolle über den Ollama-Speicher

  status            Läuft Ollama? Was liegt im Speicher? (Standard)
  ps                Nur die geladenen Modelle
  free <modell>     Ein Modell aus dem Arbeitsspeicher entfernen
  freeall           Alle Modelle aus dem Arbeitsspeicher entfernen
  stop              Ollama komplett beenden (gibt allen Speicher frei)
  disk              Festplattenbelegung anzeigen (nur Info)
  watch [sek]       Laufende Überwachung, Standard 3 Sekunden
  menu              Interaktives Menü
  help              Diese Hilfe

Es wird nie ein Modell von der Festplatte gelöscht – ausschliesslich
der Arbeitsspeicher wird freigegeben. Entladene Modelle werden beim
nächsten Aufruf einfach wieder von der Platte geladen.
EOF
}

# ---------------------------------------------------------------------- Start

case "${1:-status}" in
    status|"")  status ;;
    ps|list)    zeige_geladene; printf '\n' ;;
    free|unload)
        if [[ -z "${2:-}" ]]; then
            printf '%sModellname fehlt:  %s free <modell>%s\n' "$R" "$0" "$N"
            printf '\nGeladen:\n'; geladene_modelle | sed 's/^/  /'
            exit 1
        fi
        entlade "$2" ;;
    freeall|unloadall) entlade_alle ;;
    stop|kill)         server_stoppen ;;
    disk)              zeige_platte; printf '\n' ;;
    watch)             live "${2:-3}" ;;
    menu|-i)           menue ;;
    help|-h|--help)    hilfe ;;
    *)  printf '%sUnbekannter Befehl: %s%s\n\n' "$R" "$1" "$N"; hilfe; exit 1 ;;
esac
