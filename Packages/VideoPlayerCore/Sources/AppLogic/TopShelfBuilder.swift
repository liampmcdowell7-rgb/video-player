import Foundation
import LibraryIndex
import UserData

/// Builds what the Top Shelf extension shows: Continue Watching first, then Next Up, library items only, at most
/// `TopShelfSnapshotStore.maxItems`. The app writes the snapshot and the artwork files named in `artwork`
/// (`TopShelfSnapshotStore.write`); the extension reads them defensively (`TopShelfSnapshotStore.read`).
public struct TopShelfBuilder: Sendable {
    public struct Result: Equatable, Sendable {
        public var snapshot: TopShelfSnapshot
        /// Artwork files the app must write into the snapshot folder: file name and the artwork key to render.
        public var artwork: [Artwork]
    }
    public struct Artwork: Equatable, Sendable {
        public var file: String
        public var key: String
    }

    public let store: any LibraryStore
    public let limit: Int
    public init(store: any LibraryStore, limit: Int = 12) {
        self.store = store
        self.limit = min(max(1, limit), TopShelfSnapshotStore.maxItems)
    }

    public func build(now: Date = Date(), retentionDays: Int = 90) async throws -> Result {
        let continuing = try await store.continueWatching(limit: limit, now: now, retentionDays: retentionDays)
        let next = try await store.nextUp(limit: limit, now: now, retentionDays: retentionDays).map(\.item)
        var seen = Set<Int64>()
        var items: [TopShelfSnapshot.Item] = []
        var artwork: [Artwork] = []
        func add(_ item: LibraryItem, style: CardStyle) {
            guard items.count < limit, seen.insert(item.id).inserted else { return }
            let card = CardBuilder.card(item, style: style)
            let file = "\(card.artworkKey).jpg"
            items.append(TopShelfSnapshot.Item(id: String(item.id), title: card.title, subtitle: card.subtitle, imageFile: file,
                                               link: DeepLink.item(item.id).url.absoluteString, progress: card.progress))
            artwork.append(Artwork(file: file, key: card.artworkKey))
        }
        for item in continuing { add(item, style: .continueWatching) }
        for item in next { add(item, style: .nextUp) }
        return Result(snapshot: TopShelfSnapshot(generatedAt: now, items: items), artwork: artwork)
    }
}
