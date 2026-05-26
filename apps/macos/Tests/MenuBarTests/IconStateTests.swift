// IconStateTests.swift — exercises the pure state-mapping logic that
// drives the 5-state bird icon (S07). The mapping is a pure function,
// so tests pass in raw signal values and assert on the computed state.
import XCTest

@testable import Myna

final class IconStateTests: XCTestCase {
    private func compute(
        reachability: MenuBarController.DaemonReachability = .up,
        daemonState: String? = nil,
        paused: Bool = false,
        playing: Bool = false
    ) -> IconState {
        IconStateMapping.compute(
            reachability: reachability,
            daemonStateRaw: daemonState,
            isPlayerPaused: paused,
            isPlayerPlaying: playing
        )
    }

    func test_daemon_down_is_error() {
        XCTAssertEqual(compute(reachability: .down), .error)
        XCTAssertEqual(compute(reachability: .down, playing: true), .error)
    }

    func test_player_paused_dominates_daemon_state() {
        XCTAssertEqual(compute(daemonState: "speaking", paused: true), .paused)
    }

    func test_daemon_speaking_or_streaming_maps_to_speaking() {
        XCTAssertEqual(compute(daemonState: "speaking"), .speaking)
        XCTAssertEqual(compute(daemonState: "streaming"), .speaking)
    }

    func test_daemon_thinking_or_synthesizing_maps_to_thinking() {
        XCTAssertEqual(compute(daemonState: "thinking"), .thinking)
        XCTAssertEqual(compute(daemonState: "synthesizing"), .thinking)
    }

    func test_daemon_error_state_maps_to_error() {
        XCTAssertEqual(compute(daemonState: "error"), .error)
    }

    func test_player_playing_without_daemon_hint_maps_to_speaking() {
        XCTAssertEqual(compute(daemonState: "idle", playing: true), .speaking)
    }

    func test_no_signals_means_idle() {
        XCTAssertEqual(compute(), .idle)
    }

    func test_isAnimated_only_speaking_and_thinking() {
        XCTAssertTrue(IconState.speaking.isAnimated)
        XCTAssertTrue(IconState.thinking.isAnimated)
        XCTAssertFalse(IconState.idle.isAnimated)
        XCTAssertFalse(IconState.paused.isAnimated)
        XCTAssertFalse(IconState.error.isAnimated)
    }
}
