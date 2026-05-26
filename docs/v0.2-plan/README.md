# Myna v0.2 — planning artifacts (from BMad party-mode session, 2026-05-26)

> **What this is:** a brain-dump of ideas, specs, copy, and visual direction produced across a multi-round BMad party-mode discussion shortly after v0.1.0 shipped. Saved here so the work isn't lost.
>
> **What this is NOT:** the implementation plan. The discussion assumed a Hammerspoon-based v1 architecture in many places — the actual codebase is the native Swift app at `apps/macos/`. Treat these docs as raw material, not a sprint backlog.

## Reality check — what applies, what doesn't

| Doc | Status | Notes |
|---|---|---|
| [01-feature-stories.md](01-feature-stories.md) | ⚠️ Re-target | Amelia's stories S06–S16. File paths assume Hammerspoon; ACs & test plans are still good feature requirements. Re-map to `apps/macos/Sources/` for the menu bar / settings / cinematic / toast UI. |
| [02-karaoke-architecture.md](02-karaoke-architecture.md) | ✅ Applies | Winston's Swift sidecar architecture — fits cleanly as a new target alongside `apps/macos/`. |
| [03-ux-direction.md](03-ux-direction.md) | ✅ Applies (scenes, not impl) | Sally's UX direction. The *moments* and *failure modes* are stack-agnostic. Drop her Hammerspoon-specific implementation notes. |
| [04-visual-direction.md](04-visual-direction.md) | ✅ Applies | Caravaggio's GIF storyboards, project-dot palette, icon direction, hero composition, recording specs — all stack-agnostic. |
| [05-launch-narrative.md](05-launch-narrative.md) | ✅ Applies | Sophia's LinkedIn / Twitter / Product Hunt copy + pre-PH teaser cadence. Ship-ready drafts. |
| [06-category-naming.md](06-category-naming.md) | ✅ Decide | Mary picks "Selective Listening" (small, safe). Victor picks "Ambient Agent Audio" (bold, expandable). Open question. |
| [07-roundtable-discussions.md](07-roundtable-discussions.md) | 📚 Reference | Round 1 brainstorm (Carson wild ideas, John cold-water) + John's later cold-water cut on the sprint. |

## Quick takeaways

- **Hero feature for v0.2 announcement:** CC-hook ready toast (the wedge — Speechify can't build it).
- **Hero feature for Product Hunt v0.3:** karaoke subtitle ribbon (universal delight).
- **Tagline candidate:** "Selective listening for your Mac." or "Claude Code just learned to talk back."
- **Twitter Tweet 1 hook (Sophia's final pick):** *"Reading is the slowest part of using Claude Code. I'm not sure why we all agreed to keep doing it."*
- **Project-dot color palette:** Caravaggio specced 10 colorblind-safe hues + FNV-1a hash mod 10.
- **Karaoke timing source (Tier 1):** Option B — daemon-side estimation from char-count + audio sample count. Drift ≤200ms.
- **John's standing critique:** zero of these features are user-validated. He recommends 5 user videos before any v0.2 code. Standing advice, not blocking.

## What the actual stack is

For dev planning purposes — what exists today (post-v0.1.0):

```
myna/
├── apps/macos/Sources/          # Swift menu bar app — 40 files, 91 tests, Sparkle 2 wired
│   ├── Audio/                   # AVAudioEngine playback, seek, speed-without-pitch
│   ├── Input/                   # SelectionService, ChromeService, HotkeyManager
│   ├── Logging/                 # OSLog + file mirror
│   ├── MenuBar/                 # MenuBarController, MenuBarView, BirdIcon
│   ├── MynaApp/                 # AppDelegate, lifecycle
│   ├── Network/                 # DaemonClient, SynthesizeStream
│   ├── Settings/                # 4-tab settings UI, @AppStorage persistence
│   ├── URLScheme/               # myna:// handler
│   └── Updates/                 # Sparkle UpdateController
├── daemon/myna/                 # Python daemon — 94 tests, v1 + v2 endpoints
├── dist/                        # build/sign/notarize/dmg scripts (DO NOT TOUCH WITHOUT ASK)
├── hammerspoon/myna.lua         # v1 legacy, still works side-by-side
├── tap/                         # Homebrew tap (Casks/myna.rb + Formula/myna-daemon.rb)
└── hooks/, cli/                 # Claude Code Stop hook, `myna` CLI
```

## Re-mapping the party-mode stories to actual stack

Translation table for the dev work:

| Story | Party-mode said | Actual target |
|---|---|---|
| S06 Menu bar redesign | Hammerspoon Lua refactor | `apps/macos/Sources/MenuBar/` — the SwiftUI menu already exists; redesign the popover layout in `MenuBarView.swift` |
| S07 Thinking indicator | hammerspoon icon swap | `apps/macos/Sources/MenuBar/BirdIcon.swift` + daemon `/v2/status` state |
| S08 CC-hook ready toast | `hs.canvas` popup | NEW Swift view in `apps/macos/Sources/MenuBar/` (e.g. `CCToastWindow.swift`) + daemon `/v2/registry` endpoints |
| S09 Voice preview | hs.menubar voice rows | `apps/macos/Sources/Settings/` Voice tab + `/v2/synthesize` for short sample |
| S10 What's New dialog | `hs.webview` markdown | NEW Swift window — could reuse Sparkle's "what's new" support |
| S11 First-run cinematic | `hs.webview` overlay | NEW Swift `OnboardingWindowController` — full-screen NSWindow |
| S12 Karaoke ribbon | Swift sidecar (already Swift) | ✅ Lands as planned — new `karaoke/` SwiftPM target OR new app target inside `apps/macos/` |
| S13 Settings webview shell | `hs.webview` shell | OBSOLETE — Settings already exists in `apps/macos/Sources/Settings/` with 4 tabs |
| S14 Release prep | dist/ + nested signing | Mostly already exists in `dist/` — just need to add karaoke sidecar to the bundle |
| S15 Tier 1.5 | three variants | Same as planned |
| S16 Demo GIF pipeline | tools/ CLI | Same as planned |

**Net:** S13 mostly evaporates (Settings exists). S06 is a re-design of existing SwiftUI, not a rewrite. Everything else holds with file-path adjustments.

---

*Generated 2026-05-26 as part of the post-v0.1.0 planning session. Updated when the actual dev plan lands.*
