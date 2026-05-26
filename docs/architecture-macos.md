# Myna — macOS Native App Architecture

> Authoritative architecture reference for the Swift menu-bar app at `apps/macos/`. Tracks the v0.1.0 shipped tree (Lane A of the v2 native-app rebuild). Companion docs: [API_CONTRACT.md](native-app/API_CONTRACT.md), [NATIVE_APP_PROPOSAL.md](native-app/NATIVE_APP_PROPOSAL.md), [TEST_PLAN.md](native-app/TEST_PLAN.md).

---

## 1. Executive Summary

Myna.app is a **menu-bar-only macOS application** that replaces the v1 Hammerspoon script (`hammerspoon/myna.lua`, 322 lines) with a native Swift host for the local TTS pipeline. It speaks the user's selected text or the front Chrome article, controlled by global hotkeys, the menu bar, the Settings window, or `myna://` URLs.

**What it is:**

- A **client** of the local Python daemon (`daemon/myna/`) over `http://127.0.0.1:8766`. It never talks to a remote network host.
- A **playback host**: it owns the audio engine (`AVAudioEngine` + `AVAudioUnitTimePitch`) so it can do real speed change (no chipmunk pitch), scrubable seeking, and pause/resume that the v1 `afplay` pipeline could never do.
- A **menu-bar agent**: `LSUIElement=YES` means no Dock icon, no main window, no app switcher entry. The UI is a `MenuBarExtra` plus a SwiftUI `Settings` scene.
- A **URL-scheme target** (`myna://...`) so BetterTouchTool, Shortcuts.app, and shell automations can drive playback without simulating keystrokes.
- A **Sparkle host** for EdDSA-signed delta updates from a GitHub Releases appcast.

**What it is NOT:**

- Not a sandboxed app — sandboxing would break `CGEvent.post(.cghidEventTap)` (Cmd+C simulation) and AppleScript over Chrome.
- Not a TTS engine — synthesis happens in the Python daemon (which talks to Kokoro at `127.0.0.1:8765`). The Swift app only consumes the WAV byte stream.
- Not a daemon manager — the launchd plist is owned by the Homebrew formula (`tap/Formula/myna-daemon.rb`). The "Restart Daemon" button in Settings shells out to `launchctl`.
- Not a Catalyst/SwiftUI-on-iOS hybrid. It's pure native macOS, AppKit-backed, deployment target macOS 13.0 (Ventura) so the install base is the broadest plausible.

**Lifecycle in one sentence:** XcodeGen synthesises `Myna.xcodeproj` from `project.yml` → `xcodebuild` produces `Myna.app` → `.app` is signed/notarized/stapled by `dist/*.sh` → packaged into a `.dmg` → distributed via the Homebrew tap `PrerakGada/homebrew-tap` and auto-updated via Sparkle 2.

---

## 2. Technology Stack

