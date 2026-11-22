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

/// R348 (owner's device test of build 5, 21 Nov 2026, item B; PROVISIONAL): selecting the tab that is ALREADY selected
/// takes that tab back to its first page, scrolled to the top, as Apple's apps do (pressing Settings again on build 5 left
/// the pushed Settings page in place). Every tab has a root generation; re-selecting a tab raises its generation, and the
/// app rebuilds that tab's navigation stack from its root when the generation changes (`.id` on the stack, RootView), so
/// pages pushed by value AND by destination are all gone and the root starts at its top. Selecting another tab changes
/// nothing: each tab keeps its own pages, as before.
public struct TabRoots: Equatable, Sendable {
    private var generations: [AppTabID: Int] = [:]

    public init() {}

    /// The selection of `tab` while `current` is selected. True when it was a re-selection (the tab's root generation rose).
    @discardableResult
    public mutating func select(_ tab: AppTabID, current: AppTabID) -> Bool {
        guard tab == current else { return false }
        generations[tab, default: 0] += 1
        return true
    }

    /// The identity of `tab`'s navigation stack: it changes only when the tab is re-selected.
    public func generation(of tab: AppTabID) -> Int { generations[tab] ?? 0 }
}

/// R376 (owner's request of 21 Nov 2026; decided by the owner's standing rule R312, R359 option (d)): the sidebar's
/// structure. Home, then ONE system section "Library" holding Movies, Shows and Files, then Search and Settings, so the
/// items keep the order of `AppTabID.allCases` (and of R359's UI checks). Apple: `TabSection`, tvOS 18.0+, "A container
/// that you can use to add hierarchy within a tab view"; the sample "Creating a tvOS media catalog app in SwiftUI" names
/// `SidebarContentView`, which "shows how to make a sectioned sidebar using the new tab bar APIs in tvOS 18" (its code is
/// not on the page). No customization: `TabViewCustomization` and `tabViewCustomization(_:)` list iOS, iPadOS, Mac Catalyst,
/// macOS and visionOS, not tvOS. RootView declares the same structure; this model is what the Linux tests check.
public enum SidebarEntry: Equatable, Sendable {
    case item(AppTabID)
    case section(title: String, items: [AppTabID])
}

public enum AppSidebar {
    /// The section's header, as RootView's `TabSection("Library")` writes it.
    public static let libraryTitle = "Library"

    public static let entries: [SidebarEntry] = [
        .item(.home),
        .section(title: libraryTitle, items: [.movies, .shows, .files]),
        .item(.search),
        .item(.settings),
    ]

    /// Every item from top to bottom, sections opened.
    public static var order: [AppTabID] {
        entries.flatMap { (entry: SidebarEntry) -> [AppTabID] in
            switch entry {
            case .item(let tab): [tab]
            case .section(_, let items): items
            }
        }
    }

    /// The section that holds `tab`, nil for an item at the top level.
    public static func section(of tab: AppTabID) -> String? {
        for case .section(let title, let items) in entries where items.contains(tab) { return title }
        return nil
    }
}
