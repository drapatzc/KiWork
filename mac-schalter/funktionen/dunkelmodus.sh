GRUPPE="Entwickler"
BESCHREIBUNG="Dunkelmodus"
# Beim ersten Mal fragt macOS, ob das Terminal „System Events“ steuern darf.

zustand()     { [[ $(defaults read -g AppleInterfaceStyle 2>/dev/null) == Dark ]] && print an || print aus }
einschalten() { osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' }
ausschalten() { osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' }
