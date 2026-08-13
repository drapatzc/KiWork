#!/bin/sh
# Starts Ollama (official app) for OpenCode and pins gemma4 in RAM
# Compatible with zsh and bash

# Start Ollama via the OFFICIAL app (not the brew service): only the app
# ships the runner that can start gemma4 (GGUF).
brew services stop ollama >/dev/null 2>&1
open -a Ollama >/dev/null 2>&1
echo "Ollama: official app started"

# Wait until ready
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -s --max-time 2 http://localhost:11434 >/dev/null 2>&1 && break
  sleep 1
done

if curl -s --max-time 2 http://localhost:11434 >/dev/null 2>&1; then
  echo "Ollama: reachable at http://localhost:11434"
  # Preload gemma4 with a fixed num_ctx AND pin it permanently in RAM
  # (keep_alive:-1). Prevents the constant unload/reload that caused
  # "Stopping..." hangs and minutes-long waits.
  # Important: num_ctx 32768 matches litellm_config.yaml -> otherwise Ollama
  # reloads the 9.7 GB model every time you switch tools.
  echo "Ollama: preloading and pinning gemma4 (num_ctx 32768)..."
  curl -s http://localhost:11434/api/chat -d '{"model":"gemma4:latest","messages":[{"role":"user","content":"hi"}],"options":{"num_ctx":32768},"keep_alive":-1,"stream":false}' >/dev/null 2>&1
  echo "Ollama: gemma4 loaded (stays in RAM)"
else
  echo "Ollama: not reachable yet — please re-check with ./opencode-status.sh"
fi

echo ""
echo "Start OpenCode with:"
echo "  ./opencode-start.sh"
