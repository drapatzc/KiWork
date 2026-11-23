# Startton beim Einschalten des Macs (NVRAM-Variable StartupMute).

GRUPPE="System"
BESCHREIBUNG="Startton beim Hochfahren"

zustand() {
    [[ $(nvram StartupMute 2>/dev/null) == *%01* ]] && print aus || print an
}

einschalten() { sudo nvram StartupMute=%00 }
ausschalten() { sudo nvram StartupMute=%01 }
