# Myna — Operations & Release Architecture

> **Scope.** This document covers the operations / release infrastructure
> only: GitHub Actions, code-signing + notarization shell scripts, Homebrew
> tap, LaunchAgents, the `install.sh` dev installer, the `cli/myna` wrapper,
> the legacy Hammerspoon module, and the Claude Code Stop hook. Application
> internals (Swift app, Python daemon) and the marketing site are documented
> in their respective lane docs. Cross-references to `RELEASE.md`,
> `HANDOFF.md`, and `STATUS.md` are given by file:section rather than
> reproduced inline.

---

## 1. Executive Summary

The ops layer exists to turn a single human action — `git tag vX.Y.Z && git push --tags` — into a fully reproducible release artifact: a signed, notarized, stapled `Myna.app` packaged in a signed, notarized DMG, attached to a GitHub Release, advertised through a Sparkle EdDSA-signed appcast, and exposed through a Homebrew tap (`brew install --cask myna`). The pipeline is implemented as **nine sequential GitHub Actions jobs** (`.github/workflows/release.yml`), each delegating real work to a shell script under `dist/`, and is supported by two helper workflows (`ci.yml` for PR validation, `appcast.yml` for one-shot appcast rebuilds).

v0.1.0 shipped via this pipeline on 2026-05-26 in run [26438169061](https://github.com/PrerakGada/myna/actions/runs/26438169061) — iteration 10. The 9-iteration saga that preceded it (a Sparkle.framework signing bug that was actually an upload-artifact symlink/xattr-flattening bug) is documented in `HANDOFF.md:34`–`44`; the defensive code added during that hunt remains in `dist/sign.sh` lines 50–165 and the `tar`-between-jobs invariant in `release.yml` lines 126–134.

---

## 2. Components overview

| Component | Files | Role |
|---|---|---|
| **CI workflow** | `.github/workflows/ci.yml` | Build + test + lint on every PR (Swift app, Python daemon, dist script smoke). No signing. |
| **Release workflow** | `.github/workflows/release.yml` | 9-job pipeline triggered on `git push --tags v*`. Builds → signs → notarizes → DMG-packages → re-signs DMG → re-notarizes DMG → creates GH release → signs Sparkle appcast → bumps tap. |
| **Appcast rebuild workflow** | `.github/workflows/appcast.yml` | Manual (`workflow_dispatch`) regeneration of `appcast.xml` from the last N GitHub Releases. Disaster-recovery only — `release.yml` appends incrementally. |
| **dist/ shell scripts** | `dist/{build,sign,notarize,dmg,appcast}.sh`, `dist/_lib.sh`, `dist/tests/test_scripts.sh` | All real work happens here. Each script supports `--dry-run` and `--help` and can be invoked locally (see `RELEASE.md:209`–`260`). |
| **Homebrew tap (source)** | `tap/Casks/myna.rb`, `tap/Formula/myna-daemon.rb`, `tap/README.md` | Source-of-truth for the tap; mirrored into `PrerakGada/homebrew-tap` by the `tap-bump` job. |
| **LaunchAgents** | `launchagents/dev.myna.{daemon,engine}.plist.template` | Per-user agents that keep the Python daemon and mlx-audio engine running 24/7. Templated on `__HOME__`; installed by `install.sh`. |
| **install.sh** | `install.sh` (root) | One-shot local dev installer: venv, CLI symlink, Hammerspoon copy, CC-hook JSON merge, LaunchAgent unload+load. Idempotent. |
| **CLI wrapper** | `cli/myna` | 27-line bash POSTer to `/speak`. Supports `--summary`, `--speed`, `MYNA_PORT`. |
| **Hammerspoon legacy** | `hammerspoon/myna.lua` | v1 menu-bar + hotkey driver. Kept alongside the new Swift app — both work; last hotkey registration wins. |
| **CC Stop hook** | `hooks/myna-cc-announce.py` | Claude Code Stop hook that POSTs the last assistant turn to `/announce`. Silent, best-effort. |

---

## 3. `release.yml` job graph

Triggered on `push: tags: [v*]` and `workflow_dispatch{inputs.tag}`. Concurrency group `release-${{ github.ref }}`, `cancel-in-progress: false`. `permissions: contents: write` (needed by `gh release create`). Xcode pinned to 16.0 via `env.XCODE_VERSION`.

```
preflight ──┬─► build-universal ─► sign ─► notarize ─► dmg ─► sign-dmg ─► appcast ─► release ─► tap-bump
            │                                                                                 (gated on
            └──────────────────────────────────────────────────────────────────────────────── has_tap_key)
```

### Jobs in detail

| # | Job | `needs` | Output artifact | Format | Why this format |
|---|---|---|---|---|---|
| 1 | `preflight` (`release.yml:45`) | – | – | sets `outputs.version`, `outputs.has_tap_key` | Fail-fast on missing secrets. Detects optional `TAP_DEPLOY_KEY` and gates `tap-bump`. |
| 2 | `build-universal` (`:104`) | preflight | `myna-app-unsigned` | **tar** of `Myna.app` | xcodebuild archive → `dist/build.sh`. Tar (not raw upload) preserves Sparkle.framework symlinks + xattrs across the artifact boundary. |
| 3 | `sign` (`:136`) | preflight, build-universal | `myna-app-signed` | tar | Imports Developer ID p12 into temp keychain, runs `dist/sign.sh`. |
| 4 | `notarize` (`:187`) | preflight, sign | `myna-app-stapled` | tar | `dist/notarize.sh` with `TARGET_SET=1` forcing the .app path; stapler runs after notary `Accepted`. |
| 5 | `dmg` (`:219`) | preflight, notarize | `myna-dmg-unsigned` | raw .dmg | `brew install create-dmg`, then `dist/dmg.sh`. |
| 6 | `sign-dmg` (`:247`) | preflight, dmg | `myna-dmg` | raw .dmg | Inline `codesign --force --timestamp` + `dist/notarize.sh TARGET_SET=1`. Stapled in place. |
| 7 | `appcast` (`:305`) | preflight, sign-dmg | `appcast` (file: `appcast.xml`) | XML | Downloads existing appcast from the `appcast` GH release (404 tolerated for the first ever release), installs `sign_update` from Sparkle 2.6.4 tarball + Homebrew `openssl@3`, runs `dist/appcast.sh`. Exposes `outputs.sha256` of the DMG for `tap-bump`. |
| 8 | `release` (`:372`) | preflight, sign-dmg, appcast | – | – | Idempotent `gh release create`/`upload --clobber` for the `v$VERSION` release; same for the permanent `appcast` release (Sparkle's `SUFeedURL` points to its `appcast.xml` asset). |
| 9 | `tap-bump` (`:422`) | preflight, appcast, release; `if: has_tap_key == 'true'` | – | git commit pushed to `PrerakGada/homebrew-tap` (or `${vars.HOMEBREW_TAP_REPO}`) | Updates `Casks/myna.rb` (`version` + `sha256` of DMG) and `Formula/myna-daemon.rb` (`url` + `sha256` of generated source tarball). Curl-retries up to 5× for the GitHub-generated tarball. |

### The tar-between-jobs workaround (cite `HANDOFF.md:34`–`44`)

Iterations 2–9 of the v0.1.0 release chased Sparkle.framework signing structure bugs that were actually a single upstream cause: `actions/upload-artifact@v4` uses a Linux-style zip that (a) **follows symlinks**, flattening Sparkle's `Versions/Current → B` layout into duplicate real directories, and (b) **strips macOS extended attributes** that Sealed Resources V2 hashing depends on. The flattening happened twice — once between Build and Sign, once between Sign and Notarize — and the second one mutated a freshly-signed bundle, so notary rejected with `"The signature of the binary is invalid"` on the top-level Mach-O binaries.

The fix is the **`tar -cf … -C …`** at the end of every upload-producing job (lines 127, 178, 210, plus the dmg-stage equivalents) and the matching `tar -xf` at the start of every consumer job (lines 148, 198, 230). Tar preserves symlinks + xattrs verbatim. **Do not remove these tar steps.** The block comment at `release.yml:118`–`125` is the on-file warning.

The symlink-normalization block inside `dist/sign.sh` (`sign_sparkle()`, lines 66–164) stays in place as belt-and-braces defence in case Xcode itself flattens any future build.

---

## 4. Signing & notarization

### Identity

Secret `APPLE_DEVELOPER_ID_NAME` — e.g. `Developer ID Application: Prerak Gada (RC63N3VU27)`. Imported from a base64-encoded p12 (`APPLE_DEVELOPER_ID_P12` + password) into a fresh temp keychain per job (`release.yml:150`–`172`, repeated at `:258`–`278`).

### Codesign flags

All codesign invocations in `dist/sign.sh` use:

- `--force` (replace existing signature)
- `--options runtime` (**hardened runtime** — mandatory for notarization)
- `--timestamp` (Apple TSA round-trip, mandatory for notarization)
- `--keychain "$KEYCHAIN_PATH"` (the temp keychain just created)
- `--entitlements apps/macos/Resources/Myna.entitlements` (only on the root `.app` — preserves Xcode's archive-time entitlements; `dist/sign.sh:199`)

The main `.app` is signed **last** (`sign.sh:197`–`201`) so that all nested signatures are already in place when the outer `_CodeSignature/CodeResources` Sealed Resources V2 hash is computed. Verification follows: `codesign --verify --deep --strict --verbose=2` plus a non-fatal `spctl --assess --type execute`.

### Sparkle.framework bottom-up signing flow (`sign.sh:66`–`164`)

Sparkle 2 ships a **versioned** framework. Apple's framework rule allows only `Versions/` + alias symlinks (`Sparkle`, `Headers`, `Modules`, `Resources`, `Updater.app`, `XPCServices`, plus the empirically-observed `Autoupdate`) at the framework root. Xcode's embed-and-sign frequently flattens these into real directories during CI, which makes the bundle ambiguous (`"bundle format is ambiguous (could be app or framework)"`) or unsealed-content-bearing (`"unsealed contents present in the root directory of an embedded framework"`).

`sign_sparkle()` does three things:

1. **Normalize** the framework: restore the `Versions/Current → B` symlink if Xcode replaced it with a real dir, restore each top-level alias symlink, and drop any stale root `_CodeSignature/` left over from Xcode's pre-sign.
2. **Sign bottom-up inside `Versions/B`**: `Autoupdate` binary → `Updater.app/Contents/MacOS/Autoupdate` → `XPCServices/{Downloader,Installer}.xpc` → `Updater.app` → `Versions/B`.
3. **Sign the framework root** (now unambiguously versioned).

The generic post-Sparkle find loop (`sign.sh:174`–`191`) signs every other `.framework | .bundle | .xpc | .app` deepest-first (longest path = deepest, `sort -rn`), explicitly excluding the Sparkle subtree (`-not -path "*/Sparkle.framework*"`).

**Bash 3 portability** (`sign.sh:174`–`182`): `mapfile`/`readarray` is bash 4+; macOS runners default to bash 3.2 and bail with `command not found`. The `while IFS= read -r t` loop is the portable equivalent (commit `f996347`, also called out in AUDIT_REPORT.md Lane B 🟡 #1).

### Notarization (`dist/notarize.sh`)

- If `TARGET` is a `.app`, `ditto -c -k --keepParent` zips it to `dist/build/Myna.app.zip` and that zip is submitted (notarytool refuses raw `.app`s).
- `xcrun notarytool submit --wait --timeout 30m` blocks until Apple returns `Accepted` or `Invalid`.
- On success, `xcrun stapler staple "$TARGET"` then `stapler validate` writes the offline ticket back into the original bundle/DMG. The zip artifact (when used) is discarded.

`.dmg` notarization (steps 6 in the job graph) reuses the same script with `TARGET=…/Myna-$VERSION.dmg TARGET_SET=1` so the .dmg-auto-detect at `notarize.sh:30` is suppressed.

---

## 5. Sparkle pipeline

### EdDSA keys

- **Public key** baked into the .app at build time as `SUPublicEDKey` in `apps/macos/project.yml` (line 60) and rendered into `apps/macos/Resources/Info.plist`. Current value: `lEoEYOBRVnzZC9bysaAYSRpEuXSDmd/FagSmzv2ozHg=` (per `HANDOFF.md:88`).
- **Private key** held only in GitHub secret `SPARKLE_EDDSA_PRIVATE_KEY` (base64 of the 32-byte raw Ed25519 seed) and 1Password (`Myna Sparkle EdDSA private key`). The `dist/sparkle_private_key.NEVER_COMMIT.txt` file is git-ignored and was deleted from disk post-setup (`RELEASE.md:54`).

### Signing the appcast item (`dist/appcast.sh:53`–`155`)

The script prefers Sparkle's official `sign_update` binary (installed in CI at `release.yml:340`–`354` from the pinned Sparkle 2.6.4 tarball). If that's missing, it falls back to **real OpenSSL** (`openssl pkeyutl -sign -inkey <pem> -rawin -in <dmg> -out <sig>`) — explicitly **rejecting LibreSSL**, which ships as `/usr/bin/openssl` on macOS and cannot do raw Ed25519 via `pkeyutl -rawin` (LibreSSL ≤3.x). Auto-detection at `:74`–`88`. Per AUDIT_REPORT.md Lane B 🔴 #2.

The PEM the fallback builds wraps the 32-byte seed in the PKCS#8 prefix `302e020100300506032b657004220420` (`appcast.sh:139`).

### Dedicated `appcast` GitHub release

`release.yml:405`–`420` publishes `appcast.xml` as the only asset on a single, **permanent, never-deleted** GH release tagged `appcast` (idempotent create-if-not-exists + `gh release upload --clobber`). Sparkle's `SUFeedURL` points to this asset's download URL — that's how every shipped copy of Myna polls for updates.

### Key-rotation hazard (cite `RELEASE.md:58`–`62`)

**Never rotate `SPARKLE_EDDSA_PRIVATE_KEY` after the first public release.** Sparkle verifies every appcast signature against the public key baked into the installed .app at build time. A rotated private key means **every installed copy refuses every future update**, with no remote remediation possible — users must download a new build manually once. If the key leaks, the only safe move is a new minor version with a new public key and a one-time-manual upgrade prompt to existing users.

### Appcast XML shape (`appcast.sh:159`–`205`)

Each `<item>` carries `sparkle:version` (build number), `sparkle:shortVersionString` (marketing version), `sparkle:minimumSystemVersion` (default `13.0`), and `<enclosure url=… sparkle:edSignature=… length=…>`. New items are **prepended** inside `<channel>` by a Python heredoc that also de-dupes any pre-existing `<item>` for the same version (`appcast.sh:212`–`230`). Values are passed via env vars so a tag like `v0.1.0"""` cannot break out of the Python string literal (per AUDIT_REPORT.md Lane B 🟡 #2).

---

## 6. Homebrew tap

### Split rationale: cask vs formula

- **`tap/Casks/myna.rb`** — installs the prebuilt, signed, notarized `Myna.app` from the GitHub Releases DMG. `auto_updates true` defers in-app updates to Sparkle so `brew upgrade` doesn't fight Sparkle mid-download (lines 13–17). `depends_on macos: ">= :ventura"`. `depends_on formula: "myna-daemon"`. `zap trash:` lists every `~/Library` path Myna touches.
- **`tap/Formula/myna-daemon.rb`** — Python daemon (FastAPI + uvicorn + httpx + trafilatura + summarizer). Installed as a Homebrew formula because the cask depends on it.

### The resource-block generation gymnastics (cite `HANDOFF.md:48`–`58`)

Homebrew's `pip_install_and_link` is hardcoded to `--no-deps`. To get the daemon's 40+ transitive PyPI dependencies installed, every one must be declared as a separate `resource "name" do …` block with a pinned PyPI sdist URL and sha256. Three orthogonal pitfalls (per `MEMORY.md:homebrew-python-monorepo-pitfalls`):

1. `virtualenv_install_with_resources` is hard-coded to use `buildpath` (the extraction root) regardless of a surrounding `cd "daemon" do … end` block — pip runs against the repo root, which has no `pyproject.toml`. **Fix:** use `venv = virtualenv_create(libexec, "python3.13"); venv.pip_install resources; venv.pip_install_and_link buildpath/"daemon"` (deployed formula lines 242–244).
2. `pip_install_and_link --no-deps` means resources must be exhaustive — no transitive ride-along. `/tmp/gen-resources.py` (deployed in the tap repo, not in this monorepo) queries the PyPI JSON API for sdist URL + sha256 of every dep.
3. `--no-binary :all:` policy means even pure-Python wheels are rebuilt from sdist, and pydantic_core + watchfiles ship Rust extensions that can't bootstrap source-only. **Fix:** `depends_on "rust" => :build` (line 22).

**Divergence — must reconcile before v0.2** (cited `HANDOFF.md:74`–`77`): the source formula in this repo (`tap/Formula/myna-daemon.rb`) was updated only for the dead `cd` removal. The deployed `PrerakGada/homebrew-tap/Formula/myna-daemon.rb` has the full 40-resource block list + `depends_on "rust" => :build`. If someone re-bootstraps the tap from this repo, they'll ship a broken formula. The `tap-bump` job (`release.yml:480`–`499`) only copies the source if the deployed formula doesn't exist, then sed-updates `url` + `sha256` — so the divergence is benign for v0.1.x but will land badly on a tap re-init.

### `brew test` will fail

The formula's `test do` block (lines 301–304) asserts `"usage"` appears in `myna-daemon --help` output, but the daemon has no `argparse` and `--help` won't print `usage`. Either add argparse or change the assertion. Tracked in `STATUS.md:182` and `HANDOFF.md:67`.

### `brew services`

The formula declares a Homebrew-managed LaunchAgent (lines 271–278): `keep_alive true`, `log_path var/"log/myna-daemon.log"`, `working_dir var/"myna"`, env var `MYNA_CONFIG_DIR: etc/"myna"`. Users run `brew services start myna-daemon` once.

---

## 7. LaunchAgents (dev / non-Homebrew)

`launchagents/dev.myna.{daemon,engine}.plist.template` are the per-user agents `install.sh` writes. Both templates substitute `__HOME__` for `$HOME` at install time (`install.sh:66`–`71`).

| Plist | Program | Port | `KeepAlive` | `WorkingDirectory` | Logs |
|---|---|---|---|---|---|
| `dev.myna.engine.plist` | `~/.venvs/mlx-audio/bin/python -m mlx_audio.server --host 127.0.0.1 --port 8765` | 8765 | true | `~/.cache/myna` | `~/Library/Logs/myna-engine.log` |
| `dev.myna.daemon.plist` | `~/.venvs/myna/bin/python -m myna` | 8766 | true | `~/.cache/myna` | `~/Library/Logs/myna-daemon.log` |

`RunAtLoad: true` + `KeepAlive: true` makes them always-on. `WorkingDirectory=~/.cache/myna` because mlx-audio writes a relative `logs/` directory and we want it sandboxed away from the user's `$PWD`. Both `StandardOutPath` and `StandardErrorPath` point at the same file so stderr is interleaved with stdout for one-pane debugging.

These are the **dev** path; the production install path is the Homebrew formula's `service do` block (see §6 above).

---

## 8. `install.sh`

A 79-line idempotent local-dev installer. Every step is safe to re-run.

1. **Prerequisites check** (`install.sh:6`–`12`) — `PY313` (default `~/.local/bin/python3.13`), `~/.venvs/mlx-audio` directory, optional `ollama`, optional `Hammerspoon.app`. Fails on missing Python; warns on the optional ones.
2. **Daemon venv + editable install** (`:14`–`16`) — `python3.13 -m venv ~/.venvs/myna` if absent, `pip install --upgrade pip`, `pip install -e $REPO/daemon`.
3. **Default keybindings.json** (`:18`–`28`) — written to `~/.config/myna/keybindings.json` only if absent. ⌘⌥⇧ on S/A/R/Space/. for the five actions.
4. **CLI symlink** (`:30`–`33`) — `chmod +x cli/myna`, `ln -sf $REPO/cli/myna ~/.local/bin/myna`.
5. **Hammerspoon module copy** (`:35`–`39`) — `cp $REPO/hammerspoon/myna.lua ~/.hammerspoon/myna.lua`. Idempotently appends `myna = require("myna"); myna.start()` to `~/.hammerspoon/init.lua` only if not already present.
6. **CC Stop hook JSON merge** (`:41`–`61`) — `chmod +x` the hook, then a Python heredoc opens `~/.claude/settings.json`, parses it (or starts `{}` if absent), and appends a new `{ "hooks": [{ "type": "command", "command": "<absolute path>" }] }` block under `hooks.Stop` **only if** no existing entry has the same `command`. This is the canonical pattern for JSON-merge into a shared user settings file without clobbering anything else.
7. **LaunchAgents** (`:63`–`71`) — `mkdir -p ~/Library/LaunchAgents ~/.cache/myna`, then for both `engine` and `daemon`: `sed` substitute `__HOME__`, write to `~/Library/LaunchAgents/dev.myna.<n>.plist`, `launchctl unload` (suppressing the not-loaded error), `launchctl load`. The unload/load cycle (rather than `kickstart`) ensures any in-flight process is killed before reload.

Final prints next-step instructions (Hammerspoon Reload Config, launch-at-login, PATH).

---

## 9. CLI (`cli/myna`)

27-line bash wrapper around `POST http://127.0.0.1:8766/speak`. Accepts:

- Positional text args (joined with space) **or** stdin (when no args).
- `--summary` → adds `"mode": "summary"` (default `"full"`).
- `--speed <float>` → adds `"speed": <float>`.
- `MYNA_PORT` env override (default `8766`).

JSON body built with a small Python one-liner (avoids shell-quoting hell). Curl is silent (`-s`) and output suppressed (`>/dev/null`) — the daemon does the speaking; the CLI is fire-and-forget. Always sets `"source": "cli"` so the daemon can attribute the speak request.

Examples (from `README.md:79`–`83`):
```bash
myna "Read this aloud."
pbpaste | myna
myna --summary "Long text to condense first."
myna --speed 1.25 "Faster reading."
```

---

## 10. Hammerspoon legacy (`hammerspoon/myna.lua`)

The v1 control surface. 322 lines of Lua, preserved alongside the new Swift app per `STATUS.md:167`: *"both can run side-by-side (second hotkey registration wins; in practice you'll keep one or the other)."*

**Why preserved:** v0.1.0 ships the Swift app, but the Hammerspoon path is a working safety net — if the Swift app breaks on a future macOS, users can fall back to `brew install hammerspoon` + `./install.sh`. It also still drives an ad-hoc menu bar with five features the Swift app may not yet have shipped 1:1.

**What it does:**
- Polls `GET /status` every 1.5s (`tick()`, line 117); reflects `state ∈ {idle, playing, paused, down}` as a menu-bar suffix marker.
- Custom monochrome bird canvas icon (line 18–34), falls back to emoji `🐦` if `imageFromCanvas()` fails.
- Builds a context menu with Pause/Resume, Stop, Speed submenu (0.75/1.0/1.25/1.5/2.0×), the Claude-Code registry (each item has Full / Summary submenus that POST `/play/<id>?mode=…`), and Customize Shortcuts… / Open Logs / Reload Myna / Hammerspoon Console.
- Five global hotkeys (`bindAll()`, line 211) loaded from `~/.config/myna/keybindings.json` with `DEFAULT_BINDINGS` fallback: speak-full, speak-summary, read-chrome-article, pause-resume, stop.
- Selection capture: `hs.eventtap.keyStroke({cmd}, "c")` + 120ms sleep + `hs.pasteboard.getContents()` (`selectionText`, line 160).
- Chrome URL via AppleScript (`chromeURL`, line 175); falls back to selection-speak on `extract_failed` response (line 192).
- Custom hotkey **recorder** (`openRecorder` + `captureNextChord`, lines 267–308) — chooser UI, captures the next key chord via `hs.eventtap`, detects collisions with existing bindings, persists to `keybindings.json`, rebinds.

**Dual-registration hotkey conflict:** both the Hammerspoon module and the Swift app use `hs.hotkey.bind` / `KeyboardShortcuts` to register `⌘⌥⇧S` etc. with macOS. **Last registration wins.** In practice run only one. The README's "Install" section (`README.md:51`–`59`) still references the Hammerspoon install path even after the Swift app shipped — both code paths remain valid; pick your surface.

---

## 11. Claude Code Stop hook (`hooks/myna-cc-announce.py`)

A 82-line Python script registered as a Claude Code **Stop** hook by `install.sh:41`–`61`. Stop fires after Claude finishes a turn; the hook:

1. Reads a JSON event from stdin (Claude Code's hook protocol). Silently exits on parse failure.
2. Walks the `transcript_path` JSONL file and finds the **last** `type: assistant` (or `message.role == "assistant"`) entry. Joins the `content[].text` parts. Truncates to 8000 chars.
3. Derives a short `label` from the basename of the session's `cwd`.
4. POSTs `{session_id, label, text}` to `http://127.0.0.1:8766/announce` with a 1.5-second timeout. Silently exits on any HTTP failure (`urllib.urlopen` raises → caught and ignored).

**Registry pick semantics** — the daemon's `/announce` adds an entry to its `registry`; the Hammerspoon menu bar (or Swift app) shows the announced sessions as menu items so the user can click **Full** / **Summary** on the one they care about. They never all play at once. This is the core "parallel-CC sessions don't talk over each other" UX (`README.md:23`–`25`).

`MYNA_PORT` env override supported (defaults `8766`).

---

## 12. Secrets matrix

All 9 GitHub Actions secrets, cited from `RELEASE.md:107`–`117`:

| Secret | Used by | Purpose |
|---|---|---|
| `APPLE_DEVELOPER_ID_P12` | `release.yml` `sign`, `sign-dmg` | base64 of Developer ID `.p12` export (cert + private key) |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | same | password set on the p12 export |
| `APPLE_DEVELOPER_ID_NAME` | `dist/sign.sh` env `DEVELOPER_ID_APPLICATION` | identity string, e.g. `Developer ID Application: Prerak Gada (RC63N3VU27)` |
| `APPLE_ID` | `dist/notarize.sh` | Apple ID email |
| `APPLE_ID_APP_PASSWORD` | `dist/notarize.sh` | app-specific password from appleid.apple.com |
| `APPLE_TEAM_ID` | `dist/notarize.sh` | 10-char team ID |
| `KEYCHAIN_PASSWORD` | `release.yml` `sign`, `sign-dmg` | random string used to create + unlock the temp keychain |
| `SPARKLE_EDDSA_PRIVATE_KEY` | `release.yml` `appcast`, `appcast.yml` | base64 32-byte raw Ed25519 seed for `sign_update`/openssl fallback |
| `TAP_DEPLOY_KEY` | `release.yml` `tap-bump` (optional — gated by `preflight`) | SSH private key (Ed25519) with write access to the tap repo |

Also: `vars.HOMEBREW_TAP_REPO` (repo variable, optional) overrides the default tap repo path (`<owner>/homebrew-tap`).

Verify with `gh secret list --repo PrerakGada/myna`.

---

## 13. CI workflow (`ci.yml`)

Triggered on push/PR against `main` and `native-app-rebuild`. Concurrency-grouped to cancel in-progress on a new push to the same ref. Five jobs, **none signed**:

1. `swift-build` — `xcode-select 16.0`, `brew install xcodegen`, `xcodegen generate`, `xcodebuild build` Debug with codesigning disabled.
2. `swift-test` — `needs: swift-build`; same setup; `xcodebuild test`.
3. `swift-lint` — `swiftlint --strict` and `swift-format lint --recursive --strict Sources Tests`.
4. `daemon-test` — `actions/setup-python@v5` with 3.13, `pip install -e daemon[dev]`, `pytest daemon/tests -q`.
5. `dist-scripts` — runs `bash dist/tests/test_scripts.sh` (the 16-assertion smoke test from `dist/tests/test_scripts.sh`). Tolerates the test script being absent.

**What CI does not run:** signing, notarization, DMG creation, Sparkle signing, tap bumps, anything that touches GH releases. All of that is `release.yml`-only.

---

## 14. Source Tree (ops scope only)

```
dist/                                Release shell scripts (sourced by release.yml)
├── _lib.sh                          Shared helpers: log/ok/warn/die, require_env,
│                                    require_cmd, parse_common_args (--dry-run / --help),
│                                    run (eval-or-print), repo_root, version_from_tag.
├── build.sh                         xcodegen generate → xcodebuild archive (universal,
│                                    code-sign-disabled) → cp .app to dist/export/.
├── sign.sh                          Sparkle-aware bottom-up codesign of nested helpers,
│                                    then generic depth-first sign of other bundles, then
│                                    main .app last with --entitlements. --options runtime
│                                    + --timestamp throughout.
├── notarize.sh                      ditto-zip .app, notarytool submit --wait,
│                                    stapler staple + validate. .dmg/.pkg submitted as-is.
├── dmg.sh                           create-dmg (preferred) or hdiutil fallback. Outputs
│                                    dist/out/Myna-$VERSION.dmg.
├── appcast.sh                       Sign DMG with Sparkle EdDSA (sign_update or openssl
│                                    fallback, LibreSSL rejected), append <item> to
│                                    appcast.xml (Python-mediated de-dupe + prepend).
└── tests/
    └── test_scripts.sh              16-assertion smoke test: bash -n parse, shellcheck
                                     (best-effort), --help non-empty, --dry-run exit 0.

tap/                                 Source-of-truth for the Homebrew tap; mirrored to
│                                    PrerakGada/homebrew-tap by release.yml tap-bump.
├── Casks/
│   └── myna.rb                      cask "myna": Myna.app from GH DMG; depends on
│                                    formula myna-daemon; auto_updates true (Sparkle).
├── Formula/
│   └── myna-daemon.rb               Python daemon via Homebrew Virtualenv. 40 PyPI
│                                    resource blocks; depends_on python@3.13 + rust:build.
│                                    Service block for `brew services start`.
└── README.md                        Tap-end-user install/upgrade/uninstall guide.

.github/workflows/
├── ci.yml                           Per-PR build/test/lint matrix (5 jobs).
├── release.yml                      9-job tag-triggered release pipeline.
└── appcast.yml                      Manual appcast-rebuild fallback (workflow_dispatch).

launchagents/
├── dev.myna.engine.plist.template   mlx-audio Kokoro server on :8765 (KeepAlive).
└── dev.myna.daemon.plist.template   Python `myna` daemon on :8766 (KeepAlive).

hooks/
└── myna-cc-announce.py              Claude Code Stop hook → POST /announce.

cli/
└── myna                             27-line bash wrapper → POST /speak.

hammerspoon/
└── myna.lua                         v1 menu-bar + hotkey driver. Preserved alongside the
                                     Swift app; last hotkey registration wins.

install.sh                           One-shot local dev installer (idempotent).

(Cross-reference root docs — not duplicated here)
RELEASE.md                           Operator manual (one-time setup + per-release + rollback + manual fallback).
HANDOFF.md                           v0.1.0 ship state + the 10-iteration sign saga writeup.
STATUS.md                            Overnight-build narrative + 🟡 follow-up backlog.
SECURITY.md                          Threat model + vulnerability reporting contact.
README.md                            User-facing project intro (install, hotkeys, CLI).
```

---

## 15. Known gaps / debt

| Where | Issue | Source |
|---|---|---|
| `dist/_lib.sh:21`–`28` | Comment notes `${!name}` requires bash 4+; uses `eval` fallback for bash 3.2 portability. Real concern: any future contributor adding `mapfile`/`readarray` to dist/ will break CI silently when the local-only macOS bash 3.2 runs it. | `STATUS.md:181`, commit `f996347` |
| `tap/Formula/myna-daemon.rb:303` | `brew test myna-daemon` asserts `"usage"` in `myna-daemon --help`, but the daemon has no argparse. `brew test` will fail. | `STATUS.md:182`, `HANDOFF.md:67` |
| `tap/Formula/myna-daemon.rb` (source) | Source formula in this repo lacks the 40 resource blocks + `depends_on "rust" => :build` present in the deployed tap. Re-bootstrapping from this source would ship a broken formula. | `HANDOFF.md:74`–`77` |
| `tap/Formula/myna-daemon.rb` install vs `daemon/myna/config.py` | Formula writes `keybindings.json` to `etc/myna/`; the daemon hardcodes `~/.config/myna` and ignores `MYNA_CONFIG_DIR`. The two never meet. | `STATUS.md:183`, `HANDOFF.md:68` |
| `release.yml:328`–`339` | Appcast fetch swallows **all** non-success exits (`|| echo "no existing appcast …"`), not just 404. An auth glitch silently rewrites the appcast from scratch. | `STATUS.md:184`, `HANDOFF.md:69` |
| `dist/notarize.sh` | On `Invalid` / `Rejected` status, never auto-fetches `xcrun notarytool log <submission-id>`. Iteration 10 of v0.1.0 required manually pasting Apple ID + app-password to get the log. A 5-line patch (capture id from `notarytool submit`, on non-Accepted run `notarytool log $id`) would self-diagnose. | `HANDOFF.md:76` |
| `dist/dmg.sh:62`–`63` | `dist/dmg-background.png` not in repo → DMG works but install window has no branding. | `STATUS.md:131`, `HANDOFF.md:71` |
| `cli/myna` | No error handling on curl failure — silent fire-and-forget. Acceptable, but a `--verbose` flag would help debug "myna said nothing". | Observation |
| `hooks/myna-cc-announce.py:75`–`78` | Hard-coded 1.5-second `urlopen` timeout. If the daemon ever blocks on `/announce` (e.g. during long synthesize), the hook silently drops the announcement and Claude turns will go un-announced with no signal in `~/Library/Logs/`. Worth logging to stderr on failure. | Observation |

### Risk: source formula divergence

Concretely: `tap-bump` job (`release.yml:480`–`499`) only `cp source/tap/Formula/myna-daemon.rb` if the deployed file is **missing**. On any existing deployed formula it only sed-edits `url` and `sha256`. So today's deployed formula is safe forever (until someone deletes it). But:

- A new owner forking this repo and running their first `tap-bump` against a fresh tap repo will get this repo's incomplete formula deployed verbatim, and `brew install --cask myna` will ImportError on the daemon.
- The honest fix is to port the 40 resource blocks + `depends_on "rust" => :build` from the deployed tap into `tap/Formula/myna-daemon.rb` here. Tracked.

---

## 16. Risks & Open Questions (premortem)

### What if Apple revokes the Developer ID cert?

- Every installed copy of Myna fails Gatekeeper on next launch (`spctl --assess` rejects). Users see "Myna can't be opened because it is from an unidentified developer."
- Sparkle updates also fail because the new DMG's signature chains to the revoked cert.
- **Recovery:** apply for a new cert ($99/yr renewal usually preempts this), re-generate p12, update `APPLE_DEVELOPER_ID_*` secrets, ship a new release. Users must download the new DMG manually (Sparkle's stored cert pinning will reject).
- **Mitigation:** keep the cert renewed; set a calendar reminder 30 days before expiry.

### What if GitHub Actions macos-14/15 image drops Xcode 16?

- `XCODE_VERSION: "16.0"` is hard-pinned in `release.yml:42` and `ci.yml:20`.
- The `sudo xcode-select -s /Applications/Xcode_16.0.app || true` pattern (tolerant of missing) means the build silently falls through to the runner's default Xcode, which could be a different version producing different Sealed Resources V2 hashes.
- **Mitigation:** make the xcode-select step `set -e`-strict (drop `|| true`) so the job fails loud if 16.0 is gone. Bump pinned version deliberately.

### What if the Sparkle private key leaks?

- An attacker can sign a malicious appcast item; every Myna install will accept the corresponding malicious DMG as an update.
- **Recovery (cite `RELEASE.md:58`–`62`):** ship a new minor version with a new public key. Every existing user has to download the new build manually once (Sparkle of the old version will refuse the new public key). Document this in release notes.
- **Mitigation:** key lives only in GH secret + 1Password. `dist/sparkle_private_key.NEVER_COMMIT.txt` is git-ignored. There's no copy on a contributor's laptop. STATUS.md notes that during the overnight build the key was rotated once after audit caught a leak (`STATUS.md:228`).

### What if a future `release.yml` change accidentally publishes an unsigned binary?

- Today the workflow is sequential: `release` job requires `sign-dmg` (which calls `notarize.sh` — fails if Apple rejects). An unsigned DMG cannot pass `notarize.sh`.
- But a refactor that, say, parallelizes `sign-dmg` and `appcast` and uses `gh release create` from an earlier job could theoretically upload an unsigned artifact.
- **Mitigation:** keep `release` strictly `needs: [preflight, sign-dmg, appcast]`. Add a pre-release `codesign --verify --deep --strict` gate inside the `release` job for belt-and-braces.

### What if the GitHub-generated source tarball never materializes?

- `tap-bump` retries up to 5× with `sleep 5` (`release.yml:489`–`492`). GitHub usually generates within seconds; 99% of the time the first attempt wins.
- If all 5 fail, the `set -euo pipefail` at the top of the step kills the job, leaving the cask updated but the formula's `sha256` stale → `brew install myna-daemon` on the next user will fail with a sha256 mismatch.
- **Mitigation:** the curl retries already cover the common case. A longer-term fix would be to invert the order (compute formula sha256 first, fail the whole release if missing, then publish).

### What if a user's pre-existing `~/.claude/settings.json` is malformed?

- `install.sh:43`–`61` does `json.loads(p.read_text())` which raises on malformed JSON, killing `install.sh` mid-flight with a Python traceback. The LaunchAgent install step (later) never runs.
- **Mitigation:** wrap the JSON read in a `try/except`, fall back to `{}` with a clear warning to the user. Idempotency requirement is satisfied today, robustness on bad inputs is not.

### What if Hammerspoon and the Swift app both register the same hotkey?

- Last registration wins, but the loser silently fails to respond, with no UI indication. User confusion guaranteed.
- **Mitigation:** the README should say "pick one surface, uninstall the other". The Swift app could detect a Hammerspoon binding via `hs -c` and warn at first launch.
