// GestureMonitor.swift — public lifecycle wrapper for Myna's trackpad
// gesture system.
//
// v0.2.x REDESIGN — see GestureRouter.swift header for context. The
// monitor used to host an NSEvent `.swipe` + `.pressure` pair; that
// approach was scrapped because (a) global swipe collides with macOS
// Mission Control and (b) global tap finger counts aren't exposed by
// public APIs.
//
// The monitor now owns a `MultitouchBridge` (private MT framework +
// pressure NSEvent) and exposes the same `start()` / `stop()` /
// `isRunning` surface so the AppDelegate wiring (and the
// `applyGestureToggle` Combine sink) keeps working unchanged.
import AppKit
import Foundation

@MainActor
public final class GestureMonitor {
    private let bridge: MultitouchBridge
    private let log = Log(.app)

    /// Outcome of the most recent `start()` call. Useful for surfacing
    /// a "trackpad not detected" banner in the Settings tab in a
    /// future iteration; today we only log it.
    public private(set) var lastStartResult: MultitouchBridgeStartResult?

    public init(router: GestureRouter) {
        self.bridge = MultitouchBridge(router: router)
    }

    public var isRunning: Bool { bridge.isRunning }

    public func start() {
        log.info("GestureMonitor.start")
        let result = bridge.start()
        lastStartResult = result
        switch result {
        case .started:
            break
        case .frameworkMissing:
            log.warn("Gestures disabled: MultitouchSupport framework not present.")
        case .symbolMissing(let name):
            log.warn("Gestures disabled: MultitouchSupport missing symbol \(name).")
        case .noTrackpad:
            log.warn("Gestures inactive: no trackpad detected.")
        }
    }

    public func stop() {
        log.info("GestureMonitor.stop")
        bridge.stop()
    }
}
