import Foundation
import LibraryIndex
import UserData

/// R471 (17), PROVISIONAL: Add to List and Add to Playlist or Collection. The user's own lists of library titles (movies,
/// shows, episodes) in the user layer (`UDUserList`, synced in the iCloud backup, R456). "Add to List" offers the lists of
/// kind list; "Add to Playlist or Collection" offers playlists and collections. Each menu shows every list of its kinds with
/// a check on those that hold the title (choosing one adds or removes it), then the entries that make a new list. Lists are
/// created, renamed and deleted in Settings > Library > My Lists. Words ours.
public enum UserListText {
    public static func kinds(for action: ProductAction) -> [UDUserList.Kind] {
        action == .addToList ? [.list] : [.playlist, .collection]
    }

    /// The entry that makes a new list of a kind.
    public static func newEntry(_ kind: UDUserList.Kind) -> String {
        switch kind {
        case .list: return "New List…"
        case .playlist: return "New Playlist…"
        case .collection: return "New Collection…"
        }
    }

    /// The name page's title when a list is made or renamed.
    public static func nameTitle(_ kind: UDUserList.Kind, renaming: Bool) -> String {
        (renaming ? "Rename " : "New ") + kindName(kind)
    }

    public static func kindName(_ kind: UDUserList.Kind) -> String {
        switch kind {
        case .list: return "List"
        case .playlist: return "Playlist"
        case .collection: return "Collection"
        }
    }

    /// The kind as a lower-case noun inside a sentence.
    static func noun(_ kind: UDUserList.Kind) -> String { kindName(kind).lowercased() }

    /// The settings section of each kind.
    public static func sectionTitle(_ kind: UDUserList.Kind) -> String {
        switch kind {
        case .list: return "Lists"
        case .playlist: return "Playlists"
        case .collection: return "Collections"
        }
    }

    /// The name page: words capitalised, no autocorrection (as the source name, R323).
    public static let nameEntry = SourceFieldEntry(keyboard: .standard, content: .none, capitalizesWords: true, autocorrects: false, isSecret: false)
    public static func nameSummary(_ kind: UDUserList.Kind) -> String { "The name of the " + noun(kind) + "." }
    public static let settingsSummary = "Your own lists, playlists and collections of titles in your library. They are kept with your other devices through iCloud."
    public static func rename(_ kind: UDUserList.Kind) -> String { "Rename " + kindName(kind) }
    public static let removeEntry = "Remove from List"
    public static func listSummary(_ kind: UDUserList.Kind) -> String { "Choose a title to open it or to remove it from this " + noun(kind) + "." }
    public static let settingsTitle = "My Lists"
    public static let emptyList = "Nothing in this list yet. Add titles from a title's page or a long press on its card."
    public static let missing = "Not in this library"

    /// The delete confirmation: what goes, and that the titles stay.
    public static func deleteConfirmation(_ list: UDUserList) -> (title: String, message: String, button: String) {
        ("Delete \u{201C}\(list.name)\u{201D}?",
         "The " + noun(list.kind) + " is removed from this device and your other devices. The titles in it stay in your library.",
         "Delete " + kindName(list.kind))
    }

    /// The menu entry of one list: its name, and the kind after it in the shared playlist-or-collection menu.
    public static func entry(_ list: UDUserList, in action: ProductAction) -> String {
        action == .addToList ? list.name : list.name + " (" + kindName(list.kind) + ")"
    }
}

/// A title in a list as this device's library has it now: the item or the show, or nil when the library does not have it.
public enum UserListTarget: Hashable, Sendable {
    case item(Int64)
    case series(Int64)
}

/// The library's stable keys for titles (`items.key`, `series.key`), both ways.
public protocol TitleKeyResolving: Sendable {
    func titleRef(itemID: Int64, kind: ItemKind) async -> UDTitleRef?
    func titleRef(seriesID: Int64) async -> UDTitleRef?
    func target(of ref: UDTitleRef) async -> UserListTarget?
}

extension SQLiteLibraryStore: TitleKeyResolving {
    public func titleRef(itemID: Int64, kind: ItemKind) async -> UDTitleRef? {
        guard let key = try? itemKey(itemID) else { return nil }
        return UDTitleRef(kind: kind == .movie ? .movie : .episode, key: key)
    }

    public func titleRef(seriesID: Int64) async -> UDTitleRef? {
        guard let key = try? seriesKey(forSeries: seriesID) else { return nil }
        return UDTitleRef(kind: .show, key: key)
    }

    public func target(of ref: UDTitleRef) async -> UserListTarget? {
        switch ref.kind {
        case .movie, .episode: return (try? itemID(forKey: ref.key)).flatMap { $0 }.map(UserListTarget.item)
        case .show: return (try? seriesID(forKey: ref.key)).flatMap { $0 }.map(UserListTarget.series)
        }
    }
}
