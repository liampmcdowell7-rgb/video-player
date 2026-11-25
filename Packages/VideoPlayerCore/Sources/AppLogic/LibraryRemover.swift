import Foundation
import LibraryIndex
import UserData

/// R471 (15), PROVISIONAL: Delete from Library for a movie, an episode, a season or a whole show. The title leaves this app's
/// library only: its files are marked removed in the index and recorded as removed in the user layer (`UDLibraryRemoval`),
/// so later scans and the user's other devices leave them out. The files stay on the source: deleting a file there is NOT
/// built (OPEN_QUESTIONS R471 (15)). Settings > Library > Removed from Library brings a title back.
public struct LibraryRemover: Sendable {
    public enum Target: Equatable, Sendable {
        case item(itemID: Int64)
        case season(seriesID: Int64, season: Int)
        case show(seriesID: Int64)
    }

    public let store: any LibraryStore
    public let ledger: UserDataLedger

    public init(store: any LibraryStore, ledger: UserDataLedger) { self.store = store; self.ledger = ledger }

    /// The confirmation (our wording): what leaves, and that the file stays on the source.
    public static func confirmation(_ target: Target, title: String, episodeCount: Int = 0) -> (title: String, message: String, button: String) {
        let stays = "Nothing is deleted from the source: the files stay there, and later scans do not add them back. "
            + "You can bring it back in Settings > Library > Removed from Library."
        switch target {
        case .item:
            return ("Delete “\(title)” from the Library?",
                    "It is removed from this app’s library. The file stays on the source and is not deleted there. "
                    + "Later scans do not add it back; you can bring it back in Settings > Library > Removed from Library.",
                    ProductAction.delete.title)
        case .season, .show:
            let episodes = episodeCount == 1 ? "its 1 episode" : "its \(episodeCount) episodes"
            return ("Delete “\(title)” from the Library?", "It is removed from this app’s library with \(episodes). " + stays,
                    ProductAction.delete.title)
        }
    }

    /// The library items the target covers.
    public func items(_ target: Target) async throws -> [LibraryItem] {
        switch target {
        case .item(let id): return try await store.item(id: id).map { [$0] } ?? []
        case .show(let seriesID): return try await store.episodes(ofSeries: seriesID)
        case .season(let seriesID, let season): return try await store.episodes(ofSeries: seriesID).filter { $0.season == season }
        }
    }

    /// Removes the target from the library. Returns how many items left it.
    @discardableResult
    public func run(_ target: Target, at date: Date = Date()) async throws -> Int {
        let items = try await items(target)
        for item in items {
            let label = item.kind == .episode ? [item.seriesTitle, DisplayText.episodeCode(season: item.season, episode: item.episode, episodeEnd: item.episodeEnd)]
                .compactMap { $0 }.joined(separator: ", ") : item.title
            for file in try await store.versions(of: item.id) {
                ledger.removeFromLibrary(UDLibraryRemoval(sourceID: file.sourceID, path: file.path, title: label.isEmpty ? item.title : label,
                                                          removedAt: date), at: date)
            }
        }
        try await store.removeFromLibrary(itemIDs: items.map(\.id), at: date)
        return items.count
    }
}

/// R471 (15): the words of Settings > Library > Removed from Library (ours).
public enum LibraryRemovalTexts {
    public static let summary = "Titles you deleted from the library. Their files are still on the source."
    public static let emptyTitle = "Nothing Removed"
    public static let emptyMessage = "Titles you delete from the library appear here, so you can bring them back."
    public static let footer = "Choose a title to bring it back. It returns with the next scan of its source."
    public static let restore = "Bring Back to Library"
    public static let restoreMessage = "The title returns to the library with the next scan of its source."
    /// The row's second line: the file's name, not its whole path.
    public static func fileName(_ path: String) -> String { path.split(separator: "/").last.map(String.init) ?? path }
}
