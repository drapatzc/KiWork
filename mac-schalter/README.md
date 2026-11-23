# mac-schalter

Kleines zsh-Skript, mit dem sich Mac-Funktionen dauerhaft ein- und ausschalten lassen.
Die Einstellungen bleiben auch nach einem Neustart erhalten, weil sie direkt in macOS
gespeichert werden (`pmset`, `defaults`, `nvram`, `networksetup`, `tmutil`).

## Einrichten

In `~/.zshrc` steht der Alias:

```sh
alias schalter="$HOME/GIT-Home/KiWork/mac-schalter/schalter"
```

Damit steht `schalter` in jedem neuen Terminal zur Verfügung.

## Benutzen

```sh
schalter                          # Menü mit zwei Spalten (siehe unten)
schalter liste                    # alle Schalter und Aktionen als Liste
schalter aus ruhezustand          # Mac schläft nicht mehr
schalter an ruhezustand           # wieder normal
schalter um dock-ausblenden       # umschalten
schalter aus ruhezustand bildschirm-ruhe   # mehrere auf einmal
schalter zustand wlan
schalter start xcode-frisch       # Aktion sofort ausführen
schalter start -j device-support  # kritische Aktion ohne Rückfrage
schalter neu mein-schalter        # neuen Schalter aus Vorlage
```

Bei Systemeinstellungen (pmset, nvram, tmutil) fragt `sudo` nach dem Passwort.

### Menü

`schalter` ohne Angaben öffnet ein Menü, das fest oben im Terminal steht und nie rutscht
(zweiter Bildschirmpuffer). Passen nicht alle Zeilen ins Fenster, rollt nur der Inhalt
der Spalte; `▲` und `▼ weitere` zeigen das an.

- Links stehen die Schalter: `[x]` an, `[ ]` aus, `[-]` auf diesem Mac nicht verfügbar.
- Rechts stehen die Aktionen mit Pfeil: `→` startet sofort, `→ !` fragt vorher in einem
  Dialog nach (Abbrechen oder Ausführen).
- Pfeil hoch/runter (oder k/j): Eintrag wählen
- Pfeil links/rechts oder Tab: Spalte wechseln
- Return oder Leertaste: Schalter umschalten bzw. Aktion starten
- r: alle Zustände neu einlesen
- q oder Esc: beenden

Die Ausgabe einer Aktion erscheint auf einer eigenen Seite; eine beliebige Taste führt
zurück ins Menü. Ist die Ausgabe kein Terminal (z. B. in einer Pipe), zeigt `schalter`
stattdessen die Liste.

## Aktionen

Die Aktionen stehen in `lib/aktionen.sh` (früher `xcodeclean.sh`): Xcode beenden und
starten, Caches leeren, Simulatoren aufräumen, Papierkorb, DNS, Quick Look und mehr.
Ein Eintrag in `AKTIONEN` hat die Form `name|Gruppe|Kurzbeschreibung|Rückfrage`, dazu
gehört eine Funktion `aktion_<name>`. Steht eine Rückfrage drin, gilt die Aktion als
kritisch. Archive werden nie gelöscht.

## Enthaltene Funktionen

