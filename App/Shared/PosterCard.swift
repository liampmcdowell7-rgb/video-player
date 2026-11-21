import SwiftUI
import AppLogic

/// One title in a row or grid: ONE lockup, the artwork and its text inside one system `.borderless` button (R335; Liquid
/// Glass on the artwork on focus, Apple: "applies a Liquid Glass effect to the first image of the button's content").
///
/// Every card has the same parts in the same places (screenshot review item 4: posters in one grid row sat at different
/// heights because cards with fewer text lines were centred): the title, the second line and the badge line are always laid
/// out, empty ones hidden (the progress is inside the artwork, #15 D4), so equal cards are exactly equal in size and their posters line up. Short texts
/// follow rule S1 (`FittingLine`): one line, scaled to the readable minimum, never cut with "…".
///
/// #34 5a (OPEN_QUESTIONS R229, PROVISIONAL): the Continue Watching card (`wide`) puts its title and second lines INSIDE the
/// button, Apple's tvOS content lockup ("Creating a tvOS media catalog app in SwiftUI": `.borderless`, image and title in the
/// label, the title moves out of the way as the image scales up), exactly as the episode card (`EpisodeCard`,
/// SeasonsList.swift, #30), so the whole lockup is the focused item. R335: portrait cards too.
/// #36 group 1 d: the earlier claim that the system then SCROLLS a long title (the marquee) is withdrawn: the third run of
/// 20 Nov showed 50 and 50-later identical with the title cut mid-word.
///
/// #36 7 (OPEN_QUESTIONS R259, PROVISIONAL): Apple's sample: "the button style locates the first `Image` within the button's
/// label and attaches a highlight hover effect to it"; for a custom view, "you can manually attach it" with
/// `hoverEffect(.highlight)`, so the highlight is on the artwork. Whether the system lifts the custom artwork is unverified.
/// #36 group 4 (OPEN_QUESTIONS R264, PROVISIONAL): the title is a `CardCaption` (shrinks to the 23 pt floor, then wraps,
/// never cut) and every card of a row reserves the same caption height (`equalCaptionRow`, CardRow); the artwork's height is
/// fixed (`fixedSize`), so a caption can never take height from it.
struct PosterCard: View {
    let card: ItemCard
    /// #15 4.1: a 16:9 card for Continue Watching (OPEN_QUESTIONS R185); portrait everywhere else.
    var wide = false

