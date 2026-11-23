# macOS speichert hier "DSDontWriteUSBStores", deshalb ist die Logik umgedreht.
# Wirkt nach dem nächsten Abmelden oder Neustart.

GRUPPE="Finder"
BESCHREIBUNG=".DS_Store auf USB-Laufwerken"

zustand() {
    [[ $(defaults_zustand com.apple.desktopservices DSDontWriteUSBStores aus) == an ]] \
        && print aus || print an
}
einschalten() { defaults write com.apple.desktopservices DSDontWriteUSBStores -bool false }
ausschalten() { defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true }
