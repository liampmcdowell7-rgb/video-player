import MetadataOnline

/// R379 (audit docs/AUDIT_AGAINST_REFERENCE_PACK.md #29, owner 21 Nov 2026): the lines of Discover > Missing Episodes and
/// which of them take focus. HIG Focus and selection, tvOS: "you need to make sure that people can bring focus to every
/// element in your app"; WWDC21 "Direct and reflect focus in SwiftUI": "focus will only move if there is something
/// adjacent and focusable in the given direction". Before, no line could take focus, so the remote could not scroll down
/// a long list. Now every episode line is focusable (a plain focusable row, as About's text rows); the show's name and its
/// where-to-watch sentence stay the group's heading and are not focus stops. The wording is unchanged.
public struct MissingEpisodeLine: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var isFocusable: Bool
}

public enum MissingEpisodeLines {
    /// One line per missing episode, in the group's order: "S1, E2  Name", with "  (aired 2024-01-31)" when the date is
    /// known (the same text as before R379).
    public static func lines(_ group: MissingEpisodesGroup) -> [MissingEpisodeLine] {
        group.episodes.map { (episode: MissingEpisode) -> MissingEpisodeLine in
            MissingEpisodeLine(id: episode.id, text: text(episode), isFocusable: true)
        }
    }

    public static func text(_ episode: MissingEpisode) -> String {
        let base: String = "\(episode.code)  \(episode.name)"
        guard let date = episode.airDate else { return base }
        return "\(base)  (aired \(date))"
    }
}
