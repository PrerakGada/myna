# Myna Daemon — Development Guide

*Lane B exhaustive scan • How to run, test, extend, and debug `daemon/myna/`*

---

## 1. Prerequisites

| Tool | Version | How it's used | Hard requirement? |
|---|---|---|---|
| Python | **3.13** in prod (3.10+ technically supported per `pyproject.toml:5`) | runs the daemon | yes |
| `~/.venvs/myna` | a Python venv created by `install.sh:14` | isolates the daemon's deps | yes |
| mlx-audio Kokoro server at `127.0.0.1:8765` | latest from your `~/.venvs/mlx-audio` | actually generates audio | yes for end-to-end; no for unit tests |
| Ollama with `qwen3.5:4b` pulled | latest Ollama | summary mode only | optional — summary endpoints fail without it |
| `afplay` | macOS built-in | v1 player plays WAVs | yes for v1 `_speak`, no for v2 |

Prerak's prod setup (from `install.sh:4`):

```bash
export PY313=$HOME/.local/bin/python3.13
```

The daemon's venv lives at `~/.venvs/myna`. The mlx-audio engine's venv lives separately at `~/.venvs/mlx-audio` and is managed independently (the daemon never imports it; it only talks HTTP).

---

## 2. Install

### Production install (what `install.sh` does)

```bash
$HOME/.venvs/myna/bin/pip install -e $REPO/daemon
```

This installs the `myna` package editable from `daemon/`. Editable install means edits to `.py` files are picked up on the next process restart without a reinstall — but uvicorn does not hot-reload (see § 9).

### Fresh dev install

```bash
python3.13 -m venv ~/.venvs/myna
~/.venvs/myna/bin/pip install --upgrade pip
~/.venvs/myna/bin/pip install -e /path/to/myna/daemon
~/.venvs/myna/bin/pip install pytest  # for tests
```

### Homebrew tap (end-user install)

```bash
brew install PrerakGada/tap/myna-daemon
```

This uses `tap/Formula/myna-daemon.rb`. See `daemon/myna/__main__.py` § "Known gap" — currently no `--version` flag, so `brew test myna-daemon` is wired weakly.

---

## 3. Run

### Foreground (dev)

```bash
~/.venvs/myna/bin/python -m myna
```

Entrypoint: `daemon/myna/__main__.py:9` calls `uvicorn.run(create_app(cfg), host="127.0.0.1", port=cfg["daemon_port"])`. Logs to stdout/stderr.

### As a LaunchAgent (prod)

`install.sh:66-71` installs and loads `~/Library/LaunchAgents/dev.myna.daemon.plist`. Inspect:

```bash
launchctl list | grep myna
launchctl unload ~/Library/LaunchAgents/dev.myna.daemon.plist
launchctl load   ~/Library/LaunchAgents/dev.myna.daemon.plist
```

The plist template lives at `launchagents/dev.myna.daemon.plist.template`. `__HOME__` is replaced by `$HOME` during install.

### As a Homebrew service

```bash
brew services start  PrerakGada/tap/myna-daemon
brew services stop   PrerakGada/tap/myna-daemon
brew services list
```

---

## 4. Test

```bash
pytest daemon/                  # all 94 tests
pytest daemon/tests/test_v2_synthesize.py -v
pytest daemon/ -k "voices"     # any test with "voices" in the name
pytest daemon/ -x --ff         # stop on first failure, run prev failures first
```

### What's covered

- **33 v1 tests** — every v1 endpoint + the helper modules (chunking, config, engine, extract, player, registry, summarize).
- **49 v2 tests** — every v2 endpoint, cross-checked against the JSON fixtures in `docs/native-app/fixtures/`.
- **12 audit-regression tests** in `test_v2_audit_fixes.py` — one per finding in `docs/native-app/audits/AUDIT_REPORT.md`, so a known bug cannot return silently.

### The seam

Tests build a `TestClient` via `make_client()` (`tests/v2_helpers.py:51-79` for v2; `tests/test_app.py:32-42` for v1). Both helpers:

