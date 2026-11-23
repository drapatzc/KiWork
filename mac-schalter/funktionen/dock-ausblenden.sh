GRUPPE="Dock"
BESCHREIBUNG="Dock automatisch ausblenden"

zustand()     { defaults_zustand com.apple.dock autohide aus }
einschalten() { defaults write com.apple.dock autohide -bool true;  killall Dock }
ausschalten() { defaults write com.apple.dock autohide -bool false; killall Dock }
