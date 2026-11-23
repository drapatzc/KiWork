GRUPPE="Entwickler"
BESCHREIBUNG="Xcode: Build-Dauer zeigen"
# Wirkt nach dem nächsten Start von Xcode.

zustand()     { defaults_zustand com.apple.dt.Xcode ShowBuildOperationDuration aus }
einschalten() { defaults write com.apple.dt.Xcode ShowBuildOperationDuration -bool true }
ausschalten() { defaults write com.apple.dt.Xcode ShowBuildOperationDuration -bool false }
