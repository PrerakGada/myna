# Karaoke subtitle ribbon — architecture brief

> **Source:** BMad party-mode rounds 2–3, agent: Winston (System Architect).
> **Status:** ✅ Applies. Architecture fits cleanly alongside the existing Swift `apps/macos/`.

## Top-line verdict

**Tier 1 — GO. 6h weekend job — provided we accept:**
1. Option B timing estimation (daemon-side char-weighted, drift ≤200ms)
2. Ribbon bundled inside Myna.app, not a separate Homebrew formula
3. Zero Swift CI tests for v0.2 (local `swift test` only)

**Tier 2** (in-place word highlight inside source apps via AX) — defer to v0.3. 1.5 weeks of edge cases.

**Tier 3** (universal AX + OCR fallback) — skip until explicitly requested. Screen Recording permission costs too much trust at Alpha.

**Gestures (BetterTouchTool replacement)** — defer to v0.2+. Private MultitouchSupport.framework is a maintenance tarpit. Public-API `.swipe` only if absolutely must demo gestures at launch.

---

## 1. Swift binary structure

**SwiftPM, multi-file, packaged as `.app` post-build.**

```
karaoke/                              # NEW top-level dir (or apps/karaoke/)
├── Package.swift                     # SwiftPM manifest
├── Sources/
│   └── MynaKaraoke/
│       ├── main.swift                # ~30 LOC: AppDelegate bootstrap
│       ├── PanelController.swift     # ~80 LOC: NSPanel + NSTextView mgmt
│       ├── SocketListener.swift      # ~60 LOC: Unix socket reader + JSON decode
│       └── Protocol.swift            # ~30 LOC: Codable message types
├── Tests/
│   └── MynaKaraokeTests/
│       └── ProtocolTests.swift       # XCTest, Codable round-trip
├── Resources/
│   └── Info.plist                    # LSUIElement=YES, bundle ID com.dpsca... NO — use com.prerakgada.myna.karaoke
└── build.sh                          # swift build + .app wrap + codesign
```

**Total: ~200 LOC Swift, ~40 LOC shell, one Package.swift.**

**Bundle ID:** `com.prerakgada.myna.karaoke` (sidecar) and `com.prerakgada.myna` (outer). Get it right on day one — Gatekeeper UX disaster to rename later.

**Info.plist key combinations:**
- `LSUIElement = YES` — hides from Dock and Cmd-Tab
- `LSBackgroundOnly = NO` — need window server connection for NSPanel
- `LSMinimumSystemVersion = 14.0` (Sonoma) — unlocks TextKit2 cleanly, skips back-compat ladder

**SwiftUI vs AppKit:** AppKit for Tier 1. NSPanel with `becomesKeyOnlyIfNeeded = true` + `canBecomeKey = false` is 10 lines of AppKit. SwiftUI WindowGroup can't make non-activating floating panels without dropping to NSPanel anyway.

---

## 2. IPC protocol — Unix domain socket

**Socket path:** `~/.myna/karaoke.sock` (0600, user-owned).
- ✅ Verified `~/.myna/` doesn't exist yet — daemon needs to `mkdir -p ~/.myna/` with 0700 on first karaoke event.
- ❌ Not `/tmp` (purged unpredictably on macOS).
- ❌ No `XDG_RUNTIME_DIR` (not a macOS thing).

**Framing:** newline-delimited JSON (NDJSON). Debuggable via `nc -U ~/.myna/karaoke.sock | cat`. Codable JSON never emits embedded newlines (escapes them).

**Message schema:**

```json
{"v":1,"type":"start","id":"u_2c1f","sentence":"Hello world, this is Myna.",
 "words":[{"i":0,"t":"Hello"},{"i":1,"t":"world,"},{"i":2,"t":"this"},
          {"i":3,"t":"is"},{"i":4,"t":"Myna."}],
 "estimatedDurationMs":2400,"voice":"af_heart"}

{"v":1,"type":"word","id":"u_2c1f","i":2,"tMs":1100}

{"v":1,"type":"pause","id":"u_2c1f"}
{"v":1,"type":"resume","id":"u_2c1f","tMs":1100}
{"v":1,"type":"stop","id":"u_2c1f"}

{"v":1,"type":"config","fontSize":18,"position":"bottom","theme":"dark","opacity":0.95}

{"v":1,"type":"hello","sidecarPid":54321}  // sidecar → daemon, on connect
{"v":1,"type":"ack","id":"u_2c1f"}          // sidecar → daemon, on start receipt
```

