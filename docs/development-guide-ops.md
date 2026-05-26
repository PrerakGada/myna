# Myna — Operations Development Guide

For contributors editing the release pipeline, shell scripts, tap, LaunchAgents, hooks, or the `install.sh` flow. Application-side dev guides live alongside `apps/macos/` and `daemon/`. This file is the ops-side counterpart.

---

## 1. Prerequisites

### Local

| Tool | Purpose | Install |
|---|---|---|
| `bash` 3.2+ | dist/*.sh shebang is `#!/usr/bin/env bash` and CI runs them under macOS-default bash 3.2 — **all scripts must stay bash-3-portable** (no `mapfile`/`readarray`, no `${!var}`, no `${var,,}`). | shipped with macOS |
| `shellcheck` | Lint shell scripts; best-effort in `test_scripts.sh` (`dist/tests/test_scripts.sh:55`). | `brew install shellcheck` |
| `brew` | Tap install/uninstall + style audits. | <https://brew.sh> |
| `gh` | All release operator commands (`gh run watch`, `gh release create`, `gh secret list`). | `brew install gh` |
| `xcodegen` | Regenerate `apps/macos/Myna.xcodeproj` from `project.yml` before `xcodebuild`. | `brew install xcodegen` |
| Xcode 16.0 | Pinned in workflows; bumping requires editing `XCODE_VERSION` in both `ci.yml` and `release.yml`. | App Store |
| Python 3.13 | Daemon dev installs + the heredoc in `dist/appcast.sh:134` (PKCS#8 PEM build) + the JSON-merge in `install.sh:43`. | `brew install python@3.13` |

### Remote

All eight mandatory GitHub Actions secrets must be set before `release.yml` will succeed (see `architecture-ops.md §12` for the full table). Verify with `gh secret list --repo PrerakGada/myna`. The optional `TAP_DEPLOY_KEY` plus the deployed tap repo are needed for `tap-bump` to do anything; without it, the rest of the release still ships (`release.yml:87`–`102`).

---

## 2. Local dry-run all scripts

```bash
bash dist/tests/test_scripts.sh
```

Expected: **16 pass / 0 fail** (output ends with `==> 16 pass, 0 fail — OK`). The test covers:

- `bash -n` parse of every script + `_lib.sh`.
- shellcheck per script (warning-only — skipped if `shellcheck` not installed).
- `--help` exits 0 and prints non-empty for each script (asserts the auto-generated help block works).
- `--dry-run` exits 0 for each script without touching Apple infrastructure.

Stub credentials are injected (`test_scripts.sh:22`–`30`) so `require_env` checks pass even in dry-run mode. The Sparkle private key used here is a throwaway and does NOT correspond to the production `SUPublicEDKey` — rotating it has no impact on shipped updates (cited in the file comment).

The `ci.yml` `dist-scripts` job runs this on every push/PR to `main`/`native-app-rebuild`.

---

## 3. Editing `release.yml`

### Validation

```bash
# YAML syntax + structure
python3 -c "import yaml, glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml')]"

# act-style local simulation (limited — Actions-specific contexts are stubbed)
# brew install act, then:
act -W .github/workflows/release.yml -j preflight --container-architecture linux/amd64 --dryrun
# Note: macos-15 runners can't be simulated locally — act falls back to ubuntu.
# Only useful for testing the YAML shape, not the actual macOS-specific steps.

# Tag a test release on a throwaway tag to verify end-to-end on the real runner
# (your safest validation — costs Apple notarization but proves the pipeline)
git tag v0.0.1-test && git push origin v0.0.1-test
gh run watch
# Then clean up:
gh release delete v0.0.1-test --yes
git push --delete origin v0.0.1-test
git tag -d v0.0.1-test
```

### The tar-between-jobs invariant — **DO NOT REMOVE**

Every job that hands a `.app` to a downstream job MUST tar it first, and every downstream job MUST untar before use. See `release.yml:118`–`134` for the canonical comment block, and `HANDOFF.md:34`–`44` for the 10-iteration debugging saga that established this invariant.

The reason in one line: `actions/upload-artifact@v4` zips with a Linux-style zip that flattens macOS symlinks (breaking Sparkle.framework's versioned layout) and strips xattrs (invalidating Sealed Resources V2 signatures). Tar preserves both verbatim.

If you ever need to add a new job that consumes the .app, replicate the pattern:

```yaml
# producer job
- name: Tar .app for transport
  run: tar -cf myna-app-<stage>.tar -C dist/export Myna.app
- name: Upload .app
  uses: actions/upload-artifact@v4
  with:
    name: myna-app-<stage>
    path: myna-app-<stage>.tar
    if-no-files-found: error
```

```yaml
# consumer job
- name: Download .app tarball
  uses: actions/download-artifact@v4
  with:
    name: myna-app-<stage>
- name: Extract .app
  run: |
    mkdir -p dist/export
    tar -xf myna-app-<stage>.tar -C dist/export
```

### Artifact upload matrix

Audit every `actions/upload-artifact` call before merging — they're load-bearing:

| Artifact name | Producer job | Consumer job(s) | Retention | Format |
|---|---|---|---|---|
| `myna-app-unsigned` | `build-universal` | `sign` | 7d | tar |
| `myna-app-signed` | `sign` | `notarize` | 7d | tar |
| `myna-app-stapled` | `notarize` | `dmg` | 7d | tar |
| `myna-dmg-unsigned` | `dmg` | `sign-dmg` | 7d | raw .dmg |
| `myna-dmg` | `sign-dmg` | `appcast`, `release` | 30d | raw .dmg |
| `appcast` | `appcast` | `release` | 30d | raw `appcast.xml` |

`if-no-files-found: error` on every one — a missing artifact is a hard fail, not a silent empty download.

---

## 4. Editing `dist/sign.sh`

### Sparkle bottom-up signing rules (`sign.sh:50`–`164`)

Sparkle 2 ships a **versioned** framework. Apple's framework spec says the root of a versioned framework may contain **only** `Versions/` plus symlink aliases (`Sparkle`, `Headers`, `Modules`, `Resources`, `Updater.app`, `XPCServices`, and — empirically — `Autoupdate`). Anything else triggers `"bundle format is ambiguous"` or `"unsealed contents present"` from codesign.

Sign in this exact order:

1. **Normalize**: restore `Versions/Current → B` symlink, restore each alias-at-root symlink, drop any stale root `_CodeSignature/`.
2. **Bottom-up sign inside `Versions/<current>`**: `Autoupdate` binary, `Updater.app/Contents/MacOS/Autoupdate`, `XPCServices/Downloader.xpc`, `XPCServices/Installer.xpc`, `Updater.app`, then `Versions/<current>` itself.
3. **Sign the framework root**.
4. **Then** the generic find-loop for everything else (excluding `*/Sparkle.framework*` from the find).
5. **Then** the main `.app` last with `--entitlements`.

### What NOT to touch

- The **symlink-normalize block** (`sign.sh:94`–`130`) is defensive code. The `tar`-between-jobs fix in `release.yml` made it strictly redundant in the current CI flow, but it still catches anything Xcode itself flattens during embed-and-sign in any future change. **Leave it.**
- The **`while IFS= read -r t` loop** (`sign.sh:176`–`182`) replaced `mapfile` because macOS runners ship bash 3.2 (commit `f996347`). Don't switch back to `mapfile`/`readarray`.
- The **`-type d` filter on `find`** (`sign.sh:181`) skips files — important because Sparkle's symlinks would otherwise be visited as filesystem entries and double-signed (commit `ff029b6`).
- The **`awk '{ print length, $0 }' | sort -rn`** trick (`sign.sh:182`) sorts paths by length descending = deepest-first, so nested bundles are signed before their containers.

### Adding a new nested bundle type

If a future dep ships a `.dext` or `.systemextension`, extend the find pattern at `sign.sh:180`–`182`:

```bash
\( -name '*.framework' -o -name '*.bundle' -o -name '*.xpc' -o -name '*.app' -o -name '*.dext' \) \
```

### Verifying a local sign result

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Prerak Gada (RC63N3VU27)"
bash dist/build.sh
bash dist/sign.sh
codesign --verify --deep --strict --verbose=2 dist/export/Myna.app
spctl --assess --type execute --verbose=2 dist/export/Myna.app   # accepted means Gatekeeper-clean
```

