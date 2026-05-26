# Myna Daemon — HTTP API Reference

*Lane B exhaustive scan • Source of truth: `daemon/myna/app.py`*

**Base URL:** `http://127.0.0.1:8766` (configurable via `~/.config/myna/config.json` → `daemon_port`)
**Auth:** none (loopback-only).
**Default Content-Type:** `application/json` (except `/v2/synthesize` which is `multipart/mixed`).
**Daemon version:** `0.2.0` (`daemon/myna/__init__.py:1`).

Two surfaces share one app:

- **v1**: unversioned, used by Hammerspoon v1 and the v1 CLI. Mutates the daemon's internal `Player`.
- **v2**: prefixed `/v2/`, used by the Swift app. Returns raw bytes / status; never plays audio.

Section 4 lists **spec drift** between this code and `docs/native-app/API_CONTRACT.md`.

---

## 1. v2 Endpoints

### `POST /v2/synthesize`

Handler: `app.py:415-417` → `_v2_synthesize_response` (`app.py:312-411`).
Stream raw WAVs back to the Swift app via `multipart/mixed`.

**Request body — `V2SynthesizeReq` (`v2_types.py:12-19`):**

| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| `text` | `string \| null` | conditional | `null` | mutually exclusive with `url`; one of `text`/`url` must be set |
| `url` | `string \| null` | conditional | `null` | mutually exclusive with `text`; no scheme validation here (only `/v2/extract` validates) |
| `voice` | `string \| null` | no | `cfg["voice"]` (default `af_heart`) | Kokoro voice id; not validated server-side |
| `speed` | `float` | no | `1.0` | **clamped** to `[0.5, 2.0]` (`app.py:338`) |
| `mode` | `"full" \| "summary"` | no | `"full"` | enforced via `Literal` |
| `chunk_chars` | `int \| null` | no | `cfg["chunk_chars"]` (default 1500) | no clamp (see § 4) |
| `session_id` | `string \| null` | no | server-generated `uuid4().hex` | echoed back in the final part |

**Response — happy path (HTTP 200):**

- `Content-Type: multipart/mixed; boundary=mynachunk`
- `Transfer-Encoding: chunked`
- One audio part per chunk:

  ```
  --mynachunk
  Content-Type: audio/wav
  X-Chunk-Index: 0
  X-Chunk-Total-Estimate: 8
  X-Chunk-Text: First%20200%20chars%20URL-encoded

  <WAV bytes>
  ```

- One closing JSON part:

  ```
  --mynachunk
  Content-Type: application/json

  {"ok": true, "chunks": 8, "session_id": "abc-123"}
  --mynachunk--
  ```

`X-Chunk-Text` is URL-encoded via `urllib.parse.quote(preview[:200], safe="")` (`app.py:362`).

**Error responses (all single JSON body, NOT multipart):**

| Status | Body | When |
|---|---|---|
| 400 | `{"detail": {"ok": false, "reason": "neither_text_nor_url"}}` | both `text` and `url` are absent (`app.py:277-281`) |
| 400 | `{"detail": {"ok": false, "reason": "both_text_and_url"}}` | both `text` and `url` provided (`app.py:269-273`) |
| 400 | `{"detail": {"ok": false, "reason": "empty"}}` | text trims to empty (`app.py:295-299`) or chunker returns `[]` (`app.py:327-331`) |
| 400 | `{"detail": {"ok": false, "reason": "extract_failed"}}` | `app.state.extract(url)` returned None/empty (`app.py:285-290`) |
| 502 | `{"ok": false, "reason": "engine_down"}` | engine health check failed (`app.py:317-321`) — note flat body, not wrapped in `detail` |
| 502 | `{"ok": false, "reason": "engine_error", "detail": "<exception str>"}` | first-chunk synthesis raised (`app.py:353-357`) |

**Status notes:**

- Mid-stream chunk failure does **NOT** error the response. The stream closes cleanly and the final JSON part reports the actual chunk count (`app.py:398-406`). The client sees `ok:true` even though chunks were lost. See `architecture-daemon.md` § 18 #1.
- `text="   "` (whitespace) is rejected, but `text=null` + `url=null` is `neither_text_nor_url`; these are distinct codes.

**Curl example:**

```bash
curl -N -X POST http://127.0.0.1:8766/v2/synthesize \
  -H 'Content-Type: application/json' \
  -d '{"text": "Hello there. This is Myna.", "speed": 1.25, "mode": "full"}'
```

