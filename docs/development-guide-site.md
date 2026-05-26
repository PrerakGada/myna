# Myna — Site Development Guide

> How to work on the Next.js 16 marketing site at [`site/`](../site). For an architectural overview see [`architecture-site.md`](./architecture-site.md); for per-component details see [`component-inventory-site.md`](./component-inventory-site.md).

---

## 1. Prerequisites

- **Node.js 18.18+** — Next.js 16 requires it; on Vercel the default Node runtime is `>= 20`, so 20 LTS is the recommended local match.
  - No `engines` field is declared in [`site/package.json`](../site/package.json) — adding one is a worthwhile hardening step.
- **npm** — `package-lock.json` is checked in, so `npm install` is the supported install path. pnpm/yarn would work but would drift the lockfile.
- **macOS / Linux / WSL** — nothing in the build is OS-specific.
- **A modern browser** for dev (Chrome / Safari / Firefox latest).

Optional:
- **Vercel CLI** (`npm i -g vercel`) for local preview deploys.

---

## 2. Install

```bash
cd site
npm install
```

This installs `next@^16.2.6`, `react@^19.0.0`, `react-dom@^19.0.0`, plus TypeScript, Tailwind, PostCSS, and autoprefixer. Total install is ~250 MB in `node_modules/`.

---

## 3. Dev server

```bash
npm run dev
# → http://localhost:3000
```

Runs `next dev`. Hot module reload is on by default. The first request triggers font fetches via `next/font/google` (cached after first build).