---

## 5. Editing `dist/notarize.sh`

### Recommended patch: auto-fetch notary log on rejection

Per `HANDOFF.md:76` and `STATUS.md` follow-ups, iteration 10 of v0.1.0 required manually pasting Apple ID + app-password to fetch the notary log when `notarytool submit` returned `Invalid`. A ~5-line patch would self-diagnose:

Current shape (`notarize.sh:57`–`62`):

```bash
run "xcrun notarytool submit '$submit_path' \
       --apple-id \"\$APPLE_ID\" \
       --team-id \"\$APPLE_TEAM_ID\" \
       --password \"\$APPLE_ID_APP_PASSWORD\" \
       --wait \
       --timeout 30m"
```

Proposed:

```bash
submit_out=$(mktemp)
if ! xcrun notarytool submit "$submit_path" \
       --apple-id "$APPLE_ID" \
       --team-id "$APPLE_TEAM_ID" \
       --password "$APPLE_ID_APP_PASSWORD" \
       --wait --timeout 30m \
       --output-format plist > "$submit_out"; then
  sub_id=$(/usr/libexec/PlistBuddy -c 'Print :id' "$submit_out" 2>/dev/null || true)
  if [ -n "$sub_id" ]; then
    warn "notarization rejected; fetching log for submission $sub_id"
    xcrun notarytool log "$sub_id" \
      --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_ID_APP_PASSWORD" >&2 || true
  fi
  die "notarization failed (see log above)"
fi
```

