import SwiftUI

extension View {
    /// Rule 17 screenshots (docs/DESIGN_REFERENCES.md): in a DEBUG UI-test launch with `-UITestTextSize <size>` or
    /// `-UITestBoldText`, the app's views are drawn at that text size or with bold text. This IMITATES the system settings;
    /// it is not them (docs/COVERAGE.md; the real settings are checked on a device).
    ///
    /// Text size: the `dynamicTypeSize` environment value
    /// (https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize).
    ///
    /// Bold Text (#17 A): setting only `legibilityWeight` to `.bold` did NOT make the app's text bold; in the reviewed CI
    /// run the Bold Text screenshots differed from the normal ones only in the tab bar. Apple's page says that value
    /// "reflects the value of the Bold Text display setting" — it reports the setting to code that reads it; it does
    /// not say that writing it changes how `Text` draws, and the screenshots show it did not
    /// (https://developer.apple.com/documentation/swiftui/environmentvalues/legibilityweight). So the override now also
    /// applies `bold(_:)`, which Apple documents as "Applies a bold font weight to the text in this view" (tvOS 16+,
    /// https://developer.apple.com/documentation/swiftui/view/bold(_:)); the HIG names `bold()` as the way to get each text
    /// style's emphasized weight, which on tvOS is Bold for every style except Subtitle 1 (Medium)
    /// (https://developer.apple.com/design/human-interface-guidelines/typography, "tvOS built-in text styles"). Whether
    /// the real Bold Text setting gives exactly those weights is not on Apple's pages: unproven, device checklist. The
    /// tab-bar difference in that run is outside this override and not explained. `legibilityWeight` stays set, for any
    /// code that reads it. Reduce Motion, Reduce
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
            // Applied outside the views, so text inside that sets its own weight should keep it (unverified, from memory).
            .bold(bold)
        #else
        content
        #endif
    }
}
