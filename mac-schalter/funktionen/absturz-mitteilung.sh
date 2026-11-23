GRUPPE="Entwickler"
BESCHREIBUNG="Abstürze nur als Mitteilung"

zustand()     { defaults_zustand com.apple.CrashReporter UseUNC aus }
einschalten() { defaults write com.apple.CrashReporter UseUNC -bool true }
ausschalten() { defaults write com.apple.CrashReporter UseUNC -bool false }
