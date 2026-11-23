# macOS speichert hier "disable-shadow", deshalb ist die Logik umgedreht.

GRUPPE="Bildschirmfotos"
BESCHREIBUNG="Schatten bei Fensterfotos"

zustand() {
    [[ $(defaults_zustand com.apple.screencapture disable-shadow aus) == an ]] && print aus || print an
}
einschalten() { defaults write com.apple.screencapture disable-shadow -bool false; killall SystemUIServer }
ausschalten() { defaults write com.apple.screencapture disable-shadow -bool true;  killall SystemUIServer }
