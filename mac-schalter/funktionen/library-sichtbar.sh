GRUPPE="Finder"
BESCHREIBUNG="Ordner Library zeigen"

zustand()     { [[ $(stat -f %Sf "$HOME/Library") == *hidden* ]] && print aus || print an }
einschalten() { chflags nohidden "$HOME/Library" }
ausschalten() { chflags hidden "$HOME/Library" }
