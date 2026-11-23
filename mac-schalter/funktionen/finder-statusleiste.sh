GRUPPE="Finder"
BESCHREIBUNG="Statusleiste zeigen"

zustand()     { defaults_zustand com.apple.finder ShowStatusBar aus }
einschalten() { defaults write com.apple.finder ShowStatusBar -bool true;  killall Finder }
ausschalten() { defaults write com.apple.finder ShowStatusBar -bool false; killall Finder }
