# Category naming — Mary vs. Victor

> **Source:** BMad party-mode round 4, agents: Mary (Business Analyst, evidence-grounded) and Victor (Innovation Oracle, strategic gambit). They disagreed by design.
> **Status:** ✅ Open decision. Both names have merits. Prerak picks the flag.

---

## The two candidates

| | Mary's pick | Victor's pick |
|---|---|---|
| **Name** | **Selective Listening** | **Ambient Agent Audio** |
| Pattern | Gerund + object (read-later, async video) | Carve a new noun (webhooks, growth hacking) |
| Audience | "Everyone reading too much" | "Devs running autonomous agents" |
| Defensibility | Excludes Speechify by *behavior* (selective ≠ comprehensive) | Excludes Speechify by *architecture* (daemon ≠ SaaS) |
| Lindy stability | High — works on any platform, any roadmap | Highest — but only if Myna stays agent-first |
| Risk | Slightly under-claims the v0.3 wedge | May feel niche-jargon to broader PH audience |

---

## Mary's full case — "Selective Listening"

**Top-line:** Myna isn't a TTS app, a screen reader, or an AI voice generator — it's the first tool built around the act of **choosing what to listen to** in a world where machines now produce more readable text per day than any human can read. The name should describe that human behavior, not the underlying tech.

### Why this name

Every named category in the neighborhood describes either the *tech stack* (TTS, AI voice generator) or a *content shape* (audiobook, podcast, read-later). **No one has named the human behavior of selectively listening to text on demand.** That's the white space.

The strongest category-naming pattern is **gerund + object** — names the behavior, not the tool. Pocket → "read-later." Loom → "async video." Karpathy → "vibe coding." Behavior is human, durable, defensible.

### Tests

| Test | Selective Listening |
|---|---|
| Searchability | 9/10 — exists in psychology, NOT in software. Myna would dominate the SERP within a year. Adjacent meaning reinforces the human-behavior frame. |
| Memorability | 9/10 — two ordinary words. "Oh, like Pocket but for audio?" is the right reaction. |
| Defensibility | 8/10 — Speechify *cannot* credibly rebrand as "selective listening" because their entire product (full-article narration) is the opposite of selective. |
| Expandability | 10/10 — works on Linux, mobile, browser extension, AI integrations. "Listening" doesn't care about platform. |

### Discarded alternatives

