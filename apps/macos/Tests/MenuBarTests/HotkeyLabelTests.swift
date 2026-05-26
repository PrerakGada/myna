// HotkeyLabelTests.swift — verifies the glyph cluster builder
// translates modifiers + key into the macOS menu-row display string
// (S06 AC #4). Tests build Shortcut values directly so we never touch
// the system event loop.
import KeyboardShortcuts
import XCTest

@testable import Myna

@MainActor
final class HotkeyLabelTests: XCTestCase {
    func test_command_option_shift_s_renders_macos_glyph_form() {
        let shortcut = KeyboardShortcuts.Shortcut(.s, modifiers: [.command, .option, .shift])
        // KeyboardShortcuts.Shortcut.description renders modifiers in
        // macOS canonical order (⌃⌥⇧⌘) followed by the key glyph.
        // Exact string: "⌥⇧⌘S".
        XCTAssertEqual(HotkeyLabel.display(shortcut: shortcut), "⌥⇧⌘S")
    }

    func test_period_with_command_option() {
        let shortcut = KeyboardShortcuts.Shortcut(.period, modifiers: [.command, .option])
        XCTAssertEqual(HotkeyLabel.display(shortcut: shortcut), "⌥⌘.")
    }

    func test_right_arrow_with_command() {
        let shortcut = KeyboardShortcuts.Shortcut(.rightArrow, modifiers: [.command])
        let rendered = HotkeyLabel.display(shortcut: shortcut)
        XCTAssertTrue(rendered.hasPrefix("⌘"), "expected modifier prefix in '\(rendered)'")
        XCTAssertTrue(rendered.contains("→"), "expected arrow glyph in '\(rendered)'")
    }

    func test_space_with_full_set() {
        let shortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .option, .shift, .control])
        let rendered = HotkeyLabel.display(shortcut: shortcut)
        // Modifier order is ⌃⌥⇧⌘ — assert the prefix, not the trailing
        // key glyph (which the library renders as a name like "Space").
        XCTAssertTrue(rendered.hasPrefix("⌃⌥⇧⌘"), "expected '⌃⌥⇧⌘' prefix in '\(rendered)'")
    }

    func test_unbound_action_returns_nil() {
        // pauseResume has a default binding registered, so getShortcut
        // returns it. We pass a fresh, unbound shortcut name to verify
        // the nil branch.
        let unbound = KeyboardShortcuts.Name("test-unbound-\(UUID().uuidString)")
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: unbound))
    }
}
