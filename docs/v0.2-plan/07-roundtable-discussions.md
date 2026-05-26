# Roundtable discussions — Round 1 brainstorm + John's cold-water passes

> **Source:** BMad party-mode rounds 1 and 4. The other docs in this folder are the *outputs* of the discussion; this doc preserves the conversation that produced them, including dissents and trade-offs that didn't make it into the consolidated docs.

---

## Round 1 — Initial brainstorm (4 agents)

When Prerak said "let's brainstorm next-level features for Myna v0.2," four agents took swings.

### 🧠 Carson — "Wild ideas, kerosene mode"

Carson's job was divergent ideation. Themes:

**Theme 1 — Myna has a PERSONALITY (the moat nobody's building)**
1. **Voice Wardrobe** — Per-app voice mapping. Slack reads in your "chill friend" voice, Terminal in your "wise mentor" voice, Claude Code in your "co-pilot" voice. Context-switching by ear.
2. **Mood Engine** 🌶️ — Myna detects sentiment in the text and modulates pace/voice. Stack trace? Slower, calmer. Shipping celebration in Slack? Warmer, brighter.
3. **Wake Phrase, Not Wake Word** 🌶️ — "Hey Myna, what was that last bit?" / "Myna, slower." No cloud, just whisper.cpp local.

**Theme 2 — Claude Code becomes a LIVE TEAMMATE, not a notification**
4. **The Standup** — One hotkey summarizes ALL parallel CC sessions in 20 seconds: "Session 1 finished migrations, Session 2 hit a test failure, Session 3 is still working."
5. **Disagreement Detector** 🌶️ — When two CC sessions output conflicting conclusions on the same file, Myna interrupts: "Heads up — Session A and B disagree about the cache strategy." Killer demo.
6. **Worry Voice** — When CC outputs words like "however," "but," "warning," "deleted," Myna reads those clauses in a slightly different tone.

**Theme 3 — The READING experience nobody's nailed**
7. **Skim Mode** — Hold a modifier, Myna reads only headings + first sentence of each paragraph at 1.5x. Release modifier, drops into current paragraph.
8. **Bookmark-on-Pause** — Pause anywhere, Myna remembers. Resume tomorrow from that exact word.
9. **The Re-Read** 🌶️ — Triple-tap hotkey rewinds 15s AND drops original text into floating overlay synced to audio (karaoke-style). For when you spaced out. → became S12 karaoke ribbon

**Theme 4 — The deeply weird ones**
10. **Duet Mode** 🌶️🌶️ — Two Kokoro voices read a Claude Code session like a play: User in one voice, Claude in another. Code review as radio drama.

**Carson's disagreement banked:** *"If anyone tries to push cloud sync of preferences or team features, I will fight them. Myna's whole vibe is your machine, your voice, no servers."*

---

### 📋 John — "Cold-water pass, JTBD discipline"

John's Round 1 response set the standing critique that has run through every subsequent round.

**Jobs Myna is already winning (v0.1):**
1. "Let me keep reading while my eyes are doing something else." — selection-to-speech, article reader. **This is the wedge.** Local, instant, no API meter ticking.
2. "Tell me when my Claude Code agent is done so I don't babysit it." — silent menu-bar announce + click-to-hear. **This is the only job in the product nobody else is doing.**
3. "Let me run N parallel CC sessions without them all screaming at me." — routing UX. Quiet superpower.

**Adjacent jobs worth interrogating (not adopting yet):**
1. Per-source summary length presets (article = 3 bullets, CC reply = 1 sentence)
2. Per-context voice (CC = one voice, articles = another)
3. Playlist for menu-bar announces

**John's cold water:**

> They will all die in real usage because nobody hired Myna for those jobs. They hired it because their eyes are tired and their CC agents are loud.
>
> **Why do you need a second announcement to have new features?** The Instagram Story was "I built a thing." LinkedIn could be "here's the one job it does that nothing else does."
>
> You don't have a feature problem. You might have a *story* problem.

**John's direct question to Prerak:** *"Of the users who've installed v0.1.0 in the last 24 hours — how many have you actually watched use it? If the answer is zero, no feature we brainstorm today is grounded."*

This question went unanswered. It returned in Round 4.

---

### 🎨 Sally — "The UX leap, scenes not features"

Sally specced the user-facing moments. Full document at `03-ux-direction.md`. Key contributions:

- Vivid "first 60 seconds of a new user" failure scenario (45 seconds of silence → user quits → app sits in /Applications forever, unloved)
- First-run cinematic concept (became S11)
- "Thinking" indicator across time-bands (became S07)
- Re-read gesture (echoed Carson's #9)
- Voice preview in picker (became S09)
- Output-device contract (don't blast laptop speakers when no headphones connected)
- VoiceOver / non-English language detection
- *"The leap from 'neat tool' to 'I texted three friends about this' is almost never the new wow feature. It's the removal of those forty-five seconds."*

Sally's disagreement banked: *"Don't add a second new wow feature for the LinkedIn post. Add the first-run cinematic and the re-read hotkey, then announce 'Myna now teaches itself to you in 30 seconds.'"*

---

### ⚡ Victor — "Strategic gambit, name the new category"

Victor's Round 1 framing became the strategic backbone of every subsequent round.

**Key declaration:** *"You are not building a TTS app. If you market Myna as 'another text-to-speech tool,' you are walking onto Speechify's chessboard. You will lose."*

**What Myna actually is:** the listening surface for AI-generated output. **The category does not exist yet.** Every other player solves "read my PDF aloud" — a human-authored-content problem. Myna solves "my three Claude Code sessions just finished and I cannot stare at six terminals."

**Christensen frame:** low-end disruption that grew teeth. Started where incumbents don't compete (free, local, developer-flavored). Structural moat: they're SaaS businesses; you're a daemon. Their business model forbids them from being you.

**Four bets that widen the moat:**
1. Multi-agent orchestration as first-class concept (not "Claude Code support" — registry of Claude Code, Codex, Cursor, Aider, Gemini CLI, custom shell hooks)
2. Audio-first agent triage (summary is not a feature, it is the *product*) — "auditory standup with your agents"
3. The CLI as differentiator, not afterthought — pipeable, scriptable, hookable
4. "Listening sessions" — persistent, resumable audio context (closed laptop mid-summary, reopen and it resumes)

**Strategic theater to refuse:**
- Voice cloning (drags onto Speechify's chessboard)
- 200-voice library (you're not in the voices business)
- iOS app yet (premature)
- Audiobook playback (wrong content shape)

> "You are in the *what-deserves-my-ears* business."

Victor's Round 1 question: *"When someone asks you 'what is Myna?' at a conference in 90 days — what is the single sentence? If it contains the phrase 'text-to-speech,' you have already lost the positioning war."*

---

## Round 4 — John's cold-water cut (after 11 stories were specced)

After Amelia specced S06–S16 (~61h, 11 stories) and the team had drafted GIFs, launch copy, and category naming, Prerak asked John to pressure-test the sprint.

### The cut

> **S11 — First-run cinematic. Move to v0.3. No mourning.**

John's case:
- *What job does this hire Myna to do?* "Make a strong first impression." For whom? Prerak has zero recorded user sessions.
- *Will a v0.1 user notice its absence in v0.2?* No. They already had their first run. This serves new installs only — the unmeasured cohort.
- *What announcement copy can't be written without it?* None. The v0.2 announcement is CC-hook + karaoke teaser + menu bar. Cinematic doesn't make the headline.
- *If shipped but next 50 users never reached the end?* And they won't. Onboarding completion rates on indie macOS tools are brutal.

> Ten hours. Solo dev. Pre-evidence. Cut.

**Soft cut: S15 (Karaoke Tier 1.5 variants)** — *"Spec'ing variants of a Tier-1 that doesn't exist yet is template-filling energy. Build Tier 1 (S12), watch five users, *then* decide which variant."*

**Lowest-conviction cut: S10 (What's New dialog)** — *"What job does this hire Myna to do that a LinkedIn post and a release notes link in the menu can't? Defend the dialog against 'release notes URL in the menu bar.' I'll listen."*

**Total cut:** 10h hard (S11) + S15 hours + 4h soft (S10) = at least 10h, plausibly 18h. Sprint goes from ~61h to ~43h.

### The risk triage (post-cut)

| Rank | Story | Trip wire | Mitigation before code |
|------|-------|-----------|------------------------|
| 1 | S08 CC-hook ready toast | Toast fires for wrong event, or correct event but copy reads like system error | Write toast copy first. All four states. Show to two humans who don't know Claude Code. |
| 2 | S12 Karaoke ribbon | Latency. 400ms behind voice = horror movie | Spike worst case first — fastest speaker, longest sentence, on battery. If lag visible, scope to "completed-phrase reveal." |
| 3 | S06 Menu bar redesign | Redesign only marginally better invites same critique | Hold Sally to one round of revisions max. Don't bikeshed. |
| 4 | S07 Thinking indicator | Doesn't disappear cleanly on failure. User sees "thinking…" forever | Define timeout + failure-state copy *before* success animation. Failure states are the feature. |
| 5 | S09 Voice preview | Plays over active session, or preview voice ≠ actual due to caching | Confirm audio pipeline can interrupt-and-resume cleanly. |
| 6 | S13 Settings shell | Empty shell ships, users expect settings, find none | Ship with ≥3 real settings inside, or don't ship the shell. |
| 7 | S14 Release prep | You already lived this once | Re-read MEMORY.md. The 10-iteration sign saga is documented for the version of you who forgot. |
| 8 | S16 Demo GIF pipeline | Rough GIFs make Myna look amateur to your conversion audience | One golden GIF for the hero feature (S08). Manual capture. Don't build pipeline for a problem you'll have 3 times this year. |

### The forcing function — the standing recommendation

> **Seven days. Five names. Five videos.**
>
> Prerak picks five names — not abstract personas, actual humans with email addresses. He sends them v0.1.0 with one ask: "Install this, use it for a week, screen-record one session, send it back." Offer something — a coffee, a feature credit, eternal gratitude. The deliverable is *five videos sitting on his desk before line one of v0.2 code*.
>
> If five is too many, do three. If three is too many, do one. Zero is the only failure state.

**Three questions whose answers change the v0.2 priority order:**

1. *Where do the five users get confused in the first 60 seconds?* If menu bar → S06 urgent. If onboarding → reopen S11 cut. If voice picker → S09 jumps queue.
2. *When (if ever) does a user trigger something Myna can't handle gracefully?* Tells you whether S07 is a polish item or a retention bug.
3. *Does anyone — even once — say "wait, did it hear me?"* If yes, karaoke (S12) isn't a PH-launch flourish, it's a v0.2 must-have.

### John's honest assessment

> The team is currently building for the announcement. Not entirely — the wedge thesis (CC-hook toast) is user-grounded, and the karaoke argument has strategic merit. But the sprint shape (11 stories, hero features chosen for tweet-ability, GIF pipeline as its own story) is a marketing sprint with engineering attached, not the reverse.
>
> Indie tools that nail their announcement get the second chance to learn what users actually want. But you only get to play the announcement card a few times. Spending it on features you haven't validated is how you arrive at v0.3 with louder silence than v0.2.

---

## Status of John's recommendations

| John's call | Decision pending |
|---|---|
| Cut S11 (cinematic) | Soft — already specced; defer to v0.3 unlikely to lose much |
| Cut S15 (Tier 1.5 variants) | Recommended — don't spec variants of a feature that doesn't exist yet |
| Cut S10 (What's New) | Open — Amelia's S10 is 4h and shares schema with S11/S13, may be cheaper than skipping |
| Forcing function (watch 5 users in 7 days, before any v0.2 code) | **Standing advice, not blocking.** Token-cheap. Costs zero engineering. Should happen regardless. |
