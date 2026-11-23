GRUPPE="Bildschirmfotos"
BESCHREIBUNG="Als JPG speichern (aus = PNG)"

zustand()     { [[ $(defaults read com.apple.screencapture type 2>/dev/null) == jpg ]] && print an || print aus }
einschalten() { defaults write com.apple.screencapture type -string jpg; killall SystemUIServer 2>/dev/null; return 0 }
ausschalten() { defaults write com.apple.screencapture type -string png; killall SystemUIServer 2>/dev/null; return 0 }
