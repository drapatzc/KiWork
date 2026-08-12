#!/usr/bin/env bash

set -euo pipefail

# Legt den Alias "resetTerminal" in der ~/.zshrc an – aber nur, wenn er
# noch nicht vorhanden ist. Mehrfaches Ausfuehren ist unschaedlich.
#
#   resetTerminal  ->  source ~/.zshrc
#
# Warum ein Alias und kein Script?
# Ein Script laeuft immer in einem Kindprozess. Ein "source ~/.zshrc"
# darin wuerde nur diesen Kindprozess betreffen, der sich danach sofort
# beendet – die aufrufende Terminal-Shell bekommt davon nichts mit.
# Ein Alias wird dagegen direkt in der aktuellen Shell expandiert.
# Nur so wirkt das "source" dort, wo es soll.

ALIAS_NAME="resetTerminal"
ZSHRC="$HOME/.zshrc"
MARKER=">>> KiWork ${ALIAS_NAME} >>>"

echo "=============================================="
echo "   Alias-Setup: ${ALIAS_NAME}"
echo "=============================================="
echo

touch "$ZSHRC"

if grep -qE "^[[:space:]]*alias[[:space:]]+${ALIAS_NAME}=" "$ZSHRC"; then
    echo "Alias '${ALIAS_NAME}' ist bereits in ${ZSHRC} eingetragen."
    echo "Nichts zu tun."
    echo
    grep -nE "^[[:space:]]*alias[[:space:]]+${ALIAS_NAME}=" "$ZSHRC"
    exit 0
fi

{
    echo ""
    echo "# ${MARKER}"
    echo "# Laedt die ~/.zshrc in der aktuellen Shell neu."
    echo "alias ${ALIAS_NAME}='source \$HOME/.zshrc'"
    echo "# <<< KiWork ${ALIAS_NAME} <<<"
} >> "$ZSHRC"

echo "Alias '${ALIAS_NAME}' wurde in ${ZSHRC} eingetragen:"
echo "  alias ${ALIAS_NAME}='source \$HOME/.zshrc'"
echo
echo "Einmalig noch von Hand ausfuehren, damit der Alias aktiv wird:"
echo "  source ~/.zshrc"
echo
echo "Danach genuegt kuenftig:  ${ALIAS_NAME}"
