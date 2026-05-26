# Myna Daemon — Data Models

*Lane B exhaustive scan • Pydantic v2 wire types, in-memory shapes, on-disk JSON*

This catalogs every typed shape in the daemon: Pydantic models, dict shapes returned by helpers, the on-disk config and keybindings JSON, and the in-memory registry record. Cross-references the Swift counterpart in `apps/macos/Sources/Network/DaemonTypes.swift` for each.

---

## 1. v2 Pydantic models (`daemon/myna/v2_types.py`)

All v2 endpoints use Pydantic v2 `BaseModel` from `pydantic`. The file header binds the contract: *"Canonical schemas are documented in docs/native-app/API_CONTRACT.md § 5. JSON shapes must match the test fixtures in docs/native-app/fixtures/."*

### `V2SynthesizeReq` — `v2_types.py:12-19`

Request body for `POST /v2/synthesize` and `POST /v2/synthesize-summary`.

| Field | Type | Default | Required | Validator | Notes |
|---|---|---|---|---|---|
| `text` | `Optional[str]` | `None` | conditional | none | mutually exclusive with `url`, checked in handler (`app.py:269-281`) |
| `url` | `Optional[str]` | `None` | conditional | none | not scheme-validated here (only `/v2/extract` does) |
| `voice` | `Optional[str]` | `None` | no | none | falls back to `cfg["voice"]` |
| `speed` | `float` | `1.0` | no | clamped in handler to `[0.5, 2.0]` (`app.py:338`) | not a Pydantic validator — could be `Field(ge=0.5, le=2.0)` for free OpenAPI |
| `mode` | `Literal["full","summary"]` | `"full"` | no | enum enforced | |
| `chunk_chars` | `Optional[int]` | `None` | no | none — *should be* `Field(ge=100)` (see spec drift § 4.8 in api-contracts) | |
| `session_id` | `Optional[str]` | `None` | no | none | echoed verbatim; server-generated `uuid4().hex` if absent |

**Swift counterpart**: `SynthesizeRequest` (`DaemonTypes.swift:170-206`). CodingKeys translate `chunk_chars`/`session_id` ↔ `chunkChars`/`sessionId`. Default values match (`speed=1.0`, `mode=.full`).

---

### `V2ExtractReq` — `v2_types.py:22-23`

```python
class V2ExtractReq(BaseModel):
    url: str  # required
```

**Swift counterpart**: `ExtractRequest` (`DaemonTypes.swift:222-228`).

URL scheme validation lives in the handler (`app.py:489-493`), not on the model. Reject is HTTP 400 with `{detail: {ok:false, reason:"invalid_url"}}`.

---

### `V2ExtractResp` — `v2_types.py:26-31`

| Field | Type | Default |
|---|---|---|
| `ok` | `bool` | — (required) |
| `text` | `Optional[str]` | `None` |
| `title` | `Optional[str]` | `None` |
| `byline` | `Optional[str]` | `None` |
| `reason` | `Optional[str]` | `None` |

**Wire discipline**: the route registers `response_model_exclude_none=True` (`app.py:478-482`) so success bodies look like `{ok, text[, title, byline]}` and failure bodies look like `{ok, reason}` — never `{ok:true, text:"...", reason:null}`. Pinned by `test_v2_audit_fixes.py:38-68`.

**Swift counterpart**: `ExtractResponse` (`DaemonTypes.swift:230-244`). Swift treats all five fields as optional; the daemon hides nulls so Swift's `JSONDecoder` simply omits them.

---

### `V2SummarizeReq` — `v2_types.py:34-35`

```python
class V2SummarizeReq(BaseModel):
    text: str
```

Empty / whitespace-only text is rejected at the handler (`app.py:521-526`), not the model.

**Swift counterpart**: `SummarizeRequest` (`DaemonTypes.swift:246-252`).

---

### `V2SummarizeResp` — `v2_types.py:38-41`

