GRUPPE="Tastatur"
BESCHREIBUNG="Auto-Korrektur Rechtschreibung"
# Wirkt in Apps erst nach deren Neustart.

zustand()     { defaults_zustand NSGlobalDomain NSAutomaticSpellingCorrectionEnabled an }
einschalten() { defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool true }
ausschalten() { defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false }
