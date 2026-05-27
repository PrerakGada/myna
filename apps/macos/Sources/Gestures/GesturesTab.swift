// GesturesTab.swift — Settings tab for the v0.2.x trackpad gesture
// redesign. Pure SwiftUI form — no NSEvent hooks here. AppDelegate
// owns the GestureMonitor and observes
// `settings.trackpadGesturesEnabled` to start/stop it.
//
// IMPLEMENTATION NOTE
// The view body is broken into small @ViewBuilder properties because
// a single-expression body containing every Form section together
// hit Swift's "compiler is unable to type-check this expression in
// reasonable time" limit on CI (x86_64 universal builds). The split
// is cosmetic-only — no behaviour change.
import SwiftUI

public struct GesturesTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            enableSection
            gesturesSection
            howItWorksSection
            limitationsSection
        }
        .padding()
        .frame(width: 480, height: 480)
    }

    // MARK: - sections

    @ViewBuilder
    private var enableSection: some View {
        Section("Trackpad gestures (opt-in)") {
            Toggle("Enable trackpad gestures", isOn: $viewModel.trackpadGesturesEnabled)
            Text(
                "Off by default. When on, Myna listens to the trackpad "
                + "for four-finger gestures."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var gesturesSection: some View {
        Section("Gestures") {
            LabeledContent("4-finger tap") {
                Text("Speak selection").foregroundStyle(.secondary)
            }
            LabeledContent("4-finger double-tap") {
                Text("Stop").foregroundStyle(.secondary)
            }
            LabeledContent("4-finger click") {
                Text("Play / pause  (debug)").foregroundStyle(.secondary)
            }
            LabeledContent("4-finger double-click") {
                Text("Stop  (debug)").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var howItWorksSection: some View {
        Section("How it works") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hold four fingers on the trackpad to trigger.")
                Text(
                    "Tap = brief contact with all four fingers, then lift. "
                    + "Click = press the trackpad firmly while four fingers "
                    + "are down. Double versions need a second tap or click "
                    + "within the system double-click interval."
                )
                .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var limitationsSection: some View {
        Section("Known limitations") {
            VStack(alignment: .leading, spacing: 6) {
                limitConflict
                limitTrackpadOnly
                limitPrivateAPI
                limitClick
            }
            .font(.caption)
        }
    }

    // MARK: - individual limitations
    // Split into separate views so the compiler doesn't have to
    // type-check ten chained Texts inside one VStack.

    @ViewBuilder
    private var limitConflict: some View {
        Text("• Conflicts with BetterTouchTool & other multitouch utilities.")
        Text(
            "  BTT, Magnet, Cinch and similar tools also subscribe to "
            + "MultitouchSupport's contact-frame callback. Only one app "
            + "reliably receives the events at a time — whichever started "
            + "first usually wins. If your gestures aren't firing, quit "
            + "those apps (or disable their trackpad gestures) and "
            + "toggle Myna's gestures off and on once to re-subscribe."
        )
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var limitTrackpadOnly: some View {
        Text("• Requires a built-in or Magic Trackpad.")
        Text(
            "  External mice and most Bluetooth keyboards' trackpads "
            + "are not detected. The toggle stays on but no gestures fire."
        )
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var limitPrivateAPI: some View {
        Text("• Uses a private macOS framework.")
        Text(
            "  Public NSEvent APIs don't expose trackpad finger counts "
            + "for global gestures, so Myna reads them from Apple's "
            + "MultitouchSupport framework. This framework has powered "
            + "BetterTouchTool, Magnet, Hammerspoon and similar tools "
            + "for 15+ years; if Apple ever removes it, gestures will "
            + "stop working and Myna will fall back to hotkeys only."
        )
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var limitClick: some View {
        Text("• Click gestures need a click while 4 fingers are touching.")
        Text(
            "  Press the trackpad firmly enough to actuate the click "
            + "(the haptic feedback / audible click). Force Touch "
            + "is not required — a normal click works on any trackpad."
        )
        .foregroundStyle(.secondary)
    }
}
