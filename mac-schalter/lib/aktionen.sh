# Aktionen: Befehle, die sofort starten (rechte Spalte im Menü, "schalter start <name>").
# Hervorgegangen aus dem früheren xcodeclean.sh.
#
# Eintrag in AKTIONEN:  "name|Gruppe|Kurzbeschreibung|Rückfrage"
#   Rückfrage leer  = startet sofort
#   Rückfrage gesetzt = kritischer Befehl, das Menü fragt vorher in einem Dialog nach
# Zu jedem Namen gehört eine Funktion aktion_<name>, mit "_" statt "-".
# Es werden nur Werkzeuge verwendet, die Apple mitliefert.

AKTIONEN=(
    "xcode-beenden|Xcode|Xcode beenden|"
    "xcode-starten|Xcode|Xcode starten|"
    "xcode-neustart|Xcode|Xcode neu starten|"
    "xcode-frisch|Xcode|DerivedData leeren und Neustart|"
    "xcode-wahl|Xcode|Aktives Xcode wählen|"
    "index|Xcode|Index neu aufbauen|"
    "dienste|Xcode|Hängende Dienste beenden|"

    "derived-data|Caches|DerivedData leeren|"
    "module-cache|Caches|Module-Cache leeren|"
    "paket-cache|Caches|Swift-Package-Caches leeren|"
    "xcode-cache|Caches|Xcode-Cache leeren|"
    "previews|Caches|SwiftUI-Previews zurücksetzen|"
    "device-support|Caches|DeviceSupport löschen|Die Symboldateien aller angeschlossenen Geräte werden gelöscht. Xcode lädt sie beim nächsten Anschließen neu, das dauert einige Minuten pro Gerät."
    "grossputz|Caches|Großputz: alle Caches|Xcode wird beendet. Danach werden alle Caches geleert und die Simulatoren aufgeräumt. Der nächste Build dauert deutlich länger."

    "sim-stop|Simulatoren|Alle herunterfahren|"
    "sim-alt|Simulatoren|Nicht nutzbare löschen|"
    "sim-cache|Simulatoren|Simulator-Cache leeren|"
    "sim-statusleiste|Simulatoren|Statusleiste 9:41 setzen|"
    "sim-statusleiste-aus|Simulatoren|Statusleiste zurücksetzen|"
    "sim-laufzeiten|Simulatoren|Laufzeiten anzeigen|"
    "sim-laufzeiten-alt|Simulatoren|Veraltete Laufzeiten löschen|Veraltete und unbrauchbare Simulator-Laufzeiten werden gelöscht. Sie lassen sich nur durch erneutes Laden in Xcode zurückholen."
    "sim-reset|Simulatoren|Alle zurücksetzen|Alle Simulatoren werden auf den Werkszustand gesetzt. Installierte Apps und ihre Daten in den Simulatoren gehen verloren."

    "speicher|Mac|Speicherbelegung anzeigen|"
    "papierkorb|Mac|Papierkorb leeren|"
    "schnappschuesse|Mac|Lokale Schnappschüsse löschen|Alle lokalen Time-Machine-Schnappschüsse auf der internen Festplatte werden gelöscht. Die Backups auf dem Time-Machine-Laufwerk bleiben erhalten."
    "dns|Mac|DNS-Cache leeren|"
    "quicklook|Mac|Quick Look zurücksetzen|"
    "finder-dock|Mac|Finder und Dock neu starten|"
    "updates|Mac|Softwareupdates anzeigen|"
)

ENTW="$HOME/Library/Developer"
DERIVED="$ENTW/Xcode/DerivedData"

# ---------------------------------------------------------------- Hilfen

# Größe eines Ordners, z. B. "4,3G"; leer, wenn er fehlt.
groesse_von() { [[ -e $1 ]] && du -sh "$1" 2>/dev/null | cut -f1 }

# Ordner löschen und anzeigen, wie viel frei wurde.
ordner_loeschen() {
    local p=$1 g
    if [[ -z $p || $p == / || $p == $HOME ]]; then
        print "  Abgebrochen: unsicherer Pfad »$p«"; return 1
    fi
    if [[ ! -e $p ]]; then
        print "  nicht vorhanden: ${p/#$HOME/~}"; return 0
    fi
    g=$(groesse_von "$p")
    rm -rf -- "$p"
    print "  gelöscht: ${p/#$HOME/~} ($g)"
}

