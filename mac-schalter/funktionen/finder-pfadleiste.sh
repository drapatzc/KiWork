GRUPPE="Finder"
BESCHREIBUNG="Pfadleiste zeigen"

zustand()     { defaults_zustand com.apple.finder ShowPathbar aus }
einschalten() { defaults write com.apple.finder ShowPathbar -bool true;  killall Finder }
ausschalten() { defaults write com.apple.finder ShowPathbar -bool false; killall Finder }
