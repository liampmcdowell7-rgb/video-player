import SwiftUI
import AppLogic

/// R350 (owner's device test of build 5, 21 Nov 2026, item D; PROVISIONAL): ONE metadata line of a movie or show page, as
/// the TV app's product page: the facts ("2021 · 1 h 52 min · ★ 7.4") then the format badges. R370: the badges are the
/// headline few (resolution, HDR, audio format), drawn (`FormatBadge`). Rule S1: the line is never wrapped or cut; when it
/// does not fit, the badges are dropped from the end (`ViewThatFits` tries the line with all badges, then one fewer, down
/// to the facts alone, which shrink to fit). Whether `ViewThatFits` uses its last child when none fits is not on Apple's
/// page: UNVERIFIED (the facts alone are the last child, and they shrink, so it should always fit).
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
            ForEach(shown, id: \.self) { (badge: FormatBadgeItem) in
                FormatBadge(item: badge)
            }
        }
    }
}

/// R370 (owner's decision of 21 Nov 2026): a row of badges on one line, for a shelf card and an episode row. Rule S1: the
/// badges are dropped from the end when the row is too narrow, never cut; with none left it draws nothing.
struct BadgeRow: View {
    let badges: [FormatBadgeItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: badges.count, through: 1, by: -1)), id: \.self) { (count: Int) in
                HStack {
                    ForEach(Array(badges.prefix(count)), id: \.self) { (badge: FormatBadgeItem) in
                        FormatBadge(item: badge)
                    }
                }
            }
            // The last child: nothing, when not even the first badge fits.
            EmptyView()
        }
        .accessibilityElement(children: .combine)
    }
}

/// R370: the full set of a file at the top of Information. Every badge is shown: the row wraps onto as many lines as it
/// needs (`BadgeFlow`), so none is dropped or cut.
struct BadgeFlowRow: View {
    let badges: [FormatBadgeItem]
    // The gap between badges scales with the text size.
    @ScaledMetric(relativeTo: .caption) private var gap: CGFloat = 12

    var body: some View {
        BadgeFlow(gap: gap) {
            ForEach(badges, id: \.self) { (badge: FormatBadgeItem) in
                FormatBadge(item: badge)
            }
        }
        // Each badge stays its own element (the UI check `badgesNotCutCheck` reads their frames).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("badges.all")
    }
}

/// R370: a SwiftUI `Layout` that places its children left to right at their natural size and starts a new line when the
/// next one would pass the proposed width. Each child is measured with `.unspecified` (its ideal size, so a badge is never
/// squeezed).
struct BadgeFlow: Layout {
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + gap * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + gap
            }
            y += row.height + gap
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + gap + size.width
            if !current.indices.isEmpty && needed > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + gap + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
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

/// R371 (owner's request of 21 Nov 2026): the content rating as an outlined text badge ("PG-13", "TV-MA", "15"), the
/// rating spelled out, no rating board's logo. A thin primary outline, the text in primary: told apart from the format
/// badges, which never use a plain primary outline with regular text. Never cut (`fixedSize`).
struct RatingBadge: View {
    let rating: String
    @ScaledMetric(relativeTo: .caption) private var inset: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var corner: CGFloat = 4
    @ScaledMetric(relativeTo: .caption) private var line: CGFloat = 1

    var body: some View {
        Text(rating)
            .font(.caption)
            .fixedSize()
            .padding(.horizontal, inset)
            .overlay {
                RoundedRectangle(cornerRadius: corner)
                    .stroke(.primary, lineWidth: line)
            }
            .accessibilityLabel("Rated \(rating)")
            .accessibilityIdentifier("badge.rating")
    }
}

/// R370 (owner's decision of 21 Nov 2026; replaces R350's one outlined style): an ORIGINAL badge drawn by the app, a small
/// rounded badge with the format's name spelled out in the system font. No logo images, logo shapes or third-party lettering
/// (docs/NAMES.md: technology names as text only). One treatment per group, so the groups read apart at a glance; every
/// treatment uses system styles only (primary, the readable secondary of R240, the quaternary fill, the background style),
/// so it follows light and dark:
/// - resolution ("4K", "1080p", "720p", "SD"): filled in the readable secondary, the text in the background style, bold;
/// - HDR ("Dolby Vision", "HDR10", "HDR10+", "HLG"): outlined in primary, semibold;
/// - audio format and channels ("Dolby Atmos", "DTS:X", "7.1", "Stereo"): outlined in the readable secondary;
/// - video codec ("HEVC", "H.264", "AV1"): the system quaternary fill, no outline;
/// - container ("MKV", "MP4", "M2TS"): a dashed outline in the readable secondary.
/// No SF Symbol is used: none could be checked on Apple's pages for these formats. Never cut: the badge takes its natural
/// width (`fixedSize`), and its rows drop or wrap badges instead. The corner, the inset and the line scale with the text size.
struct FormatBadge: View {
    let item: FormatBadgeItem
    @ScaledMetric(relativeTo: .caption) private var inset: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var corner: CGFloat = 6
    @ScaledMetric(relativeTo: .caption) private var line: CGFloat = 1.5
    @ScaledMetric(relativeTo: .caption) private var dash: CGFloat = 4

    var body: some View {
        Text(item.text)
            .font(.caption)
            .fontWeight(weight)
            .foregroundStyle(textStyle)
            .fixedSize()
            .padding(.horizontal, inset)
            .background { fill }
            .overlay { outline }
            .accessibilityLabel(item.spokenLabel)
            .accessibilityIdentifier("badge.\(item.group.rawValue)")
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: corner) }

    private var weight: Font.Weight {
        switch item.group {
        case .resolution: return .bold
        case .hdr: return .semibold
        case .audio, .channels, .videoCodec, .container: return .regular
        }
    }

    private var textStyle: AnyShapeStyle {
        switch item.group {
        case .resolution: return AnyShapeStyle(.background)
        case .hdr, .videoCodec: return AnyShapeStyle(.primary)
        case .audio, .channels, .container: return ReadableSecondary.style
        }
    }

    @ViewBuilder private var fill: some View {
        switch item.group {
        case .resolution: shape.fill(ReadableSecondary.style)
        case .videoCodec: shape.fill(.quaternary)
        case .hdr, .audio, .channels, .container: EmptyView()
        }
    }

    @ViewBuilder private var outline: some View {
        switch item.group {
        case .hdr: shape.stroke(.primary, lineWidth: line)
        case .audio, .channels: shape.stroke(ReadableSecondary.style, lineWidth: line)
        case .container: shape.stroke(ReadableSecondary.style, style: StrokeStyle(lineWidth: line, dash: [dash, dash]))
        case .resolution, .videoCodec: EmptyView()
        }
    }
}

/// R350 (PROVISIONAL, alternatives in OPEN_QUESTIONS): the hero area of a movie or show page fills this share of the first
/// screen, its content at the bottom, so the artwork shows above the title as on the TV app's product page and the top of
/// the next section shows below it. A share of the page's own height, not a point size; Apple publishes no number.
enum ProductPageLayout {
    static let heroFraction: CGFloat = 0.85
}

extension View {
    /// R350: the hero area of a product page: at least `ProductPageLayout.heroFraction` of the page's height, content at the
    /// bottom left. A MINIMUM height, so at Larger Text the hero grows instead of being cut (rule L7).
    func productHero(pageHeight: CGFloat) -> some View {
        frame(maxWidth: .infinity, minHeight: pageHeight * ProductPageLayout.heroFraction, alignment: .bottomLeading)
    }
}
