# Visual direction — Caravaggio

> **Source:** BMad party-mode round 4, agent: Caravaggio (Visual Communication Expert).
> **Status:** ✅ Stack-agnostic. Applies fully to the Swift app + karaoke ribbon.

**Reference bar:** *"If Prerak ships every GIF and screenshot at the quality of Linear's launch reel (linear.app/method), the conversion funnel does itself."*

Not Raycast (too tooly), not Arc (too precious). Linear's motion-feels-inevitable, screenshots-look-like-the-product's-already-in-your-dock, restraint-lets-the-idea-breathe. Steal the cadence, not the palette.

---

## 1. The four demo GIFs — frame-by-frame storyboards

### GIF-1 — "The Hook" (Tweet 1)

**Duration:** 4.0s exactly. 0.5s cold-open + 2.5s action + 1.0s payoff.
**Aspect:** 16:9 at 1280×720.

| Time | On screen | Eye lands on |
|------|-----------|--------------|
| 0.0s | Chrome + Stratechery article. Myna bird idle in menu bar. | Menu bar bird |
| 0.5s | Cursor drags across paragraph 2. Highlight blue. | Highlight expanding |
| 1.0s | Selection complete — 3 sentences, ~40 words. | Highlighted text block |
| 1.5s | Hotkey overlay flashes bottom-center: `⌥⇧S` in soft pill, 80% opacity. | The hotkey pill |
| 2.0s | Pill fades. Bird transitions: outline → fill + 3-bar equalizer. **STATE CHANGE — money moment.** | Menu bar bird (alive) |
| 2.5s | Subtle waveform at bottom edge. First word "Stratechery" as ribbon teaser. | Waveform + ribbon |
| 3.0s | Steady state — equalizer animating, ribbon shows current word. | Animated bird + ribbon |
| 3.5s | Hold. "myna.audio" stamp fades in bottom-right. | Logo lockup |
| 4.0s | Crossfade loop to 0.0s. | — |

**⭐ Screenshot moment:** 2.0s — the state change. All 3 story beats in one frame.

**Color notes:** Menu bar in dark mode (light-mode loses bird at thumbnail). System blue for selection (`#0A84FF` dark). Hotkey pill: 12% white on black, SF Mono 14pt — Mac-native.

---

### GIF-2 — "The Wedge" (Tweet 4)

**Duration:** 6.0s. Longer because the GIF has 3 reveals; each gets ~2s breathing room.
**Aspect:** 16:9 at 1280×720, cropped to bottom-right quadrant.

| Time | On screen | Eye lands on |
|------|-----------|--------------|
| 0.0s | Claude Code, 3 terminal panes running. Corner empty. | The 3 panes |
| 0.5s | Pane 1 (top-left) checkmark, "Done." | Pane 1's checkmark |
| 1.0s | Toast 1 slides in: **green dot** (myna-repo) + "myna-repo: tests passing, 23 files changed." 300ms slide ease. | The new toast |
| 1.5s | Voice begins reading toast 1. Bird icon lights. Toast 1 speaker indicator. | Toast 1's speaker icon |
| 2.5s | Pane 2 checkmark. Toast 2 slides above toast 1: **amber dot** (docs-site) + "PR opened." | Toast 2 (new top) |
| 3.5s | Pane 3 checkmark. Toast 3 slides above: **purple dot** (landing-redesign) + "deploy preview ready." | **Full stack of 3 — money frame** |
| 4.5s | Stack holds. Toast 1 speaker fades. Toast 2 activates. | Toast 2 (now active) |
| 5.5s | "myna.audio" stamp. | Whole stack |
| 6.0s | Crossfade loop. | — |

**⭐ Screenshot moment:** 3.5s — the full stack of three. Three different-colored dots, three project names, three statuses, one voice queue. **This single frame IS the wedge.** Frame it, print it.

