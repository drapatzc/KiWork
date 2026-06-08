# Anleitung — Lokale KI auf dem Mac (Claude Code + OpenCode)

Stand der Modelle: **beide Werkzeuge nutzen `gemma4:latest`** (8B, ~9,6 GB),
beide `num_ctx 32768` → eine gemeinsame Ollama-Instanz, kein Neu-Laden.

> ⚠️ **Hardware-Hinweis:** Auf einem **M4 (32 GB)** ist **Claude Code lokal
> sehr langsam** (Claude Codes großer System-Prompt + viele Aufrufe pro
> Frage → Minuten). **OpenCode** ist dort schnell. Auf einer **Mac Ultra**
> läuft auch Claude Code lokal flott.
>
> Für *wirklich* schnelles Claude Code auf jeder Hardware: `./claude-abo.sh`
> (dein Abo) oder `./claude-api.sh` (Cloud) — läuft nicht über das lokale
> Modell.

---

## 0. Das große Bild

Du hast **zwei Werkzeuge**, die sich **ein Ollama + gemma4** teilen:

```
                 ┌─────────────────────────────┐
                 │   Ollama  (gemma4:latest)   │   ← das KI-Modell, lokal
                 └─────────────────────────────┘
                   ▲                         ▲
     (über LiteLLM-Proxy :4000)        (direkt :11434)
                   │                         │
        ┌──────────────────┐        ┌──────────────────┐
        │   Claude Code     │        │    OpenCode      │
        └──────────────────┘        └──────────────────┘
```

- **Claude Code lokal** braucht zusätzlich den **LiteLLM-Proxy** (übersetzt
  Anthropic-Anfragen → Ollama).
- **OpenCode** redet direkt mit Ollama, **ohne** LiteLLM.

> **Wichtig:** Ollama immer über die **offizielle App** starten
> (`open -a Ollama`), nicht über den Homebrew-Dienst — nur die App bringt
> den Runner mit, der gemma4 (GGUF) starten kann. Die `*-up.sh`-Skripte
> erledigen das für dich.

---

## 1. Einmalige Installation

Voraussetzung: **Homebrew** ist installiert.

```sh
# Claude-Code-Stack (Node, Claude Code, Ollama-App, Python, LiteLLM, gemma4)
./install-localai.sh

# OpenCode-Stack (Ollama, OpenCode, Config)
./install-opencode.sh
```

Beide Skripte sind **idempotent** — mehrfaches Ausführen schadet nicht,
schon Vorhandenes wird übersprungen. gemma4 (~9,6 GB) wird einmalig geladen.

Danach Terminal einmal neu öffnen (oder `source ~/.zshrc`), damit
`claude` und `opencode` im PATH sind.

---

## 2. Variante A — Claude Code (lokal)

```sh
./localai-up.sh        # startet Ollama-App + LiteLLM, pinnt gemma4
./claude-local.sh      # startet Claude Code gegen gemma4 (lokal, kostenlos)
./localai-down.sh      # stoppt LiteLLM + Ollama, wenn fertig
```

Hinweise:
- Claude Code zeigt evtl. „Sonnet 4.6" an — das ist nur der interne
  Routing-Name, **tatsächlich läuft gemma4 lokal**.
- Beim allerersten Start kann ein „Custom API Key gefunden?"-Dialog
  kommen → einmal bestätigen, danach nie wieder.

### Claude Code mit Abo oder Cloud (statt lokal)

```sh
./claude-abo.sh        # über dein Claude-Abo (OAuth-Login, keine API-Kosten)
./claude-api.sh        # über Anthropic-Cloud (braucht ANTHROPIC_API_KEY)
```

Für `claude-api.sh` vorher den Key setzen:
```sh
export ANTHROPIC_API_KEY="sk-ant-..."
```

---

## 3. Variante B — OpenCode

```sh
./opencode-up.sh       # stellt sicher, dass Ollama läuft
./opencode-start.sh    # startet OpenCode gegen gemma4
./opencode-down.sh     # stoppt Ollama, wenn fertig
```

In OpenCode ist „Gemma 4" das Standardmodell.

---

## 4. Status prüfen

```sh
./claude-status.sh     # zeigt: aktive KI, Ollama, LiteLLM, Modelle
./opencode-status.sh   # zeigt: OpenCode, Config, Ollama, Modelle
```

---

## 5. Typische Abläufe

**„Ich will lokal mit Claude Code arbeiten":**
```sh
./localai-up.sh && ./claude-local.sh
```

**„Ich will mit OpenCode arbeiten":**
```sh
./opencode-up.sh && ./opencode-start.sh
```

**„Ich bin fertig":**
```sh
./localai-down.sh      # bzw. ./opencode-down.sh
```

**„OpenCode läuft schon — wie starte ich zusätzlich Claude Code?":**
Beide nutzen dasselbe gemma4 (eine gemeinsame Instanz). In einem zweiten
Terminal genügt für Claude Code zusätzlich der LiteLLM-Proxy:
```sh
cd ~/GIT-Home/KiWork && ./localai-up.sh && ./claude-local.sh
```
> Auf **M4** immer nur **eines aktiv** nutzen — gleichzeitige Anfragen teilen
> sich die GPU und werden seriell abgearbeitet (alles wird zäh). Auf einer
> **Mac Ultra** ist Parallelbetrieb unkritisch.

---

## 6. Modelle verwalten (Ollama)

```sh
ollama list                    # installierte Modelle
ollama pull <name>             # Modell laden
ollama rm <name>               # Modell löschen
ollama ps                      # was ist gerade geladen?
```

> **Faustregel für 32 GB RAM:** Modell sollte ≤ ~14 GB belegen, sonst
> swappt der Mac und alles wird zäh. gemma4 (9,6 GB) passt gut.
> Modelle > 20 GB (z. B. qwen3-coder:30b) sind hier zu langsam.

---

## 7. Wenn etwas hakt

| Problem | Lösung |
|---|---|
| „Ollama läuft nicht" | `./localai-up.sh` (startet die Ollama-App) |
| „LiteLLM Proxy läuft nicht" | `./localai-up.sh` |
| Tool-/Befehle werden nicht ausgeführt | Modell muss Tool-Calling können — **gemma4 kann es**; Coder-Modelle wie qwen2.5-coder nicht |
| Sehr langsam / hängt minutenlang | `ollama ps` prüfen: steht da **"Stopping…"**, ist der Runner festgefahren → Ollama-App neu starten bzw. `./localai-up.sh` (bzw. `./opencode-up.sh`) erneut ausführen. Die Skripte pinnen gemma4 dann mit `keep_alive:-1` (UNTIL = "Forever"). |
| Modell lädt ständig neu | `num_ctx` muss in `opencode.json` **und** `litellm_config.yaml` gleich sein (beide 32768), sonst lädt Ollama bei jedem Wechsel neu. |
| LiteLLM-Log ansehen | `cat /tmp/litellm.log` |

---

## 8. Wissenswertes

- Lokal = **kostenlos & datenschutzfreundlich** (nichts verlässt den Mac).
- Die `*-up.sh`-Skripte **laden gemma4 beim Start vor und pinnen es im RAM**
  (`keep_alive:-1`, `ollama ps` zeigt `UNTIL: Forever`). Dadurch ist schon
  der erste Prompt schnell, und das Modell wird **nicht** mehr nach Leerlauf
  entladen — das verhindert die früheren „Stopping…"-Hänger.
- gemma4 läuft mit ~25 Tokens/s (8B auf M4). Lange Antworten dauern also
  ein paar Sekunden — das ist normal, kein Fehler.
- Details/Historie der Einrichtung stehen in `work.txt`.
