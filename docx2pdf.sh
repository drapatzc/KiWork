#!/bin/bash

set -e

# Verzeichnis bestimmen
if [ -n "$1" ]; then
    DIRECTORY="$1"
else
    DIRECTORY="$(pwd)"
fi

echo "Verzeichnis: $DIRECTORY"

# Prüfen ob Homebrew vorhanden
if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Homebrew ist nicht installiert."
    echo "Bitte zuerst Homebrew installieren:"
    echo ""
    echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi

# LibreOffice prüfen
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
