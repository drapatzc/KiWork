GRUPPE="Finder"
BESCHREIBUNG="Suche im aktuellen Ordner"
# SCcf = aktueller Ordner, SCev = diesen Mac durchsuchen.

zustand()     { [[ $(defaults read com.apple.finder FXDefaultSearchScope 2>/dev/null) == SCcf ]] && print an || print aus }
einschalten() { defaults write com.apple.finder FXDefaultSearchScope -string SCcf; killall Finder }
ausschalten() { defaults write com.apple.finder FXDefaultSearchScope -string SCev; killall Finder }
