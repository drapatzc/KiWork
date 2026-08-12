#!/usr/bin/env bash

set -euo pipefail

# Legt den Alias "claudeLokal" in der ~/.zshrc an – aber nur, wenn er
# noch nicht vorhanden ist. Mehrfaches Ausführen ist unschädlich.

ALIAS_NAME="claudeLokal"
TARGET_SCRIPT="/Users/Christian.Drapatz/GITHOME/KiWork/claude-ollama-run.sh"
ZSHRC="$HOME/.zshrc"
MARKER="# >>> KiWork ${ALIAS_NAME} >>>"

echo "=============================================="
echo "   Alias-Setup: ${ALIAS_NAME}"
echo "=============================================="
echo

if [[ ! -f "$TARGET_SCRIPT" ]]; then
    echo "FEHLER: Script nicht gefunden: $TARGET_SCRIPT"
    exit 1
fi

if [[ ! -x "$TARGET_SCRIPT" ]]; then
    echo "Setze Ausführungsrecht für $TARGET_SCRIPT"
    chmod +x "$TARGET_SCRIPT"
fi

touch "$ZSHRC"

if grep -qE "^[[:space:]]*alias[[:space:]]+${ALIAS_NAME}=" "$ZSHRC"; then
    echo "Alias '${ALIAS_NAME}' ist bereits in ${ZSHRC} eingetragen."
    echo "Nichts zu tun."
    echo
    grep -nE "^[[:space:]]*alias[[:space:]]+${ALIAS_NAME}=" "$ZSHRC"
    echo
    echo "Falls '${ALIAS_NAME}' im Terminal trotzdem nicht gefunden wird,"
    echo "kennt die laufende Shell den Eintrag noch nicht. Dann einmal:"
    echo
    echo "    source ~/.zshrc"
    echo
    exit 0
fi

{
    echo ""
    echo "$MARKER"
    echo "alias ${ALIAS_NAME}='${TARGET_SCRIPT}'"
    echo "# <<< KiWork ${ALIAS_NAME} <<<"
} >> "$ZSHRC"

echo "Alias '${ALIAS_NAME}' wurde in ${ZSHRC} eingetragen:"
echo "  alias ${ALIAS_NAME}='${TARGET_SCRIPT}'"
echo
echo "Damit er im aktuellen Terminal aktiv wird:"
echo "  source ~/.zshrc"
