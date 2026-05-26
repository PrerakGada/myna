# Myna Daemon — Architecture

*Lane B exhaustive scan • Python FastAPI HTTP daemon at `daemon/myna/`*

## 1. Executive Summary

The daemon is a single-process **FastAPI** application that binds **`127.0.0.1:8766`** and brokers every TTS-adjacent request in the Myna stack. It sits between three classes of producer (the Swift menu-bar app, Hammerspoon v1, the Claude Code Stop hook) and one consumer (the **mlx-audio Kokoro engine** at `127.0.0.1:8765`), with an optional second consumer (an **Ollama** server at `127.0.0.1:11434`) used only for summarisation.

The daemon does five things, and only five:

1. **Text → audio**, by chunking text and forwarding each chunk to Kokoro's OpenAI-style `POST /v1/audio/speech`.
2. **URL → text**, via `trafilatura`.
3. **Text → summary**, via Ollama's `qwen3.5:4b` (configurable).
4. **Plays audio locally** (v1 `Player` shells out to `afplay`) for legacy callers.
5. **Tracks Claude Code announcements** in an in-memory registry for "pick later" playback.

Two API surfaces live in the same FastAPI app:

- **v1** (`/speak`, `/announce`, `/pause`, `/resume`, `/stop`, `/speed`, `/status`, `/registry`, `/play/{id}`): the original surface, used by Hammerspoon. Mutates the daemon-owned `Player`.
- **v2** (`/v2/synthesize`, `/v2/synthesize-summary`, `/v2/extract`, `/v2/summarize`, `/v2/health`, `/v2/status`, `/v2/voices`): added for the Swift app, which owns its own playback via AVAudioEngine and needs raw WAV bytes streamed back, not "fire-and-forget speak."

The two surfaces share state only via `app.state` — the same `Player`, `Registry`, config, and engine adapter — so the daemon is a single uvicorn worker. v2 endpoints intentionally never touch the v1 `Player` (enforced by a trip-wire fake in tests).

## 2. Technology Stack

| Layer | Choice | Version pin | Why |
|---|---|---|---|
| Language | Python | `>=3.10` declared in `pyproject.toml`; **3.13 in prod** (set via `install.sh:4` `PY313`) | type hints (PEP 604 `str \| None`), trafilatura wheels, modern asyncio |
| HTTP framework | FastAPI | unpinned (`fastapi`) | Pydantic v2 model validation, async-friendly, free OpenAPI |
| ASGI server | uvicorn[standard] | unpinned | `[standard]` pulls `httptools` + `uvloop`; the `--standard` extras matter for streaming responses on macOS |
| HTTP client | httpx | unpinned | sync `httpx.post` used inside generator threads; consistent timeout semantics |
| HTML→text | trafilatura | unpinned | best-in-class boilerplate stripping for the read-from-URL path |
| Validation | Pydantic v2 | bundled with FastAPI | v2 endpoint request/response shapes (`v2_types.py`) |
| Test runner | pytest | optional dep | 94 tests via `pytest daemon/` |

Build system is `setuptools>=61` (`pyproject.toml:17`). Package layout: `myna*` discovered under `daemon/` (`pyproject.toml:20-22`). Package version is `0.2.0`, sourced from `daemon/myna/__init__.py:1` and surfaced in `/v2/health` and `/v2/status.daemon.version`.

## 3. Process Model

- **Single uvicorn worker**, started by `daemon/myna/__main__.py:9`:
  ```python
  uvicorn.run(create_app(cfg), host="127.0.0.1", port=cfg["daemon_port"])
  ```
  Launched in production by the `dev.myna.daemon` LaunchAgent (see `install.sh:66-71`).
- **Shared state lives on `app.state`** (set in `app.py:90-104`):
  - `app.state.cfg` — the merged config dict.
  - `app.state.speed` — mutable global speed (clamped 0.5–2.0, mutated by `POST /speed`).
  - `app.state.player` — the v1 `Player` instance (owns the afplay subprocess).
  - `app.state.registry` — in-memory `Registry` of CC announcements.
  - `app.state.synthesize / engine_up / summarize / extract` — function references that tests monkey-patch (this is the seam, not classes).
  - `app.state.started_at` — for uptime (`/v2/status.daemon.uptime_s`).
  - `app.state.last_engine_check_at / last_engine_status` — 1s engine-health cache.
  - `app.state.voices_cache / voices_cache_at` — 5-minute voice-list cache.
