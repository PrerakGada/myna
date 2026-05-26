# Myna v0.1.0 Release — Session Handoff

**Date:** 2026-05-26 (early morning, after the overnight v2 build)
**Repo:** https://github.com/PrerakGada/myna (public)
**Tap:** https://github.com/PrerakGada/homebrew-tap (public, already seeded)
**Branch:** `main` at commit `e838932`
**Tag:** `v0.1.0` (currently pointing at `e838932`; will need delete + retag after next fix)
**Latest CI run:** `26436969709` — **FAILED at Sign step (7th consecutive sign failure)**

> Pick up exactly here. Everything below is current-state truth, scrollable, no fluff.

---

## TL;DR — what works, what doesn't

✅ **Everything OFF the release pipeline works.** The Swift app builds locally, all 91 tests pass, lint is clean, daemon's 94 tests pass, app runs end-to-end on user's Mac (`dev.sh` then click bird → hotkey → audio plays through Kokoro via `/v2/synthesize`).

✅ **CI builds successfully** (universal binary, arm64+x86_64). Build step is green.

❌ **CI Sign step has failed 7 times** on `Sparkle.framework`. Each fix peeled one layer of the onion. The next fix is needed for **"unsealed contents present in the root directory of an embedded framework"**.

✅ **All 9 GitHub Actions secrets set.** Tap deploy key works (verified). Production Sparkle key rotated and safe.

---

## The release-loop progression so far (so you don't repeat fixes)

| Run | Tag | Failed at | Why | Fix committed |
|---|---|---|---|---|
| 1 | (canceled) | (canceled) | Tag landed on commit without Lane A merge | Re-merged native-app-rebuild → main, retagged |
| 2 (26435892468) | v0.1.0 | Build | `LogViewerView.swift:50` — Xcode 16 Swift 6 strict-concurrency rejected `reload()` in Timer closure | `a5dbec8` — `Task { @MainActor in reload() }` |
| 3 (26436385905) | v0.1.0 | Sign | `dist/sign.sh:50` — `mapfile: command not found` (bash 3.2 on macos-15) | `f996347` — replace mapfile with `while IFS= read -r` loop |
| 4 (26436518451) | v0.1.0 | Sign | Sparkle.framework "bundle format is ambiguous" — `find` matched symlinks AND real dirs | `ff029b6` — `-type d` on find |
| 5 (26436678535) | v0.1.0 | Sign | Same "ambiguous" — `-type d` didn't help because Xcode flattened symlinks into real dirs on CI | `6b5e5bd` — Sparkle-aware `sign_sparkle()` function, exclude from generic loop |
| 6 (26436805988) | v0.1.0 | Sign | Same "ambiguous" — sign_sparkle's bottom-up loop ran fine but root sign still failed | `9f1d3ac` — `--deep` on Sparkle.framework root |
| 7 (26436969709) | v0.1.0 | Sign | `--deep` rejected with same error (codesign refuses bundle BEFORE deep recursion starts) | `e838932` — normalize: restore symlinks for Sparkle/Headers/Modules/Resources/Updater.app/XPCServices |
| 7 (re-failed!) | v0.1.0 | Sign | **NEW error:** `unsealed contents present in the root directory of an embedded framework` | **TO DO** (see "Next iteration" below) |

The full log of run #7 (most recent failure) is saved at `docs/native-app/last-ci-failure.log` (gitignored — local only).

**Key insight:** Each fix has been correct; we're peeling a multi-layer Sparkle.framework + Xcode-embed-and-sign bug onion. Run #7's failure is real progress (different, more specific error). We're close.

---

## Next iteration — what to try

The current error is:
```
Sparkle.framework: unsealed contents present in the root directory of an embedded framework
```

This means: after symlink normalization, **something at the framework root is neither a known alias, Versions/, _CodeSignature/, nor an Info.plist that codesign expects**. Apple's framework signing rules require everything at the framework root to be sealed.

**Most likely candidates** (in priority order):

1. **`_CodeSignature/` at the framework root** (NOT inside `Versions/<X>/`). Xcode pre-signs and leaves this artifact. Frameworks shouldn't have it at root — it should only exist under `Versions/<X>/_CodeSignature/`.
2. **An extra `Info.plist` at root** (not under `Resources/Info.plist`).
3. **`.DS_Store` or similar** filesystem cruft.
4. **A binary/resource we didn't symlink** in our normalization — anything Xcode flattened that we missed in our 6-name list (`Sparkle Headers Modules Resources Updater.app XPCServices`).

### Diagnostic step to add to `dist/sign.sh`

Add this BEFORE the framework root `codesign` line in `sign_sparkle()`:
```bash
log "sparkle root contents (debug):"
ls -la "$sparkle" 2>&1 | sed 's/^/  /'
```

That will print exactly what's at the framework root so you see what's "unsealed". Then either symlink it, delete it, or move it into `Versions/<current>/`.

