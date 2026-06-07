# config-backup — Sicherungskopien der Konfigurationsdateien

Dieser Ordner **spiegelt dein Home-Verzeichnis (`~`)**. Der Pfad einer Datei
hier zeigt also genau, wo sie im Original liegt.

> ⚠️ Das sind **Kopien zur Sicherung**. Die aktiven Dateien sind die unter
> `~/…`. Änderungen hier wirken sich NICHT aus, bis du sie zurückkopierst.
> Stand der Kopie: siehe Datei-Datum.

## Zuordnung: welche Datei gehört wohin und wozu

| Datei hier (relativ zu `config-backup/`) | Original-Ort | Wozu |
|---|---|---|
| `.config/opencode/opencode.json` | `~/.config/opencode/opencode.json` | **OpenCode**-Konfiguration: Ollama-Provider, Modell (`gemma4:latest`, num_ctx 32768, tool_call), Berechtigungen. Wird beim Start von OpenCode gelesen. |
| `litellm_config.yaml` | `~/litellm_config.yaml` | **LiteLLM-Proxy** für **Claude Code lokal**: übersetzt Anthropic-Anfragen → Ollama. Alle Claude-Modellnamen → `ollama_chat/gemma4:latest` (num_ctx 32768). Wird von `localai-up.sh` an LiteLLM übergeben. |
| `zshrc-relevante-zeilen.txt` | `~/.zshrc` (nur Auszug) | Die für dieses Setup relevanten PATH-/Alias-Zeilen aus der Shell-Config (z. B. `~/.local/bin`, `~/.opencode/bin`). Kein vollständiges `.zshrc`. |

## Die Skripte selbst

Die Start-/Stop-/Status-Skripte (`*.sh`) sowie `ANLEITUNG.md` und `work.txt`
liegen bereits im übergeordneten Repo-Ordner (`KiWork/`) und sind hier **nicht**
nochmal kopiert.

## Wiederherstellen (falls nötig)

```sh
cp config-backup/.config/opencode/opencode.json ~/.config/opencode/opencode.json
cp config-backup/litellm_config.yaml            ~/litellm_config.yaml
```

## Hinweis zu weiteren Backups

Im Home liegen zusätzlich `~/litellm_config.yaml.bak` und `.bak2` — frühere
automatische Sicherungen aus der Einrichtung (nicht Teil dieser Struktur).
