# Feature stories — Amelia (S06–S16)

> **Source:** BMad party-mode rounds 2–4, agent: Amelia (Senior Software Engineer).
> **⚠️ Re-target required:** Original stories assumed Hammerspoon Lua surface. The actual menu bar / settings is the native Swift app at `apps/macos/Sources/`. File paths and tech specifics need re-mapping (see `README.md`); acceptance criteria and test plans remain useful as feature requirements.

## Sprint shape (planning artifact)

11 stories total. Original estimate: ~61h across 5 sessions. John (PM agent) recommends cutting S11, soft-cutting S10 and S15 — see `07-roundtable-discussions.md`.

| ID | Title | Size | Notes |
|---|---|---|---|
| S06 | Menu bar redesign | L (6h) | Re-target to SwiftUI in `apps/macos/Sources/MenuBar/` |
| S07 | Thinking indicator | S (3h) | Re-target to Swift `BirdIcon` state + daemon `/v2/status` |
| S08 | CC-hook ready toast | M (5h) | New Swift toast window + daemon `/v2/registry` endpoints |
| S09 | Voice preview in picker | M (5h) | Settings Voice tab — sample sentence on hover/click |
| S10 | What's New dialog | M (4h) | New Swift window; could reuse Sparkle "what's new" UI |
| S11 | First-run cinematic | L (10h) | New Swift `OnboardingWindowController` |
| S12 | Karaoke subtitle ribbon | L (7h) | Swift sidecar — already Swift, see `02-karaoke-architecture.md` |
| S13 | Settings webview shell | M (4h) | **OBSOLETE** — Settings UI already exists at `apps/macos/Sources/Settings/` |
| S14 | Release prep | L (10h) | Mostly already done in v0.1.0; minor sidecar bundling additions |
| S15 | Karaoke Tier 1.5 | varies | Three variants: live config reload (S), multi-display (M), mlx-audio PR (L) |
| S16 | Demo GIF pipeline | M (6h) | `myna demo <scenario>` CLI + ffmpeg encode wrapper |

---

## S06 — Menu bar redesign

**Goal:** state-driven menu bar icon + popover hierarchy with "Now reading" header, transport block, voice/speed/recent/CC submenus, footer with Settings entry.

**Acceptance criteria (re-targeted to Swift):**

1. Menu bar icon transitions between 5 states (idle / speaking / thinking / paused / error) with 150ms debounce.
2. Click popover renders in order: Now Reading block, separator, Transport (Pause/Stop/Skip±15s — each row shows current hotkey), separator, Voice ▸ Speed ▸ Recent ▸ [CC ▸ if non-empty], separator, Settings… Restart Daemon Quit.
3. Idle state collapses transport block to single dim "No audio playing" row; Now Reading hides.
4. Transport row titles include current hotkey from `keybindings.json`; updating keybinding reflects immediately on next popover open.
5. Multi-display: popover anchors on `NSScreen.main` at click time.
6. SwiftUI views unit-testable with stub view models.

**Tests:**
- Swift XCTest per submenu's state→view mapping with stub `MenuViewModel`
- Integration: launch app, drive through states via `/v2/status` injection, assert popover structure
- Manual: drag to second display, click, popover lands there

**Risk:** the current `MenuBarView.swift` already exists with simpler hierarchy. This is a re-layout, not a rewrite.

---

## S07 — Thinking indicator

**Goal:** when daemon state == thinking (synthesis warming, Ollama summarizing), icon shows soft halo animation + optional earcon at thinking-onset.

**Acceptance criteria:**

1. Daemon `/v2/status` extended to emit `state: idle | thinking | speaking | paused | error` with `since_ms` and `request_id`.
2. Swift app polls `/v2/status` every 250ms while non-idle, 1s while idle.
3. Icon halo cycles ~30% opacity peak at 600ms cosine when state==thinking.
4. Earcon plays once at thinking-onset if user setting enabled; never overlaps speech.
5. Animation suspends when battery is in Low Power Mode (check via `IOPSGetProvidingPowerSourceType`).
6. State machine has unit tests for valid/invalid transitions.

**Tests:**
- pytest for daemon state machine + `/v2/status` payload schema
- XCTest for `MenuBarController` icon-state mapping with mocked status responses
- Manual: kill engine, run `myna speak "hi"`, observe halo; restart engine, observe transition