| Field | Type | Default |
|---|---|---|
| `ok` | `bool` | — |
| `summary` | `Optional[str]` | `None` |
| `reason` | `Optional[str]` | `None` |

Also `exclude_none=True` (`app.py:513-517`). Success: `{ok, summary}`. Failure (not currently emitted as JSON because the handler raises HTTPException): `{ok, reason}`.

**Swift counterpart**: `SummarizeResponse` (`DaemonTypes.swift:254-264`).

---

### `V2EngineInfo` — `v2_types.py:44-48`

Nested into `V2Status.engine`.

| Field | Type | Source |
|---|---|---|
| `url` | `str` | `cfg["engine_url"]` |
| `status` | `str` | `"up"` or `"down"` (`app.py:433`) |
| `model` | `str` | `cfg["model"]` |
| `last_check_age_s` | `float` | seconds since the cached `engine_up` probe (`app.py:434`) |

**Swift counterpart**: `EngineInfo` (`DaemonTypes.swift:18-37`). `last_check_age_s` ↔ `lastCheckAgeS`.

---

### `V2DaemonInfo` — `v2_types.py:51-54`

| Field | Type | Source |
|---|---|---|
| `version` | `str` | `myna.__version__` (`app.py:437`) |
| `uptime_s` | `float` | `time.time() - app.state.started_at` (`app.py:438`) |
| `pid` | `int` | `os.getpid()` (`app.py:439`) |

**Swift counterpart**: `DaemonInfo` (`DaemonTypes.swift:39-55`). `uptime_s` ↔ `uptimeS`.

---

### `V2ConfigInfo` — `v2_types.py:57-62`

| Field | Type |
|---|---|
| `voice` | `str` |
| `speed` | `float` |
| `lang_code` | `str` |
| `chunk_chars` | `int` |
| `summary_model` | `str` |

All sourced from `cfg` / `app.state.speed` (`app.py:441-447`). **Note**: this is what's loaded *now*, not necessarily what's on disk — `app.state.speed` is mutated by `POST /speed`, so `config.speed` reflects the live value.

**Swift counterpart**: `DaemonConfig` (`DaemonTypes.swift:57-79`).

---

### `V2RegistryItem` — `v2_types.py:65-69`

| Field | Type | Source |
|---|---|---|
| `id` | `str` | 8-hex (`registry.py:17`) |
| `label` | `str` | as posted to `/announce` |
| `age_s` | `int` | `int(now - created)` (`registry.py:38`) |
| `preview` | `str` | `text[:60]` (`registry.py:39`) |

**Swift counterpart**: `RegistryItem` (`DaemonTypes.swift:81-100`). Conforms to `Identifiable` via `id`. `age_s` ↔ `ageS`.

---

### `V2RegistryInfo` — `v2_types.py:72-74`

```python
class V2RegistryInfo(BaseModel):
    count: int
    items: list[V2RegistryItem]
```

**Swift counterpart**: `RegistryInfo` (`DaemonTypes.swift:102-110`).

---

### `V2V1PlayerInfo` — `v2_types.py:77-79`

| Field | Type |
|---|---|
| `state` | `str` (`idle` / `playing` / `paused`) |
| `now_playing` | `Optional[dict]` |

`now_playing` shape is `{"source": str, "preview": str}` when set (`app.py:144`), `None` otherwise.

**Swift counterpart**: there isn't one. `DaemonStatus` in Swift (`DaemonTypes.swift:112-132`) **omits** `v1_player` because the Swift app ignores it (the contract explicitly says it's diagnostic-only). Pydantic emits it; Swift's `JSONDecoder` is lenient about unknown keys.

---

### `V2Status` — `v2_types.py:82-88`

Top-level response for `GET /v2/status`. Composes `V2EngineInfo`, `V2DaemonInfo`, `V2ConfigInfo`, `V2RegistryInfo`, `V2V1PlayerInfo`.