Test it with a deliberately bad signature (e.g. flip a bit in the .app binary with `dd`, then re-run notarize) to confirm the log appears in the job output before merging.

### What not to change

- `--wait --timeout 30m` — Apple's notary queue can take 20+ minutes during peak hours. Dropping `--wait` and polling separately would shave runtime when the queue is short but complicates the script substantially; not worth it.
- `ditto -c -k --keepParent` for `.app` zipping — `zip -r` strips xattrs (same root cause as the upload-artifact bug). `ditto` preserves them.

---

## 6. Editing the tap

### Local tap workflow

```bash
# Bootstrap (one-time)
gh repo create PrerakGada/homebrew-tap --public
git clone git@github.com:PrerakGada/homebrew-tap.git ~/Developer/homebrew-tap
cp -R tap/Casks tap/Formula ~/Developer/homebrew-tap/
cd ~/Developer/homebrew-tap && git add -A && git commit -m 'initial' && git push

# Per-edit
cd ~/Developer/homebrew-tap
# … edit Casks/myna.rb or Formula/myna-daemon.rb …
brew style Casks/myna.rb        # required before commit
brew style Formula/myna-daemon.rb
brew install --cask --force ./Casks/myna.rb   # local install test
git commit -am "myna: <change>" && git push
```

The `brew style` audit must be clean — `release.yml`'s `tap-bump` job blindly seds and commits, so style violations land in `main`.

### Cask vs formula split rationale (recap)

- **Cask** = pre-built signed `.app` from GH Releases. Fast install. Sparkle owns updates (`auto_updates true`).
- **Formula** = Python daemon installed via Homebrew's `Virtualenv`. Slow first-install (Rust+sdist compile), bottle-cached after.

Splitting means a user who already has the daemon running (via a different install path) can `brew install --cask myna` without pulling Python. The cask's `depends_on formula: "myna-daemon"` ensures the canonical path Just Works for a clean Mac.

---

## 7. Adding a new daemon dependency

**Critical:** the **deployed** tap (`PrerakGada/homebrew-tap/Formula/myna-daemon.rb`) holds the resource blocks; the **source-of-truth in this repo** (`tap/Formula/myna-daemon.rb`) currently lacks them per `HANDOFF.md:74`–`77`. Reconcile before v0.2 ships — until you do, every dep addition requires both files to be edited.

### Step 1 — regenerate resource blocks