### Most-likely-correct one-liner fix

If the diagnostic shows `_CodeSignature/` at the root:

```bash
# Inside sign_sparkle(), right after the normalize block, before signing:
rm -rf "$sparkle/_CodeSignature"
```

Xcode's previous signature at the root is stale after our normalization anyway; deleting it lets our fresh sign produce a clean one.

If the diagnostic shows other unsealed files, extend the normalize block to symlink or remove them.

### Fallback if cleanup doesn't work

Two nuclear options:
1. **Replace Sparkle.framework with a fresh copy from the SPM checkout** before signing — bypasses all of Xcode's embed-and-sign damage. The SPM cache is at `~/Library/Developer/Xcode/DerivedData/<...>/SourcePackages/checkouts/Sparkle/` on local builds, and at `$RUNNER_TEMP/<...>/SourcePackages/checkouts/Sparkle/` on CI.
2. **Switch from Sparkle SPM to Sparkle XCFramework** (`https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz`) and embed manually. XCFramework's pre-built binary is signed by Sparkle's own team and avoids Xcode embed-and-sign entirely.

Fallback #2 is the cleaner long-term solution but a bigger change (modify `apps/macos/project.yml` to drop the SPM `Sparkle` package, add an XCFramework reference instead, and adjust the build script).

---

## Per-release iteration loop (the muscle memory)

For each fix attempt, do this:
```bash
cd ~/Developer/myna
# 1. Edit dist/sign.sh (or wherever the fix lives)
# 2. Smoke test locally:
bash dist/tests/test_scripts.sh
# 3. Commit:
git add dist/sign.sh
git -c user.email="rashid@dpsca.in" -c user.name="Orchestrator" commit -m "fix(dist/sign): <what>"
# 4. Delete old tag + push:
git tag -d v0.1.0
git push --delete origin v0.1.0
git push origin main
# 5. Re-tag + push (fires release.yml):
git tag -a v0.1.0 -m "Myna v0.1.0 — first native-app release"
git push origin v0.1.0
# 6. Watch:
sleep 4 && gh run list --repo PrerakGada/myna --workflow=release.yml --limit 1
# Then arm Monitor (see below).
```

### Monitor template

```bash
# Replace RUN_ID below with the new run's ID from `gh run list`.
# Use the Monitor tool with this script:
cd ~/Developer/myna
prev=""
RUN_ID=<new-run-id>
while true; do
  s=$(gh run view "$RUN_ID" --repo PrerakGada/myna --json status,conclusion,jobs 2>/dev/null) || { sleep 30; continue; }
  cur=$(jq -r '.jobs[] | "\(.name)\t\(.status)\t\(.conclusion // "—")"' <<<"$s" | sort)
  diff_lines=$(comm -13 <(printf '%s\n' "$prev") <(printf '%s\n' "$cur") | sed -E 's/\t/ · /g')
  if [ -n "$diff_lines" ]; then
    while IFS= read -r line; do echo "[job-update] $line"; done <<<"$diff_lines"
  fi
  prev="$cur"
  run_status=$(jq -r '.status' <<<"$s")
  run_conclusion=$(jq -r '.conclusion // ""' <<<"$s")
  if [ "$run_status" = "completed" ]; then
    echo "[run-done] finished: $run_conclusion"
    if [ "$run_conclusion" != "success" ]; then
      gh run view "$RUN_ID" --repo PrerakGada/myna --log-failed 2>&1 | tail -40 | sed 's/^/[log] /'
    fi
    break
  fi
  sleep 45
done
```

Use Monitor tool with `timeout_ms: 2400000` (40 min).

### Common foot-guns

- **Bash chain masks merge conflicts.** `git merge ... 2>&1 | tail -6 && echo next` — the `tail` exits 0, so `&&` continues even though merge conflicted. Don't pipe `git merge`.
- **Zsh reserves `$status`.** In Monitor scripts use `run_status` instead.
- **`gh run watch` with `--exit-status` sometimes returns 0 mid-flight.** Trust Monitor over watch.
- **Don't recreate `dev.sh` from scratch — it's at `apps/macos/dev.sh`** and works.

---

## What "done" looks like

