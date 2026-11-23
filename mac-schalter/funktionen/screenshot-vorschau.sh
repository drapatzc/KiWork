GRUPPE="Bildschirmfotos"
BESCHREIBUNG="Vorschau nach dem Foto"

zustand()     { defaults_zustand com.apple.screencapture show-thumbnail an }
einschalten() { defaults write com.apple.screencapture show-thumbnail -bool true;  killall SystemUIServer 2>/dev/null; return 0 }
ausschalten() { defaults write com.apple.screencapture show-thumbnail -bool false; killall SystemUIServer 2>/dev/null; return 0 }
