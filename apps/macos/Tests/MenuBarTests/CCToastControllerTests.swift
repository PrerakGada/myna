// CCToastControllerTests.swift — exercises the toast stack manager
// (S08). We don't render real NSPanel windows in tests (they'd race with
// the test host); instead we verify the public state — windows.count,
// overflowCount, presentedIds — across ingest passes.
import AppKit
import XCTest

@testable import Myna

@MainActor
final class CCToastControllerTests: XCTestCase {

    private func makeItem(id: String, title: String = "t", projectId: String = "p", ageMs: Int = 0) -> RegistryV2Item {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        return RegistryV2Item(
            id: id,
            source: "claude-code",
            projectId: projectId,
            title: title,
            announcedAtMs: now - ageMs,
            ttlS: 600
        )
    }

    func test_ingest_new_items_presents_them() {
        let ctrl = CCToastController()
        let items = [makeItem(id: "a"), makeItem(id: "b")]
        ctrl.ingest(registry: items, chimeEnabled: false)
        XCTAssertEqual(ctrl.windows.count, 2)
    }

    func test_ingest_caps_visible_at_max_visible() {
        let ctrl = CCToastController()
        let items = (0..<5).map { makeItem(id: "i\($0)") }
        ctrl.ingest(registry: items, chimeEnabled: false)
        XCTAssertEqual(ctrl.windows.count, CCToastController.maxVisible)
        XCTAssertEqual(ctrl.overflowCount, 5 - CCToastController.maxVisible)
    }

    func test_ingest_does_not_re_show_already_presented() {
        let ctrl = CCToastController()
        let items = [makeItem(id: "a")]
        ctrl.ingest(registry: items, chimeEnabled: false)
        XCTAssertEqual(ctrl.windows.count, 1)
        // Re-ingest same set → no new presentation, count stays at 1.
        ctrl.ingest(registry: items, chimeEnabled: false)
        XCTAssertEqual(ctrl.windows.count, 1)
    }

    func test_ingest_removes_toasts_whose_items_disappear() {
        let ctrl = CCToastController()
        let firstBatch = [makeItem(id: "a"), makeItem(id: "b")]
        ctrl.ingest(registry: firstBatch, chimeEnabled: false)
        XCTAssertEqual(ctrl.windows.count, 2)

        // Daemon dropped "b" from the registry → its toast should go too.
        ctrl.ingest(registry: [makeItem(id: "a")], chimeEnabled: false)
        XCTAssertEqual(ctrl.windows.count, 1)
        XCTAssertEqual(ctrl.windows.first?.item.id, "a")
    }

    func test_dismiss_all_clears_windows() {
        let ctrl = CCToastController()
        ctrl.ingest(registry: [makeItem(id: "a"), makeItem(id: "b")], chimeEnabled: false)
        ctrl.dismissAll()
        XCTAssertEqual(ctrl.windows.count, 0)
        XCTAssertEqual(ctrl.overflowCount, 0)
    }

    func test_overflow_count_matches_registry_minus_visible() {
        let ctrl = CCToastController()
        let many = (0..<10).map { makeItem(id: "i\($0)") }
        ctrl.ingest(registry: many, chimeEnabled: false)
        XCTAssertEqual(ctrl.overflowCount, 10 - CCToastController.maxVisible)
    }

    // MARK: - frame math

    func test_target_frame_for_nil_screen_returns_size_only() {
        let frame = CCToastWindow.targetFrame(on: nil, stackIndex: 0)
        XCTAssertEqual(frame.size, NSSize(width: CCToastWindow.toastWidth, height: CCToastWindow.toastHeight))
    }

    func test_target_frame_stacks_below_previous_with_gap() {
        guard let screen = NSScreen.main else { return }
        let first = CCToastWindow.targetFrame(on: screen, stackIndex: 0)
        let second = CCToastWindow.targetFrame(on: screen, stackIndex: 1)
        XCTAssertEqual(first.origin.x, second.origin.x, accuracy: 0.5)
        let delta = first.origin.y - second.origin.y
        XCTAssertEqual(delta, CCToastWindow.toastHeight + CCToastWindow.stackGap, accuracy: 0.5)
    }
}
