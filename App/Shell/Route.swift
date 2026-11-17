import Foundation

/// Where a card, a row or a link goes inside one tab's navigation stack.
enum Route: Hashable {
    case item(Int64)
    case series(Int64)
    case folder(sourceID: String, sourceName: String, path: String)
}
