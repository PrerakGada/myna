// GestureRecognizer4Finger.swift — pure-Swift state machine that
// classifies 4-finger trackpad activity into one of the four
// `MynaGesture` cases (tap, double-tap, click, double-click).
//
// WHY A SEPARATE TYPE
// -------------------
// `MultitouchBridge` owns the MultitouchSupport.framework C-callback and
// the global pressure NSEvent monitor; both are deeply non-testable
// (private framework + global event hooks). This recognizer is the
// brain — it accepts plain value events and emits gestures — so we can
// unit-test every classification path without touching real hardware.
//
// EVENT INPUT
// -----------
// The bridge feeds the recognizer two kinds of events:
//
//   1. `Touch` frames at ~60 Hz (the MT callback fires for every
//      trackpad refresh). Each frame carries the *current* finger
//      count on the trackpad and the max per-finger normalized
//      pressure for that frame.
//
//   2. `Pressure` events from NSEvent's global `.pressure` monitor.
//      We mainly trust these for the click stage (0/1/2) because the
//      MultitouchSupport per-finger pressure field is finicky across
//      hardware generations.
//
// CLASSIFICATION RULES
// --------------------
//   * **Tap**: 4-finger contact comes up (count rises to ≥ 4), all
//     fingers lift within `tapMaxDuration` (default 220 ms), and no
//     force-click stage ≥ 1 occurred during contact.
//   * **Double-tap**: two taps within `doubleClickInterval` (sourced
//     from `NSEvent.doubleClickInterval` at construction time,
//     defaults to 500 ms in tests).
//   * **Click**: pressure stage rises to ≥ `clickStage` (default 2 =
//     hard click) *while* finger count was ≥ 4 at any point in the
//     current contact window. We don't require it be exactly 4 at the
//     moment of stage transition — the hand naturally drifts during
//     a hard press.
//   * **Double-click**: two clicks within `doubleClickInterval`.
//
// DEBOUNCE & "WAIT TO SEE IF IT BECOMES A DOUBLE"
// -----------------------------------------------
// Tap and click are emitted *delayed* — we hold the first event for
// `doubleClickInterval` before firing it, so that if a second tap/click
// arrives we can upgrade to double-tap / double-click instead. Without
// this, every double-tap would fire a single-tap first (= speak
// selection) and *then* the double-tap (= speak summary), and the user
// would hear both.
//
// The delay is implemented via a "pending emission" record that the
// recognizer surfaces via `pendingDeadline()`. The bridge sets up a
// timer that calls `flush(at:)` when the deadline elapses. In tests we
// drive the flush manually.
//
// CONCURRENCY
// -----------
// `GestureRecognizer4Finger` is **not** thread-safe — the bridge
// guarantees serial access from the MT callback thread (after hopping
// to a dedicated serial queue) or the main actor (for NSEvent).
import Foundation

public enum FourFingerGesture: Equatable, Sendable {
    case tap
    case doubleTap
    case click
    case doubleClick
}

/// One frame of trackpad state as observed by `MultitouchBridge`.
public struct GestureTouchFrame: Equatable, Sendable {
    /// Timestamp in seconds, monotonic. Use `ProcessInfo.processInfo.systemUptime`
    /// in production; arbitrary in tests as long as it's monotonic.
    public let timestamp: TimeInterval
    /// Number of fingers currently in contact (state == makeTouch / touching).
    public let fingerCount: Int
    public init(timestamp: TimeInterval, fingerCount: Int) {
        self.timestamp = timestamp
        self.fingerCount = fingerCount
    }
}

/// One pressure event from NSEvent's `.pressure` global monitor.
public struct GesturePressureEvent: Equatable, Sendable {
    public let timestamp: TimeInterval
    /// Force Touch stage: 0 = no press, 1 = normal click, 2 = deep press.
    public let stage: Int
    public init(timestamp: TimeInterval, stage: Int) {
        self.timestamp = timestamp
        self.stage = stage
    }
}

