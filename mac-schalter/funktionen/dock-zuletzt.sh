GRUPPE="Dock"
BESCHREIBUNG="Zuletzt benutzte Apps zeigen"

zustand()     { defaults_zustand com.apple.dock show-recents an }
einschalten() { defaults write com.apple.dock show-recents -bool true;  killall Dock }
ausschalten() { defaults write com.apple.dock show-recents -bool false; killall Dock }
