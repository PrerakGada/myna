// FloatingPillWindow.swift — NSPanel subclass that hosts the pill UI.
//
// Requirements:
//   - Never becomes key, never becomes main, never steals focus from
//     the foreground app. This is crucial: the pill exists alongside
//     the user's editor / browser, not in front of it.
//   - Floats above ordinary windows, joins every Space and works in
//     full-screen apps (so reading-mode-while-watching-video still
//     surfaces the pill).
//   - Background is transparent at the AppKit layer so the SwiftUI
//     view can render its own rounded-pill material background.
//   - Has no shadow at the window level (SwiftUI will apply its own
//     subtle shadow inside the pill shape — a window-level shadow
//     gives away the rectangular bounds and looks wrong on a pill).
//   - Draggable from anywhere on the surface (we override mouseDown
//     and call performDrag(with:)) — the AppKit-native pattern gives
//     us proper drag feedback, edge-snap, and multi-display behaviour
//     for free. SwiftUI DragGesture inside a borderless panel is
//     fragile (the gesture races SwiftUI's own hit-test for the
//     transport buttons), so we keep dragging at the AppKit layer.
//   - Persists frame across launches via setFrameAutosaveName; the
//     autosave key is `dev.myna.app.pillFrame`. PillController also
//     reads/writes this same key when "Reset pill position" fires.
//
// Why NSPanel + .nonactivatingPanel:
//   `NSWindow` would steal focus on click. `.nonactivatingPanel`
//   tells AppKit "don't activate this app when this panel becomes
//   front", which is what an HUD wants.
import AppKit

/// UserDefaults key that AppKit reads/writes under
/// `NSWindow Frame <name>` when setFrameAutosaveName is set. We
/// expose the bare autosave name so PillController can clear the
/// stored value (Reset pill position) without reaching into
/// AppKit-internal key formatting.
public enum FloatingPillFrame {
    /// Autosave name passed to setFrameAutosaveName. AppKit prefixes
    /// "NSWindow Frame " internally when persisting.
    public static let autosaveName = "dev.myna.app.pillFrame"
    /// The actual UserDefaults key AppKit writes under. Useful for
    /// tests and for the Reset action to clear directly.
    public static let defaultsKey = "NSWindow Frame \(autosaveName)"
}

/// Subclass primarily so we can lock `canBecomeKey` / `canBecomeMain`
/// to false. The default NSPanel implementation returns `true` for
/// canBecomeKey when the panel has any focusable subview — our SwiftUI
/// buttons would activate that path.
///
/// Also adds AppKit-native click-drag from anywhere on the panel
/// background via `mouseDown(with:)` → `performDrag(with:)`. SwiftUI
/// child controls (buttons) consume their own mouseDown first, so the
/// transport controls still work — only mouseDowns that reach the
/// panel itself initiate a drag.
public final class FloatingPillWindow: NSPanel {
    /// Notification posted when the user finishes a drag and the
    /// panel comes to rest. PillController listens for this so it can
    /// stop auto-repositioning the pill (the user has expressed a
    /// position preference).
    public static let didMoveByUserNotification = Notification.Name(
        "dev.myna.app.FloatingPillWindow.didMoveByUser"
    )

    /// True while the user has explicitly positioned the pill. Until
    /// the first user-drag (or a successful autosave restore),
    /// PillController owns positioning. After, PillController defers
    /// to the saved frame.
    public private(set) var hasUserPosition: Bool = false

    /// True only for the brief window between mouseDown and mouseUp
    /// while a user drag is in flight. Read by PillController so it
    /// doesn't fight the drag with a reposition.
    public private(set) var isDragging: Bool = false

    public init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 28),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        // Transparent background — the SwiftUI view paints its own pill.
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false

        // Float above app windows but below the menu bar and below
        // system alerts. .statusBar is too aggressive; .floating sits
        // nicely just above ordinary content windows.
        self.level = .floating

        // Be present on every Space, including full-screen apps.
        // .stationary keeps the position fixed when the user swipes
        // between Spaces (otherwise it'd "slide" with the desktop).
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Don't show up in Window menu, Mission Control, screenshots
        // of "all windows", or the app switcher.
        self.isExcludedFromWindowsMenu = true

        // Allow click-through prevention: we *do* want clicks on the
        // pill to land (for hover/expand and pin), so we keep
        // ignoresMouseEvents = false (its default).
        self.ignoresMouseEvents = false

        // No title bar / no traffic-light buttons.
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true

        // We do our own dragging via performDrag(with:) in
        // mouseDown — leaving isMovableByWindowBackground = false
        // ensures AppKit doesn't compete with us for the gesture.
        // isMovable stays true so performDrag(with:) is allowed.
        self.isMovableByWindowBackground = false
        self.isMovable = true

        // Animate frame changes (resize between collapsed/expanded).
        self.animationBehavior = .utilityWindow

        self.contentView = contentView

        // Default visibility: hidden. PillController shows it when
        // playback starts.
        self.alphaValue = 0
        self.orderOut(nil)

        // Autosave frame — AppKit handles read/write of the panel's
        // frame under UserDefaults key "NSWindow Frame <name>" on
        // every move/resize. The call must happen AFTER the first
        // setFrame*, otherwise AppKit attempts to read a stored frame
        // for a panel that doesn't yet have a sane size. We trigger
        // an explicit restore so `hasUserPosition` reflects whether
        // anything was previously persisted.
        let restored = self.setFrameUsingName(FloatingPillFrame.autosaveName)
        self.setFrameAutosaveName(FloatingPillFrame.autosaveName)
        if restored {
            self.hasUserPosition = true
        }
    }

    /// Locked to false. The pill must never accept keyboard focus —
    /// that would yank focus from the user's editor and break typing.
    public override var canBecomeKey: Bool { false }

    /// Locked to false. There is no "main window" semantic for an HUD.
    public override var canBecomeMain: Bool { false }

    /// Required by NSWindow but we never use it.
    public override var acceptsFirstResponder: Bool { false }

    // MARK: - drag handling
    //
    // mouseDown on a borderless panel does not start a drag by
    // default. We forward to performDrag(with:), which is the
    // AppKit-supported API for moving a window from a code-driven
    // drag: it shows the correct cursor, snaps to display edges if
    // configured, and crucially handles multi-display geometry
    // (drag from one monitor to another) without us touching frame
    // math.
    //
    // SwiftUI buttons inside the panel intercept mouseDown via their
    // own NSResponder and return without forwarding here, so the
    // transport controls still work. Only background hits land
    // here.
    public override func mouseDown(with event: NSEvent) {
        isDragging = true
        defer { isDragging = false }
        self.performDrag(with: event)
        hasUserPosition = true
        // The autosave already fires from AppKit on mouseUp, but
        // post our own notification so PillController knows the
        // user has expressed a position preference.
        NotificationCenter.default.post(
            name: Self.didMoveByUserNotification,
            object: self
        )
    }
}
