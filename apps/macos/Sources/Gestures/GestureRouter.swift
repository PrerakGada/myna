// GestureRouter.swift — translates a recognised gesture into an
// AppDispatcher action. Decoupled from the gesture detection layer
// (MultitouchBridge + GestureRecognizer4Finger) so this stays a thin,
// fully unit-testable mapping.
//
// v0.2.x REDESIGN
// ---------------
// The original v0.2 gesture set was 4-finger swipe + force-touch
// click. Swipe collides with macOS Mission Control ("Swipe between
// full-screen apps" — defaults to 4 fingers on Magic Trackpad) and
// never fires reliably, so we scrapped it. The new set is:
//
//   • 4-finger tap         → speak selection (full)
//   • 4-finger double-tap  → speak selection (summary)
//   • 4-finger click       → play / pause toggle
//   • 4-finger double-click → stop
//
// "Click" here means a Force Touch hard click (stage ≥ 2) while four
// fingers are in contact. See GestureRecognizer4Finger for the state
// machine.
import Foundation

/// The semantic gesture vocabulary Myna recognises.
public enum MynaGesture: String, Sendable, CaseIterable {
    /// 4-finger trackpad tap → speak selection (full).
    case fourFingerTap

    /// 4-finger trackpad double-tap → speak selection (summary).
    case fourFingerDoubleTap

    /// 4-finger trackpad hard click → play / pause toggle.
    case fourFingerClick

    /// 4-finger trackpad hard double-click → stop.
    case fourFingerDoubleClick
}

/// Pluggable target so the router can be unit-tested. Implemented by
/// `AppDispatcher` in production.
@MainActor
public protocol GestureActionTarget: AnyObject {
    func speakSelection(mode: SynthesizeMode)
    func togglePause()
    func stop()
    /// Retained from v0.1 for backwards-compat with any internal call
    /// sites; the new gesture set does not use seek but the protocol
    /// keeps it so we don't churn `AppDispatcher`. Removing this would
    /// force a separate `URLSchemeDispatching`-style split.
    func seek(delta: TimeInterval)
}

/// Dispatch each recognised gesture to the action target. Keeps the
/// gesture → action mapping in one place; the AppDispatcher conforms
/// to GestureActionTarget so production wiring is one line.
@MainActor
public final class GestureRouter {
    private weak var target: (any GestureActionTarget)?
    private let log = Log(.app)

    public init(target: any GestureActionTarget) {
        self.target = target
    }

    public func handle(_ gesture: MynaGesture) {
        guard let target else { return }
        switch gesture {
        case .fourFingerTap:
            target.speakSelection(mode: .full)
        case .fourFingerDoubleTap:
            target.speakSelection(mode: .summary)
        case .fourFingerClick:
            target.togglePause()
        case .fourFingerDoubleClick:
            target.stop()
        }
        log.info("gesture handled: \(gesture.rawValue)")
    }
}
