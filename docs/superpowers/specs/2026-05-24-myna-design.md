# Myna — Design Spec

**Date:** 2026-05-24
**Status:** Approved for planning
**Repo:** `~/Developer/myna/` (public GitHub repo)

> *The myna is a bird famous for mimicking human speech.* Myna is an always-on, fully local text-to-speech companion for macOS (Apple Silicon) that reads anything aloud — selected text, web articles, Claude Code output — so you can listen instead of read and work for longer without mental fatigue.

---

## 1. Goal — what "good" means

A daily-driver TTS that runs locally on Apple Silicon with **zero API cost**, suitable for hours of background listening to long articles, Claude Code output, research, and study material. The quality bar is **Audible-narrator consistency** (a calm, fatigue-free voice), not expressive performance. The engine choice — Kokoro 82M via mlx-audio, voice `af_heart` — is already validated and installed (see `kokoro-tts-setup.md`); Myna is the **always-on + control + integration layer** on top of it.

Success criteria:
- Server and player run 24/7, restart on crash and at login, no manual start.
- From any app, a recorded shortcut reads the current selection aloud within ~1–2s of first audio.
- Playback is controllable: pause/resume, stop, speed.
- 4–8 parallel Claude Code sessions never auto-speak; their output is announced silently and the user routes one to audio on demand.
- Every shortcut is rebindable by recording a chord in the app — no file editing required.

---

## 2. Decisions (locked)

| Decision | Choice |
|---|---|
| Playback model | Stateful: play / pause / resume / stop / speed, single "now playing" item, no queue |
| Control surface | Menu bar icon + global hotkeys |
| Input surfaces (v1) | Universal speak-selection, browser article reader (Chrome), Claude Code narration, `myna` CLI |
| Claude Code routing | **Announce + you pick** — sessions register output silently; user clicks one to play |
| Summary vs full | **Two separate triggers** — one shortcut reads full, another summarises (Ollama) then reads |
| Stack | Hammerspoon (control surface) + Python daemon (brain) + existing mlx-audio server (engine) |
| Shortcuts | Recorded in-app, persisted to JSON, rebound live; defaults ship |
| Summariser | Ollama `qwen3.5:4b` (fast fallback `qwen3.5:0.8b`) — both already installed |

---

## 3. Architecture

```
INPUT ADAPTERS                 BRAIN (always-on)              ENGINE (always-on)
─────────────                  ─────────────────              ──────────────────
record-bound  selection(full) ┐
record-bound  selection(summ.)│
record-bound  Chrome article ─┼──▶  myna daemon  ──speak──▶  mlx-audio server
myna CLI (pbpaste | myna)     ┘     :8766 (Python)           :8765 (Kokoro af_heart)
                                    │  • pipeline: extract →
CC Stop hook (×4–8)  ──announce─────┤    summarise(Ollama) →
  (silent, per session)            │    chunk → play
                                    │  • state: idle/playing/paused
   Hammerspoon  ◀────/status────────┤  • CC registry (announced,
   menu bar + recorded hotkeys      │    unplayed outputs)
   + CC "pick" list  ────play───────┘
```

Three layers:
- **Engine** — mlx-audio server (exists), TTS only, unchanged.
- **Brain** — `myna` Python daemon, owns all logic and state.
- **Surface** — Hammerspoon config (menu bar + hotkeys + shortcut recorder), plus thin adapters (CLI, CC hook).

---

## 4. Component specs

### 4.1 mlx-audio server (engine) — existing, made 24/7
- **Does:** OpenAI-compatible TTS at `POST /v1/audio/speech`, `127.0.0.1:8765`, model `prince-canuma/Kokoro-82M`, voice `af_heart`, `lang_code: a`.
- **Change:** wrap launch in a LaunchAgent (`RunAtLoad` + `KeepAlive`). No code change.
- **Depends on:** the existing `~/.venvs/mlx-audio` venv and cached weights.

