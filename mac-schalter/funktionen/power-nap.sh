GRUPPE="System"
BESCHREIBUNG="Power Nap"

zustand() {
    local wert=$(pmset_wert powernap)
    [[ -z $wert ]] && { print "–"; return }
    [[ $wert == 1 ]] && print an || print aus
}

einschalten() { sudo pmset -a powernap 1 }
ausschalten() { sudo pmset -a powernap 0 }
