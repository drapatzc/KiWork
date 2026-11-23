GRUPPE="Tastatur"
BESCHREIBUNG="Typografische Anführungszeichen"
# Wirkt in Apps erst nach deren Neustart.

zustand()     { defaults_zustand NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled an }
einschalten() {
    defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool true
    defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool true
}
ausschalten() {
    defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
}
