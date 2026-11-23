GRUPPE="Tastatur"
BESCHREIBUNG="Punkt bei doppeltem Leerzeichen"
# Wirkt in Apps erst nach deren Neustart.

zustand()     { defaults_zustand NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled an }
einschalten() { defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool true }
ausschalten() { defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false }
