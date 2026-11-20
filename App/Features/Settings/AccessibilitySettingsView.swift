import SwiftUI
import AppLogic

/// The app follows the system's accessibility settings and has none of its own. This page shows what the system reports.
/// #15 3.7: the four states are read-only status text in the left column (L3), not rows that look focusable; the full
/// explanation is one press away (L5).
struct AccessibilitySettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // #30 Part 3: the device states are ONE paragraph (a short list under its lead line); the summary is another.
        SettingsPane(title: "Accessibility", summary: SettingsTexts.accessibilitySummary, status: [deviceStates]) {
            Section {
                LearnMoreLink(title: SettingsTexts.accessibilityLearnMoreTitle, text: SettingsTexts.accessibilityFull)
            }
        }
    }

    /// "Currently on this device:" and the four states, one per line (typed steps).
    private var deviceStates: String {
        let lines: [String] = [
            "Currently on this device:",
            "Reduce Motion: " + onOff(reduceMotion),
            "Reduce Transparency: " + onOff(reduceTransparency),
            "Bold Text: " + onOff(legibilityWeight == .bold),
            "Increase Contrast: " + onOff(contrast == .increased),
        ]
        return lines.joined(separator: "\n")
    }

    private func onOff(_ isOn: Bool) -> String {
        isOn ? "On" : "Off"
    }
}
