import Foundation

/// The letter a title is filed under in the alphabet jump list, with the same rules the index sorts by: accents and case are
/// ignored, a leading "The", "A" or "An" is dropped, and anything that does not start with A to Z (digits, symbols, other
/// scripts) is filed under "#". Public so the screens that sort without the index (Shows) use exactly the same buckets.
public enum TitleLetter {
    /// "#" first, then A to Z: the order of the jump list.
    public static let all: [String] = ["#"] + (65...90).compactMap { UnicodeScalar($0).map { String(Character($0)) } }

    public static func letter(for title: String) -> String { LibraryText.titleSortValue(title).letter }

    /// A string that sorts titles in the order the index does ("#" titles first, digit runs by number).
    public static func sortKey(_ title: String) -> String { LibraryText.titleSortValue(title).value }
}