**Key design points:**
- `"v":1` — protocol version on every message (cheap insurance for Tier 2)
- `"id"` — utterance UUID. Word events reference it. Mismatched ID → sidecar discards (crash-recovery primitive)
- `words` array pre-tokenized by daemon. Sidecar doesn't tokenize. One source of truth
- `tMs` is relative to utterance start, not wall-clock

**Backpressure:** single-slot mailbox with coalescing. If a `word` event arrives while previous is still painting, replace in the mailbox. `start` / `stop` / `pause` / `resume` / `config` never drop.

**Reconnection:** daemon owns spawn/respawn.
1. On `EPIPE`, daemon closes FD, spawns fresh sidecar via `Process` launch
2. Reconnects to socket (sidecar creates it on launch)
3. Re-sends cached `start` + most recent `word` event

Sidecar is dumb. Zero state survives across restarts.

---

## 3. Word-timing signal — the hard part

**Tier 1: Option B (daemon-side estimation), Option A hook stubbed in.**

**Option A reality check:** mlx-audio's Kokoro implementation does NOT emit phoneme-level alignment in streaming output today. (Prerak: confirm by `grep -r "alignment\|timestamps\|phoneme\|duration_predictor" ~/path/to/mlx-audio/`.) Adding it = Tier 2 PR project.

**Option C** (whisper-timestamps post-hoc forced alignment) — correct but expensive. 0.5-2s per utterance on M-series, would block synthesis-to-playback. Wrong for interactive Tier 1.

**Option B sketch:**

```python
# daemon/myna/karaoke/timing.py  (~40 LOC, new)
class WordTimingEstimator:
    # chars/sec baseline per voice, measured empirically once
    BASELINE = {"af_heart": 14.0, "af_sky": 13.5, ...}  # default 14.0

    def __init__(self, voice: str, sample_rate: int = 24000):
        self.cps = self.BASELINE.get(voice, 14.0)
        self.sample_rate = sample_rate

    def estimate(self, sentence: str, audio_samples: int) -> list[tuple[int, int]]:
        """Returns [(word_index, t_ms_relative_to_start), ...]"""
        words = sentence.split()
        total_ms = int(audio_samples * 1000 / self.sample_rate)
        weights = [len(w) + 1 for w in words]  # +1 for trailing space
        total_weight = sum(weights)
        out = []
        cumulative = 0
        for i, w in enumerate(weights):
            out.append((i, int(total_ms * cumulative / total_weight)))
            cumulative += w
        return out
```

Drift: 50-200ms over a 5-second sentence. Humans tolerate ~80ms; notice ~150ms. Acceptable for Tier 1's free-floating ribbon (not in-place AX highlight, where the eye is already comparing word-by-word).

**Where the emit hook goes** (in daemon synth orchestration):

```python
async def synthesize_and_play(text: str):
    sentences = split_sentences(text)
    for sentence in sentences:
        audio = await engine.synthesize(sentence)              # existing
        karaoke.emit_start(sentence, audio.duration_ms)        # NEW, ~1 LOC
        timings = WordTimingEstimator(voice).estimate(...)     # NEW
        asyncio.create_task(emit_word_events(timings))         # NEW
        await player.play(audio)                                # existing
        karaoke.emit_stop()                                     # NEW
```

Net daemon delta: ~80 LOC across `daemon/myna/karaoke/{timing,socket}.py` + ~8 LOC at orchestration site. Socket writer is `asyncio.open_unix_connection` — stdlib. No new Python deps.

---

## 4. Build, sign, notarize, bundle

**Build with `swift build -c release --arch arm64`, then wrap step.**

```bash
# karaoke/build.sh
set -euo pipefail
swift build -c release --arch arm64
mkdir -p MynaKaraoke.app/Contents/{MacOS,Resources}
cp .build/release/MynaKaraoke MynaKaraoke.app/Contents/MacOS/
cp Resources/Info.plist MynaKaraoke.app/Contents/
codesign --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID" MynaKaraoke.app
```

**Nested bundle structure:**
```
Myna.app/
└── Contents/
    └── Resources/
        └── MynaKaraoke.app/    # nested helper
            └── Contents/
                ├── MacOS/MynaKaraoke
                └── Info.plist
```

