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
        SettingsPane(title: "Accessibility", summary: SettingsTexts.accessibilitySummary, status: [
            "Currently on this device:",
            "Reduce Motion: " + (reduceMotion ? "On" : "Off"),
            "Reduce Transparency: " + (reduceTransparency ? "On" : "Off"),
            "Bold Text: " + (legibilityWeight == .bold ? "On" : "Off"),
            "Increase Contrast: " + (contrast == .increased ? "On" : "Off"),
        ]) {
            Section {
                LearnMoreLink(title: SettingsTexts.accessibilityLearnMoreTitle, text: SettingsTexts.accessibilityFull)
            }
        }
    }
}
