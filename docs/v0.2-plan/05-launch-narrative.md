# Launch narrative — Sophia

> **Source:** BMad party-mode rounds 3–4, agent: Sophia (Master Storyteller).
> **Status:** ✅ Stack-agnostic. Ship-ready drafts.

---

## Tagline candidates

1. **Your machine, finally with a voice of its own.** *(poetic)*
2. **Local TTS for the AI age. Free. Forever.** *(blunt)*
3. **Myna reads your screen. Locally. From the menu bar.** *(technical)*
4. **Claude Code just learned to talk back.** *(witty — wedge angle)*
5. **The listening surface for everything your AI writes.** *(category-defining)*
6. **Press a hotkey. Hear anything.** *(demonstration)*
7. **A daemon that reads aloud. No cloud. No bill.** *(developer-honest)*
8. **Stop reading what your AI just wrote. Listen.** *(reframe)*

→ **Original ship pick: #4 "Claude Code just learned to talk back."** Most work per syllable.

---

## v0.1.0 LinkedIn post (the announcement you can ship today)

> I spent an embarrassing amount of time last month staring at Claude Code finishing tasks I'd asked it to do — and never noticing.
>
> Tab in the background. Build done. Tests passing. Me, on another monitor, oblivious for forty minutes.
>
> So I built the thing I wanted: a small daemon that lives in my menu bar and reads stuff out loud. Selected text. Web articles. The output of my AI agents when they finish.
>
> No cloud. No subscription. No "sign in with Google." It runs entirely on your Mac, using local Kokoro voices that genuinely sound like a person who's had coffee.
>
> It's called **Myna**, and v0.1.0 (alpha) shipped today.
>
> What's in this first cut:
> • Menu bar app + global hotkeys + a `myna` CLI
> • Reads selections from any app
> • Hooks into Claude Code so finished sessions speak themselves
> • macOS Apple Silicon, free, open, local-only
>
> What's coming in v0.2 (next few weeks): a karaoke-style subtitle ribbon that follows along word-by-word, a thinking-indicator chime, voice previews, a proper first-run cinematic.
>
> This is the rough alpha. It has edges. I'd rather ship it to twelve people who care than polish it for six more months in private.
>
> If you've ever lost a Claude Code session to a background tab — install it, break it, tell me what hurts.
>
> 🔗 Link in comments (DMG + `brew install`).

---

## Twitter thread (8 tweets, v0.1.0 announcement)

```
1/
Claude Code just learned to talk back.

A free, local, always-on TTS daemon for macOS. Reads your selections, your articles, and the output of your AI agents — out loud, through Kokoro voices, with zero cloud.

v0.1.0 alpha shipped today.

[GIF: menu bar icon → select paragraph → hotkey → voice begins, all in 4 seconds]
```

```
2/
Why this exists:

I kept missing Claude Code sessions finishing in background tabs.

40 minutes of "wait, is it still running?" became the most expensive thing in my workflow.

So I built the smallest possible fix: make the machine tell me when it's done.
```

```
3/
The constraints I gave myself:

— Local only. No API key, no token bill, no cloud round-trip.
— Lives in the menu bar. Stays out of the way.
— One hotkey from anywhere in macOS.
— Free, open, forever.

Speechify and friends are SaaS GUIs. This is a daemon.
```

```
4/
The Claude Code integration is the part I'm most proud of.

When a session finishes, a tiny toast appears with project-colored dots — one dot per parallel agent. Tap, and Myna reads the summary aloud.

You can finally walk away from your terminal.

[GIF: 3 parallel CC sessions, each completing, stacked toast with colored dots]
```

```
5/
Under the hood:

— Swift menu bar app + Python TTS daemon
— Kokoro voices (local neural, ~80MB)
— Apple Silicon only (for now)
— ~12k LOC, 91 Swift tests + 94 daemon tests green
— `brew install PrerakGada/tap/myna`

The whole thing weighs less than a Slack tab.
```

```
6/
v0.1.0 is rough. It's an alpha. Things I know are missing:

— No voice preview before you pick one (coming next sprint)
— No "now reading" indicator beyond the menu bar
— Settings panel is barely there
— Windows / Intel not supported

If you find more, my DMs are open.
```

```
7/
v0.2 is already in flight. The thing I can't wait to show you:

A floating karaoke ribbon at the bottom of your screen.

Current sentence. Active word bolded as Myna speaks it.

Works in every app. You read along with the voice, or you don't — your call.

[GIF: karaoke ribbon overlaying VS Code, then Safari, then Slack — same ribbon, three contexts]
```

```
8/
If you spend your days reading what your AI just wrote — Claude Code, Cursor, Codex, Aider, any of them — try this.

It costs nothing. It runs locally. It might save you 40 minutes a day.

DMG + brew: github.com/PrerakGada/myna

Built by one person. Feedback wanted, loudly.
```

---

## Alternate Tweet-1 hooks (5 variants)

