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
}