**Inside-out signing order (NON-NEGOTIABLE — caused v0.1.0's 10-iteration saga):**

1. Build sidecar binary
2. Wrap into MynaKaraoke.app
3. Sign sidecar `.app` with `--options runtime --timestamp`
4. `ditto` (NOT `cp -R`) signed sidecar into Myna.app/Contents/Resources/
5. Sign outer Myna.app (re-seals nested helper)
6. Notarize outer .app
7. Staple

**`cp -R` is wrong** — breaks extended attributes. Use `ditto`. Reference commit `a7fcbd2` from v0.1 sign saga.

**Homebrew tap:** zero changes. Sidecar lives inside Myna.app; cask installs Myna.app; sidecar comes along.

**Universal binary:** NO. arm64-only (mlx-audio is MLX-only, MLX is Apple Silicon only). Saves a `lipo` step and ~50% binary size.

---

## 5. Lifecycle and crash recovery

**Sidecar = on-demand child of daemon. NOT its own LaunchAgent.**

Daemon spawns via `subprocess.Popen([sidecar_path, "--socket", SOCKET_PATH])` on the first karaoke message after daemon boot. Sidecar inherits daemon's process group; if daemon dies, sidecar gets SIGHUP or detects `getppid() == 1` and exits.

**Lazy spawn timing:** don't spawn at daemon boot. Spawn on first karaoke event. Cold-start is ~100-200ms on M-series; for medium-length articles, invisible.

**Crash recovery cases:**

1. **Sidecar crashes mid-utterance:** Daemon's next socket write returns EPIPE. Daemon respawns, re-sends cached `start` + most recent `word`. Visible glitch: ~150ms blank ribbon. Acceptable.
2. **Daemon crashes:** Sidecar's socket read returns EOF. 10s idle timer → exit. Fade-out-after-1s is independent of socket state.
3. **User force-quits:** Daemon's `atexit` handler sends SIGTERM. If atexit doesn't fire (SIGKILL), parent-gone detector catches it within 5s.

**CRITICAL:** daemon must `Process.wait()` or `os.waitpid(pid, os.WNOHANG)` in event loop, or use `asyncio.create_subprocess_exec` (handles SIGCHLD correctly). Without this, Activity Monitor fills with `<defunct>` MynaKaraoke processes — embarrassing first GitHub issue.

---

## 6. Permissions and entitlements

**Tier 1 requires ZERO new permission prompts. Confirmed.**

NSPanel = window. Window doesn't need TCC. Reading own daemon over own Unix socket doesn't need TCC. No screen recording, no accessibility, no input monitoring, no notifications.

**Hardened runtime entitlements (all false — "I am a boring AppKit app"):**

```xml
<key>com.apple.security.cs.allow-jit</key> <false/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key> <false/>
<key>com.apple.security.cs.disable-library-validation</key> <false/>
```

**Tier 2 upgrade path** (when in-place AX highlight lands):
- Add `NSAccessibilityUsageDescription` to Info.plist
- User grants Accessibility in System Settings → Privacy
- Keep `com.apple.security.app-sandbox` disabled (sandboxed apps can't use AX on other apps)
- **Same bundle ID, same Developer ID, same entitlements file shape** — Gatekeeper doesn't see Tier 2 as a new app

---

## 7. Test surface

**Recommendation:** XCTest target for protocol + rendering. NO AppKit panel tests. NOT gated in CI for v0.2.

```
karaoke/Tests/MynaKaraokeTests/
├── ProtocolTests.swift          # Codable round-trip per message type
├── BackpressureTests.swift      # Single-slot mailbox semantics
└── EstimatorClientTests.swift   # Sidecar's tMs interpolation
```

Three files, ~150 LOC total, runs in ~1s via `swift test`. AppKit-free.

**Why not gate CI:** macOS runners are slow + expensive + flaky. Prerak runs `make test` locally pre-push. When sidecar grows past ~500 LOC or a second contributor lands, revisit.

**Python-side integration test:**

```python
# tests/test_karaoke_integration.py  (~50 LOC)
async def test_sidecar_receives_start_message(tmp_path):
    socket_path = tmp_path / "karaoke.sock"
    server = await asyncio.start_unix_server(echo_handler, path=str(socket_path))
    karaoke = KaraokeClient(socket_path)
    await karaoke.emit_start("Hello world", words=["Hello", "world"], dur_ms=1000)
    received = await asyncio.wait_for(received_queue.get(), timeout=1.0)
    assert json.loads(received)["type"] == "start"
```

Mock the socket server side, verify daemon writes right bytes. No real sidecar in Python tests.

**Honest test gap:** no automated "ribbon visually renders the right word at the right time." Manual QA pre-release. Acceptable for v0.2.

---

## 8. Honest 6-vs-16h breakdown

**6h version delivers:**

| Block | Hours | Deliverable |
|---|---|---|
| Swift sidecar skeleton (Package.swift, AppDelegate) | 0.5 | Empty .app that launches/exits cleanly |
| NSPanel + NSTextView + fade animation | 1.0 | Visible ribbon with hardcoded string |
| Socket listener + Codable protocol | 1.0 | Sidecar reads NDJSON, parses |
| Active-word rendering (NSAttributedString bolded range) | 0.5 | Word highlight with mock input |
| Daemon: socket writer + timing estimator | 1.0 | Real word events during real synthesis |
| Integration: spawn from daemon, end-to-end smoke | 0.5 | First real karaoke ribbon |
| Build script + sign + bundle into Myna.app | 1.0 | DMG builds with sidecar nested, correctly signed |
| Manual QA + small fixes | 0.5 | Looks good in 3 apps, doesn't crash |
| **Total** | **6.0h** | Tier 1 shipped |

**Corners cut to hit 6h:**
1. Timing is estimated, not measured (Option B drift accepted)
2. Single-display only
3. No live settings (compile-time constants; `config` message in protocol but sidecar ignores it)
4. No XCTest gating
5. Manual QA only

**What turns 6h → 16h:**

| Trap | +Hours |
|---|---|
| Notarization fails because of nested-bundle signing order | +3-4h |
| mlx-audio doesn't expose sample count, must instrument | +1-2h |
| Multi-display ribbon positioning | +1-2h |
| Font rendering: emoji + CJK in NSAttributedString ranges | +2-3h |
| LaunchAgent permission edge case (brew install → Gatekeeper) | +1-2h |
| Live config reload leaks into Tier 1 scope | +1-2h |

**Safe to cut:** 1, 2, 3, 4 (Tier 1.5 picks them up).

**NOT safe to cut:**
- Codable protocol versioning (`"v":1`)
- Sign-inside-out discipline (already paid tuition)
- Bundle ID stability
- `LSUIElement = YES`

---

## 9. Risk register — top 5

1. **mlx-audio doesn't expose audio duration cleanly.** *Mitigation:* first 30 min is grepping mlx-audio. If `synth()` doesn't return knowable buffer length, fall back to `AVAudioPlayer.duration` callback (+30 min).
2. **Nested-app signing breaks notarization.** *Mitigation:* sign sidecar first, outer Myna.app second. Reuse exact codesign invocations from v0.1.0 release flow. Test notarization on a Tier 0 commit before adding features.
3. **Word-timing drift annoying enough to look "broken."** *Mitigation:* measure on 3 real articles before committing to Option B. If drift >200ms on 80% of sentences, escalate to Option A.
4. **NSPanel `level=.statusBar` collides with menubar / fullscreen apps.** *Mitigation:* try `.floating` (level 3) first. Fullscreen Safari is the boss-fight test case.
5. **Sidecar spawned by daemon dies and zombies.** *Mitigation:* daemon uses `asyncio.create_subprocess_exec` (handles SIGCHLD) OR polls `os.waitpid(pid, os.WNOHANG)` in event loop.

---

## What I need from Prerak to start coding

1. Confirm `~/.myna/` doesn't exist (verified: it doesn't — daemon will create with 0700)
2. Confirm mlx-audio's synth call returns audio sample count or duration. `grep -r "duration\|samples\|len(audio)"` in mlx-audio source. **2 minutes.**
3. Confirm bundle ID prefix. Proposed: `com.prerakgada.myna.karaoke`. (Originally was `com.dpsca.myna.karaoke` — corrected to Prerak's identity.) **10 seconds.**
4. Confirm the existing DMG build script's entry point. Path + line where outer Myna.app gets signed. Need to inject sidecar build step there. **60 seconds.** (From v0.1.0: `dist/sign.sh`, `dist/build.sh` already exist; check structure.)
5. Pick Tier 1.5 variant for v0.2: (a) live settings reload [recommended], (b) multi-display ribbon, (c) better timing via mlx-audio PR. **30 seconds.**

Answer those five and Tier 1 commits by Sunday.
