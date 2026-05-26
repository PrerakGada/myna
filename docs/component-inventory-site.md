# Myna — Site Component Inventory

> Per-component reference for everything under `site/app/` and `site/components/`. Grouped by role: **Layout · Hero/visuals · Interactive · Content**.

Conventions:
- File-line links point at the relevant declaration.
- "Server / Client" refers to React Server / Client component (`"use client"` directive).
- "Used by" lists the importers within this lane (`page.tsx`, `layout.tsx`, and sibling components).

---

## Layout

### `RootLayout` (default export)
- **File:** [`site/app/layout.tsx:60`](../site/app/layout.tsx#L60)
- **Kind:** default export (Next App Router root layout).
- **Server / Client:** **Server**.
- **Props:** `{ children: React.ReactNode }`.
- **Children expected:** any (Next supplies the routed page).
- **External deps:** `next` (`Metadata`, `Viewport` types), `next/font/google` (Fraunces, Newsreader, JetBrains Mono).
- **Used by:** Next.js router (implicit).
- **Visual purpose:** Sets `<html>`, applies font CSS variables, paints the cream `bg-paper` body, mounts the global `.grain-overlay` div.
- **Reuse potential:** Layout root — not reusable.

### `Page` (default export)
- **File:** [`site/app/page.tsx:19`](../site/app/page.tsx#L19)
- **Kind:** default export.
- **Server / Client:** **Server**.
- **Props:** none.
- **External deps:** all 15 site components (see imports at [`page.tsx:1-15`](../site/app/page.tsx#L1)).
- **Used by:** Next.js router (route `/`).
- **Visual purpose:** Assembles the entire single-page narrative (hero → hook → features → how → why local → install → platforms → shortcuts → FAQ → closing → footer + mobile sticky CTA).
- **Reuse potential:** Page-level shell — not reusable.

### `FeatureRow` (helper, private to `page.tsx`)
- **File:** [`site/app/page.tsx:556`](../site/app/page.tsx#L556)
- **Kind:** local function component (not exported).
- **Server / Client:** **Server**.
- **Props:**
  ```ts
  {
    number: string;       // "01" … "05"
    eyebrow: string;      // e.g. "Selection"
    title: React.ReactNode;
    body: React.ReactNode;
    visual: React.ReactNode;
    reverse?: boolean;    // swap visual to the left column on md+
    accent?: boolean;     // adds the teal/rust gradient halo behind the visual
  }
  ```
- **Children expected:** all content comes through props (`title`, `body`, `visual`).
- **External deps:** `Reveal`.
- **Used by:** [`page.tsx:129-201`](../site/app/page.tsx#L129) — five invocations, one per feature.
- **Visual purpose:** The repeating 2-column feature template (eyebrow + numeric tag + display title + body + visual), wrapped in scroll-reveal.
- **Reuse potential:** Could be extracted to `components/FeatureRow.tsx` if a second page ever shares this pattern; currently kept inline because it's used in exactly one place.

### `Detail` (helper, private to `page.tsx`)
- **File:** [`site/app/page.tsx:602`](../site/app/page.tsx#L602)
- **Kind:** local function component.
- **Server / Client:** **Server**.
- **Props:** `{ label: string; value: string }`.
- **External deps:** none.
- **Used by:** [`page.tsx:341-343`](../site/app/page.tsx#L341) — three pills in the Install section ("Updates", "Min macOS", "License").
- **Visual purpose:** Small ringed pill with uppercase mono label + display value, styled for the dark Install background.
- **Reuse potential:** One-off. If the dark style is ever reused, lift it out.

### `Nav`
- **File:** [`site/components/Nav.tsx:14`](../site/components/Nav.tsx#L14)
- **Kind:** named export.
- **Server / Client:** **Client** (`"use client"` at [`Nav.tsx:1`](../site/components/Nav.tsx#L1)).
- **Props:** `{ starSlot?: React.ReactNode }`.
- **Children expected:** none directly (children passed via `starSlot`).
- **External deps:** `MynaMark`, `MynaWordmark`, `GitHubStarButton` (the last is only referenced by the imports, not actually rendered — `starSlot` is passed from `page.tsx`).
- **Used by:** [`page.tsx:22`](../site/app/page.tsx#L22).
- **Visual purpose:** Sticky top nav with logo, primary section links (md+), install CTA (md+), live GitHub star button (sm+), and a mobile hamburger that opens a backdrop-blur drawer.
- **Reuse potential:** One-off — the `SECTIONS` constant ([`Nav.tsx:7`](../site/components/Nav.tsx#L7)) is hard-coded.

> Heads-up: `GitHubStarButton` is imported in [`Nav.tsx:5`](../site/components/Nav.tsx#L5) but never used. The actual star button comes through `starSlot`. Worth removing the dead import.

---

## Hero / visuals

### `MynaMark`
- **File:** [`site/components/MynaMark.tsx:9`](../site/components/MynaMark.tsx#L9)
- **Kind:** named export.
- **Server / Client:** **Server**.
- **Props:** `{ className?: string; size?: number }` (default `size = 28`).
- **External deps:** none.
- **Used by:** `Nav` (header + drawer), `page.tsx` (closing CTA at [`page.tsx:517`](../site/app/page.tsx#L517) and footer at [`page.tsx:533`](../site/app/page.tsx#L533)), `MenubarMockup` (menubar icon at [`MenubarMockup.tsx:32`](../site/components/MenubarMockup.tsx#L32)).
- **Visual purpose:** Hand-drawn 64×64 SVG of a myna bird (ink-black body, teal neck sheen, yellow eye ring, orange beak).
- **Reuse potential:** Brand mark — already correctly centralised; reuse anywhere a logo is needed.

### `MynaWordmark`
- **File:** [`site/components/MynaMark.tsx:48`](../site/components/MynaMark.tsx#L48)
- **Kind:** named export.
- **Server / Client:** **Server**.
- **Props:** `{ className?: string }`.
- **External deps:** none.
- **Used by:** `Nav` ([`Nav.tsx:47`](../site/components/Nav.tsx#L47)).
- **Visual purpose:** "Myna" text in Fraunces display medium, used inline with the mark.
- **Reuse potential:** Brand wordmark — central.

### `MenubarMockup`
- **File:** [`site/components/MenubarMockup.tsx:12`](../site/components/MenubarMockup.tsx#L12)
- **Kind:** named export.
- **Server / Client:** **Client** (`"use client"` — though it does no client-only work itself; see [Architecture §13](./architecture-site.md#13-risks--open-questions)).
- **Props:** `{ className?: string }`.
- **External deps:** `Soundwave`, `MynaMark`.
- **Used by:** [`page.tsx:88`](../site/app/page.tsx#L88) (hero only).
- **Visual purpose:** The hero — fakes the macOS menu-bar + a dropdown panel mid-playback (now-playing strip, progress wave, Claude Code queue of 3, footer with speed/voice/shortcuts).
- **Reuse potential:** Hero-specific; not reusable.

### `Soundwave`
- **File:** [`site/components/Soundwave.tsx:27`](../site/components/Soundwave.tsx#L27)
- **Kind:** named export.
- **Server / Client:** **Client** (`"use client"` — needs `useState` to seed deterministic bar profile, avoids hydration mismatch).
- **Props:**
  ```ts
  {
    bars?: number;        // default 28
    className?: string;
    pace?: number;        // default 1 — speed multiplier
    height?: number;      // default 56 (px)
    min?: number;         // default 6 (px) — minimum bar height
    barWidth?: number;    // default 3 (px)
    gap?: number;         // default 6 (px)
  }
  ```
- **External deps:** none.
- **Used by:** `MenubarMockup` (3× with different bar/pace), `SelectionVisual`, `ClaudeSessionsVisual`.
- **Visual purpose:** Warm, organic CSS-animated waveform driven by sine-based seeded profile. Drives the menubar "playing" indicator, the selection visual chord card, and the Claude session "now playing" icon.
- **Reuse potential:** **High** — already parameterised; reuse anywhere a waveform indicator is needed.

### `StaticWave`
- **File:** [`site/components/Soundwave.tsx:86`](../site/components/Soundwave.tsx#L86)
- **Kind:** named export.
- **Server / Client:** **Server** (pure SVG, no hooks).
- **Props:** `{ className?: string; bars?: number; height?: number }` (defaults 40, 36).
- **External deps:** none.
- **Used by:** [`page.tsx:123`](../site/app/page.tsx#L123) (features section header decoration only).
- **Visual purpose:** Rest-state, non-animated waveform decoration — used when motion would be noise (or when prefers-reduced-motion applies).
- **Reuse potential:** **High** for static contexts.

### `SelectionVisual`
- **File:** [`site/components/SelectionVisual.tsx:8`](../site/components/SelectionVisual.tsx#L8)
- **Kind:** named export.
- **Server / Client:** **Server**.
- **Props:** `{ className?: string }`.
- **External deps:** `Kbd`, `Soundwave`.
- **Used by:** [`page.tsx:139`](../site/app/page.tsx#L139) (feature 01 — Selection).
- **Visual purpose:** Mock browser window with an essay paragraph, a teal-highlighted selection, and a floating chord card bottom-right.
- **Reuse potential:** One-off feature illustration.

### `ArticleVisual`
- **File:** [`site/components/ArticleVisual.tsx:8`](../site/components/ArticleVisual.tsx#L8)
- **Kind:** named export.
- **Server / Client:** **Server**.
- **Props:** `{ className?: string }`.
- **External deps:** `Kbd`.
- **Used by:** [`page.tsx:152`](../site/app/page.tsx#L152) (feature 02 — The Web).
- **Visual purpose:** Side-by-side messy-vs-clean article cards with a centered `Kbd` chord card showing `⌘⌥⇧R`.
- **Reuse potential:** One-off.

### `ClaudeSessionsVisual`
- **File:** [`site/components/ClaudeSessionsVisual.tsx:7`](../site/components/ClaudeSessionsVisual.tsx#L7)
- **Kind:** named export.
- **Server / Client:** **Server** (composes client `Soundwave`).
- **Props:** `{ className?: string }`.
- **External deps:** `Soundwave`.
- **Used by:** [`page.tsx:167`](../site/app/page.tsx#L167) (feature 03 — Claude Code).
- **Visual purpose:** Dark-card queue UI: 1 playing (teal highlight, wave), 3 waiting (muted dots), 1 heard (strikethrough + checkmark).
- **Reuse potential:** One-off.

### `ControlVisual`
- **File:** [`site/components/ControlVisual.tsx:11`](../site/components/ControlVisual.tsx#L11)
- **Kind:** named export.
- **Server / Client:** **Server**.
- **Props:** `{ className?: string }`.
- **External deps:** `Kbd`.
- **Used by:** [`page.tsx:183`](../site/app/page.tsx#L183) (feature 04 — Control).
- **Visual purpose:** Fake "Customise Shortcuts" pane mimicking the macOS Settings shortcut UI.
- **Reuse potential:** One-off (overlaps with the live shortcuts table at [`page.tsx:472`](../site/app/page.tsx#L472) — same content, different framing).

### `PrivacyVisual`
- **File:** [`site/components/PrivacyVisual.tsx:6`](../site/components/PrivacyVisual.tsx#L6)
- **Kind:** named export.
- **Server / Client:** **Server**.
- **Props:** `{ className?: string }`.
- **External deps:** none.
- **Used by:** [`page.tsx:200`](../site/app/page.tsx#L200) (feature 05 — Private).
- **Visual purpose:** Mac silhouette enclosing three "local" pills (Kokoro voice / Qwen summary / Daemon + UI) plus a dashed line to a "cloud TTS" pill terminated with a rust X.
- **Reuse potential:** One-off.

### `ArchitectureDiagram`
- **File:** [`site/components/ArchitectureDiagram.tsx:6`](../site/components/ArchitectureDiagram.tsx#L6)
- **Kind:** named export.
- **Server / Client:** **Server**.
- **Props:** none.
- **External deps:** none.
- **Used by:** [`page.tsx:225`](../site/app/page.tsx#L225) (How it works section).
- **Visual purpose:** Three-step App → Daemon → Voice ordered list with adaptive connecting line (vertical on mobile, horizontal on desktop).
- **Reuse potential:** One-off, but the connector pattern (CSS-only gradient line behind grid items) is reusable.

---

## Interactive

### `Reveal`
- **File:** [`site/components/Reveal.tsx:16`](../site/components/Reveal.tsx#L16)
- **Kind:** named export.
- **Server / Client:** **Client** (`"use client"` for `useEffect` + `IntersectionObserver`).
- **Props:** `{ children: React.ReactNode; delay?: number; className?: string }`.
- **Children expected:** any.
- **External deps:** none (uses native `IntersectionObserver` + `window.matchMedia`).
- **Used by:** wraps almost every section in `page.tsx` and `FeatureRow` ([`page.tsx:98, 112, 210, 224, 233, 263, 283, 300, 339, 353, 370, 443, 456, 471, 496, 506, 515, 574`](../site/app/page.tsx)).
- **Visual purpose:** Fade-up on scroll entry; respects `prefers-reduced-motion` (no animation, immediately visible).
- **Reuse potential:** **High** — generic scroll-reveal primitive.

### `FAQ`
- **File:** [`site/components/FAQ.tsx:50`](../site/components/FAQ.tsx#L50)
- **Kind:** named export.
- **Server / Client:** **Client** (accordion state).
- **Props:** none (content is static `ITEMS` constant at [`FAQ.tsx:7`](../site/components/FAQ.tsx#L7)).
- **External deps:** none.
- **Used by:** [`page.tsx:507`](../site/app/page.tsx#L507).
- **Visual purpose:** 10-question accordion. First item opens by default. Animates with `grid-template-rows: 0fr → 1fr` for smooth height transition without measuring.
- **Reuse potential:** Currently couples content + chrome. If the chrome is ever reused, extract `<Accordion items={...} />` and feed `ITEMS` as a prop.

### `CopyBlock`
- **File:** [`site/components/CopyBlock.tsx:13`](../site/components/CopyBlock.tsx#L13)
- **Kind:** named export.
- **Server / Client:** **Client** (clipboard API + toast state).
- **Props:**
  ```ts
  {
    lines: { prompt?: boolean; text: string; comment?: boolean }[];
    className?: string;
    label?: string;       // when provided, copy button moves to the header row
  }
  ```
- **Children expected:** none; everything comes through `lines`.
- **External deps:** none.
- **Used by:** [`page.tsx:303, 315, 326`](../site/app/page.tsx#L303) (three install blocks: brew, dmg, ollama).
- **Visual purpose:** Dark code-block card with syntax-coloured prompts (`$`), comments (`#`), and a tap-to-copy button that shows "copied ✓" for 1.8s.
- **Reuse potential:** **High** — already parameterised cleanly.

### `GitHubStarButton`
- **File:** [`site/components/GitHubStar.tsx:37`](../site/components/GitHubStar.tsx#L37)
- **Kind:** named export.
- **Server / Client:** **Server** (async; uses Next `fetch` with `revalidate: 600`).
- **Props:** `{ compact?: boolean }` (default `false`).
- **Children expected:** none.
- **External deps:** none (uses native `fetch`); internally uses `Suspense` + an internal `StarCount` async sub-component.
- **Used by:** [`page.tsx:22`](../site/app/page.tsx#L22) (passed as `Nav`'s `starSlot`).
- **Visual purpose:** Cream rounded pill with GitHub logo + rust star icon + live count ("1.5k" formatting >1000); link to repo.
- **Reuse potential:** **High** — would work in any docs site that links to a GitHub repo. The `REPO` constant at [`GitHubStar.tsx:3`](../site/components/GitHubStar.tsx#L3) would need to become a prop.

### `MobileStickyCTA`
- **File:** [`site/components/MobileStickyCTA.tsx:9`](../site/components/MobileStickyCTA.tsx#L9)
- **Kind:** named export.
- **Server / Client:** **Client** (scroll listener).
- **Props:** none.
- **External deps:** none.
- **Used by:** [`page.tsx:549`](../site/app/page.tsx#L549) (only — imported again at [`page.tsx:613`](../site/app/page.tsx#L613); see note).
- **Visual purpose:** Mobile-only sticky pill that fades in past 70% viewport scroll and hides once the install section is in view.
- **Reuse potential:** One-off; the show/hide rules are tied to the `#install` anchor id.

> Note: `MobileStickyCTA` is imported at the **bottom** of `page.tsx` ([`page.tsx:613`](../site/app/page.tsx#L613)), after the function definition. Stylistic oddity, not a bug — TS hoists the import either way.

---

## Content primitives

### `Kbd`
- **File:** [`site/components/Kbd.tsx:25`](../site/components/Kbd.tsx#L25)
- **Kind:** named export.
- **Server / Client:** **Server** (pure markup).
- **Props:** `{ keys: string[]; className?: string }`.
- **Children expected:** none.
- **External deps:** none.
- **Used by:** `SelectionVisual`, `ArticleVisual`, `ControlVisual`, `FAQ` (inline mentions of `⌘⌥⇧S`), `page.tsx` (FeatureRow bodies + shortcuts table at [`page.tsx:475-485`](../site/app/page.tsx#L475)).
- **Visual purpose:** Renders a row of macOS-style key caps (`⌘ ⌥ ⇧ S` etc.) using semantic `<kbd>` elements. Lookup map at [`Kbd.tsx:3`](../site/components/Kbd.tsx#L3) translates modifier names to Unicode symbols.
- **Reuse potential:** **High** — well-factored primitive, no Myna-specific assumptions.

---

## Public assets

### `favicon.svg`
- **File:** [`site/public/favicon.svg`](../site/public/favicon.svg) — 8 lines.
- **Used by:** wired in `Metadata.icons.icon` ([`layout.tsx:48-50`](../site/app/layout.tsx#L48)).
- **Visual purpose:** 64×64 myna mark on cream rounded square — same palette as the in-app mark.

---

## Quick-glance matrix

| Component | Client? | Has state? | DOM/Window? | External net? | Reuse score |
|---|:-:|:-:|:-:|:-:|:-:|
| `RootLayout` |  |  |  |  | — |
| `Page` |  |  |  |  | — |
| `Nav` | ✓ | ✓ | ✓ |  | low |
| `MynaMark` |  |  |  |  | **high** |
| `MynaWordmark` |  |  |  |  | **high** |
| `MenubarMockup` | ✓ |  |  |  | low |
| `Soundwave` | ✓ | ✓ |  |  | **high** |
| `StaticWave` |  |  |  |  | **high** |
| `SelectionVisual` |  |  |  |  | low |
| `ArticleVisual` |  |  |  |  | low |
| `ClaudeSessionsVisual` |  |  |  |  | low |
| `ControlVisual` |  |  |  |  | low |
| `PrivacyVisual` |  |  |  |  | low |
| `ArchitectureDiagram` |  |  |  |  | low |
| `Reveal` | ✓ | ✓ | ✓ |  | **high** |
| `FAQ` | ✓ | ✓ |  |  | med |
| `CopyBlock` | ✓ | ✓ | ✓ |  | **high** |
| `GitHubStarButton` |  | (server) |  | ✓ (api.github.com) | med |
| `MobileStickyCTA` | ✓ | ✓ | ✓ |  | low |
| `Kbd` |  |  |  |  | **high** |

---