- **Ambient Listening** — already claimed by healthcare AI ($5B market, Nuance DAX / Abridge). Don't fight an entrenched incumbent for a phrase. Sophia's "ambient AI audio" instinct was directionally right but the literal phrase is taken.
- **Listen-Later** — strong rhyme with read-later, instantly legible, but slightly under-claims live AI agent output (it's not really "later"). Keep in pocket as fallback.

### Where it lands

| Surface | Use? | How |
|---|---|---|
| Tagline (8 words) | YES | "Selective listening for your Mac." |
| PH topic / category | YES — propose as new | First line of PH description: *"Myna is selective listening — [definition]."* |
| README h1 / subhead | YES | H1: "Myna" / Sub: "Selective listening for macOS." |
| Personal bio | YES | "Building Myna — selective listening for the AI era." |
| HN / Show HN title | SOFTER | HN crowd rejects marketing. Title: *"Show HN: Myna — a local macOS daemon that reads any text aloud."* Category name in body, not title. |
| Technical docs | NO | Keep literal ("text-to-speech daemon"). |

### 30-word elevator pitch (lift verbatim)

> Myna is selective listening for your Mac — a local daemon that turns anything you select, read, or generate with AI into speech, on your queue, on your terms.

(Exactly 30 words.)

### Mary's footnote (anticipating Victor)

> Pocket called itself "read-later" before it called itself "the place where the internet's best stuff lives." Order matters. Claim the small, defensible, behavior-named category first. Expand the claim later when the product can defend it.

---

## Victor's full case — "Ambient Agent Audio"

**Top declaration:** *AMBIENT AGENT AUDIO. That's the flag. Plant it.*

Myna is the local runtime that turns autonomous agents into ambient companions — voice that arrives without you asking, fades without you managing, and lives on your machine because the network can't be in the loop.

Myna is NOT a TTS app, a screen reader, a notification sound, or "Speechify for code."

### Candidates Victor rejected

- **"Text-to-speech for developers"** — TRAP. Anchors you to a 30-year-old commodity. Death by analogy.
- **"AI voice notifier"** — NO. Notifier is a feature.
- **"Ambient AI audio"** — NO, too broad — includes Suno, ElevenLabs, every soundscape app. Loses the agent specificity that IS the moat.
- **"The audio layer for agentic work"** — GO as descriptor, NO as category. Too many words. Categories are nouns.
- **"Listening surface for AI"** (his own Round 1 framing) — TRAP. Thesis-shaped, not flag-shaped. Killed publicly.
- **"Read-aloud, locally"** — NO. Feature description wearing a category costume.

### Why Ambient Agent Audio

**What it forces incumbents to do:** Speechify, ElevenReader, NaturalReader cannot enter Ambient Agent Audio without rebuilding around a local daemon. Their SaaS architecture + per-character billing model are *constitutionally* incompatible with hook-driven machine-local agent-triggered playback. The category name *names their disability.* Christensen's asymmetric motivation in its purest form.

**What it forecloses for Myna:**
- Cannot pivot to cloud TTS
- Cannot become a podcast tool
- Cannot sell a per-character API as primary product
- "Ambient" rules out interruption-as-a-feature
- "Agent" rules out human-authored content as the wedge
- "Audio" (not "voice") leaves room for earcons, status tones, the karaoke ribbon's sonic textures

**Good foreclosures. Sharp ones.**

### The naming move

Class (a) — **Carve a new noun.** Hardest play, biggest payoff. "Ambient Agent Audio" is not a phrase anyone uses today. Pocket carved "read-later." Loom carved "async video." Figma carved "multiplayer design." Each one took an adjective-adjective-noun stack and welded it into a single category referent through sheer consistent usage.

Not (b) bend-existing-noun — "audio" too generic, "voice" too narrow.
Not (c) modifier-stack ("agentic TTS," "local voice runtime") — sounds like SEO, not strategy. Optimizes for being found by people already searching. Carving a new noun optimizes for being the *only* answer when the search finally starts.

### The Lindy test

Five years out. Myna has a multi-agent registry, Linux port, mobile companion mirroring agent activity, API for third parties. Does "Ambient Agent Audio" still describe it? **Yes.** Every one is ambient (background, non-demanding), agent-triggered, audio (the shared substrate). The name expands without strain.

Compare "read-aloud for AI output" — collapses the moment Myna ships anything beyond playback. Lindy-fragile. Discard.

### The single-page bet (77 words, README front-matter material)

> **Myna is the local runtime for Ambient Agent Audio — the always-on, never-intrusive voice layer for the autonomous agents already running on your machine. Speechify reads what you choose; Myna speaks what your agents do. It lives in your daemon, not their cloud, because the network can't sit between you and a tool that's supposed to feel like a sense. Claude Code just learned to talk back. Soon, all of them will.**

### Victor's parting line

> Mary will give you the safer name. I'm giving you the bigger one. Both are defensible; only one is expandable. Pick the flag you're willing to plant for five years.

---

## Orchestrator synthesis

**The third option neither named:** ship both, in two registers.

- **Ambient Agent Audio** as the thesis paragraph (Victor's 77-word bet is genuinely great for positioning). Use on README front matter, in long-form pitch decks, in "what is Myna?" body of PH listing.
- **Selective Listening** as the user-facing surface noun (Mary's "selective listening for your Mac" lands faster in a PH card, on a tagline, in a bio).

They're not actually competing — they describe the same product from two angles. Victor's framing is the *product side* (what it does mechanically); Mary's framing is the *user side* (what they do with it).

**If forced to ONE for v0.2:** Mary's "Selective Listening" wins on timing. Prerak doesn't yet have the multi-agent registry / Linux port / third-party API that would make "Ambient Agent Audio" feel earned at the listing-card scale. Victor's framing becomes correct in v0.4+ when the agent surface widens.

**Plant Mary's flag first, evolve to Victor's flag later** — Pocket / Notion / Loom all did this.

---

## What it costs to get this wrong

**Leaving it unnamed:** Speechify spends $50M/year on marketing. Every press article frames Myna as "another Speechify alternative." Every PH visitor reads through the lens *they already have*. Unnamed = absorbed into the nearest incumbent's category. This is the default fate of every product without a flag.

**Naming it badly:** the name sticks. Pocket tried to rebrand from "Read It Later" to "Pocket" — took 3 years and a Mozilla acquisition. Once v0.1 ships with a category name on README, GitHub stars, PH comments, and tweets cement it.

**Over-claiming:** "Ambient AI audio" or "the audio layer for agentic work" are aspirational categories requiring a team of 50 and $20M to defend. Solo founder, Alpha stage — Prerak cannot occupy a category that requires defending against OpenAI / Anthropic / Apple simultaneously.

**Prerak's specific risk tier:**
- Solo founder → name must be self-explanatory, no marketing budget to teach a new word
- Alpha stage → name must work *before* the product is polished
- macOS-only → name should not foreclose Linux/mobile (rules out "Mac listener")
- Adjacent to a $200M incumbent (Speechify) → name must structurally *exclude* the incumbent's positioning, not compete inside theirs

**"Selective Listening" satisfies all four.** Two ordinary words, no teaching cost. Works on barely-launched Alpha. Platform-agnostic. Actively excludes Speechify's full-narration positioning.
