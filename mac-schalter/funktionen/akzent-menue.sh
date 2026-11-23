GRUPPE="Tastatur"
BESCHREIBUNG="Akzent-Menü bei gehaltener Taste"
# Wirkt in Apps erst nach deren Neustart.

zustand()     { defaults_zustand NSGlobalDomain ApplePressAndHoldEnabled an }
einschalten() { defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool true }
ausschalten() { defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false }