```bash
# In the deployed tap repo, regenerate the 40+ resource blocks.
# The /tmp/gen-resources.py script (referenced in HANDOFF.md:52) queries the
# PyPI JSON API for sdist URL + sha256 for every dep + transitive dep.
# It does not live in this repo; rebuild it from the pattern below:

cat > /tmp/gen-resources.py <<'PY'
import json, urllib.request, sys
# Read the resolved deps (e.g. from pip-compile or `pip install --report -`)
# and emit Ruby resource blocks.
def fetch(pkg, ver):
    r = json.load(urllib.request.urlopen(f"https://pypi.org/pypi/{pkg}/{ver}/json"))
    sdist = [f for f in r["urls"] if f["packagetype"] == "sdist"][0]
    print(f'  resource "{pkg}" do')
    print(f'    url "{sdist["url"]}"')
    print(f'    sha256 "{sdist["digests"]["sha256"]}"')
    print(f'  end\n')

for pkg, ver in [(line.split("==")[0], line.split("==")[1])
                 for line in sys.stdin if "==" in line]:
    fetch(pkg, ver)
PY

# Resolve the full dep tree (in the daemon's venv):
~/.venvs/myna/bin/pip install -e ~/Developer/myna/daemon
~/.venvs/myna/bin/pip freeze | python3 /tmp/gen-resources.py > /tmp/resources.rb

# Paste the contents of /tmp/resources.rb between `depends_on "rust"` and
# `def install` in BOTH:
#   tap/Formula/myna-daemon.rb (this repo)
#   ~/Developer/homebrew-tap/Formula/myna-daemon.rb (deployed)
```

### Step 2 — add the build dep if needed

If the new dep is a Rust extension (anything that uses `maturin` or `setuptools-rust`), `depends_on "rust" => :build` is already in place. For C extensions, no extra dep is usually needed (Xcode CLT is preinstalled on the runner).

### Step 3 — verify locally

```bash
# Local install test
cd ~/Developer/homebrew-tap
brew install --build-from-source ./Formula/myna-daemon.rb
brew test myna-daemon   # will fail today on the argparse assertion — see STATUS.md:182
```

### Step 4 — bump and ship

The `tap-bump` job will sed-update `url` + `sha256` automatically when you tag the next release; it does **not** regenerate resource blocks, so step 1 must be done by hand and committed to the deployed tap **before** tagging the release.

---

## 8. Editing the Hammerspoon module

### Workflow

```bash
# Edit hammerspoon/myna.lua, then sync the live one:
cp hammerspoon/myna.lua ~/.hammerspoon/myna.lua

# Reload Hammerspoon (faster than the menu item):
hs -c "hs.reload()"          # requires hs.ipc to be enabled — myna.lua does this at startup

# Tail Hammerspoon's console for errors:
osascript -e 'tell application "Hammerspoon" to activate'
# Then: Hammerspoon menu → Console
```

### Logging

`hs.alert.show("Myna: …")` for user-visible debug. `print(...)` lands in the Hammerspoon Console. For sticky errors, use `hs.notify.new({title="Myna", informativeText=msg}):send()`.

### Hotkey conflict diagnosis

If a chord stops responding:

```bash
# Quit Hammerspoon entirely
osascript -e 'tell application "Hammerspoon" to quit'

# Is the Swift app also running?
ps aux | grep -i myna.app

# If both ran simultaneously, the last-registered binding wins — usually whichever
# launched second. Quit the other and reload Hammerspoon.
```

The `loadBindings()` function (`myna.lua:151`) reads `~/.config/myna/keybindings.json`. Delete it to reset to `DEFAULT_BINDINGS` (`myna.lua:143`–`149`).

---

## 9. Editing the CC hook (`hooks/myna-cc-announce.py`)

### Testing without a real Claude Code session

The hook reads JSON from stdin matching Claude Code's Stop event shape. Synthesize one:

```bash
# Create a minimal fake transcript
mkdir -p /tmp/myna-hook-test
cat > /tmp/myna-hook-test/transcript.jsonl <<'JSONL'
{"type":"user","message":{"role":"user","content":"hello"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"This is the last assistant turn that should be announced to Myna."}]}}
JSONL

# Pipe a synthetic Stop event into the hook
echo '{
  "transcript_path": "/tmp/myna-hook-test/transcript.jsonl",
  "session_id": "test-session-123",
  "cwd": "/Users/nimbus/Developer/myna"
}' | python3 hooks/myna-cc-announce.py

# Verify it landed in the daemon
curl -s http://127.0.0.1:8766/registry | python3 -m json.tool
# Expect the announcement with label="myna" and the assistant text
```

### Adding a new event type

If you ever add a hook for `PreToolUse`, `PostToolUse`, etc.:

