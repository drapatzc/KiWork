# Manual — Local AI on the Mac (Claude Code + OpenCode)

Model status: **both tools use `gemma4:latest`** (8B, ~9.6 GB), both with
`num_ctx 32768` → one shared Ollama instance, no reloading.

> ⚠️ **Hardware note:** On an **M4 (32 GB)**, **Claude Code is very slow when
> run locally** (Claude Code's large system prompt + many calls per query →
> minutes). **OpenCode** is fast there. On a **Mac Ultra**, Claude Code runs
> fast locally too.
>
> For *really* fast Claude Code on any hardware: `./claude-abo.sh`
> (your subscription) or `./claude-api.sh` (cloud) — these do not use the
> local model.

---

## 0. The big picture

You have **two tools** that share **one Ollama + gemma4**:

```
                 ┌─────────────────────────────┐
                 │   Ollama  (gemma4:latest)   │   ← the AI model, local
                 └─────────────────────────────┘
                   ▲                         ▲
     (via LiteLLM proxy :4000)        (direct :11434)
                   │                         │
        ┌──────────────────┐        ┌──────────────────┐
        │   Claude Code     │        │    OpenCode      │
        └──────────────────┘        └──────────────────┘
```

- **Claude Code (local)** additionally needs the **LiteLLM proxy** (translates
  Anthropic requests → Ollama).
- **OpenCode** talks to Ollama directly, **without** LiteLLM.

> **Important:** Always start Ollama via the **official app**
> (`open -a Ollama`), not via the Homebrew service — only the app ships the
> runner that can start gemma4 (GGUF). The `*-up.sh` scripts handle this for
> you.

---

## 1. One-time installation

Prerequisite: **Homebrew** is installed.

```sh
# Claude Code stack (Node, Claude Code, Ollama app, Python, LiteLLM, gemma4)
./install-localai.sh

# OpenCode stack (Ollama, OpenCode, config)
./install-opencode.sh
```

Both scripts are **idempotent** — running them multiple times does no harm,
anything already present is skipped. gemma4 (~9.6 GB) is downloaded once.

Afterwards open a new terminal once (or `source ~/.zshrc`) so that `claude`
and `opencode` are on the PATH.

---

## 2. Variant A — Claude Code (local)

```sh
./localai-up.sh        # starts Ollama app + LiteLLM, pins gemma4
./claude-local.sh      # starts Claude Code against gemma4 (local, free)
./localai-down.sh      # stops LiteLLM + Ollama when you're done
```

Notes:
- Claude Code may show "Sonnet 4.6" — that's only the internal routing name,
  **gemma4 is actually running locally**.
- On the very first start a "Custom API key found?" dialog may appear →
  confirm once, then never again.

### Claude Code with subscription or cloud (instead of local)

```sh
./claude-abo.sh        # via your Claude subscription (OAuth login, no API cost)
./claude-api.sh        # via Anthropic cloud (needs ANTHROPIC_API_KEY)
```

For `claude-api.sh`, set the key first:
```sh
export ANTHROPIC_API_KEY="sk-ant-..."
```

---

## 3. Variant B — OpenCode

```sh
./opencode-up.sh       # makes sure Ollama is running
./opencode-start.sh    # starts OpenCode against gemma4
./opencode-down.sh     # stops Ollama when you're done
```

In OpenCode, "Gemma 4" is the default model.

---

## 4. Check status

```sh
./claude-status.sh     # shows: active AI, Ollama, LiteLLM, models
./opencode-status.sh   # shows: OpenCode, config, Ollama, models
```

---

## 5. Typical workflows

**"I want to work locally with Claude Code":**
```sh
./localai-up.sh && ./claude-local.sh
```

**"I want to work with OpenCode":**
```sh
./opencode-up.sh && ./opencode-start.sh
```

**"I'm done":**
```sh
./localai-down.sh      # or ./opencode-down.sh
```

**"OpenCode is already running — how do I also start Claude Code?":**
Both use the same gemma4 (one shared instance). In a second terminal, Claude
Code just needs the LiteLLM proxy in addition:
```sh
cd ~/GIT-Home/KiWork && ./localai-up.sh && ./claude-local.sh
```
> On **M4**, only use **one at a time** — simultaneous requests share the GPU
> and are processed serially (everything gets sluggish). On a **Mac Ultra**,
> running them in parallel is not a problem.

---

## 6. Managing models (Ollama)

```sh
ollama list                    # installed models
ollama pull <name>             # download a model
ollama rm <name>               # delete a model
ollama ps                      # what's currently loaded?
```

> **Rule of thumb for 32 GB RAM:** a model should use ≤ ~14 GB, otherwise the
> Mac swaps and everything gets sluggish. gemma4 (9.6 GB) fits well.
> Models > 20 GB (e.g. qwen3-coder:30b) are too slow here.

---

## 7. When something goes wrong

| Problem | Solution |
|---|---|
| "Ollama is not running" | `./localai-up.sh` (starts the Ollama app) |
| "LiteLLM proxy is not running" | `./localai-up.sh` |
| Tools/commands are not executed | The model must support tool calling — **gemma4 does**; coder models like qwen2.5-coder do not |
| Very slow / hangs for minutes | Check `ollama ps`: if it shows **"Stopping…"**, the runner is stuck → restart the Ollama app or run `./localai-up.sh` (or `./opencode-up.sh`) again. The scripts then pin gemma4 with `keep_alive:-1` (UNTIL = "Forever"). |
| Model reloads constantly | `num_ctx` must be the same in `opencode.json` **and** `litellm_config.yaml` (both 32768), otherwise Ollama reloads on every switch. |
| View the LiteLLM log | `cat /tmp/litellm.log` |

---

## 8. Good to know

- Local = **free & privacy-friendly** (nothing leaves the Mac).
- The `*-up.sh` scripts **preload gemma4 at startup and pin it in RAM**
  (`keep_alive:-1`, `ollama ps` shows `UNTIL: Forever`). This makes even the
  first prompt fast, and the model is **no longer** unloaded after idle —
  which prevents the earlier "Stopping…" hangs.
- gemma4 runs at ~25 tokens/s (8B on M4). Long answers therefore take a few
  seconds — that's normal, not a fault.
- Setup details/history are in `work.txt`.