# Rückfrage im Text (nur außerhalb des Menü-Dialogs gebraucht).
bestaetigen() {
    local a
    read -r "a?$1 [j/N] "
    [[ $a == (j|J|ja|Ja|JA|y|Y) ]] && return 0
    print "  Übersprungen."; return 1
}

xcode_laeuft() { pgrep -x Xcode >/dev/null 2>&1 }

# Pfad des aktiven Xcode (aus xcode-select), sonst /Applications/Xcode.app.
xcode_app() {
    local p=$(xcode-select -p 2>/dev/null)
    p=${p%/Contents/Developer}
    [[ $p == *.app ]] && print -r -- "$p" || print -r -- "/Applications/Xcode.app"
}

# Kennungen aller laufenden Simulatoren, eine pro Zeile.
sim_laufende() {
    xcrun simctl list devices booted 2>/dev/null | grep '(Booted)' \
        | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'
}

# ---------------------------------------------------------------- Xcode

aktion_xcode_beenden() {
    if ! xcode_laeuft; then print "Xcode läuft nicht."; return 0; fi
    print "Xcode wird beendet …"
    osascript -e 'quit app "Xcode"' >/dev/null 2>&1
    local i=0
    while xcode_laeuft && (( i < 30 )); do sleep 1; (( i++ )); done
    if xcode_laeuft; then
        print "  Xcode reagiert nicht (vielleicht ist ein Dialog offen)."
        if bestaetigen "  Xcode hart beenden? Nicht gesicherte Änderungen gehen verloren."; then
            killall -9 Xcode 2>/dev/null; sleep 1
        else
            return 1
        fi
    fi
    print "Xcode beendet."
}

aktion_xcode_starten() {
    local app=$(xcode_app)
    print "Xcode wird gestartet: $app"
    open -a "$app" || print "  Konnte $app nicht öffnen."
}

aktion_xcode_neustart() { aktion_xcode_beenden && aktion_xcode_starten }

aktion_xcode_frisch() {
    aktion_xcode_beenden || return 1
    aktion_derived_data
    aktion_xcode_starten
}

