import Foundation

/// R336 (PROVISIONAL, docs/HIG_AUDIT.md T8): the cast shelf's circle when a person has no photo. HIG Lockups, Monograms:
/// "Each monogram consists of a circular picture of the person and their name. If an image isn't available, the person's
/// initials appear in place of an image." Before R336 the circle showed the system person symbol for everyone without a
/// photo (today: everyone from the online lookup, which requests no photos).
public enum Monogram {
    /// The first letter of the first word and of the last word, upper-cased ("Sample Actor 2" gives "S2", "Cher" gives
    /// "C"). Words are split on spaces; empty when the name has no letter or digit, so the view falls back to the symbol.
    public static func initials(_ name: String) -> String {
        let words: [Substring] = name.split(whereSeparator: { $0.isWhitespace })
            .map { $0.drop(while: { !$0.isLetter && !$0.isNumber }) }
            .filter { !$0.isEmpty }
        guard let first = words.first?.first else { return "" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }
}
