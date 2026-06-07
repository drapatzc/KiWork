DOCX-Dateien automatisch in PDF umwandeln

Diese Anleitung zeigt, wie man auf dem Mac alle .docx-Dateien in einem Verzeichnis automatisch in PDF-Dateien umwandelt, ohne jede Datei einzeln in Microsoft Word zu öffnen.

Die erzeugte PDF-Datei bekommt denselben Namen wie die DOCX-Datei.

Beispiel:

anleitung-de.docx  → anleitung-de.pdf
anleitung-en.docx  → anleitung-en.pdf
swift.docx         → swift.pdf

Lösung mit LibreOffice

Der einfachste Weg ist LibreOffice im Headless-Modus. Dabei läuft LibreOffice ohne sichtbares Fenster im Hintergrund.

Script: docx2pdf.sh

#!/bin/bash
set -e
if [ -n "$1" ]; then
    DIRECTORY="$1"
else
    DIRECTORY="$(pwd)"
fi
echo "Verzeichnis: $DIRECTORY"
if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Homebrew ist nicht installiert."
    echo "Bitte zuerst Homebrew installieren:"
    echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi
if [ ! -f "/Applications/LibreOffice.app/Contents/MacOS/soffice" ]; then
    echo "📦 LibreOffice nicht gefunden. Installation wird gestartet..."
    brew install --cask libreoffice
    echo "✅ LibreOffice installiert."
fi
SOFFICE="/Applications/LibreOffice.app/Contents/MacOS/soffice"
if [ ! -f "$SOFFICE" ]; then
    echo "❌ LibreOffice konnte nicht gefunden werden."
    exit 1
fi
DOCX_COUNT=$(find "$DIRECTORY" -type f -name "*.docx" | wc -l | tr -d ' ')
if [ "$DOCX_COUNT" -eq 0 ]; then
    echo "ℹ️ Keine DOCX-Dateien gefunden."
    exit 0
fi
echo "📄 Gefundene DOCX-Dateien: $DOCX_COUNT"
find "$DIRECTORY" -type f -name "*.docx" | while read -r FILE
do
    echo "➡️  Konvertiere: $(basename "$FILE")"
    "$SOFFICE" \
        --headless \
        --convert-to pdf \
        --outdir "$(dirname "$FILE")" \
        "$FILE"
done
echo ""
echo "✅ Alle DOCX-Dateien wurden konvertiert."

Script ausführbar machen

chmod +x docx2pdf.sh

Verwendung

Aktuelles Verzeichnis verwenden:

./docx2pdf.sh

Bestimmtes Verzeichnis verwenden:

./docx2pdf.sh /Users/drapatz/Documents

Script global verfügbar machen

Damit das Script überall im Terminal aufgerufen werden kann, kann der Script-Ordner in die ZSH-Konfiguration eingetragen werden.

Beispielordner:

~/GIT-Home/KiWork

ZSH-Konfiguration öffnen:

nano ~/.zshrc

Diese Zeile einfügen:

export PATH="$HOME/GIT-Home/KiWork:$PATH"

Konfiguration neu laden:

source ~/.zshrc

Alle Shell-Scripte im Ordner ausführbar machen:

find ~/GIT-Home/KiWork -name "*.sh" -exec chmod +x {} \;

Prüfen, ob das Script gefunden wird:

which docx2pdf.sh

Danach kann das Script aus jedem Verzeichnis gestartet werden:

docx2pdf.sh

oder mit Pfad:

docx2pdf.sh /Users/drapatz/GIT-Home/learning/work/Tutorial-iOS27

Ergebnis

Alle .docx-Dateien im angegebenen Verzeichnis werden automatisch in PDF-Dateien umgewandelt.

Die PDF-Dateien werden im selben Verzeichnis wie die DOCX-Dateien abgelegt

::
