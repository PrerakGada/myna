# UX direction — Sally

> **Source:** BMad party-mode round 2, agent: Sally (UX Designer).
> **Status:** ✅ Scenes & failure modes apply. Implementation hints reference Hammerspoon — translate to SwiftUI / AppKit in `apps/macos/Sources/`.

---

## The framing scene

Prerak's at his desk, third coffee, Claude Code chewing on a refactor. The menu bar in the corner is a sad little speaker icon that opens a list that looks like a 2009 utility app. He just shipped v0.1.0 and the install flow is *gorgeous* — `brew install myna` and a DMG that signs itself. Then you click the icon and it's… a spreadsheet. That's the gap we're closing. Myna should feel like a *companion in the corner*, not a control panel.

---

## 1. Menu bar redesign — the popover

**Visual hierarchy principle.** Top = state (what is Myna doing right now). Middle = transport (what I want to do to that state). Bottom = customization. The menu reads like a sentence: *"Right now Myna is reading 'Designing Data-Intensive Apps' in Bella at 1.2×. Pause? Stop? Different voice? Settings?"*

**Menu bar icon — state-driven:**
- Idle: outlined bird glyph (monochrome, template-rendered, adapts to light/dark + accent)
- Speaking: filled bird with 3-bar equalizer overlay (animated 3-bar pulse, ~2fps)
- Thinking: bird with soft halo (see Section 4)
- Paused: bird with horizontal bar through it
- Error: bird with subtle red corner dot

**Popover structure (top to bottom):**

```
┌─────────────────────────────────────────────┐
│  ▶ Now reading                              │  ← disabled header, dim
│    "Designing Data-Intensive Applications"  │  ← truncated to ~38 chars + ellipsis
│    Bella · 1.2× · 0:42 / 3:18               │  ← greyed metadata line
├─────────────────────────────────────────────┤
│  ⏸  Pause              Space                │  ← shows current global hotkey
│  ⏹  Stop               ⌥⌘.                  │
│  ⏭  Skip ahead 15s     ⌘→                   │
│  ⏮  Skip back 15s      ⌘←                   │
├─────────────────────────────────────────────┤
│  🔊 Voice           ▸                       │  ← submenu
│  ⚡ Speed           ▸  (1.2×)               │
├─────────────────────────────────────────────┤
│  📋 Recent  ▸                               │  ← last 5 things Myna read
│  🎧 Claude Code (2) ▸                       │  ← only shown if CC audio waiting
├─────────────────────────────────────────────┤
│  ⚙  Settings…                  ⌘,           │
│  ⌨  Shortcuts…                              │
│  ──                                         │
│  About Myna                                 │
│  Quit Myna                     ⌘Q           │
└─────────────────────────────────────────────┘
```

**Idle state collapses the top.** When nothing is playing, the first three lines become a single dim row: `No audio playing` and the transport block disappears entirely.

**Voice submenu** — checkmark list, each row has voice name + sibling `▶ Preview` row. Click `▶ Preview` → samples play, menu stays open. Click voice name → selects, closes menu.

**Speed submenu** — discrete steps + "Custom…": 0.75×, 1.0×, 1.2×, 1.5×, 1.75×, 2.0×, 2.5×, 3.0×.

**Recent submenu** — last 5 reads, each shows `Bella · 2 min ago · "Designing Data-Intensive…"`. Click → re-reads from start. Quietly one of the best features.

**Claude Code submenu** — only appears when registry non-empty:

```
   ● myna-repo · 14s ago · "Tests passing, ready for review…"
   ● docs-site · 2m ago  · "I refactored the routing to…"
   ─────────────
   Play all in order
   Clear queue
```

Project-colored dot via deterministic hash → hue.

**Edge cases:**
- VoiceOver: every menu item has proper text label (emojis are prefixes, not replacements)
- Multi-display: popover anchors on click-time screen, not always primary
- Long titles: truncate at 38 chars + ellipsis; full title in tooltip
- Rapid state changes: debounce icon transitions at 150ms

---

## 2. First-run cinematic

**The technical shape.** Full-screen overlay with transparent dark backdrop, centered card ~480×340, rounded 24px, drop shadow. Audio plays from Myna's actual TTS pipeline — the cinematic *proves the product works* while it runs. If TTS fails mid-script, degrade to silent captions.

**Script (verbatim, with timing):**

