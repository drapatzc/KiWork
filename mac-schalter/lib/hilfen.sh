# Gemeinsame Hilfsfunktionen für alle Funktionsdateien.
# Wird vor jeder Funktionsdatei geladen.

# Liest einen Bool-Wert aus "defaults" und gibt "an" oder "aus" aus.
#   $1 = Domain, $2 = Schlüssel, $3 = Standard, falls nicht gesetzt (an/aus)
defaults_zustand() {
    local wert
    wert=$(defaults read "$1" "$2" 2>/dev/null) || { print -r -- "${3:-aus}"; return }
    [[ $wert == 1 || $wert == true || $wert == YES ]] && print an || print aus
}

# Liest einen Wert aus "pmset -g" (aktuell gültige Energieeinstellungen).
#   $1 = Name, z. B. displaysleep. Gibt leer aus, wenn es den Wert nicht gibt.
pmset_wert() {
    pmset -g | awk -v k="$1" '$1 == k { print $2; exit }'
}

# Gibt den Gerätenamen der WLAN-Schnittstelle aus (z. B. en0), leer wenn keine.
wlan_geraet() {
    networksetup -listallhardwareports \
        | awk '/^Hardware Port: (Wi-Fi|WLAN|AirPort)/ { getline; print $2; exit }'
}
