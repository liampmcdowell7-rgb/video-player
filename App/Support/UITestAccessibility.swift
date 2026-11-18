import SwiftUI

extension View {
    /// Rule 17 screenshots (docs/DESIGN_REFERENCES.md): in a DEBUG UI-test launch with `-UITestTextSize <size>` or
    /// `-UITestBoldText`, the app's views are drawn at that text size or with bold text, through the two environment values
    /// Apple documents as settable: `dynamicTypeSize` and `legibilityWeight`
    /// (https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize,
    /// https://developer.apple.com/documentation/swiftui/environmentvalues/legibilityweight). Reduce Motion, Reduce
    /// Transparency and Increase Contrast are read-only in SwiftUI, so the CI job turns those on in the simulator instead
    /// (scripts/ci-a11y-setting.sh). Does nothing in every other launch, and in Release builds nothing is compiled in.
    func uiTestAccessibilityOverrides() -> some View {
        modifier(UITestAccessibilityOverrides())
    }
}

private struct UITestAccessibilityOverrides: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        let size = UITestMode.dynamicTypeSize
        let bold = UITestMode.boldText
        content
            .transformEnvironment(\.dynamicTypeSize) { if let size { $0 = size } }
            .transformEnvironment(\.legibilityWeight) { if bold { $0 = .bold } }
        #else
        content
        #endif
    }
}
