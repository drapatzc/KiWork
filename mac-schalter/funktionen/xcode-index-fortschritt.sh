GRUPPE="Entwickler"
BESCHREIBUNG="Xcode: Indizierung als Zahl"
# Wirkt nach dem nächsten Start von Xcode.

zustand()     { defaults_zustand com.apple.dt.Xcode IDEIndexerActivityShowNumericProgress aus }
einschalten() { defaults write com.apple.dt.Xcode IDEIndexerActivityShowNumericProgress -bool true }
ausschalten() { defaults write com.apple.dt.Xcode IDEIndexerActivityShowNumericProgress -bool false }
