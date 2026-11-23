GRUPPE="Programme"
BESCHREIBUNG="Sichern und Drucken ausgeklappt"
# Wirkt in Apps erst nach deren Neustart.

zustand()     { defaults_zustand NSGlobalDomain NSNavPanelExpandedStateForSaveMode aus }
_setzen() {
    local s
    for s in NSNavPanelExpandedStateForSaveMode NSNavPanelExpandedStateForSaveMode2 \
             PMPrintingExpandedStateForPrint PMPrintingExpandedStateForPrint2; do
        defaults write NSGlobalDomain $s -bool $1
    done
}
einschalten() { _setzen true }
ausschalten() { _setzen false }
