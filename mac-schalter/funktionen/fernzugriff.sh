# Fernzugriff: Der Mac schläft nie und Claude Code Remote Control läuft dauerhaft
# im Hintergrund. Steuern über die Claude-App (iPhone/iPad) oder claude.ai/code.
#
# Einschalten:
#   - pmset: sleep 0, disablesleep 1, autorestart 1 (Neustart nach Stromausfall), womp 1
#   - LaunchAgent startet "claude remote-control" in einer screen-Sitzung und
#     startet es neu, falls es abstürzt oder sich beendet.
# Ausschalten: LaunchAgent entfernen und die vorherigen pmset-Werte zurückschreiben.
#
# Arbeitsordner: SCHALTER_FERN_ORDNER (Standard ~/GIT-Home)
# Lokal mitschauen: screen -r claude-fern   (wieder lösen mit Ctrl-A, dann D)
# Protokoll: ~/.config/mac-schalter/fernzugriff.log

GRUPPE="Entwickler"
BESCHREIBUNG="Fernzugriff mit Remote Control"

FERN_LABEL="de.mac-schalter.claude-fernzugriff"
FERN_PLIST="$HOME/Library/LaunchAgents/$FERN_LABEL.plist"
FERN_DATEN="$HOME/.config/mac-schalter"
FERN_VORHER="$FERN_DATEN/fernzugriff-vorher"
FERN_LOG="$FERN_DATEN/fernzugriff.log"
FERN_ORDNER="${SCHALTER_FERN_ORDNER:-$HOME/GIT-Home}"

fern_dienst_laeuft() {
    launchctl print "gui/$UID/$FERN_LABEL" >/dev/null 2>&1
}

zustand() {
    local schlaf_aus=$(pmset -g | awk '$1 == "SleepDisabled" { print $2 }')
    [[ $schlaf_aus == 1 ]] && fern_dienst_laeuft && print an || print aus
}

einschalten() {
    local claude_bin=${commands[claude]:-$HOME/.local/bin/claude}
    [[ -x $claude_bin ]] || { print -u2 "claude nicht gefunden"; return 1 }
    [[ -d $FERN_ORDNER ]] || { print -u2 "Arbeitsordner fehlt: $FERN_ORDNER"; return 1 }
    mkdir -p "$FERN_DATEN" "$HOME/Library/LaunchAgents"

    # Vorherige Energiewerte nur beim ersten Einschalten sichern.
    if [[ ! -f $FERN_VORHER ]]; then
        local schlaf_aus=$(pmset -g | awk '$1 == "SleepDisabled" { print $2 }')
        print "sleep=$(pmset_wert sleep) disablesleep=${schlaf_aus:-0} autorestart=$(pmset_wert autorestart)" \
            > "$FERN_VORHER"
    fi

    sudo pmset -a sleep 0 disablesleep 1 autorestart 1 womp 1 || return 1

    local name="$(scutil --get ComputerName 2>/dev/null || hostname -s) Fernzugriff"
    cat > "$FERN_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$FERN_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/screen</string>
        <string>-DmS</string>
        <string>claude-fern</string>
        <string>$claude_bin</string>
        <string>remote-control</string>
        <string>--name</string>
        <string>$name</string>
    </array>
    <key>WorkingDirectory</key><string>$FERN_ORDNER</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>TERM</key><string>xterm-256color</string>
        <key>LANG</key><string>de_DE.UTF-8</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>StandardOutPath</key><string>$FERN_LOG</string>
    <key>StandardErrorPath</key><string>$FERN_LOG</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$UID/$FERN_LABEL" 2>/dev/null
    launchctl bootstrap "gui/$UID" "$FERN_PLIST" || return 1
    print "Remote Control läuft. In der Claude-App die Sitzung \"$name\" öffnen."
}

ausschalten() {
    launchctl bootout "gui/$UID/$FERN_LABEL" 2>/dev/null
    rm -f "$FERN_PLIST"

    local -A alt
    local paar
    if [[ -f $FERN_VORHER ]]; then
        for paar in $(<"$FERN_VORHER"); do alt[${paar%%=*}]=${paar#*=}; done
    fi
    sudo pmset -a sleep "${alt[sleep]:-10}" disablesleep "${alt[disablesleep]:-0}" \
        autorestart "${alt[autorestart]:-0}" || return 1
    rm -f "$FERN_VORHER"
}