(`-N` disables curl buffering so you see the streamed multipart in real time.)

**Request example** (`docs/native-app/fixtures/synthesize-request.json`):

```json
{
  "text": "Hello there. This is a test of the Myna v2 synthesize endpoint.",
  "voice": "af_heart",
  "speed": 1.0,
  "mode": "full",
  "chunk_chars": 1500,
  "session_id": "1f3b2c50-8b4f-4d2c-9c5e-2f5a6f1b3d2c"
}
```

---

### `POST /v2/synthesize-summary`

Handler: `app.py:419-421`. Identical to `/v2/synthesize` but forces `mode="summary"` regardless of what the client sends. Used by the Swift summary-shortcut path so the CLI/URL scheme can hit one route without conditional JSON.

Request body, response, and errors are identical to `/v2/synthesize` (just always summary).

---

### `GET /v2/status`

Handler: `app.py:423-456`. Returns a full state snapshot for the Swift menu bar.

**Response — `V2Status` (HTTP 200):**

```json
{
  "state": "idle",
  "engine": {
    "url": "http://127.0.0.1:8765",
    "status": "up",
    "model": "prince-canuma/Kokoro-82M",
    "last_check_age_s": 1.4
  },
  "daemon": {
    "version": "0.2.0",
    "uptime_s": 12345.6,
    "pid": 4444
  },
  "config": {
    "voice": "af_heart",
    "speed": 1.0,
    "lang_code": "a",
    "chunk_chars": 1500,
    "summary_model": "qwen3.5:4b"
  },
  "registry": {
    "count": 1,
    "items": [
      {"id": "abcd1234", "label": "ECS", "age_s": 12, "preview": "Here is the first sixty characters of an announced message."}
    ]
  },
  "v1_player": {"state": "idle", "now_playing": null}
}
```

**Field notes:**

- `state` (`app.py:429`) is **only ever** `"down"` (engine cached as down) or `"idle"` (engine up). The other documented states `"synthesizing"` and `"streaming"` (per `API_CONTRACT.md:154`) are never emitted. See § 4 below.
- `engine.last_check_age_s` is seconds since last engine probe (cached for 1.0s by `_check_engine_cached`).
- `daemon.uptime_s` is `time.time() - app.state.started_at` (`app.py:438`).
- `v1_player.now_playing` is whatever `meta` was passed to `Player.play()` — `{"source": <str>, "preview": <60 chars>}` or `null`.
- `registry.items[*].preview` is `text[:60]`. `age_s` is integer seconds.

Errors: no error path; `_check_engine_cached` swallows exceptions and returns `False`.

**Curl example:**

```bash
curl http://127.0.0.1:8766/v2/status | jq
```

---

### `GET /v2/voices`

Handler: `app.py:458-476`.

**Response — `V2Voices` (HTTP 200), happy path (engine up):**

```json
{
  "voices": [
    {"id": "af_heart",   "label": "Heart (female)",   "lang": "en", "default": true},
    {"id": "af_bella",   "label": "Bella (female)",   "lang": "en", "default": false},
    {"id": "am_michael", "label": "Michael (male)",   "lang": "en", "default": false},
    {"id": "am_adam",    "label": "Adam (male)",      "lang": "en", "default": false}
  ]
}
```

**Response — engine down (HTTP 200):**

```json
{"voices": [], "engine": "down"}
```

**Key set discipline** (`app.py:458`, `response_model_exclude_none=True`):

- Happy path body keys **exactly** `{voices}`. No `engine: null` leak. (Pinned by `test_v2_audit_fixes.py:16-23`.)
- Down path body keys **exactly** `{voices, engine}`. (Pinned by `test_v2_audit_fixes.py:26-33`.)

**Behavior:**

- First call to engine `GET /v1/voices` (`app.py:233`). Parses three shapes: `["id", ...]`, `{"voices": [...]}` with strings or dicts, `{"data": [...]}`.
- Cached **5 minutes** (`_VOICES_CACHE_TTL_S = 300.0`, `app.py:39`).
- If engine endpoint fails or returns empty, falls back to `["af_heart", "af_bella", "am_michael", "am_adam"]` (`app.py:42, 250-251`).
- Configured default voice is force-injected into the list if missing (`app.py:253-254`), and marked `default: true`.
- Voice id parsing: `af_*` → female en, `bf_*` → female en, `am_*` → male en, `bm_*` → male en, else `unknown` (`app.py:64-84`).

**Curl example:**

