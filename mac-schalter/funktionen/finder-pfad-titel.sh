GRUPPE="Finder"
BESCHREIBUNG="Voller Pfad im Fenstertitel"

zustand()     { defaults_zustand com.apple.finder _FXShowPosixPathInTitle aus }
einschalten() { defaults write com.apple.finder _FXShowPosixPathInTitle -bool true;  killall Finder }
ausschalten() { defaults write com.apple.finder _FXShowPosixPathInTitle -bool false; killall Finder }
