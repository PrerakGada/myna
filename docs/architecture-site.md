# Myna — Marketing Site Architecture

> Lane C of the Myna documentation set. Covers the Next.js 16 marketing/landing site at `site/`.

---

## 1. Executive Summary

`site/` is the **single-page marketing site** for Myna — a free, open-source native macOS menu-bar TTS app. It exists to:

- Sell the product (hero → features → install) in a deliberately editorial, non-SaaS register;
- Surface a live install path (Homebrew cask + DMG) with copy-to-clipboard blocks;
- Show, via hand-drawn SVG + CSS, what Myna actually looks and feels like (menubar mockup, Claude Code queue, article extractor, shortcut table);
- Carry the brand identity ("Warm Reading Room") that links README, app, and tap.

It is **statically generated** by Next.js 16 (App Router) and **deployed on Vercel** from `site/` as the root directory. There is no database, no auth, no API route, no environment variable. The only outbound network call at render time is a cached fetch to `api.github.com` for the live star count. Aesthetic intent and feature list are anchored in [`site/README.md:7`](../site/README.md#L7) and [`site/README.md:78`](../site/README.md#L78).

Target domain (from metadata base): **myna.dev** ([`site/app/layout.tsx:28`](../site/app/layout.tsx#L28)).

---

## 2. Technology Stack

| Layer | Choice | Source |
|---|---|---|
| Framework | **Next.js 16.2.6** (App Router) | [`site/package.json:13`](../site/package.json#L13) |
| Runtime | **React 19 / React DOM 19** | [`site/package.json:14-15`](../site/package.json#L14) |
| Language | **TypeScript 5.7** (`strict: true`, `target: ES2022`, `moduleResolution: bundler`) | [`site/tsconfig.json:3`](../site/tsconfig.json#L3) |
| Styling | **Tailwind CSS 3.4.16** + bespoke globals.css | [`site/package.json:23`](../site/package.json#L23) · [`site/app/globals.css`](../site/app/globals.css) |
| PostCSS | `postcss` 8.4 + `autoprefixer` 10.4 | [`site/postcss.config.mjs`](../site/postcss.config.mjs) |
| Fonts | `next/font/google` self-hosting **Fraunces, Newsreader, JetBrains Mono** | [`site/app/layout.tsx:2`](../site/app/layout.tsx#L2) |
| Hosting | **Vercel** (framework auto-detected as `nextjs`, root = `site/`) | [`site/vercel.json:3`](../site/vercel.json#L3) |
| Build hint | `experimental.optimizePackageImports: ["motion"]` (no actual `motion` dep installed — see Risks §13) | [`site/next.config.mjs:7`](../site/next.config.mjs#L7) |

There are **zero client-side animation libraries**. All motion is CSS keyframes (defined in [`site/tailwind.config.ts:40`](../site/tailwind.config.ts#L40)) and one `IntersectionObserver` in `Reveal.tsx`. There are zero third-party React component libraries. The runtime dependency footprint is `next + react + react-dom`.

---

## 3. Routing

The site is a **single page**:

- [`site/app/layout.tsx`](../site/app/layout.tsx) — root layout (fonts, metadata, viewport, grain overlay, `<html lang="en">`).
- [`site/app/page.tsx`](../site/app/page.tsx) — the entire landing page; ~550 lines including two local helper components (`FeatureRow`, `Detail`).
- [`site/app/globals.css`](../site/app/globals.css) — design tokens, button styles, kbd chips, paper-grain backgrounds, reveal-on-scroll keyframes.

There are no API routes (`app/api/*` does not exist), no dynamic segments, no parallel routes, no intercepting routes, no middleware, no server actions. In-page navigation is hash anchors: `#top`, `#features`, `#how`, `#install`, `#platforms`, `#faq` ([`site/app/page.tsx:21`](../site/app/page.tsx#L21) and `<a href="#..."` throughout).

---

## 4. Rendering Strategy

Next 16 App Router defaults to **React Server Components**. Everything is rendered on the server at build time except components that explicitly opt in with `"use client"`.

### Server components (rendered to HTML, zero JS shipped to client)

| File | Reason it stays on the server |
|---|---|
| [`app/layout.tsx`](../site/app/layout.tsx) | Static shell; sets up fonts and metadata. |
| [`app/page.tsx`](../site/app/page.tsx) | Static composition. Imports a mix of server + client children. |
| [`components/MynaMark.tsx`](../site/components/MynaMark.tsx) | Pure SVG. |
| [`components/Kbd.tsx`](../site/components/Kbd.tsx) | Pure markup. |
| [`components/ArchitectureDiagram.tsx`](../site/components/ArchitectureDiagram.tsx) | Static layout. |
| [`components/ArticleVisual.tsx`](../site/components/ArticleVisual.tsx) | Static SVG/divs. |
| [`components/ClaudeSessionsVisual.tsx`](../site/components/ClaudeSessionsVisual.tsx) | Imports `Soundwave` (client) but is itself static. |
| [`components/ControlVisual.tsx`](../site/components/ControlVisual.tsx) | Static. |
| [`components/PrivacyVisual.tsx`](../site/components/PrivacyVisual.tsx) | Static. |
| [`components/SelectionVisual.tsx`](../site/components/SelectionVisual.tsx) | Static (imports `Soundwave` client child). |
| [`components/GitHubStar.tsx`](../site/components/GitHubStar.tsx) | **Async Server Component** — `fetch` with `next: { revalidate: 600 }` for ISR. |
| `StaticWave` inside [`components/Soundwave.tsx`](../site/components/Soundwave.tsx) | Named export; pure SVG. |

### Client components (`"use client"` at the top — interactive or DOM-aware)

| File | Why it needs the client |
|---|---|
| [`components/Nav.tsx`](../site/components/Nav.tsx#L1) | `scroll` listener (sticky-style change), mobile drawer state, body-scroll lock. |
| [`components/Soundwave.tsx`](../site/components/Soundwave.tsx#L1) | `useState` to deterministically seed bar profiles (server/client byte-identical). |
| [`components/Reveal.tsx`](../site/components/Reveal.tsx#L1) | `IntersectionObserver` + `prefers-reduced-motion` matchMedia. |
| [`components/FAQ.tsx`](../site/components/FAQ.tsx#L1) | Accordion open/close state. |
| [`components/CopyBlock.tsx`](../site/components/CopyBlock.tsx#L1) | `navigator.clipboard.writeText`, "copied ✓" toast state. |
| [`components/MenubarMockup.tsx`](../site/components/MenubarMockup.tsx#L1) | Marked client (composes client `Soundwave`); arguably could be server since itself has no interactivity. |
| [`components/MobileStickyCTA.tsx`](../site/components/MobileStickyCTA.tsx#L1) | `scrollY` listener to fade in past the hero. |

`GitHubStar.tsx` is the only data-fetching component. ISR cadence is 10 minutes (`revalidate: 600`), matching the README's stated caching policy. The build output is otherwise pure static HTML.

---

## 5. Component Composition (the visual narrative arc)

[`site/app/page.tsx`](../site/app/page.tsx) assembles the page top-to-bottom as a single editorial narrative:

```
Nav  (sticky, with starSlot = GitHubStarButton)
  │
  ├─ HERO  → MenubarMockup
  │
  ├─ HOOK  (single big balanced paragraph w/ dropcap)
  │
  ├─ FEATURES (No. I — five FeatureRow blocks alternating sides)
  │     01 Selection            → SelectionVisual
  │     02 The Web              → ArticleVisual           [reverse]
  │     03 Claude Code          → ClaudeSessionsVisual    [accent halo]
  │     04 Control              → ControlVisual           [reverse]
  │     05 Private              → PrivacyVisual
  │
  ├─ HOW IT WORKS (No. II)      → ArchitectureDiagram
  │
  ├─ WHY LOCAL (No. III)        → 3 cards (Privacy/Cost/Latency)
  │
  ├─ INSTALL (No. IV, dark)     → 3× CopyBlock (brew, dmg, ollama)
  │
  ├─ PLATFORMS (No. IV.b)       → 3 platform-status cards
  │
  ├─ SHORTCUTS TABLE            → Kbd rows
  │
  ├─ FAQ (No. V)                → FAQ
  │
  ├─ CLOSING                    → MynaMark + CTAs
  │
  ├─ FOOTER                     → MynaMark + nav links
  │
  └─ MobileStickyCTA  (fixed, mobile-only, appears past hero)
```

The pattern is editorial: each section has a `font-mono` eyebrow (`No. I · what it does`), a balanced Fraunces display headline, and a long-form Newsreader body. The `<Reveal>` wrapper provides scroll-triggered fade-up for almost every section.

`FeatureRow` (private to `page.tsx`, [`site/app/page.tsx:556`](../site/app/page.tsx#L556)) is a reusable two-column layout with optional `reverse` (visual on left) and `accent` (gradient halo behind the visual for the Claude Code section).

---

## 6. Component-by-Component Summary

### Layout & shell

#### `Nav` — [`site/components/Nav.tsx`](../site/components/Nav.tsx)
- **Kind:** named export, **client component**.
- **Props:** `{ starSlot?: React.ReactNode }` — slot for the live star button so the async server component can be passed down from the page.
- **External libs:** none.
- **Notable:** scroll listener swaps to `bg-paper/85 backdrop-blur-md` past 12px scroll; mobile burger flips into an X with two animated bars; off-canvas drawer locks `document.body.style.overflow`; sections list lives in a local constant ([`Nav.tsx:7`](../site/components/Nav.tsx#L7)). `safe-top` class respects `env(safe-area-inset-top)`.

#### `MynaMark` / `MynaWordmark` — [`site/components/MynaMark.tsx`](../site/components/MynaMark.tsx)
- **Kind:** two named exports, **server**.
- **Props:** `MynaMark { className?: string; size?: number }` (default 28); `MynaWordmark { className?: string }`.
- **Notable:** hand-drawn 64×64 SVG of a myna bird — body ink-black, teal neck sheen, yellow eye ring, orange beak. Used in nav, hero corner, closing, footer, mobile drawer.

### Hero & visuals

#### `MenubarMockup` — [`site/components/MenubarMockup.tsx`](../site/components/MenubarMockup.tsx)
- **Kind:** named export, **client** (probably unnecessary — composes `Soundwave` which is already client).
- **Props:** `{ className?: string }`.
- **Notable:** fakes the macOS menu-bar strip plus a dropdown showing "Now reading", playback controls, progress soundwave, and a 3-row Claude Code queue. Includes a hand-drawn dashed callout arrow on desktop only.

#### `Soundwave` + `StaticWave` — [`site/components/Soundwave.tsx`](../site/components/Soundwave.tsx)
- **Kind:** two named exports. `Soundwave` is **client**, `StaticWave` is **server** SVG.
- **Props (`Soundwave`):** `{ bars?, className?, pace?, height?, min?, barWidth?, gap? }` (all numeric, defaults documented in source).
- **Notable:** generates a seeded pseudo-random profile in `useState(() => ...)` so the SSR/client HTML is byte-identical (no hydration mismatch). Pure CSS animation drives each bar via inline `animationDuration` / `animationDelay`. Uses the `wave` keyframe from [`tailwind.config.ts:56`](../site/tailwind.config.ts#L56).

#### `SelectionVisual` — [`site/components/SelectionVisual.tsx`](../site/components/SelectionVisual.tsx)
- **Kind:** named export, **server**.
- **Props:** `{ className?: string }`.
- **Notable:** mock browser chrome + an essay paragraph with a teal-highlighted selection + a "speak it" pill bottom-right pairing `Kbd` and `Soundwave`.

#### `ArticleVisual` — [`site/components/ArticleVisual.tsx`](../site/components/ArticleVisual.tsx)
- **Kind:** named export, **server**.
- **Props:** `{ className?: string }`.
- **Notable:** side-by-side "messy article (ads, newsletter banner)" vs. "clean reading view with waveform" with a centered `Kbd` chord between them.

#### `ClaudeSessionsVisual` — [`site/components/ClaudeSessionsVisual.tsx`](../site/components/ClaudeSessionsVisual.tsx)
- **Kind:** named export, **server** (renders client `Soundwave`).
- **Props:** `{ className?: string }`.
- **Notable:** stylised "queue" UI showing 1 playing / 3 waiting / 1 heard; uses Soundwave for the playing state and an SVG checkmark for the heard state.

#### `ControlVisual` — [`site/components/ControlVisual.tsx`](../site/components/ControlVisual.tsx)
- **Kind:** named export, **server**.
- **Props:** `{ className?: string }`.
- **Notable:** fake "Customise Shortcuts" pane mimicking System Settings with all 5 shortcuts via `Kbd`.

#### `PrivacyVisual` — [`site/components/PrivacyVisual.tsx`](../site/components/PrivacyVisual.tsx)
- **Kind:** named export, **server**.
- **Props:** `{ className?: string }`.
- **Notable:** mac silhouette enclosing three "local" pills (Kokoro voice / Qwen summary / Daemon + UI) and a dashed line to a "cloud TTS" pill terminated by a red X.

#### `ArchitectureDiagram` — [`site/components/ArchitectureDiagram.tsx`](../site/components/ArchitectureDiagram.tsx)
- **Kind:** named export, **server**.
- **Props:** none.
- **Notable:** three-layer App → Daemon → Voice ordered list; pure CSS for both vertical (mobile) and horizontal (desktop) connecting lines.

### Interactive

#### `Reveal` — [`site/components/Reveal.tsx`](../site/components/Reveal.tsx)
- **Kind:** named export, **client**.
- **Props:** `{ children: ReactNode; delay?: number; className?: string }`.
- **Notable:** `IntersectionObserver` with `threshold: 0.12`, `rootMargin: "0px 0px -40px 0px"`. Auto-disables under `prefers-reduced-motion`. Adds `.in` class which is styled in `globals.css` (`.reveal` → `.reveal.in`).

#### `FAQ` — [`site/components/FAQ.tsx`](../site/components/FAQ.tsx)
- **Kind:** named export, **client**.
- **Props:** none (questions are a static module-scope constant `ITEMS` at [`FAQ.tsx:7`](../site/components/FAQ.tsx#L7)).
- **Notable:** controlled accordion (`useState<number | null>(0)`); animates open/close via `grid-template-rows: 0fr → 1fr` (CSS-only smooth height). 10 questions, first is open by default.

#### `CopyBlock` — [`site/components/CopyBlock.tsx`](../site/components/CopyBlock.tsx)
- **Kind:** named export, **client**.
- **Props:** `{ lines: Line[]; className?: string; label?: string }` where `Line = { prompt?: boolean; text: string; comment?: boolean }`.
- **Notable:** "copied ✓" toast resets after 1800ms. Comments serialise as `# ...`, prompts as `$ ...`. Two button placements depending on whether `label` is provided.

#### `GitHubStarButton` (+ internal `StarCount`) — [`site/components/GitHubStar.tsx`](../site/components/GitHubStar.tsx)
- **Kind:** named export, **server** (async).
- **Props:** `{ compact?: boolean }`.
- **Notable:** server-side `fetch("https://api.github.com/repos/PrerakGada/myna")` with `revalidate: 600`. Suspense fallback (`…`). Star count formatted with `1.5k` suffix above 1000. Returns `null` on failure (button still renders).

#### `MobileStickyCTA` — [`site/components/MobileStickyCTA.tsx`](../site/components/MobileStickyCTA.tsx)
- **Kind:** named export, **client**.
- **Props:** none.
- **Notable:** appears past 70% viewport scroll, hides again once the `#install` section is in the upper 70% of viewport. Respects `env(safe-area-inset-bottom)` via `.safe-bottom`.

### Primitives

#### `Kbd` — [`site/components/Kbd.tsx`](../site/components/Kbd.tsx)
- **Kind:** named export, **server**.
- **Props:** `{ keys: string[]; className?: string }`.
- **Notable:** lookup map turns `cmd → ⌘`, `alt → ⌥`, `shift → ⇧`, `ctrl → ⌃`, `space → Space`, `.` → uppercased literal. Renders semantic `<kbd>` per key. Visual chip styling lives in `.kbd` ([`globals.css:163`](../site/app/globals.css#L163)).

---

## 7. Tailwind Config — every customisation

Source: [`site/tailwind.config.ts`](../site/tailwind.config.ts).

**`content` scan:** `./app/**/*.{ts,tsx}`, `./components/**/*.{ts,tsx}` ([`tailwind.config.ts:4`](../site/tailwind.config.ts#L4)).

**Custom colors** (Warm Reading Room palette):

| Token | Value | Use |
|---|---|---|
| `paper.DEFAULT` | `#F5EFE2` | body background, base cream |
| `paper.deep` | `#EFE6D2` | slightly deeper cream (cards, alternating sections) |
| `paper.warm` | `#FBF6E9` | warmest highlight (cards, kbd chip top) |
| `ink.DEFAULT` | `#1A1714` | primary text (warm near-black) |
| `ink.soft` | `#3A332A` | body copy secondary |
| `ink.muted` | `#6B5F4F` | eyebrows, labels |
| `ink.faint` | `#A89880` | tertiary |
| `teal.DEFAULT` | `#0F6B5C` | accent — the "myna sheen" |
| `teal.deep` | `#0A4F44` | accent on light bg |
| `teal.bright` | `#1A9985` | brighter accent |
| `teal.glow` | `#3FBFA8` | accent on dark bg |
| `rust` | `#B65A3C` | dried-ink accent (eyebrows, numerals, dots) |

**Font families** (CSS variables wired up in `layout.tsx` via `next/font`):
- `display` → Fraunces, Georgia fallback
- `body` → Newsreader, Georgia fallback
- `mono` → JetBrains Mono, ui-monospace fallback

**Custom font sizes** (mobile-first responsive via `clamp()`):
- `display-xl` → `clamp(2.5rem, 9vw, 6.5rem)`, line-height 0.95, letter-spacing −0.03em
- `display-lg` → `clamp(2rem, 6vw, 4rem)`, line-height 1.02, letter-spacing −0.025em
- `display-md` → `clamp(1.5rem, 4vw, 2.5rem)`, line-height 1.1, letter-spacing −0.02em

**Custom animations & keyframes:**
- `wave-1` … `wave-5`, `wave-slow-1`/`-2`/`-3` — soundwave bars (keyframe `wave: scaleY(0.35 → 1 → 0.35)`)
- `fade-up` — 0.8s cubic-bezier; opacity 0→1, translateY 24px→0
- `fade-in` — 1.2s
- `marquee` — 40s linear infinite (translateX 0→−50%)
- `pulse-slow` — 4s opacity 0.4↔0.8
- `shimmer` — 3s backgroundPosition swing

**Custom box-shadows:**
- `page` — large drop for hero card
- `soft` — generic card shadow
- `chip` — inset ring + top highlight for star button and architecture nodes

**Plugins:** none.

---

## 8. Vercel Deployment

[`site/vercel.json`](../site/vercel.json) declares:

- `"framework": "nextjs"` — explicit so Vercel uses the Next.js builder
- `"buildCommand": "next build"`
- `"installCommand": "npm install"`
- Three response headers on `/(.*)`:
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Permissions-Policy: camera=(), microphone=(), geolocation=()`

There is no `outputDirectory` override; Next 16 + App Router produces a hybrid build (ISR for the page since `GitHubStar` opts into `revalidate: 600`). The README ([`site/README.md:27`](../site/README.md#L27)) describes it as "fully static" with a 10-minute revalidate — which matches.

Deploy modes:
- **Local:** `cd site && npx vercel` (preview) or `npx vercel --prod`.
- **GitHub-integrated:** push to `main`; configure Vercel project Root Directory = `site`; preview deploys per PR; production deploy on push to default branch.

No environment variables required. The Permissions-Policy correctly denies camera/mic/geolocation since the site has no use for them; cloud-TTS apologists denied. There is no CSP — see Risks §13.

---

## 9. SEO & Metadata

`Metadata` export at [`site/app/layout.tsx:27`](../site/app/layout.tsx#L27):

- `metadataBase: https://myna.dev` — the canonical production origin.
- `title`: `"Myna — A quiet voice for your Mac"`.
- `description`: 280 characters covering "free, open-source, native macOS menu-bar app … real audio engine, signed + notarised, auto-updating, runs entirely on Apple Silicon. No cloud, no cost, no noise."
- `openGraph`: type `website`, url `/`, siteName `Myna`, same title/description.
- `twitter`: `summary_large_image` (but no explicit OG image is configured — see Risks §13).
- `authors`: `[{ name: "Prerak Gada", url: "https://github.com/PrerakGada" }]`.
- `creator`: `"Prerak Gada"`.
- `icons.icon`: `/favicon.svg` ([`site/public/favicon.svg`](../site/public/favicon.svg), 8 lines — myna mark on cream rounded square).

`Viewport` export at [`site/app/layout.tsx:53`](../site/app/layout.tsx#L53):

- `themeColor: #F5EFE2` (matches `paper.DEFAULT` — the address bar tints to cream on mobile Safari/Chrome).
- `width: device-width`, `initialScale: 1`, `maximumScale: 5`.

No `robots.txt`, no `sitemap.xml`, no `manifest.json` ship from `public/` — only the favicon.

---

## 10. Accessibility Considerations

What's in place:
- `<html lang="en">` ([`layout.tsx:63`](../site/app/layout.tsx#L63)).
- Semantic landmarks: `<header>` and `<nav aria-label="Primary">` ([`Nav.tsx:37`](../site/components/Nav.tsx#L37)), `<main>` ([`page.tsx:21`](../site/app/page.tsx#L21)), `<footer>` ([`page.tsx:530`](../site/app/page.tsx#L530)).
- Semantic `<kbd>` for every key chip ([`Kbd.tsx:32`](../site/components/Kbd.tsx#L32)).
- `aria-label` on nav home link, mobile menu toggle, copy button (when no label), pause/stop buttons, and the GitHub star button.
- `aria-expanded` on FAQ toggles and mobile menu button.
- `aria-hidden="true"` on all decorative SVGs (`MynaMark`, soundwave bars, dropdown chrome dots, dashed callout arrows, the grain overlay div).
- `prefers-reduced-motion` respected globally in [`globals.css:11`](../site/app/globals.css#L11) (kills animations + smooth-scroll) and explicitly inside `Reveal` ([`Reveal.tsx:23`](../site/components/Reveal.tsx#L23)).
- `:focus-visible` style with teal outline + 3px offset ([`globals.css:211`](../site/app/globals.css#L211)).
- Touch targets are ≥ 44×44px — README states this is design-system policy; verified for buttons (`min-height: 48px` on `.btn-primary` / `.btn-ghost`, `h-11 w-11` on the burger).
- `safe-top`/`safe-bottom` utilities use `env(safe-area-inset-*)` for iOS notch/home-indicator.
- Body scroll lock when the mobile drawer is open.

Gaps (not necessarily bugs, but worth tracking):
- The mobile drawer doesn't trap focus, doesn't restore focus on close, and doesn't close on `Escape`.
- The FAQ accordion uses a `<button>` but lacks the WAI-ARIA `aria-controls` pointing at its panel id.
- Soundwave is `aria-hidden`, which is correct for decoration, but the menubar mockup carries no overall description — a screen-reader user gets no sense of what the hero visual conveys.
- No alt text strategy because there are zero `<img>` / `next/image` uses on the site — all visuals are inline SVG or styled divs.

---

## 11. Source Tree (`site/`, excluding `node_modules`, `.next`, `.vercel`)

```
site/
├── .gitignore
├── README.md
├── next-env.d.ts                         (auto-generated by Next)
├── next.config.mjs                       reactStrictMode, optimizePackageImports
├── package.json                          next 16.2.6, react 19, ts 5.7, tailwind 3.4
├── package-lock.json
├── postcss.config.mjs                    tailwindcss + autoprefixer
├── tailwind.config.ts                    Warm Reading Room tokens
├── tsconfig.json                         strict, ES2022, bundler resolution
├── tsconfig.tsbuildinfo                  (incremental TS cache; checked-in artefact)
├── vercel.json                           framework + 3 security headers
├── app/
│   ├── globals.css                       design tokens, kbd chips, paper grain, reveal kf
│   ├── layout.tsx                        fonts, metadata, viewport, grain overlay
│   └── page.tsx                          the whole landing page (FeatureRow + Detail inline)
├── components/                           15 .tsx files (see §6)
│   ├── ArchitectureDiagram.tsx
│   ├── ArticleVisual.tsx
│   ├── ClaudeSessionsVisual.tsx
│   ├── ControlVisual.tsx
│   ├── CopyBlock.tsx
│   ├── FAQ.tsx
│   ├── GitHubStar.tsx
│   ├── Kbd.tsx
│   ├── MenubarMockup.tsx
│   ├── MobileStickyCTA.tsx
│   ├── MynaMark.tsx
│   ├── Nav.tsx
│   ├── PrivacyVisual.tsx
│   ├── Reveal.tsx
│   ├── SelectionVisual.tsx
│   └── Soundwave.tsx
└── public/
    └── favicon.svg                       64x64 myna mark on cream
```

---

## 12. Testing Strategy

**There are none.** No `jest.config`, no `vitest`, no `playwright`, no `@testing-library/*`, no `__tests__` folder, no `e2e/` folder, no test script in `package.json` (the only scripts are `dev`, `build`, `start`, `lint`, `typecheck`).

Quality gates that *do* exist:
- `npm run typecheck` → `tsc --noEmit` (strict-mode TS catches prop misuse and unused symbols).
- `npm run lint` → `next lint` (default Next 16 ESLint config; no custom rules).
- The Next build itself fails on type errors and broken imports.

This is acceptable for a one-page brochure site, but worth calling out as the explicit gap. Candidates if testing is added later:
- Visual regression with Playwright + screenshot diffs (especially `MenubarMockup`, `ClaudeSessionsVisual`).
- A smoke test that the page server-renders successfully and the GitHub star button doesn't throw when the API is down.
- Lighthouse CI in the GitHub Actions or Vercel deploy hook for performance/a11y/SEO regressions.

---

## 13. Risks & Open Questions

**Devil's-advocate read:**

1. **`optimizePackageImports: ["motion"]` is a phantom.** [`next.config.mjs:7`](../site/next.config.mjs#L7) names a `motion` package that is not in `dependencies` or `devDependencies`. It's a harmless hint today (the optimiser just no-ops on a missing package) but it implies an earlier intent to use Framer Motion / `motion`. Remove if the design genuinely never needs JS-driven motion.
2. **React 19 + Next 16 are very fresh.** No semantic version pinning beyond a `^` caret. A minor Next bump might change `next/font` axis support (Fraunces uses `axes: ["SOFT", "opsz"]` — niche). Consider pinning exact versions or adding a `package-lock.json`-aware CI build to catch regressions.
3. **No CSP header.** `vercel.json` sets `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, but no `Content-Security-Policy`. Adding one is straightforward (single-origin, self) and would harden against accidental future XSS through user-supplied content.
4. **No OG image.** `twitter.card: summary_large_image` is set but no image URL anywhere. Link previews on Twitter/LinkedIn will fall back to the bare title. A static 1200×630 in `public/og.png` or a route handler at `app/opengraph-image.tsx` would close this.
5. **No `robots.txt` or `sitemap.xml`.** For a single-page brochure this is minor; Google will index from the title/description. If multiple pages are ever added, add them via `app/robots.ts` / `app/sitemap.ts`.
6. **`MobileStickyCTA` listens to every `scroll` event** (passive but unthrottled). On low-end Android this could be jittery. Throttling via `requestAnimationFrame` would be cheap insurance.
7. **GitHub star fetch failure is silent.** `getStars()` returns `null` on any error; the button renders without a count. There's no telemetry that would tell us if the GitHub API got rate-limited. If we ever care, log at the edge or use an unauthenticated `If-None-Match` cache header.
8. **`MenubarMockup` is marked `"use client"` for no obvious reason.** It composes the client `Soundwave` but contributes no interactivity itself. Could be a server component, shrinking the client bundle slightly.
9. **`tsconfig.tsbuildinfo` is checked in.** That's a 108KB incremental-build cache file — almost certainly accidental ([`git status` shows it as `M`](../site/tsconfig.tsbuildinfo)). It belongs in `.gitignore`. The current `.gitignore` covers `.next/`, `out/`, `.vercel`, `.turbo`, `node_modules/`, `.env*.local`, `.DS_Store`, `*.log` — but not `tsconfig.tsbuildinfo`.
10. **Bundle size is not measured.** No `@next/bundle-analyzer` integration. Given the site is intentionally minimal (zero third-party UI deps) this is fine, but adding the analyzer to `next.config.mjs` would surface any future regression cheaply.
11. **Edge runtime not configured.** Page renders as Node by default; `GitHubStar` fetch happens on the Node runtime at revalidate intervals. If the page were ever pushed to the edge for lower TTFB, the `fetch` would need to be reviewed (it's already standard `fetch`, so should be portable).
12. **"Pages Router idioms"** — none present. Everything is App Router idiomatic: server components by default, `"use client"` opt-in, `next/font/google` with CSS variables, route-level metadata via `export const metadata`.

---
