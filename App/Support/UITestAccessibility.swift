import SwiftUI

extension View {
    /// Rule 17 screenshots (docs/DESIGN_REFERENCES.md): in a DEBUG UI-test launch with `-UITestTextSize <size>` or
    /// `-UITestBoldText`, the app's views are drawn at that text size or with bold text, through the two environment values
    /// Apple documents as settable: `dynamicTypeSize` and `legibilityWeight`
    /// (https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize,
    /// https://developer.apple.com/documentation/swiftui/environmentvalues/legibilityweight). Reduce Motion, Reduce
    /// Transparency and Increase Contrast are read-only in SwiftUI, so the CI job turns those on in the simulator instead
    /// (scripts/ci-a11y-setting.sh). Does nothing in every other launch, and in Release builds nothing is compiled in.
    ///
    /// Applied to each tab's content (RootView) and the player, NOT to the window: the system tab bar must keep the
    /// simulator's own text size, as it would keep the device's. #15 item 1.5: when this sat on the window root, the
    /// tab bar was drawn at accessibility3 too and "Settings" was cut to "Sett" in the Larger Text screenshots. A
    /// `dynamicTypeSize(...)` range on the TabView cannot fix that: Apple's page says a range applied outside limits any
    /// value set inside (https://developer.apple.com/documentation/swiftui/view/dynamictypesize(_:)), so the tab
    /// content could not get its larger size back. OPEN_QUESTIONS R175.
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
