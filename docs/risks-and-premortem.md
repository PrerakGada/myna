# Myna — Risks, Pre-Mortem, and Adversarial Elicitation

**Date:** 2026-05-26
**Method:** advanced elicitation pass applied to the v0.1.0 documentation
**Lenses applied:** Devil's Advocate, Pre-Mortem, Red Team, First
Principles, Scenario Analysis, Stakeholder Round-Robin

This document is the synthesis of multi-angle elicitation passes over
the codebase, the four lane-architecture documents, the integration
architecture, and the v0.1.0 release log
([`HANDOFF.md`](https://github.com/PrerakGada/myna/blob/f5860c8/HANDOFF.md)). Each item is graded by **likelihood
× impact** and tagged with the part(s) it touches and the smallest
mitigation that would defuse it.

Grading scale:

- **Likelihood:** L (low, <10% per year), M (medium, 10–40%), H (high, >40%)
- **Impact:** Minor (annoyance), Moderate (degraded UX, fixable in days),
  Severe (release blocked or trust loss), Catastrophic (cannot ship
  updates, cannot recover without manual user intervention)

---

## 1. Pre-Mortem — "It's six months from now and v0.x failed. Why?"

Six scenarios where v0.x crashes into a wall. For each: the failure
narrative, the lens that surfaces it, the upstream signal that would
warn us in time, and the smallest fix today.

### 1.1 The Sparkle key leak (Catastrophic / L)

**The story.** A laptop with `dist/sparkle_private_key.NEVER_COMMIT.txt`
on disk is stolen. The thief publishes a `0.99.0` appcast entry signed
with the real private key. Every Myna install on the planet auto-updates
to a backdoored binary. We learn about it from a bug report.

**Why the lens caught it.** Pre-Mortem: the operator manual
([RELEASE.md § 1.4](../RELEASE.md#14-sparkle-eddsa-keys)) tells you to
delete the file after stashing in 1Password, but install paths leave
it on disk by default for the first release. SECURITY.md doesn't list
a procedure for key compromise.

**Upstream signal.** Any time the file exists on a machine that isn't
the immediate point of use. A pre-commit grep would catch a re-commit,
but not the on-disk persistence.

**Smallest fix today.**
1. Add a `dist/check-keys.sh` script that fails if
   `dist/sparkle_private_key.NEVER_COMMIT.txt` exists on a machine where
   `git rev-parse --show-toplevel` matches the myna repo.
2. Document a "key compromise" procedure in SECURITY.md: ship a new
   minor version with a new public key + a banner instructing users to
   manually reinstall.
3. Consider Sparkle's "rotate via signed metadata" support
   (post-2.5.x added this — verify support in 2.6.0).

### 1.2 The `actions/upload-artifact` regression (Severe / M)

**The story.** Six months from now we upgrade
`actions/upload-artifact@v4` → `@v5` because Dependabot opened a PR. The
new version "improves performance" by removing the manual symlink-
preserve workaround the v0.1 fix relies on. Notarization breaks on the
next release. We chase the previous-iteration ghost for two days before
re-reading [HANDOFF.md "The actual root cause"](https://github.com/PrerakGada/myna/blob/f5860c8/HANDOFF.md).

**Why the lens caught it.** Red Team: pre-mortem of CI dep upgrades is
underweighted. The current fix works because the artifact path
explicitly `tar`s the .app — but a "convenience" change to upload-
artifact could silently change semantics again.

**Upstream signal.** A failed notarization with "binary signature
invalid" on a known-good code change. A `release.yml` diff that touches
the upload-artifact action versions.

**Smallest fix today.**
1. Add a top-of-file comment in `release.yml` pinning the rationale:
   ```yaml
   # CRITICAL: We tar .app between every job. actions/upload-artifact
   # flattens symlinks (Sparkle.framework versioned layout) and strips
   # xattrs (Sealed Resources V2). DO NOT REMOVE the tar step. See
   # HANDOFF.md "The actual root cause" for the 10-iteration saga.
   ```
2. Pin upload-artifact to a known-good major (`@v4` is acceptable).
3. Add a release-smoke step that runs `codesign --verify --deep
   --strict --verbose=2 Myna.app` after every job that uploads a .app
   artifact — fail fast if the bundle is no longer signature-clean.

### 1.3 The Homebrew formula divergence (Severe / M)

**The story.** A contributor opens a "fix daemon dep" PR. They update
`tap/Formula/myna-daemon.rb` here, the source-of-truth. Release.yml's
`tap-bump` job sed-updates the deployed tap's url + sha256 — but the
deployed tap's resource blocks + `depends_on "rust" => :build` are
**only** in the deployed copy. The PR ships. Next release attempts to
re-init the tap from this repo's source. The deployed formula reverts
to the dead-`cd` version + no resource blocks. Every `brew install
--cask myna` fails with `ImportError: No module named fastapi`.

**Why the lens caught it.** Devil's Advocate: HANDOFF.md flagged the
divergence as v0.2 follow-up. Six months out, the next contributor
won't read HANDOFF.md.

**Upstream signal.** A PR that touches `tap/Formula/myna-daemon.rb`
without also adding the resource blocks.

**Smallest fix today.**
1. Port the resource blocks + rust dep from the deployed tap back into
   `tap/Formula/myna-daemon.rb` immediately — this is the v0.2 blocker
   item.
2. Add a `tap/Formula/.deploy-parity-check.sh` script that diffs the
   source against the deployed tap and fails if they drift.
3. Add a GH Actions check on PRs touching `tap/` that runs the parity
   check.

### 1.4 The Sparkle.framework cosmic-ray bug (Severe / L)

**The story.** Apple ships macOS 16.0 with a new Sealed Resources hash
format that requires Sparkle 2.7+. We're pinned to `from 2.6.0`. Existing
users on macOS 16 see "Myna is damaged and can't be opened" because
Gatekeeper re-evaluates and the framework's v2 hash doesn't pass v3
validation. New installs fail. We can ship a new build with Sparkle 2.7
— but users on 0.1.x already on macOS 16 are stranded until they
manually re-download.

**Why the lens caught it.** Scenario Analysis: external OS upgrades are
the biggest non-malicious risk to a notarized macOS app.

**Upstream signal.** macOS beta dev forum chatter; Apple's "what's new"
release notes (June WWDC).

**Smallest fix today.**
1. Subscribe to Sparkle-project release notes and Apple Developer News.
2. Document a "macOS-major-upgrade smoke test" in
   `development-guide-ops.md`: install the latest macOS beta on a
   spare VM, run Myna, check Console for codesign warnings, run
   `spctl --assess --type execute --verbose=2 Myna.app`.
3. Test SUPMS upgrade paths on every macOS major release before the
   wider population reaches it.

### 1.5 The Apple cert expiration (Severe / M, becomes Catastrophic if
**The story.** Operator forgets to renew the Apple Developer Program
($99/yr). Cert expires. All `release.yml` runs fail at the sign step.
Sparkle updates keep working (they're signed with EdDSA, independent
of the Apple cert), but no new releases can ship. If discovered too
late, the cert needs full re-issuance + a `release.yml` `APPLE_DEVELOPER_ID_NAME`
secret update — even after re-up, the new cert string differs (new
serial number in the parens).

**Why the lens caught it.** Stakeholder Round-Robin (Operator's seat):
the calendar reminder isn't in this repo.

**Upstream signal.** Apple Developer account email warning at 30 days.

**Smallest fix today.**
1. Add a calendar reminder for cert expiration (one-time setup, but the
   operator should record it). The repo can't enforce this but can
   document the trade-off — link from RELEASE.md.
2. `release.yml` preflight job could `security find-certificate` and
   parse the expiration date — fail with a clear "cert expires in N
   days" if N < 30. Bonus: open an issue automatically.

### 1.6 The drift between Swift and Python wire types (Moderate / H)

**The story.** A daemon contributor adds a new field to `V2Status` in
`v2_types.py`. Tests pass (pytest only validates Python side). Release
ships. The Swift app's `JSONDecoder` silently drops the unknown field —
no UI break. But the field carries useful info (say, queue depth) that
the menu bar should surface. Six months later, someone asks why the
queue indicator never works.

**Why the lens caught it.** First Principles: there's no compiler-
enforced contract between Pydantic and Codable. The shared fixture JSON
in `docs/native-app/fixtures/` is the only cross-stack check, and it
checks SHAPES not SEMANTICS.

**Upstream signal.** Any `v2_types.py` PR that adds a field without a
companion Swift PR.

**Smallest fix today.**
1. Tighten the Codable models — make `V2Status` etc. use
   `decodeIfPresent` *and* log unknown keys at debug level (Swift's
   `JSONDecoder` can be subclassed to capture unknown keys).
2. Add a cross-stack test that dumps `V2Status` from Python and asserts
   the Swift decoder produces an instance with no info loss.
3. Document the "if you change a v2 type, you must also update Swift"
   step in [`integration-architecture.md § 6`](./integration-architecture.md#6-operational-hand-off-matrix)
   (already done).

---

## 2. Devil's Advocate — "Why is this the wrong architecture?"

### 2.1 "Why not a single Swift app — drop the daemon entirely?"

**Argument.** The Python daemon is a complexity tax: 944 LOC, 40 PyPI
resource blocks, Rust toolchain dep, 20–30 min first install. Porting
`chunking.py`, `summarize.py`, `extract.py` to Swift and embedding
Kokoro via Swift wrappers around `MLX-swift` would yield a single
signed binary. v0.4 already plans this.

**Counter-argument.** mlx-audio's Kokoro implementation is Python-first
and tracks the upstream model rapidly. Porting to Swift means owning
the model-runtime wrapper across mlx-swift upgrades. The summary +
extract paths are also non-trivial — trafilatura has years of edge-
case handling, and re-implementing in Swift would replicate that. The
daemon also gives a useful seam for swapping engines (could plug in a
cloud TTS via the same /v2/synthesize contract).

**Synthesis.** Keep the daemon through v0.3. In v0.4, do a phased port:
chunking + extract → Swift (simple); summarize → Swift (medium); engine
stays Python until mlx-swift Kokoro support is mature. The seam between
Swift and engine becomes a Swift Process subprocess instead of HTTP —
but only if benchmarks show meaningful latency wins.

### 2.2 "Why no auth on the daemon?"

**Argument.** Any local process can curl `127.0.0.1:8766/speak` and
make Myna talk. A misbehaving Electron app, a curious cron job, an
NPM install script — anything could do it.

**Counter-argument.** It binds 127.0.0.1, which is a privilege boundary
on Mac (no LAN exposure). Authenticating local services adds significant
UX friction (key exchange between Swift app and daemon) for a threat
model where the attacker already has user-level code execution on the
machine — at which point they have plenty worse than "make TTS speak".

**Synthesis.** Stay un-auth'd. Document the threat model decision
explicitly in SECURITY.md. If the attack surface ever becomes "third-
party browser extensions that can curl localhost", consider a startup-
generated bearer token in `~/.config/myna/auth_token` with `0600` perms
and a `MYNA_TOKEN` env that adapters read.

### 2.3 "Why isn't the Hammerspoon path deleted?"

**Argument.** Maintaining two control surfaces (Swift app + Hammerspoon)
means dual-registering hotkeys, dual-polling daemon, dual-documenting,
double the bug surface. "Second registration wins" is a bad UX — users
get random behavior depending on launch order.

**Counter-argument.** Hammerspoon was the v0 surface and current
installed-base users depend on it. The dev install path (`install.sh`)
sets up both for backward compat. Deleting it before v0.4 strands
existing users.

**Synthesis.** Mark Hammerspoon as v1 legacy in the install script;
make installation opt-in (a `MYNA_LEGACY_HAMMERSPOON=1` flag for users
who explicitly want it). Plan removal in v0.4 alongside the daemon-to-
Swift port. Until then, document the "pick one" rule loudly in the
README troubleshooting section.

### 2.4 "Why does the site exist at all?"

**Argument.** A README + GitHub Releases page is sufficient distribution.
The site is `~16k LOC of Tailwind + React 19` for a brochure. Vercel
deploy, custom domain, ongoing maintenance — all for content that could
live in `README.md`.

**Counter-argument.** A landing page builds shareability (Twitter cards,
SEO for "local mac TTS", a hero CTA above the fold). It's the
appropriate marketing layer for a v1 launch on HN/Product Hunt
(planned v1.0). It's also genuinely small — no DB, no analytics SDK,
no auth — so ongoing cost is minimal.

**Synthesis.** Site stays. But it should be more honest about what
it's for: lifetime-cost-to-Prerak in maintenance is real. Add a
"don't gold-plate this" comment in `site/README.md`. Keep components
hand-rolled (no UI library install) to keep dep-update overhead near
zero.

### 2.5 "Why bundle 40 Python resources instead of pip-installing at
       install time?"

**Argument.** The formula's 40 declared resource blocks are a
maintenance burden — `/tmp/gen-resources.py` scrapes PyPI JSON for each.
Every daemon dep upgrade requires regen. End-users wait 20–30 min on
first install because every resource is built from source (`--no-binary
:all:`).

**Counter-argument.** Homebrew's `pip_install_and_link` hardcodes
`--no-deps`, leaving only the `myna` package without its tree. Either
declare resources (current) or invoke a custom `python_install` that
bypasses Homebrew's wrappers (against Homebrew style). Source builds
also ensure reproducibility and avoid the "binary wheel breaks on a
future Python" class of bugs.

**Synthesis.** Stick with resource blocks until v0.4 daemon-to-Swift
removes the Python dependency entirely. Mitigate the regen pain by
automating it: a `dist/regen-formula-resources.sh` script that calls
the PyPI JSON API and rewrites `tap/Formula/myna-daemon.rb` deterministically.

---

## 3. Red Team — "I want to compromise Myna users"

### 3.1 Vector: supply chain via PyPI

**Attack.** Compromise one of the 40 transitive Python deps (e.g. take
over a small dep `is-eight-and-two`-style). Push a tainted version that
runs at daemon import. Users who `brew upgrade myna-daemon` get the
tainted code, with daemon-level access to their mic, audio output, and
ability to simulate keystrokes (no — that's the Swift app, not the
daemon; the daemon has no Accessibility entitlement).

**Mitigation today.** Resource blocks pin **specific versions + sha256**
in the deployed tap. A taint upstream doesn't propagate until someone
regenerates resources. Audit any resource-regen PR carefully.

**Residual risk.** Low. The daemon's blast radius is narrow (no
keystroke sim, no pasteboard access, no Accessibility). Worst case is
the daemon exfiltrates the text users are about to speak.

### 3.2 Vector: supply chain via Swift SPM

**Attack.** Compromise `sindresorhus/KeyboardShortcuts` or `sparkle-
project/Sparkle`. New version with malicious code lands; the next
`xcodegen generate` + release pulls it.

**Mitigation today.** SPM uses commit hashes after resolve. `project.yml`
pins `from 2.0.0` / `from 2.6.0` (minimum versions). Reviewer should
inspect `Package.resolved` diff on dep updates.

**Residual risk.** Medium. Sparkle has a privileged installer launcher
service in the bundle — a tainted Sparkle could replace the .app with
arbitrary code. Mitigation: only upgrade Sparkle in a dedicated PR
that links to the diff and includes a manual code-skim.

### 3.3 Vector: malicious URL scheme input

**Attack.** Web page or BetterTouchTool gesture invokes
`myna://speak?text=…` with a crafted payload that exploits an
underlying audio-decoding bug or floods the daemon.

**Mitigation today.** `URLSchemeHandler` validates and clamps all
inputs — and **explicitly does NOT include an "arbitrary-text-speak"
route**. The 11 adversarial inputs in
[`AuditSecurityURLSchemeTests.swift`](../apps/macos/Tests/URLSchemeTests/AuditSecurityURLSchemeTests.swift)
all dropped or clamped safely. Confirmed in the security audit.

**Residual risk.** Low. If a future action added that allowed text
injection (e.g. `myna://speak-clipboard`), the threat would re-open.
Maintain the "no arbitrary-text route" invariant in
`development-guide-macos.md`.

### 3.4 Vector: trafilatura SSRF / file:// leakage

**Attack.** Send `/v2/extract` a `file:///etc/passwd` URL. Daemon
trafilatura reads the file and returns the content.

**Mitigation today.** `app.py:489` validates `req.url.startswith("http://"
) or "https://"` — anything else returns 400 `invalid_url`. **But v1
`_speak` doesn't do this** (cross-checked in app.py — v1 url handling
is more permissive). Hammerspoon legacy + CC hook + CLI could pass a
crafted url to v1.

**Residual risk.** Medium. Recommended: add URL-scheme validation to v1
`_speak` too. Defense in depth.

### 3.5 Vector: AppleScript abuse via daemon RCE

**Attack.** Compromise the daemon (somehow — say PyPI supply chain
above). Daemon doesn't have Accessibility OR AppleScript entitlement
directly, but the Swift app does — could the daemon coerce the app into
running AppleScript?

**Mitigation today.** The Swift app's `ChromeService` is the only path
to AppleScript and it has a 5-second timeout. Daemon would need to
provoke the user to press the read-Chrome hotkey, which doesn't escalate
beyond reading the active Chrome tab URL — bounded.

**Residual risk.** Low.

### 3.6 Vector: Sparkle MITM (rejected by design)

**Attack.** Intercept the appcast HTTPS fetch and serve a malicious
appcast.

**Mitigation today.** Even if HTTPS is bypassed, every entry is
EdDSA-signed; Sparkle verifies against the public key baked into the
app. Forgery requires the private key.

**Residual risk.** Catastrophic if private key compromised — see § 1.1.

---

## 4. First Principles — what is the irreducible architecture?

If we tore everything down to first principles, the irreducible
architecture is:

1. **A capture surface** (hotkey, AppleScript, URL scheme) that can read
   user-selected text from the active app.
2. **A processing pipeline** that turns text → optional summary → chunks
   → WAV.
3. **An output engine** that renders audio with rate-control without
   pitch shift.
4. **A control surface** for pause/resume/stop/speed.

Everything else (LaunchAgents, Hammerspoon legacy, CLI wrapper, CC
hook, Sparkle, brew tap, site, release pipeline) is **distribution
glue and ergonomics**.

This framing surfaces:

- **The Python daemon is replaceable.** Today it provides processing +
  engine-orchestration. Both can be Swift (v0.4 plan). The daemon is
  the largest movable piece.
- **The Hammerspoon module is REDUNDANT.** It re-implements capture +
  control. It survives only for migration ergonomics; nothing the
  capture+control surface needs is unique to Lua.
- **The CLI is REDUNDANT.** It's a 27-line wrapper around `/speak` that
  the Swift app's URL scheme (or `osascript -e 'tell Myna…'`) could
  replicate. Survives because power users love pipes.
- **The site is OPTIONAL.** It doesn't run code. It's a brochure.

A radical v1.0 simplification would be: **one Swift binary, one Kokoro
process Swift owns as a subprocess, no daemon, no Hammerspoon, no CLI**.
Everything else is content (site) or pipeline (release). 70% of the
maintenance surface vanishes.

We aren't proposing this for v0.x — but the framing should guide
architectural decisions: every new piece of code should justify itself
against this floor.

---

## 5. Stakeholder Round-Robin — what each role would change

### 5.1 The end-user

- **First-install pain.** 20–30 min compile-from-source is brutal.
  Solution paths: ship bottled Python wheels via the tap (Homebrew
  bottle build flag); or v0.4 daemon-to-Swift removes this entirely.
- **First-launch permission storm.** Accessibility + AppleScript +
  Notifications + (Sparkle) AutomaticInstallerLauncherService. Each is
  a separate macOS prompt with different copy. Solution: a SwiftUI
  "welcome" screen on first launch that explains why each is needed,
  in the order they'll be requested.
- **"Where did I leave off?"** No session persistence. If user pauses
  mid-article, kills the app, relaunches, the article is gone. Solution
  candidate: persist `PlaybackQueue` state to `~/Library/Application
  Support/Myna/state.plist` on pause/quit.

### 5.2 The contributor

- **Multi-language build matrix is intimidating.** Swift + Python + TS +
  Bash + Lua + Ruby + Plist + YAML. A newcomer has to install Xcode 16,
  XcodeGen, python3.13, Node, brew formulas, then know about Hammerspoon.
  Solution: a one-script bootstrap (`dev-bootstrap.sh`) that installs
  everything and validates with `dev.sh` smoke runs.
- **No CONTRIBUTING.md.** [`contribution-guide.md`](./contribution-guide.md)
  was synthesized in this scan but lives in `docs/`. Pin a root-level
  `CONTRIBUTING.md` that points to it.
- **Tests for site are missing.** No regression net on the marketing
  surface. Add a Playwright smoke ("page loads, FAQ accordion expands,
  hero CTA links to the right GH release URL").

### 5.3 The operator (Prerak)

- **Calendar dependencies are off-repo.** Apple cert renewal, app-
  specific password rotation, Sparkle key 1Password sync.
  Solution: a `docs/operator-calendar.md` checklist + a quarterly
  reminder.
- **Notarytool log fetch is manual.** Per HANDOFF.md follow-up: on
  Rejected status, the operator has to manually `xcrun notarytool log
  <id>`. Patch `dist/notarize.sh` to do this automatically and post
  the log into the GH Actions step output.
- **HANDOFF.md is gitignored.** It contains the most useful "why did
  we do this" context but isn't available to the next contributor.
  Solution: a curated, redacted version checked in as
  `docs/history/v0.1.0-release-saga.md`.

### 5.4 The security reviewer

- **Public security email is stale.** SECURITY.md still publishes
  `rashid@dpsca.in`; CLAUDE.md says Prerak is `prerak@engaze.in`.
  **Trivial fix:** update SECURITY.md.
- **No vulnerability disclosure pipeline.** SECURITY.md mentions
  GitHub private vuln reporting and email; no PGP key, no GPG-signed
  contact, no triage SLA enforcement.
- **No SBOM.** For a desktop app talking to the network on a daily
  basis, an SBOM (e.g. SPDX or CycloneDX generated from the tap
  formula's resource list + the SPM Package.resolved) would help
  downstream consumers.

### 5.5 The future-Claude or other AI agent

- **`docs/index.md` exists** (this workflow's output) and links every
  doc. Good.
- **Wire-type drift between Swift and Python** is not machine-checkable.
  Add a `make verify-contracts` that loads both type systems and asserts
  field parity.
- **The release pipeline has no rollback automation.** A bad release
  requires manual deletion + tap revert + appcast rebuild. A
  `dist/rollback.sh <version>` would make recovery one command.

---

## 6. Scenario Analysis — three macro paths and what breaks

### Scenario A: Myna becomes popular (10k installs in 30 days)

**What breaks:**
- The Sparkle appcast is a GitHub Release asset. 10k daily fetches of
  appcast.xml is fine. 100k might warrant a CDN (GitHub Releases CDN
  handles this — verify SLA).
- First-install bottling pressure increases. Users complain about
  20–30 min wait. Solution: get a Homebrew bottle build running.
- GitHub Issues become unmanageable. Need a triage process; the
  contribution guide should grow.
- Apple notarization quota concerns (unlikely; we'd need >100
  notarizations/day to hit limits).

**Mitigations to start now:**
- Add a bottle build flag to the tap formula.
- Document an Issue triage cadence in `contribution-guide.md`.
- Investigate Apple notarization quota limits — document in SECURITY.md.

### Scenario B: Myna stagnates (no users; abandoned)

**What breaks:**
- Apple cert lapses; no new releases ship.
- Existing users on `0.x` keep working until macOS upgrade breaks the
  signature.
- Codebase rots; deps go stale.

**Mitigations to start now:**
- Document a "last release wishes" plan: if Prerak stops shipping,
  release a final un-Sparkle'd version with `SUEnableAutomaticChecks=NO`
  so users don't get stranded checking a dead URL.
- License is MIT — anyone can fork. Make sure
  [`CONTRIBUTING.md`](./contribution-guide.md) clearly explains
  build-from-source.

### Scenario C: Apple Silicon ARM becomes the minority (x86_64
       resurgence) [low likelihood]

Not credible in 5-year horizon. Skip.

### Scenario C': Apple deprecates `xcrun notarytool` (medium likelihood
       in 3-year horizon)

**What breaks:** `dist/notarize.sh` and `release.yml notarize` job.
**Mitigation:** Watch Apple Developer release notes. Replace with
the successor tool (likely a `notarytool v2` or a Cloud-Notary
REST API) when announced.

---

## 7. Consolidated triage — what to do in the next two sprints

### Critical (do before v0.2 tag)

| Item | Effort | Owner | Document |
|---|---|---|---|
| Reconcile `tap/Formula/myna-daemon.rb` source ↔ deployed (port resource blocks + rust dep) | M | Prerak | [HANDOFF.md "Tap formula tail"](https://github.com/PrerakGada/myna/blob/f5860c8/HANDOFF.md), [`architecture-ops.md § 6`](./architecture-ops.md) |
| Update SECURITY.md contact email to `prerak@engaze.in` | S | Prerak | [SECURITY.md:23](../SECURITY.md#L23) |
| Add `dist/check-keys.sh` to fail if Sparkle private key file present on disk | S | Prerak | This doc § 1.1 |
| Pin upload-artifact to `@v4`, add CRITICAL comment in release.yml | XS | Prerak | This doc § 1.2 |
| Add v1 `_speak` URL scheme validation (defense in depth) | S | Prerak | This doc § 3.4, [api-contracts-daemon.md spec drift](./api-contracts-daemon.md) |

### High (do in v0.2 cycle)

| Item | Effort | Owner | Document |
|---|---|---|---|
| Patch `dist/notarize.sh` to auto-`notarytool log` on Reject | S | Prerak | [HANDOFF.md v0.2 follow-ups](https://github.com/PrerakGada/myna/blob/f5860c8/HANDOFF.md), this doc § 5.3 |
| Add try/except wrap to install.sh CC-hook JSON merge | XS | Prerak | [development-guide-ops.md](./development-guide-ops.md), this doc § 5.1 |
| Add `make verify-contracts` (Pydantic ↔ Codable parity) | M | Prerak | This doc § 1.6, § 5.5 |
| Create root-level `CONTRIBUTING.md` pointing at `docs/contribution-guide.md` | XS | Prerak | This doc § 5.2 |
| Add `site/tsconfig.tsbuildinfo` to `.gitignore` | XS | Prerak | [development-guide-site.md](./development-guide-site.md) |
| Document "key compromise procedure" in SECURITY.md | S | Prerak | This doc § 1.1 |
| Add `dist/rollback.sh <version>` script | M | Prerak | This doc § 5.5 |
| Bump Ollama failure mode from 500 → structured 502 `summary_engine_down` | S | Daemon contributor | [api-contracts-daemon.md spec drift](./api-contracts-daemon.md), this doc § 2.3 |
| Add `chunk_chars >= 1` validator to `V2SynthesizeReq` | XS | Daemon contributor | Lane B summary, this doc § 1.6 |

### Medium (v0.3 cycle)

| Item | Effort | Owner |
|---|---|---|
| Operator calendar + reminders (`docs/operator-calendar.md`) | S | Prerak |
| Curated `docs/history/v0.1.0-release-saga.md` (redacted HANDOFF) | M | Prerak |
| First-launch SwiftUI welcome screen (permission storm explainer) | M | macos contributor |
| Persist `PlaybackQueue` state across app restarts | M | macos contributor |
| Playwright smoke test for `site/` | M | site contributor |
| One-script bootstrap `dev-bootstrap.sh` | S | Prerak |
| Bottle build flag exploration for tap formula | M | Prerak |
| Cert-expiration preflight in `release.yml` | S | Prerak |

### Lower priority (v0.4+ / strategic)

| Item | Effort | Owner |
|---|---|---|
| Daemon-to-Swift port (chunking + extract first; engine last) | XL | Prerak |
| Drop Hammerspoon path (after daemon Swift port) | M | Prerak |
| Drop CLI path or convert to a Swift sub-command | S | Prerak |
| SBOM generation | M | security-aware contributor |

---

## 8. Open Questions

Things that would change the risk calculus if answered. Asking Prerak
isn't blocked; these are flagged for an asynchronous decision when
convenient.

1. **macOS minimum target.** Sticking with 13 (Ventura) costs us
   `@Observable` and other Sonoma+ APIs. What % of target users are on
   13? If <5%, bumping to 14 simplifies the Swift code.
2. **Telemetry stance.** Currently zero. A privacy-first crash-only
   telemetry (no user content, just stack traces; opt-in) would help
   diagnose field bugs. Worth the trust hit?
3. **Internationalization.** All UI is English. Spanish + Portuguese +
   French would meaningfully expand reach. Kokoro voices for non-en
   exist. Scope?
4. **Pricing.** v0.x is free + MIT. v1.0 could maintain free + accept
   donations, or introduce a paid tier (e.g. cloud-synced settings,
   premium voices). Stance?
5. **What does v2.0 look like?** v0.4 has a concrete plan; v1.0 is
   "public launch on HN" but the technical scope is unclear. Worth a
   PRFAQ pass.

---

_Generated using BMAD Method `document-project` workflow — advanced
elicitation pass. Lenses: Devil's Advocate, Pre-Mortem, Red Team,
First Principles, Scenario Analysis, Stakeholder Round-Robin._
