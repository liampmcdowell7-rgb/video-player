import Foundation

/// The app's tabs, in the order the tab bar shows them (OPEN_QUESTIONS R167, option (c), PROVISIONAL): there is no Discover
/// tab; Discover is shown inside the Search tab while its search field is empty (`SearchTabContent`). The raw value is the
/// name used by `-UITestTab` and in tests; the app's `AppTab` is this type.
public enum AppTabID: String, CaseIterable, Hashable, Sendable {
    case home, movies, shows, files, search, settings

    /// The title under which the tab bar shows the tab.
    public var title: String {
        switch self {
        case .home: "Home"
        case .movies: "Movies"
        case .shows: "Shows"
        case .files: "Files"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    /// The identifier of the tab's root screen (UI tests wait on it).
    public var screenIdentifier: String { "screen.\(rawValue)" }

    /// Only these four show the library (the library-only rule). Search shows library results once something is typed;
    /// Discover's titles appear only in Search with an empty field, marked as not in the library.
    public var showsLibraryOnly: Bool {
        switch self {
        case .home, .movies, .shows, .files: true
        case .search, .settings: false
        }
    }
}

/// What the Search tab shows below the system search field. Library results and Discover are never in one list.
public enum SearchTabContent: Equatable, Sendable {
    /// The field is empty and Discover is on (Settings > Home Screen > Show Discover): Discover's rows, or its own empty
    /// state (for example "needs a TMDB key", with nothing sent).
    case discover
    /// The field is empty and Discover is off: the plain "Search Your Library" prompt. No discovery request is made.
    case prompt
    /// Something is typed: library results only.
    case libraryResults

    /// The decision. Spaces alone count as empty, the same as `SearchViewModel.search` treats them.
    public static func forQuery(_ query: String, showDiscover: Bool) -> SearchTabContent {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .libraryResults }
        return showDiscover ? .discover : .prompt
    }

    /// Whether Discover may load (and so contact the online service, when a key is set) in this state.
    public var loadsDiscover: Bool { self == .discover }
}
