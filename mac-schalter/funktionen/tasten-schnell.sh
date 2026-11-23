GRUPPE="Tastatur"
BESCHREIBUNG="Schnelle Tastenwiederholung"
# Wirkt nach dem nächsten Ab- und Anmelden.

zustand() {
    local wert
    wert=$(defaults read NSGlobalDomain KeyRepeat 2>/dev/null) || { print aus; return }
    (( wert <= 2 )) && print an || print aus
}
einschalten() {
    defaults write NSGlobalDomain KeyRepeat -int 2
    defaults write NSGlobalDomain InitialKeyRepeat -int 15
}
ausschalten() {
    defaults delete NSGlobalDomain KeyRepeat 2>/dev/null
    defaults delete NSGlobalDomain InitialKeyRepeat 2>/dev/null
    return 0
}
