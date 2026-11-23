GRUPPE="Dock"
BESCHREIBUNG="Dock ohne Verzögerung einblenden"
# Nur sichtbar, wenn „dock-ausblenden“ an ist. aus = Standardverzögerung von macOS.

zustand() {
    local wert
    wert=$(defaults read com.apple.dock autohide-delay 2>/dev/null) || { print aus; return }
    (( wert == 0 )) && print an || print aus
}
einschalten() { defaults write com.apple.dock autohide-delay -float 0; killall Dock }
ausschalten() { defaults delete com.apple.dock autohide-delay 2>/dev/null; killall Dock }