| Field | Type |
|---|---|
| `state` | `str` |
| `engine` | `V2EngineInfo` |
| `daemon` | `V2DaemonInfo` |
| `config` | `V2ConfigInfo` |
| `registry` | `V2RegistryInfo` |
| `v1_player` | `V2V1PlayerInfo` |

`state` is sent as `"idle"` or `"down"`. The contract documents `synthesizing` / `streaming` as additional values; the daemon never emits them today. See `api-contracts-daemon.md` § 4.1.

**Swift counterpart**: `DaemonStatus` (`DaemonTypes.swift:112-132`).

---

### `V2Voice` — `v2_types.py:91-95`

| Field | Type | Source |
|---|---|---|
| `id` | `str` | Kokoro voice id |
| `label` | `str` | `_voice_label(id)` (`app.py:64-76`) |
| `lang` | `str` | `_voice_lang(id)` — `"en"` or `"unknown"` (`app.py:79-84`) |
| `default` | `bool` | `id == cfg["voice"]` (`app.py:260`) |

**Swift counterpart**: `Voice` (`DaemonTypes.swift:134-153`). `default` ↔ `isDefault` (because `default` is a Swift keyword).

---

### `V2Voices` — `v2_types.py:98-100`

```python
class V2Voices(BaseModel):
    voices: list[V2Voice]
    engine: Optional[str] = None
```

`response_model_exclude_none=True` at the route (`app.py:458`) — so the wire payload is `{voices}` happy path, `{voices: [], engine: "down"}` when down. Pinned by `test_v2_audit_fixes.py:16-33`.

**Swift counterpart**: `VoicesResponse` (`DaemonTypes.swift:155-163`). Swift `engine` is `String?`. Cross-checked.

---

### `V2Health` — `v2_types.py:103-106`

| Field | Type |
|---|---|
| `ok` | `bool` |
| `version` | `str` |
| `engine_up` | `bool` |

**Swift counterpart**: `HealthResponse` (`DaemonTypes.swift:294-310`). `engine_up` ↔ `engineUp`.

---

## 2. v1 inline models (`daemon/myna/app.py`)

Three small models defined inside `app.py` (not exported to `v2_types.py` because v1 is feature-frozen):

### `SpeakReq` — `app.py:45-51`

| Field | Type | Default |
|---|---|---|
| `text` | `Optional[str]` | `None` |
| `url` | `Optional[str]` | `None` |
| `mode` | `str` | `"full"` (no enum constraint) |
| `voice` | `Optional[str]` | `None` |
| `speed` | `Optional[float]` | `None` (falls back to `app.state.speed`) |
| `source` | `Optional[str]` | `None` (defaults to `"speak"` in player meta) |

No mutex check (unlike v2). If both `text` and `url` are set, `url` wins (`app.py:125-128`).

### `AnnounceReq` — `app.py:54-57`

| Field | Type | Required |
|---|---|---|
| `session_id` | `str` | yes |
| `label` | `str` | yes |
| `text` | `str` | yes |

**Swift counterpart**: `AnnounceRequest` (`DaemonTypes.swift:266-282`). `session_id` ↔ `sessionId`.

### `SpeedReq` — `app.py:60-61`

```python
class SpeedReq(BaseModel):
    value: float
```

Clamped to `[0.5, 2.0]` at the handler (`app.py:187`), not the model.

---

## 3. Other typed dicts (not Pydantic)

### Player status — `Player.status() -> dict` (`player.py:83-85`)

```python
{"state": "idle" | "playing" | "paused", "now_playing": dict | None}
```

`now_playing` shape comes from the `meta` arg passed to `Player.play()` — in practice `{"source": str, "preview": str[:60]}` (`app.py:144`).

### Registry external item — `Registry.list_items()` (`registry.py:31-42`)

```python
{"id": str, "label": str, "age_s": int, "preview": str}
```

### Registry internal record — built in `Registry.add` (`registry.py:14-23`)

