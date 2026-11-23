GRUPPE="Finder"
BESCHREIBUNG="Ordner zuerst sortieren"

zustand()     { defaults_zustand com.apple.finder _FXSortFoldersFirst aus }
einschalten() { defaults write com.apple.finder _FXSortFoldersFirst -bool true;  killall Finder }
ausschalten() { defaults write com.apple.finder _FXSortFoldersFirst -bool false; killall Finder }
