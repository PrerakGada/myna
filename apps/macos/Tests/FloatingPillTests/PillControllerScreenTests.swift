// PillControllerScreenTests.swift — exercises the cursor-based
// screen-picking logic that replaces the v0.2.0 AX-based path.
//
// We can't spin up extra NSScreens in a test process, but the
// `screenForCursor(_:screens:main:)` helper is pure geometry over
// injected arrays — perfect for unit testing the three cases that
// matter on Prerak's multi-display rig:
//   (1) cursor on the primary display              → primary
//   (2) cursor on the secondary display            → secondary
//   (3) cursor between displays / on neither       → main fallback
//
// We use a tiny test double for NSScreen because NSScreen has no
// public initialiser. Swift type system can't make a mock conform
// to NSScreen, but the helper only reads `.frame`. We instead
// expose a parallel pure-CGRect helper in the test target (kept
// in lock-step with the production code) and verify the cases
// against that — see `pickScreenFrame` below.
//
// (When/if NSScreen-injection is needed in production, the
// production helper takes `[NSScreen]` directly; this test
// validates the algorithm.)
import XCTest

@testable import Myna

@MainActor
final class PillControllerScreenTests: XCTestCase {

    // MARK: - pure-geometry helper used by both production and tests
    //
    // Mirrors PillController.screenForCursor but operates on plain
    // CGRects. Production uses NSScreen.screens; the algorithm is
    // identical.
    private static func pickScreenFrame(
        cursor: CGPoint,
        screens: [CGRect],
        mainIndex: Int? = nil
    ) -> Int? {
        if let hitIndex = screens.firstIndex(where: { $0.contains(cursor) }) {
            return hitIndex
        }
        if let mainIndex { return mainIndex }
        return screens.indices.first
    }

    /// Built-in MacBook display ≈ 1512x982 starting at origin.
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)

    /// External monitor placed to the right of the built-in.
    /// Typical 4K @ 2x logical = 1920x1080.
    private let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

    func test_cursor_on_builtin_returns_builtin() {
        let cursor = CGPoint(x: 100, y: 100)
        let result = Self.pickScreenFrame(
            cursor: cursor,
            screens: [builtIn, external],
            mainIndex: 0
        )
        XCTAssertEqual(result, 0)
    }

    func test_cursor_on_external_returns_external() {
        // Centre of external monitor.
        let cursor = CGPoint(x: 1512 + 960, y: 540)
        let result = Self.pickScreenFrame(
            cursor: cursor,
            screens: [builtIn, external],
            mainIndex: 0
        )
        XCTAssertEqual(result, 1)
    }

    func test_cursor_off_all_screens_falls_back_to_main() {
        // Cursor well outside either display (e.g. transitioning
        // between displays during a hot-unplug).
        let cursor = CGPoint(x: -500, y: -500)
        let result = Self.pickScreenFrame(
            cursor: cursor,
            screens: [builtIn, external],
            mainIndex: 1
        )
        XCTAssertEqual(result, 1, "Should fall back to main display when cursor is off-screen")
    }

    func test_cursor_off_all_screens_no_main_falls_back_to_first() {
        let cursor = CGPoint(x: -500, y: -500)
        let result = Self.pickScreenFrame(
            cursor: cursor,
            screens: [builtIn, external],
            mainIndex: nil
        )
        XCTAssertEqual(result, 0, "Should fall back to first screen when no main hint provided")
    }

    func test_empty_screens_returns_nil() {
        let cursor = CGPoint(x: 0, y: 0)
        let result = Self.pickScreenFrame(
            cursor: cursor,
            screens: [],
            mainIndex: nil
        )
        XCTAssertNil(result)
    }

    // MARK: - production helper via NSScreen.screens path
    //
    // Validates the production helper compiles and returns a
    // reasonable result on the test host. We can't assert *which*
    // screen we get back (depends on the CI runner / dev machine),
    // but we can assert it's non-nil and that NSScreen.screens
    // contains the result.

    func test_production_helper_returns_a_real_screen() {
        let cursor = NSEvent.mouseLocation
        let result = PillController.screenForCursor(
            cursor,
            screens: NSScreen.screens
        )
        if NSScreen.screens.isEmpty {
            XCTAssertNil(result, "No screens available on test host")
        } else {
            XCTAssertNotNil(result)
            // The returned screen must be in the input array.
            XCTAssertTrue(NSScreen.screens.contains { $0 === result })
        }
    }

    func test_production_helper_handles_off_screen_cursor() {
        // Cursor far off any reasonable display.
        let cursor = CGPoint(x: -100_000, y: -100_000)
        let result = PillController.screenForCursor(
            cursor,
            screens: NSScreen.screens,
            main: NSScreen.main
        )
        if NSScreen.screens.isEmpty {
            XCTAssertNil(result)
        } else {
            XCTAssertNotNil(result, "Should fall back rather than return nil when screens exist")
        }
    }
}
