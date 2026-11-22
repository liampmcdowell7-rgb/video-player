import SwiftUI
import AppLogic

/// The show page (#15 5.1, 5.2; R350, item D: the TV app's product page, the hero area on the first screen over the clear
/// artwork, then the season tabs and episodes, then Cast & Crew): backdrop, the title (or its title logo, #15 Part 9), the synopsis, Play and More as buttons,
/// the season tabs and the chosen season's 16:9 episode cards, then the cast (#22 B: synopsis and cast as on the movie page,
/// nothing when there are no details).
///
/// R339 (owner decision of 21 Nov 2026, docs/HIG_AUDIT.md T10): seasons are a row of tabs above ONE episode list, as Apple's
/// TV app does (AppLogic `SeasonTabs`): the system segmented picker for two to seven seasons (HIG Segmented controls, tvOS:
/// "Segments become selected when focus moves to them"; "Aim for no more than about five to seven segments"), the system
/// menu picker above seven, the season's name as the heading for one. The tab shown first is the season Play starts in. This
/// replaces R189's shelf per season (its text below is history). How the segmented picker looks on tvOS 27 is UNVERIFIED.
/// R393 (owner's review of the run on fd9731f, item 6 a; PROVISIONAL): the picker is compact and left-aligned
/// (`fixedSize()`), not stretched edge to edge. No Apple page read shows what the TV app uses to choose a season
/// (the reference pack marks it UNVERIFIED), so the control itself stays the system picker.
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
    /// R350: the height of the page's scroll view, so the hero area fills the first screen (`ProductPageLayout`).
    @State private var pageHeight: CGFloat = 0

    private var shownSeason: SeasonSection? {
        SeasonTabs.shown(content.seasons, chosen: chosenSeason, resumeEpisodeID: content.resumeEpisodeID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // R350 (item D): the hero area fills the first screen, its content at the bottom over the clear artwork.
                VStack(alignment: .leading) {
                    TitleHeader(title: content.seriesTitle, artworkKey: "series-\(seriesID)")
                    // R350: the one metadata line (the seasons; no format badges for a whole show).
                    ProductMetadataLine(facts: ProductPage.showFacts(seasonCount: content.seasons.count), rating: details?.contentRating, badges: [])
                    ContentAdviceLine(descriptors: details?.contentDescriptors ?? [])
                    // As on the movie page: the synopsis above the buttons (three lines, the whole text one press away).
                    if let overview = details?.overview {
                        SynopsisLink(title: content.seriesTitle, text: overview, artworkKey: "series-\(seriesID)")
                    } else if !services.online.hasCatalogueKey {
                        // #26 item 4: one short line saying the synopsis needs the key and where to add it.
                        StatusText(OnlineLookupText.detailsNeedKey)
                    }
                    actions
                        // #33 I (OPEN_QUESTIONS R239, PROVISIONAL): room between the button row and the first season heading.
                        .padding(.bottom, DetailPageLayout.belowActions)
                }
                .productHero(pageHeight: pageHeight)
                // #25 B7 (OPEN_QUESTIONS R193, the alternative now taken, still PROVISIONAL): the episodes right after Play,
                // the cast after them. R339: the season tabs, then the chosen season's episodes.
                seasonTabs
                if let season = shownSeason {
                    StatusText(season.summary)
                    // R387: the shelf is shared with the episode page (EpisodeCards.swift).
                    EpisodeShelfRow(episodes: season.episodes, model: model)
                    // R339: another season starts at its first episode.
                    .id(season.season)
                }
                if let cast = details?.cast, !cast.isEmpty {
                    CastShelf(cast: cast)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { (height: CGFloat) in
            if abs(height - pageHeight) >= 0.5 { pageHeight = height }
        }
        // R345: the focused buttons and cards grow past the page's scroll view; it must not clip them.
        .scrollClipDisabled()
        // R346 (item A): the scrolling page is one focus region, so Up scrolls back to its first row before it
        // can leave for the tab bar (reason and UNVERIFIED cause: PaneColumns, App/Shared/SettingsPane.swift).
        .focusSection()
        .defaultFocus($playFocused, true)
        // #25 B10: as on the movie page, Play takes the focus once the page is on screen (a page pushed at launch kept the
        // tab bar's focus).
        .task(id: seriesID) { playFocused = true }
        // #15 5.2: the show's fan art (or its matched online backdrop) behind the page, as on the movie page.
        .background { BackdropView(artworkKey: "series-\(seriesID)", style: .hero) }
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
                ShelfHeader(season.title)
            }
        case .segmented:
            Picker("Season", selection: choice) {
                ForEach(content.seasons) { Text($0.title).tag($0.season) }
            }
            .pickerStyle(.segmented)
            // R393 (item 6 a; PROVISIONAL): as wide as its segments, at the leading edge. Before, the system gave the
            // control the page's whole width, edge to edge.
            .fixedSize()
            .accessibilityIdentifier(ControlID.seasonTabs)
        case .menu:
            Picker("Season", selection: choice) {
                ForEach(content.seasons) { Text($0.title).tag($0.season) }
            }
            .pickerStyle(.menu)
            .fixedSize()
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
                    ActionLabel("More", systemImage: "ellipsis", iconOnly: true)
                }
                // R396 (audit SF2): a round icon button beside Play, as on the TV app's show page (picture A4).
                .roundAction()
                .accessibilityLabel("More")
                .accessibilityIdentifier(ControlID.more)
            }
        }
    }
}
