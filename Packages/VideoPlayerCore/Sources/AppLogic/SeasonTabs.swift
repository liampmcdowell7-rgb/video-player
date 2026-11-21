import Foundation

/// R339 (owner decision of 21 Nov 2026, docs/HIG_AUDIT.md T10): the show page's seasons are a row of tabs above ONE episode
/// list, as Apple's TV app does, in place of one shelf per season (R189). The tabs are the system segmented picker. HIG
/// Segmented controls, tvOS: "Segments become selected when focus moves to them, not when people click them", and "Aim for no
/// more than about five to seven segments in a wide interface"; above seven seasons the same choice is a system menu picker.
public enum SeasonTabs {
    public enum Style: Equatable, Sendable {
        /// One season: no control, its name as the heading.
        case heading
        /// Two to seven seasons: the system segmented picker.
        case segmented
        /// More than seven: the system menu picker.
        case menu
    }

    public static let mostSegments = 7

    public static func style(seasonCount: Int) -> Style {
        if seasonCount <= 1 { return .heading }
        return seasonCount <= mostSegments ? .segmented : .menu
    }

    /// The season shown: the one chosen, if it still exists; else the season of the episode Play starts; else the first.
    public static func shown(_ seasons: [SeasonSection], chosen: Int?, resumeEpisodeID: Int64?) -> SeasonSection? {
        if let chosen, let season = seasons.first(where: { $0.season == chosen }) { return season }
        if let resumeEpisodeID, let season = seasons.first(where: { $0.episodes.contains { $0.id == resumeEpisodeID } }) { return season }
        return seasons.first
    }
}
