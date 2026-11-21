import SwiftUI
import AppLogic

/// The show page (#15 5.1, 5.2): backdrop, the title (or its title logo, #15 Part 9), the synopsis, Play and More as buttons,
/// the season tabs and the chosen season's 16:9 episode cards, then the cast (#22 B: synopsis and cast as on the movie page,
/// nothing when there are no details).
///
/// R339 (owner decision of 21 Nov 2026, docs/HIG_AUDIT.md T10): seasons are a row of tabs above ONE episode list, as Apple's
/// TV app does (AppLogic `SeasonTabs`): the system segmented picker for two to seven seasons (HIG Segmented controls, tvOS:
/// "Segments become selected when focus moves to them"; "Aim for no more than about five to seven segments"), the system
/// menu picker above seven, the season's name as the heading for one. The tab shown first is the season Play starts in. This
/// replaces R189's shelf per season (its text below is history). How the segmented picker looks on tvOS 27 is UNVERIFIED.
///
/// 5.1: only the show-wide mark that changes something is offered, inside More; the "X of Y watched" summary is secondary
/// text under each season's name (R180). 5.2 (OPEN_QUESTIONS R189, PROVISIONAL): every season is its own shelf, so no
/// season menu is needed and nothing is hidden behind one; an episode card shows its still (or the show's picture), the
/// progress inside it, "E1 · Title", the duration and the watched mark. There is no per-episode synopsis in the library
/// index, so the card has none. Fixed in code, verify in next screenshots (55, 56).
struct SeasonsList: View {
    let content: SeasonsContent
    let seriesID: Int64
    let model: ScreenModel<SeasonsViewModel>
    var onPlay: (Int64) -> Void
    @Environment(AppServices.self) private var services
    /// #22 B (OPEN_QUESTIONS R193): the show's synopsis and cast, from the same details lookup as the movie page. Nil (no
    /// key, no match, or both empty) draws nothing: no empty band (rule L6).
    @State private var details: TitleDetails?
    @FocusState private var playFocused: Bool
    /// R339: the season the person chose with the tabs; nil until they choose (then `SeasonTabs.shown` picks).
    @State private var chosenSeason: Int?

