==================================================================
QUICK INSTALL — Local AI on the Mac (Claude Code + OpenCode)
==================================================================

Both tools share ONE Ollama + gemma4:latest (8B, ~9.6 GB, num_ctx 32768).
For the full guide see MANUAL-EN.md / MANUAL-DE.md.

Prerequisite: Homebrew is installed (https://brew.sh).


------------------------------------------------------------------
1. ONE-TIME INSTALLATION (recommended: use the scripts)
------------------------------------------------------------------

The install scripts are idempotent — re-running them is safe, anything
already present is skipped.

  # Claude Code stack (Node, Claude Code, Ollama app, Python 3.13,
  # LiteLLM, gemma4)
  ./install-localai.sh

  # OpenCode stack (Ollama app, OpenCode, config)
  ./install-opencode.sh

Afterwards open a new terminal once (or: source ~/.zshrc) so that
`claude` and `opencode` are on the PATH.


------------------------------------------------------------------
2. WHAT THE SCRIPTS DO (manual equivalents)
------------------------------------------------------------------

Node.js (for Claude Code):
  brew install node
  node --version
  npm --version
  npm install -g @anthropic-ai/claude-code

Ollama — IMPORTANT: install the official APP via cask, NOT the formula.
The formula "brew install ollama" ships only the MLX runner and cannot
start GGUF models like gemma4 (llama-server is missing).
  brew install --cask ollama-app
  open -a Ollama            # always start via the app, not brew services
  ollama --version
  ollama list
  ollama pull gemma4:latest

Note: older notes mentioned qwen3-coder:30b / devstral. These are no
longer used — on 32 GB RAM they are too slow. gemma4 supports tool
calling, the coder models above do not.

LiteLLM proxy (only Claude Code needs it; OpenCode talks to Ollama
directly). LiteLLM requires Python 3.13 max.
  brew install python@3.13
  brew install pipx && pipx ensurepath
  pipx install --python "$(brew --prefix python@3.13)/bin/python3.13" 'litellm[proxy]'
Config lives at ~/litellm_config.yaml (created by install-localai.sh).

OpenCode:
  curl -fsSL https://opencode.ai/install | bash
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
  source ~/.zshrc
  which opencode
  opencode --version
Config at ~/.config/opencode/opencode.json (created by install-opencode.sh):
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "gemma4:latest": {
          "name": "Gemma 4",
          "tool_call": true
        }
      }
    }
  },
  "model": "ollama/gemma4:latest",
  "permission": {
    "bash": "allow",
    "read": "allow",
    "glob": "allow",
    "grep": "allow",
    "edit": "ask",
    "write": "ask",
    "task": "deny",
    "webfetch": "deny"
  }
}


------------------------------------------------------------------
3. START / STOP
------------------------------------------------------------------

Claude Code (local, free):
  ./localai-up.sh        # start Ollama app + LiteLLM, pin gemma4
  ./claude-local.sh      # start Claude Code against gemma4
  ./localai-down.sh      # stop LiteLLM + Ollama

Claude Code (fast, not local):
  ./claude-abo.sh        # via your Claude subscription (OAuth login)
  ./claude-api.sh        # via Anthropic cloud (needs ANTHROPIC_API_KEY)

OpenCode:
  ./opencode-up.sh       # make sure Ollama is running
  ./opencode-start.sh    # start OpenCode against gemma4
  ./opencode-down.sh     # stop Ollama

Status:
  ./claude-status.sh
  ./opencode-status.sh


------------------------------------------------------------------
4. HARDWARE NOTE
------------------------------------------------------------------

On an M4 (32 GB), Claude Code is very slow locally (large system prompt
+ many calls). OpenCode is fast there. On a Mac Ultra, Claude Code runs
fast locally too. For fast Claude Code on any hardware use claude-abo.sh
or claude-api.sh.