What's reactive in dev:
- Tailwind classes hot-reload because `app/**/*.{ts,tsx}` and `components/**/*.{ts,tsx}` are in the JIT content scan ([`tailwind.config.ts:4`](../site/tailwind.config.ts#L4)).
- `globals.css` edits hot-reload.
- React Server Components re-render on save; the GitHub star fetch is **not** re-evaluated on every request in dev (it respects `revalidate: 600` even locally).

---

## 4. Build

```bash
npm run build
```

Runs `next build`. Output goes to `site/.next/`. The page is prerendered with ISR (10-minute revalidate driven by `GitHubStar`'s fetch options). You should see one route in the build output:

```
Route (app)                              Size     First Load JS
○ /                                      …kB      …kB
```

`○` means static (with ISR). No dynamic routes, no API routes, no middleware.

---

## 5. Start

```bash
npm start
```

Runs `next start` against the compiled `.next/` output on port 3000. Use this to validate the production build locally before deploying.

---

## 6. Typecheck

```bash
npm run typecheck
```

Runs `tsc --noEmit`. `strict: true` is on in [`tsconfig.json`](../site/tsconfig.json), so all checks are enforced (no implicit `any`, strict null checks, etc.).

Incremental compile cache lives in `site/tsconfig.tsbuildinfo` — it speeds up local typechecks but **should not be committed**; add to `.gitignore` (see [`architecture-site.md` §13](./architecture-site.md#13-risks--open-questions)).

---

## 7. Lint

```bash
npm run lint
```

Runs `next lint` with the default `next/core-web-vitals` ESLint preset. There is no custom `.eslintrc*` file; whatever Next ships in 16.x is what runs.

---

## 8. Deploy to Vercel

[`site/vercel.json`](../site/vercel.json) sets `framework: nextjs`, `buildCommand: next build`, `installCommand: npm install`, and three security headers on every response.

### Local one-off deploy

```bash
cd site
npx vercel              # preview deploy
npx vercel --prod       # production deploy (after preview looks right)
```

### Git-integrated (recommended)

1. In the Vercel dashboard, import `PrerakGada/myna`.
2. Set **Root Directory** = `site`.
3. Accept Next.js detected settings.
4. Push to `main` → production deploy. Open a PR → preview deploy with a unique URL.

### Environment variables

**None required.** The site has no auth, no analytics, no third-party services. The only outbound network call is the unauthenticated GitHub API call in [`GitHubStar.tsx:7`](../site/components/GitHubStar.tsx#L7), cached for 10 minutes via `next: { revalidate: 600 }`.

If you ever want to add Plausible/Vercel Analytics/etc., add them via env vars and document them here.

### Custom domain

Production domain assumed to be **`myna.dev`** based on `metadataBase: new URL("https://myna.dev")` ([`layout.tsx:28`](../site/app/layout.tsx#L28)). Wire the domain through the Vercel project settings.

---

## 9. Adding a new component

1. Create `site/components/MyThing.tsx`.
2. Decide whether it's a **server** or **client** component:
   - **Default = server.** Don't add `"use client"`.
   - Add `"use client"` only if the component needs: `useState`, `useEffect`, `useRef`, `useLayoutEffect`, `useContext`, event handlers, browser globals (`window`, `document`, `localStorage`, `IntersectionObserver`, `navigator`), or it composes a third-party library that does any of the above.
3. Match the existing convention:
   - Default export only when it's a route. Otherwise prefer **named** exports.
   - Always accept an optional `className` prop for caller composition.
   - Tailwind classes only — no inline `style={{}}` except for animation timing or CSS variables (see [`Soundwave.tsx:66`](../site/components/Soundwave.tsx#L66) for the canonical example of acceptable inline style).
4. Import into `page.tsx`:
   ```tsx
   import { MyThing } from "@/components/MyThing";
   ```
   The `@/*` alias is wired in [`tsconfig.json:25`](../site/tsconfig.json#L25).
5. If your component needs scroll-reveal, wrap it in `<Reveal>` rather than implementing it again.
6. If it accepts user interaction, define a strict TS `Props` type — never `any`.

### Server-component check

If you accidentally use a hook in a file without `"use client"`, the Next build fails with:

```
You're importing a component that needs `useState`. It only works in a Client Component but none of its parents are marked with "use client" …
```

Fix by adding `"use client";` to the file's first line.

---

## 10. Adding a new section to `page.tsx`

Sections follow a consistent editorial template:

```tsx
<section id="my-section" className="relative py-24 sm:py-32">
  <div className="mx-auto max-w-6xl px-5 sm:px-8">
    <Reveal>
      <div className="mb-14 sm:mb-20 max-w-3xl">
        <div className="font-mono text-[0.72rem] uppercase tracking-[0.22em] text-ink-muted mb-3">
          No. VI · my section
        </div>
        <h2 className="font-display text-display-lg text-ink balance">
          Headline here,<br/>
          <span className="italic text-teal-deep">italic accent.</span>
        </h2>
        <p className="mt-5 text-[1.05rem] leading-[1.65] text-ink-soft max-w-[52ch] pretty">
          Body copy.
        </p>
      </div>
    </Reveal>

    <Reveal delay={80}>
      {/* … your content … */}
    </Reveal>
  </div>
</section>
```

Conventions to keep:
- Mobile-first responsive (`px-5 sm:px-8`, `py-24 sm:py-32`).
- Wrap in `<Reveal>` for the fade-up entry; stagger child reveals with `delay={80}` (ms) increments.
- Use the design tokens (`text-ink`, `text-ink-soft`, `text-ink-muted`, `text-teal-deep`, `text-rust`) — don't introduce raw hex values.
- Use `.balance` on display headlines and `.pretty` on body paragraphs ([`globals.css:222`](../site/app/globals.css#L222)).
- Add the section id to the `SECTIONS` constant in [`Nav.tsx:7`](../site/components/Nav.tsx#L7) if you want it in the nav.
- Add an anchor link from the closing CTA or footer if it's a primary section.

---

## 11. Updating site copy

- **Hero / section body copy:** edit directly in [`site/app/page.tsx`](../site/app/page.tsx). Each section is inline (intentional — easier to see the editorial flow as one document).
- **FAQ:** edit the `ITEMS` constant at [`FAQ.tsx:7`](../site/components/FAQ.tsx#L7). Answers accept React nodes, so `<span className="font-mono text-ink-soft">⌘⌥⇧S</span>` etc. work inline.
- **Install commands:** edit the three `<CopyBlock>` invocations at [`page.tsx:303`](../site/app/page.tsx#L303), [`page.tsx:315`](../site/app/page.tsx#L315), [`page.tsx:326`](../site/app/page.tsx#L326).
- **Nav sections:** edit `SECTIONS` in [`Nav.tsx:7`](../site/components/Nav.tsx#L7).
- **Shortcuts table:** edit the inline array at [`page.tsx:474-480`](../site/app/page.tsx#L474). The `ControlVisual` mock has its own copy at [`ControlVisual.tsx:3`](../site/components/ControlVisual.tsx#L3) — keep them in sync if you change defaults.
- **Metadata (title/description/OG):** edit `metadata` in [`layout.tsx:27`](../site/app/layout.tsx#L27).
- **Brand colours/fonts:** edit [`tailwind.config.ts`](../site/tailwind.config.ts).

---

## 12. Performance

### Image strategy

There are **no `<img>` tags and no `next/image` usage anywhere on the site.** Every visual is either inline SVG or styled `<div>`s with Tailwind. This keeps the page weight tiny (no image bytes, no CLS from late-loading images, no LCP image to optimise) but means:

- You **don't need** the `images` config in `next.config.mjs`.
- If you ever add a real image (e.g. an OG card, a screenshot), use `next/image` for automatic sizing and lazy loading.

### Fonts

Self-hosted via `next/font/google` with `display: "swap"` ([`layout.tsx:5-25`](../site/app/layout.tsx#L5)) — no FOIT, no extra network calls to fonts.googleapis.com. Fraunces explicitly requests `SOFT` and `opsz` axes, Newsreader requests normal + italic styles, JetBrains Mono requests weights 400 + 500. Only what's needed is downloaded.

### Bundle analysis

There is no bundle analyzer wired in. To inspect bundle size ad-hoc:

```bash
cd site
ANALYZE=true npm run build
```

— but you'll first need to wrap `next.config.mjs` with `@next/bundle-analyzer`. A minimal change:

```js
import bundleAnalyzer from "@next/bundle-analyzer";
const withBundleAnalyzer = bundleAnalyzer({ enabled: process.env.ANALYZE === "true" });
export default withBundleAnalyzer(nextConfig);
```

`@next/bundle-analyzer` is not currently a devDependency; add it if you need this.

### Other perf-relevant settings

- `reactStrictMode: true` ([`next.config.mjs:3`](../site/next.config.mjs#L3)) — strict mode in dev catches side-effect bugs.
- `poweredByHeader: false` ([`next.config.mjs:4`](../site/next.config.mjs#L4)) — drops `X-Powered-By: Next.js` from responses (minor hardening).
- `compress: true` ([`next.config.mjs:5`](../site/next.config.mjs#L5)) — gzip in self-hosted; on Vercel the edge handles compression anyway.
- `experimental.optimizePackageImports: ["motion"]` — currently a no-op because `motion` is not installed. Remove or actually install it.

---

## 13. Common pitfalls

1. **Forgetting `"use client"` on a hook-using file** → Next build fails. Add the directive to the file's first line.
2. **Hydration mismatch** — easy to introduce by reading `window` / `Date.now()` / `Math.random()` during render. The site already handles this correctly:
   - `Soundwave` uses a seeded sine-wave profile so server and client compute identical values ([`Soundwave.tsx:39`](../site/components/Soundwave.tsx#L39)).
   - `Reveal` only touches `window` inside `useEffect` ([`Reveal.tsx:20`](../site/components/Reveal.tsx#L20)).
   - `Nav` and `MobileStickyCTA` do the same.
   - **Don't break this pattern.** If a new component needs random data or timestamps, generate them in `useEffect`/`useState(() => …)` not at module scope.
3. **Tailwind purge surprises** — class names must appear as **literal strings** in source for Tailwind to keep them. Don't do `` className={`text-${variant}-deep`} `` — Tailwind can't see it. Use a lookup map of literal class names instead.
4. **Client-component bloat** — every `"use client"` ships its (transitive) imports to the browser. Keep client components small and at the leaves. The current layout is good: `Reveal`, `FAQ`, `CopyBlock`, `Nav`, `MobileStickyCTA`, `Soundwave` are client; everything else is server.
5. **`MenubarMockup` is marked client without needing to be** ([`MenubarMockup.tsx:1`](../site/components/MenubarMockup.tsx#L1)) — it just composes the client `Soundwave`. If you touch the file, consider whether the directive is still needed (its parent already being a server component is enough for the boundary).
6. **The GitHub star button is server-rendered with ISR.** Don't move its `fetch` to a client `useEffect` — you'd lose the cache and add a render flash. If you need a "refresh now" button, add a route handler that re-validates the path.
7. **CSS keyframe names live in `tailwind.config.ts`, not in `globals.css`.** If you add an animation, declare both the `keyframes` and `animation` blocks ([`tailwind.config.ts:40-80`](../site/tailwind.config.ts#L40)). One exception: the bare `wave` keyframe is also referenced by inline `style={{ animationName: 'wave' }}` in `Soundwave`, which still resolves because Tailwind injects `@keyframes wave` into the stylesheet from the `keyframes.wave` config.
8. **`prefers-reduced-motion`** is honoured globally in [`globals.css:11`](../site/app/globals.css#L11) (zeroes all `animation-duration` and `transition-duration`). When adding interactivity, **don't bypass this** by hard-coding inline durations that overrule the global rule — keep durations in CSS classes or Tailwind utilities.
9. **`scroll-behavior: smooth`** is on globally ([`globals.css:8`](../site/app/globals.css#L8)). Anchor clicks scroll smoothly — but this is disabled under `prefers-reduced-motion`.
10. **Adding a route** flips the site from "single page" to "multi-page" and re-introduces questions about robots/sitemap/canonical URLs. Don't add routes unless you mean it; consider an anchor section first.

---

## 14. Where things live

| Want to change… | Edit |
|---|---|
| Site copy | [`site/app/page.tsx`](../site/app/page.tsx) |
| FAQ Q&A | [`site/components/FAQ.tsx`](../site/components/FAQ.tsx) |
| Install commands | [`site/app/page.tsx:303-336`](../site/app/page.tsx#L303) |
| Hero title / subtitle | [`site/app/page.tsx:35-49`](../site/app/page.tsx#L35) |
| Nav sections | [`site/components/Nav.tsx:7`](../site/components/Nav.tsx#L7) |
| Page title / description / OG | [`site/app/layout.tsx:27`](../site/app/layout.tsx#L27) |
| Brand palette | [`site/tailwind.config.ts:7-28`](../site/tailwind.config.ts#L7) |
| Font choices | [`site/app/layout.tsx:5`](../site/app/layout.tsx#L5) + [`site/tailwind.config.ts:29-33`](../site/tailwind.config.ts#L29) |
| Animation keyframes | [`site/tailwind.config.ts:40-80`](../site/tailwind.config.ts#L40) |
| Global CSS (buttons, kbd, grain) | [`site/app/globals.css`](../site/app/globals.css) |
| Security headers | [`site/vercel.json`](../site/vercel.json) |
| Favicon | [`site/public/favicon.svg`](../site/public/favicon.svg) |

---
