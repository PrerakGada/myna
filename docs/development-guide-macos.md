# Myna macOS — Development Guide

> Step-by-step setup, build, test, debug, and "how do I add X" workflows for the native Swift app at `apps/macos/`. Complements [architecture-macos.md](architecture-macos.md) and [component-inventory-macos.md](component-inventory-macos.md).

---

## 1. Prerequisites

| Tool | Version / source | Why |
|---|---|---|
| macOS | 13.0+ Ventura on Apple Silicon | Deployment target is 13.0; recent Xcode requires Apple Silicon. |
| Xcode | 16+ (the project pins `xcodeVersion: "16.0"` in [`project.yml:10`](../apps/macos/project.yml)) | Swift 6 strict-concurrency support. |
| XcodeGen | `brew install xcodegen` | Generates `Myna.xcodeproj` from `project.yml`. The `.xcodeproj` is gitignored. |
| SwiftLint | `brew install swiftlint` | Repo lint config in [`.swiftlint.yml`](../apps/macos/.swiftlint.yml). |
| swift-format | `brew install swift-format` | Repo formatter config in [`.swift-format`](../apps/macos/.swift-format). |
| Running daemon | `myna-daemon` at `http://127.0.0.1:8766` | The Swift app is a client only — no daemon means no audio. |
| Kokoro engine | Optional (port 8765) | If absent, daemon reports `engine: down` and synthesis fails — but UI still works. |

**One-shot install:**

```bash
brew install xcodegen swiftlint swift-format
```

**Permissions you'll need granted to the built app** the first time you launch it:

- **Accessibility** (System Settings → Privacy & Security → Accessibility) — required so `CGEvent.post(.cghidEventTap)` can simulate Cmd+C in other apps. macOS prompts on first launch via `AXIsProcessTrustedWithOptions`.
- **Automation → Google Chrome** (System Settings → Privacy & Security → Automation) — required for `NSAppleScript` to read the front tab's URL. macOS prompts on first invocation of the "Read Chrome" hotkey.

---

## 2. Bootstrap

```bash
cd apps/macos
xcodegen generate            # creates Myna.xcodeproj from project.yml
```

XcodeGen reads [`project.yml`](../apps/macos/project.yml), pulls SPM dependencies (KeyboardShortcuts ≥ 2.0.0, Sparkle ≥ 2.6.0), and writes the `.xcodeproj`. Regenerate any time you add/remove source files or change `project.yml`. It's fast (~1–2 s) and idempotent.

---

## 3. Run from terminal

The repo ships a one-shot dev loop at [`apps/macos/dev.sh`](../apps/macos/dev.sh) that kills the running app, regenerates the project, debug-builds without signing, and launches the fresh `.app`. From the repo root:

```bash
./apps/macos/dev.sh
```

Or from inside `apps/macos/`:

```bash
./dev.sh
```

What it runs (transcribed from the script):

```bash
pkill -f "Myna.app/Contents/MacOS/Myna" 2>/dev/null || true
sleep 1
xcodegen generate >/dev/null
xcodebuild \
  -scheme Myna \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
open build/Build/Products/Debug/Myna.app
```

No flags, no env vars. If you want a different flow, read the script — it's 36 lines.

The unsigned debug build *will* prompt for Accessibility on first launch; that's expected. macOS treats unsigned binaries as ephemeral, so a fresh rebuild may force you to re-grant.

---

## 4. Run from Xcode

```bash
cd apps/macos
xcodegen generate
open Myna.xcodeproj
```

Then in Xcode: select the **Myna** scheme, choose **My Mac** as the destination, and press ⌘R. The first build pulls SPM packages (Sparkle + KeyboardShortcuts) — give it ~15 s. Subsequent builds are seconds.

If Xcode's source navigator shows files in the wrong order or missing, you edited the file tree without regenerating: `xcodegen generate` again and close + reopen the project.

---

## 5. Test

From `apps/macos/`:

```bash
xcodebuild test \
  -scheme Myna \
  -destination 'platform=macOS' \
  -derivedDataPath build
```

Or from Xcode: ⌘U on the **Myna** scheme.

