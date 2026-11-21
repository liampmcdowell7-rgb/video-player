import Foundation

/// R350 (owner's device test of build 5, 21 Nov 2026, item D; PROVISIONAL): the movie and show pages follow the product
/// pages of Apple's TV app (docs/DESIGN_SYSTEM.md "Reference screens"): full-bleed artwork behind everything, the title
/// logo or name, ONE metadata line (year, runtime, rating) followed by format badges, the description, Play (or Resume) and
/// More; for a show the season tabs and episodes; then Cast & Crew; then "Information" at the bottom with every technical
/// row of the file, none collapsed, most important first (`MediaInfo.rows`).
public enum ProductPage {
    /// The section names, as the TV app names them.
    public static let castHeading = "Cast & Crew"
    public static let informationHeading = "Information"

    /// The format badges of a title, in the owner's order: resolution, HDR format, Dolby Atmos, then the channel layout of
    /// the best audio ("5.1", "7.1"). `cardBadges` are the card's (`CardBuilder.badges`: 4K, the HDR format, Dolby Atmos);
    /// stereo and mono get no badge (nothing special to show, as the TV app shows none).
    public static func formatBadges(cardBadges: [String], maxChannels: Int?) -> [String] {
        var badges: [String] = cardBadges
        if let layout = channelLayout(maxChannels) { badges.append(layout) }
        return badges
    }

    /// The show page's metadata line: the number of seasons ("1 Season", "3 Seasons"); the library index holds no year,
    /// runtime or rating for a show. Empty for none.
    public static func showFacts(seasonCount: Int) -> String {
        if seasonCount <= 0 { return "" }
        return seasonCount == 1 ? "1 Season" : "\(seasonCount) Seasons"
    }

    /// "7.1" for eight channels or more, "5.1" for six or seven, nil below.
    public static func channelLayout(_ channels: Int?) -> String? {
        guard let channels else { return nil }
        if channels >= 8 { return "7.1" }
        if channels >= 6 { return "5.1" }
        return nil
    }
}
