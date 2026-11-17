import SwiftUI

/// The app follows the system's accessibility settings and has none of its own. This page shows what the system reports.
struct AccessibilitySettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Form {
            Section {
                LabeledContent("Reduce Motion", value: reduceMotion ? "On" : "Off")
                LabeledContent("Reduce Transparency", value: reduceTransparency ? "On" : "Off")
                LabeledContent("Bold Text", value: legibilityWeight == .bold ? "On" : "Off")
                LabeledContent("Increase Contrast", value: contrast == .increased ? "On" : "Off")
            } header: {
                Text("Currently On This Device")
            } footer: {
                Text("Text size, Bold Text, Reduce Motion, Reduce Transparency, Increase Contrast, VoiceOver and captions are set in the device’s own Accessibility settings. This app follows them and has no separate copies.")
            }
        }
        .navigationTitle("Accessibility")
    }
}
