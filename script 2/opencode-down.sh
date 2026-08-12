#!/bin/sh
# Stops Ollama (official app) and frees the model from RAM
# Compatible with zsh and bash

# Unload models from RAM -> RELIABLY frees the memory, even with
# keep_alive:-1 ("Forever"). "ollama stop" for each currently loaded model.
if curl -s --max-time 2 http://localhost:11434 >/dev/null 2>&1; then
  ollama ps 2>/dev/null | awk 'NR>1 && $1!="" {print $1}' | while read -r m; do
    ollama stop "$m" >/dev/null 2>&1 && echo "Ollama: model $m unloaded from RAM"
  done
fi

# Quit the Ollama app. osascript alone is unreliable -> help it with pkill.
brew services stop ollama >/dev/null 2>&1
osascript -e 'tell application "Ollama" to quit' >/dev/null 2>&1
sleep 2
pkill -f "Ollama.app/Contents/Resources/ollama serve" 2>/dev/null
pkill -f "llama-server" 2>/dev/null
pkill -f "Ollama.app/Contents/MacOS/Ollama" 2>/dev/null
sleep 1

if curl -s --max-time 2 http://localhost:11434 >/dev/null 2>&1; then
  echo "Ollama: still running (app may relaunch) -- but the model is unloaded, RAM freed"
else
  echo "Ollama: quit, RAM freed"
fi
