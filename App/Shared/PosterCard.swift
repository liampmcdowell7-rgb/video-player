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
    /// R457: Hide Spoilers also covers the Continue Watching and Next Up cards: an episode is unwatched until it is watched (a started one too).
    @AppStorage(AppPreference.hideSpoilers.rawValue) private var hideSpoilers = false
    /// R458 (General): captions under posters, the watched check and progress, and the file name in place of the title.
    @AppStorage(AppPreference.showPosterTitles.rawValue) private var showTitles = true
    @AppStorage(AppPreference.watchedIndicators.rawValue) private var indicators = true
    @AppStorage(AppPreference.showFilenames.rawValue) private var showFilenames = false
    @Environment(AppServices.self) private var services
    @State private var fileName: String?
    @Environment(\.listRows) private var listRows
    /// #15 4.1: a 16:9 card for Continue Watching (OPEN_QUESTIONS R185); portrait everywhere else.
    var wide = false
    /// R471 (40): a Related card's one line, shown only while the card has focus, in place of the title and second lines.
    var focusCaption: String? = nil

    var body: some View {
        VStack(alignment: .leading) {
            if wide {
                NavigationLink(value: Route.item(card.id)) {
                    // R360 (compile run of 21 Nov 2026, item 7): the artwork and the text are SIBLINGS in the label, as Apple's
                    // sample writes a lockup ("Provide a separate `Image` and `Text` view in the button's label closure"), so
                    // the borderless style can move the text "out of the way of the button's image as it scales up on focus".
                    // Picture 53: wrapped in one VStack, the focused poster lifted and its title stayed put.
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
                    // R393 (item 6 c): the row's equal height is reserved under the last line, not under the title.
                    .equalCaptionBlock()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(card.title)
                .accessibilityValue(card.subtitle ?? "")
                .cardContextMenu(card)
            } else if listRows {
                // R458: List View. One system row: a small poster, the title, the second line.
                NavigationLink(value: Route.item(card.id)) {
                    HStack {
                        artwork
                            .containerRelativeFrame(.horizontal, count: 12, span: 1, spacing: 0) // design-lint:allow R458: a poster one twelfth of the row, as a list row of the Apple TV app (R312); a ratio of the container, not points
                        VStack(alignment: .leading) {
                            FittingText(PosterCaption.text(title: card.title, fileName: fileName, showFilenames: showFilenames), style: .caption)
                            secondLines
                        }
                        Spacer()
                    }
                }
                .accessibilityLabel(card.title)
                .accessibilityValue(card.subtitle ?? "")
                .cardContextMenu(card)
                .task(id: showFilenames) { await loadFileName() }
            } else {
                // R335 (PROVISIONAL, docs/HIG_AUDIT.md T1, T2): the portrait card is the same lockup as the wide one, as
                // Apple's sample builds a poster ("Creating a tvOS media catalog app in SwiftUI": `.borderless`, "Provide a
                // separate `Image` and `Text` view in the button's label closure"; the title "automatically move[s] out of
                // the way of the button's image as it scales up on focus"). Before: a `.card` button around the artwork and
                // the caption outside it.
                NavigationLink(value: Route.item(card.id)) {
                    // R360 (compile run of 21 Nov 2026, item 7): the artwork and the text are SIBLINGS in the label, as Apple's
                    // sample writes a lockup ("Provide a separate `Image` and `Text` view in the button's label closure"), so
                    // the borderless style can move the text "out of the way of the button's image as it scales up on focus".
                    // Picture 53: wrapped in one VStack, the focused poster lifted and its title stayed put.
                    artwork
                        // design-lint:allow R335: Apple's tvOS media catalog sample attaches the borderless lockup's highlight by hand to a custom artwork view; the system effect, not our own
                        .hoverEffect(.highlight)
                    // #17 C: the text keeps a side padding, so it never touches the card's edge (Larger Text screenshot
                    // 80: titles ended 2-3 px from it). The system's default padding; FittingLine measures the width
                    // inside it.
                    if let focusCaption {
                        FocusOnlyCaption(text: focusCaption)
                            .padding(.horizontal)
                    } else if showTitles || showFilenames {
                        VStack(alignment: .leading) {
                            FittingText(PosterCaption.text(title: card.title, fileName: fileName, showFilenames: showFilenames), style: .caption)
                            secondLines
                        }
                        .padding(.horizontal)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(card.title)
                .accessibilityValue(card.subtitle ?? "")
                .cardContextMenu(card)
                .task(id: showFilenames) { await loadFileName() }
                // R471 (49): drawn at every scroll position (R443's whole-row hiding removed; see PosterGridLayout).
            }
        }
    }

    // #15 D4: the progress sits inside the artwork's bottom edge, so it moves and lifts with the focused card
    // and every card keeps the same height. Fixed in code, verify in next screenshots.
    private var artwork: some View {
        ArtworkView(key: card.artworkKey, symbol: card.kind == .movie ? "film" : "tv", wide: wide)
            .blur(radius: card.kind == .episode && SpoilerRules.hidesStill(watched: card.isWatched, hideSpoilers: hideSpoilers) ? 30 : 0) // design-lint:allow R457: the spoiler blur of an unwatched episode's picture, only while Hide Spoilers is on; not a glass or scrim
            .overlay(alignment: .bottom) {
                if indicators, let progress = card.progress {
                    ProgressView(value: progress)
                        .padding()
                        .progressScrim() // R452
                }
            }
            .overlay(alignment: .topTrailing) {
                // R458: Watched Indicators. A finished title carries the system check.
                if indicators, card.isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .padding()
                        .accessibilityHidden(true)
                }
            }
    }

    private func loadFileName() async {
        guard showFilenames else { return }
        fileName = (try? await services.store.versions(of: card.id))?.first?.name
    }

    @ViewBuilder private var secondLines: some View {
        FittingLine(line: card.subtitleLine, style: .caption2)
            .foregroundStyle(.secondary)
        // R370: the card's badges drawn (4K, the HDR format, Dolby Atmos), dropped from the end where space is short.
        BadgeRow(badges: card.formatBadges)
    }
}

/// #36 group 4 (OPEN_QUESTIONS R264, PROVISIONAL; replaces the one-line marquee caption of R259): the title of a lockup
/// card (Continue Watching, episode) is never cut. It is ONE line in the Caption style when it fits, else ONE line at the
/// 23 pt floor (Caption 2, Apple's minimum on tvOS), else it is drawn at the floor size and wraps onto as many lines as it
/// needs, so no word is ever clipped. The third run of 20 Nov showed why the marquee had to go: 50 and 56 were cut
/// mid-word ("… that i") and did not move.
/// R354 (compile run of 21 Nov 2026, item 5): the choice is made by the system's `ViewThatFits` (tvOS 16.0+: "adapts to
/// the available space by providing the first child view that fits"), in the same layout pass, with no measured state.
/// Before, a hidden measure set a `@State` flag after the first layout and the caption switched to the wrapping text
/// afterwards; the run's hierarchy (55, 56, 77, 108) showed the long caption laid out 30 pt high (one line) but drawn
/// 88 pt high (three lines), so it ran over "43 min" under it. Why the card did not take the new height on the later
/// pass is not proven (the borderless lockup's layout of its label is not on Apple's pages): UNVERIFIED; this layout
/// does not depend on a later pass. The shrink is now in steps (Caption, then Caption 2) instead of continuous.
/// Height: the caption reports its own height (`CaptionHeightKey`) and every card of the row takes the tallest one
/// (`reservedCaptionHeight`, set by `equalCaptionRow`), so the cards of a row stay exactly equal. The width is the
/// column's (`maxWidth: .infinity`) and never depends on the height (#31, R231).
/// R393 (owner's review of the run on fd9731f, item 6 c): the caption no longer reserves the row's height itself. That
/// put the spare height between a short title and the line under it (the runtime). The card's whole text block reserves
/// it now (`equalCaptionBlock`), so the lines stay together and the spare height is under the last one.
struct CardCaption: View {
    let text: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            oneLine(TVTextStyle.caption)
            oneLine(TVTextStyle.caption2)
            // At the floor (Caption 2 is 23 pt on tvOS, Apple's minimum), as many lines as the title needs.
            Text(text)
                .font(TVTextStyle.caption2.font)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One line in `style`; `ViewThatFits` uses it only when its natural width fits, so it is never cut (rule S1).
    private func oneLine(_ style: TVTextStyle) -> some View {
        Text(text)
            .font(style.font)
            .lineLimit(1) // design-lint:allow R354: offered to ViewThatFits only at its natural width, so it is never cut (rule S1)
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
                // R471 (100): the SDK's @Sendable action is not main-actor isolated and `height` is, so the read and the
                // write run under an explicit main-actor assumption (synchronous, same look), as in ArtTextTop (R471 (99)).
                MainActor.assumeIsolated {
                    if abs(tallest - height) >= 0.5 { height = tallest }
                }
            }
    }
}

extension View {
    /// #36 group 4 (R264): see `EqualCaptionRow`.
    func equalCaptionRow() -> some View {
        modifier(EqualCaptionRow())
    }

    /// R393: see `EqualCaptionBlock`.
    func equalCaptionBlock() -> some View {
        modifier(EqualCaptionBlock())
    }
}

/// R393 (item 6 c of the owner's review of the run on fd9731f): the text block under a lockup's artwork (title, second
/// lines) reports its own height (`CaptionHeightKey`) and takes the tallest one of its row (`reservedCaptionHeight`),
/// its lines at the top. The cards of a row stay exactly equal (R264), and a short title has no gap under it.
struct EqualCaptionBlock: ViewModifier {
    @State private var ownHeight: CGFloat = 0
    @Environment(\.reservedCaptionHeight) private var reserved: CGFloat

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { (height: CGFloat) in
                if abs(height - ownHeight) >= 0.5 { ownHeight = height }
            }
            .preference(key: CaptionHeightKey.self, value: ownHeight)
            .frame(minHeight: reserved, alignment: .topLeading)
    }
}