> **[0:00 — fade in, bird logo pulses once]**
> **Myna (Bella, calm, slightly amused):** "Hi. I'm Myna."
>
> **[0:03 — card text fades in: "Your reading companion."]**
> **Myna:** "I read things out loud. Articles you're scrolling. Replies from Claude. Anything you've selected. All from right here on your Mac — nothing goes to the cloud."
>
> **[0:11 — small animation: cursor selecting text on fake browser, speaker icon lights]**
> **Myna:** "To do that well, I'll need three small things. I'll ask once."
>
> **[0:16 — permission #1: Accessibility]**
> **Myna:** "First — Accessibility. This lets me know what you've highlighted. I never read your screen on my own. Only when you tell me to."
>
> **[0:23 — User clicks, grants. Checkmark.]**
> **Myna:** "Thank you."
>
> **[0:28 — permission #2: Notifications]**
> **Myna:** "Second — Notifications. When Claude finishes a long task, I'll let you know audio is ready. A tiny tap on the shoulder. Nothing more."
>
> **[0:35 — User grants. Checkmark.]**
> **Myna:** "Almost there."
>
> **[0:38 — permission #3: Input Monitoring (global hotkeys)]**
> **Myna:** "Last one — keyboard shortcuts. So you can pause me from anywhere. Option-Command-Period stops me. Try it now if you'd like."
>
> **[0:46 — If user presses ⌥⌘., Myna stops, waits 1.2s, then:] "Nice. I'm back."**
> **[If not pressed, Myna continues after 4s of silence:] "I'll show you again later."**
>
> **[0:52 — final card: tiny menu bar mockup, arrow pointing up to real icon]**
> **Myna:** "I live up here. Click me anytime. Want a tour of what I can do, or shall we just start?"
>
> **[0:58 — two buttons: `Show me around` and `I've got it from here`]**

Total: ~58s if all permissions granted in flow.

**Edge cases:**
- User mutes system → detect volume==0, show full captions, persistent toggle
- User denies permission → message changes to "No problem. Some features will be off — you can enable this anytime in Settings." NEVER scold.
- User Cmd-Q's mid-cinematic → save state, next launch shows "Finish setup ▸" banner
- VoiceOver running → don't speak the script (VO will read captions); offer "Play with Myna's voice" button
- **PH screenshot moment:** the 0:11 frame is the hero shot. Build it screenshot-first.

---

## 3. Voice preview in picker

**Interaction model.** Hover-to-preview is unreliable in SwiftUI menus. Use **click**, with clear separation between *preview* and *select* rows.

**Preview behavior:**

- Click `▶ Preview Bella` → Myna says one context-aware sample sentence in that voice.
  - If something currently playing → sample is the next 8-12 words of current text in previewed voice; resumes original voice after
  - If nothing playing → rotating curated sample from ~12 lines showing prosody: *"The fog crept in on little cat feet."* / *"Two plus two is four. Four plus four is eight."* / *"Did you mean to leave the door open, or was that on purpose?"*
- During preview, `▶` becomes `◼ Stop preview`
- Clicking another voice's `▶ Preview` → previous stops instantly, new one starts
- Menu closes → any active preview stops
- Select a voice (click name row, not preview) → applies at next sentence boundary, not mid-word

**Edge cases:**
- Voice not downloaded → `↓ Download (4.2 MB)`, auto-previews when ready
- Preview during real read → current pauses, preview plays, read resumes
- Spam-clicks → debounce 300ms; queue depth 1
- VoiceOver: accessibility label "Preview Bella voice" not just "Preview"

---

## 4. "Thinking" indicator

**Three time bands:**

- **Band 1: 0-150ms** — Show nothing. Pre-attentive eye blink.
- **Band 2: 150ms-1.5s** — Icon → "Thinking" state: bird glyph with soft pulsing halo (2-step animation, 600ms cycle, ~30% opacity peak). Subtle.
- **Band 3: 1.5s-6s** — Halo continues. At 1.5s mark: single low chime, 80ms, -18dB. "Acknowledgment without interruption." Used for Ollama summarizing case.
- **Band 4: 6s+** — Halo + tiny number badge ("…" then "5s", "10s"). If >15s, icon → "stuck" state + toast: *"This is taking longer than usual. Cancel?"*

**Audio language:**
- Acknowledgment chime: 80ms, soft, low (~220Hz fundamental, sine-ish, slight reverb)
- Ready chime (audio queued, about to start): even softer, 60ms
- Error sound: NEVER macOS funk/error; deliberate neutral 120ms descending two-tone, -22dB

All tunable in Settings → Behavior → Sounds with Off option.

**Edge cases:**
- User triggers while already thinking → cancel-then-retry; brief "Restarting…" caption 400ms
- VoiceOver: tooltip "Myna is thinking" + polite `NSAccessibilityAnnouncementRequestedNotification` at 2s mark
- Background mode (fullscreen app, menu bar hidden) → audio chime is the only signal
- Screenshot moment: halo at peak pulse is great "thinking AI" hero shot

---

## 5. CC-hook "ready" toast

**Window:** borderless, transparent rounded background, ~340×80, top-right of active display (12px from edge, 8px below menu bar).

**Why top-right:**
- Visual neighborhood of Myna icon → spatial association
- Doesn't fight macOS's own bottom-right notifications
- Multi-display: appears on screen with menu bar, not primary

**Visual:**

```
┌──────────────────────────────────────┐
│  ● myna-repo            Just now  ✕  │
│  "Refactor complete. All 47 tests…"  │
│  ▶ Play  ·  Later  ·  Dismiss        │
└──────────────────────────────────────┘
```

- `●` = project-colored dot (deterministic hash → hue from palette)
- Bold project name, dim timestamp
- Preview text: first ~50 chars of summarized audio
- Three actions: Play (immediate, dismisses), Later (moves to menu-bar submenu, dismisses), Dismiss (discards audio with "—" confirmation)
- Soft slide-in from above-right over 220ms ease-out
- Acknowledgment chime fires on appear (60ms, -20dB)

**Lifetime:**
- Auto-dismisses to menu-bar submenu after 8s (NOT discarded — moved). Progress line at bottom shows timer; hovering pauses it.
- Click body (not Later/Dismiss) = Play
- ✕ = Dismiss with confirmation chip ("Audio discarded · Undo" for 4s)
- `Esc` while focused = Dismiss without discarding (= Later)

**Multi-session stacking:**
- Up to 3 toasts visible, stacked vertically, 8px gaps, newest on top
- 4th+: top toast's header morphs to `myna-repo + 2 more ready` and menu bar icon shows badge count
- Each toast has own auto-dismiss timer

**Focus stealing — CRITICAL constraint.** Toasts MUST NEVER steal keyboard focus. NSPanel with `becomesKeyOnlyIfNeeded = true` + `canBecomeKey = false`. User can ignore toast and keep typing.

**Edge cases:**
- DND / Focus mode → route to submenu silently, no toast, no chime
- Fullscreen app (menu bar hidden) → fallback `NSUserNotification` ("Myna: audio ready from myna-repo") + queue to submenu
- Same project sends 3 hooks in 30s → collapse: latest toast replaces previous with `(3)` count, "Play latest / Play all"
- VoiceOver: post `NSAccessibilityAnnouncementRequestedNotification` "Myna: myna-repo audio ready, press Control-Option-M to play"; define a global hotkey for keyboard-first users
- Display sleeps mid-toast → re-show on wake for 4s without replaying chime
- Multi-display, menu bar moved mid-session → toast follows icon
- **Screenshot moment:** stacked trio (myna-repo, docs-site, landing-redesign — 3 colored dots) over Claude Code window = PH GIF money shot

---

## Order of operations (solo dev, 48h focused weekend)

1. **Menu bar redesign (Sat AM, 4-6h).** Highest ROI per hour. Foundation everyone else builds on. Ship first.
2. **CC-hook ready toast (Sat PM, 4-5h).** Indispensable for CC users — beachhead market. Ship single-toast first, stacking is v0.2.1 polish.
3. **Thinking indicator (Sun AM, 2-3h).** Cheap, mostly state plumbing + one audio file. Polish that makes screenshots feel alive.
4. **Voice preview in picker (Sun PM, 3-4h).** Higher complexity than it looks (pause-resume-current-read logic). Feature people demo to friends.
5. **First-run cinematic (next weekend, all of it).** Most fragile; only one of the five that touches users exactly once. Ship boring infrastructure first, nail the cinematic later.

**Hidden 6th item:** ship Settings shell on day one of menu bar work, even with placeholder content. Don't ship menu items that go nowhere.
