import Foundation

// The owner's review of the screenshot run on fd9731f (22 Nov 2026): "all of the icons are terribly spaced out and nothing
// looks like the Apple TV app". The numbers the views take, kept here so the Linux tests cover them and so each one names
// where it comes from. Points on a 1920 x 1080 screen.

/// R391 (PROVISIONAL): the gap between badges. Cause of the fault: every badge row was an `HStack` with NO spacing given,
/// and the system's default stack spacing on tvOS is wide (the run measured 60 to 72 pt between badges; Apple publishes no
/// value for it). Apple's media catalog sample gives its own small row an explicit value ("Show information-dense
/// lockups": `HStack(spacing: 4)` for the symbols of a card, `padding(12)` around it), so the badge rows now give one too.
public enum BadgeSpacing {
    /// Between two badges of one group (the owner's range: about 8 to 12 pt).
    public static let inGroup: Double = 8
    /// Between two groups (resolution, HDR, audio …; R373), and between the line's text and its first badge.
    public static let betweenGroups: Double = 12

    /// The extra leading space of a badge that starts a new group (the row's own spacing is `inGroup`).
    public static var groupExtra: Double { betweenGroups - inGroup }
}

/// R392 (PROVISIONAL): the widths and gaps of the product pages that no Apple page gives as a number for this place.
public enum ProductPageSpacing {
    /// The synopsis on the hero spans this many columns of the page (so half of it). HIG Layout, tvOS grids, two-column
    /// grid: "Unfocused content width 860 pt", "Horizontal spacing 40 pt". The sample's product page shows its description
    /// as one of three columns but gives no width for it.
    public static let synopsisColumns: Int = 2
    /// The spacing those columns are counted with (HIG Layout: 40 pt).
    public static let columnSpacing: Double = 40
    /// The whole synopsis in its cover: Apple's sample, "Provide product highlight pages":
    /// `Text(loremIpsum).frame(maxWidth: 600)` inside the `fullScreenCover`.
    public static let coverTextWidth: Double = 600
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
