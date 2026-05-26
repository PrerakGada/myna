# Contributing to Myna

> Myna doesn't yet have a root-level `CONTRIBUTING.md` (gap flagged in `STATUS.md:285`). This document synthesizes the active conventions from the codebase and project rules until a canonical one lands. If anything here disagrees with `CLAUDE.md`, `CLAUDE.md` wins.

Myna is built in public, by one person in spare hours (`README.md:104`). Patches that fit the existing architecture and respect the user's "ship fast, parallel execution" working style are welcome.

---

## 1. Code style

### Swift (`apps/macos/`)

- **swift-format** — configured in `apps/macos/.swift-format`. 4-space indent, 120-char line width, `fileScopedDeclarationPrivacy` enforced, `OrderedImports`, `UseEarlyExits`. Run before commit:
  ```bash
  cd apps/macos
  swift-format format --in-place --recursive Sources Tests
  swift-format lint --recursive --strict Sources Tests
  ```
- **SwiftLint** — configured in `apps/macos/.swiftlint.yml`. Includes `Sources` + `Tests`. Notable opt-in rules: `empty_count`, `explicit_init`, `first_where`, `force_unwrapping` (flags `as!`/`!` usage — historical bug fixed in commit `9a3c389` was a `kCFBooleanTrue` force-unwrap). `--strict` in CI. Line-length warning at 140, error at 200. Body length: 80 (warning) / 150 (error).
- CI runs both with `--strict`: `.github/workflows/ci.yml:55`–`66`. Lints must be clean to merge.

### Python (`daemon/`)

- Implicit PEP 8. No automated formatter is enforced in CI today.
- Type hints encouraged on new public functions (Pydantic v2 models in `daemon/myna/v2_types.py` are the reference shape).
- `pytest` for tests under `daemon/tests/`. Keep them fast (<2s suite).

### TypeScript (`site/`)

- `tsconfig.json` with `"strict": true` enforced via `tsbuildinfo` regen on every build.
- Next.js conventions. No additional linter configured at the repo level.

### Shell (`dist/*.sh`, `install.sh`, `cli/myna`)

- **bash 3.2 portable** — macOS GitHub Actions runners ship bash 3.2; CI invokes scripts with `/usr/bin/env bash` which resolves to whatever is on `$PATH`. **Do not use**: `mapfile`, `readarray`, `${!var}`, `${var,,}`, `${var^^}`, `${arr[*]:start:len}` slicing.
- The portable patterns in use:
  - `eval "val=\${$name:-}"` instead of `${!name}` (`dist/_lib.sh:24`).
  - `while IFS= read -r t; do … done < <(find …)` instead of `mapfile -t arr < <(find …)` (`dist/sign.sh:176`–`182`, commit `f996347`).
- `set -euo pipefail` at the top of every script.
- shellcheck-clean (best-effort) — `dist/tests/test_scripts.sh` runs shellcheck with `-e SC1091,SC2086` (intentional `eval`-based `run` wrapper). New scripts should pass without new exemptions.

### Lua (`hammerspoon/myna.lua`)

- No enforced linter. Match the existing style (2-space indent, `local` everywhere, `pcall` around anything that can throw).

### Markdown

- 80-col soft wrap, fenced code blocks with explicit language tags, headings sentence-cased (matches `README.md`, `RELEASE.md`).

---

## 2. Branch policy

From `CLAUDE.md` (project rules):

> Branch policy from `~/.claude/CLAUDE.md` applies: **commit or push only when Prerak asks; if on default branch, branch first.**

In practice for outside contributors:

