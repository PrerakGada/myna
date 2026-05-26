// WhatsNewStateTests.swift — exercises the state.json persistence
// + safe defaults (S10).
import XCTest

@testable import Myna

final class WhatsNewStateTests: XCTestCase {

    private func tempStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("myna-whats-new-\(UUID().uuidString)")
            .appendingPathComponent("state.json")
    }

    func test_load_returns_defaults_when_file_missing() {
        let url = tempStateURL()
        let store = WhatsNewStateStore(fileURL: url)
        let state = store.load()
        XCTAssertEqual(state, WhatsNewState.defaults)
        XCTAssertEqual(state.lastSeenVersion, "0.0.0")
        XCTAssertFalse(state.firstRunComplete)
    }

    func test_save_then_load_round_trips() {
        let url = tempStateURL()
        let store = WhatsNewStateStore(fileURL: url)
        let written = WhatsNewState(
            lastSeenVersion: "0.2.0",
            firstRunComplete: true,
            lastUpdatedAtMs: 1_700_000_000_000
        )
        XCTAssertTrue(store.save(written))
        let read = store.load()
        XCTAssertEqual(read, written)
    }

    func test_load_falls_back_to_defaults_on_malformed_file() throws {
        let url = tempStateURL()
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "this is not json".write(to: url, atomically: true, encoding: .utf8)
        let store = WhatsNewStateStore(fileURL: url)
        XCTAssertEqual(store.load(), WhatsNewState.defaults)
    }

    func test_save_creates_directory_if_missing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("myna-deep-\(UUID().uuidString)")
            .appendingPathComponent("nested")
            .appendingPathComponent("state.json")
        let store = WhatsNewStateStore(fileURL: url)
        XCTAssertTrue(store.save(.defaults))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_uses_snake_case_keys() throws {
        let url = tempStateURL()
        let store = WhatsNewStateStore(fileURL: url)
        let state = WhatsNewState(
            lastSeenVersion: "0.2.0",
            firstRunComplete: true,
            lastUpdatedAtMs: 1
        )
        _ = store.save(state)
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"last_seen_version\""), "expected snake_case keys: \(raw)")
        XCTAssertTrue(raw.contains("\"first_run_complete\""))
        XCTAssertTrue(raw.contains("\"last_updated_at_ms\""))
    }
}
