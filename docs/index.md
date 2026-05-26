# Myna Documentation Index

**Type:** multi-part with 5 parts
**Primary Languages:** Swift 6 · Python 3.13 · TypeScript 5.7 · Bash 3.2 · Lua · Ruby
**Architecture:** Local-first menu-bar app ↔ loopback HTTP daemon ↔ local TTS engine
**Last Updated:** 2026-05-26
**Status:** v0.1.0 shipped (DMG live, `brew install --cask myna` works end-to-end — see [HANDOFF.md](https://github.com/PrerakGada/myna/blob/f5860c8/HANDOFF.md))

---

## Project Overview

Myna is an always-on, fully local text-to-speech companion for macOS
Apple Silicon. It reads selections, web articles, and Claude Code output
aloud through Kokoro (mlx-audio) — zero API cost, zero network egress
for user content. Drives from the menu bar and recordable global hotkeys.

The repo carries every layer in one tree: native Swift menu-bar app,
Python FastAPI daemon, Next.js marketing site, bash CLI, and the full
release / install / hotkey infrastructure.

For the executive summary, see [project-overview.md](./project-overview.md).

## Project Structure

This project consists of **5 distinct parts**:

### macos ([`apps/macos/`](../apps/macos/))
- **Type:** desktop · **Tech:** Swift 6 / SwiftUI + AppKit / AVAudioEngine / Sparkle 2 / KeyboardShortcuts / XcodeGen
- **Entry Point:** [`Sources/MynaApp/MynaApp.swift`](../apps/macos/Sources/MynaApp/MynaApp.swift)
- **Tests:** ~91 XCTest cases

### daemon ([`daemon/`](../daemon/))
- **Type:** backend · **Tech:** Python 3.13 / FastAPI / uvicorn / httpx / trafilatura / Pydantic
- **Entry Point:** [`daemon/myna/__main__.py`](../daemon/myna/__main__.py) (binds `127.0.0.1:8766`)
- **Tests:** 94 pytest cases

### site ([`site/`](../site/))
- **Type:** web · **Tech:** Next.js 16 (App Router) / React 19 / TypeScript / Tailwind 3.4
- **Entry Point:** [`site/app/page.tsx`](../site/app/page.tsx)
- **Tests:** none (gap)

### cli ([`cli/`](../cli/))
- **Type:** cli · **Tech:** Bash 3.2 portable
- **Entry Point:** [`cli/myna`](../cli/myna) (27 LOC wrapper around `/speak`)

### ops ([`dist/`, `tap/`, `.github/`, `launchagents/`, `hooks/`, `hammerspoon/`, `install.sh`](../))
- **Type:** infra · **Tech:** GitHub Actions / Bash / Ruby (brew) / Lua (Hammerspoon legacy) / Python (CC hook)
- **Entry Point:** [`.github/workflows/release.yml`](../.github/workflows/release.yml) on `git tag v*`
- **Tests:** [`dist/tests/test_scripts.sh`](../dist/tests/test_scripts.sh) (16/16 pass)

## Cross-Part Integration

All runtime traffic is loopback-only. The Swift app talks to the daemon
over HTTP/1.1 (mostly JSON, with multipart-streaming WAV for
`/v2/synthesize`); the daemon talks to mlx-audio Kokoro (and optionally
Ollama) over HTTP; the CLI/Hammerspoon/CC hook all hit the daemon's v1
surface. No telemetry, no third-party SDKs, no auth (single-user box).

Full integration map: [integration-architecture.md](./integration-architecture.md).

## Quick Reference

### macos
- **Stack:** Swift 6 · SwiftUI/AppKit · AVAudioEngine · Sparkle 2 · KeyboardShortcuts · XcodeGen
- **Entry:** [`MynaApp.swift`](../apps/macos/Sources/MynaApp/MynaApp.swift)
- **Pattern:** menu-bar-only app (LSUIElement=YES), strict concurrency complete, hardened runtime ON

### daemon
- **Stack:** Python 3.13 · FastAPI · uvicorn[standard] · httpx · trafilatura · Pydantic v2
- **Entry:** [`__main__.py`](../daemon/myna/__main__.py) → `127.0.0.1:8766`
- **Pattern:** single-file `app.py` routes (544 LOC); v1 + v2 surfaces side-by-side; multipart streaming `/v2/synthesize`

### site
- **Stack:** Next.js 16 App Router · React 19 · TS 5.7 · Tailwind 3.4
- **Entry:** [`site/app/page.tsx`](../site/app/page.tsx)
- **Pattern:** single page, 16 hand-rolled SVG/CSS components, no UI library, deployed on Vercel

### cli
- **Stack:** Bash 3.2 + curl + inline python3 JSON
- **Entry:** [`cli/myna`](../cli/myna)
- **Pattern:** POST `/speak` (v1); symlinked to `~/.local/bin/myna`

### ops
- **Stack:** GH Actions + bash 3.2 portable + Apple `codesign`/`notarytool` + Sparkle 2 `sign_update` + Homebrew DSL + launchd
- **Entry:** [`release.yml`](../.github/workflows/release.yml) on `git tag v*` (9 jobs)
- **Pattern:** tar .app between every job (the v0.1.0 saga fix); bottom-up Sparkle.framework signing

## Generated Documentation

### Core
- [project-overview.md](./project-overview.md) — Executive summary, tech stack, parts, integration sketch
- [source-tree-analysis.md](./source-tree-analysis.md) — Annotated directory tree, critical folders, integration table
- [integration-architecture.md](./integration-architecture.md) — Cross-part topology, sequence diagrams, failure modes, hand-off matrix
- [risks-and-premortem.md](./risks-and-premortem.md) — Advanced-elicitation pass (pre-mortem, devil's advocate, red team, first principles, stakeholder round-robin, consolidated triage)
- [project-parts.json](./project-parts.json) — Machine-readable parts manifest
- [project-scan-report.json](./project-scan-report.json) — Workflow state file

### Part-Specific Documentation

#### macos
- [architecture-macos.md](./architecture-macos.md) — 21-section deep dive (lifecycle, audio pipeline, network, hotkeys, URL scheme, Settings, Sparkle, entitlements, testing, known bugs, devil's-advocate risks)
- [component-inventory-macos.md](./component-inventory-macos.md) — Every Swift type with kind, public API surface, conforms-to, used-by, purpose
- [development-guide-macos.md](./development-guide-macos.md) — Prereqs, bootstrap, dev loop, test, lint, add-a-file/endpoint/hotkey, debugging, common pitfalls

#### daemon
- [architecture-daemon.md](./architecture-daemon.md) — Process model, module-by-module, pipelines (engine/extract/summarize/chunking/player/registry), source tree, testing, perf, security, tech debt, risks
- [api-contracts-daemon.md](./api-contracts-daemon.md) — Full v1+v2 endpoint catalog with schemas, headers, errors, curl examples, and a **spec-drift report** (9 places where API_CONTRACT.md ↔ app.py ↔ DaemonTypes.swift disagree)
- [data-models-daemon.md](./data-models-daemon.md) — Every Pydantic model + the v1 inline models + player/registry shapes + on-disk config + keybindings JSON schemas, cross-referenced to Swift counterparts
- [development-guide-daemon.md](./development-guide-daemon.md) — Install, run (foreground / LaunchAgent / brew), test patterns (FakePlayer trip-wire), add-an-endpoint walkthrough, local Kokoro stub recipe, debugging, 10 common pitfalls

#### site
- [architecture-site.md](./architecture-site.md) — Stack, routing, render strategy, component composition, full Tailwind token inventory, Vercel config, SEO/metadata, a11y, source tree, testing gap, risks
- [component-inventory-site.md](./component-inventory-site.md) — Every .tsx with file:line links, server/client classification, props, deps, used-by, reuse-score matrix
- [development-guide-site.md](./development-guide-site.md) — Prereqs through Vercel deploy, adding components/sections, copy-editing map, performance notes, common pitfalls

#### ops
- [architecture-ops.md](./architecture-ops.md) — 16-section component map (release.yml job graph, signing/notarization, Sparkle pipeline, tap split, LaunchAgents, install.sh, CLI, Hammerspoon, CC hook, secrets matrix, CI workflow, source tree, gaps, premortem)
- [deployment-guide.md](./deployment-guide.md) — Per-release operator commands, CI walkthrough, watching/verifying/hotfix/rollback flows, manual fallback link to RELEASE.md, end-user install paths, Sparkle UX, telemetry (none)
- [development-guide-ops.md](./development-guide-ops.md) — Prereqs, dry-run, release.yml editing rules (tar-between-jobs invariant + artifact matrix), sign.sh Sparkle bottom-up rules, notarize.sh notary-log auto-fetch patch sketch, tap editing, daemon-dep regeneration, Hammerspoon/CC-hook/LaunchAgent/install.sh editing patterns
- [contribution-guide.md](./contribution-guide.md) — Code style (Swift / Python / TS / shell bash-3 / Lua / Markdown), branch policy, commit conventions (with real `git log` examples), PR process, testing requirements, security disclosure, Windows-vote rule

### Optional / Cross-cutting
- [deployment-guide.md](./deployment-guide.md) — see ops section above
- [contribution-guide.md](./contribution-guide.md) — see ops section above
- [integration-architecture.md](./integration-architecture.md) — see core section above

## Existing Documentation (curated by hand, pre-this-scan)

These live outside `docs/` (in repo root) and predate this generated catalogue.

- [README.md](../README.md) — Public-facing landing copy, install, shortcuts, roadmap
- [RELEASE.md](../RELEASE.md) — Operator manual for the release pipeline (one-time setup, per-release, rollback, manual fallback)
- [SECURITY.md](../SECURITY.md) — Threat model, supported versions, disclosure email — **note: still has stale `rashid@dpsca.in`; should be updated to `prerak@engaze.in` per CLAUDE.md** (tracked in [risks-and-premortem.md § 1](./risks-and-premortem.md))
- [STATUS.md](../STATUS.md) — Overnight-build chronicle of the v0.1 native-app-rebuild (historical context for why the Swift app exists)
- [HANDOFF.md](https://github.com/PrerakGada/myna/blob/f5860c8/HANDOFF.md) — v0.1.0 ship log (gitignored — kept local; references internal CI run IDs and the 10-iteration release-pipeline saga)
- [CLAUDE.md](../CLAUDE.md) — Project instructions for Claude Code agents (user identity, repo basics, working style)
- [LICENSE](../LICENSE) — MIT

### Historical Phase-0 specs (audit trail under `docs/native-app/`)
- [docs/native-app/NATIVE_APP_PROPOSAL.md](./native-app/NATIVE_APP_PROPOSAL.md) — original architecture proposal
- [docs/native-app/API_CONTRACT.md](./native-app/API_CONTRACT.md) — canonical v1+v2 spec (cross-check against [api-contracts-daemon.md spec drift](./api-contracts-daemon.md))
- [docs/native-app/TEST_PLAN.md](./native-app/TEST_PLAN.md) — per-module test matrices the lane agents built against
- [docs/native-app/fixtures/](./native-app/fixtures/) — shared JSON fixtures between Swift XCTest and Python pytest
- [docs/native-app/audits/](./native-app/audits/) — code-review + security-review checklists and the AUDIT_REPORT.md

### Per-part READMEs (next to the code)
- [apps/macos/README.md](../apps/macos/README.md)
- [site/README.md](../site/README.md)
- [tap/README.md](../tap/README.md)

### Roadmap and forward planning
- [docs/roadmap/windows-vote-issue.md](./roadmap/windows-vote-issue.md) — source-of-truth for issue #1 body (the 100-reaction Windows-build commitment)
- [docs/v0.2-plan/](./v0.2-plan/) — forward planning

### Earlier exploratory specs
- [docs/superpowers/](./superpowers/) — earlier specs incl. the 2026-05-24 myna-design doc

## Getting Started

### End-user — install via brew
```bash
brew tap PrerakGada/tap
brew install --cask myna   # auto-installs myna-daemon + python@3.13 + rust (build dep)
open /Applications/Myna.app
```
First install ≈ 20–30 min (Python daemon compiles from source);
subsequent installs are bottle-cached.

After install, open Hammerspoon and Reload Config (if you also want the
v1 legacy hotkey path), grant Accessibility + AppleScript permissions
on first hotkey usage, and enable **Launch Hammerspoon at login** so the
24/7 surface survives reboots. Or just use the Swift app's menu-bar
controls — Hammerspoon is optional.

### Contributor — local dev
```bash
git clone https://github.com/PrerakGada/myna.git ~/Developer/myna
cd ~/Developer/myna
./install.sh

# Build & run the Swift app
cd apps/macos && bash dev.sh

# Daemon ships as an editable pip install (install.sh handles it).
# Manual run:   ~/.venvs/myna/bin/python -m myna

# Marketing site
cd site && npm install && npm run dev
```

Per-part dev workflows are in:
[development-guide-macos.md](./development-guide-macos.md),
[development-guide-daemon.md](./development-guide-daemon.md),
[development-guide-site.md](./development-guide-site.md),
[development-guide-ops.md](./development-guide-ops.md).

### Ship a release
1. Bump `MARKETING_VERSION` in [`apps/macos/project.yml`](../apps/macos/project.yml).
2. `git commit -am "release: v0.X.Y"`.
3. `git tag v0.X.Y && git push origin main --tags`.
4. `gh run watch` — the [release.yml](../.github/workflows/release.yml) 9-job pipeline finishes in 10–20 min.

Operator manual: [RELEASE.md](../RELEASE.md). Quick-reference per-release commands and rollback: [deployment-guide.md](./deployment-guide.md).

## For AI-Assisted Development

This documentation was generated by the `/bmad-document-project`
workflow specifically to enable AI agents (incl. Claude Code) to
understand and extend this codebase without re-discovering the
architecture from scratch.

**When planning new features, point your AI at the appropriate
documents:**

| Feature scope | Reference |
|---|---|
| Menu-bar UI / hotkey / Settings UI / playback / Sparkle | [architecture-macos.md](./architecture-macos.md) + [component-inventory-macos.md](./component-inventory-macos.md) |
| Daemon endpoint / extraction / summarization / chunking / Kokoro integration | [architecture-daemon.md](./architecture-daemon.md) + [api-contracts-daemon.md](./api-contracts-daemon.md) + [data-models-daemon.md](./data-models-daemon.md) |
| Full-stack feature (UI ↔ daemon) | [integration-architecture.md](./integration-architecture.md) + both architecture docs |
| Marketing site (landing copy, FAQ, new section) | [architecture-site.md](./architecture-site.md) + [component-inventory-site.md](./component-inventory-site.md) |
| Release pipeline / signing / notarization / brew tap / LaunchAgent | [architecture-ops.md](./architecture-ops.md) + [deployment-guide.md](./deployment-guide.md) |
| Risk-aware planning / architecture review / pre-mortem | [risks-and-premortem.md](./risks-and-premortem.md) |
| Adding a contributor / PR review | [contribution-guide.md](./contribution-guide.md) |

**When debugging a real issue, also load:**
- [HANDOFF.md](https://github.com/PrerakGada/myna/blob/f5860c8/HANDOFF.md) (gitignored, local-only) — for the v0.1.0
  release saga and v0.2 follow-up list.
- [STATUS.md](../STATUS.md) — for the overnight-build context.
- The relevant `development-guide-*.md` for the part you're working on.

### When changing a v2 daemon endpoint

You MUST update all of these (see [integration-architecture.md § 6](./integration-architecture.md#6-operational-hand-off-matrix) for the full hand-off matrix):
1. [`daemon/myna/v2_types.py`](../daemon/myna/v2_types.py) — Pydantic model
2. [`daemon/myna/app.py`](../daemon/myna/app.py) — handler
3. [`daemon/tests/test_v2_*.py`](../daemon/tests/) — test
4. [`apps/macos/Sources/Network/DaemonTypes.swift`](../apps/macos/Sources/Network/DaemonTypes.swift) — Codable model
5. [`apps/macos/Sources/Network/DaemonClient.swift`](../apps/macos/Sources/Network/DaemonClient.swift) — client method
6. [`apps/macos/Tests/NetworkTests/`](../apps/macos/Tests/NetworkTests/) — Swift test
7. [`docs/native-app/API_CONTRACT.md`](./native-app/API_CONTRACT.md) — canonical spec
8. [`docs/api-contracts-daemon.md`](./api-contracts-daemon.md) — endpoint catalog

### When in doubt about an architectural risk

Read [risks-and-premortem.md](./risks-and-premortem.md) first. It
captures the assumptions, threat model, and "why did we do it this
way" reasoning that took months to develop.

---

_Documentation generated by BMAD Method `document-project` workflow (exhaustive scan), 2026-05-26._
