import Foundation

/// R344 (docs/HIG_AUDIT.md T5): the texts of the one Sort and Filter menu of Movies and Shows.
public enum SortFilterText {
    public static let title = "Sort and Filter"
    public static let clearAll = "Clear All Filters"

    /// "Sort By (Title, A to Z)": the submenu's title says the current order, as "Resolution (2)" says the active filters.
    public static func sortTitle(order: String) -> String { order.isEmpty ? "Sort By" : "Sort By (\(order))" }

    /// "Title, A to Z; no filters", "Title, A to Z; 1 filter on", "…; 3 filters on".
    public static func spokenValue(order: String, filtersOn: Int) -> String {
        let filters: String
        switch filtersOn {
        case ..<1: filters = "no filters"
        case 1: filters = "1 filter on"
        default: filters = "\(filtersOn) filters on"
        }
        return order + "; " + filters
    }

    /// R375 (owner's review of R375, 21 Nov 2026): the toolbar symbol shows when a filter is on, with the SF Symbol's own
    /// filled form, as Apple's apps show an active filter; no circle of our own. HIG SF Symbols: "use the fill variant to
    /// indicate selection". With no filter on, the outline symbol without a border (HIG Toolbars: "Prefer system-provided
    /// symbols without borders"). The filled form of this filter symbol is its enclosed one (`.circle.fill`, drawn by SF
    /// Symbols); that no unenclosed `.fill` form exists is from the SF Symbols catalog as remembered, not read here: UNVERIFIED.
    public static let symbol = "line.3.horizontal.decrease"
    public static let filledSymbol = "line.3.horizontal.decrease.circle.fill"

    public static func symbolName(filtersOn: Int) -> String { filtersOn > 0 ? filledSymbol : symbol }
}
