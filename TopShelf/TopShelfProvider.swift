import Foundation
import TVServices
import UserData

/// The Top Shelf row: the titles the app last wrote to the shared folder (Continue Watching first, then Next Up).
/// Reads defensively: a missing, damaged or empty snapshot, or an item without artwork, means nothing is shown.
final class TopShelfProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.liamp.videoplayer") else {
            return nil
        }
        let folder = container.appendingPathComponent("TopShelf", isDirectory: true)
        guard case .items(let ready) = TopShelfSnapshotStore.read(from: folder) else { return nil }
        let items: [TVTopShelfSectionedItem] = ready.map { entry in
            let item = TVTopShelfSectionedItem(identifier: entry.item.id)
            item.title = entry.item.title
            item.imageShape = .poster
            item.setImageURL(entry.imageURL, for: .screenScale1x)
            item.setImageURL(entry.imageURL, for: .screenScale2x)
            if let link = URL(string: entry.item.link) {
                item.displayAction = TVTopShelfAction(url: link)
                item.playAction = TVTopShelfAction(url: link)
            }
            if let progress = entry.item.progress { item.playbackProgress = progress }
            return item
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Continue Watching"
        return TVTopShelfSectionedContent(sections: [section])
    }
}