### 4.2 myna daemon (brain) — new, Python
- **Does:** single local HTTP service on `127.0.0.1:8766` that turns text into controllable audio, holds the one "now playing" state, and the Claude Code announce registry.
- **HTTP interface:**
  | Method/Path | Body / Params | Behavior |
  |---|---|---|
  | `POST /speak` | `{text? , url? , mode: "full"\|"summary", voice?, speed?, source?}` | Run pipeline and play. **Interrupts** any current playback. |
  | `POST /announce` | `{session_id, label, text}` | Store in registry. **Never plays.** |
  | `GET /registry` | — | List unplayed announced items: `[{id, label, age_s, preview}]` |
  | `POST /play/{id}` | `?mode=full\|summary` | Play a registered item; remove from registry. |
  | `POST /pause` `/resume` `/stop` | — | Control current playback. |
  | `POST /speed` | `{value: 0.5–2.0}` | Set speed for the next/subsequent requests. |
  | `GET /status` | — | `{state, now_playing, speed, registry_count, engine: "up"\|"loading"\|"down"}` |
- **Pipeline (internal):** `text|url → (extract if url) → (summarise if mode=summary) → chunk(~1500 chars on sentence/para boundaries) → for each chunk: POST mlx-audio → write WAV to temp → play`.
- **Player:** plays each chunk via an `afplay` subprocess, sequentially. **Pause = `SIGSTOP` the afplay PID; resume = `SIGCONT`.** Stop = kill child + drop remaining chunks. Speed is applied per-request via Kokoro's `speed` field at trigger time.
- **State:** held in memory; exposed via `/status` (Hammerspoon polls). Registry capped at last 10 items; entries cleared when played or after 30 min.
- **Depends on:** mlx-audio server (`:8765`), Ollama (`:11434`, summary mode only), `trafilatura` (URL extraction), Python 3.13 venv.
- **Run:** LaunchAgent (`RunAtLoad` + `KeepAlive`).

### 4.3 Hammerspoon config (surface) — new, Lua
- **Does:** menu bar icon + global hotkeys + shortcut recorder. The only GUI.
- **Menu bar:** icon mirrors `/status` — `▶` idle, `🔊` playing, `⏸` paused, `⚠️` daemon/engine down. Dropdown:
  - Pause/Resume, Stop, Speed submenu (0.75/1.0/1.25/1.5/2.0).
  - **Live CC list** from `/registry`: e.g. `ECS PYQs · 2m — ▶ Full | ✦ Summary`; clicking calls `/play/{id}`.
  - `Customize Shortcuts…`, `Open Logs`, `Restart Engine`.
- **Hotkeys:** loaded from the keybindings JSON; each bound to a daemon call. Actions: speak-selection-full, speak-selection-summary, read-chrome-article, pause/resume, stop.
  - *Speak selection:* simulate ⌘C, read pasteboard, `POST /speak`.
  - *Chrome article:* AppleScript gets the front Chrome tab URL → `POST /speak {url}`. On extraction failure the daemon returns a flag and Hammerspoon retries with the current selection.
