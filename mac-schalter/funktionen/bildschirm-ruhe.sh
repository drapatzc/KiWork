# Bildschirm nach einer Wartezeit ausschalten (pmset displaysleep).
# Die Minuten beim Einschalten lassen sich mit SCHALTER_BILDSCHIRM_MINUTEN ändern.

GRUPPE="System"
BESCHREIBUNG="Bildschirm schaltet sich ab"

zustand() {
    local wert=$(pmset_wert displaysleep)
    [[ -z $wert ]] && { print "–"; return }
    [[ $wert == 0 ]] && print aus || print an
}

einschalten() { sudo pmset -a displaysleep ${SCHALTER_BILDSCHIRM_MINUTEN:-10} }
ausschalten() { sudo pmset -a displaysleep 0 }