**a) The demonstration**
> [GIF: 6s, no caption — selecting a Claude Code response, hitting a hotkey, the agent's last paragraph plays back in a warm voice while the user just keeps scrolling.]

*Pure show. Highest ceiling, risk is engagement.*

**b) The provocation** ← Sophia's overthrown-final pick
> Reading is the slowest part of using Claude Code.
>
> I'm not sure why we all agreed to keep doing it.

*"A claim about the reader will retweet better than a claim about the product."*

**c) The cost**
> Speechify charges $139/year to read PDFs to you.
>
> My laptop already has every voice it needs. So does yours.

**d) The vignette**
> 11:47pm. The dog is asleep. The agent finishes a long refactor.
>
> I close my eyes and listen to it tell me what it changed.

**e) The category claim**
> Local-first TTS for macOS. Built for developers. Reads your agent back to you.
>
> Free, open, and shipping next Tuesday.

**Final recommendation:** lead with (b). Hold "Claude Code just learned to talk back" as Tweet 2.

---

## The "what I was listening to" closer (for v0.2 LinkedIn)

> I built most of v0.2 at the corner table of Third Wave in Indiranagar — the one near the window, where the espresso machine hisses just loud enough to drown out my own typing. Bon Iver's *22, A Million* on loop, the dog (her name is Mishti) asleep under the desk, the menu bar icon pulsing every time I asked the daemon to read me back what I'd just written. It read this paragraph too. It got most of it right.

*82 words. Café name and album are placeholders Prerak should overwrite with truth. The last sentence is load-bearing — don't trim it.*

---

## Pre-Product Hunt teaser cadence (3 weeks out, 9 tweets)

### Week -3 — Category seed

> **Tweet 1**
> Every other interface my computer has — windows, notifications, the dock — got 40 years of design work.
>
> Audio got a volume slider.

> **Tweet 2**
> I've been watching my Claude Code sessions scroll past in silence and realizing: the agent is doing the most interesting work in the room and I'm reading it like a stock ticker.
>
> Something about that is broken.

> **Tweet 3**
> Speechify is a $100M company built on the premise that you'd rather listen than read.
>
> Nothing on macOS does this locally. Nothing does it for developers. Nothing reads what the agent just wrote you back.
>
> Weird, right?

### Week -2 — Capability tease

> **Tweet 4**
> macOS Apple Silicon. 100% local. Zero network calls.
>
> The voice in this clip is running on the same chip rendering this browser tab. No API key, no rate limit, no "your free trial has ended."
>
> [GIF: 8s clip — selecting a paragraph in Safari, hitting hotkey, menu bar icon pulses, voice plays. Network indicator visible and flat.]

> **Tweet 5**
> Six months ago I asked a friend what tool he used to listen to long PDFs.
>
> He said "I just don't."
>
> That's the gap.

> **Tweet 6 (3-tweet reply-to-self)**
>
> **Part 1:** Three things I learned building a local TTS daemon for Apple Silicon that nobody warned me about: 🧵
>
> **Part 2:** 1. Kokoro voices run at <200ms latency on M-series silicon. The bottleneck isn't inference — it's the synthesis-to-CoreAudio handoff. Nobody on the internet had written this down.
>
> **Part 3:** 2. Hotkeys + selection + TTS is a permissions minefield on modern macOS. Accessibility, Input Monitoring, and a Helper bundle just to read what's on your screen.
>
> 3. The hard part wasn't the audio. It was making the menu bar icon stop lying about whether it was speaking.
>
> Soon.

### Week -1 — The "you can have it" turn