```bash
curl http://127.0.0.1:8766/v2/voices
```

---

### `POST /v2/extract`

Handler: `app.py:478-511`.

**Request — `V2ExtractReq` (`v2_types.py:22-23`):**

| Field | Type | Required | Validation |
|---|---|---|---|
| `url` | `string` | yes | must start with `http://` or `https://` (`app.py:489-493`) |

**Response — `V2ExtractResp` (`v2_types.py:26-31`):**

Success (HTTP 200):

```json
{"ok": true, "text": "Lorem ipsum...", "title": "Lorem Ipsum: The Article", "byline": "Cicero"}
```

If the underlying `extract` returns a plain string, only `{ok, text}` is emitted (no null leaks):

```json
{"ok": true, "text": "Lorem ipsum..."}
```

Failure (HTTP 200, **not 4xx** — the URL was valid, the extraction just failed):

```json
{"ok": false, "reason": "extract_failed"}
```

URL validation failure (HTTP 400):

```json
{"detail": {"ok": false, "reason": "invalid_url"}}
```

**Key discipline**: `response_model_exclude_none=True` (`app.py:478-482`). Success bodies never carry null `title`/`byline`/`reason`; failure bodies never carry null `text`/`title`/`byline`. Pinned by `test_v2_audit_fixes.py:38-68`.

**Curl example:**

```bash
curl -X POST http://127.0.0.1:8766/v2/extract \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/article"}'
```

---

### `POST /v2/summarize`

Handler: `app.py:513-534`.

**Request — `V2SummarizeReq` (`v2_types.py:34-35`):**

| Field | Type | Required | Validation |
|---|---|---|---|
| `text` | `string` | yes | trimmed; rejected if empty |

**Response — `V2SummarizeResp` (`v2_types.py:38-41`):**

Success (HTTP 200):

```json
{"ok": true, "summary": "Short spoken summary in under 150 words."}
```

Empty text (HTTP 400):

```json
{"detail": {"ok": false, "reason": "empty"}}
```

Ollama unreachable: the underlying `httpx.ConnectError` is not caught — FastAPI emits a 500. Worth fixing for graceful degradation.

`response_model_exclude_none=True` keeps `reason: null` out of success bodies (`app.py:513-517`). Pinned by `test_v2_audit_fixes.py:71-78`.

**Curl example:**

```bash
curl -X POST http://127.0.0.1:8766/v2/summarize \
  -H 'Content-Type: application/json' \
  -d '{"text":"long article body to summarise..."}'
```

---

### `GET /v2/health`

Handler: `app.py:536-542`.

**Response — `V2Health` (HTTP 200):**

```json
{"ok": true, "version": "0.2.0", "engine_up": true}
```

Always returns HTTP 200; `ok` is always `true`. `engine_up` uses the 1s cache.

**Curl example:**

```bash
curl http://127.0.0.1:8766/v2/health
```

---

## 2. v1 Endpoints

These exist for Hammerspoon, the v1 CLI, and the CC Stop hook. Lane C must not change their shape.

### `POST /speak`

Handler: `app.py:150-152` → `_speak` (`app.py:123-146`).

**Request — `SpeakReq` (`app.py:45-51`):**

| Field | Type | Required | Default |
|---|---|---|---|
| `text` | `string \| null` | conditional | `null` |
| `url` | `string \| null` | conditional | `null` |
| `mode` | `string` | no | `"full"` |
| `voice` | `string \| null` | no | `null` → fall back to `cfg["voice"]` |
| `speed` | `float \| null` | no | `null` → fall back to `app.state.speed` |
| `source` | `string \| null` | no | `null` → falls back to `"speak"` in player meta |

No mutual-exclusion check — if both `text` and `url` are given, `url` wins (extraction overwrites text).

**Response (HTTP 200):**

- `{"ok": true}` on success.
- `{"ok": false, "reason": "empty"}` if text trims empty.
- `{"ok": false, "reason": "extract_failed"}` if URL fetch/extract returns empty.

No 4xx — v1 always returns 200 with an `ok` flag.

---

### `POST /announce`

Handler: `app.py:154-157`. Used by the CC Stop hook (`hooks/myna-cc-announce.py`).

**Request — `AnnounceReq` (`app.py:54-57`):**

| Field | Type | Required |
|---|---|---|
| `session_id` | `string` | yes |
| `label` | `string` | yes (typically `basename(cwd)`) |
| `text` | `string` | yes (truncated by caller to 8000 chars) |