    private var shownSeason: SeasonSection? {
        SeasonTabs.shown(content.seasons, chosen: chosenSeason, resumeEpisodeID: content.resumeEpisodeID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                TitleHeader(title: content.seriesTitle, artworkKey: "series-\(seriesID)")
                // As on the movie page: the synopsis above the buttons (three lines, the whole text one press away).
                if let overview = details?.overview {
                    SynopsisLink(title: content.seriesTitle, text: overview)
                } else if !services.online.hasCatalogueKey {
                    // #26 item 4: one short line saying the synopsis needs the key and where to add it.
                    StatusText(OnlineLookupText.detailsNeedKey)
                }
                actions
                    // #33 I (OPEN_QUESTIONS R239, PROVISIONAL): room between the button row and the first season heading.
                    .padding(.bottom, DetailPageLayout.belowActions)
                // #25 B7 (OPEN_QUESTIONS R193, the alternative now taken, still PROVISIONAL): the episodes right after Play,
                // the cast after them. R339: the season tabs, then the chosen season's episodes.
                seasonTabs
                if let season = shownSeason {
                    StatusText(season.summary)
                    ScrollView(.horizontal) {
                        // design-lint:allow HIG Layout, 40 pt horizontal spacing between cards (docs/DESIGN_SYSTEM.md section 4)
                        LazyHStack(alignment: .top, spacing: 40) {
                            ForEach(season.episodes) { episode in
                                EpisodeCard(episode: episode, model: model)
                                    // design-lint:allow HIG Layout, four columns of the grid width for 16:9 episode cards (R189)
                                    .containerRelativeFrame(.horizontal, count: 4, spacing: 40)
                            }
                        }
                        // #36 group 4 (R264): every episode card of the season the same caption height.
                        .equalCaptionRow()
                    }
                    .scrollClipDisabled()
                    // R339: another season starts at its first episode.
                    .id(season.season)
                }
                if let cast = details?.cast, !cast.isEmpty {
                    CastShelf(cast: cast)
                }
            }
        }
        .defaultFocus($playFocused, true)
        // #25 B10: as on the movie page, Play takes the focus once the page is on screen (a page pushed at launch kept the
        // tab bar's focus).
        .task(id: seriesID) { playFocused = true }
        // #15 5.2: the show's fan art (or its matched online backdrop) behind the page, as on the movie page.
        .background { BackdropView(artworkKey: "series-\(seriesID)") }
        .task(id: "series-\(seriesID)|\(services.online.keyRevision)") {
            details = await services.online.details(key: "series-\(seriesID)")
        }
        .pushedScreen(content.seriesTitle)
    }

    /// R339: the system picker for the seasons (segmented or menu, `SeasonTabs.style`), or the one season's name.
    @ViewBuilder private var seasonTabs: some View {
        let choice = Binding<Int>(get: { shownSeason?.season ?? 0 }, set: { chosenSeason = $0 })
        switch SeasonTabs.style(seasonCount: content.seasons.count) {
        case .heading:
            if let season = shownSeason {
                Text(season.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
        case .segmented:
            Picker("Season", selection: choice) {
                ForEach(content.seasons) { Text($0.title).tag($0.season) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(ControlID.seasonTabs)
        case .menu:
            Picker("Season", selection: choice) {
                ForEach(content.seasons) { Text($0.title).tag($0.season) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(ControlID.seasonTabs)
        }
    }

    private var actions: some View {
        ActionRow {
            if let resume = content.resumeEpisodeID {
                Button { onPlay(resume) } label: { ActionLabel(content.playTitle, systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .focused($playFocused)
                    .accessibilityIdentifier(ControlID.play)
            }
            if content.canMarkWatched || content.canMarkUnwatched {
                Menu {
                    if content.canMarkWatched {
                        Button("Mark Show as Watched", systemImage: "eye") {
                            Task { await model.run { await $0.markSeries(watched: true) } }
                        }
                    }
                    if content.canMarkUnwatched {
                        Button("Mark Show as Unwatched", systemImage: "eye.slash") {
                            Task { await model.run { await $0.markSeries(watched: false) } }
                        }
                    }
                } label: {
                    ActionLabel("More", systemImage: "ellipsis")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier(ControlID.more)
            }
        }
    }
}

/// One episode as a 16:9 lockup: the still and the text under it are ONE system button (`.borderless`, the tvOS lockup
/// style of Apple's "Creating a tvOS media catalog app in SwiftUI"), so the text belongs to the focused item.
/// #30 Part 2: the text is inside the button, so it belongs to the focused lockup (before, the still was a `.card` button and
/// the text sat outside it). #36 group 1 d: the earlier claim that the system marquee then scrolls a long caption is
/// withdrawn (third run of 20 Nov: 56 and 56-later identical, the caption cut mid-word). #36 group 4 (R264): the caption
/// shrinks to the 23 pt floor, then wraps, never cut (`CardCaption`); every card of a season row reserves the same caption
/// height (`equalCaptionRow`), and the still keeps its 16:9 height (`fixedSize`). The lift of the still is unverified.
private struct EpisodeCard: View {
    let episode: EpisodeRow
    let model: ScreenModel<SeasonsViewModel>

    var body: some View {
        NavigationLink(value: Route.item(episode.id)) {
            VStack(alignment: .leading) {
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
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(episode.code), \(episode.title)")
        .accessibilityValue(accessibilityValue)
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
        if episode.isWatched { parts.append("Watched") }
        return parts.joined(separator: ", ")
    }

    private var captions: some View {
        VStack(alignment: .leading) {
            // #25 B7: always "S2 E1 · Title" (the title is "Episode 1" when the file names none, never the code again).
            // #36 group 4 (R264): shrinks to the floor, then wraps, never cut; the row's tallest caption height.
            CardCaption(text: episode.code + " · " + episode.title)
            HStack {
                if let runtime = episode.runtimeText {
                    FittingText(runtime, style: .caption2)
                        .foregroundStyle(.secondary)
                }
                // #15 D5: the watched mark keeps its slot.
                SymbolColumn(systemImage: "checkmark.circle", isShown: episode.isWatched, accessibilityText: "Watched")
            }
        }
        .padding(.horizontal)
    }
}
