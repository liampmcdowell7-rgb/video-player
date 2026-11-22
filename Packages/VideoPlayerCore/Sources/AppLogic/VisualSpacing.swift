import Foundation

// The owner's review of the screenshot run on fd9731f (22 Nov 2026): "all of the icons are terribly spaced out and nothing
// looks like the Apple TV app". The numbers the views take, kept here so the Linux tests cover them and so each one names
// where it comes from. Points on a 1920 x 1080 screen.

/// R391 (PROVISIONAL): the gap between badges. Cause of the fault: every badge row was an `HStack` with NO spacing given,
/// and the system's default stack spacing on tvOS is wide (the run measured 60 to 72 pt between badges; Apple publishes no
/// value for it). Apple's media catalog sample gives its own small row an explicit value ("Show information-dense
/// lockups": `HStack(spacing: 4)` for the symbols of a card, `padding(12)` around it), so the badge rows now give one too.
/// R396: the values are now the ones measured on Apple's own pictures (docs/AUDIT_VISUAL_TVAPP.md, SF1): badges 10 to
/// 15 pt apart on the TV app's product pages (B1: 10 to 14 pt; A4: 12 to 15 pt), the rating about 10 pt after the text.
public enum BadgeSpacing {
    /// Between two badges of one group.
    public static let inGroup: Double = 12
    /// Between two groups (resolution, HDR, audio …; R373).
    public static let betweenGroups: Double = 15
    /// Between a line's text and what follows it (the rating badge, the first badge, the watched mark).
    public static let afterText: Double = 10

    /// The extra leading space of a badge that starts a new group (the row's own spacing is `inGroup`).
    public static var groupExtra: Double { betweenGroups - inGroup }
}

/// R396 (docs/AUDIT_VISUAL_TVAPP.md, SF1, SF2, SF3, SF7, H6): the ONE shared set of row values, each measured on an Apple
/// picture named in the audit's section 1. No screen keeps a number of its own for these.
public enum RowSpacing {
    /// A list row's symbol to its title. Apple's pictures: about 25 pt in the library's category list (A3) and about
    /// 29 pt in the sidebar (A2); 27 is between the two.
    public static let iconToLabel: Double = 27
    /// Between the buttons of an action row. A1 (Home) and B1 (movie page): about 22 pt; A4 (show page): about 27 pt.
    public static let betweenActions: Double = 22
    /// The widest a synopsis or other running text is drawn. B1: about 650 pt; A4: about 658 pt.
    public static let textColumn: Double = 650
    /// From the bottom of Home's featured buttons to the first shelf's header. A1: about 105 pt (802 to about 910).
    public static let featuredToShelf: Double = 105
    /// The gap the page's own stack already leaves there (the run on fd9731f measured 20 to 23 pt with nothing added),
    /// so the padding added under the buttons is `featuredToShelf` less this.
    public static let stackGap: Double = 20
    /// Continue Watching and Next Up: 16:9 cards this many across. A1: about 318 pt wide, five across (five columns at
    /// 40 pt spacing on a 1760 pt page are 320 pt).
    public static let landscapeShelfColumns: Int = 5
    /// The "Starring" block at the trailing edge of a product page's first screen. B1: x about 1430 to the margin.
    public static let creditsWidth: Double = 330
}

/// R392 (PROVISIONAL): the widths and gaps of the product pages that no Apple page gives as a number for this place.
public enum ProductPageSpacing {
    // R396: the synopsis width on the page and in its cover is `RowSpacing.textColumn` (650 pt, Apple's pictures). The
    // half-page width (860 pt) and the sample's 600 pt of R392 are its alternatives now.
    /// The cast circles: this many to a page width at 40 pt spacing. HIG Layout, eight-column grid: "Unfocused content
    /// width 184 pt". The sample sizes its lockups the same way (`containerRelativeFrame(.horizontal, count:spacing:)`).
    public static let castColumns: Int = 8
    /// Under the count line of Movies and Shows, above the first row of cards. HIG Layout: "Minimum vertical spacing
    /// 100 pt" between two rows, which holds the growth of both focused cards; one card under a line of text needs half.
    public static let aboveFirstGridRow: Double = 50
    /// Between the heading, the badge row and the table of Information (the system's default stack spacing was used).
    public static let informationRows: Double = 20
}

extension ProductPage {
    /// Item 5 (b): the time left is the last fact of the ONE metadata line ("2021 · 1 h 52 min · 29 min left"), no longer
    /// a line of its own between the synopsis and the buttons. Either part may be empty or nil.
    public static func factsLine(_ facts: String, timeLeft: String?) -> String {
        let left: String = (timeLeft ?? "").trimmingCharacters(in: .whitespaces)
        if left.isEmpty { return facts }
        if facts.isEmpty { return left }
        return facts + " · " + left
    }
}

extension ProductPage {
    /// R396 (audit M7): the "Starring" line of a product page's first screen: the first names of the cast, in billing
    /// order, as Apple's movie page lists them ("Starring Tom Cruise, Hayley Atwell, Ving Rhames", picture B1). Nil
    /// with no names. The library holds no director, so no "Director" line is drawn (never invented).
    public static func starring(_ names: [String], limit: Int = 3) -> String? {
        let shown: [String] = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(max(limit, 0)).map { $0 }
        return shown.isEmpty ? nil : shown.joined(separator: ", ")
    }

    public static let starringLabel = "Starring"

    /// R396 (audit E1, E2): the small line above an episode's title: the show's name, then the episode's code
    /// ("Sample Show 1 · S1, E3"). Either part may be missing; nil with neither.
    public static func episodeOverline(show: String?, code: String?) -> String? {
        let parts: [String] = [show, code].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension TitleLogoRules {
    /// Item 6 (b): the box of a logo's visible pixels (alpha above `threshold`), so the logo can be cut to it and its
    /// visible left edge lines up with the text under it. A logo file often has empty margins: the run showed the logo
    /// starting at 150 pt with everything else at 80 pt. Nil when the buffer is wrong or nothing is visible.
    /// `rgba` is 4 bytes a pixel, row by row from the top.
    public static func inkBounds(rgba: [UInt8], width: Int, height: Int, threshold: UInt8 = 8)
        -> (x: Int, y: Int, width: Int, height: Int)? {
        guard width > 0, height > 0, rgba.count == width * height * 4 else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where rgba[row + x * 4 + 3] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }
}
