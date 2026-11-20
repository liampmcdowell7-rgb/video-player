import SwiftUI
import AppLogic

/// One title in a row or grid: the poster is the button (system `.card` style, Liquid Glass on focus), the text sits below it.
///
/// Every card has the same parts in the same places (screenshot review item 4: posters in one grid row sat at different
/// heights because cards with fewer text lines were centred): the title, the second line and the badge line are always laid
/// out, empty ones hidden (the progress is inside the artwork, #15 D4), so equal cards are exactly equal in size and their posters line up. Short texts
/// follow rule S1 (`FittingLine`): one line, scaled to the readable minimum, never cut with "…".
///
/// #34 5a (OPEN_QUESTIONS R229, PROVISIONAL): the Continue Watching card (`wide`) puts its title INSIDE the button, so the
/// system marquee can run. `UILabel.enablesMarqueeWhenAncestorFocused` scrolls "when any ancestor in its view hierarchy has
/// focus" (Apple, UILabel), and `isFocused` reads the "nearest focusable ancestor": with the title beside the button (as on
/// every other card) neither ever happened, so the #33 E marquee could not start. The wide card uses Apple's tvOS content
/// lockup ("Creating a tvOS media catalog app in SwiftUI": `.borderless`, image and title in the label, the title moves out
/// of the way as the image scales up), exactly as the episode card (`EpisodeCard`, SeasonsList.swift, #30). Whether the
/// system finds the artwork as the "first image" for its lift is unverified (ArtworkView is a custom view). Portrait cards are unchanged.
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
                        // #33 E: fades at rest when too long (R229 (c)); #34 5a: inside the focused button, so it scrolls.
                        FittingText(card.title, style: .caption, fadesAtRest: true)
                            .padding(.horizontal)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(card.title)
                .accessibilityValue(card.subtitle ?? "")
                .cardContextMenu(card)
                VStack(alignment: .leading) {
                    secondLines
                }
                .padding(.horizontal)
            } else {
                NavigationLink(value: Route.item(card.id)) {
                    artwork
                }
                .buttonStyle(.card)
                .accessibilityLabel(card.title)
                .accessibilityValue(card.subtitle ?? "")
                .cardContextMenu(card)
                // #17 C: the text keeps a side padding, so it never touches the card's edge (Larger Text screenshot 80: titles
                // ended 2-3 px from it). The system's default padding; FittingLine measures the width inside it.
                VStack(alignment: .leading) {
                    FittingText(card.title, style: .caption)
                    secondLines
                }
                .padding(.horizontal)
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