1. `create_app(cfg)`.
2. Replace `app.state.player` with a `FakePlayer`.
3. Replace `app.state.{synthesize, engine_up, summarize, extract}` with lambdas returning canned values.

This means **you can write a new test without monkeypatching modules** — just override on `app.state`.

### FakePlayer trip-wire

`tests/v2_helpers.py:22-48` is a `FakePlayer` whose `play / pause / resume / stop` methods record the call. If any v2 test ever sees a recorded call, the test fails. This enforces the architectural rule: v2 endpoints **never** touch the v1 player.

If you need to assert "this endpoint definitely didn't touch the player":

```python
assert not any(c[0] in {"play","pause","resume","stop"} for c in fp.calls)
```

(Pattern from `test_v2_synthesize.py:221-226`.)

### Fixture-shape tests

`test_v2_status.py:_keys_deep` (`test_v2_status.py:16-34`) walks both the fixture and the live response, asserts identical dotted-path key sets. Apply this whenever you add a top-level v2 response: write the fixture, write the test, assert key parity.

---

## 5. Adding a New Endpoint

Working example: adding `POST /v2/transcribe` (hypothetical).

1. **Define the request/response models** in `daemon/myna/v2_types.py`:

   ```python
   class V2TranscribeReq(BaseModel):
       audio_url: str

   class V2TranscribeResp(BaseModel):
       ok: bool
       text: Optional[str] = None
       reason: Optional[str] = None
   ```

2. **Add the route handler** in `daemon/myna/app.py` (above the closing `return app`):

   ```python
   @app.post(
       "/v2/transcribe",
       response_model=V2TranscribeResp,
       response_model_exclude_none=True,
   )
   def v2_transcribe(req: V2TranscribeReq) -> V2TranscribeResp:
       # validate → fan out → respond
       ...
   ```

   Always pass `response_model_exclude_none=True` so success bodies don't leak `null reason` fields. This is the lesson from the audit (see `test_v2_audit_fixes.py:38-78`).

3. **Add an `app.state` seam** if the handler talks to anything external. Pattern:

   ```python
   # at the top of create_app(), with the others:
   app.state.transcribe = my_module.transcribe
   ```

   Then in the handler call `app.state.transcribe(...)`. Tests override via `make_client(transcribe=fake_fn)`.

4. **Write the test** in `daemon/tests/test_v2_transcribe.py` (mirror the existing `test_v2_*.py` pattern):

   ```python
   from .v2_helpers import make_client

   def test_v2_transcribe_returns_text():
       client, fp, app = make_client()
       app.state.transcribe = lambda url: "transcribed text"
       r = client.post("/v2/transcribe", json={"audio_url": "https://x"})
       assert r.status_code == 200
       assert r.json() == {"ok": True, "text": "transcribed text"}
   ```

5. **Update `docs/native-app/API_CONTRACT.md`** with the new endpoint (compatibility matrix in § 3, full schema in § 2). This is the canonical spec — the daemon must follow it, and the Swift side reads it.

6. **Mirror the wire types in Swift** at `apps/macos/Sources/Network/DaemonTypes.swift` (or coordinate with Lane A). The Swift test suite will read the same fixture file, so add one in `docs/native-app/fixtures/` if the response shape is non-trivial.

---

## 6. Adding a New Pydantic Model

Follow the pattern in `v2_types.py`:

```python
class V2FooBar(BaseModel):
    required_field: str
    optional_with_default: int = 0
    optional_no_default: Optional[str] = None  # NOT Optional[str] without default
```

Conventions:

- Snake_case for all field names (matches Pydantic v2 default; Swift uses CodingKeys to translate).
- `Optional[...] = None` for nullable fields (not `... | None` — be consistent with existing models).
- Don't use Pydantic validators when the constraint is best enforced in the handler (e.g. cross-field mutex like `text`/`url`). Use validators when the constraint is per-field and total (e.g. enum membership).
- If the model is a *response*, register `response_model_exclude_none=True` on the route.