**Risk:** the daemon already has v2/status (per STATUS.md). This story extends it; verify what's already there.

---

## S08 — CC-hook ready toast

**Goal:** when Claude Code Stop hook fires and audio is ready, show a small toast in the corner with project-colored dot, click-to-play.

**Acceptance criteria:**

1. Stop hook (`hooks/stop_hook.py`) calls `POST /v2/registry/announce` with `{id, source, title, ttl_s}`.
2. Daemon `/v2/registry/list` returns pending entries; `/v2/registry/play/{id}` triggers playback.
3. Swift toast window (NSPanel, non-activating, floating, ignoresMouseEvents=false for action area only) appears within 1.5s of registry write.
4. Toast displays project-colored dot (FNV-1a hash → palette index from `04-visual-direction.md`), source label, truncated title, "Play / Later / Dismiss" actions.
5. Auto-dismiss to menu-bar Claude Code submenu after 8s of no interaction; progress line shows timer.
6. Up to 3 toasts stack vertically; 4th+ collapses to "+N more" with badge on menu bar icon.
7. Respects macOS Focus mode — when DND active, route to submenu silently.

**Tests:**
- pytest for daemon `/v2/registry/*` routes
- pytest for `hooks/stop_hook.py` calling `announce`
- XCTest for `ToastWindowController` lifecycle, stack management, focus-mode detection
- Manual: trigger real CC Stop hook, verify toast + click plays audio

**Risk:** NSPanel focus-stealing edge cases on macOS 15.x. Test with `becomesKeyOnlyIfNeeded = true` + `canBecomeKey = false`.

---

## S09 — Voice preview in picker

**Goal:** in Settings → Voice tab, allow hovering or clicking a voice to hear a sample sentence before committing.

**Acceptance criteria:**

1. Daemon `POST /v2/voices/preview/{voice_id}` returns short synthesized WAV (≤3s), cached to `~/Library/Caches/myna/voice_previews/{voice_id}.wav`.
2. Cache invalidated when engine version bumps (check `engine /version` against cache manifest).
3. Settings voice picker shows preview button per voice (click-only — hover unreliable in SwiftUI menus).
4. During preview, current utterance (if any) ducks to 30% volume; preview plays at -6dB; resumes after.
5. Selecting a *different* voice while previewing cancels the in-flight preview within 100ms.
6. Engine warming (state==thinking) → preview returns 503; UI shows "Engine warming…" inline for 2s.

**Tests:**
- pytest for `/v2/voices/preview/*` route + cache hit/miss + invalidation
- pytest for ducking gain envelope during concurrent preview + utterance
- XCTest for Settings voice tab interaction
- Manual: click 5 voices in rapid succession — only last plays

**Risk:** the audio ducking path needs to not break existing playback. AVAudioEngine mixer node config.

---

## S10 — What's New dialog on first launch post-update

**Goal:** on first launch after auto-update, show a dialog listing the changes in the new version.

**Acceptance criteria:**

1. Persistent state in `~/Library/Application Support/Myna/state.json`: `last_seen_version`, `first_run_complete`.
2. On launch, if `installed_version > last_seen_version` AND `first_run_complete == true`, mark What's New as pending.
3. Swift window opens within 2s of launch, renders markdown from `Resources/changelogs/v0.X.Y.md`.
4. "Got it" button updates `last_seen_version = current`; subsequent launches skip.
5. Skipping (close button) also acks — no nag loop. Re-show only via menu's "What's New…" entry.
6. Missing changelog file → silent skip + log warning; never blocks boot.
7. Fresh install (`first_run_complete == false`) does NOT show What's New — first-run cinematic owns that slot.
8. Patch releases (0.x.y where y > 0) do NOT auto-show — minor releases only.

**Tests:**
- Swift unit tests for version comparison + state machine
- Integration: simulate version bump by editing state.json, restart, assert dialog
- Manual: install v0.1.0, upgrade to v0.2.0, verify dialog on next launch

**Risk:** Sparkle already has "what's new" support. Check whether to extend that vs. build new.

---

## S11 — First-run cinematic

**Goal:** 60-second spoken onboarding — Myna speaks its own introduction while walking through permission prompts.

**John's standing critique:** he recommends cutting this story for v0.2 since onboarding serves users you haven't measured yet. Defer to v0.3 if scope pressure.

