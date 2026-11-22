import Foundation
import LibraryIndex
import PlaybackLogic

/// R313 (owner's request of 21 Nov 2026; form decided by the owner's standing rule R312, Apple's TV app): wherever the player
/// names an episode or its show, it also says which episode, in the TV app's form "S1, E3" ("S1, E3–E4" for a file that holds
/// two episodes). Used by the transport bar's title and subtitle (the item's external metadata, which the system also shows in
/// the Info tab and publishes as the Now Playing entry), the Episodes tab, the Up Next card and the playback error. A number
/// that is not known is left out ("E3", "S2"); never "S?". Films are unchanged.
public enum PlayerEpisodeText {
    /// "S1, E3", "S1, E3–E4", "E3" (season unknown), "S2" (episode unknown), nil when neither is known.
    public static func code(season: Int?, episode: Int?, episodeEnd: Int? = nil) -> String? {
        var parts: [String] = []
        if let season { parts.append("S\(season)") }
        if let episode {
            if let end = episodeEnd, end > episode { parts.append("E\(episode)–E\(end)") } else { parts.append("E\(episode)") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// R394 (PROVISIONAL): the separator inside the line the SYSTEM player draws above the title. The run on fd9731f showed
    /// that line with "•" and "·" mixed. The app never writes "•" in the player, so the system adds it between the parts it
    /// joins (UNVERIFIED which parts; not on Apple's pages). The app's part of that line now uses the same sign. Every
    /// text the app draws itself keeps "·".
    public static let systemSeparator = " • "

    /// The transport bar's two lines for an episode. R396 (docs/AUDIT_VISUAL_TVAPP.md PL1, Apple's picture of the TV
    /// app's player controls, A4): the SHOW's name is the large line and "S1, E1 • Episode name" the small line above it,
    /// with one separator. Before (R313, R394) the episode's name was the large line and "Show • S1, E3" the small one.
    /// Without a show the episode's name is the large line and the code the small one. Whatever is not known is left
    /// out; with nothing known at all the title is "Untitled".
    public static func episodeLines(name: String?, show: String?, season: Int?, episode: Int?,
                                    episodeEnd: Int? = nil) -> (title: String, subtitle: String?) {
        let name = clean(name), show = clean(show)
        let code = code(season: season, episode: episode, episodeEnd: episodeEnd)
        if let show {
            let subtitle = [code, name].compactMap { $0 }.joined(separator: systemSeparator)
            return (show, subtitle.isEmpty ? nil : subtitle)
        }
        if let name { return (name, code) }
        return (code ?? "Untitled", nil)
    }

    /// The two lines for a library item: an episode by the rules above (a name that is only the code again or the show's
    /// name counts as no name), a film unchanged (its title, and the second line the caller already had).
    public static func lines(for item: LibraryItem, filmTitle: String, filmSubtitle: String?) -> (title: String, subtitle: String?) {
        guard item.kind == .episode else { return (filmTitle, filmSubtitle) }
        return episodeLines(name: CardBuilder.episodeTitleIsReal(item) ? item.title : nil, show: item.seriesTitle,
                            season: item.season, episode: item.episode, episodeEnd: item.episodeEnd)
    }

    /// The Up Next card's line under "Up Next": "Show · S1, E4 · Episode name", leaving out what is not known.
    public static func upNextLine(show: String?, season: Int?, episode: Int?, episodeEnd: Int? = nil, name: String?) -> String {
        [clean(show), code(season: season, episode: episode, episodeEnd: episodeEnd), clean(name)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The Up Next card's line for a proposal; the placeholder name "Episode 4" counts as no name (the code says it).
    public static func upNextLine(_ proposal: UpNextProposal, show: String?) -> String {
        let ref = proposal.episode
        let name: String? = proposal.episodeTitle == "Episode \(ref.episode)" ? nil : proposal.episodeTitle
        return upNextLine(show: show, season: ref.season, episode: ref.episode, episodeEnd: ref.lastEpisode, name: name)
    }

    /// The line the playback error starts with for an episode ("Show · S1, E3 · Name"); nil for a film.
    public static func errorLine(for item: LibraryItem) -> String? {
        guard item.kind == .episode else { return nil }
        let line = upNextLine(show: item.seriesTitle, season: item.season, episode: item.episode, episodeEnd: item.episodeEnd,
                              name: CardBuilder.episodeTitleIsReal(item) ? item.title : nil)
        return line.isEmpty ? nil : line
    }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
