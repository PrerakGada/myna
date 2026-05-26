# GitHub Issue body — Windows support vote

> This is the source-of-truth for the pinned GitHub issue
> `Windows support — 👍 to vote`. If the issue body is edited on GitHub,
> reconcile it back here. Linked from `README.md`, `tap/README.md`, and
> `site/app/page.tsx`.

---

## Title

`Windows support — 👍 react to vote`

## Body

```markdown
## TL;DR

If you want Myna on Windows, **add a 👍 reaction to this issue** (the
reaction picker at the top of this post — not a comment). When this
issue reaches **100 reactions**, I commit to shipping a Windows build.

Bonus signal — leave a comment with:
- Your OS (Windows 10 / 11, ARM or x64)
- One sentence on what you'd use Myna for

That helps me build the right thing if we cross the threshold.

## Why a vote?

Myna is built by one person in spare hours. A Windows port is real
engineering — the MLX-based TTS engine needs an ONNX / DirectML rewrite,
the Hammerspoon menu bar layer has to be rebuilt in a native tray
runtime, hotkeys and accessibility-API selection-reading re-plumbed
against Win32, plus installer + code-signing + auto-update redone.
Roughly three weeks of focused work.

I'd rather build it for a community that exists than guess at one.

## The decision rule

| Reactions at 90 days | What happens |
|---|---|
| **< 30** | Close this issue. Windows is parked. |
| **30 – 99** | Extend 60 days. Re-evaluate at day 150. |
| **≥ 100** | I commit to scoping a Windows build. |

I'll post a monthly heartbeat on this issue with the current count and
whatever shipped on macOS that month.

## What "shipped" will mean (if we get there)

- A signed installer (MSI or MSIX) on the GitHub Releases page
- Feature parity with the latest macOS release: selection reading,
  hotkeys, Kokoro voices, Claude Code integration
- Same fully-local, zero-cost, MIT-licensed model
- Auto-update via the Windows equivalent of Sparkle (likely Velopack)

## What it won't be

- Not a web app. Not a cloud service. Not a paid SKU.
- Not a half-finished port — it ships when it's as good as the Mac
  version, or it doesn't ship.

## Current count

**Progress: 0 / 100.** _Last updated 2026-05-26._

— Comments welcome, but the reaction count is what moves the needle.
```

## Labels

- `platform:windows`
- `roadmap`
- `discussion`

## After creating the issue

1. **Pin it** to the repository (Issues tab → click `📌` on this issue).
2. Optionally lock the conversation to "Collaborators and contributors"
   if comment noise becomes a problem (keeps 👍 reactions open to all).
3. Add the issue number/URL into:
   - `README.md` (badge + Roadmap section)
   - `tap/README.md` (footer line)
   - `site/app/page.tsx` (hero pill + Platforms section)
4. Set a calendar reminder for the first heartbeat post: 30 days from
   issue creation.
