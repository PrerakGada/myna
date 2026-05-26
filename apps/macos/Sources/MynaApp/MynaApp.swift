// MynaApp.swift — @main entry. Wires the MenuBarExtra and Settings
// scenes to the singletons owned by AppDelegate.
//
// AppDelegate bootstraps its singletons in `applicationDidFinishLaunching`
// (and skips this entirely under XCTest), so the scene bodies here use
// `RootView`/`SettingsRootView` shims that pull the optionals out
// lazily — the views are never displayed inside a test process so the
// "not yet bootstrapped" branch is purely defensive.
import SwiftUI

@main
struct MynaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            RootMenuBarView(appDelegate: appDelegate)
        } label: {
            RootMenuBarLabel(appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            RootSettingsView(appDelegate: appDelegate)
        }
    }
}

/// Bird label for the MenuBarExtra. Renders the state-driven SwiftUI
/// bird while bootstrap is complete; falls back to the static SF Symbol
/// during launch / test-host.
private struct RootMenuBarLabel: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        if appDelegate.didBootstrap, let controller = appDelegate.menuController {
            BootedLabel(controller: controller)
        } else {
            BirdIcon.image
        }
    }
}

private struct BootedLabel: View {
    @ObservedObject var controller: MenuBarController
    var body: some View {
        BirdIconView(
            state: controller.iconState,
            suppressAnimation: PowerMonitor.shared.shouldSuppressAnimation
        )
    }
}

private struct RootMenuBarView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        // Gate on the @Published `didBootstrap` flag so SwiftUI re-renders
        // the menu when bootstrap() completes. Reading `menuController`
        // alone wouldn't trigger an update because IUOs aren't @Published.
        if appDelegate.didBootstrap, let controller = appDelegate.menuController {
            MenuBarView(controller: controller)
        } else {
            Text("Myna initialising…").padding()
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

private struct RootSettingsView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        // Pass the running AudioPlayer in as the AudioDuckable so the S09
        // voice preview can duck main playback to 30% during a sample.
        // SettingsView.audioSink is optional, so passing nil in contexts
        // where the player isn't ready is also safe.
        let isReady = appDelegate.didBootstrap
        let viewModel = appDelegate.settings
        let client = appDelegate.client
        if isReady, let viewModel, let client {
            SettingsView(viewModel: viewModel, client: client, audioSink: appDelegate.player)
        } else {
            Text("Settings unavailable in this context.").padding()
        }
    }
}