- **No global httpx client**: each call constructs a fresh `httpx.post(...)` (`engine.py:14`, `summarize.py:24`, `app.py:233`). This is a known tradeoff — cheap to reason about, expensive under sustained load (not a real concern at local-only RPS).
- **Threading**: the v1 `Player` runs playback in a daemon thread (`player.py:31-34`); FastAPI handlers themselves are sync (`def`, not `async def`). Streaming responses for `/v2/synthesize` are produced by a sync generator (`app.py:382-406`), which uvicorn runs in a threadpool.
- **Graceful shutdown**: there is no explicit `@app.on_event("shutdown")`. `Player.stop()` (`player.py:70-81`) does kill the subprocess and join the thread (timeout 1s), but it is only invoked from `/stop`, `/speak` start, or the next `play()` call — process termination relies on `afplay` getting SIGTERM from its parent.

## 4. Module-by-module Breakdown

### `daemon/myna/__init__.py` (1 line)

- `__version__ = "0.2.0"` — the only source of truth for the daemon version, re-exported by `app.py:13` and embedded in `/v2/health` and `/v2/status.daemon.version`.

### `daemon/myna/__main__.py` (14 lines)

- `main()` (`__main__.py:7-9`) loads config and runs uvicorn on `127.0.0.1:<daemon_port>`.
- Imports: `uvicorn`, `.app.create_app`, `.config.load_config`.
- Side effects: binds a TCP socket; no other I/O.
- **Known gap**: no argparse / no `--version` / no `--help`. `brew test myna-daemon` currently fails because the formula tries `myna-daemon --version` — see `HANDOFF.md`.

### `daemon/myna/app.py` (545 lines, the heart)

#### Public

- `create_app(config: dict | None = None) -> FastAPI` (`app.py:87-544`) — the FastAPI factory. Tests build their own app via this entrypoint and then patch `app.state.{synthesize,engine_up,summarize,extract,player}` to inject fakes.
- Pydantic request models defined inline:
  - `SpeakReq` (`app.py:45-51`) — v1 `/speak` body. Fields: `text`, `url`, `mode="full"`, `voice`, `speed`, `source`.
  - `AnnounceReq` (`app.py:54-57`) — v1 `/announce` body. Required: `session_id`, `label`, `text`.
  - `SpeedReq` (`app.py:60-61`) — v1 `/speed` body. Required: `value`.
- Helpers `_voice_label(voice_id)` (`app.py:64-76`) and `_voice_lang(voice_id)` (`app.py:79-84`) decode Kokoro's `<lang><gender>_<name>` naming convention into human-readable labels.

#### Private (closure-captured inside `create_app`)

- `_producer(text, voice, speed)` (`app.py:108-121`) — generator that chunks text, calls `app.state.synthesize` per chunk, writes each WAV to `~/.cache/myna/tmp/<uuid>.wav`, yields the path. Used by `_speak`. **Tempdir is never garbage-collected** — files accumulate. Pre-existing tech debt.
- `_speak(req: SpeakReq)` (`app.py:123-146`) — the v1 pipeline. Extracts if URL given, summarises if mode=summary, then `app.state.player.play(_producer(...), meta=...)`.
- `_check_engine_cached()` (`app.py:203-218`) — 1s-TTL cached engine health probe; always swallows exceptions and returns False.
- `_engine_check_age_s()` (`app.py:220-223`) — for `/v2/status.engine.last_check_age_s`.
- `_fetch_voices_from_engine()` (`app.py:225-263`) — queries Kokoro `GET /v1/voices`, parses three response shapes (list of strings, list of dicts, dict-with-voices-key), falls back to a hardcoded list (`["af_heart","af_bella","am_michael","am_adam"]`, `app.py:42`) if the call fails or returns empty. Always ensures the configured default voice is in the list.
- `_prepare_v2_text(req, *, mode)` (`app.py:265-310`) — the v2 text/url/summary pipeline. Differs from `_speak` only in error shape: raises `HTTPException` with a `{ok, reason}` detail so FastAPI returns a JSON body and HTTP 400.
- `_v2_synthesize_response(req, *, mode)` (`app.py:312-411`) — the streaming pipeline. Pre-checks engine, eagerly synthesises the first chunk (so engine errors surface as a clean 502 before any bytes are sent), then yields a `multipart/mixed; boundary=mynachunk` stream of `audio/wav` parts followed by a final `application/json` summary part. Clamps `speed` to `[0.5, 2.0]` (`app.py:338`).