**Acceptance criteria:**

1. On first launch where `first_run_complete != true`, full-screen overlay opens within 3s of menu-bar load.
2. Scene loader iterates through scene modules in order; adding scenes requires no orchestrator change.
3. Skip available from scene 2+; writes `first_run_complete = true` and `first_run_scene_reached`.
4. Quit mid-cinematic resumes from `first_run_scene_reached` on next launch.
5. Each scene has 30s max timeout; auto-advances if user idle.
6. Permission prompts (Accessibility, Notifications, Input Monitoring) woven into the script, not dumped as modals.
7. VoiceOver detection → silent mode with full captions, "Play with Myna's voice" opt-in button.
8. Mid-flow Cmd-Q saves state; menu bar shows "Finish setup ▸" banner.

**Tests:**
- Swift unit tests for scene loader, state persistence, resume logic
- Manual: delete state.json, restart, walk every scene; quit at scene 3, verify resume

**Risk:** highest fragility surface in the sprint (permission polling, audio sync, captions, VO fallback). John recommends defer.

---

## S12 — Karaoke subtitle ribbon

**See `02-karaoke-architecture.md` for the full architecture brief (Winston).**

Quick summary:
- New Swift sidecar (SwiftPM, ~200 LOC, NSPanel + NSTextView)
- Reads NDJSON over Unix socket at `~/.myna/karaoke.sock` from daemon
- Daemon emits word-timing events using char-weighted estimator (Option B — drift ≤200ms)
- Ribbon: bottom of screen, dark background, active word bold + 100% opacity, surrounding dim @ 55%
- Fade out 1s after last word
- Tier 1: 6h. Honest 6-vs-16h breakdown in the architecture doc.

**Files (re-targeted to actual stack):**
- NEW: `karaoke/Package.swift` — SwiftPM target `MynaKaraoke`
- NEW: `karaoke/Sources/MynaKaraoke/{main,PanelController,SocketListener,Protocol}.swift`
- NEW: `karaoke/Resources/Info.plist` — LSUIElement=YES
- NEW: `karaoke/build.sh` — swift build → wrap into .app
- NEW: `daemon/myna/karaoke/{timing,socket}.py`
- EDIT: `daemon/myna/synth.py` or equivalent — emit word events at synth boundaries
- EDIT: `dist/build.sh` / signing scripts — bundle sidecar inside Myna.app

---

## S13 — Settings webview shell

**OBSOLETE.** The Swift Settings UI already exists at `apps/macos/Sources/Settings/` with 4 tabs (Hotkeys, Voice, Daemon, Advanced) per `STATUS.md`. The party-mode story assumed Hammerspoon — irrelevant.

If anything is needed here, it's a 6th tab for Behavior (toast settings, thinking-indicator earcon toggle, karaoke ribbon settings) and an About tab. Both are minor extensions of existing SettingsViewModel, not a new shell.

**Drop from sprint.** Roll any settings additions into the relevant feature stories (S07, S08, S15a).

---

## S14 — Release prep (DMG + nested-app signing + notarization)

**Mostly already done in v0.1.0** — `dist/build.sh`, `dist/sign.sh`, `dist/notarize.sh`, `tap/`, `appcast.xml` all exist and shipped.

**What's NEW for v0.2:**

