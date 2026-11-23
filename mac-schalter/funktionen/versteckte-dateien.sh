GRUPPE="Finder"
BESCHREIBUNG="Versteckte Dateien zeigen"

zustand()     { defaults_zustand com.apple.finder AppleShowAllFiles aus }
einschalten() { defaults write com.apple.finder AppleShowAllFiles -bool true;  killall Finder }
ausschalten() { defaults write com.apple.finder AppleShowAllFiles -bool false; killall Finder }
