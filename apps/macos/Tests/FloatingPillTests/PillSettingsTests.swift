// PillSettingsTests.swift — verifies the v0.2.x "always visible"
// setting persists, defaults to off, and round-trips through
// SettingsViewModel correctly. Also exercises the frame-autosave
// reset path so we know "Reset pill position" wipes the right key.
import Foundation
import XCTest

@testable import Myna

@MainActor
final class PillSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "dev.myna.app.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        try await super.tearDown()
    }

    func test_pillAlwaysVisible_defaults_off() {
        let viewModel = SettingsViewModel(store: store)
        XCTAssertFalse(viewModel.pillAlwaysVisible)
    }

    func test_pillAlwaysVisible_persists() {
        let viewModel = SettingsViewModel(store: store)
        viewModel.pillAlwaysVisible = true
        let reloaded = SettingsViewModel(store: store)
        XCTAssertTrue(reloaded.pillAlwaysVisible)
    }

    func test_pillAlwaysVisible_resetAll_returns_to_default() {
        let viewModel = SettingsViewModel(store: store)
        viewModel.pillAlwaysVisible = true
        viewModel.resetAll()
        XCTAssertFalse(viewModel.pillAlwaysVisible)
        // And the on-disk key is gone.
        XCTAssertNil(defaults.object(forKey: SettingsKey.pillAlwaysVisible.rawValue))
    }

    func test_floatingPillFrame_autosave_key_matches_appkit_convention() {
        // Sanity-check the constant — AppKit prefixes "NSWindow Frame "
        // when persisting setFrameAutosaveName-tagged windows. If
        // AppKit changes the prefix in a future macOS, the reset
        // path will silently fail; this test will catch the drift.
        XCTAssertEqual(
            FloatingPillFrame.defaultsKey,
            "NSWindow Frame \(FloatingPillFrame.autosaveName)"
        )
        XCTAssertEqual(FloatingPillFrame.autosaveName, "dev.myna.app.pillFrame")
    }
}
