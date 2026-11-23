GRUPPE="Tastatur"
BESCHREIBUNG="F1–F12 als Funktionstasten"
# activateSettings ist ein Apple-Werkzeug, das die Einstellung sofort übernimmt.

AKTIVIEREN=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings

zustand()     { defaults_zustand NSGlobalDomain com.apple.keyboard.fnState aus }
einschalten() { defaults write NSGlobalDomain com.apple.keyboard.fnState -bool true;  [[ -x $AKTIVIEREN ]] && $AKTIVIEREN -u }
ausschalten() { defaults write NSGlobalDomain com.apple.keyboard.fnState -bool false; [[ -x $AKTIVIEREN ]] && $AKTIVIEREN -u }
