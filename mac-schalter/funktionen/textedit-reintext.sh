GRUPPE="Programme"
BESCHREIBUNG="TextEdit mit reinem Text"
# macOS speichert "RichText", deshalb ist die Logik umgedreht.

zustand() {
    [[ $(defaults_zustand com.apple.TextEdit RichText an) == an ]] && print aus || print an
}
einschalten() { defaults write com.apple.TextEdit RichText -bool false }
ausschalten() { defaults write com.apple.TextEdit RichText -bool true }