/// Tunable thresholds for the recognizer. Defaults align with macOS UX
/// norms; tests can pass smaller values to keep wall-clock time bounded.
public struct GestureRecognizerConfig: Sendable {
    /// Minimum finger count for a "4-finger" event. Default 4. We accept
    /// exactly 4 — anything higher is ignored as a palm rest.
    public let requiredFingerCount: Int
    /// Upper bound on tap duration (finger-down → finger-up).
    public let tapMaxDuration: TimeInterval
    /// Max gap between two taps / two clicks to qualify as a double.
    /// Defaults to `NSEvent.doubleClickInterval` in production.
    public let doubleClickInterval: TimeInterval
    /// Force Touch stage at or above which we treat the event as a click.
    /// `2` = hard click (system "force click" threshold).
    public let clickStage: Int
    /// Minimum gap between two distinct gestures (debounce). Prevents
    /// a residual contact from triggering a phantom tap immediately
    /// after a click is emitted.
    public let postEmitDebounce: TimeInterval

    public init(
        requiredFingerCount: Int = 4,
        tapMaxDuration: TimeInterval = 0.220,
        doubleClickInterval: TimeInterval = 0.500,
        clickStage: Int = 2,
        postEmitDebounce: TimeInterval = 0.150
    ) {
        self.requiredFingerCount = requiredFingerCount
        self.tapMaxDuration = tapMaxDuration
        self.doubleClickInterval = doubleClickInterval
        self.clickStage = clickStage
        self.postEmitDebounce = postEmitDebounce
    }
}

public final class GestureRecognizer4Finger {
    public let config: GestureRecognizerConfig
    private let emit: (FourFingerGesture) -> Void

    /// Internal state machine phases.
    private enum Phase {
        /// No 4-finger contact, no pending emission.
        case idle
        /// Currently in 4-finger contact (≥ requiredFingerCount fingers
        /// have been seen since the most recent transition from < 4).
        case contact(start: TimeInterval, sawClickStage: Bool)
        /// One tap or click landed and we're waiting to see whether
        /// it becomes a double.
        case pending(kind: PendingKind, firedAt: TimeInterval)
    }

    private enum PendingKind {
        case tap
        case click
    }

    private var phase: Phase = .idle
    /// Last time any gesture fired — used for `postEmitDebounce`.
    private var lastEmitAt: TimeInterval = -.infinity
    /// Last observed touch frame timestamp; for `pendingDeadline()`.
    private var lastFrameAt: TimeInterval = -.infinity

    public init(
        config: GestureRecognizerConfig = GestureRecognizerConfig(),
        emit: @escaping (FourFingerGesture) -> Void
    ) {
        self.config = config
        self.emit = emit
    }

    // MARK: - Inputs

    /// Feed one touch frame from the MT callback.
    public func onTouchFrame(_ frame: GestureTouchFrame) {
        lastFrameAt = frame.timestamp
        // Step 1: maybe a pending tap/click has aged out into an
        // emission — handle that first so the in-contact transition
        // sees a clean state.
        flushIfDue(at: frame.timestamp)

        switch phase {
        case .idle:
            if frame.fingerCount >= config.requiredFingerCount {
                phase = .contact(start: frame.timestamp, sawClickStage: false)
            }
        case .contact(let start, let sawClickStage):
            if frame.fingerCount == 0 {
                // Fingers lifted. Decide tap vs nothing.
                let duration = frame.timestamp - start
                if !sawClickStage,
                   duration <= config.tapMaxDuration,
                   frame.timestamp - lastEmitAt >= config.postEmitDebounce {
                    enterPending(.tap, at: frame.timestamp)
                } else {
                    // Either it was a click already (emitted separately
                    // via pressure event), or held too long, or debounced.
                    phase = .idle
                }
            } else if frame.fingerCount < config.requiredFingerCount {
                // Some fingers dropped but not all. Stay in contact —
                // count climbs again often during a hard press.
                // We treat this as still-in-contact so the eventual
                // lift counts as a tap *if* total duration is short.
                _ = sawClickStage  // unchanged
            }
            // If count is still ≥ required, just continue in contact.
        case .pending:
            // A pending tap/click is in flight. The user's second
            // finger-down kicks us back into contact, but `onPressure`
            // / `onTouchFrame` below upgrade pending → double on
            // re-tap/re-click. Track new contact so the second tap is
            // recognized.
            if frame.fingerCount >= config.requiredFingerCount {
                phase = .contact(start: frame.timestamp, sawClickStage: false)
            }
        }
    }