> **Tweet 7**
> It's called Myna. It's free. It's open. It runs locally.
>
> I shipped v0.1 quietly last month to a dozen people. v0.2 lands next Tuesday — and the thing I'm proudest of is the one feature Speechify cannot ship even if they wanted to.
>
> [GIF: the wedge toast appearing as a Claude Code session finishes. Three-second beat, soft entrance, voice begins reading the agent's last message.]

> **Tweet 8**
> The feature: when Claude Code finishes a thought, a little wedge slides up from the menu bar and offers to read the last message aloud.
>
> You don't even have to highlight anything.
>
> It just knows when the agent stopped talking.

> **Tweet 9**
> Product Hunt next Tuesday. Brew install today.
>
> `brew tap PrerakGada/tap && brew install --cask myna`
>
> If you've ever wished your agent would just *tell you* when it's done, this is for that.

---

## Product Hunt listing copy

### Tagline (60 char cap)

> Local TTS for macOS. Built for developers. Reads agents back.

(58 characters. Three sentences, three claims.)

### Description (260 char cap)

> Myna is a menu bar app that reads selections, articles, and Claude Code agent output aloud — using local Kokoro voices on Apple Silicon. No cloud, no API key, no subscription. Open source. Free forever. Built because nothing on macOS did this for devs.

(247 characters.)

### Topics

1. **Developer Tools** — primary; this is who shows up to vote
2. **macOS** — anchors platform, pulls mac-power-user voter base
3. **Open Source** — differentiator vs Speechify; PH's OSS cohort is small but loud

(Skip "AI" — over-saturated, would put us next to ChatGPT wrappers. Skip "Productivity" — Developer Tools covers it.)

### First comment from the maker

> Hey Product Hunt — Prerak here, maker of Myna.
>
> Short story: I use Claude Code every day, and I spent six months squinting at long agent responses on a screen that's already too full. I tried every TTS tool on macOS. None of them were local. None of them knew what Claude Code was. Most of them charged me $10/month to read a PDF.
>
> So I built the one I wanted. It's free, it's open source (MIT), and it runs entirely on your Mac — no API keys, no subscriptions, no telemetry.
>
> The feature I'm proudest of is the little wedge that pops up when a Claude Code session finishes and offers to read the agent's last message back to you. You don't have to select anything. It just knows.
>
> Happy to answer anything. Bug reports especially welcome.
>
> — Prerak

### "What is Myna?" listing body

> **Myna is a local-first text-to-speech daemon for macOS Apple Silicon.**
>
> It lives in your menu bar. You select text — anywhere, in any app — hit a hotkey, and Myna reads it aloud using Kokoro voices running natively on your machine. No cloud round-trip. No API key. No "you've used 3 of 5 free articles this month."
>
> **Built for developers, not commuters.** Most TTS tools assume you're listening to a novel on a train. Myna assumes you're listening to a 4,000-token Claude Code response while you keep your hands on the keyboard. The whole interface — hotkeys, CLI, menu bar wedge — is designed for the person who already lives in their terminal.
>
> **The Claude Code integration is the part I cannot stop demoing.** When an agent session finishes, a small toast slides up from the menu bar offering to read the last message aloud. It works through a CC hook. You don't have to highlight anything, switch apps, or remember to invoke it. It just notices when the agent stopped talking.
>
> **It also reads:** selections in any app, web articles (with a proper readability pass, not raw HTML), and anything you pipe into the CLI. Voices include the full Kokoro library — 25+ presets, switchable per-context.
>
> **Open source. MIT licensed.** Brew install:
>
> `brew tap PrerakGada/tap && brew install --cask myna`
>
> If you've ever wished your agent would just tell you when it's done, give it a try.

### Feature bullets

> - 🎙️ Reads selections aloud from any app via global hotkey
> - 🔔 Claude Code wedge: auto-reads the agent's last response
> - 🌐 Web article reader with proper readability extraction
> - 🎚️ 25+ local Kokoro voices, switchable per context
> - 💻 Full CLI for piping anything you can type into a terminal
> - 🔒 100% local. No cloud. No telemetry. No API keys.
> - 🆓 Free forever. MIT licensed. Built by one person who got tired of squinting.

---

## v0.2.0 LinkedIn post (ship ~3-4 weeks from now after v0.2 lands)

> Three weeks ago I shipped v0.1 of Myna to twelve people.
>
> Today I'm shipping v0.2 to everyone else.
>
> The thing I didn't understand when I started: building a TTS tool for developers is mostly a study in what NOT to do. The twelve people who tried v0.1 sent me bug reports, feature requests, and — twice — voice memos describing exactly what they wished the menu bar icon would do instead. One of them sent me a 90-second screen recording with the words "watch where my eyes go" as the only annotation. I watched it four times.
>
> v0.2 is what those twelve people taught me.
>
> The headline feature is something I've been calling the wedge — a little toast that slides up from the menu bar when a Claude Code session finishes and offers to read the agent's last response aloud. You don't have to select anything. You don't have to switch apps. It just notices when the agent stopped talking.
>
> There's also a redesigned menu bar (the old one was lying about its state), a thinking indicator (because silence during synthesis felt broken), voice preview before you commit to a voice, a first-run flow that doesn't dump you at a blank screen, and a karaoke-style subtitle ribbon that I'm holding back as the Product Hunt hero.
>
> Free. Open. Local. Apple Silicon.
>
> `brew install --cask PrerakGada/tap/myna`
>
> If you tried v0.1, thank you. If you're trying v0.2, tell me what's broken.
>
> I built most of v0.2 at the corner table of Third Wave in Indiranagar — the one near the window, where the espresso machine hisses just loud enough to drown out my own typing. Bon Iver's *22, A Million* on loop, the dog (her name is Mishti) asleep under the desk, the menu bar icon pulsing every time I asked the daemon to read me back what I'd just written. It read this paragraph too. It got most of it right.

---

## What's missing (Sophia's flags)

- **A name for the category** — see `06-category-naming.md`. Mary and Victor took swings.
- **Asymmetric social proof, fast** — get Myna into the hands of one well-followed Claude Code power user (Simon Willison, Mitchell Hashimoto, similar) BEFORE the Twitter thread goes live. A single screenshotted reply from someone the audience trusts collapses 10 tweets of trust-building.
- **The "what I was listening to" closer** — only ships in v0.2, not v0.1. v0.1 hasn't earned the intimacy.