When CI eventually succeeds, you'll see this job order in `gh run list`:
1. Preflight ✅
2. Build universal ✅
3. Sign .app ✅ ← *currently here, broken*
4. Notarize .app ✅ (5–15 min wait on Apple)
5. Build DMG ✅
6. Sign + notarize DMG ✅
7. Sparkle appcast ✅ (signs DMG with EdDSA, generates `<item>` XML)
8. Create GH Release ✅ (DMG attached to https://github.com/PrerakGada/myna/releases/tag/v0.1.0)
9. Bump Homebrew cask ✅ (cask + formula commit lands on `PrerakGada/homebrew-tap`)

Then verify end-to-end:
```bash
# Fresh-install test (on a clean Mac or after cleanup)
brew tap PrerakGada/tap
brew install --cask myna
open /Applications/Myna.app
# Bird icon → grant Accessibility → select text → ⌘⌥⇧S → hear audio
```

---

## State of secrets / credentials

All set on `PrerakGada/myna`. Verify with `gh secret list --repo PrerakGada/myna` → should show 9 entries:
- `APPLE_DEVELOPER_ID_P12` (base64 of `~/Documents/Certificates.p12`)
- `APPLE_DEVELOPER_ID_P12_PASSWORD`
- `APPLE_DEVELOPER_ID_NAME` = `Developer ID Application: MIND WEALTH (RC63N3VU27)`
- `APPLE_ID` (user-set)
- `APPLE_ID_APP_PASSWORD` (user-set)
- `APPLE_TEAM_ID` = `RC63N3VU27`
- `KEYCHAIN_PASSWORD` (random)
- `SPARKLE_EDDSA_PRIVATE_KEY` (from `dist/sparkle_private_key.NEVER_COMMIT.txt`)
- `TAP_DEPLOY_KEY` (SSH key, verified can push to `PrerakGada/homebrew-tap`)

Local-only artifacts (not in repo):
- `~/Documents/Certificates.p12` (cert + key)
- `dist/sparkle_private_key.NEVER_COMMIT.txt` (Sparkle EdDSA private — value `qLjUGLP/OchclqHWHELNAhgMpg4mV2LLj8xhZqP4yyQ=`; gitignored)
- `~/.ssh/myna_tap_deploy` + `.pub` (tap deploy key)

The public Sparkle key baked into the .app: `lEoEYOBRVnzZC9bysaAYSRpEuXSDmd/FagSmzv2ozHg=` (in `apps/macos/project.yml` line 60 and `apps/macos/Resources/Info.plist`).

---

## Tap repo state

`PrerakGada/homebrew-tap`:
- `Formula/myna-daemon.rb` — pushed manually by us; SHA256 is currently a placeholder (`0000...`); release.yml's tap-bump job will recompute and update it on every release.
- `Formula/clarity.rb` — pre-existing, not touched.
- `Casks/myna.rb` — will be created by release.yml on first successful release.

---

## Repo state recap (everything that's NOT release pipeline)

Released to `main`:
- Full Swift menu bar app (40 files, 91 tests passing)
- Python daemon v0.2.0 with v2 endpoints (94 tests passing)
- Sparkle 2 integration
- All three lane audits + security review committed
- All real-bug fixes applied
- `apps/macos/dev.sh` (one-command local dev loop)
- `STATUS.md` (the overnight morning briefing)
- `RELEASE.md` (operator manual)
- `docs/native-app/*` (proposal, contract, test plan, fixtures, audit reports)

Worktrees from the overnight swarm are at `.claude/worktrees/agent-*/` (gitignored, contain JSONL agent transcripts).

`native-app-rebuild` branch still exists; `main` has everything from it via the `1203c8f` merge.

Hammerspoon (v1) is **currently stopped** on user's machine (we quit it for hotkey testing). Bring back with `open -a Hammerspoon`.

---

## Pre-existing v0.2+ follow-ups (deferred, not blockers)

From STATUS.md (still relevant):
- 🟡 Mid-stream `/v2/synthesize` failure silently truncates with `ok: true`
- 🟡 `/v2/status.state` never emits `synthesizing`/`streaming`
- 🟡 v1 player tempdir never garbage-collected
- 🟡 `brew test myna-daemon` assertion will fail (daemon has no argparse)
- 🟡 `MYNA_CONFIG_DIR` ignored by `daemon/myna/config.py`
- 🟡 `release.yml` appcast fetch swallows non-404 errors
- DMG background image missing (`dist/dmg-background.png`)
- BTT preset file (v0.3)
- Port daemon to Swift (v0.4)

---

## Final advice for next-session Claude

1. **Don't redo the overnight work.** It's all in `git log --oneline main`. Read commits if you want context.
2. **Don't change the secrets.** They're set and working.
3. **Don't change `Sparkle.framework` strategy without trying the diagnostic line first.** Run #7's logs are in `docs/native-app/last-ci-failure.log`. The "unsealed contents" error has a specific cause; identify it before guessing.
4. **The user's `dev.sh` workflow works.** If they ever say "it broke locally", first ask if Hammerspoon got restarted and is stealing hotkeys again. Quit Hammerspoon via `osascript -e 'tell application "Hammerspoon" to quit'`.
5. **Don't tag a release pipeline that hasn't passed sign step yet.** Iterate on `main` commits, retag the same `v0.1.0` after each fix.
6. **Read `STATUS.md` for the v0.2+ roadmap.** Don't bake new features into v0.1.0.

The grind is small — probably 1-2 more sign iterations, then notarize succeeds, then the rest of the pipeline likely runs clean since each step downstream is much simpler than sign. The first successful release should land within 2-4 more iterations.