| Name | Was | Technik |
|---|---|---|
| ruhezustand | aus = Mac schläft nie, auch zugeklappt | `pmset disablesleep` |
| bildschirm-ruhe | Bildschirm geht nach Wartezeit aus | `pmset displaysleep` |
| power-nap | Power Nap | `pmset powernap` |
| startton | Startton beim Hochfahren | `nvram StartupMute` |
| versteckte-dateien | Versteckte Dateien im Finder | `defaults` Finder |
| dateiendungen | Alle Dateiendungen zeigen | `defaults` NSGlobalDomain |
| dock-ausblenden | Dock automatisch ausblenden | `defaults` Dock |
| screenshot-schatten | Schatten bei Fenster-Screenshots | `defaults` screencapture |
| ds-store-netzwerk | .DS_Store auf Netzlaufwerken | `defaults` desktopservices |
| wlan | WLAN | `networksetup` |
| time-machine | Automatische Backups | `tmutil` |
| fernzugriff | Nie schlafen + Claude Code Remote Control dauerhaft | `pmset` + LaunchAgent |
| akzent-menue | Akzent-Menü beim Halten einer Taste | `defaults` NSGlobalDomain |
| autokorrektur | Automatische Rechtschreibkorrektur | `defaults` NSGlobalDomain |
| smarte-zeichen | Typografische Anführungszeichen und Gedankenstriche | `defaults` NSGlobalDomain |
| gross-schreibung | Automatische Großschreibung | `defaults` NSGlobalDomain |
| doppel-leer-punkt | Punkt bei doppeltem Leerzeichen | `defaults` NSGlobalDomain |
| tasten-schnell | Schnelle Tastenwiederholung | `defaults` KeyRepeat |
| f-tasten | F1 bis F12 als echte Funktionstasten | `defaults` fnState |
| dunkelmodus | Dunkles Erscheinungsbild | `osascript` System Events |
| finder-pfadleiste | Pfadleiste im Finder | `defaults` Finder |
| finder-statusleiste | Statusleiste im Finder | `defaults` Finder |
| finder-pfad-titel | Voller Pfad im Fenstertitel | `defaults` Finder |
| ordner-zuerst | Ordner zuerst sortieren | `defaults` Finder |
| endung-warnung | Warnung beim Ändern der Dateiendung | `defaults` Finder |
| suche-im-ordner | Suche im aktuellen Ordner | `defaults` Finder |
| library-sichtbar | Ordner Library zeigen | `chflags` |
| ds-store-usb | .DS_Store auf USB-Laufwerken | `defaults` desktopservices |
| dock-zuletzt | Zuletzt benutzte Apps im Dock | `defaults` Dock |
| dock-sofort | Dock ohne Verzögerung einblenden | `defaults` Dock |
| screenshot-vorschau | Schwebende Vorschau nach Bildschirmfoto | `defaults` screencapture |
| screenshot-jpg | Bildschirmfotos als JPG | `defaults` screencapture |
| dialoge-ausgeklappt | Sichern- und Druckdialog ausgeklappt | `defaults` NSGlobalDomain |
| textedit-reintext | TextEdit mit reinem Text | `defaults` TextEdit |
| absturz-mitteilung | Abstürze als Mitteilung | `defaults` CrashReporter |
| xcode-build-dauer | Build-Dauer in Xcode | `defaults` Xcode |
| xcode-index-fortschritt | Indizierung in Xcode als Zahl | `defaults` Xcode |

### fernzugriff

Schaltet den Ruhezustand ab (`pmset sleep 0`, `disablesleep 1`), lässt den Mac nach einem
Stromausfall neu starten (`autorestart 1`) und startet `claude remote-control` als LaunchAgent
in einer `screen`-Sitzung. Stürzt Claude ab, startet launchd es nach 30 Sekunden neu.
Gesteuert wird über die Claude-App (iPhone/iPad) oder claude.ai/code.

- Arbeitsordner: `SCHALTER_FERN_ORDNER`, Standard `~/GIT-Home`
- Lokal mitschauen: `screen -r claude-fern`, lösen mit Ctrl-A, dann D
- Protokoll: `~/.config/mac-schalter/fernzugriff.log`
- Ausschalten stellt die vorher gesicherten pmset-Werte wieder her.

Grenze: Mit FileVault bleibt der Mac nach jedem Neustart (Stromausfall, macOS-Update) am
Anmeldebildschirm stehen, bis jemand vor Ort das Passwort eingibt. Bis dahin gibt es keinen
Fernzugriff. Für längere Abwesenheit deshalb automatische macOS-Updates pausieren.

Die Wartezeit für `bildschirm-ruhe` beim Einschalten: `SCHALTER_BILDSCHIRM_MINUTEN=15 schalter an bildschirm-ruhe`.

## Erweitern

Jede Funktion ist eine Datei `funktionen/<name>.sh` mit vier Teilen:

```zsh
BESCHREIBUNG="Was geschaltet wird"
zustand()     { ... }   # gibt "an", "aus" oder "–" (nicht verfügbar) aus
einschalten() { ... }
ausschalten() { ... }
```

`schalter neu <name>` legt so eine Datei aus `funktionen/_vorlage.sh` an. Hilfsfunktionen
in `lib/hilfen.sh`: `defaults_zustand`, `pmset_wert`, `wlan_geraet`. Jede Datei läuft in
einer eigenen Subshell, Namen können sich also nicht in die Quere kommen.
Dateien mit `_` am Anfang werden nicht als Funktion gelistet.