#### Side effects

- `~/.cache/myna/tmp/` directory creation + WAV writes (v1 `_producer` only).
- Outbound HTTP to `cfg["engine_url"]` (default `http://127.0.0.1:8765`) and `cfg["ollama_url"]` (`http://127.0.0.1:11434`).
- Subprocess spawn (`afplay`) via the `Player`.

#### Threading

- All route handlers are sync (`def`, not `async def`). uvicorn runs them in a threadpool.
- The `_v2_synthesize_response` generator is sync; uvicorn streams it from a thread.
- Race-safety on `app.state`: writes to `voices_cache`, `last_engine_check_at`, and `speed` are not locked. With one worker and short-lived requests this has not bitten in practice, but two simultaneous `/v2/voices` requests on a cold cache would each fetch from Kokoro before either set the cache — wasted work, not a bug.

#### Cross-module imports

`app.py` is the only module that pulls everything else together. Direct imports:

| From | Imports |
|---|---|
| `. (myna)` | `__version__`, `chunking`, `engine`, `extract as extract_mod`, `summarize as summarize_mod` |
| `.config` | `load_config` |
| `.player` | `Player` |
| `.registry` | `Registry` |
| `.v2_types` | every `V2*` Pydantic model |

### `daemon/myna/chunking.py` (29 lines)

- `chunk_text(text: str, max_chars: int = 1500) -> list[str]` (`chunking.py:4-28`).
- Splits on sentence boundaries `(?<=[.!?])\s+` (`chunking.py:12`), greedy-packs into bins ≤ `max_chars`. A single sentence longer than `max_chars` is **hard-split** mid-word (`chunking.py:23-25`).
- Pure function. No I/O. No async. Stateless.

### `daemon/myna/config.py` (28 lines)

- Module constants: `CONFIG_DIR = ~/.config/myna/`, `CONFIG_PATH = CONFIG_DIR/config.json` (`config.py:5-6`).
- `DEFAULTS` dict (`config.py:8-20`):
  - `engine_url: "http://127.0.0.1:8765"`
  - `ollama_url: "http://127.0.0.1:11434"`
  - `voice: "af_heart"`
  - `lang_code: "a"` (English/American per Kokoro convention)
  - `model: "prince-canuma/Kokoro-82M"`
  - `summary_model: "qwen3.5:4b"`
  - `summary_think: False`
  - `summary_timeout: 60.0`
  - `speed: 1.0`
  - `chunk_chars: 1500`
  - `daemon_port: 8766`
- `load_config() -> dict` (`config.py:23-27`) — defaults overlaid with whatever is in `config.json` (no validation; trusts the JSON).
- **Known gap**: `MYNA_CONFIG_DIR` env var is **ignored**. The path is hardcoded.

### `daemon/myna/engine.py` (35 lines)

