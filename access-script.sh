#!/bin/bash

set -e

DIRECTORY="${1:-.}"

echo "Vergebe Ausführungsrechte in: $DIRECTORY"

find "$DIRECTORY" -type f \( \
    -name "*.sh" -o \
    -name "*.command" \
\) -exec chmod +x {} \;

echo "Fertig."