```python
{
    "id": str,         # uuid4().hex[:8]
    "label": str,      # whatever the caller passed
    "text": str,       # the full text — NOT exposed via list_items
    "created": float,  # self._clock() at insert time
}
```

`text` is **only** exposed via `Registry.pop(id)` (used by `POST /play/{id}`). `list_items` exposes only the 60-char `preview`.

### Extract pluggable return shape

`extract.extract_article` (`extract.py:4-12`) declares `-> str | None`. The v2 handler (`app.py:494-511`) also accepts a `dict` shape with `text/title/byline` keys. The Lane B-side handler is forgiving:

```python
result = app.state.extract(url)
if result is None: ...                       # 1. None
if isinstance(result, dict): ...             # 2. dict with text + optional title/byline
# else: plain str
```

This means a future "richer extractor" can return `{"text": "...", "title": "...", "byline": "..."}` without changing the wire contract or the route handler.

---

## 4. Config file — `~/.config/myna/config.json`

Loaded by `config.load_config` (`config.py:23-27`). All keys optional; missing keys take the default.

**Full schema** (every key is the default value):

```json
{
  "engine_url":      "http://127.0.0.1:8765",
  "ollama_url":      "http://127.0.0.1:11434",
  "voice":           "af_heart",
  "lang_code":       "a",
  "model":           "prince-canuma/Kokoro-82M",
  "summary_model":   "qwen3.5:4b",
  "summary_think":   false,
  "summary_timeout": 60.0,
  "speed":           1.0,
  "chunk_chars":     1500,
  "daemon_port":     8766
}
```

| Key | Type | Default | What it does |
|---|---|---|---|
| `engine_url` | str | `http://127.0.0.1:8765` | mlx-audio Kokoro endpoint |
| `ollama_url` | str | `http://127.0.0.1:11434` | Ollama endpoint (summary only) |
| `voice` | str | `af_heart` | default Kokoro voice id |
| `lang_code` | str | `a` | Kokoro language code (a = American English, b = British) |
| `model` | str | `prince-canuma/Kokoro-82M` | Kokoro model name |
| `summary_model` | str | `qwen3.5:4b` | Ollama model used by `summarize` |
| `summary_think` | bool | `false` | enable reasoning-model `<think>` blocks (slow; usually false) |
| `summary_timeout` | float | `60.0` | httpx timeout for Ollama call in seconds |
| `speed` | float | `1.0` | initial v1 global speed; mutated by `POST /speed` |
| `chunk_chars` | int | `1500` | default chunk size for both v1 and v2 |
| `daemon_port` | int | `8766` | the port the daemon binds |

**Unknown keys** are accepted and ignored (Python `dict.update`). **Type errors** (e.g. `"speed": "fast"`) won't be caught at load time but will explode later when used (e.g. in chunker arithmetic).

**Known gap**: `MYNA_CONFIG_DIR` env var is **not honored** — the path is hardcoded to `~/.config/myna/` in `config.py:5`.

---

## 5. Keybindings file — `~/.config/myna/keybindings.json`

Written once by `install.sh:20-28` (only if absent). Used by the Hammerspoon module and the Swift app's Settings → Hotkeys tab.

**Schema** (object of action → keybinding):

```json
{
  "speak_selection_full":    { "mods": ["cmd","alt","shift"], "key": "s" },
  "speak_selection_summary": { "mods": ["cmd","alt","shift"], "key": "a" },
  "read_chrome_article":     { "mods": ["cmd","alt","shift"], "key": "r" },
  "pause_resume":            { "mods": ["cmd","alt","shift"], "key": "space" },
  "stop":                    { "mods": ["cmd","alt","shift"], "key": "." }
}
```

