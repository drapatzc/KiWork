# config-backup — Backup copies of the configuration files

This folder **mirrors your home directory (`~`)**. A file's path here therefore
shows exactly where the original lives.

> ⚠️ These are **backup copies**. The active files are the ones under `~/…`.
> Changes made here have NO effect until you copy them back.
> Snapshot date: see the file's timestamp.

## Mapping: which file belongs where and what for

| File here (relative to `config-backup/`) | Original location | Purpose |
|---|---|---|
| `.config/opencode/opencode.json` | `~/.config/opencode/opencode.json` | **OpenCode** configuration: Ollama provider, model (`gemma4:latest`, num_ctx 32768, tool_call), permissions. Read when OpenCode starts. |
| `litellm_config.yaml` | `~/litellm_config.yaml` | **LiteLLM proxy** for **Claude Code (local)**: translates Anthropic requests → Ollama. All Claude model names → `ollama_chat/gemma4:latest` (num_ctx 32768). Passed to LiteLLM by `localai-up.sh`. |
| `zshrc-relevante-zeilen.txt` | `~/.zshrc` (excerpt only) | The PATH/alias lines from the shell config relevant to this setup (e.g. `~/.local/bin`, `~/.opencode/bin`). Not a full `.zshrc`. |

## The scripts themselves

The start/stop/status scripts (`*.sh`) as well as `ANLEITUNG.md` and `work.txt`
already live in the parent repo folder (`KiWork/`) and are **not** copied here
again.

## Restoring (if needed)

```sh
cp config-backup/.config/opencode/opencode.json ~/.config/opencode/opencode.json
cp config-backup/litellm_config.yaml            ~/litellm_config.yaml
```

## Note on other backups

The home directory also contains `~/litellm_config.yaml.bak` and `.bak2` —
earlier automatic backups from the setup process (not part of this structure).
