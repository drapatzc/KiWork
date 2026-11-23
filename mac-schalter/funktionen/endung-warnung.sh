GRUPPE="Finder"
BESCHREIBUNG="Warnung bei neuer Dateiendung"

zustand()     { defaults_zustand com.apple.finder FXEnableExtensionChangeWarning an }
einschalten() { defaults write com.apple.finder FXEnableExtensionChangeWarning -bool true;  killall Finder }
ausschalten() { defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false; killall Finder }
