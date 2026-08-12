#!/bin/sh
# Starts the local AI stack: Ollama (official app) + LiteLLM (background)
# Compatible with zsh and bash

CONFIG="$HOME/litellm_config.yaml"
PID_FILE="/tmp/litellm.pid"
LOG_FILE="/tmp/litellm.log"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: $CONFIG is missing."
  echo "Please run ./install-localai.sh first."
  exit 1
fi

# Start Ollama via the OFFICIAL app (/Applications/Ollama.app).
# Important: do NOT use "brew services start ollama" -- in this version the
# Homebrew CLI ships only the MLX runner, not "llama-server", and therefore
# cannot start GGUF models like gemma4.
brew services stop ollama >/dev/null 2>&1
open -a Ollama >/dev/null 2>&1
echo "Ollama:  official app started"

# Wait until ready
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -s --max-time 2 http://localhost:11434 >/dev/null 2>&1 && break
  sleep 1
done

# Preload gemma4 AND pin it permanently in RAM (keep_alive:-1). Prevents the
# constant unload/reload ("Stopping..." hangs). num_ctx 32768 matches
# opencode.json -> only ONE model instance for both tools.
if curl -s --max-time 2 http://localhost:11434 >/dev/null 2>&1; then
  echo "Ollama:  preloading and pinning gemma4 (num_ctx 32768)..."
  curl -s http://localhost:11434/api/chat -d '{"model":"gemma4:latest","messages":[{"role":"user","content":"hi"}],"options":{"num_ctx":32768},"keep_alive":-1,"stream":false}' >/dev/null 2>&1
  echo "Ollama:  gemma4 loaded (stays in RAM)"
fi

# LiteLLM: check whether it is already running
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "LiteLLM: already running (PID $(cat "$PID_FILE"))"
else
  nohup litellm --config "$CONFIG" --port 4000 > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "LiteLLM: started (PID $(cat "$PID_FILE"))"
  echo "         Log: $LOG_FILE"
fi

echo ""
echo "Stack is up. Start Claude Code with:"
echo "  ./claude-local.sh"