| Action | Default chord | Triggered behavior |
|---|---|---|
| `speak_selection_full` | ⌘⌥⇧S | grab clipboard selection → `POST /speak text=… mode=full` |
| `speak_selection_summary` | ⌘⌥⇧A | as above with `mode=summary` |
| `read_chrome_article` | ⌘⌥⇧R | grab Chrome's URL → `POST /speak url=… mode=full` |
| `pause_resume` | ⌘⌥⇧Space | `POST /pause` then `POST /resume` (toggle) |
| `stop` | ⌘⌥⇧. | `POST /stop` |

**Per-entry schema**:

- `mods`: array of strings, each ∈ `{"cmd", "alt", "shift", "ctrl"}`.
- `key`: string, single character or special name (`"space"`, `"."`, etc. — the Hammerspoon and Swift hotkey parsers both accept these).

The **daemon itself does not read this file** — it's purely client-side. Listed here because the data model is part of the Myna user-facing contract.

---

## 6. Registry in-memory shape (CC announce)

Already covered in § 3 above. Summary diagram:

```
POST /announce  →  Registry._items = [
  {id, label, text, created},      ← internal
  ...
]
                ↓ Registry.list_items() / V2RegistryItem ↓
GET /registry  →  {id, label, age_s, preview}    (no text!)
GET /v2/status →  {registry: {count, items: [V2RegistryItem]}}
POST /play/{id} →  Registry.pop(id) returns internal record; _speak uses text
```

Lifecycle invariants:

- `created` is set at `add()` time using the injected `clock`.
- `prune()` is called at every `add()` and `list_items()`.
- TTL = 1800s, cap = 10 (`registry.py:8`).
- A daemon restart wipes everything — no persistence.

---

## 7. Cross-reference summary

| Daemon model | File:line | Swift model | File:line |
|---|---|---|---|
| `V2SynthesizeReq` | `v2_types.py:12-19` | `SynthesizeRequest` | `DaemonTypes.swift:170-206` |
| `V2ExtractReq` | `v2_types.py:22-23` | `ExtractRequest` | `DaemonTypes.swift:222-228` |
| `V2ExtractResp` | `v2_types.py:26-31` | `ExtractResponse` | `DaemonTypes.swift:230-244` |
| `V2SummarizeReq` | `v2_types.py:34-35` | `SummarizeRequest` | `DaemonTypes.swift:246-252` |
| `V2SummarizeResp` | `v2_types.py:38-41` | `SummarizeResponse` | `DaemonTypes.swift:254-264` |
| `V2EngineInfo` | `v2_types.py:44-48` | `EngineInfo` | `DaemonTypes.swift:18-37` |
| `V2DaemonInfo` | `v2_types.py:51-54` | `DaemonInfo` | `DaemonTypes.swift:39-55` |
| `V2ConfigInfo` | `v2_types.py:57-62` | `DaemonConfig` | `DaemonTypes.swift:57-79` |
| `V2RegistryItem` | `v2_types.py:65-69` | `RegistryItem` | `DaemonTypes.swift:81-100` |
| `V2RegistryInfo` | `v2_types.py:72-74` | `RegistryInfo` | `DaemonTypes.swift:102-110` |
| `V2V1PlayerInfo` | `v2_types.py:77-79` | *(omitted, diagnostic-only)* | — |
| `V2Status` | `v2_types.py:82-88` | `DaemonStatus` | `DaemonTypes.swift:112-132` |
| `V2Voice` | `v2_types.py:91-95` | `Voice` | `DaemonTypes.swift:134-153` |
| `V2Voices` | `v2_types.py:98-100` | `VoicesResponse` | `DaemonTypes.swift:155-163` |
| `V2Health` | `v2_types.py:103-106` | `HealthResponse` | `DaemonTypes.swift:294-310` |
| `AnnounceReq` | `app.py:54-57` | `AnnounceRequest` | `DaemonTypes.swift:266-282` |
| `SpeakReq` | `app.py:45-51` | *(no Swift equivalent — Swift doesn't use v1)* | — |
| `SpeedReq` | `app.py:60-61` | *(no Swift equivalent)* | — |