- `synthesize(text, *, voice, speed, base_url, model="prince-canuma/Kokoro-82M", lang_code="a", timeout=180.0) -> bytes` (`engine.py:4-27`). Posts to `{base_url}/v1/audio/speech` with `{model, input, voice, response_format:"wav", lang_code, speed}`. Returns the raw WAV bytes. Raises `httpx.HTTPStatusError` on non-2xx (passed through to the route's exception handlers).
- `engine_up(base_url, timeout=2.0) -> bool` (`engine.py:30-35`). GETs `{base_url}/v1/models`; returns True on 2xx, swallows all exceptions and returns False.

### `daemon/myna/extract.py` (12 lines)

- `extract_article(url: str) -> str | None` (`extract.py:4-12`). Thin wrapper over `trafilatura.fetch_url` + `trafilatura.extract(..., include_comments=False, include_tables=False)`. Returns the cleaned article body or `None`.
- **Note**: the signature says `str | None`, but `/v2/extract` in `app.py:494-511` *also* handles a `dict` return shape with `text/title/byline`. The fixture `docs/native-app/fixtures/extract-response.json` includes title and byline. This means the extract layer is **expected to grow** a dict return; today it returns plain strings. v2 tolerates both.

### `daemon/myna/player.py` (86 lines)

- `Player(spawn=None, sig=os.kill)` (`player.py:8-23`). Constructor injects the subprocess spawner (default `subprocess.Popen(["afplay", path])`) and the signal sender — the seam tests use.
- `play(producer, meta)` (`player.py:25-34`) — stops any current playback, replaces it with a new thread that iterates the producer and plays each WAV file in sequence.
- `_run(producer)` (`player.py:36-46`) — the playback loop. Cleans up state on exit.
- `_play_file(path)` (`player.py:48-56`) — spawns afplay, polls `proc.poll()` until done or `_stop` is set. The poll loop sleeps 50ms (`player.py:56`).
- `pause()` / `resume()` (`player.py:58-68`) — sends SIGSTOP / SIGCONT to the afplay PID. This is genuinely the Unix way and works on macOS.
- `stop()` (`player.py:70-81`) — kills the process, joins the thread (1s timeout), resets state.
- `status()` (`player.py:83-85`) — returns `{state, now_playing}`. `state` ∈ `{"idle", "playing", "paused"}`. `now_playing` is whatever `meta` was passed to `play()`.

Threading: a single `RLock` (`player.py:18`) guards `_state`, `_proc`, `_meta`. The playback thread is a daemon thread.

### `daemon/myna/registry.py` (49 lines)

- `Registry(cap=10, ttl=1800, clock=time.time)` (`registry.py:5-12`). In-memory FIFO of CC announcements with bounded size (10) and TTL (30 min). `clock` is injected for tests.
- `add(label, text) -> str` (`registry.py:14-23`) — generates an 8-hex id, appends, prunes.
- `prune()` (`registry.py:25-29`) — drops expired entries, then truncates to `cap`.
- `list_items() -> list[dict]` (`registry.py:31-42`) — returns wire-shape items (`id, label, age_s, preview`) where `preview` is `text[:60]`.
- `pop(item_id) -> dict | None` (`registry.py:44-48`) — removes and returns the full record (with the original `text`) so the speak path can play it.

No persistence. A daemon restart wipes the registry.

### `daemon/myna/summarize.py` (35 lines)

- `_PROMPT` (`summarize.py:3-7`) — the spoken-style summary prompt. Asks for ≤150 words, no markdown.
- `build_summary_prompt(text)` (`summarize.py:10-11`) — pure formatter.
- `summarize(text, *, model, base_url, think=False, timeout=60.0) -> str` (`summarize.py:14-35`). Posts to `{base_url}/api/generate` (Ollama). `think=False` (the default) suppresses reasoning-model "thinking" so a summary returns in seconds — this is intentional and tested (`test_summarize.py:33-34`).
- Raises `httpx.HTTPStatusError` on non-2xx and `KeyError` if the Ollama response is malformed.

### `daemon/myna/v2_types.py` (107 lines)

Pure Pydantic v2 model file. Documented in detail in `data-models-daemon.md`. Models:

`V2SynthesizeReq`, `V2ExtractReq`, `V2ExtractResp`, `V2SummarizeReq`, `V2SummarizeResp`, `V2EngineInfo`, `V2DaemonInfo`, `V2ConfigInfo`, `V2RegistryItem`, `V2RegistryInfo`, `V2V1PlayerInfo`, `V2Status`, `V2Voice`, `V2Voices`, `V2Health`.

The file header says "Canonical schemas are documented in docs/native-app/API_CONTRACT.md § 5. JSON shapes must match the test fixtures in docs/native-app/fixtures/." That's the binding contract.

## 5. Endpoints (Summary)

15 routes total. Full schemas + examples live in **`api-contracts-daemon.md`**.

| Surface | Routes |
|---|---|
| v1 (Hammerspoon, hook) | `POST /speak`, `POST /announce`, `GET /registry`, `POST /play/{item_id}`, `POST /pause`, `POST /resume`, `POST /stop`, `POST /speed`, `GET /status` |
| v2 (Swift app) | `POST /v2/synthesize`, `POST /v2/synthesize-summary`, `GET /v2/status`, `GET /v2/voices`, `POST /v2/extract`, `POST /v2/summarize`, `GET /v2/health` |

## 6. Engine Integration (Kokoro)

- `engine.synthesize` (`engine.py:4-27`) is a thin client over Kokoro's OpenAI-compatible `POST /v1/audio/speech`. Request body is exactly the OpenAI shape plus `lang_code` and `speed`.
- 180s default timeout — generous because Kokoro on first request after the engine LaunchAgent starts can take 10–20s to warm up.
- `engine_up` (`engine.py:30-35`) hits `GET /v1/models` with a 2s timeout. This is the cheapest no-op endpoint Kokoro exposes.
- The daemon never streams a single WAV — Kokoro returns the entire WAV as one blob and we forward it as one multipart part. The "streaming" in `/v2/synthesize` is **chunk-of-text → one WAV per chunk**, not WAV byte streaming.
- Failure mapping:
  - Engine down at pre-check → HTTP 502, body `{ok:false, reason:"engine_down"}` (`app.py:317-321`).
  - First-chunk synth fails → HTTP 502, body `{ok:false, reason:"engine_error", detail:<str(exc)>}` (`app.py:353-357`).
  - Mid-stream chunk fails → stream **terminates cleanly** with a closing JSON part containing the actual chunk count (`app.py:398-406`). The client gets `ok:true` but a smaller `chunks` than `X-Chunk-Total-Estimate` promised. **This is a known issue** — see § 18.

## 7. Extraction Pipeline

- `extract.extract_article(url)` (`extract.py:4-12`) calls `trafilatura.fetch_url` then `trafilatura.extract(include_comments=False, include_tables=False)`.
- The v2 endpoint adds a strict URL allow-list: only `http://` or `https://` are accepted (`app.py:489-493`). `file://`, `myna://`, and the like are rejected as `invalid_url`.
- No JS rendering — single HTTP GET, parse the HTML. JS-heavy SPAs typically return empty body → `{ok:false, reason:"extract_failed"}`.
- The v1 path (`POST /speak` with `url`) does **not** validate the scheme (`app.py:125-128`). Tightening v1 would risk breaking Hammerspoon — left intentionally lax.

## 8. Summarisation

- Ollama at `cfg["ollama_url"]` (default `http://127.0.0.1:11434`).
- Model: `cfg["summary_model"]` (default `qwen3.5:4b`).
- `summary_think` is the toggle that matters most: with reasoning models (qwen3.5 family), `think=False` cuts response time from minutes to seconds because Ollama suppresses the `<think>...</think>` segment. Default is `False`, tested at `test_summarize.py:33-34`.
- `summary_timeout` (default 60s) is the httpx timeout — relevant on first request to a cold Ollama model.
- **Graceful degradation when Ollama is absent**: zero. If Ollama isn't running, `httpx.post` raises `ConnectError`, the v1 `_speak` will let the exception bubble (500 from FastAPI's default handler), and the v2 `/v2/summarize` will also surface a 500. `install.sh:9` only warns — it doesn't make Ollama a hard prereq. The daemon will start fine without it; the failure mode is per-request.

