# Ruhezustand des ganzen Systems. "aus" setzt pmset disablesleep 1:
# Der Mac schläft dann gar nicht mehr, bei MacBooks auch nicht mit zugeklapptem Deckel.
# Achtung: Ein zugeklapptes MacBook in der Tasche kann dann sehr warm werden.

GRUPPE="System"
BESCHREIBUNG="Ruhezustand (aus = nie schlafen)"

zustand() {
    [[ $(pmset -g | awk '$1 == "SleepDisabled" { print $2 }') == 1 ]] && print aus || print an
}

einschalten() { sudo pmset -a disablesleep 0 }
ausschalten() { sudo pmset -a disablesleep 1 }
