import SwiftUI
import AppLogic

/// R387: one season's episodes as a shelf of 16:9 lockups (Apple's media catalog sample, [Display content shelves]:
/// `ScrollView(.horizontal)`, `LazyHStack(spacing: 40)`, `.scrollClipDisabled()`). Shared by the show page (the chosen
/// season, R339) and the episode page (the season's other episodes), so both draw the same cards; moved here unchanged
/// from SeasonsList.swift.
struct EpisodeShelfRow: View {
    let episodes: [EpisodeRow]
    let model: ScreenModel<SeasonsViewModel>

    var body: some View {
        ScrollView(.horizontal) {
            // design-lint:allow HIG Layout, 40 pt horizontal spacing between cards (docs/DESIGN_SYSTEM.md section 4)
            LazyHStack(alignment: .top, spacing: 40) {
                ForEach(episodes) { episode in
                    EpisodeCard(episode: episode, model: model)
                        // design-lint:allow HIG Layout, four columns of the grid width for 16:9 episode cards (R189)
                        .containerRelativeFrame(.horizontal, count: 4, spacing: 40)
                }
            }
            // #36 group 4 (R264): every episode card of the season the same caption height.
            .equalCaptionRow()
        }
        .scrollClipDisabled()
    }
}

/// One episode as a 16:9 lockup: the still and the text under it are ONE system button (`.borderless`, the tvOS lockup
/// style of Apple's "Creating a tvOS media catalog app in SwiftUI"), so the text belongs to the focused item.
/// #30 Part 2: the text is inside the button, so it belongs to the focused lockup (before, the still was a `.card` button and
/// the text sat outside it). #36 group 1 d: the earlier claim that the system marquee then scrolls a long caption is
/// withdrawn (third run of 20 Nov: 56 and 56-later identical, the caption cut mid-word). #36 group 4 (R264): the caption
/// shrinks to the 23 pt floor, then wraps, never cut (`CardCaption`); every card of a season row reserves the same caption
/// height (`equalCaptionRow`), and the still keeps its 16:9 height (`fixedSize`). The lift of the still is unverified.
struct EpisodeCard: View {
    let episode: EpisodeRow
    let model: ScreenModel<SeasonsViewModel>

    var body: some View {
        NavigationLink(value: Route.item(episode.id)) {
            // R360 (item 7): the still and the captions are siblings in the label (Apple's sample lockup), so the borderless
            // style moves the text out of the way of the lifted still.
            ArtworkView(key: episode.artworkKey, symbol: "tv", wide: true)
                .overlay(alignment: .bottom) {
                    if let progress = episode.progress {
                        ProgressView(value: progress)
                            .padding()
                    }
                }
                // #36 7 (OPEN_QUESTIONS R259): the artwork is the source of the card's size, as in Apple's tvOS media catalog
                // sample ("attach the modifier to the Image instance within the button's label closure to make the image the
                // source of the frame calculations"). Picture 55: S2 E3 (the long title) came out 378 x 566 beside
                // 410 x 615 cards: its artwork was 378 wide (410 less the caption's two 16 pt side paddings) while its
                // caption still took 378 + 32; the frame on the button alone "positions this view within an invisible
                // frame" (Apple) and does not force the label to fill it.
                // design-lint:allow HIG Layout, four columns of the grid width for 16:9 episode cards (R189, R259)
                .containerRelativeFrame(.horizontal, count: 4, spacing: 40)
                // #36 group 4 (R264): the still keeps its 16:9 height. Picture 55 of the third run of 20 Nov: S2 E3 (the
                // long title) 410 x 225 beside 410 x 231, both "43 min" lines at y 1447: the flexible 16:9 frame gave up
                // 6 pt to its taller marquee caption (probable cause; where the 6 pt came from exactly is not proven).
                .fixedSize(horizontal: false, vertical: true)
                // design-lint:allow #36 7 (R259): Apple's tvOS media catalog sample attaches the borderless lockup's highlight by hand to a custom artwork view; the system effect, not our own
                .hoverEffect(.highlight)
            captions
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(episode.code), \(episode.title)")
        .accessibilityValue(accessibilityValue)
        // R427 (run #28, item 4 b): the card's own identifier. Without one, the card button carried its badges' identifiers
        // joined ('badge.resolution-badge.hdr' on "S2, E1, Second chances", 410 x 231), so it was counted as a badge. The
        // badges are still spoken in the value above.
        .accessibilityIdentifier("card.episode.\(episode.id)")
        .contextMenu {
            Button(episode.isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: episode.isWatched ? "eye.slash" : "eye") {
                Task { await model.run { await $0.setWatched(!episode.isWatched, episodeID: episode.id) } }
            }
        }
    }

    /// The duration and "Watched", spoken after the label (typed steps).
    private var accessibilityValue: String {
        var parts: [String] = []
        if let runtime = episode.runtimeText { parts.append(runtime) }
        parts.append(contentsOf: episode.badges.map(\.spokenLabel))
        if episode.isWatched { parts.append("Watched") }
        return parts.joined(separator: ", ")
    }

    private var captions: some View {
        VStack(alignment: .leading) {
            // #25 B7: always "S2, E1 · Title" (R358: the player's form) (the title is "Episode 1" when the file names none, never the code again).
            // #36 group 4 (R264): shrinks to the floor, then wraps, never cut; the row's tallest caption height.
            CardCaption(text: episode.code + " · " + episode.title)
            // R391 (shared fault 1): one tight group at the leading edge (`BadgeSpacing`). Before: an `HStack` at the
            // system's default spacing (the run on fd9731f: "43 min" and "1080p" 60 pt apart) and a fixed 44 pt slot for
            // the watched mark (`SymbolColumn`), drawn or not.
            HStack(spacing: CGFloat(BadgeSpacing.afterText)) {
                if let runtime = episode.runtimeText {
                    FittingText(runtime, style: .caption2)
                        .foregroundStyle(.secondary)
                }
                // R370: the episode's own badges (resolution, HDR, Dolby Atmos), dropped from the end where space is short.
                BadgeRow(badges: episode.badges)
                if episode.isWatched {
                    Image(systemName: "checkmark.circle")
                        .font(.caption2)
                        .accessibilityLabel("Watched")
                }
            }
        }
        .padding(.horizontal)
        // R393 (item 6 c): the row's equal height is reserved under the runtime line, not between the title and it.
        .equalCaptionBlock()
    }
}
