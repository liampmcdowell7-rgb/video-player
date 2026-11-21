import Foundation

/// R343 (Decided by the owner, 21 Nov 2026; docs/HIG_AUDIT.md T11): recent searches under the search field while it is
/// empty, with Clear Recent Searches. HIG Searching: "display a person's recent searches before they start typing".
/// Kept on this Apple TV only: one plain UserDefaults value (`defaultsKey`), which is not a `SettingsKey`, not in the
/// essentials copy, not in the iCloud backup's file list (LibraryBackupFiles lists files only) and never sent anywhere.
public enum RecentSearches {
    /// The UserDefaults key. Its value is the searches, newest first, one per line.
    public static let defaultsKey = "search.recentSearches"
    /// The most searches kept. PROVISIONAL.
    public static let limit = 8
    /// Shorter texts are not kept (one letter is typing, not a search).
    public static let minimumLength = 2

    public static let heading = "Recent Searches"
    public static let clearTitle = "Clear Recent Searches"

    /// `list` with `query` added first: trimmed, once (case-insensitive; the newest spelling wins), at most `limit`.
    /// Unchanged when the text is too short.
    public static func recording(_ query: String, in list: [String]) -> [String] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minimumLength else { return list }
        let key = text.lowercased()
        return Array(([text] + list.filter { $0.lowercased() != key }).prefix(limit))
    }

    /// The stored value as a list (empty lines dropped).
    public static func decode(_ stored: String) -> [String] {
        stored.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// The list as the stored value. A line break inside a search becomes a space.
    public static func encode(_ list: [String]) -> String {
        list.map { $0.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n")
    }

    /// What the field shows under it: the recent searches while nothing is typed, nothing otherwise.
    public static func shown(_ list: [String], query: String) -> [String] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? list : []
    }
}