- Mirror the silent-failure pattern — never `raise` or `print` to stderr in a way that disrupts the Claude session.
- Keep the urlopen timeout small (1.5s today). Claude blocks on Stop hooks, so a slow hook is a slow session.
- Update `install.sh:43`–`61` to register the new hook idempotently under the right `hooks.<event>` key.

---

## 10. Editing LaunchAgents

### Reload cycle

```bash
# After editing launchagents/dev.myna.daemon.plist.template:
sed "s|__HOME__|$HOME|g" \
  ~/Developer/myna/launchagents/dev.myna.daemon.plist.template \
  > ~/Library/LaunchAgents/dev.myna.daemon.plist

launchctl unload ~/Library/LaunchAgents/dev.myna.daemon.plist 2>/dev/null || true
launchctl load   ~/Library/LaunchAgents/dev.myna.daemon.plist

# Confirm it's loaded and running
launchctl list | grep dev.myna
```

### Log inspection

```bash
# Daemon
tail -f ~/Library/Logs/myna-daemon.log

# Engine
tail -f ~/Library/Logs/myna-engine.log

# launchd's own log (look for "Service exited with abnormal code" etc.)
log show --predicate 'subsystem == "com.apple.xpc.launchd"' --info --last 5m \
  | grep -i myna
```

### Common edits

- **Change port**: edit the plist's `ProgramArguments` (engine: `--port 8765`; daemon picks up `MYNA_PORT` env). Update `cli/myna`, `hooks/myna-cc-announce.py`, `hammerspoon/myna.lua`, and `daemon/myna/config.py` in lockstep — they all hardcode the default.
- **Change Python**: edit `ProgramArguments[0]` (`~/.venvs/myna/bin/python` → wherever). Recreate the venv with the new interpreter first or the agent will respawn-loop.
- **Add env var**: insert an `<key>EnvironmentVariables</key><dict>…</dict>` block. Don't forget to reload.

---

## 11. Editing `install.sh`

### Idempotency requirement

**Every step must be safe to re-run.** Users will run `./install.sh` after every `git pull`. The current implementation gets this right (worth preserving):

- `[ -d "$HOME/.venvs/myna" ] || python3.13 -m venv ...` (venv creation)
- `ln -sf` (symlink force-overwrites without erroring on existing)
- `[ -f "$HOME/.config/myna/keybindings.json" ] || cat > ...` (config writes only if absent)
- `grep -q 'require("myna")' ... || echo ...` (init.lua append-once)
- `launchctl unload ... 2>/dev/null || true; launchctl load ...` (suppresses not-loaded error)

### The JSON-merge pattern for `~/.claude/settings.json`

`install.sh:43`–`61` is the canonical pattern for merging a hook entry into a JSON file you don't own. It:

1. Reads the file (`{}` if absent).
2. Sets up `data["hooks"]["Stop"]` as a list (using `setdefault`).
3. Walks every existing entry checking `h.get("command") == cmd`.
4. Appends only if not already present.
5. `mkdir -p` the parent (in case `~/.claude` doesn't exist yet).
6. Writes back with `indent=2` (preserves human-edited formatting reasonably).

If you ever extend `install.sh` to write to other JSON config files (e.g. `~/.config/myna/config.json` for a new opt-in feature), copy this exact pattern — don't roll a new one.

### Gotcha: malformed user JSON

`json.loads(p.read_text())` raises on malformed JSON, killing `install.sh` mid-flight with a Python traceback. The LaunchAgent step (later) never runs. A future hardening pass should wrap the read in `try/except json.JSONDecodeError: data = {}` with a clear warning. Tracked in `architecture-ops.md §15`.

### Testing

```bash
# Clean room: simulate first-install on a fresh user
rm -rf ~/.venvs/myna ~/.config/myna/keybindings.json
launchctl unload ~/Library/LaunchAgents/dev.myna.{daemon,engine}.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/dev.myna.{daemon,engine}.plist
./install.sh

# Re-install: must be a no-op for everything except 'pip install -e' which
# always re-syncs the editable install.
./install.sh

# Confirm everything is wired
curl -s http://127.0.0.1:8766/v2/health
launchctl list | grep dev.myna
which myna
ls ~/.hammerspoon/myna.lua
python3 -c "import json; print(json.load(open('$HOME/.claude/settings.json'))['hooks']['Stop'])"
```
