#!/bin/sh
# Stops the local AI stack
# Compatible with zsh and bash

PID_FILE="/tmp/litellm.pid"

# Stop LiteLLM
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "LiteLLM: PID $PID stopped"
  fi
  rm -f "$PID_FILE"
else
  # Fallback: all litellm processes using our config
  if pkill -f "litellm --config" 2>/dev/null; then
    echo "LiteLLM: stopped (fallback)"
  fi
fi

# Unload models from RAM -> RELIABLY frees the memory, even with
# keep_alive:-1 ("Forever"). "ollama stop" for each currently loaded model.
if curl -s --max-time 2 http://localhost:11434 >/dev/null 2>&1; then
  ollama ps 2>/dev/null | awk 'NR>1 && $1!="" {print $1}' | while read -r m; do
    ollama stop "$m" >/dev/null 2>&1 && echo "Ollama:  model $m unloaded from RAM"
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

echo ""
if curl -s --max-time 2 http://localhost:11434 >/dev/null 2>&1; then
  echo "Local stack stopped (models unloaded, RAM freed; the Ollama app may"
  echo "relaunch on its own, but then WITHOUT a loaded model)."
else
  echo "Local stack stopped. Ollama quit, RAM freed."
fi