- **Shortcut recorder:** `Customize Shortcuts…` opens a small `hs.webview` panel listing each action with its current chord and a **Record** button. Record captures the next key-down + modifiers via `hs.eventtap`, writes to the JSON config, and re-binds live (no restart). Conflicts are flagged.
- **Depends on:** Hammerspoon (free install), the daemon HTTP API.
- **Run:** Hammerspoon auto-launches at login and loads `~/.hammerspoon/init.lua` (which loads Myna's module).

### 4.4 Claude Code Stop hook — new, script in `~/.claude/settings.json`
- **Does:** on session stop, read the last assistant message from the transcript, `POST /announce {session_id, label: <cwd basename>, text}`. **Silent — never plays.**
- **Constraints:** POST-and-exit fast (must never block a session); no-op silently if the daemon is unreachable; truncate very long messages before sending.
- **Depends on:** the daemon `/announce` endpoint.

### 4.5 myna CLI — new, tiny script on `PATH`
- **Does:** `myna "text"`, `pbpaste | myna`, `myna --summary`, `myna --speed 1.25`. Thin client to `POST /speak`.
- **Depends on:** the daemon. Installed as a symlink in `~/.local/bin`.

### 4.6 Browser article reader
- **Does:** read the current Chrome page's main article. Hammerspoon supplies the front-tab URL; the daemon fetches and extracts with `trafilatura` (strips nav/ads), then runs the normal pipeline.
- **Fallback:** extraction failure (JS-rendered or login-walled page) → daemon signals failure → Hammerspoon retries with the page selection.
- **Rationale:** no Chrome extension to build or maintain. (A bookmarklet/extension that posts the rendered DOM is a documented future upgrade if server-side extraction proves insufficient.)

---

## 5. Configuration files

- `~/.config/myna/keybindings.json` — recorded shortcuts:
  ```json
  {
    "speak_selection_full":    { "mods": ["cmd","shift"], "key": "s" },
    "speak_selection_summary": { "mods": ["cmd","shift"], "key": "a" },
    "read_chrome_article":     { "mods": ["cmd","shift"], "key": "r" },
    "pause_resume":            { "mods": ["cmd","shift"], "key": "space" },
    "stop":                    { "mods": ["cmd","shift"], "key": "." }
  }
  ```
  Ships with these defaults; the recorder overwrites entries live.
- `~/.config/myna/config.json` — daemon settings: `voice` (`af_heart`), default `speed`, `summary_model` (`qwen3.5:4b`), `chunk_chars` (1500), ports.

---

## 6. Always-on model

- **Two LaunchAgents** in `~/Library/LaunchAgents/`: `dev.myna.engine.plist` (mlx-audio server) and `dev.myna.daemon.plist`. Both `RunAtLoad=true`, `KeepAlive=true`. Logs to `~/Library/Logs/myna-engine.log` and `~/Library/Logs/myna-daemon.log`.
- **Hammerspoon** launches at login (its own setting) and loads the Myna module.
- `install.sh` writes/loads the plists, symlinks the CLI, installs the Hammerspoon module, registers the CC hook, and verifies dependencies (Hammerspoon, `trafilatura`, Ollama model present).

---

## 7. Error handling / edge cases

- **Daemon down** → CLI and CC hook fail silently; Hammerspoon shows `⚠️` and a `Restart Engine` action.
- **CC hook** must POST-and-exit fast and no-op if the daemon is unreachable, so a stopped daemon never blocks a Claude session.
- **mlx-audio cold start** (first request loads the model) → `/status` reports `engine: "loading"`; the menu bar reflects it.
- **Empty text** → skipped. **Oversized text** → summary input is capped; full reading always chunks.
- **New `/speak` or `/play` while playing** → interrupts current playback (single now-playing, by design).
- **Registry overflow** → capped at last 10; entries clear on play or after 30 min.
- **Shortcut conflict** during recording → flagged in the recorder UI; not silently overwritten.

---

## 8. Testing

- **Engine smoke test** — the existing `curl … /v1/audio/speech … && afplay` from `kokoro-tts-setup.md`.
- **Daemon** — `/status` healthy; `/speak {"text":"hello","mode":"full"}` plays; pause → resume → stop transitions; `/speak {... "mode":"summary"}` hits Ollama and shortens.
- **CLI** — `echo "hi" | myna` plays; `myna --summary "<long text>"` shortens.
- **CC hook** — finishing a session POSTs to `/announce`; `/registry` shows it; menu bar lists it; clicking plays it; no auto-play occurs.
- **Browser** — `read_chrome_article` on a real article extracts and reads; a JS-walled page falls back to selection.
- **Shortcut recorder** — record a new chord for one action; it persists to JSON and rebinds without restart.

---

## 9. Out of scope (v1) / future

- Live mid-playback speed change and seek/replay-paragraph → upgrade path via `mpv` IPC socket (replaces afplay).
- Multi-item queue across articles.
- Voice cloning (Kokoro can't; Chatterbox/Fish path).
- Streaming first-byte via WebSocket (long-form is already fast enough).
- Chrome extension/bookmarklet for rendered-DOM extraction (only if `trafilatura` proves insufficient).
- Non-Chrome browsers.

---

## 10. Repo layout

```
~/Developer/myna/
├── daemon/            # Python: HTTP service, pipeline, player, registry
├── hammerspoon/       # Lua: menu bar, hotkeys, shortcut recorder (Myna module)
├── hooks/             # Claude Code Stop hook script
├── cli/               # myna CLI
├── launchagents/      # .plist templates (engine + daemon)
├── install.sh         # one-shot installer / verifier
├── docs/superpowers/specs/
└── README.md
```
