# Vorlage für eine neue Funktion. Anlegen mit: schalter neu <name>
#
# GRUPPE ordnet die Funktion im Menü ein (Entwickler, Tastatur, Finder, Dock,
# Bildschirmfotos, Programme, System). BESCHREIBUNG kurz halten, etwa 30 Zeichen.
# Pflicht sind BESCHREIBUNG und die drei Funktionen zustand, einschalten, ausschalten.
# zustand gibt genau "an", "aus" oder "–" (auf diesem Mac nicht verfügbar) aus.
# Für Systemeinstellungen einfach "sudo" voranstellen, dann wird nach dem Passwort gefragt.
# Hilfsfunktionen aus lib/hilfen.sh: defaults_zustand, pmset_wert, wlan_geraet

GRUPPE="System"
BESCHREIBUNG="Was diese Funktion schaltet"

zustand() {
    defaults_zustand com.example.domain EinSchluessel aus
}

einschalten() {
    defaults write com.example.domain EinSchluessel -bool true
}

ausschalten() {
    defaults write com.example.domain EinSchluessel -bool false
}