Mirror in Swift at `DaemonTypes.swift`. If the field name differs in Swift (e.g. `chunk_chars` → `chunkChars`), add a CodingKey:

```swift
enum CodingKeys: String, CodingKey {
    case chunkChars = "chunk_chars"
}
```

---

## 7. Local Engine Substitution

For dev without running the full mlx-audio venv, swap in a stub:

### Inline at boot

Edit `daemon/myna/__main__.py` to inject a stub:

```python
from . import engine as eng
eng.synthesize = lambda text, **kw: b"RIFFfake\x00\x00\x00\x00"
eng.engine_up = lambda base_url, **kw: True
```

Or simpler — set up an actual stub server on `127.0.0.1:8765`:

```python
# tiny_kokoro_stub.py
from fastapi import FastAPI
from fastapi.responses import Response

app = FastAPI()
WAV = b"RIFF\x24\x00\x00\x00WAVE..."  # minimal valid WAV

@app.get("/v1/models")
def models(): return {"data": []}

@app.post("/v1/audio/speech")
def speech(_): return Response(WAV, media_type="audio/wav")

@app.get("/v1/voices")
def voices(): return ["af_heart","am_michael"]
```

```bash
uvicorn tiny_kokoro_stub:app --host 127.0.0.1 --port 8765
```

This unblocks v2 streaming locally without needing mlx-audio installed.

---

## 8. Debugging

### Where logs go

- **Foreground (`python -m myna`)**: stdout/stderr in the terminal.
- **LaunchAgent**: depends on the plist's `StandardOutPath` / `StandardErrorPath`. By convention `~/Library/Logs/myna-daemon.log` (check the template).
- **Homebrew service**: `brew services info myna-daemon` shows the log paths.

### Verbosity

No `MYNA_LOG_LEVEL` env var is wired today. uvicorn defaults to INFO. To get debug:

```bash
~/.venvs/myna/bin/uvicorn myna.app:create_app --factory \
  --host 127.0.0.1 --port 8766 --log-level debug
```

### Curl the streaming endpoint

```bash
curl -N -X POST http://127.0.0.1:8766/v2/synthesize \
  -H 'Content-Type: application/json' \
  -d '{"text":"Hello there.","speed":1.0,"mode":"full"}' \
  | xxd | head -50
```

`-N` is the magic flag — without it curl buffers the entire response. With it you see each multipart chunk as it arrives.

### Inspect engine and Ollama health independently

```bash
curl -sf http://127.0.0.1:8765/v1/models  && echo "engine UP"
curl -sf http://127.0.0.1:11434/api/tags   && echo "ollama UP"
curl -s  http://127.0.0.1:8766/v2/health  | jq
```

### Open the auto-generated OpenAPI docs

FastAPI exposes its schema at:

```
http://127.0.0.1:8766/docs        # Swagger UI
http://127.0.0.1:8766/redoc       # ReDoc
http://127.0.0.1:8766/openapi.json
```

These are live — they reflect whatever the running daemon's routes are. Use them to inspect Pydantic models without reading source.

---

## 9. Hot-reload

For tight dev loops:

```bash
~/.venvs/myna/bin/uvicorn myna.app:create_app --factory \
  --host 127.0.0.1 --port 8766 --reload --reload-dir daemon/myna
```

`--factory` is required because `create_app` is a factory function, not a module-level `app` instance.

**The LaunchAgent does not use `--reload`** — production runs `python -m myna` which calls `uvicorn.run(create_app(cfg))` directly. Re-loading the LaunchAgent (`launchctl unload && load`) is the prod equivalent of hot-reload.

---

## 10. Common Pitfalls

### Touching `app.state.player` from a v2 endpoint

The trip-wire `FakePlayer` (`tests/v2_helpers.py:22-48`) records `play / pause / resume / stop` calls. If a v2 endpoint test sees one, the test fails. Architectural rule: **v2 endpoints don't play audio**, ever. The Swift app owns playback. If you find yourself wanting to call `player.play()` from a v2 route, you're solving the wrong problem.

