import Foundation

/// Where a card, a row or a link goes inside one tab's navigation stack.
enum Route: Hashable {
    case item(Int64)
    case series(Int64)
    case folder(sourceID: String, sourceName: String, path: String)
    /// Files that could not be sorted (docs/SORTING.md), from the Movies and Shows controls.
    case needsReview
    /// R341: a cast member's titles in the library, by the name the cast shelf shows.
    case person(String)
}