1. Add karaoke sidecar to the bundle: `MynaKaraoke.app` nested at `Myna.app/Contents/Resources/MynaKaraoke.app`.
2. Update `dist/sign.sh` for inside-out nested signing (Winston's 7-step sequence):
   - Sign sidecar `.app` first with `--options runtime --timestamp`
   - `ditto` (NOT `cp -R`) into outer bundle
   - Sign outer `.app` (re-seals nested helper)
   - Notarize outer; staple
3. Smoke test: `pgrep -f MynaKaraoke` returns PID after karaoke trigger.
4. Verify `codesign --verify --deep --strict /Applications/Myna.app` and `spctl --assess --type execute` both pass.

**Lessons from v0.1.0 saga (per MEMORY.md) that apply:**
- Tar `.app` between every CI job (upload-artifact flattens bundles)
- Preserve Sparkle.framework root Autoupdate symlink
- Delete stale `_CodeSignature/` before re-signing
- arm64-only; `LSMinimumSystemVersion = 14.0`

**Tests:**
- Dry-run mode (`--no-sign --no-notarize`) — verify bundle structure
- Tar-roundtrip regression test
- `ci/smoke_test.sh` against published DMG

**Risk:** the nested-app signing wrinkle is the single biggest v0.2 release risk. Dry-run twice before the real cut.

---

## S15 — Karaoke Tier 1.5 (three variants — pick one for v0.2)

### S15a — Live config reload (S, 3h) **← recommended**

Sidecar listens for `{"type":"config",...}` socket messages, applies font/position/theme without restart. Daemon exposes `POST /v2/karaoke/config`. Settings → Behavior tab gains 3 controls bound to that endpoint.

**Why:** lowest shipping cost, activates settings UI, demos well as a GIF (live slider → ribbon morphs).

### S15b — Multi-display ribbon (M, 5h)

Sidecar detects all `NSScreen.screens`, creates one NSPanel per display. On play, picks the screen of the active app. Handles display hotplug.

**Why:** wow factor for multi-monitor users. Niche-of-niche.

### S15c — mlx-audio PR for true word durations (L, 8h external)

Upstream PR to mlx-audio adding `return_word_timings=True` kwarg. Engine consumes it if present; falls back to Option B otherwise.

**Why:** best quality lever — fixes the drift that karaoke users will complain about. But unbounded shipping cost (upstream review).

**Overlap warning:** all 3 touch `karaoke/Sources/MynaKaraoke/PanelController.swift`. If picking two, do 15b first (structural refactor) then 15a (additive method).

**Recommendation:** S15a in v0.2. 15b and 15c to v0.3.

---

## S16 — Demo GIF production pipeline

**Goal:** scripted, deterministic CLI to record the 4 named launch GIFs without hand-curating QuickTime each time.

**Acceptance criteria:**

1. `myna demo --list` prints all 4 scenarios with target durations.
2. `myna demo gif-1-hook` orchestrates Chrome open → AX-select paragraph → trigger hotkey → wait for audio → quit. Total runtime ±300ms of 4.0s across 5 runs.
3. `myna demo gif-2-cc-stack` fires 3 sequential `POST /v2/registry/announce` calls at 1500ms intervals from fixture sessions; holds 2s post-final-toast.
4. `myna demo gif-3-karaoke-vscode` and `gif-4-karaoke-multi-app` use `osascript` to drive VS Code / Safari / Slack focus + trigger TTS at scripted offsets.
5. `tools/record_demo.sh gif-N` wraps screen capture + ffmpeg palettegen encode; output ≤5MB warn, fail >10MB.
6. `demo_reset.py` idempotent pre-scenario cleanup; aborts if can't reach clean state in 10s.
7. Encoding targets: `--target twitter` (≤5MB, 1280×720, 24fps), `--target hover-thumb` (≤2MB, 640×360, 12fps).

**Hand-curated fixtures (Prerak's job, not code):**
- `demo/fixtures/article.html` — 4-second-of-TTS punchy article
- `demo/fixtures/cc_sessions.json` — 3 realistic session summaries (no private project leaks)
- `demo/fixtures/code_sample.swift` — visually distinctive code for VS Code shots

**Tests:**
- pytest for scenario orchestration step ordering
- Determinism: run `gif-1-hook` 3x, diff output byte-checksums

**Risk:** Chrome AX-select is finicky; budget 1h yak-shaving. Fallback: triple-click + cmd+c via osascript.

---

## Updated sprint shape (after John's recommended cuts)

If you take John's cut of S11 (cinematic) and drop S13 (obsolete):

| Story | Hours |
|---|---|
| S06 Menu bar redesign | 6 |
| S07 Thinking indicator | 3 |
| S08 CC-hook ready toast | 5 |
| S09 Voice preview | 4 |
| S10 What's New dialog | 4 |
| S12 Karaoke ribbon | 7 |
| S14 Release prep extension | 4 (only the sidecar bundling delta) |
| S15a Live config reload | 3 |
| S16 Demo GIF pipeline | 6 |
| **Total** | **42h** |

**Single-point-of-failure for v0.2 ship:** S14 (nested-app signing). Mitigation: dry-run twice; treat Winston's 7-step sequence as gospel-by-paste, not gospel-by-paraphrase.
