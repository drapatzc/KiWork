# macOS speichert hier "DSDontWriteNetworkStores", deshalb ist die Logik umgedreht.
# Wirkt nach dem nächsten Abmelden oder Neustart.

GRUPPE="Finder"
BESCHREIBUNG=".DS_Store auf Netzlaufwerken"

zustand() {
    [[ $(defaults_zustand com.apple.desktopservices DSDontWriteNetworkStores aus) == an ]] \
        && print aus || print an
}
einschalten() { defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool false }
ausschalten() { defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true }