- Branch from `main`. Don't commit directly to `main`.
- Branch naming: `<area>/<short-desc>` (e.g. `release/auto-fetch-notary-log`, `daemon/v2-error-events`).
- Open a PR against `main`. The maintainer merges.
- For agent-assisted commits, the trailer must be:
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
  (also required by `CLAUDE.md`'s "End git commit messages with:" rule).

---

## 3. Commit conventions

Observed from `git log --oneline -20`. The pattern is:

```
<area>(<sub-area>): <imperative summary>
```

Or shorter forms (`<area>: <summary>`, `chore: <summary>`) for cross-cutting changes.

Recent examples:

| SHA | Message | Notes |
|---|---|---|
| `0bba9e9` | `chore: post-v0.1.0 cleanup — gitignore HANDOFF, reconcile tap formula` | `chore` for non-feature work |
| `f72c133` | `fix(release.yml): tar .app between jobs — preserve symlinks + xattrs` | `fix(<file>)` for targeted bug fixes |
| `63bb322` | `fix(dist/sign): symlink-restore Sparkle's root Autoupdate binary` | `<area>/<sub-area>` allowed |
| `f996347` | `fix(dist/sign): replace mapfile with while-read loop for bash 3.2 portability` | bash-portability fix explicitly cited |
| `a5dbec8` | `fix(macos/logging): Task { @MainActor in reload() } in Timer closure` | `macos/<module>` |
| `30b8140` | `feat(macos): apps/macos/dev.sh — one-command dev loop` | `feat(<area>)` for new functionality |
| `cf20847` | `feat(release): tap-bump also updates myna-daemon formula sha256` | feature on release pipeline |
| `f5860c8` | `docs: HANDOFF.md — session boundary for next-session Claude` | `docs` for doc-only changes |

Common areas: `macos`, `daemon`, `release.yml`, `dist/<script>`, `tap`, `site`, `docs`, `chore`. The `area` should match the directory or file you're primarily touching.

Use **imperative mood** (`add`, `fix`, `replace`) — not past tense (`added`, `fixed`).

The optional em-dash trailing clause (`— preserve symlinks + xattrs`) is a nice pattern when the headline is terse and you want one extra clause of context. Multi-paragraph commit bodies are fine for non-obvious fixes — the v0.1.0 sign-saga commits are good models.

---

## 4. PR process

1. **Branch off `main`** and push to your fork (external) or origin (maintainer).
2. **Open the PR against `main`**.
3. **Ensure CI green** — `.github/workflows/ci.yml` runs five jobs (Swift build/test/lint, daemon pytest, dist smoke). All must pass. Lints are `--strict`; a single SwiftLint violation blocks.
4. **Reference the area in the PR title** (same convention as commits — `fix(daemon): ...`).
5. **Link any tracked follow-up** from `STATUS.md`, `HANDOFF.md`, or `docs/v0.2-plan/` if your PR is closing one.
6. **Squash on merge** by default — maintainer's call on whether to keep individual commits.

If you're touching the release pipeline (anything under `.github/workflows/release.yml`, `dist/`, or `tap/`), run `bash dist/tests/test_scripts.sh` locally first and quote the `16 pass, 0 fail` line in the PR description.

---

## 5. Testing requirements

### Swift (`apps/macos/Tests/`)

- **All 91 tests must pass.** As of v0.1.0: 90 Lane A tests + 1 security-audit URL-scheme regression (`STATUS.md:217`).
- Run locally:
  ```bash
  cd apps/macos
  xcodegen generate
  xcodebuild test -scheme Myna -destination 'platform=macOS' \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  ```
- **New endpoints / surface area need tests.** The convention from Lane A: one XCTest file per module under `Tests/`, mirroring the `Sources/` layout. Use the shared fixtures in `docs/native-app/fixtures/*.json` where the daemon contract is involved.

### Daemon (`daemon/tests/`)

- **All 94 tests must pass.** v0.1.0: 33 v1 + 49 v2 + 12 audit-regression (`STATUS.md:219`).
- Run locally:
  ```bash
  pip install -e daemon[dev]
  pytest daemon/tests -q
  ```
- **New v2 endpoints must include `app.state.player` trip-wire tests** (the `FakePlayer` pattern from v0.2.0) to prove they don't touch v1 playback state.
- The shared fixtures under `docs/native-app/fixtures/` are loaded by both Swift and Python tests — keep them in lockstep when changing the API contract (`docs/native-app/API_CONTRACT.md`).

### Dist scripts

- `bash dist/tests/test_scripts.sh` must end with `16 pass, 0 fail — OK`.
- For new scripts in `dist/`: support `--help` and `--dry-run` (the auto-generated help block via `_lib.sh` helpers handles `--help`), source `_lib.sh` for `log`/`ok`/`warn`/`die`/`run`/`require_env`/`require_cmd`, set `set -euo pipefail`. Add the script name to the `SCRIPTS=(...)` array in the test runner.

---

## 6. Security disclosure

**Do not open a public GitHub issue for security vulnerabilities.** See `SECURITY.md` for the full policy.

- Email: **prerak@engaze.in** with subject `myna-security`. (Note: `SECURITY.md:23` currently lists `rashid@dpsca.in` — that's stale residue from an earlier laptop per `CLAUDE.md`. Use `prerak@engaze.in`.)
- Or use GitHub's private vulnerability reporting on the repo.
- Include: description, repro steps, Myna version (Menu → About), macOS version, and whether you want credit in release notes.
- Acknowledgement target: 72 hours. Fix target for high-severity: 30 days.
- Coordinated disclosure: maintainer works the fix privately, then publishes fix + CVE (when applicable) together.

The threat model — Accessibility + Automation permissions, mitigations via Developer ID + notarization + Sparkle EdDSA + GH-Actions-built artifacts — is documented in `SECURITY.md:5`–`18`.

---

## 7. The Windows-vote rule

Myna is macOS-only today (Apple Silicon). Windows support is **community-voted**: see `docs/roadmap/windows-vote-issue.md` for the canonical issue body.

### TL;DR

A pinned GitHub issue (`Windows support — 👍 react to vote`, currently `#1`) tracks demand. The decision rule:

| 👍 reactions at 90 days | Outcome |
|---|---|
| **< 30** | Close the issue. Windows is parked. |
| **30 – 99** | Extend 60 days. Re-evaluate at day 150. |
| **≥ 100** | Maintainer commits to scoping a Windows build. |

### What "shipped" would mean (if the threshold is crossed)

A signed MSI/MSIX installer on GitHub Releases, feature parity with the latest macOS release, fully-local MIT-licensed Kokoro-equivalent, auto-update via the Windows equivalent of Sparkle (likely Velopack). Three weeks of focused work — MLX TTS → ONNX/DirectML rewrite, Hammerspoon → native Win32 tray runtime, accessibility-API selection re-plumbed.

### What it won't be

Not a web app. Not a cloud service. Not a paid SKU. Not a half-finished port — it ships when it's as good as the Mac version, or it doesn't ship.

### How to influence

Add a 👍 reaction to issue #1. Optionally comment with your OS (Win10/11, ARM or x64) and one-line use case. The pinned issue is the source of truth; the body in `docs/roadmap/windows-vote-issue.md` is what's mirrored there (reconcile to source-of-truth if the GitHub copy is edited).

Until the threshold is crossed, all engineering hours go into deepening the macOS experience — voices, workflows, Claude Code integration (`README.md:124`–`126`).
