import SwiftUI
import AppLogic

/// R350 (owner's device test of build 5, 21 Nov 2026, item D; PROVISIONAL): ONE metadata line of a movie or show page, as
/// the TV app's product page: the facts ("2021 · 1 h 52 min · ★ 7.4"), the rating (R371), then the format badges, the
/// headline few (resolution, HDR, audio format; R370). Rule S1: the line is never wrapped or cut; when it does not fit, the
/// badges are dropped from the end (`ViewThatFits` tries the line with all badges, then one fewer, down to the facts alone,
/// which shrink to fit). Whether `ViewThatFits` uses its last child when none fits is not on Apple's page: UNVERIFIED (the
/// facts alone are the last child, and they shrink, so it should always fit).
struct ProductMetadataLine: View {
    let facts: String
    /// R371: the content rating, after the facts and before the format badges; never dropped before them.
    var rating: String? = nil
    let badges: [FormatBadgeItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: badges.count, through: 0, by: -1)), id: \.self) { (count: Int) in
                line(Array(badges.prefix(count)))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("product.metadataLine")
    }

    private func line(_ shown: [FormatBadgeItem]) -> some View {
        HStack {
            if !facts.isEmpty {
                FittingText(facts, style: .callout)
                    .foregroundStyle(ReadableSecondary.style)
            }
            if let rating {
                RatingBadge(rating: rating)
            }
            BadgeGroups(badges: shown)
        }
    }
}

/// R373 (owner's review of R370, 21 Nov 2026, option a): the badges side by side, the groups told apart only by their
/// order (resolution, HDR, audio and channels, video codec, container; `FormatBadges.all`) and by a wider gap where one
/// group ends and the next begins. Inside a group the system's default spacing of an `HStack`; between groups that
/// spacing plus `groupGap`, which scales with the text size.
struct BadgeGroups: View {
    let badges: [FormatBadgeItem]
    @ScaledMetric(relativeTo: .caption) private var groupGap: CGFloat = 12

    var body: some View {
        HStack {
            ForEach(Array(badges.enumerated()), id: \.element) { (index: Int, badge: FormatBadgeItem) in
                FormatBadge(item: badge)
                    .padding(.leading, index > 0 && Self.startsGroup(badge, after: badges[index - 1]) ? groupGap : 0)
            }
        }
    }

    /// Audio format and channels are one group (both say what the sound is).
    static func startsGroup(_ badge: FormatBadgeItem, after previous: FormatBadgeItem) -> Bool {
        func family(_ g: FormatBadgeGroup) -> FormatBadgeGroup { g == .channels ? .audio : g }
        return family(badge.group) != family(previous.group)
    }
}

/// R370 (owner's decision of 21 Nov 2026): a row of badges on ONE line, for a shelf card, an episode row and the top of
/// Information. Rule S1 (R373: never cut or wrapped): the badges are dropped from the end when the row is too narrow; with
/// none left it draws nothing. In Information every badge is also a row, so a dropped badge is never lost. `separate`
/// keeps each badge its own accessibility element (Information, where the UI check `badgesNotCutCheck` reads the frames);
/// otherwise the row is read as one.
struct BadgeRow: View {
    let badges: [FormatBadgeItem]
    var separate: Bool = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: badges.count, through: 1, by: -1)), id: \.self) { (count: Int) in
                BadgeGroups(badges: Array(badges.prefix(count)))
            }
            // The last child: nothing, when not even the first badge fits.
            EmptyView()
        }
        .accessibilityElement(children: separate ? .contain : .combine)
    }
}

/// R372 (owner's request of 21 Nov 2026): Wikidata's content advice ("Violence · Strong Language") as ONE short secondary
/// line right under the metadata line that holds the rating badge. Rule S1: the descriptors are dropped from the end when
/// the line is too long (`FittingLine`); Information lists them all ("Content Advice"). Nothing when there are none.
struct ContentAdviceLine: View {
    let descriptors: [String]

    var body: some View {
        if !descriptors.isEmpty {
            FittingLine(line: ShortLine(ordered: descriptors), style: .caption2)
                .foregroundStyle(ReadableSecondary.style)
                .accessibilityLabel("Content advice: " + descriptors.joined(separator: ", "))
        }
    }
}

/// R371 (owner's request of 21 Nov 2026): the content rating as a badge, the rating spelled out ("PG-13", "TV-MA", "15"),
/// no rating board's logo. R373: the same one badge style as the format badges (`BadgeOutline`).
struct RatingBadge: View {
    let rating: String

    var body: some View {
        BadgeOutline(text: rating)
            .accessibilityLabel("Rated \(rating)")
            .accessibilityIdentifier("badge.rating")
    }
}

/// R373 (owner's review of R370, 21 Nov 2026, option a; replaces R370's six drawn treatments): a format badge in ONE
/// consistent style, R350's: the format's name in the system font (`.caption`) in a rounded outline in the readable
/// secondary style (R240). Original, text only, never a logo (docs/NAMES.md). The group is not drawn; it is told by the
/// badge's place in the line (`BadgeGroups`) and spoken by VoiceOver ("4K, resolution").
struct FormatBadge: View {
    let item: FormatBadgeItem

    var body: some View {
        BadgeOutline(text: item.text)
            .accessibilityLabel(item.spokenLabel)
            .accessibilityIdentifier("badge.\(item.group.rawValue)")
    }
}

/// R350, R373: the one badge drawing. The side inset and the corner scale with the text size (`@ScaledMetric`); never cut:
/// the badge takes its natural width (`fixedSize`), and its line drops badges instead.
struct BadgeOutline: View {
    let text: String
    @ScaledMetric(relativeTo: .caption) private var inset: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var corner: CGFloat = 6

    var body: some View {
        Text(text)
            .font(.caption)
            .fixedSize()
            .padding(.horizontal, inset)
            .overlay {
                RoundedRectangle(cornerRadius: corner)
                    .stroke(ReadableSecondary.style)
            }
    }
}

/// R350 (PROVISIONAL, alternatives in OPEN_QUESTIONS): the hero area of a movie or show page fills this share of the first
/// screen, its content at the bottom, so the artwork shows above the title as on the TV app's product page and the top of
/// the next section shows below it. A share of the page's own height, not a point size.
/// R377 (audit docs/AUDIT_INVENTED_UI.md #3, owner 21 Nov 2026, rule R312): 0.8, the value of Apple's media catalog sample
/// (`length * 0.8`). Was 0.85 (R350).
enum ProductPageLayout {
    static let heroFraction: CGFloat = 0.8
}

extension View {
    /// R350: the hero area of a product page: at least `ProductPageLayout.heroFraction` of the page's height, content at the
    /// bottom left. A MINIMUM height, so at Larger Text the hero grows instead of being cut (rule L7).
    func productHero(pageHeight: CGFloat) -> some View {
        frame(maxWidth: .infinity, minHeight: pageHeight * ProductPageLayout.heroFraction, alignment: .bottomLeading)
    }
}