**Response:** `{"ok": true, "id": "abcd1234"}` — `id` is an 8-hex unique key.

---

### `GET /registry`

Handler: `app.py:159-161`.

**Response:**

```json
{
  "items": [
    {"id": "abcd1234", "label": "ECS", "age_s": 12, "preview": "first 60 chars..."}
  ]
}
```

Always HTTP 200. `preview` is `text[:60]`. Items past TTL (30 min) or cap (10) are pruned before listing.

---

### `POST /play/{item_id}`

Handler: `app.py:163-168`. Path param `item_id` (8-hex), query param `?mode=full|summary` (default `full`).

Pops the registry item and pipes it to `_speak`. Returns whatever `_speak` returns, or `{"ok": false, "reason": "not_found"}` if the id is unknown.

---

### `POST /pause`, `POST /resume`, `POST /stop`

Handlers: `app.py:170-183`. No body. Always `{"ok": true}`. Forwards to `Player.pause / resume / stop`. Idempotent — `pause` on idle is a no-op (state stays idle).

---

### `POST /speed`

Handler: `app.py:185-188`.

**Request — `SpeedReq` (`app.py:60-61`):** `{"value": 1.5}`.

**Response:** `{"ok": true, "speed": <clamped>}`. Clamped to `[0.5, 2.0]` (`app.py:187`).

Mutates `app.state.speed` — this is the v1 global speed used by future `/speak` calls when `req.speed` is null. **Does not** affect `/v2/synthesize` (v2 takes its `speed` from the request only).

---

### `GET /status`

Handler: `app.py:190-199`.

**Response:**

```json
{
  "state": "idle",
  "now_playing": null,
  "speed": 1.0,
  "registry_count": 3,
  "engine": "up"
}
```

`state` ∈ `{idle, playing, paused}` (player state — no `down` here; engine status is a separate field).
`engine` ∈ `{up, down}`. **Not cached** — every `/status` call hits Kokoro fresh, unlike `/v2/status` which uses the 1s cache. (Acceptable because v1 callers poll less often.)

---

## 3. The CC Stop Hook (not part of the daemon, but relevant)

`hooks/myna-cc-announce.py` (83 lines) is registered by `install.sh:43-61` as a Claude Code Stop hook. On every CC session end:

1. Reads stdin (JSON from CC).
2. Tails the transcript file at `data["transcript_path"]`, extracts the **last** assistant turn (`_last_assistant_text` walks the jsonl).
3. Joins all `{type:"text"}` content blocks; truncates to 8000 chars.
4. Labels with `basename(data["cwd"])` (e.g. `myna`, `dpsca-site`).
5. Posts to `POST http://127.0.0.1:${MYNA_PORT:-8766}/announce` with 1.5s timeout, **silently swallows all errors**.

The CC hook never blocks the session and never plays audio — only registers.

---

## 4. Spec Drift (code ↔ `API_CONTRACT.md` ↔ `DaemonTypes.swift`)

Catalogued by reading `app.py` and the contract side by side. Anything not listed here is in lockstep.

### 4.1 `/v2/status.state` enum

- **Contract** (`API_CONTRACT.md:154`): `"idle | synthesizing | streaming | down"`.
- **Swift** (`DaemonTypes.swift:5-16`): four cases plus `.unknown` fallback.
- **Daemon** (`app.py:429`): only emits `"idle"` or `"down"`.

Two enum cases are unreachable. The Swift side handles it (falls back to `.unknown`), but the menu bar can't distinguish "engine up, not doing anything" from "engine up, mid-stream right now." Fixing requires the daemon to track in-flight `/v2/synthesize` calls (simple counter on `app.state`).

### 4.2 `VoicesResponse.engine`

- **Contract** (`API_CONTRACT.md:351-353`): `VoicesResponse` declared as `{ voices: [Voice] }` — `engine` field is *not* listed in the canonical Swift declaration.
- **Swift actual** (`DaemonTypes.swift:155-163`): includes `public let engine: String?` (optional).
- **Daemon** (`app.py:466-476`): emits `engine: "down"` only when down, omits otherwise.

This is a contract update that didn't make it back into the doc — code and Swift agree, doc lags. Either fix the doc or remove the field. Code-wise it's right; the contract MD needs a refresh.

### 4.3 `DaemonError.transport(Error)` vs `DaemonError.transport(String)`

- **Contract** (`API_CONTRACT.md:393`): `case transport(Error)`.
- **Swift actual** (`DaemonTypes.swift:338`): `case transport(String)`.

