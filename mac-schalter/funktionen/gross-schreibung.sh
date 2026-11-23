GRUPPE="Tastatur"
BESCHREIBUNG="Automatische Großschreibung"
# Wirkt in Apps erst nach deren Neustart.

zustand()     { defaults_zustand NSGlobalDomain NSAutomaticCapitalizationEnabled an }
einschalten() { defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool true }
ausschalten() { defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false }
