import Foundation
import LibraryIndex

/// One entry of the alphabet jump list: the letter and the first item filed under it.
public struct JumpTarget: Equatable, Sendable, Identifiable {
    public var letter: String
    /// The id of the first title (in list order) filed under this letter.
    public var firstID: Int64
    public var count: Int
    public var id: String { letter }
    public init(letter: String, firstID: Int64, count: Int) { self.letter = letter; self.firstID = firstID; self.count = count }
}

/// The alphabet jump list for lists the app sorts itself (Shows). Movies use the index's own `alphabetIndex`
/// (`ItemGridViewModel.jump(to:)`); both file titles under the same letters (`TitleLetter`). Only letters that have a title
/// appear, in the order "#", A to Z, so the menu never offers a jump that goes nowhere.
public enum AlphabetJump {
    /// `titles` must already be in list order (`TitleLetter.sortKey` order, which `EpisodeGroupingCatalog` produces).
    public static func targets(forTitles titles: [(id: Int64, title: String)]) -> [JumpTarget] {
        var order: [String] = []
        var first: [String: Int64] = [:]
        var count: [String: Int] = [:]
        for t in titles {
            let letter = TitleLetter.letter(for: t.title)
            if first[letter] == nil { first[letter] = t.id; order.append(letter) }
            count[letter, default: 0] += 1
        }
        let rank = Dictionary(uniqueKeysWithValues: TitleLetter.all.enumerated().map { ($1, $0) })
        return order.sorted { (rank[$0] ?? 0) < (rank[$1] ?? 0) }.map { JumpTarget(letter: $0, firstID: first[$0] ?? 0, count: count[$0] ?? 0) }
    }

    public static func targets(for series: [SeriesSummary]) -> [JumpTarget] {
        targets(forTitles: series.map { ($0.id, $0.title) })
    }

    /// Jump-menu label: "A (12)". The count helps the person judge how far a letter is.
    public static func label(_ target: JumpTarget) -> String { "\(target.letter) (\(target.count))" }
}
