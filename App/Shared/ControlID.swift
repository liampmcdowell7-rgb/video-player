/// #25 A2: stable accessibility identifiers of the controls the screenshot tests reach (UITests/ScreenshotTests.swift).
/// This one file is compiled into the app AND the UI-test bundle (project.yml), so both sides use the same names.
///
/// An identifier is for tests only: it is not shown and not spoken (SwiftUI `accessibilityIdentifier(_:)`, "Use this value
/// for testing. It isn't visible to the user."). VoiceOver keeps the control's own readable label. Why: the run on
/// 1fe5d50 showed Extras and More as Button elements with NO label (library notes/57-movie-detail-HIERARCHY.txt): a `Menu`
/// whose label is a custom view hands its text to a child StaticText, so a search for a button labelled "More" found
/// nothing. Each id is set once, on the control itself (never on its label), so it is exposed once.
///
/// Controls the system draws (the player's Skip Intro contextual action, its Subtitles and Audio menus, the Up Next card)
/// cannot carry an identifier: `UIAction` has no accessibility identifier. The tests find those by their label.
enum ControlID {
    static let sort = "control.sort"
    static let filter = "control.filter"
    static let savedViews = "control.savedViews"
    static let needsReview = "control.needsReview"
    static let jumpToLetter = "control.jumpToLetter"
    /// #25 B2: the menu that holds Saved Views, Needs Review and Jump to Letter when the row does not fit (Larger Text).
    static let moreControls = "control.moreControls"
    static let play = "control.play"
    static let startOver = "control.startOver"
    static let extras = "control.extras"
    static let more = "control.more"
    static let versions = "control.versions"
    static let goToTitle = "control.goToTitle"
    static let fullLicenceTexts = "control.fullLicenceTexts"
    static let searchYourNetwork = "control.searchYourNetwork"
    static let sourceCancel = "control.sourceCancel"
    static let learnMore = "control.learnMore"
    /// #26: Settings > Online Lookup (the TMDB key row, its masked value, Free Data Sources) and About > Data Sources.
    static func keyRow(_ service: String) -> String { "control.keyRow." + service }
    static func keyValue(_ service: String) -> String { "control.keyValue." + service }
    static let freeDataSources = "control.freeDataSources"
    static let dataSources = "control.dataSources"

    /// One row per source type in Add a Source: "sourceKind.webdav", "sourceKind.directLink", ... (`SourceKind.rawValue`).
    static func sourceKind(_ rawValue: String) -> String { "sourceKind." + rawValue }
}
