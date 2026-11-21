import Foundation
import LibraryIndex

/// R350 (owner's device test of build 5, 21 Nov 2026, item D; PROVISIONAL): the movie and show pages follow the product
/// pages of Apple's TV app (docs/DESIGN_SYSTEM.md "Reference screens"): full-bleed artwork behind everything, the title
/// logo or name, ONE metadata line (year, runtime, rating) followed by format badges, the description, Play (or Resume) and
/// More; for a show the season tabs and episodes; then Cast & Crew; then "Information" at the bottom with every technical
/// row of the file, none collapsed, most important first (`MediaInfo.rows`).
public enum ProductPage {
    /// The section names, as the TV app names them.
    public static let castHeading = "Cast & Crew"
    public static let informationHeading = "Information"

    /// R370 (owner's decision of 21 Nov 2026): the format badges are drawn badges in groups (`FormatBadges`). This page
    /// shows the headline few (resolution, HDR, audio format) on its metadata line and the full set in Information.
    /// R350's text badges and R369's six-badge line are replaced; their alternatives stay in OPEN_QUESTIONS.

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