## 9. Chunking

- `chunking.chunk_text(text, max_chars)` (`chunking.py:4-28`).
- Strategy:
  1. Strip whitespace.
  2. Sentence-split on `(?<=[.!?])\s+` (look-behind for terminal punctuation followed by whitespace).
  3. Greedy-pack sentences into bins, joining with a single space.
  4. Any single sentence > `max_chars` is hard-sliced into `max_chars`-sized substrings (no word boundary respect — Kokoro tolerates this for English).
- Default `max_chars = 1500` (config) — tuned for Kokoro latency. Lower values (500–1000) reduce time-to-first-audio for long articles; higher values cut overhead but make pause-between-chunks more audible.
- Returns `[]` for empty input — both `app.py:327-331` and the test at `test_chunking.py:5` cover this.

## 10. Player (v1)

- The v1 `_speak` path (`app.py:123-146`) is the entire reason `Player` exists.
- Flow:
  1. Text and/or URL is normalised → final text string.
  2. `_producer` is a generator that synthesises one chunk at a time, writes the WAV to `~/.cache/myna/tmp/<uuid>.wav`, yields the path.
  3. `Player.play(producer, meta)` runs the producer-consumer in a thread, shelling `afplay` per file.
- **Tempdir tech debt**: `~/.cache/myna/tmp/` is created on first use (`app.py:106`, `app.py:109`) and **nothing ever deletes** the WAVs. After heavy use, the directory grows unbounded. Sweep with a cron, or manually periodically. Acceptable for v0.x; should be tracked.
- Pause/resume use SIGSTOP/SIGCONT — works flawlessly with afplay because afplay is a single-threaded foreground audio process.

## 11. Registry (Claude Code Announce)