    var body: some View {
        VStack(alignment: .leading) {
            if wide {
                NavigationLink(value: Route.item(card.id)) {
                    VStack(alignment: .leading) {
                        artwork
                            // #36 group 4: the artwork keeps its 16:9 height whatever the caption needs (R264).
                            .fixedSize(horizontal: false, vertical: true)
                            // design-lint:allow #36 7 (R259): Apple's tvOS media catalog sample attaches the borderless lockup's highlight by hand to a custom artwork view; the system effect, not our own
                            .hoverEffect(.highlight)
                        // #36 7: the title and the second lines inside the button (R259); #36 group 4: the title shrinks
                        // to the floor, then wraps, never cut (CardCaption, R264).
                        VStack(alignment: .leading) {
                            CardCaption(text: card.title)
                            secondLines
                        }
                        .padding(.horizontal)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(card.title)
                .accessibilityValue(card.subtitle ?? "")
                .cardContextMenu(card)
            } else {
                // R335 (PROVISIONAL, docs/HIG_AUDIT.md T1, T2): the portrait card is the same lockup as the wide one, as
                // Apple's sample builds a poster ("Creating a tvOS media catalog app in SwiftUI": `.borderless`, "Provide a
                // separate `Image` and `Text` view in the button's label closure"; the title "automatically move[s] out of
                // the way of the button's image as it scales up on focus"). Before: a `.card` button around the artwork and
                // the caption outside it.
                NavigationLink(value: Route.item(card.id)) {
                    VStack(alignment: .leading) {
                        artwork
                            // design-lint:allow R335: Apple's tvOS media catalog sample attaches the borderless lockup's highlight by hand to a custom artwork view; the system effect, not our own
                            .hoverEffect(.highlight)
                        // #17 C: the text keeps a side padding, so it never touches the card's edge (Larger Text screenshot
                        // 80: titles ended 2-3 px from it). The system's default padding; FittingLine measures the width
                        // inside it.
                        VStack(alignment: .leading) {
                            FittingText(card.title, style: .caption)
                            secondLines
                        }
                        .padding(.horizontal)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(card.title)
                .accessibilityValue(card.subtitle ?? "")
                .cardContextMenu(card)
            }
        }
    }

    // #15 D4: the progress sits inside the artwork's bottom edge, so it moves and lifts with the focused card
    // and every card keeps the same height. Fixed in code, verify in next screenshots.
    private var artwork: some View {
        ArtworkView(key: card.artworkKey, symbol: card.kind == .movie ? "film" : "tv", wide: wide)
            .overlay(alignment: .bottom) {
                if let progress = card.progress {
                    ProgressView(value: progress)
                        .padding()
                }
            }
    }

    @ViewBuilder private var secondLines: some View {
        FittingLine(line: card.subtitleLine, style: .caption2)
            .foregroundStyle(.secondary)
        FittingLine(line: card.badgeLine, style: .caption2)
            .foregroundStyle(.secondary)
    }
}

/// #36 group 4 (OPEN_QUESTIONS R264, PROVISIONAL; replaces the one-line marquee caption of R259): the title of a lockup
/// card (Continue Watching, episode) is never cut. It is ONE line in the Caption style while it fits when shrunk no lower
/// than the 23 pt floor (`minimumScaleFactor`, rule S1, as `FittingText`); a longer title is drawn at the floor size
/// (Caption 2, 23 pt) and wraps onto a second line, and onto more if it needs them, so no word is ever clipped. Apple,
/// `minimumScaleFactor(_:)`: "Sets the minimum amount that text in this view scales down to fit in the available space."
/// The third run of 20 Nov showed why the marquee had to go: 50 and 56 were cut mid-word ("… that i") and did not move.
/// Height: the caption reports its own height (`CaptionHeightKey`) and every card of the row takes the tallest one
/// (`reservedCaptionHeight`, set by `equalCaptionRow`), so the cards of a row stay exactly equal; the hidden one-line
/// "spacer" text of R259 is gone. The width is the column's (`maxWidth: .infinity`) and never depends on the height, so no
/// measure feeds back into the next layout (#31, R231). The natural one-line width is measured off screen as in
/// `FittingText` (hidden, never drawn or spoken).
struct CardCaption: View {
    let text: String
    @State private var natural: Double = 0
    @State private var available: Double = 0
    @State private var ownHeight: CGFloat = 0
    @Environment(\.reservedCaptionHeight) private var reserved: CGFloat

    var body: some View {
        let readable: Double = ShortLine.minimumScale(forPointSize: TVTextStyle.caption.pointSize)
        let wraps: Bool = FittingText.isTooLong(natural: natural, available: available, readable: readable)
        caption(wraps: wraps, readable: readable)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { (height: CGFloat) in
                if abs(height - ownHeight) >= 0.5 { ownHeight = height }
            }
            .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { (width: Double) in
                if abs(width - available) >= 0.5 { available = width }
            }
            .preference(key: CaptionHeightKey.self, value: ownHeight)
            .frame(minHeight: reserved, alignment: .topLeading)
            .background(alignment: .leading) {
                // The natural one-line width in the Caption style, measured off screen (hidden: not drawn, not spoken).
                Text(text)
                    .font(TVTextStyle.caption.font)
                    .lineLimit(1) // design-lint:allow hidden measurement of the natural width, never drawn or spoken (rule S1 is applied to the visible text)
                    .fixedSize()
                    .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { natural = $0 }
                    .hidden()
            }
    }

    @ViewBuilder
    private func caption(wraps: Bool, readable: Double) -> some View {
        if wraps {
            // At the floor (Caption 2 is 23 pt on tvOS, Apple's minimum), as many lines as the title needs.
            Text(text)
                .font(TVTextStyle.caption2.font)
        } else {
            Text(text)
                .font(TVTextStyle.caption.font)
                .lineLimit(1)
                // design-lint:allow rule S1 (OPEN_QUESTIONS R165, R229, R264): the caption shrinks to fit, never below the readable floor
                .minimumScaleFactor(readable)
        }
    }
}

/// #36 group 4 (R264): the tallest caption height reported in a row of lockup cards.
struct CaptionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension EnvironmentValues {
    /// #36 group 4 (R264): the caption height every card of the row reserves (0 outside an `equalCaptionRow`).
    @Entry var reservedCaptionHeight: CGFloat = 0
}

/// #36 group 4 (R264): a row of lockup cards whose captions all take the tallest caption's height. Only the cards the lazy
/// row has laid out report; a taller caption scrolled into view raises the row once (unverified on a device).
struct EqualCaptionRow: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.reservedCaptionHeight, height)
            .onPreferenceChange(CaptionHeightKey.self) { (tallest: CGFloat) in
                if abs(tallest - height) >= 0.5 { height = tallest }
            }
    }
}

extension View {
    /// #36 group 4 (R264): see `EqualCaptionRow`.
    func equalCaptionRow() -> some View {
        modifier(EqualCaptionRow())
    }
}