Lane A changed `Error` → `String` (probably for `Equatable` conformance — see `DaemonTypes.swift:341-364`). Contract MD never caught up. Cosmetic from the daemon's perspective, but the contract MD is now lying.

### 4.4 `DaemonError.invalidURL(String)` is new

- **Contract** (`API_CONTRACT.md:382-394`): no `invalidURL` case.
- **Swift actual** (`DaemonTypes.swift:339`): `case invalidURL(String)` exists.

Added on the Swift side to handle the `/v2/extract` 400 `invalid_url` reason. Contract MD missing.

### 4.5 `/v2/synthesize` errors `504 engine_timeout` not implemented

- **Contract** (`API_CONTRACT.md:138`): documents `504 {ok:false, reason:"engine_timeout"}`.
- **Daemon** (`app.py:344-357`): only ever emits 502 for engine errors. A real timeout (`httpx.TimeoutException`) gets caught as `Exception` and reported as `engine_error` with the timeout exception's `str(exc)` in `detail`.

Tightening: catch `httpx.TimeoutException` separately and emit 504 with the documented body.

### 4.6 `_v2_synthesize_response` declared `async` in contract, written as sync

- **Contract** (`API_CONTRACT.md:404-405`): `async def v2_synthesize(...)`.
- **Daemon** (`app.py:415-417`): sync `def v2_synthesize(...)`.

This is fine — FastAPI runs sync handlers in a threadpool, and the streaming generator is sync too. Contract MD is stylistic, not enforceable.

### 4.7 Mid-stream chunk failure surfaces as `ok:true`

Not really "drift" but a behavior the contract leaves ambiguous. The contract says "stream returns one part per chunk + final summary." It doesn't say what happens if chunk N of M fails mid-stream. The daemon (`app.py:398-406`) silently truncates and emits `ok:true, chunks:<partial>`. Either the contract should mandate `ok:false, reason:"partial_engine_failure"` and the daemon should follow, or the contract should explicitly bless the current behavior.

### 4.8 `V2SynthesizeReq.chunk_chars` has no minimum

- **Daemon** (`v2_types.py:18`): `chunk_chars: Optional[int] = None`. No validator.
- **Risk**: `chunk_chars=0` would loop in `chunking.chunk_text` (`chunking.py:23-25`). Should be `Field(ge=100)` or similar.

### 4.9 v1 `POST /speak` accepts any URL scheme, v2 `POST /v2/extract` does not

- **Daemon v1** (`app.py:125`): forwards any `url` straight to `trafilatura.fetch_url` (which accepts `http(s)://` in practice but doesn't reject `file://` upfront).
- **Daemon v2** (`app.py:489-493`): rejects anything not `http://` / `https://`.

Asymmetric on purpose — v1 left lax to keep Hammerspoon callers happy. Document the asymmetry; don't fix it.

---

## 5. Quick-reference cheat sheet

| Method | Path | Body type | Returns | Purpose |
|---|---|---|---|---|
| POST | `/speak` | `SpeakReq` | JSON `{ok}` | v1 speak via internal Player |
| POST | `/announce` | `AnnounceReq` | JSON `{ok, id}` | register a CC turn |
| GET | `/registry` | — | JSON `{items}` | list pending CC items |
| POST | `/play/{id}?mode=` | — | JSON `{ok}` | pop + speak |
| POST | `/pause` | — | JSON `{ok}` | SIGSTOP afplay |
| POST | `/resume` | — | JSON `{ok}` | SIGCONT afplay |
| POST | `/stop` | — | JSON `{ok}` | kill afplay |
| POST | `/speed` | `SpeedReq` | JSON `{ok, speed}` | set global speed |
| GET | `/status` | — | JSON (5 keys) | v1 status |
| POST | `/v2/synthesize` | `V2SynthesizeReq` | `multipart/mixed` | stream WAV per chunk |
| POST | `/v2/synthesize-summary` | `V2SynthesizeReq` | `multipart/mixed` | as above, force summary |
| GET | `/v2/status` | — | `V2Status` JSON | rich status for Swift menu |
| GET | `/v2/voices` | — | `V2Voices` JSON | voice list, 5min cached |
| POST | `/v2/extract` | `V2ExtractReq` | `V2ExtractResp` | URL → article text |
| POST | `/v2/summarize` | `V2SummarizeReq` | `V2SummarizeResp` | text → spoken summary |
| GET | `/v2/health` | — | `V2Health` | fast liveness probe |