**Color notes:** Toasts = `rgba(28,28,30,0.92)` with 1px `rgba(255,255,255,0.08)` inner stroke. **Glass-but-NOT-glassmorphism** — frosted blur is overdone, signals "vibe coder side project." Project dots: 10px circles with 1px white inner ring at 40% opacity (Stripe's status-indicator trick).

---

### GIF-3 — "The v0.2 Tease" (Pre-PH Week -2)

**Duration:** 3.5s. Short on purpose — reply guys say "wait what is that ribbon."
**Aspect:** 16:9 at 1280×720, bottom 25% does the work.

| Time | On screen | Eye lands on |
|------|-----------|--------------|
| 0.0s | VS Code, `pull-request-review.md`. No ribbon. | Code (baseline) |
| 0.5s | Ribbon fades in at bottom: dark glass, "This PR refactors..." with **This** bolded. | Ribbon (appeared from nothing) |
| 1.0s-2.5s | Bold word advances: This → PR → refactors → auth → OAuth | Bolded word travel |
| 3.0s | Line completes. Tiny `v0.2` tag fades top-right at 60% opacity. | The v0.2 tag |
| 3.5s | Loop with 0.3s fade. | — |

**⭐ Screenshot moment:** 1.5s — "refactors" bolded mid-ribbon. Viewer's brain still resolving "what's happening to that word." Cognitive itch IS the screenshot.

**Color notes:** Ribbon = `rgba(20,20,22,0.94)` bg, `#A8A8AA` inactive words at 60% opacity, **`#FFFFFF` 100%** for bolded active. **No clever color** — white-on-dark, full stop. SF Pro Display Semibold 18pt — same metrics as macOS subtitles, feels native.

---

### GIF-4 — "The Universal" (Tweet 7)

**Duration:** 7.5s. Three contexts × 2.5s each. Hard ceiling.
**Aspect:** 16:9 at 1280×720. Ribbon stays anchored at bottom across context shifts.

| Time | On screen | Eye lands on |
|------|-----------|--------------|
| 0.0s | VS Code + ribbon: "Refactors **auth** flow to..." | Ribbon + code |
| 1.5s | Ribbon mid-sentence: "...uses **OAuth** with PKCE for..." | Bolded word |
| 2.5s | **Hard cut** to Safari + Stratechery. Ribbon STAYS, mid-sentence: "Aggregation **theory** explains how..." | Ribbon (didn't move!) |
| 4.0s | Safari: ribbon advances "...how **platforms** capture demand." | Bolded word |
| 5.0s | **Hard cut** to Slack DM. Ribbon at bottom: "Hey can you **review** the spec..." | Ribbon (still there!) |
| 6.5s | Slack: ribbon advances "...the **spec** before EOD?" | Bolded word |
| 7.0s | Hold. Tiny "myna.audio — anything, anywhere" overlay fades in. | Tagline |
| 7.5s | Loop. | — |

**⭐ Screenshot moment:** 2.5s — the cut. Either VS Code+ribbon or Safari+ribbon. Take the *after* — viewer's brain goes "wait, this isn't a code thing." Cognitive flip IS the screenshot.

For LinkedIn: 3-panel composite (VS Code / Safari / Slack stacked vertically, ribbon visible in all 3). Static carousel slide that does the GIF's job in one image.

**CRITICAL — Hard cuts only between contexts.** NO crossfades — crossfading dissolves the punchline. Ribbon pixel-identical across all 3 contexts (same color, position, font, baseline). Lock CSS, screenshot-verify.

---

## 2. The 10-hue project-dot palette

Colorblind-safe (deuteranopia/protanopia/tritanopia). Distinguishable side-by-side. Readable on light + dark menu bar. No collision with macOS system semantics. Built against Color Universal Design + Wong 2011, sanity-checked in OKLCH.

| # | Name | Hex | Why |
|---|------|-----|-----|
| 1 | **Coral** | `#FF6B6B` | Warm red shifted to orange (~25° from pure red) — reads "red-ish" without triggering system-error pattern |
| 2 | **Marigold** | `#F2A93B` | Warm yellow-orange, ~70° hue — distinct from coral by 45°+ |
| 3 | **Olive** | `#A8B545` | Yellow-green, ~115° — the "third dot" most palettes botch; rare in product UI = high recognizability |
| 4 | **Emerald** | `#3FB46C` | True green shifted slightly cool — not macOS success-green (`#34C759`), close enough to read green |
| 5 | **Teal** | `#2BB4B0` | Cyan-green ~190° — unsung hero; works for deuteranopes |
| 6 | **Sky** | `#4DA6FF` | Soft blue, saturation drop vs macOS system blue (`#007AFF`) — doesn't compete with system controls |
| 7 | **Iris** | `#7B5BFF` | Blue-purple ~280° — Linear-purple cousin; premium without precious |
| 8 | **Orchid** | `#C964D4` | Magenta ~320° — saturated enough to read purple-pink, not pastel |
| 9 | **Rose** | `#FF7AA8` | Warm pink ~350° — sits next to coral but separated by saturation + warmth |
| 10 | **Slate** | `#9098A6` | Neutral blue-gray — THE NEUTRAL SLOT. Every palette forgets this; every CC user with a "misc" project needs it. Default. |

**Hue distribution:** 3 warm (1,2,9), 2 yellow-green (3,4), 2 cool-green/blue (5,6), 2 purples (7,8), 1 neutral (10). Full hue coverage, no gap >40°.

**Lightness 60-75 perceptually** — readable on both backgrounds without per-mode swapping.
**Saturation 55-75%** — confident without kindergarten.

**Implementation:** FNV-1a hash on project root path, modulo 10. Same project = same dot forever. The determinism IS the feature — muscle memory.

**Validation:** run through Coblis before shipping.

---

## 3. The Myna bird icon

**Refused upfront:** no microphone icon, no speech bubble, no headphones, no soundwave-only abstraction. Every TTS app since 2014 has a microphone — Myna is the *listening surface*, not a podcast app.

### Construction rules

- Geometric, single-weight stroke, SF Symbol-adjacent (sits next to native Apple icons without being foreign)
- Single continuous outline at 1.5pt stroke weight
- 22×22pt target with 2pt safe-area padding (bird = 18×18pt expressive area)
- 3-curve maximum for body silhouette: head, body, tail. No wing detail, no feather texture, no foot — noise at menu-bar scale.
- **One personality detail:** the eye. Small filled dot (1pt radius), slightly forward of center. That single dot makes the bird *attentive* not *generic*.
- **Beak slightly open, tilted up ~15°.** Closed-beak = sparrow. Open-beak = listening for you. The entire personality is the beak.

**Silhouette test:** at 16×16 in pure black, no internal detail — must read as bird (not blob, not leaf, not fish). The upturned beak does this work.

**Personality:** body axis tilted ~10° forward. Upright bird reads as logo; forward-leaning bird reads as interested.

### Five state variants

| State | Visual change | Motion |
|-------|---------------|--------|
| **Idle** | Outlined bird, 1.5pt stroke, template-rendered. Static. | None |
| **Speaking** | Bird FILLS (solid). Three vertical equalizer bars replace the beak area — NOT next to bird, *as* the bird's mouth. | 2fps bar dance, ease-in-out, asymmetric (not all in sync = not robotic) |
| **Thinking** | Bird stays outlined. Soft halo (3pt outside silhouette, 30% opacity peak) pulses. | 600ms cosine cycle, 0%→30%→0% |
| **Paused** | Bird outlined, 75% opacity. Horizontal bar (2pt thick, full-width) passes through body at vertical-center. | Static — pause = absence of motion |
| **Error** | Bird outlined (full opacity). Small red dot (`#FF453A` macOS red) at upper-right of bounding box. | Static or 2s slow fade-in once |

**Bold calls explained:**
- **Equalizer-as-beak:** most icons put equalizer next to the icon. Putting it IN the beak fuses bird + sound into one symbol. "The silhouette IS the story."
- **Halo not dots:** "..." for thinking is chat-app cliché. Halo is internal-processing.
- **Pause = bar through body:** instinct is "pause icon next to bird." Veto. Pause happens TO the bird, not beside it.
- **Error = corner dot:** tinting the bird red makes it feel angry. Corner dot keeps the bird neutral — *connection* is broken, not bird.

---

## 4. Product Hunt hero image (1270×760)

**The single visual idea:** laptop screen showing apps mid-use, menu bar bird animated speaking (equalizer bars), karaoke ribbon visible at bottom of laptop screen with one word bolded. **"This is a system layer for spoken AI output"** — without a word of marketing copy.

**Composition (rule of thirds):**
- **Left third:** negative space, `#0A0A0C` dark, subtle radial gradient pulling eye rightward
- **Center third:** laptop, ~6° rotation right ("open toward you"). MacBook Pro 14" silhouette — no logo needed
- **Right third:** menu bar bird, soft "Reading" callout in 14pt SF Pro at 60% opacity, 1pt connector to bird. Whisper-tier.

**Focal hierarchy:**
1. Karaoke ribbon's bolded word (highest contrast: white on dark)
2. Menu bar bird in speaking state
3. "Reading" callout (last, supports the story)

**This is the inverse of every product hero you've seen this year.** Most product heroes shout product name + tagline + giant screenshot. Yours whispers the *use*. Linear did this. Arc didn't, and that's why Arc launched bigger but converted worse.

### Three specific compositions

**Composition A — "The Desk" (my pick).** Top-down 3/4 perspective of a desk: laptop center-left, AirPods Max right (suggesting "listening"), laptop screen shows Stratechery tab with text selected, ribbon active, bird speaking. Plant in upper-left for warmth. NO floating UI mockups, NO marketing copy on the image. **Tension:** the headphones aren't on a head — they're sitting there, *waiting*. That negative space IS the offer.

**Composition B — "The Three Contexts."** Three laptop screens fanned slightly (like a card spread): VS Code, Safari, Slack. Same ribbon across all 3. Bird visible on center laptop. Pure black background. **Tension:** real apps with real content, not Lorem Ipsum. Viewer reads each snippet before realizing they're being sold something.

**Composition C — "The Bird."** Pure illustration. Myna bird scaled to ~400px, center, equalizer-beak animated (Lottie/animated WebP for PH's video-hero). Around it: satellite arrangement of floating ribbon-text fragments. Symbolic, movie-poster, Saul Bass territory.

**My pick: A.** Most honest — shows actual context Myna is used in. Honesty converts on PH where everyone is jaded.

---

## 5. Recording specs

**Tools:**
- Screen recording: `cleanshot x` ($30, worth it — cursor customization, desktop-icon hiding, auto-hide-menu-bar-on-other-apps). Fallback: QuickTime.
- GIF encoding: `ffmpeg` with two-pass palettegen. NOT Gifski (bigger files), NOT Giphy Capture (compression kills small ribbon text).
- MP4 (LinkedIn + PH): `ffmpeg` with H.264 at CRF 23, AAC audio (muted but kept so platforms don't re-encode aggressively).

**Framerate:**
- **24fps for GIFs.** Below 18fps, ease curves snap. Above 30fps, file size doubles for nothing.
- **30fps for MP4** — codec handles efficiently.

**File-size targets:**

| Platform | Target | Hard ceiling | Format |
|----------|--------|--------------|--------|
| Twitter | <5MB | 15MB | GIF (animated WebP also fine) |
| LinkedIn | <5MB | 200MB | MP4 H.264 (NOT GIF — LinkedIn re-encodes GIFs aggressively) |
| Product Hunt | <10MB | 100MB | MP4 H.264, or WebP for animated still |

**Copy-paste workflow:**

```bash
# Step 1: palette from source
ffmpeg -i input.mov -vf "fps=24,scale=1280:-1:flags=lanczos,palettegen=max_colors=128:stats_mode=diff" -y palette.png

# Step 2: encode GIF
ffmpeg -i input.mov -i palette.png -lavfi "fps=24,scale=1280:-1:flags=lanczos[v];[v][1:v]paletteuse=dither=bayer:bayer_scale=5" -y output.gif

ls -lh output.gif
```

A 4s 1280×720 24fps clip should land 2.5-4MB for UI motion. Overshoot 5MB → drop scale to `1024:-1` before dropping framerate.

For MP4 (LinkedIn):
```bash
ffmpeg -i input.mov -vf "fps=30,scale=1280:-1:flags=lanczos" -c:v libx264 -crf 23 -preset slow -pix_fmt yuv420p -movflags +faststart -an -y output.mp4
```

`+faststart` is what makes LinkedIn's player start playing before download completes. Critical for autoplay-in-feed.

---

## 6. The two PH money-shot screenshots

### Shot 1 — The Stacked Toasts

**In frame:** bottom-right Mac corner cropped ~900×900. Three toasts stacked, dots in palette hues (top amber `docs-site`, middle green `myna-repo` [active speaker indicator], bottom purple `landing-redesign`). Behind: Claude Code terminal window with 3 panes, defocused ~40% opacity, 4px blur. Menu bar at top, bird in speaking state.

**Not in frame:** no mouse cursor (amateur tell), no wallpaper details (flat dark gradient), no app dock (crop above), no marketing copy overlaid.

**Tension:** 3 projects, 1 queue, 1 voice. Active speaker indicator on middle toast implies *queue order*, which implies *the system is making a decision for you* — the entire wedge.

**Contrast:** `#0A0A0C` near-black bg (not pure — pure black on OLED looks like hardware error). Toasts at `rgba(28,28,30,0.92)` = 4.5:1 contrast = WCAG AA.

### Shot 2 — The 0:11 Cinematic Frame

**In frame:** centered Myna bird logo at ~120pt (hero-scale). Below: **"Your reading companion."** in SF Pro Display Light 32pt, +1.2% letter-spacing, 95% white. **NOT semibold** — Light is intimacy. Below that: subdued paused animation of stylized browser window outline (~400×260pt) with paragraph of placeholder text, 3 sentences highlighted blue, paused at moment selection completes (before hotkey/audio). Background: deep gradient `#0A0A0C` → `#1A1A1F`.

**Not in frame:** no window chrome, no menu bar, no dock, no marketing tagline, no v0.2, no "get started" button.

**Tension:** the paused selection-animation. Viewer sees text *about to be read* but not yet read. Brain finishes: *"so this thing will read selected text to me."* Sold the feature without naming it.

**Note:** the bird at 120pt needs 2.5pt stroke (NOT 1.5pt scaled up — looks spindly). Stroke weights don't scale linearly per size class.

---

## Mistakes to refuse — top 5

1. **A microphone icon. Anywhere. Ever.** Microphones record. Myna *speaks*. The microphone reflex puts you in the same mental bucket as Otter, Descript, every podcast app, the iOS dictation widget. The bird is the brand. Non-negotiable.

2. **Glassmorphism on the toasts.** Frosted-blur acrylic was 2022 vibe-coder aesthetic. Looks great in screenshots, terrible in motion (blur sample lags 1-2 frames behind slide-in = "smearing"). Solid + 1px inner stroke is what Linear, Stripe, Raycast ship.

3. **Animated gradients in PH hero or as background.** "Subtle conic gradient that slowly rotates" is 2024 indie-Mac-app cliché. Signals "I have nothing specific to say so I'm decorating." Background is dark, flat, at most one radial gradient to direct eye.

4. **Karaoke ribbon with multi-color words or theme support.** Ribbon's job is invisible-until-needed and word-bolded-when-needed. Color is noise. White-on-dark, no settings. The ribbon being *the same everywhere* is what makes GIF-4 work — themable kills the universality and you've shipped a customization feature instead of a thesis statement.

5. **Text overlays on the GIFs.** "Select text → press hotkey → Myna reads it!" written in motion-typography. Veto. Every GIF must communicate visually first. Only allowable text: tiny `myna.audio` brand stamp at end (and even that's optional). The whole point of motion is to not need words.
