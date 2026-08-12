#!/usr/bin/env bash
# Startet das Modell nomic-embed-text:latest in Ollama.
# Hinweis: Embedding-Modell ohne Chat-Ausgabe - primär für die API gedacht
# (z.B. POST /api/embeddings), nicht für interaktive Konversation.
set -euo pipefail

ollama run nomic-embed-text:latest