### Breaking v1 endpoints

Hammerspoon, the v1 CLI, and the CC Stop hook all still hit v1 routes. Don't change v1 request/response shapes. New behavior goes in `/v2/`. `test_app.py` (the v1 test file) is your guard.

### `MYNA_CONFIG_DIR` does nothing

The env var is silently ignored — `config.py:5` hardcodes `~/.config/myna/`. Don't waste an hour debugging "my custom config dir isn't loading." If you need to redirect for testing, monkeypatch `myna.config.CONFIG_PATH` (the pattern used in `test_config.py:7`).

### `mode` in `SpeakReq` is a `str`, not an enum

Unlike `V2SynthesizeReq.mode` (which is `Literal["full","summary"]`), the v1 `SpeakReq.mode` is a free-form string. Anything other than `"summary"` is treated as `"full"` (the check at `app.py:132` is `if req.mode == "summary"`). Don't tighten this — v1 callers may be sending unexpected modes that silently fall through.

### `cfg["speed"]` vs `app.state.speed`

`cfg["speed"]` is the *loaded* config value. `app.state.speed` is the *live* mutable value, set by `POST /speed`. The v1 `_speak` defaults to `app.state.speed`. The v2 `/v2/synthesize` defaults to `req.speed` (which has a Pydantic default of `1.0`) and never consults `app.state.speed` at all. This asymmetry is intentional — v2 is request-stateless.

### Mid-stream `/v2/synthesize` failures look like success

If chunk 5 of 10 fails inside the streaming generator, the response still says `{"ok": true, "chunks": 5, ...}` (see `architecture-daemon.md` § 18 #1). If you're testing a Kokoro outage, watch the count, not the `ok` flag.

### Tempdir grows forever

`~/.cache/myna/tmp/*.wav` is never cleaned. v1 only. Periodically:

```bash
find ~/.cache/myna/tmp -name '*.wav' -mtime +1 -delete
```

Or add a launchd timer if it ever matters to you.

### Pydantic v2, not v1

If you copy-paste old FastAPI examples, watch for `Field(..., regex=...)` → `Field(..., pattern=...)`. The codebase uses v2 syntax throughout.

### `httpx.post` is synchronous

All HTTP calls inside the daemon use sync `httpx`. If you add a route declared `async def`, do **not** call `httpx.post` directly — it will block the event loop. Either keep the route sync or switch to `httpx.AsyncClient`.

### Don't add `app.on_event("startup")` for shared state

`create_app(cfg)` is called once per process. Initialize on `app.state` directly inside the factory (the existing pattern at `app.py:90-104`). `on_event("startup")` runs after `create_app` returns, which means tests that call `create_app()` directly won't trigger it — silent test divergence.

### Don't break the fixture parity

`docs/native-app/fixtures/*.json` is loaded by both the Python tests and the Swift tests. If you change a response shape, update both the fixture and the contract MD — otherwise Swift's `DaemonTypes` decode tests will fail on the next CI run.

---

## 11. Useful one-liners

```bash
# Force-rebuild voice cache
curl -X POST http://127.0.0.1:8766/v2/voices   # nope, GET
curl http://127.0.0.1:8766/v2/voices  # first call populates cache

# Drop the voices cache without restart (dev only — needs a debug shell):
# python -c "import requests; ..."  — no, there's no endpoint. Restart.

# Tail the daemon log (if running under LaunchAgent)
tail -f ~/Library/Logs/myna-daemon.log

# Restart the daemon LaunchAgent
launchctl kickstart -k gui/$UID/dev.myna.daemon

# Profile a single request
time curl -sf -X POST http://127.0.0.1:8766/v2/health > /dev/null

# Sanity-check chunk count for a known text
python3 -c "from myna.chunking import chunk_text; \
  print(len(chunk_text(open('article.txt').read(), 1500)))"
```