- `registry.Registry` is the in-memory store of "silent" CC outputs.
- Hammerspoon's CC hook (`hooks/myna-cc-announce.py`) posts the last assistant reply to `POST /announce` whenever a CC session ends.
- Items are capped at 10, TTL 30 min — design tradeoff: lossy on purpose, no persistence, only the most recent / most relevant items survive.
- The Swift app reads `/registry` (or `/v2/status.registry.items`) and shows a menu of "pick something Claude said" with full/summary playback.
- `POST /play/{id}` (`app.py:163-168`) pops the item — once played, it's gone from the registry.
- **De-duplication semantics**: there are none. Two announcements with identical text from the same `session_id` create two registry items. CC's Stop hook fires once per turn, so this rarely matters; if a turn fires twice (rare), you get two entries.
- **Pick semantics**: only `POST /play/{id}` pops; `GET /registry` is non-destructive.

## 12. Config

`~/.config/myna/config.json` is optional. The shape is "any subset of `DEFAULTS` keys":

```json
{
  "voice": "am_michael",
  "speed": 1.25,
  "summary_model": "qwen3.5:7b",
  "summary_think": false,
  "summary_timeout": 90.0,
  "chunk_chars": 1000,
  "engine_url": "http://127.0.0.1:8765",
  "ollama_url": "http://127.0.0.1:11434",
  "lang_code": "a",
  "model": "prince-canuma/Kokoro-82M",
  "daemon_port": 8766
}
```

