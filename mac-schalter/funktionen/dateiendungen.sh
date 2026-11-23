GRUPPE="Finder"
BESCHREIBUNG="Alle Dateiendungen zeigen"

zustand()     { defaults_zustand NSGlobalDomain AppleShowAllExtensions aus }
einschalten() { defaults write NSGlobalDomain AppleShowAllExtensions -bool true;  killall Finder }
ausschalten() { defaults write NSGlobalDomain AppleShowAllExtensions -bool false; killall Finder }