Expect ~91 tests across 14 files, total wall time under 30 s. The test bundle is host-loaded — every test runs against the built `Myna.app`'s class images, but `AppDelegate` short-circuits bootstrap when `XCTestConfigurationFilePath` is set in the environment ([`AppDelegate.swift:125-127`](../apps/macos/Sources/MynaApp/AppDelegate.swift)) so the live audio session, hotkey registration, and polling loop never start.

To run a single test class:

```bash
xcodebuild test \
  -scheme Myna \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  -only-testing:MynaTests/AudioPlayerTests
```

`xcodebuild test` returns non-zero on any failure and gathers coverage data (`gatherCoverageData: YES` in [`project.yml:112`](../apps/macos/project.yml)).

---

## 6. Lint

```bash
swiftlint --strict
swift-format lint --recursive --strict Sources Tests
```

Run both from `apps/macos/`. CI runs the same; the `--strict` flag turns warnings into errors.

Auto-fix what you can:

```bash
swift-format format -i -r Sources Tests
```

(SwiftLint has `--fix` but most rules in [`.swiftlint.yml`](../apps/macos/.swiftlint.yml) aren't auto-fixable; fix by hand.)

**Force-unwrapping policy:** `force_unwrapping` is opt-in. Every `!` needs either a `// swiftlint:disable:next force_unwrapping` (with a justification) or an `else { return }` guard. See [`AudioPlayer.swift:204-208`](../apps/macos/Sources/Audio/AudioPlayer.swift) for the canonical disable-with-comment pattern.

---

## 7. Adding a new Swift file

1. Drop the file in the right `Sources/<Module>/` folder. Keep filenames alphabetical (XcodeGen sorts by `groupSortPosition: top` per [`project.yml:9`](../apps/macos/project.yml)).
2. Run `xcodegen generate`. XcodeGen scans `Sources/` recursively (excluding `.DS_Store`) per [`project.yml:36-39`](../apps/macos/project.yml) — no manual `.xcodeproj` edits ever.
3. Format the new file: `swift-format format -i Sources/<Module>/<File>.swift`.
4. Lint: `swiftlint --strict Sources/<Module>/<File>.swift`.
5. If you added a test file, also `xcodegen generate` and confirm `xcodebuild test` picks it up. Tests live under `Tests/<Module>Tests/`.
6. Commit `project.yml` only if you changed it (the `.xcodeproj` stays out of git).

**Public-vs-internal:** the project ships everything as `public` where it crosses a folder boundary, because the test target imports `@testable import Myna` and we want types in their own folders to be reachable without `@testable`. Default to `public` for cross-folder types; `internal` is fine if it stays inside one folder.

---

## 8. Adding a daemon endpoint client

Pattern is fixed by [`DaemonClient`](../apps/macos/Sources/Network/DaemonClient.swift) and its tests. Three steps:

1. **Add the wire types** in [`Sources/Network/DaemonTypes.swift`](../apps/macos/Sources/Network/DaemonTypes.swift):

   ```swift
   public struct FooRequest: Codable, Sendable, Equatable {
       public let bar: String
       public init(bar: String) { self.bar = bar }
   }

   public struct FooResponse: Codable, Sendable, Equatable {
       public let ok: Bool
       public let result: String?
       public init(ok: Bool, result: String? = nil) {
           self.ok = ok; self.result = result
       }
   }
   ```

   Match [API_CONTRACT.md § 4](native-app/API_CONTRACT.md) JSON shape (snake_case via `CodingKeys`).

2. **Add the method** to [`DaemonClient.swift`](../apps/macos/Sources/Network/DaemonClient.swift). Use the `makeRequest(path:method:body:)` helper:

   ```swift
   public func foo(bar: String) async throws -> FooResponse {
       let req = try makeRequest(path: "/v2/foo", method: "POST", body: FooRequest(bar: bar))
       return try await decode(req)
   }
   ```

   Validate inputs locally (e.g. non-empty) before the round-trip. Map non-200 status to a typed `DaemonError` case in `mapHTTPError` ([`DaemonClient.swift:293-313`](../apps/macos/Sources/Network/DaemonClient.swift)) if it's a known error shape.

3. **Add a test** in [`Tests/NetworkTests/DaemonClientTests.swift`](../apps/macos/Tests/NetworkTests/DaemonClientTests.swift) using `MockURLProtocol`:

   ```swift
   func test_foo_decodes_response() async throws {
       let body = Data(#"{"ok":true,"result":"hello"}"#.utf8)
       MockURLProtocol.enqueue { req in
           XCTAssertEqual(req.url?.path, "/v2/foo")
           XCTAssertEqual(req.httpMethod, "POST")
           return (.make(url: req.url!, status: 200), body)
       }
       let client = makeClient()
       let resp = try await client.foo(bar: "x")
       XCTAssertTrue(resp.ok)
       XCTAssertEqual(resp.result, "hello")
   }
   ```

   If the response has a stable shape, drop a fixture into `docs/native-app/fixtures/` and load via `FixtureLoader.data("foo-response.json")`. The fixtures folder is shared with the daemon's tests — both sides break in lockstep if the shape drifts.

---

## 9. Adding a hotkey action

1. **Declare the shortcut name** in [`Sources/Input/HotkeyManager.swift`](../apps/macos/Sources/Input/HotkeyManager.swift) inside the `extension KeyboardShortcuts.Name` block:

   ```swift
   extension KeyboardShortcuts.Name {
       public static let myNewAction = Self(
           "myNewAction",
           default: .init(.j, modifiers: [.command, .option, .shift])
       )
       // …append to allMynaShortcuts
       public static let allMynaShortcuts: [KeyboardShortcuts.Name] = [
           .speakSelectionFull, .speakSelectionSummary, .readChromeArticle,
           .pauseResume, .stop, .myNewAction,
       ]
   }
   ```

2. **Add an enum case** to `HotkeyAction` ([`HotkeyManager.swift:51-67`](../apps/macos/Sources/Input/HotkeyManager.swift)) with a v1-style snake_case raw value (used in any external config):

   ```swift
   public enum HotkeyAction: String, CaseIterable, Sendable {
       // …existing cases
       case myNewAction = "my_new_action"

       public var name: KeyboardShortcuts.Name {
           switch self {
           // …
           case .myNewAction: return .myNewAction
           }
       }
   }
   ```

3. **Wire the handler** in [`AppDelegate.applicationDidFinishLaunching`](../apps/macos/Sources/MynaApp/AppDelegate.swift:74-80):

   ```swift
   hotkeys.register(handlers: [
       // …existing entries
       .myNewAction: { [weak self] in self?.dispatcher.myNewAction() },
   ])
   ```

4. **Add the dispatcher method** to [`AppDispatcher`](../apps/macos/Sources/MynaApp/AppDispatcher.swift), and an analogous URL-scheme route in [`URLSchemeHandler`](../apps/macos/Sources/URLScheme/URLSchemeHandler.swift) if the action should also be triggerable via `myna://`.

5. **Add a row** to [`HotkeysTab.swift`](../apps/macos/Sources/Settings/HotkeysTab.swift):

   ```swift
   KeyboardShortcuts.Recorder("My new action:", name: .myNewAction)
   ```

6. **Update the test** at [`HotkeyManagerTests.test_default_shortcuts_match_v1_for_compatibility`](../apps/macos/Tests/InputTests/HotkeyManagerTests.swift:13-40) and `test_all_five_actions_present` (which will now expect 6) so CI catches accidental defaults drift.

Persistence is handled automatically by the KeyboardShortcuts library (stores under its own `KeyboardShortcuts_<name>` UserDefaults key).

---

## 10. Debugging tips

**Console.app filter.** All app logs go to OSLog with subsystem `dev.myna.app`. Open Console.app, filter by `subsystem:dev.myna.app`, optionally narrow with `category:network` / `audio` / `urlscheme` / `input` / `settings` / `app`.

**File log.** Mirror at `~/Library/Logs/Myna/myna.log` (5 MB rotation, 5 archives). Tail live:

```bash
tail -F ~/Library/Logs/Myna/myna.log
```

Rotated archives are `myna.log.1` … `myna.log.5`.

**Open the log folder from the app.** Menu bar → "Open Logs", or Settings → Advanced → "Open Logs folder" — both call `NSWorkspace.activateFileViewerSelecting([LogFileMirror.shared.currentLogURL])` ([`MenuBarController.swift:115-117`](../apps/macos/Sources/MenuBar/MenuBarController.swift), [`AdvancedTab.swift:23-25`](../apps/macos/Sources/Settings/AdvancedTab.swift)).

**Diagnostic stderr.** `AppDelegate.applicationDidFinishLaunching` writes `[Myna]` prefixed lines directly to stderr before any logger is wired ([`AppDelegate.swift:49`](../apps/macos/Sources/MynaApp/AppDelegate.swift)). To see them, launch from Terminal:

```bash
build/Build/Products/Debug/Myna.app/Contents/MacOS/Myna
```

Stay in the foreground; Ctrl-C kills the app.

**Sparkle verbose mode.** To get Sparkle's full chatter while you debug an update flow, launch with environment variable:

```bash
SUFeedURL="https://github.com/PrerakGada/myna/releases/download/appcast/appcast.xml" \
  build/Build/Products/Debug/Myna.app/Contents/MacOS/Myna
```

For protocol-level debugging, set `OS_ACTIVITY_MODE=enable` and watch Console with `subsystem:org.sparkle-project.Sparkle`.

**Inspect the built bundle.** After a release build:

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  build/Build/Products/Debug/Myna.app/Contents/Info.plist
```

This catches version-flow regressions early (Lane A audit 🟡 #2 — `CFBundleShortVersionString` was once hardcoded `"1.0"` and Sparkle never offered updates).

**Drive the URL scheme manually:**

```bash
open 'myna://speak-selection'
open 'myna://seek?delta=-15'
open 'myna://speed?value=1.25'
```

---

## 11. Permission troubleshooting

**Accessibility (Cmd+C simulation).**

- Symptom: speak-selection hotkey fires but nothing plays; log shows `speak-selection: no text captured`.
- Cause: `CGEvent.post(.cghidEventTap)` silently no-ops without Accessibility permission.
- Fix: System Settings → Privacy & Security → Accessibility → enable **Myna**. If Myna is not in the list, click `+` and add `Myna.app`. Then **relaunch Myna** — TCC changes don't take effect mid-process.
- Force re-prompt: System Settings → Privacy & Security → Accessibility → select Myna → `-` to remove → relaunch Myna → the prompt re-fires via `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])`.

**Automation → Google Chrome (front-tab URL).**

- Symptom: Cmd+Opt+Shift+R does nothing; log shows `read-chrome: no Chrome tab URL`.
- Cause: macOS hasn't yet asked for Automation permission for Chrome.
- Fix: System Settings → Privacy & Security → Automation → expand **Myna** → enable **Google Chrome**. If Chrome isn't listed under Myna, trigger the AppleScript once (press the hotkey) and macOS will prompt.
- Revoke: same screen, toggle off. The next invocation will re-prompt.

**TCC blanket reset for Myna** (nuclear option, requires `sudo`):

```bash
tccutil reset Accessibility dev.myna.app
tccutil reset AppleEvents dev.myna.app
```

Then relaunch Myna and re-grant when prompted. Useful when developing — replacing the binary in-place sometimes leaves stale TCC entries pointing at the deleted hash.

**Notarization sanity:**

```bash
spctl -a -v /Applications/Myna.app
codesign -dv --verbose=4 /Applications/Myna.app
```

Should report `accepted` and a `Developer ID Application` identity.

---

## 12. Common pitfalls

1. **`@Observable` requires Sonoma.** The project targets macOS 13. Don't reach for `@Observable` in new code; use `ObservableObject + @Published` ([`SettingsViewModel.swift:6-10`](../apps/macos/Sources/Settings/SettingsViewModel.swift) for the established pattern). Migration is one targeted edit when the deployment target bumps.

2. **Plist path hardcoding in `restartDaemon()`** ([`DaemonTab.swift:86`](../apps/macos/Sources/Settings/DaemonTab.swift)). The launch agent is owned by the Homebrew formula (`tap/Formula/myna-daemon.rb`). If either side renames `dev.myna.daemon.plist`, both must move in lockstep. Greppable invariant.

3. **`CFBundleShortVersionString` must flow `$(MARKETING_VERSION)`** ([`project.yml:48-50`](../apps/macos/project.yml)). Hardcoding it breaks Sparkle's "newer version available" check. Verify after every release build:

   ```bash
   /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
     <built-app>/Contents/Info.plist
   ```

4. **Don't construct an `AudioPlayer` outside `bootstrap()`.** It grabs the audio session and starts the engine on first enqueue. The test host loads the app image before any test runs, so doing this in `AppDelegate.init` would fight the tests' own `AudioPlayer` instances. The IUO pattern in [`AppDelegate.swift:21-37`](../apps/macos/Sources/MynaApp/AppDelegate.swift) exists for exactly this reason.

5. **XCTest detection is env-var only.** [`AppDelegate.isRunningTests`](../apps/macos/Sources/MynaApp/AppDelegate.swift:125-127) reads `XCTestConfigurationFilePath`. Don't add an `NSClassFromString("XCTestCase")` check — macOS 15+ auto-loads `XCTestSupport.framework` into every app, which would make the check return true for normal Finder launches and the menu would be stuck on "Myna initialising…" forever.

6. **`didBootstrap` must stay `@Published`** ([`AppDelegate.swift:41`](../apps/macos/Sources/MynaApp/AppDelegate.swift)). The SwiftUI `MenuBarExtra` reads it; without `@Published`, no `objectWillChange` fires when bootstrap completes and the menu never re-renders.

7. **Pasteboard restore goes in `defer`.** [`SelectionService.captureSelectedText`](../apps/macos/Sources/Input/SelectionService.swift:114-132) — Task cancellation during the 120 ms sleep would otherwise leave the user with an empty clipboard. Fixed in audit 🟡 #3.

8. **AppleScript needs the 5-second timeout wrapper.** A wedged Chrome would otherwise hang the menu bar indefinitely. See [`ChromeService.swift:39-43`](../apps/macos/Sources/Input/ChromeService.swift). Audit 🟡 #1.

9. **`scheduleSegment` requires `AVAudioFile`, not `AVAudioPCMBuffer`.** Mid-buffer seeks fall through to the slow path ([`AudioPlayer.swift:303-318`](../apps/macos/Sources/Audio/AudioPlayer.swift)) that materialises the buffer to a temp `.caf`. The cache (`bufferFileCache`) is bound to the player session and cleared on `stop()`; on-disk files leak harmlessly into `/var/folders/.../T/` until macOS sweeps them.

10. **No `myna://speak?text=...` route, ever.** Any local process can post URL events. The security regression suite ([`AuditSecurityURLSchemeTests.swift`](../apps/macos/Tests/URLSchemeTests/AuditSecurityURLSchemeTests.swift)) is canonical — adding a new route means also adding adversarial counterparts there.

11. **Multipart parser is not `Sendable`.** [`MultipartChunkParser`](../apps/macos/Sources/Network/SynthesizeStream.swift:30) is a `final class` with mutable buffer state and no synchronisation. One parser per response stream; the actor-isolated [`DaemonClient.runSynthesize`](../apps/macos/Sources/Network/DaemonClient.swift:117-138) enforces this implicitly.

12. **Two `@ObservedObject` bindings in `MenuBarView`.** [`MenuBarView.swift:7-8`](../apps/macos/Sources/MenuBar/MenuBarView.swift) observes both `controller` and `controller.player`. If you collapse to one, the menu won't re-render on player state changes.

13. **No deinit cleanup of `AudioPlayer.positionTimer`.** Swift 6 strict concurrency forbids touching `@MainActor` state from a nonisolated `deinit`. Call `stop()` explicitly; the timer leak on dealloc is harmless. See [`AudioPlayer.swift:88-94`](../apps/macos/Sources/Audio/AudioPlayer.swift).