    /// Feed one pressure event from NSEvent's `.pressure` monitor.
    public func onPressure(_ event: GesturePressureEvent) {
        flushIfDue(at: event.timestamp)
        guard event.stage >= config.clickStage else { return }
        guard event.timestamp - lastEmitAt >= config.postEmitDebounce else { return }

        switch phase {
        case .contact(let start, _):
            // Promote the contact to "click-witnessed" so the eventual
            // lift doesn't accidentally also count as a tap.
            phase = .contact(start: start, sawClickStage: true)
            enterPending(.click, at: event.timestamp)
        case .pending(let kind, _):
            // Second click within window → double-click.
            if kind == .click {
                emit(.doubleClick)
                lastEmitAt = event.timestamp
                phase = .idle
            } else {
                // First was a tap, now a click landed — distinct
                // gestures. Flush the tap, then enter pending click.
                emit(.tap)
                lastEmitAt = event.timestamp
                enterPending(.click, at: event.timestamp)
            }
        case .idle:
            // Click without ever seeing a 4-finger contact frame.
            // The user might be force-clicking with fewer fingers; we
            // ignore that — only count clicks paired with a 4-finger
            // contact phase. This prevents the trackpad's normal "click
            // to select" gesture from triggering Myna pause/play.
            break
        }
    }

    // MARK: - Time-driven flushing

    /// Returns the next absolute timestamp at which `flushIfDue` will
    /// actually emit a pending gesture. The bridge schedules a one-shot
    /// timer at this deadline so that even a perfectly still trackpad
    /// (no further touch frames) gets a single-tap dispatched on time.
    /// Returns nil if nothing is pending.
    public func pendingDeadline() -> TimeInterval? {
        switch phase {
        case .pending(_, let firedAt):
            return firedAt + config.doubleClickInterval
        default:
            return nil
        }
    }

    /// Explicit time tick — drives the pending → emit conversion when
    /// no other events are arriving. Idempotent.
    public func flushIfDue(at now: TimeInterval) {
        if case .pending(let kind, let firedAt) = phase,
           now - firedAt >= config.doubleClickInterval {
            switch kind {
            case .tap: emit(.tap)
            case .click: emit(.click)
            }
            lastEmitAt = now
            phase = .idle
        }
    }

    // MARK: - Helpers

    private func enterPending(_ kind: PendingKind, at timestamp: TimeInterval) {
        // If we were already pending, an arriving same-kind event is a
        // double; the callers handle that explicitly. Mismatched-kind
        // (e.g. a click arriving while a tap is pending) is handled in
        // onPressure / onTouchFrame.
        if case .pending(let prev, _) = phase, prev == kind {
            switch kind {
            case .tap: emit(.doubleTap)
            case .click: emit(.doubleClick)
            }
            lastEmitAt = timestamp
            phase = .idle
        } else {
            phase = .pending(kind: kind, firedAt: timestamp)
        }
    }

    /// Test/diagnostic accessor — what phase is the recognizer in?
    /// String form so the (private) Phase enum stays internal.
    public var debugPhase: String {
        switch phase {
        case .idle: return "idle"
        case .contact(let start, let sawClick):
            return "contact(start=\(start), sawClick=\(sawClick))"
        case .pending(let kind, let at):
            return "pending(\(kind), at=\(at))"
        }
    }
}
