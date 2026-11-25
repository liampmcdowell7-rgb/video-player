import Foundation
import VideoPlayerCore
import LibraryIndex
import UserData

/// R471 (16), PROVISIONAL: Rate. The user's 1 to 5 stars are kept in the user layer (`UDRating`, synced in the iCloud
/// backup, R456) under the title's edit keys, and also sent to the source where the source keeps ratings and the user turned
/// two-way sync on for it: today Plex only (`PlexWatchWriter.rate`, path UNVERIFIED), for a movie's or an episode's own files.
/// A show or a season is rated in the app only. Written reviews are NOT built.
public enum RatingText {
    /// The choices of the Rate menu, best first, then the clear choice (our words).
    public static let choices: [Int] = Array(UDRating.range.reversed())
    public static let clear = "No Rating"

    public static func title(_ stars: Int) -> String { stars == 1 ? "1 Star" : "\(stars) Stars" }

    /// The Rate entry's title with the current rating ("Rate: 4 Stars"), so the menu shows it without opening it.
    public static func menuTitle(current: Int?) -> String {
        guard let current else { return ProductAction.rate.title }
        return "\(ProductAction.rate.title): \(title(current))"
    }
}

/// Sends a rating to the servers that keep ratings (Plex), for the files of the items, each server item once. Failures are
/// counted, not kept: the rating stays in the app either way.
public struct ServerRatingSender: Sendable {
    public let store: any LibraryStore
    /// Whether the user turned two-way sync on for a source id (the same switch as the watch state, R309).
    public let isOn: @Sendable (String) -> Bool
    public let source: @Sendable (String) async -> (any ServerWatchSource)?

    public init(store: any LibraryStore, isOn: @escaping @Sendable (String) -> Bool,
                source: @escaping @Sendable (String) async -> (any ServerWatchSource)?) {
        self.store = store; self.isOn = isOn; self.source = source
    }

    @discardableResult
    public func send(itemIDs: [Int64], stars: Int?) async -> (sent: Int, failed: Int) {
        var sent = 0, failed = 0
        var done = Set<String>()
        for id in itemIDs {
            for file in (try? await store.versions(of: id)) ?? [] where isOn(file.sourceID) {
                guard let server = await source(file.sourceID), let writer = server.watchWriter as? any ServerRatingWriting,
                      let key = try? await server.serverItemKey(at: file.path), done.insert(file.sourceID + "|" + key).inserted else { continue }
                do { try await writer.rate(itemKey: key, stars: stars); sent += 1 } catch { failed += 1 }
            }
        }
        return (sent, failed)
    }
}