| Category | Technology | Version | Justification |
|---|---|---|---|
| Language | Swift | 6.0 (strict concurrency: `complete`) | Project pinned in [`project.yml:14`](../apps/macos/project.yml). Strict concurrency catches Sendable bugs that would otherwise hide until release. |
| UI (declarative) | SwiftUI | macOS 13+ | `MenuBarExtra`, `Settings`, `TabView`, `Form`, `KeyboardShortcuts.Recorder`. |
| UI (legacy bridges) | AppKit | macOS 13+ | `NSApplication`, `NSPasteboard`, `NSWorkspace`, `NSAppleScript`, `CGEvent` — anything SwiftUI doesn't cover. |
| Audio engine | AVFoundation | system | `AVAudioEngine` graph with `AVAudioPlayerNode` → `AVAudioUnitTimePitch` → `mainMixerNode`. Native, no third-party deps. |
| Networking | Foundation `URLSession` | system | Ephemeral session per `DaemonClient`, `URLSession.bytes(for:)` for the multipart stream. |
| Concurrency | Swift Concurrency (`actor`, `@MainActor`, `AsyncThrowingStream`) | Swift 6 | Replaces GCD and Combine for new code paths. Combine is still used for `@Published` and KVO bridging. |
| Hotkeys | [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | from 2.0.0 | SPM, declared in [`project.yml:25-27`](../apps/macos/project.yml). Carbon Hot-Keys under the hood; provides a SwiftUI `Recorder` for free. |
| Auto-update | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) | from 2.6.0 | SPM, [`project.yml:28-30`](../apps/macos/project.yml). `SPUStandardUpdaterController` with EdDSA-signed appcast. |
| Logging | OSLog (`Logger`) + custom file mirror | system | Subsystem `dev.myna.app`. File at `~/Library/Logs/Myna/myna.log`, rotated at 5 MB × 5 archives. |
| Project gen | [yonaskolb/XcodeGen](https://github.com/yonaskolb/XcodeGen) | brew | `project.yml` is source-of-truth; the `.xcodeproj` is generated and gitignored. |
| Lint | SwiftLint | brew | Config in [`.swiftlint.yml`](../apps/macos/.swiftlint.yml). |
| Format | swift-format | brew | Config in [`.swift-format`](../apps/macos/.swift-format). |
| Tests | XCTest | system | 14 test files, ~91 tests (one fixture-loaded), in-process `URLProtocol` stub for network. |
| Distribution | Homebrew cask | — | `tap/Casks/myna.rb` installs the `.dmg`. |

No CocoaPods, no Carthage. SPM only.

---

## 3. Architecture Pattern

**Menu-bar-only NSApplication with SwiftUI islands.** The `@main` entry point ([`MynaApp.swift:11-27`](../apps/macos/Sources/MynaApp/MynaApp.swift)) is a SwiftUI `App` declaring two scenes:

1. `MenuBarExtra { RootMenuBarView } label: { BirdIcon.image }` — the bird in the menu bar and its dropdown.
2. `Settings { RootSettingsView }` — opened by `SettingsLink` (macOS 14+) or AppKit selector fallbacks (macOS 13).

Both scenes are shimmed through `@NSApplicationDelegateAdaptor(AppDelegate.self)`. The delegate, not the SwiftUI scenes, owns the long-lived singletons. The scenes pull them out of the delegate lazily, gated on `appDelegate.didBootstrap` ([`MynaApp.swift:36`](../apps/macos/Sources/MynaApp/MynaApp.swift)) so the menu re-renders the moment the singletons land.

**Why an AppDelegate at all?** Because:

- We need `applicationDidFinishLaunching` to detect XCTest and skip live audio/hotkey setup. Pure SwiftUI scenes have no equivalent escape hatch.
- We need `application(_:open:)` to receive `myna://` URLs.
- We need `applicationWillTerminate` to call `menuController.stop()`, `hotkeys.disableAll()`, and `player.stop()`.
- AppKit-only APIs (`AXIsProcessTrustedWithOptions`, `NSApp.setActivationPolicy`) live more naturally in a delegate than in a scene body.

**Concurrency model:** Most of the app is `@MainActor`. The two exceptions are:

- `DaemonClient`: an `actor` — its own concurrency boundary. It exposes one `nonisolated` async helper (`synthesize(_:)`) that returns an `AsyncThrowingStream`, so callers can iterate without re-entering the actor on every chunk.
- `MultipartChunkParser` ([`SynthesizeStream.swift:30`](../apps/macos/Sources/Network/SynthesizeStream.swift)): plain class, not thread-safe by intent — one parser per response stream.

**Why no Redux/TCA/MVVM-everywhere?** The project shipped on a one-night build budget with three parallel agents in worktrees. Singletons in `AppDelegate` + `ObservableObject` view models is the smallest-surface-area choice that still passes `SWIFT_STRICT_CONCURRENCY=complete`.

---

## 4. Module-by-Module Breakdown

### 4.1 `MynaApp/` — app entry + delegate + dispatcher

Files:

- [`MynaApp.swift`](../apps/macos/Sources/MynaApp/MynaApp.swift) — `MynaApp` (the `@main` SwiftUI `App`), `RootMenuBarView`, `RootSettingsView` (file-private shims).
- [`AppDelegate.swift`](../apps/macos/Sources/MynaApp/AppDelegate.swift) — `AppDelegate: NSObject, NSApplicationDelegate, ObservableObject`. Owns 10 singletons.
- [`AppDispatcher.swift`](../apps/macos/Sources/MynaApp/AppDispatcher.swift) — `AppDispatcher: URLSchemeDispatching`. Concrete implementation of the protocol that hotkeys + URL scheme both call into.

**Responsibilities:**

- Wire up every long-lived service in `bootstrap()` ([`AppDelegate.swift:88-113`](../apps/macos/Sources/MynaApp/AppDelegate.swift)). Order matters: settings → client → audio → input → dispatcher → URL handler → hotkeys → updater → menu controller.
- Detect XCTest (`ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`, [`AppDelegate.swift:125-127`](../apps/macos/Sources/MynaApp/AppDelegate.swift)) and skip bootstrap entirely so tests don't fight the system audio session or grab global hotkeys.
- Trigger the Accessibility TCC prompt on first launch via `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])` ([`AppDelegate.swift:137-142`](../apps/macos/Sources/MynaApp/AppDelegate.swift)).
- Decode incoming WAV chunks to `AVAudioPCMBuffer` via a temp-file roundtrip (`AppDispatcher.decodeWAV`, [`AppDispatcher.swift:114-133`](../apps/macos/Sources/MynaApp/AppDispatcher.swift)) — `AVAudioFile(forReading:)` doesn't accept raw `Data`.

**Concurrency:** Both classes are `@MainActor`. `bootstrap()` runs on the main actor; the synthesise loop in `AppDispatcher.synthesizeAndPlay` is an unstructured `Task {}` that awaits `client.synthesize(req)` and decodes chunks on a `Task.detached`-style await.

**External deps:** `AppKit`, `ApplicationServices` (for `AXIsProcessTrustedWithOptions`), `Combine` (`@Published`), `AVFoundation`, `Foundation`.

**Notable design decisions:**

- IUO singletons rather than lazy lets, because the test host loads the app first and constructing an `AudioPlayer` in `init()` would grab the audio session before tests can create their own ([`AppDelegate.swift:21-27`](../apps/macos/Sources/MynaApp/AppDelegate.swift)).
- `@Published private(set) var didBootstrap = false` ([`AppDelegate.swift:41`](../apps/macos/Sources/MynaApp/AppDelegate.swift)) is the published gate the SwiftUI `RootMenuBarView` reads. Without `@Published`, the menu was permanently stuck on the "Myna initialising…" fallback.
- `applicationWillTerminate` is guarded by `guard didBootstrap else { return }` ([`AppDelegate.swift:144-152`](../apps/macos/Sources/MynaApp/AppDelegate.swift)) — fixes the test-host crash flagged by Lane A audit 🟡 #4.

### 4.2 `Network/` — daemon HTTP client + multipart parser + wire types

Files:

- [`DaemonClient.swift`](../apps/macos/Sources/Network/DaemonClient.swift) — `actor DaemonClient`. 327 lines.
- [`DaemonTypes.swift`](../apps/macos/Sources/Network/DaemonTypes.swift) — Codable structs/enums mirroring [API_CONTRACT.md § 4](native-app/API_CONTRACT.md). 366 lines.
- [`SynthesizeStream.swift`](../apps/macos/Sources/Network/SynthesizeStream.swift) — `MultipartChunkParser` and `MultipartPart`. 209 lines.

**Responsibilities:**

- Wrap every v2 endpoint as an `async throws` method: `health()`, `status()`, `voices(forceRefresh:)`, `extract(url:)`, `summarize(text:)`, `synthesize(_:)`, plus v1 `announce(...)`, `registry()`, `playItem(id:mode:)`.
- Parse `multipart/mixed; boundary=mynachunk` incrementally so the audio pipeline can start playing chunk 0 while chunk N is still synthesising.
- Translate HTTP status + JSON `{reason: ...}` payloads into typed `DaemonError` cases ([`DaemonClient.swift:293-313`](../apps/macos/Sources/Network/DaemonClient.swift)).
- Validate inputs locally before the round-trip — e.g. `validateSynthesizeRequest` rejects empty text and the both-text-and-url combo ([`DaemonClient.swift:142-150`](../apps/macos/Sources/Network/DaemonClient.swift)).

**Concurrency:** `DaemonClient` is an `actor`. State is the immutable `baseURL`/`session` plus the mutable `cachedVoices` array. The `synthesize(_:)` method is `nonisolated` because it returns an `AsyncThrowingStream`; it spawns a `Task` that awaits back into the actor through `runSynthesize` ([`DaemonClient.swift:97-138`](../apps/macos/Sources/Network/DaemonClient.swift)).

**Wire types** ([`DaemonTypes.swift`](../apps/macos/Sources/Network/DaemonTypes.swift)): `DaemonState`, `EngineInfo`, `DaemonInfo`, `DaemonConfig`, `RegistryItem`, `RegistryInfo`, `DaemonStatus`, `Voice`, `VoicesResponse`, `SynthesizeMode`, `SynthesizeRequest`, `SynthesizedChunk`, `ExtractRequest/Response`, `SummarizeRequest/Response`, `AnnounceRequest/Response`, `HealthResponse`, `PlayMode`, `PlayResponse`, `DaemonError`. All are `Codable, Sendable, Equatable`. Snake-case JSON keys are mapped via `CodingKeys`.

**Notable design decisions:**

- Ephemeral `URLSession` per client ([`DaemonClient.swift:36-41`](../apps/macos/Sources/Network/DaemonClient.swift)) — no shared cache or cookies. Two distinct timeouts: `defaultRequestTimeout = 30s`, `synthesizeTimeout = 600s` (a full article can take a while on a cold-engine Kokoro).
- Multipart parser handles arbitrary byte fragmentation including one-byte-at-a-time delivery ([`DaemonClient.swift:154-175`](../apps/macos/Sources/Network/DaemonClient.swift) accumulates 4 KiB before feeding the parser; `MultipartChunkParser.takeNextPart` re-tries when it doesn't have a complete header block or body yet, [`SynthesizeStream.swift:75-146`](../apps/macos/Sources/Network/SynthesizeStream.swift)). This is covered by `test_synthesize_handles_partial_chunk_boundary`.
- `DaemonError.transport(String)` — the spec specifies `transport(Error)`, but `Error` isn't `Sendable` cleanly and we want to compare errors in tests. Drift documented in [STATUS.md § Lane A audit](../STATUS.md).
- `validateHTTPURL` is `public static` ([`DaemonClient.swift:318-325`](../apps/macos/Sources/Network/DaemonClient.swift)) so other layers (ChromeService, URLScheme) can reuse it.

### 4.3 `Audio/` — playback graph + virtual timeline

Files:

- [`AudioPlayer.swift`](../apps/macos/Sources/Audio/AudioPlayer.swift) — `@MainActor public final class AudioPlayer: ObservableObject`. 414 lines.
- [`PlaybackQueue.swift`](../apps/macos/Sources/Audio/PlaybackQueue.swift) — pure value-type-ish struct: `QueuedChunk`, `ChunkPosition`, `PlaybackQueue`. 87 lines.
- [`TimePitchUnit.swift`](../apps/macos/Sources/Audio/TimePitchUnit.swift) — thin facade over `AVAudioUnitTimePitch`. 32 lines.

**Responsibilities:**

- Own the `AVAudioEngine` graph: `AVAudioPlayerNode` → `AVAudioUnitTimePitch` → `mainMixerNode` → output ([`AudioPlayer.swift:41-86`](../apps/macos/Sources/Audio/AudioPlayer.swift)).
- Append PCM buffers (one per WAV chunk), auto-start playback on first enqueue.
- Pause/resume preserving position; stop clearing the queue.
- Speed change clamped to `[0.5, 2.0]` ([`TimePitchUnit.swift:10-11`](../apps/macos/Sources/Audio/TimePitchUnit.swift)); pitch is locked at 0 to avoid the chipmunk effect.
- Seek by absolute global position or by delta, across multiple chunks, via `PlaybackQueue.locate(globalPosition:)`.
- Publish `state`, `position`, `duration`, `speed` as `@Published` for SwiftUI.

**Concurrency:** Whole class is `@MainActor`. `AVAudioEngine` schedule-completion callbacks fire on the engine's render thread; they hop back to main with `Task { @MainActor in ... }` ([`AudioPlayer.swift:296-300`](../apps/macos/Sources/Audio/AudioPlayer.swift)). A `sessionToken: Int` is bumped on `stop()` and `seek(to:)`; late callbacks check `token == sessionToken` and no-op if stale ([`AudioPlayer.swift:353-355`](../apps/macos/Sources/Audio/AudioPlayer.swift)).

**Notable design decisions:**

- **Graph wired lazily** ([`AudioPlayer.swift:262-272`](../apps/macos/Sources/Audio/AudioPlayer.swift)). `AVAudioEngine.connect(_:to:format:)` needs a concrete format; we don't have one until the first PCM buffer arrives. If the format changes between sessions, we disconnect and re-wire.
- **No deinit cleanup** ([`AudioPlayer.swift:88-94`](../apps/macos/Sources/Audio/AudioPlayer.swift)). Swift 6 strict concurrency forbids touching `@MainActor` state from a nonisolated `deinit`. `stop()` is the documented teardown; the position `Timer` leaks harmlessly on dealloc.
- **Wall-clock `position`** ([`AudioPlayer.swift:64`](../apps/macos/Sources/Audio/AudioPlayer.swift)). Sample-accuracy via `AVAudioTime + lastRenderTime` is racy (nil for the first render quantum, giving 0 for the first ~150 ms). Wall-clock is fine for menu-bar position display; AV-sync would need the proper path.
- **Seek-mid-buffer fallback** ([`AudioPlayer.swift:303-318`](../apps/macos/Sources/Audio/AudioPlayer.swift)). `scheduleSegment` requires `AVAudioFile`, so we materialise the buffer to a temp `.caf` and cache the file handle in `bufferFileCache: [ObjectIdentifier: AVAudioFile]`. The cache survives until the next `stop()`.
- **🟡 Known bug** ([`AudioPlayer.swift:341`](../apps/macos/Sources/Audio/AudioPlayer.swift)): on temp-file write failure inside `mapBufferToFile`, the code currently `fatalError`s. Should return early and log. Deferred per Lane A audit.

**`PlaybackQueue` math:**

- `totalDuration` = sum of all chunk durations (rate-independent).
- `locate(globalPosition:)` walks chunks until it finds the one containing `position`; clamps to `[0, last]` on out-of-range.
- `globalPosition(forChunk:offset:)` is the inverse mapping.

This is the only thing that lets `seek(to: 12.5)` work when chunks are 2 s each — the player calls `queue.locate(globalPosition: 12.5)` → `(chunkIndex: 6, offsetInChunk: 0.5)` → `scheduleChunk(index: 6, fromOffset: 0.5, ...)` plus follow-on chunks.

### 4.4 `Input/` — selection capture, Chrome bridge, hotkeys

Files:

- [`SelectionService.swift`](../apps/macos/Sources/Input/SelectionService.swift) — `SelectionService`, `PasteboardProtocol`, `KeyPostingProtocol`, `NSPasteboardAdapter`, `CGEventKeyPoster`. 133 lines.
- [`ChromeService.swift`](../apps/macos/Sources/Input/ChromeService.swift) — `ChromeService`, `AppleScriptRunnerProtocol`, `NSAppleScriptRunner`. 61 lines.
- [`HotkeyManager.swift`](../apps/macos/Sources/Input/HotkeyManager.swift) — `HotkeyManager`, `HotkeyAction`, plus `KeyboardShortcuts.Name` extensions. 113 lines.

**Responsibilities:**

- **`SelectionService`**: capture the user's selected text in any app by simulating Cmd+C, sleeping for 120 ms, reading `NSPasteboard.general`, and restoring the prior pasteboard via `defer`.
- **`ChromeService`**: get the URL of the front Chrome tab via NSAppleScript, with a 5-second AppleScript-level timeout and an `http(s)://`-scheme validation gate.
- **`HotkeyManager`**: wrap `KeyboardShortcuts` SPM library, register handlers for the five Myna shortcuts, mirror v1 defaults exactly.

**Concurrency:** All three services are `@unchecked Sendable` (they hold only stateless protocol adapters). `HotkeyManager` is `@MainActor`. Handlers fire via `KeyboardShortcuts.onKeyDown` which is bridged back to main with `Task { @MainActor in handler() }` ([`HotkeyManager.swift:83-87`](../apps/macos/Sources/Input/HotkeyManager.swift)).

**External deps:** `AppKit`, `Foundation`, `KeyboardShortcuts` (SPM).

**Notable design decisions:**

- **Protocol injection everywhere** so tests can fake the pasteboard and CGEvent without needing TCC permission on the test host. `SelectionService(pasteboard:keyPoster:copyWaitNanos:)` takes three injectable seams ([`SelectionService.swift:101-109`](../apps/macos/Sources/Input/SelectionService.swift)). `ChromeService(runner:)` likewise ([`ChromeService.swift:28-30`](../apps/macos/Sources/Input/ChromeService.swift)).
- **`defer { pasteboard.restore(snapshot) }`** ([`SelectionService.swift:121`](../apps/macos/Sources/Input/SelectionService.swift)) — restores the clipboard on every exit path including `Task` cancellation during the 120 ms sleep. Fixes Security audit 🟡 #3.
- **120 ms copy-wait** ([`SelectionService.swift:99`](../apps/macos/Sources/Input/SelectionService.swift)) is the empirically-smallest window where Safari, Chrome, Slack, Mail, and Notes have all finished their copy handlers. Smaller windows produced flaky captures in Slack and Notes.
- **AppleScript timeout** ([`ChromeService.swift:39-43`](../apps/macos/Sources/Input/ChromeService.swift)): `with timeout of 5 seconds … end timeout` so a wedged Chrome (beachball, mid-crash, stuck script) can't hang the menu bar. Fixes Security audit 🟡 #1.
- **Defaults mirror v1** ([`HotkeyManager.swift:18-48`](../apps/macos/Sources/Input/HotkeyManager.swift)) — cmd+alt+shift+S/A/R/space/. exactly matches `hammerspoon/myna.lua` DEFAULT_BINDINGS. Verified by `test_default_shortcuts_match_v1_for_compatibility`.

### 4.5 `MenuBar/` — controller + view + icon

Files:

- [`MenuBarController.swift`](../apps/macos/Sources/MenuBar/MenuBarController.swift) — `@MainActor public final class MenuBarController: ObservableObject`. 118 lines.
- [`MenuBarView.swift`](../apps/macos/Sources/MenuBar/MenuBarView.swift) — SwiftUI `MenuBarView`. 119 lines.
- [`BirdIcon.swift`](../apps/macos/Sources/MenuBar/BirdIcon.swift) — `enum BirdIcon` exposing `Image(systemName: "bird")`. 16 lines.

**Responsibilities:**

- Drive a 1.5-second polling loop against `/v2/status` ([`MenuBarController.swift:14`](../apps/macos/Sources/MenuBar/MenuBarController.swift)) — same cadence as v1.
- Expose `@Published` `reachability`, `status`, `registry` for the SwiftUI menu to bind.
- Surface menu actions: `togglePause()`, `stopPlayback()`, `setSpeed(_:)`, `seek(delta:)`, `playRegistry(item:mode:)`, `openSettings()`, `openLogs()`.

**Concurrency:** `@MainActor`. Poll loop is a `Task` stored in `pollTask` ([`MenuBarController.swift:40-46`](../apps/macos/Sources/MenuBar/MenuBarController.swift)); cancellable via `stop()`.

**Notable design decisions:**

- **`openSettings()` fallback path** ([`MenuBarController.swift:100-113`](../apps/macos/Sources/MenuBar/MenuBarController.swift)): on macOS 14+ the menu uses `SettingsLink` (the only reliable way to open Settings from an `LSUIElement` app). On macOS 13 we activate the app and try both `showSettingsWindow:` and `showPreferencesWindow:` selectors (renamed between Ventura and Sonoma).
- **Bird is an SF Symbol** ([`BirdIcon.swift:11-14`](../apps/macos/Sources/MenuBar/BirdIcon.swift)) — `Image(systemName: "bird")`. v0.1 shipped this for immediate recognisability; a custom asset can replace it without API churn.
- **`MenuBarView` binds two observed objects** ([`MenuBarView.swift:7-13`](../apps/macos/Sources/MenuBar/MenuBarView.swift)): `controller` (for daemon status) and `player` (for transport state). Two `@ObservedObject`s means two `objectWillChange` paths; either one re-renders the menu.

### 4.6 `Settings/` — view model + 4-tab UI

Files:

- [`SettingsView.swift`](../apps/macos/Sources/Settings/SettingsView.swift) — `TabView` with 4 tabs. 26 lines.
- [`SettingsViewModel.swift`](../apps/macos/Sources/Settings/SettingsViewModel.swift) — `SettingsKey`, `SettingsDefaults`, `SettingsStore`, `SettingsViewModel`. 203 lines.
- [`HotkeysTab.swift`](../apps/macos/Sources/Settings/HotkeysTab.swift) — 5 `KeyboardShortcuts.Recorder` rows. 28 lines.
- [`VoiceTab.swift`](../apps/macos/Sources/Settings/VoiceTab.swift) — voice picker + speed slider + summary-mode toggle. 59 lines.
- [`DaemonTab.swift`](../apps/macos/Sources/Settings/DaemonTab.swift) — daemon URL/port, engine URL/port, health indicator, "Restart Daemon". 112 lines.
- [`AdvancedTab.swift`](../apps/macos/Sources/Settings/AdvancedTab.swift) — log level picker, "Open Logs Folder", "Clear Cache", "Reset All Settings". 57 lines.

**Responsibilities:**

- Persist user preferences in `UserDefaults` under the `dev.myna.app.*` keyspace.
- Validate the daemon URL is localhost-only (defence-in-depth — see `validateDaemonURL` at [`SettingsViewModel.swift:129-141`](../apps/macos/Sources/Settings/SettingsViewModel.swift)).
- Surface the daemon health and restart action.
- Provide reset and cache-clearing operations.

**Concurrency:** `SettingsViewModel` is `@MainActor` `ObservableObject`. `SettingsStore` is `@unchecked Sendable` (the wrapped `UserDefaults` is thread-safe).

**Notable design decisions:**

- **`ObservableObject + @Published` over `@Observable`** ([`SettingsViewModel.swift:6-10`](../apps/macos/Sources/Settings/SettingsViewModel.swift)): `@Observable` requires macOS 14, and the deployment target is 13.0. Migration is one targeted edit when the floor bumps.
- **Persistence via `didSet`** on every `@Published`: writes through to `SettingsStore` on assignment. Speed is clamped before persisting ([`SettingsViewModel.swift:91-100`](../apps/macos/Sources/Settings/SettingsViewModel.swift)).
- **Daemon URL validation** rejects any host that isn't `127.0.0.1`, `localhost`, or `::1`. We never want this app pointing at a remote daemon.
- **🟡 Known tech debt** ([`DaemonTab.swift:86`](../apps/macos/Sources/Settings/DaemonTab.swift)): `restartDaemon()` hardcodes the plist path as `~/Library/LaunchAgents/dev.myna.daemon.plist`. Lane B owns the actual plist; if either side renames, both must update.
- **Reset-all** wipes every `dev.myna.app.*` key and writes back the defaults ([`SettingsViewModel.swift:172-184`](../apps/macos/Sources/Settings/SettingsViewModel.swift)).
- **`clearCache`** removes `~/Library/Caches/Myna/` and re-creates the directory ([`SettingsViewModel.swift:188-202`](../apps/macos/Sources/Settings/SettingsViewModel.swift)).

### 4.7 `URLScheme/` — `myna://` parser + dispatcher

Files:

- [`URLSchemeHandler.swift`](../apps/macos/Sources/URLScheme/URLSchemeHandler.swift) — `URLSchemeAction`, `URLSchemeDispatching`, `URLSchemeHandler`. 139 lines.

**Responsibilities:**

- Parse `myna://...` URLs into typed `URLSchemeAction` cases.
- Validate and clamp numeric parameters before dispatch.
- Explicitly drop any route that would take arbitrary text from a URL.
- Route to the injected `URLSchemeDispatching` (concrete implementation lives in `AppDispatcher`).

**Concurrency:** `@MainActor`. The dispatcher protocol is `@MainActor`-isolated.

**Notable design decisions:**

- **No `myna://speak?text=...`** ([`URLSchemeHandler.swift:128-130`](../apps/macos/Sources/URLScheme/URLSchemeHandler.swift)). Any local process can fire URL events; we never speak attacker-controlled text. The audit test `test_no_arbitrary_text_speak` ([`URLSchemeHandlerTests.swift:131-140`](../apps/macos/Tests/URLSchemeTests/URLSchemeHandlerTests.swift)) and the dedicated `AuditSecurityURLSchemeTests` ([`AuditSecurityURLSchemeTests.swift`](../apps/macos/Tests/URLSchemeTests/AuditSecurityURLSchemeTests.swift)) lock this in.
- **Clamping ranges** ([`URLSchemeHandler.swift:52-54`](../apps/macos/Sources/URLScheme/URLSchemeHandler.swift)): seek delta `±3600s`, speed `[0.5, 2.0]`. Both enforced inside `parse(_:)` so unsafe values never reach the dispatcher.
- **Pure parser exposed for testing** ([`URLSchemeHandler.swift:92-131`](../apps/macos/Sources/URLScheme/URLSchemeHandler.swift)). The dispatch is a thin switch.

### 4.8 `Updates/` — Sparkle 2 host

Files:

- [`UpdateController.swift`](../apps/macos/Sources/Updates/UpdateController.swift) — `UpdateController`, `CheckForUpdatesMenuItem`. 91 lines.

**Responsibilities:**

- Construct `SPUStandardUpdaterController(startingUpdater: true, ...)` so Sparkle's scheduled-check timer starts immediately ([`UpdateController.swift:41-49`](../apps/macos/Sources/Updates/UpdateController.swift)).
- Mirror `updater.canCheckForUpdates` into a `@Published` so SwiftUI can bind `.disabled(!canCheckForUpdates)` on the menu item ([`UpdateController.swift:53-60`](../apps/macos/Sources/Updates/UpdateController.swift)).
- Expose `checkForUpdates()` for the menu button.

**Concurrency:** `@MainActor`. KVO publisher hops to main via `.receive(on: DispatchQueue.main)`.

**External config:** `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUEnableInstallerLauncherService` live in `Info.plist` (generated from [`project.yml:59-62`](../apps/macos/project.yml)). Sparkle reads them at init time — no extra wiring.

### 4.9 `Logging/` — OSLog + file mirror + viewer

Files:

- [`Log.swift`](../apps/macos/Sources/Logging/Log.swift) — `LogCategory`, `LogLevel`, `LogFileMirror`, `Log`. 159 lines.
- [`LogViewerView.swift`](../apps/macos/Sources/Logging/LogViewerView.swift) — SwiftUI `LogViewerView`. 96 lines.

**Responsibilities:**

- Emit structured log lines to OSLog (subsystem `dev.myna.app`) for Console.app + `log show`.
- Mirror the same lines to `~/Library/Logs/Myna/myna.log` with size-based rotation (5 MB cap, keep 5 archives).
- Provide an in-app SwiftUI viewer that tails the file every 2 s with level filtering, copy, and reveal-in-Finder.

**Concurrency:** `Log` is `Sendable` (immutable). `LogFileMirror` serialises writes through a `DispatchQueue(label: "dev.myna.log.file", qos: .utility)`.

**Categories:** `app`, `audio`, `network`, `input`, `urlscheme`, `settings`. Picked to match the module taxonomy so `log show --subsystem dev.myna.app --category urlscheme` is a useful filter.

---

## 5. App Lifecycle & Dispatch

```
SwiftUI App startup
  └─ @NSApplicationDelegateAdaptor → AppDelegate.applicationDidFinishLaunching
       ├─ NSApp.setActivationPolicy(.accessory)
       ├─ if XCTest → return (skip bootstrap)
       ├─ bootstrap()
       │    ├─ SettingsViewModel
       │    ├─ DaemonClient(baseURL: settings.fullDaemonBaseURL ?? defaultBaseURL)
       │    ├─ AudioPlayer
       │    ├─ SelectionService, ChromeService
       │    ├─ AppDispatcher (knows about all of the above)
       │    ├─ URLSchemeHandler(dispatcher: AppDispatcher)
       │    ├─ HotkeyManager
       │    ├─ UpdateController (starts Sparkle)
       │    ├─ MenuBarController (does NOT start polling yet)
       │    └─ didBootstrap = true  ← @Published, triggers SwiftUI re-render
       ├─ promptForAccessibilityIfNeeded()        ← TCC prompt
       ├─ hotkeys.register(handlers: [.speakSelectionFull: ..., ...])
       └─ menuController.start()                    ← polling begins
```

`application(_:open:)` ([`AppDelegate.swift:154-159`](../apps/macos/Sources/MynaApp/AppDelegate.swift)) receives `myna://` URLs and forwards to `urlHandler.handle(urls)`. Guarded by `didBootstrap` so the test host doesn't crash if AppKit fires open-URL events during launch.

`applicationWillTerminate` ([`AppDelegate.swift:144-152`](../apps/macos/Sources/MynaApp/AppDelegate.swift)) stops the menu poll, disables hotkeys, and stops the audio player. Also guarded by `didBootstrap`.

The **`didBootstrap` flag is load-bearing**: the SwiftUI `MenuBarExtra` body reads `appDelegate.didBootstrap` directly; without `@Published`, the body never re-evaluated after launch and the menu was stuck on "Myna initialising…" in shipped builds.

---

## 6. Audio Pipeline

```
            ┌──────────────────┐    ┌────────────────────────┐    ┌────────────────┐    ┌────────┐
PCM chunks →│ AVAudioPlayerNode│ →  │ AVAudioUnitTimePitch   │ →  │ mainMixerNode  │ →  │ output │
            └──────────────────┘    │ rate ∈ [0.5, 2.0], p=0 │    └────────────────┘    └────────┘
                                    └────────────────────────┘
```

- **Buffers come from `AppDispatcher.decodeWAV`** ([`AppDispatcher.swift:114-133`](../apps/macos/Sources/MynaApp/AppDispatcher.swift)): write the WAV data to a temp file, open with `AVAudioFile(forReading:)`, read into an `AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: file.length)`, delete the temp file.
- **`AudioPlayer.enqueue(buffer:)`** ([`AudioPlayer.swift:100-115`](../apps/macos/Sources/Audio/AudioPlayer.swift)) appends to the queue. If this is the first buffer and the player is idle, it calls `beginSession()`, otherwise it `scheduleChunk(...)` for auto-play.
- **`PlaybackQueue` is a virtual timeline**: each chunk has its own local sample timeline (frames / `format.sampleRate`), and the queue maps global positions ↔ (chunkIndex, offsetInChunk).
- **`setSpeed`** ([`AudioPlayer.swift:175-180`](../apps/macos/Sources/Audio/AudioPlayer.swift)) writes to `timePitch.rate`. Pitch is locked at 0 by `TimePitchUnit.init` ([`TimePitchUnit.swift:15-19`](../apps/macos/Sources/Audio/TimePitchUnit.swift)) and there is no setter — verified by `test_speed_change_does_not_change_pitch`.
- **Seek ±15s** mechanics (from the menu): `seek(delta:)` → `seek(to: position + delta)` → `queue.locate(globalPosition:)` → bump `sessionToken`, stop the player, schedule the target chunk from `offsetInChunk` (slow path via `scheduleSegment` + temp `.caf`), schedule follow-on chunks, restart engine and player ([`AudioPlayer.swift:185-224`](../apps/macos/Sources/Audio/AudioPlayer.swift)).
- **The `position` wall-clock caveat** ([`AudioPlayer.swift:54-64`](../apps/macos/Sources/Audio/AudioPlayer.swift)): `CACurrentMediaTime()` anchored at chunk start, scaled by `timePitch.rate`. Not sample-accurate. The proper path through `playerNode.lastRenderTime` is nil for the first render quantum, which caused position to read 0 for the first ~150 ms. Fine for menu-bar UI; revisit if AV sync is ever needed.

---

## 7. Network Layer

**Actor design** ([`DaemonClient.swift:12`](../apps/macos/Sources/Network/DaemonClient.swift)): one `URLSession` per `DaemonClient` instance, ephemeral config, two timeouts. The actor boundary is mostly there to prevent accidental session sharing across configurations; mutable state is just `cachedVoices`.

**Multipart parser** ([`SynthesizeStream.swift`](../apps/macos/Sources/Network/SynthesizeStream.swift)):

- `boundaryLine = "--mynachunk"`, `closingBoundary = "--mynachunk--"`.
- Stateful: callers feed arbitrary-size byte chunks into `append(_:)` and pull complete parts via `drain()`.
- Headers split on `\r\n\r\n`, body bounded by the next boundary, optional CRLF stripped from the end.
- Three kinds of "not ready yet" early-exits: no first boundary, no header terminator, no following boundary. Each returns `nil` and the caller waits for more bytes.
- Audit-style adversarial input (1-byte-at-a-time delivery): covered by `test_synthesize_handles_partial_chunk_boundary` ([`DaemonClientTests.swift:115-137`](../apps/macos/Tests/NetworkTests/DaemonClientTests.swift)).

**DaemonTypes ↔ daemon `v2_types.py` mapping:** identical fields with snake-case ↔ camelCase via Swift `CodingKeys`. The only deltas:

- Swift's `VoicesResponse` adds `engine: String?` ([`DaemonTypes.swift:156`](../apps/macos/Sources/Network/DaemonTypes.swift)) — present in the daemon's `V2Voices` ([`v2_types.py:100`](../daemon/myna/v2_types.py)) but **not** in `API_CONTRACT.md § 4`. This is undocumented drift; the field is harmless and ignored by Swift `JSONDecoder` if absent.
- The daemon `V2Status` adds `v1_player: V2V1PlayerInfo` ([`v2_types.py:88`](../daemon/myna/v2_types.py)) — the Swift app's `DaemonStatus` ([`DaemonTypes.swift:112-132`](../apps/macos/Sources/Network/DaemonTypes.swift)) does **not** declare this field. `JSONDecoder` ignores it. Documented as "for diagnostics only" in API_CONTRACT.
- `DaemonError.transport(String)` ([`DaemonTypes.swift:338`](../apps/macos/Sources/Network/DaemonTypes.swift)) drifts from spec's `transport(Error)`. Cosmetic; will be resolved in either direction.

**Retry/error strategy:** none built-in. Each call is a one-shot. The `MenuBarController` poll loop catches all errors silently and just flips `reachability = .down`. The dispatcher's `synthesizeAndPlay` logs the error and stops. Sparkle handles its own retries on the appcast.

---

## 8. Selection Capture

The pipeline ([`SelectionService.captureSelectedText`](../apps/macos/Sources/Input/SelectionService.swift:114-132)):

1. `pasteboard.saveSnapshot()` — copy every pasteboard item, including non-string types.
2. `pasteboard.clearContents()` — so we can tell empty selection from "current contents were already what the user had".
3. `defer { pasteboard.restore(snapshot) }` — runs on every exit path including `Task` cancellation. Audit-fix per Security 🟡 #3 and Lane A 🟡 #5.
4. `keyPoster.postCmdC()` — synthesise key-down + key-up for keycode 0x08 ('c') with `.maskCommand` via `CGEvent.post(tap: .cghidEventTap)`. Returns `false` if Accessibility is denied; we short-circuit to `nil`.
5. `try? await Task.sleep(nanoseconds: 120_000_000)` — 120 ms is the empirically-smallest window where every tested app has completed its copy handler.
6. Read `pasteboard.pasteboardString`. If `nil` or empty after trim → `nil`. Otherwise return the trimmed string.

**Accessibility requirement:** `CGEvent.post(.cghidEventTap)` silently no-ops without TCC Accessibility permission. The first launch surfaces the system prompt via `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])` ([`AppDelegate.swift:137-142`](../apps/macos/Sources/MynaApp/AppDelegate.swift)). After grant the user must relaunch Myna for the TCC change to take effect.

---

## 9. Chrome Integration

`ChromeService.frontTabURL()` ([`ChromeService.swift:38-48`](../apps/macos/Sources/Input/ChromeService.swift)) runs:

```applescript
with timeout of 5 seconds
  tell application "Google Chrome" to return URL of active tab of front window
end timeout
```

via `NSAppleScript(source:).executeAndReturnError(_:)`. The result is trimmed and gated through `ChromeService.isValidHTTPURL` (rejects `file://`, `javascript:`, `myna://`, empty, malformed).

**Entitlement requirement:** `com.apple.security.automation.apple-events = true` in [`Resources/Myna.entitlements`](../apps/macos/Resources/Myna.entitlements). The first invocation triggers the macOS Automation TCC prompt ("Myna would like to control Google Chrome"). The `NSAppleEventsUsageDescription` purpose string is set in [`Info.plist:36-37`](../apps/macos/Resources/Info.plist).

**Timeout rationale:** Lane A audit 🟡 — a wedged Chrome (beachball mid-render, runaway content script) without the timeout would block the AppleScript executor indefinitely, hanging the menu bar.

---

## 10. Hotkey System

**Library:** `sindresorhus/KeyboardShortcuts` SPM (Carbon Hot-Keys under the hood). Provides:

- Global hotkey registration via `KeyboardShortcuts.onKeyDown(for:)`.
- A SwiftUI `Recorder` for the Settings UI.
- Conflict detection (it owns the surface).
- Persistence via its own `UserDefaults` key (`KeyboardShortcuts_<name>`).

**Five defaults** ([`HotkeyManager.swift:18-48`](../apps/macos/Sources/Input/HotkeyManager.swift)):

| Action | Default chord | v1 string |
|---|---|---|
| `speakSelectionFull` | ⌘⌥⇧S | `speak_selection_full` |
| `speakSelectionSummary` | ⌘⌥⇧A | `speak_selection_summary` |
| `readChromeArticle` | ⌘⌥⇧R | `read_chrome_article` |
| `pauseResume` | ⌘⌥⇧Space | `pause_resume` |
| `stop` | ⌘⌥⇧. | `stop` |

**Persistence model:** Owned entirely by the library. The user opens Settings → Hotkeys, clicks a `KeyboardShortcuts.Recorder`, presses a chord; the library writes to UserDefaults. Re-registering doesn't reset the user's choice.

**Conflict surface:** if the user picks a chord already bound by another app, KeyboardShortcuts surfaces an alert. There's no in-app conflict UI beyond that.

**Test contract:** `test_default_shortcuts_match_v1_for_compatibility` ([`HotkeyManagerTests.swift:13-40`](../apps/macos/Tests/InputTests/HotkeyManagerTests.swift)) locks in the v1 chords so an inadvertent default change doesn't silently break upgraders.

---

## 11. URL Scheme

Registered in [`Info.plist:19-28`](../apps/macos/Resources/Info.plist) (and [`project.yml:56-58`](../apps/macos/project.yml)) as `CFBundleURLSchemes: [myna]` with name `dev.myna.urlscheme`.

| URL | Action | Validation |
|---|---|---|
| `myna://speak-selection` | `speakSelection(.full)` | none |
| `myna://speak-selection?mode=summary` | `speakSelection(.summary)` | `mode` ignored unless `=summary` |
| `myna://read-chrome` | `readChrome()` | none |
| `myna://toggle-pause` | `togglePause()` | none |
| `myna://stop` | `stop()` | none |
| `myna://seek?delta=±N` | `seek(delta: N)` | clamped to `[-3600, 3600]` |
| `myna://speed?value=N` | `setSpeed(N)` | clamped to `[0.5, 2.0]` |
| `myna://speed?delta=N` | `bumpSpeed(N)` | unclamped delta; player itself clamps the result |

**Deliberately omitted:** `myna://speak?text=...`, `myna://say?text=...`, `myna://announce?text=...` — any local process can post URL events, and we never speak attacker-controlled text. Adversarial inputs are covered by [`AuditSecurityURLSchemeTests.swift`](../apps/macos/Tests/URLSchemeTests/AuditSecurityURLSchemeTests.swift) which is the canonical regression suite — do not delete.

**Parsing quirk:** macOS parses `myna://action` with `host == "action"` and empty path, while `myna:action` (no `//`) parses with empty host. `URLSchemeHandler.parse` handles both by falling back to `path.trimmingCharacters(in: "/")` when `host` is empty ([`URLSchemeHandler.swift:98-100`](../apps/macos/Sources/URLScheme/URLSchemeHandler.swift)).

---

## 12. Settings & Persistence

**Storage:** `UserDefaults.standard` under keys prefixed `dev.myna.app.` ([`SettingsViewModel.swift:16-26`](../apps/macos/Sources/Settings/SettingsViewModel.swift)).

| Key | Type | Default | Notes |
|---|---|---|---|
| `dev.myna.app.voice` | String | `"af_heart"` | Must match daemon's `chunk_chars` default voice |
| `dev.myna.app.defaultSpeed` | Double | `1.0` | Clamped `[0.5, 2.0]` |
| `dev.myna.app.summaryMode` | Bool | `false` | Default mode for new speak operations |
| `dev.myna.app.daemonURL` | String | `"http://127.0.0.1"` | Validated localhost-only |
| `dev.myna.app.daemonPort` | Int | `8766` | |
| `dev.myna.app.engineURL` | String | `"http://127.0.0.1"` | For Kokoro |
| `dev.myna.app.enginePort` | Int | `8765` | |
| `dev.myna.app.logLevel` | String | `"info"` | One of `debug/info/warning/error` |
| `dev.myna.app.useNotifications` | Bool | `false` | Reserved |

**Architectural choice — `ObservableObject + @Published` vs `@Observable`:** the project targets macOS 13 (Ventura). `@Observable` requires macOS 14 (Sonoma). Migration is one targeted edit ([`SettingsViewModel.swift:6-10`](../apps/macos/Sources/Settings/SettingsViewModel.swift)) when the deployment target bumps.

**`@AppStorage` vs `ObservableObject`:** SwiftUI views could read `@AppStorage("dev.myna.app.voice")` directly, but a view model gives us validation (`validateDaemonURL`), aggregate operations (`resetAll`, `clearCache`), and a single test seam (inject `SettingsStore(defaults:)` from an ephemeral `UserDefaults(suiteName:)`). The cost is the `didSet` boilerplate.

**`restartDaemon` plist path** ([`DaemonTab.swift:86`](../apps/macos/Sources/Settings/DaemonTab.swift)): hardcoded `\(NSHomeDirectory())/Library/LaunchAgents/dev.myna.daemon.plist`. Owned by Lane B (Homebrew formula). Both sides need to stay in sync; flagged in STATUS.md.

---

## 13. Menu Bar UI

**Polling cadence:** 1.5 s ([`MenuBarController.swift:14`](../apps/macos/Sources/MenuBar/MenuBarController.swift)), inherited from v1. `/v2/status` is cheap and the menu shows daemon version, engine status, and registry items.

**State model:**

```swift
enum DaemonReachability { case unknown, up, down }
@Published var reachability: DaemonReachability
@Published var status: DaemonStatus?
@Published var registry: [RegistryItem]
```

`refresh()` ([`MenuBarController.swift:55-65`](../apps/macos/Sources/MenuBar/MenuBarController.swift)) calls `client.status()`, on success sets `.up` + the snapshot, on any error sets `.down` and clears the registry.

**Menu view** ([`MenuBarView.swift`](../apps/macos/Sources/MenuBar/MenuBarView.swift)) sections:

1. **Header** — daemon version + engine status, coloured by reachability.
2. **Transport** — Pause/Resume, Stop (disabled when idle).
3. **Speed** — submenu with 0.75 / 1.0 / 1.25 / 1.5 / 2.0.
4. **Seek** — submenu with ±15s and ±30s (disabled when `player.duration == 0`).
5. **Registry** — one submenu per pending Claude-Code output, with Full and Summary actions.
6. **Settings / Logs / Updates** — `SettingsLink` on macOS 14+, selector fallback on 13.
7. **Quit** — `⌘Q`.

**BirdIcon** ([`BirdIcon.swift`](../apps/macos/Sources/MenuBar/BirdIcon.swift)) is just `Image(systemName: "bird")`. The comment notes that state-suffix glyphs (▸/‖/!) are intended to layer via the menu Label, not into the image itself, so dark/light mode handling stays automatic.

---

## 14. Sparkle Integration

**Configured in `Info.plist`** (generated from [`project.yml:59-62`](../apps/macos/project.yml)):

| Key | Value | Purpose |
|---|---|---|
| `SUFeedURL` | `https://github.com/PrerakGada/myna/releases/download/appcast/appcast.xml` | Appcast XML location |
| `SUPublicEDKey` | `lEoEYOBRVnzZC9bysaAYSRpEuXSDmd/FagSmzv2ozHg=` | EdDSA public key (matches `dist/sparkle_private_key.NEVER_COMMIT.txt`) |
| `SUEnableAutomaticChecks` | `YES` | Daily background poll |
| `SUEnableInstallerLauncherService` | `YES` | Required for the installer XPC service in Sparkle 2 |

**Runtime wiring** ([`UpdateController.swift`](../apps/macos/Sources/Updates/UpdateController.swift)):

```swift
SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
```

`startingUpdater: true` starts the scheduled-check timer immediately. `SUEnableAutomaticChecks` in `Info.plist` controls whether it actually fetches.

**Exposed surface:**

- `UpdateController.shared` — singleton fallback for callers that don't have the env-object injected.
- `UpdateController().canCheckForUpdates: Bool` — `@Published`, KVO-mirrored from `updater.canCheckForUpdates`.
- `UpdateController().checkForUpdates()` — show the "checking" dialog now.
- `CheckForUpdatesMenuItem(controller)` — drop-in SwiftUI `Button` for the menu.
- `UpdateController().updater: SPUUpdater` — escape hatch for advanced bindings.

---

## 15. Logging

**OSLog**: `Logger(subsystem: "dev.myna.app", category: <LogCategory>)`. Six categories: `app`, `audio`, `network`, `input`, `urlscheme`, `settings`.

**File mirror** ([`LogFileMirror`](../apps/macos/Sources/Logging/Log.swift:41-132)): `~/Library/Logs/Myna/myna.log`. Rotation: 5 MB cap, keep 5 archives (`myna.log.1` … `myna.log.5`). Writes are serialised on `DispatchQueue(label: "dev.myna.log.file", qos: .utility)`. Format: ISO 8601 timestamp, `[LEVEL]`, `[category]`, message.

**In-app viewer** ([`LogViewerView.swift`](../apps/macos/Sources/Logging/LogViewerView.swift)): tails the file every 2 s, shows the last 1000 lines, supports level filtering, copy-to-clipboard, and reveal-in-Finder.

**Console.app filter:** `subsystem:dev.myna.app` shows all categories; add `category:urlscheme` to narrow.

---

## 16. Hardened Runtime & Entitlements

From [`Resources/Myna.entitlements`](../apps/macos/Resources/Myna.entitlements):

| Entitlement | Value | Why |
|---|---|---|
| `com.apple.security.automation.apple-events` | `true` | Required for `NSAppleScript`-driven Chrome control. |
| `com.apple.security.cs.allow-jit` | `false` | We don't JIT. Keeps the runtime maximally hardened. |
| `com.apple.security.cs.allow-unsigned-executable-memory` | `false` | Same. |
| `com.apple.security.cs.disable-library-validation` | `false` | We only load signed system + SPM-built libraries. |
| `com.apple.security.cs.disable-executable-page-protection` | `false` | No need to mutate code pages. |

**App sandbox** is NOT enabled. Sandboxing would block `CGEvent.post(.cghidEventTap)` (Cmd+C simulation) and confine AppleScript automation. The tradeoff is intentional and documented in the entitlements file header comment.

`ENABLE_HARDENED_RUNTIME = YES` ([`project.yml:16`](../apps/macos/project.yml)) is required for Apple notarization. `AppLifecycleTests.test_entitlements_have_hardened_runtime_compatible_flags` locks the four restrictive flags at their off positions.

---

## 17. Build Settings

From [`project.yml:12-22`](../apps/macos/project.yml):

| Setting | Value | Why |
|---|---|---|
| `SWIFT_VERSION` | `6.0` | Catches Sendable + concurrency bugs at compile time. |
| `MACOSX_DEPLOYMENT_TARGET` | `13.0` | Maximises install base. Drops Monterey but covers everything from Ventura forward (incl. anyone holding back from Sonoma). |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Notarization prerequisite. |
| `CODE_SIGN_STYLE` | `Automatic` | Xcode picks the Developer ID identity automatically; CI overrides via `dist/sign.sh`. |
| `SWIFT_STRICT_CONCURRENCY` | `complete` | Highest level. Fights with Sparkle 2 in places — we annotate `@unchecked Sendable` only where the underlying type is genuinely thread-safe. |
| `DEAD_CODE_STRIPPING` | `YES` | Smaller binary. |
| `ENABLE_USER_SCRIPT_SANDBOXING` | `YES` | Limits what Run Script phases can do. |
| `SWIFT_TREAT_WARNINGS_AS_ERRORS` | `NO` | Sparkle 2 occasionally emits deprecation warnings during version bumps; we don't want those to break the build. |
| `CLANG_ANALYZER_NONNULL` | `YES` | |

**Bundle version flow** ([`project.yml:48-50`](../apps/macos/project.yml)): `CFBundleShortVersionString = $(MARKETING_VERSION)` (which is `0.1.0`), `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`. Lane A audit caught `CFBundleShortVersionString` previously hardcoded as `"1.0"` — Sparkle never offered updates because every release reported the same version. Fixed in commit `2bc4583`.

---

## 18. Source Tree

```
apps/macos/
├── Sources/
│   ├── MynaApp/
│   │   ├── MynaApp.swift              # @main App; MenuBarExtra + Settings scenes
│   │   ├── AppDelegate.swift          # singleton owner; bootstrap; lifecycle
│   │   └── AppDispatcher.swift        # URLSchemeDispatching impl
│   ├── Network/
│   │   ├── DaemonClient.swift         # actor; HTTP client
│   │   ├── DaemonTypes.swift          # Codable wire types + DaemonError
│   │   └── SynthesizeStream.swift     # MultipartChunkParser
│   ├── Audio/
│   │   ├── AudioPlayer.swift          # @MainActor; AVAudioEngine graph
│   │   ├── PlaybackQueue.swift        # virtual timeline math
│   │   └── TimePitchUnit.swift        # AVAudioUnitTimePitch facade
│   ├── Input/
│   │   ├── SelectionService.swift     # Cmd+C + pasteboard
│   │   ├── ChromeService.swift        # AppleScript front-tab URL
│   │   └── HotkeyManager.swift        # KeyboardShortcuts wrapper
│   ├── MenuBar/
│   │   ├── MenuBarController.swift    # polling + actions
│   │   ├── MenuBarView.swift          # SwiftUI menu
│   │   └── BirdIcon.swift             # SF Symbol "bird"
│   ├── Settings/
│   │   ├── SettingsView.swift         # TabView
│   │   ├── SettingsViewModel.swift    # @Published + UserDefaults
│   │   ├── HotkeysTab.swift           # 5 Recorders
│   │   ├── VoiceTab.swift             # voice picker + speed slider
│   │   ├── DaemonTab.swift            # URL/port + health + restart
│   │   └── AdvancedTab.swift          # log level + cache + reset
│   ├── URLScheme/
│   │   └── URLSchemeHandler.swift     # myna:// parser + dispatcher
│   ├── Updates/
│   │   └── UpdateController.swift     # Sparkle 2 host + menu item view
│   └── Logging/
│       ├── Log.swift                  # OSLog + file mirror + rotation
│       └── LogViewerView.swift        # in-app tailing viewer
├── Tests/
│   ├── AudioTests/                    # AudioPlayerTests, PlaybackQueueTests, SineBuffer
│   ├── InputTests/                    # ChromeServiceTests, HotkeyManagerTests, SelectionServiceTests
│   ├── MynaAppTests/                  # AppLifecycleTests, FixtureLoader, LogTests, SendableBox, SkeletonTests
│   ├── NetworkTests/                  # DaemonClientTests, MockURLProtocol
│   ├── SettingsTests/                 # SettingsViewModelTests
│   └── URLSchemeTests/                # URLSchemeHandlerTests, AuditSecurityURLSchemeTests
├── Resources/
│   ├── Assets.xcassets                # AppIcon
│   ├── Info.plist                     # CFBundleURLTypes, SU*, LSUIElement, …
│   └── Myna.entitlements              # Apple-events + hardened-runtime flags
├── project.yml                        # XcodeGen source-of-truth
├── dev.sh                             # kill / xcodegen / xcodebuild / open
├── .swift-format                      # 120 cols, 4 spaces, ordered imports
├── .swiftlint.yml                     # opt-in force_unwrapping + others
└── README.md                          # brief build/test/lint cheatsheet
```

The `Myna.xcodeproj/` directory is generated by XcodeGen and gitignored.

---

## 19. Testing Strategy

**Layout:** XCTest, one folder per source module ([`project.yml:82-98`](../apps/macos/project.yml) declares `MynaTests: type: bundle.unit-test`).

**Counts (as of v0.1.0):** ~91 tests across 14 files.

| Test file | What it covers |
|---|---|
| `AudioTests/AudioPlayerTests.swift` | 14 tests — real AVAudioEngine + sine wave buffers; enqueue, pause/resume, stop, seek across chunks, speed clamping, state publisher, concurrency last-wins |
| `AudioTests/PlaybackQueueTests.swift` | 6 tests — pure timeline math |
| `AudioTests/SineBuffer.swift` | helper: 22.05 kHz mono 440 Hz `AVAudioPCMBuffer` generator, no disk I/O |
| `InputTests/ChromeServiceTests.swift` | 5 tests — stubbed `AppleScriptRunnerProtocol`; URL validation rejects `file://`, `javascript:`, `myna://` |
| `InputTests/HotkeyManagerTests.swift` | 5 tests — locks v1-compatible defaults, action raw strings, register/disable lifecycle |
| `InputTests/SelectionServiceTests.swift` | 4 tests — `FakePasteboard` + `FakeKeyPoster`; clipboard restore including accessibility-denied path |
| `MynaAppTests/AppLifecycleTests.swift` | 5 tests — Info.plist (LSUIElement, URL scheme, min macOS) + entitlements file (apple-events on, hardened-runtime flags off) |
| `MynaAppTests/FixtureLoader.swift` | helper: resolves shared `docs/native-app/fixtures/*.json` from bundle, falls back to walking source tree |
| `MynaAppTests/LogTests.swift` | 3 tests — file mirror append, category coverage, level ordering |
| `MynaAppTests/SendableBox.swift` | helper: lock-protected mutable cell for `@Sendable` closures in tests |
| `MynaAppTests/SkeletonTests.swift` | 4 sentinel tests — bundle id, URL scheme, LSUIElement |
| `NetworkTests/DaemonClientTests.swift` | 16 tests — health/status/voices/extract/summarize/announce/registry/play + 502 mapping + URL validation + timeout config + 1-byte-fragment multipart |
| `NetworkTests/MockURLProtocol.swift` | helper: `URLProtocol` subclass intercepting requests; one-shot and streaming handler queues |
| `SettingsTests/SettingsViewModelTests.swift` | 8 tests — defaults, persistence, clamp, reset, URL validation, fullDaemonBaseURL composition, clearCache |
| `URLSchemeTests/URLSchemeHandlerTests.swift` | 16 tests — all routes, clamping, security (no arbitrary text speak) |
| `URLSchemeTests/AuditSecurityURLSchemeTests.swift` | 1 audit case sweeping 11 adversarial URLs — canonical regression suite from the L0 security audit (2026-05-25), DO NOT delete |

**Key test infrastructure:**

- **`MockURLProtocol`** ([`Tests/NetworkTests/MockURLProtocol.swift`](../apps/macos/Tests/NetworkTests/MockURLProtocol.swift)) — pure-Swift `URLProtocol` registered on an ephemeral `URLSession`. Handlers are pushed by `MockURLProtocol.enqueue` (one-shot) or `enqueueStream` (multipart parts). No sockets opened.
- **`SineBuffer`** ([`Tests/AudioTests/SineBuffer.swift`](../apps/macos/Tests/AudioTests/SineBuffer.swift)) — 22050 Hz mono 0.1-amplitude 440 Hz sine, in-memory. Lets `AudioPlayerTests` exercise the real `AVAudioEngine` with sub-second buffers and stay under a 10 s total wall time.
- **`FixtureLoader`** ([`Tests/MynaAppTests/FixtureLoader.swift`](../apps/macos/Tests/MynaAppTests/FixtureLoader.swift)) — resolves shared JSON fixtures from `docs/native-app/fixtures/`, ferried into the test bundle via [`project.yml:89-92`](../apps/macos/project.yml) (`type: folder` reference).
- **`SendableBox<T>`** ([`Tests/MynaAppTests/SendableBox.swift`](../apps/macos/Tests/MynaAppTests/SendableBox.swift)) — `NSLock`-protected mutable cell, `@unchecked Sendable`. Tests pass it into `@Sendable` closures to record side effects without tripping strict concurrency.

**Test isolation:** `AppDelegate.isRunningTests` skips bootstrap entirely under XCTest. `SettingsViewModelTests` uses a fresh `UserDefaults(suiteName: UUID())` per test. `MockURLProtocol.reset()` runs in setUp/tearDown.

**`AuditSecurityURLSchemeTests`** is the security regression suite. Every URL listed there is an adversarial input from the L0 audit; the test asserts each one either parses to a safe action with clamped parameters or is dropped silently. New URL routes must add their adversarial counterparts here.

---

## 20. Known Bugs & Tech Debt

Sourced from [STATUS.md § Lane A audit](../STATUS.md) and [HANDOFF.md](https://github.com/PrerakGada/myna/blob/f5860c8/HANDOFF.md).

| Severity | Location | Issue | Disposition |
|---|---|---|---|
| 🟡 | [`AudioPlayer.swift:341`](../apps/macos/Sources/Audio/AudioPlayer.swift) | `fatalError` reachable on temp-file write failure during mid-buffer seek. Should return early with a logged error. | **Deferred.** Rare path; gracefully degrades. |
| 🟡 | [`DaemonTypes.swift:338`](../apps/macos/Sources/Network/DaemonTypes.swift) | `DaemonError.transport(String)` drifts from API_CONTRACT § 4 spec (`transport(Error)`). | **Deferred.** Cosmetic; update either side. |
| 🟡 | [`DaemonTypes.swift:155-163`](../apps/macos/Sources/Network/DaemonTypes.swift) | `VoicesResponse.engine: String?` was added in Swift but isn't documented in API_CONTRACT § 4 (it IS in `v2_types.py`). | **Deferred.** Update the spec. |
| 🟡 | [`AudioPlayer.swift:54-64`](../apps/macos/Sources/Audio/AudioPlayer.swift) | `position` uses wall-clock (`CACurrentMediaTime`) not sample-accurate `AVAudioTime`. | Acceptable for UI; revisit if AV sync ever matters. |
| 🟡 | [`SettingsViewModel.swift:6-10`](../apps/macos/Sources/Settings/SettingsViewModel.swift) | `ObservableObject + @Published` instead of `@Observable`. | Migrate when min macOS bumps to 14. |
| 🟡 | [`DaemonTab.swift:86`](../apps/macos/Sources/Settings/DaemonTab.swift) | "Restart Daemon" hardcodes `~/Library/LaunchAgents/dev.myna.daemon.plist`. | Sync with Lane B (Homebrew formula) if either renames. |
| ⚪ | [`AudioPlayer.swift:88-94`](../apps/macos/Sources/Audio/AudioPlayer.swift) | No deinit cleanup of `positionTimer`. Swift 6 strict concurrency forbids it. | Documented in comment; harmless leak. |

**Already-fixed in v0.1.0:**

- `CFBundleShortVersionString` now flows `$(MARKETING_VERSION)` (commit `2bc4583`).
- `applicationWillTerminate` gated on `didBootstrap` (commit `2bc4583`).
- `SelectionService` pasteboard restore via `defer` (post-`18c9de7`).
- `ChromeService` AppleScript wrapped in `with timeout of 5 seconds`.

---

## 21. Risks & Open Questions (Devil's Advocate)

**What breaks in the next 6 months?**

1. **macOS 14 Sonoma-only API drift.** When the user-base sheds Ventura and we bump `MACOSX_DEPLOYMENT_TARGET` to 14.0, we can simplify in two places: drop the `openSettings()` selector fallback ([`MenuBarController.swift:104-113`](../apps/macos/Sources/MenuBar/MenuBarController.swift)) since `SettingsLink` is everywhere, and migrate `SettingsViewModel` to `@Observable`. Neither is hard, but the test surface around the selector path is brittle and will silently rot.

2. **Sparkle EdDSA key compromise.** The public key `lEoEYOBRVnzZC9bysaAYSRpEuXSDmd/FagSmzv2ozHg=` is baked into `Info.plist`. If the private key (stored in 1Password + GitHub secret `SPARKLE_EDDSA_PRIVATE_KEY`) leaks, an attacker controlling the appcast URL (or doing DNS shenanigans) could push a malicious update signed with the leaked key. The rotation story is painful: we'd need to ship one final "trusted" update that swaps in a new public key, *and* ensure every old install picks it up before the leaked key is used in anger. **Mitigation:** monitor the appcast URL, keep the private key in 1Password only, never write it to disk on dev machines.

3. **Accessibility TCC re-grant cycle.** Every time we ship a new build with a different code-signing identity (or the user installs to a different bundle path), macOS treats it as a new app and revokes the Accessibility grant. The "Myna would like to control your computer" prompt re-fires on next launch. We've never seen the case where the user disables Myna in System Settings → Privacy → Accessibility and then can't figure out how to re-enable it; instructions would belong in the README, not the app.

4. **Kokoro voice-list drift.** `DaemonClient.cachedVoices` and `SettingsViewModel.voice` (default `"af_heart"`) both assume specific voice IDs. If the Kokoro Hugging Face repo renames a voice, the persisted setting becomes invalid. The UI gracefully shows the orphan ID ([`VoiceTab.swift:22`](../apps/macos/Sources/Settings/VoiceTab.swift)), but synthesis silently falls back to the engine default. Could be improved with a "your saved voice is no longer available" banner.

5. **Strict concurrency churn.** `SWIFT_STRICT_CONCURRENCY=complete` was set on Swift 6.0; future Xcode versions tighten enforcement of `@unchecked Sendable` boundaries. We have several: `LogFileMirror`, `PasteboardProtocol` impl, `ChromeService`, `SelectionService`, `QueuedChunk`, `PlaybackQueue`. Each is a future compile-error if Apple makes the check stricter.

6. **`scheduleSegment` temp-file growth.** Every mid-chunk seek materialises a `.caf` in `FileManager.default.temporaryDirectory` and caches the file handle ([`AudioPlayer.swift:325-343`](../apps/macos/Sources/Audio/AudioPlayer.swift)). The cache is cleared on `stop()`, but the on-disk file is not deleted. macOS cleans `/var/folders/.../T/` periodically, so this is benign, but worth a `try? FileManager.default.removeItem` on cleanup if we ever hit a long-running session.

7. **`MultipartChunkParser` adversarial robustness.** The parser tolerates 1-byte-at-a-time delivery, but a daemon-side bug that omits the closing CRLF before the next boundary, or a hostile boundary value containing `\r\n`, could wedge it. We don't fuzz the parser. Low risk because the daemon is local and trusted, but worth noting.

8. **`AppDispatcher.decodeWAV` temp-file roundtrip.** Every incoming chunk hits disk before going into `AVAudioPCMBuffer`. On a 30-chunk article that's 30 file writes + 30 reads. Acceptable for current workloads (the engine is the bottleneck), but if we ever move to a faster engine, this becomes the hot path.

9. **No formal Hammerspoon co-existence test.** If a user runs both v0.1.0 Myna.app and the v1 `hammerspoon/myna.lua` script, both will fight for the same global hotkeys. KeyboardShortcuts will register; Hammerspoon's Hot-Key registration will also try. The winner is whoever registered last. We don't surface this in the UI.