# Aktives Xcode für xcodebuild, xcrun und Kommandozeile wählen (sudo xcode-select).
aktion_xcode_wahl() {
    print "Aktiv: $(xcode_app)"
    print "Installierte Xcode-Versionen:"
    local -a apps
    local a n i=1
    for a in /Applications/Xcode*.app(N) $HOME/Applications/Xcode*.app(N); do
        [[ -d $a/Contents/Developer ]] || continue
        apps+=("$a")
        print "  $i) $a"
        (( i++ ))
    done
    (( ${#apps} == 0 )) && { print "  keine gefunden."; return 1 }
    read -r "n?Nummer (leer = abbrechen): "
    [[ $n == <-> ]] || { print "  Abgebrochen."; return 0 }
    (( n >= 1 && n <= ${#apps} )) || { print "  Ungültige Nummer."; return 1 }
    sudo xcode-select -s "${apps[n]}/Contents/Developer" && print "  Aktiv: $(xcode_app)"
}

aktion_index() {
    print "Index neu aufbauen (bei falscher Autovervollständigung, roten Fehlern ohne Grund) …"
    local lief=0 d
    xcode_laeuft && lief=1
    aktion_xcode_beenden || return 1
    for d in $DERIVED/*/Index.noindex(N/) $DERIVED/*/Index(N/); do ordner_loeschen "$d"; done
    (( lief )) && aktion_xcode_starten
    return 0
}

aktion_dienste() {
    print "Hängende Hilfsprozesse beenden (SourceKit, Build-Dienst, Previews) …"
    local p
    for p in SourceKitService sourcekit-lsp XCBBuildService SWBBuildService \
             com.apple.dt.SKAgent XCPreviewAgent PreviewShell; do
        if pgrep -x "$p" >/dev/null 2>&1; then
            killall -9 "$p" 2>/dev/null && print "  beendet: $p"
        fi
    done
    print "  Xcode startet die Dienste bei Bedarf selbst neu."
}

# ---------------------------------------------------------------- Caches

aktion_derived_data() {
    print "DerivedData löschen (Build-Ergebnisse, Index, Module) …"
    xcode_laeuft && print "  Hinweis: Xcode läuft. Besser »DerivedData leeren und Neustart« nehmen."
    ordner_loeschen "$DERIVED"
}

aktion_module_cache() {
    print "Module-Cache löschen …"
    ordner_loeschen "$DERIVED/ModuleCache.noindex"
    ordner_loeschen "$ENTW/Xcode/ModuleCache"
    ordner_loeschen "$(getconf DARWIN_USER_CACHE_DIR)clang/ModuleCache"
}

aktion_paket_cache() {
    print "Swift-Package-Caches löschen (Pakete werden beim nächsten Build neu geladen) …"
    ordner_loeschen "$HOME/Library/Caches/org.swift.swiftpm"
    ordner_loeschen "$HOME/Library/org.swift.swiftpm"
    local d
    for d in $DERIVED/*/SourcePackages(N/); do ordner_loeschen "$d"; done
}

aktion_xcode_cache() {
    print "Allgemeinen Xcode-Cache löschen …"
    ordner_loeschen "$HOME/Library/Caches/com.apple.dt.Xcode"
}

aktion_previews() {
    print "SwiftUI-Previews zurücksetzen …"
    xcrun simctl --set previews delete all >/dev/null 2>&1
    ordner_loeschen "$ENTW/Xcode/UserData/Previews"
}

aktion_device_support() {
    print "DeviceSupport löschen (Symboldateien angeschlossener Geräte) …"
    local d gefunden=0
    for d in $ENTW/Xcode/*" DeviceSupport"(N/); do ordner_loeschen "$d"; gefunden=1; done
    (( gefunden )) || print "  nichts vorhanden."
}

aktion_grossputz() {
    print "Großputz: Xcode beenden, alle Caches leeren, Simulatoren aufräumen."
    local lief=0
    xcode_laeuft && lief=1
    aktion_xcode_beenden || return 1
    aktion_derived_data
    aktion_module_cache
    aktion_paket_cache
    aktion_xcode_cache
    aktion_previews
    aktion_sim_stop
    aktion_sim_alt
    aktion_sim_cache
    (( lief )) && aktion_xcode_starten
    print "Großputz fertig."
}

# ---------------------------------------------------------------- Simulatoren

aktion_sim_stop() {
    print "Alle Simulatoren herunterfahren …"
    xcrun simctl shutdown all 2>/dev/null
    print "  erledigt."
}

aktion_sim_alt() {
    print "Simulatoren ohne passende Laufzeit löschen …"
    xcrun simctl delete unavailable && print "  erledigt."
}

aktion_sim_cache() {
    print "Simulator-Cache löschen …"
    ordner_loeschen "$ENTW/CoreSimulator/Caches"
}

# Saubere Statusleiste für App-Store-Bildschirmfotos (alle laufenden Simulatoren).
aktion_sim_statusleiste() {
    local -a ids
    local id
    ids=($(sim_laufende))
    (( ${#ids} == 0 )) && { print "Kein Simulator läuft. Bitte zuerst einen starten."; return 1 }
    print "Statusleiste setzen: 9:41, volles WLAN und Mobilfunk, Akku voll …"
    for id in $ids; do
        xcrun simctl status_bar "$id" override --time "9:41" \
            --dataNetwork wifi --wifiMode active --wifiBars 3 \
            --cellularMode active --cellularBars 4 --operatorName '' \
            --batteryState charged --batteryLevel 100 && print "  gesetzt: $id"
    done
}

aktion_sim_statusleiste_aus() {
    local -a ids
    local id
    ids=($(sim_laufende))
    (( ${#ids} == 0 )) && { print "Kein Simulator läuft."; return 0 }
    print "Statusleiste zurücksetzen …"
    for id in $ids; do
        xcrun simctl status_bar "$id" clear && print "  zurückgesetzt: $id"
    done
}

aktion_sim_laufzeiten() {
    print "Installierte Simulator-Laufzeiten:"
    xcrun simctl runtime list
    print
    print "Diese würde »Veraltete Laufzeiten löschen« entfernen (Probelauf, nichts wird gelöscht):"
    xcrun simctl runtime delete --outdated --dry-run 2>&1 | sed 's/^/  /'
    xcrun simctl runtime delete --unusable --dry-run 2>&1 | sed 's/^/  /'
}

aktion_sim_laufzeiten_alt() {
    print "Veraltete und unbrauchbare Simulator-Laufzeiten löschen …"
    xcrun simctl runtime delete --outdated
    xcrun simctl runtime delete --unusable
    print "  erledigt."
}

aktion_sim_reset() {
    print "Alle Simulatoren auf Werkszustand zurücksetzen …"
    xcrun simctl shutdown all 2>/dev/null
    xcrun simctl erase all && print "  erledigt."
}

# ---------------------------------------------------------------- Mac

aktion_speicher() {
    print "Speicherbelegung durch Xcode:"
    local p g
    for p in "$DERIVED" \
             "$ENTW/Xcode/Archives" \
             "$ENTW/Xcode/iOS DeviceSupport" \
             "$ENTW/Xcode/watchOS DeviceSupport" \
             "$ENTW/Xcode/macOS DeviceSupport" \
             "$ENTW/Xcode/UserData/Previews" \
             "$ENTW/CoreSimulator/Devices" \
             "$ENTW/CoreSimulator/Caches" \
             "$HOME/Library/Caches/com.apple.dt.Xcode" \
             "$HOME/Library/Caches/org.swift.swiftpm" \
             "$HOME/.Trash"; do
        g=$(groesse_von "$p")
        [[ -n $g ]] && printf "  %-8s %s\n" "$g" "${p/#$HOME/~}"
    done
    print
    print "  Archive werden bewusst nie gelöscht: Sie enthalten die dSYM-Dateien"
    print "  für Absturzberichte. Aufräumen in Xcode unter Window › Organizer."
    print
    print "Freier Platz auf der Festplatte: $(df -h / | awk 'NR==2 {print $4}')"
    print "Aktives Xcode: $(xcode_app)"
}

# Papierkorb leeren, bewusst ohne Rückfrage (Nutzervorgabe).
aktion_papierkorb() {
    print "Papierkorb leeren …"
    local g=$(groesse_von "$HOME/.Trash")
    if osascript -e 'tell application "Finder" to empty trash' >/dev/null 2>&1; then
        print "  geleert (${g:-0B})."
    elif find "$HOME/.Trash" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; then
        print "  geleert (${g:-0B})."
    else
        print "  Nicht möglich. Das Terminal braucht »Festplattenvollzugriff«"
        print "  (Systemeinstellungen › Datenschutz & Sicherheit) oder die Erlaubnis, den Finder zu steuern."
    fi
}

aktion_schnappschuesse() {
    print "Lokale Time-Machine-Schnappschüsse:"
    local liste=$(tmutil listlocalsnapshots / 2>/dev/null | grep -v '^Snapshots')
    if [[ -z $liste ]]; then print "  keine vorhanden."; return 0; fi
    print -r -- "$liste" | sed 's/^/  /'
    sudo tmutil deletelocalsnapshots / && print "  gelöscht."
}

aktion_dns() {
    print "DNS-Cache leeren (hilft, wenn Webseiten oder Server nicht gefunden werden) …"
    sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder && print "  erledigt."
}

aktion_quicklook() {
    print "Quick Look zurücksetzen (Vorschauen und Miniaturen) …"
    qlmanage -r >/dev/null 2>&1
    qlmanage -r cache >/dev/null 2>&1
    print "  erledigt."
}

aktion_finder_dock() {
    print "Finder und Dock neu starten …"
    killall Finder 2>/dev/null
    killall Dock 2>/dev/null
    print "  erledigt (starten automatisch neu)."
}

aktion_updates() {
    print "Verfügbare Softwareupdates (nur Anzeige, es wird nichts installiert) …"
    softwareupdate -l 2>&1 | sed 's/^/  /'
}