Unknown keys are accepted and ignored (Python's `dict.update`). Missing keys take the default.

**Known gap**: `MYNA_CONFIG_DIR` is **ignored** — the daemon always reads from `~/.config/myna/config.json` (`config.py:5-6`). Tests override `c.CONFIG_PATH` directly. If a user installs Myna under a custom XDG dir, the daemon will silently use the home directory anyway.

## 13. v2 Type Contract (overview)

`v2_types.py` defines 15 Pydantic models. They are the wire contract with the Swift app via `apps/macos/Sources/Network/DaemonTypes.swift`. Highlights:

- `V2SynthesizeReq` — request body for `/v2/synthesize`. All-optional except no body at all is rejected.
- `V2Status` — top-level status response: state + engine + daemon + config + registry + v1_player. Five nested models.
- `V2Voices` — `{voices: [...], engine?: "down"}`. `engine` is **only emitted when down** (response_model_exclude_none=True on the route).
- `V2ExtractResp` and `V2SummarizeResp` — also use `exclude_none=True` so `success` bodies don't leak null `reason` fields.

Full schemas, validators, cross-references to Swift types, and JSON examples are in **`data-models-daemon.md`**.

## 14. Source Tree

```
daemon/
├── pyproject.toml              # setuptools build, fastapi+uvicorn+httpx+trafilatura
├── myna/
│   ├── __init__.py             # __version__ = "0.2.0"
│   ├── __main__.py             # uvicorn entrypoint, host 127.0.0.1
│   ├── app.py                  # FastAPI factory, 15 routes, ~545 lines
│   ├── chunking.py             # sentence-boundary chunker
│   ├── config.py               # ~/.config/myna/config.json loader, DEFAULTS
│   ├── engine.py               # Kokoro client: synthesize(), engine_up()
│   ├── extract.py              # trafilatura wrapper
│   ├── player.py               # v1 afplay subprocess controller w/ SIGSTOP pause
│   ├── registry.py             # in-memory CC announcement store
│   ├── summarize.py            # Ollama client + spoken-style prompt
│   └── v2_types.py             # Pydantic v2 wire types for /v2 endpoints
└── tests/
    ├── __init__.py             # (empty)
    ├── v2_helpers.py           # FakePlayer trip-wire, make_client, parse_multipart
    ├── test_app.py             # v1 endpoint coverage
    ├── test_cc_hook.py         # the CC Stop hook script (loaded from hooks/)
    ├── test_chunking.py        # chunker invariants
    ├── test_config.py          # defaults + override merge
    ├── test_engine.py          # synth body shape, engine_up boolean
    ├── test_extract.py         # trafilatura monkeypatching
    ├── test_player.py          # play/pause/resume/stop with FakeProc
    ├── test_registry.py        # TTL, cap, pop semantics
    ├── test_summarize.py       # Ollama body, think toggle
    ├── test_v2_audit_fixes.py  # regression for the Lane C audit findings
    ├── test_v2_extract.py      # /v2/extract success + failure + URL validation
    ├── test_v2_health.py       # /v2/health + cache TTL
    ├── test_v2_status.py       # /v2/status shape matches fixture exactly
    ├── test_v2_summarize.py    # /v2/summarize success + reject empty
    ├── test_v2_synthesize.py   # multipart shape + first-chunk eager error
    └── test_v2_voices.py       # /v2/voices Kokoro shapes + fallback + cache
```

## 15. Testing Strategy

**94 tests total**, all green, all under 5s wall clock on an M-series Mac:

- **33 v1 tests** (`test_app.py`, `test_chunking.py`, `test_config.py`, `test_engine.py`, `test_extract.py`, `test_player.py`, `test_registry.py`, `test_summarize.py`, `test_cc_hook.py`).
- **49 v2 tests** (`test_v2_extract.py`, `test_v2_health.py`, `test_v2_status.py`, `test_v2_summarize.py`, `test_v2_synthesize.py`, `test_v2_voices.py`).
- **12 audit-regression tests** (`test_v2_audit_fixes.py`) — one per finding in `docs/native-app/audits/AUDIT_REPORT.md`. Pin specific bugs so they cannot return silently.

Patterns worth knowing:

- **FakePlayer trip-wire** (`tests/v2_helpers.py:22-48`): v2 tests inject a player that records every method call. Any v2 endpoint that calls `.play/.pause/.resume/.stop` fails the test. Enforces the architectural rule that the Swift app owns playback.
- **Function-reference seam**: tests monkeypatch `app.state.{synthesize,engine_up,summarize,extract}` rather than the modules. The route handlers go through `app.state` indirection, so this works without `unittest.mock.patch` gymnastics.
- **Fixture sharing with Swift**: `tests/v2_helpers.py:14-19` resolves `FIXTURES_DIR` to `docs/native-app/fixtures/`. Both daemon tests and Swift `DaemonTypesTests` decode the same JSON files. A schema change in either lane fails the other lane's tests until both are updated.
- **`_keys_deep` shape matcher** (`test_v2_status.py:16-34`): walks the fixture and the response, asserts the set of dotted-path keys is identical. Catches both missing and extra fields.
- **Multipart parser** (`tests/v2_helpers.py:82-114`): a 30-line parser specifically for `/v2/synthesize`. Mirrors what the Swift `SynthesizeStream` does.

Run: `pytest daemon/` (or `cd daemon && pytest`).

## 16. Performance & Limits

- **Bind**: `127.0.0.1:8766`. Not configurable to bind elsewhere (host is hardcoded in `__main__.py:9`). Port is configurable.
- **Payload limits**: none enforced by the daemon. Whatever uvicorn defaults to (8 KiB per header, no body limit by default). Pragma: send 8000 chars max via the CC hook (`hooks/myna-cc-announce.py:67`), but `/speak` and `/v2/synthesize` take whatever you give them.
- **Expected RPS**: 1–5 req/s steady-state for a single user; the daemon is fine to 50+ but local-only, so it's not tested under load.
- **Chunk size budgets**: `chunk_chars=1500` default. The Kokoro engine on M2 produces ~1s of audio per ~50ms of compute for English, so a 1500-char chunk synthesises in roughly 4–8s. Latency to first byte through `/v2/synthesize` is dominated by Kokoro synthesis of the first chunk.
- **Cache TTLs**:
  - Engine health: **1.0s** (`app.py:38`). Reused across `/v2/health` and `/v2/status`.
  - Voice list: **300s / 5 min** (`app.py:39`). Reset on daemon restart only.

## 17. Security Posture

- **127.0.0.1 only.** No external bind. No CORS handling — there is no browser in the threat model.
- **No auth.** Intentional. The daemon trusts every caller on the loopback interface. macOS process isolation is the only barrier; a malicious user-space process can absolutely speak whatever it wants. Mitigation is "don't run untrusted code on your laptop," which is true of every desktop daemon.
- **No shell=True, no eval, no exec.** `subprocess.Popen(["afplay", path])` is fixed argv; `path` is a daemon-generated UUID under `~/.cache/myna/tmp/`. No user input reaches a shell.
- **No telemetry.** No analytics. No outbound HTTP except to `127.0.0.1:8765` (Kokoro) and `127.0.0.1:11434` (Ollama) and to whatever URL the user passes to `/speak url=...` or `/v2/extract url=...` via `trafilatura.fetch_url`.
- **URL validation on v2 extract** (`app.py:489-493`): only `http://` and `https://` accepted. v1 `/speak url=...` does **not** validate the scheme — kept lax to not break Hammerspoon.
- **Trafilatura is the only third-party HTML-parsing surface.** It is a well-maintained library, but any HTML parser is in principle a fuzzing target. Mitigation: short request timeouts; the daemon is single-user.

## 18. Known Issues / Tech Debt

1. **Mid-stream synthesize truncation reports `ok:true`** (`app.py:398-406`). If chunk 5 of 10 fails inside `/v2/synthesize`, the stream breaks cleanly and the closing JSON part says `{"ok": true, "chunks": 5, ...}`. The client believes success despite a 50% loss. Better: emit `{"ok": false, "reason": "engine_error_mid_stream", "chunks": 5, "expected": 10}`.
2. **`/v2/status.state` never emits `synthesizing` or `streaming`.** Code path at `app.py:429` only returns `"down"` or `"idle"`. The Swift `DaemonState` enum (`apps/macos/Sources/Network/DaemonTypes.swift:5-16`) and `API_CONTRACT.md:154` expect four states; two of them are unreachable. The Swift side decodes them as `.unknown` (no error), but the contract drifts.
3. **v1 tempdir leak.** `~/.cache/myna/tmp/*.wav` is never cleaned. Use `find ~/.cache/myna/tmp -mtime +1 -delete` in a launchd timer if it ever matters.
4. **No argparse on `python -m myna`.** `myna-daemon --version` fails. Breaks `brew test myna-daemon`. Trivial fix.
5. **`MYNA_CONFIG_DIR` is ignored.** Hardcoded to `~/.config/myna/` (`config.py:5`).
6. **No `Player.stop()` on uvicorn shutdown.** Daemon process termination relies on the OS sending SIGTERM to afplay via the process group. Works in practice (LaunchAgent kills the whole tree).
7. **No httpx connection pooling.** Each engine/Ollama call is a fresh connection. Cheap to fix with a module-level `httpx.Client`; not painful enough to fix yet.
8. **Race on `voices_cache`.** Two simultaneous cold-cache `/v2/voices` requests will both fetch from Kokoro; one will overwrite the other. Wasted work, not corrupted data.
9. **`engine: null` was leaking from `/v2/voices`** and `reason: null` from `/v2/extract` and `/v2/summarize` success bodies. **Fixed** via `response_model_exclude_none=True` (`app.py:458, 478-482, 513-517`). Regression-pinned by `test_v2_audit_fixes.py:14-78`.

## 19. Risks & Open Questions

- **What happens if Ollama is down?** v1 `_speak mode=summary` → 500 from FastAPI default exception handler. v2 `/v2/summarize` → same. No graceful "we couldn't summarize, here's the original text" fallback. Should we 502 with `reason: "summary_engine_down"` to make the Swift app's life easier?
- **What if trafilatura returns empty?** v1 → `{ok:false, reason:"extract_failed"}` (HTTP 200). v2 → same (HTTP 200, body `{ok:false, reason}`). Consistent.
- **Concurrent requests touching `app.state`?** The v1 `Player` is the only mutable shared state under load. `Player.play()` calls `stop()` first, so a second `/speak` cleanly preempts the first. v2 endpoints don't touch the player at all. The risk is `app.state.speed` being mutated by `POST /speed` mid-`/v2/synthesize` — but `/v2/synthesize` reads `req.speed` (not `app.state.speed`), so this is fine.
- **Memory pressure from registry growth?** Capped at 10 items × 8000 chars = ~80 KB. Negligible.
- **What if Kokoro takes 30s to warm up after engine LaunchAgent boot?** First `/v2/health` returns `engine_up: false`. The Swift app retries; eventually it goes up. No special handling — the 1s cache will just re-probe.
- **Mid-stream client disconnect?** uvicorn raises in the generator when the client TCP closes; we never see it because the next `yield` faults and the generator is cleaned up. No leaked resources because no resources are held across yields (each chunk is request-local).
- **What if `chunk_chars` is set to `0`?** `chunking.chunk_text(text, 0)` would loop forever in the hard-split branch (`while len(cur) > 0: chunks.append(cur[:0]); cur = cur[0:]`). Validate this in v2 request models.
