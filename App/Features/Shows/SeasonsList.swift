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
    /// R452: where the title begins, for the cover behind it.
    @State private var textTop: CGFloat?
    /// R471 item 1: the page is scrolled below its hero (the backdrop is the blurred copy).
    @State private var belowHero = false
    @FocusState private var playFocused: Bool
    /// R339: the season the person chose with the tabs; nil until they choose (then `SeasonTabs.shown` picks).
    @State private var chosenSeason: Int?
    /// R350: the height of the page's scroll view, so the hero area fills the first screen (`ProductPageLayout`).
    @State private var pageHeight: CGFloat = 0
    /// R453: the episode card that has the focus, the one it rested on (`InfoBlockLayout.focusRestSeconds`), and the details
    /// asked for so far; the info block shows the resting episode, else the show.
    @AppStorage(AppPreference.hideSpoilers.rawValue) private var hideSpoilers = false
    @State private var focusedEpisodeID: Int64?
    @State private var restingEpisodeID: Int64?
    @State private var episodeDetails: [Int64: TitleDetails] = [:]

    private var showFacts: InfoFacts {
        InfoFacts(date: details?.releaseDate, contentRating: details?.contentRating, genres: details?.genres ?? [],
                  synopsis: details?.overview)
    }

    /// R453: what the block says: the resting episode of the shown season, else the show's own data.
    private var infoBlock: InfoBlock {
        guard let id = restingEpisodeID, let season = shownSeason, let episode = season.episodes.first(where: { $0.id == id }) else {
            return InfoBlock.show(showFacts)
        }
        let d: TitleDetails? = episodeDetails[id]
        let facts = InfoFacts(runtime: episode.runtimeText, date: d?.releaseDate, contentRating: d?.contentRating,
                              resolution: episode.badges.first { $0.group == .resolution }?.text,
                              audio: episode.badges.first { $0.group == .audio }?.text,
                              genres: d?.genres ?? [],
                              synopsis: SpoilerRules.synopsis(d?.overview, watched: episode.isWatched, hideSpoilers: hideSpoilers))
        return InfoBlock.episode(season: season.season, number: episode.number, title: episode.title, facts: facts, show: showFacts)
    }

    private var shownSeason: SeasonSection? {
        SeasonTabs.shown(content.seasons, chosen: chosenSeason, resumeEpisodeID: content.resumeEpisodeID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // R350 (item D): the hero area fills the first screen, its content at the bottom over the clear artwork.
                VStack(alignment: .leading) {
                    TitleHeader(title: content.seriesTitle, artworkKey: "series-\(seriesID)")
                    // R404: nothing in the stack without content advice, as on the movie page.
                    if let advice = details?.contentDescriptors, !advice.isEmpty {
                        ContentAdviceLine(descriptors: advice)
                    }
                    // R453 (PROVISIONAL): the info block of the focused episode (the show's own data when focus is elsewhere), of
                    // one fixed height. The show's whole synopsis is still one press away (rule L5).
                    InfoBlockView(block: infoBlock,
                                  fullText: (title: content.seriesTitle, artworkKey: "series-\(seriesID)", prefersEpisodeStill: false),
                                  fixedHeight: true)
                    if details?.overview == nil, !services.online.hasCatalogueKey {
                        // #26 item 4: one short line saying the synopsis needs the key and where to add it.
                        StatusText(OnlineLookupText.detailsNeedKey)
                    }
                    actions
                        // #33 I (OPEN_QUESTIONS R239, PROVISIONAL): room between the button row and the first season heading.
                        .padding(.bottom, DetailPageLayout.belowActions)
                }
                // R470: the whole text column reports its top for the cover behind it (not the title alone).
                .reportsArtTextTop()
                .productHero(pageHeight: pageHeight, fraction: CGFloat(InfoBlockLayout.showHeroFraction))
                // R424 (run #28, 56-show-page-SCROLL-UP): as on the movie page, Up from any card below climbs back into
                // the hero, and Play takes the focus there (reasons: ItemDetailContentView's hero).
                .focusSection()
                .defaultFocus($playFocused, true, priority: .userInitiated)
                // R471 item 1: the part below the hero starts with the show's logo (or title), centred (frames t06s, t12s).
                BelowHeroHeader(title: content.seriesTitle, artworkKey: "series-\(seriesID)")
                // #25 B7 (OPEN_QUESTIONS R193, the alternative now taken, still PROVISIONAL): the episodes right after Play,
                // the cast after them. R339: the season tabs, then the chosen season's episodes.
                seasonTabs
                    // R424: Up from an episode card at the right (x 980 in run #28) reaches the picker at the left.
                    .productPageRow()
                if let season = shownSeason {
                    // R453: no "N of M watched" line under the strip (PROVISIONAL: the watched checks are on the stills).
                    // R387: the shelf is shared with the episode page (EpisodeCards.swift).
                    EpisodeShelfRow(episodes: season.episodes, model: model, focusedID: $focusedEpisodeID)
                    // R339: another season starts at its first episode.
                    .id(season.season)
                    // R424: Up from any cast entry reaches the episodes.
                    .productPageRow()
                }
                if let cast = details?.cast, !cast.isEmpty {
                    CastShelf(cast: cast)
                }
            }
            // R470: the space the hero column reports its top in (ArtTextTop).
            .artTextContent()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { (height: CGFloat) in
            if abs(height - pageHeight) >= 0.5 { pageHeight = height }
        }
        // R471 item 1: below the hero, the backdrop turns into the blurred, dimmed copy.
        .reportsBelowHero($belowHero, heroHeight: pageHeight * CGFloat(InfoBlockLayout.showHeroFraction))
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
        .artTextTop($textTop)
        .background { BackdropView(artworkKey: "series-\(seriesID)", style: .hero, textTop: textTop, belowHero: belowHero) }
        .task(id: "series-\(seriesID)|\(services.online.keyRevision)") {
            details = await services.online.details(key: "series-\(seriesID)")
        }
        // R453: the block changes only when the focus has rested on a card (or left the cards) for a moment.
        .task(id: focusedEpisodeID) {
            try? await Task.sleep(for: .seconds(InfoBlockLayout.focusRestSeconds))
            guard !Task.isCancelled else { return }
            restingEpisodeID = focusedEpisodeID
        }
        // R453: the resting episode's own details (synopsis, date, genres, rating), the source's layer and the user's edits.
        .task(id: restingEpisodeID) {
            guard let id = restingEpisodeID, episodeDetails[id] == nil, let episode = shownSeason?.episodes.first(where: { $0.id == id }) else { return }
            var own = await services.online.details(key: episode.artworkKey)
            if let item = try? await services.store.item(id: id) {
                let files = (try? await services.store.versions(of: id)) ?? []
                own = EditTarget.apply(services.ledger.edits(for: EditTarget.keys(for: item, files: files)), to: own)
            }
            if let own { episodeDetails[id] = own }
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
            // R453 (PROVISIONAL; replaces the segmented picker of R339, R393): the chosen season is a filled capsule, the
            // others plain text (system button styles, the capsule border shape). Alternative: the segmented picker.
            HStack {
                ForEach(content.seasons) { season in
                    if season.season == choice.wrappedValue {
                        Button { choice.wrappedValue = season.season } label: { FittingText(season.title).padding(.horizontal) }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .accessibilityAddTraits(.isSelected)
                    } else {
                        Button { choice.wrappedValue = season.season } label: { FittingText(season.title).padding(.horizontal) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .fixedSize()
            .accessibilityElement(children: .contain)
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
            // R453: the round Watched button: the check when everything is watched, the eye otherwise. With the focus on this
            // button no episode is focused, so it acts on the whole show; one episode is marked from its card's menu.
            if content.canMarkWatched || content.canMarkUnwatched {
                let everythingWatched: Bool = !content.canMarkWatched
                Button {
                    Task { await model.run { await $0.markSeries(watched: !everythingWatched) } }
                } label: {
                    ActionLabel("Watched", systemImage: PageButtonSymbols.watched(everythingWatched), iconOnly: true)
                }
                .roundAction()
                .accessibilityLabel("Watched")
                .accessibilityValue(everythingWatched ? "On" : "Off")
                .accessibilityHint(everythingWatched ? "Marks the whole show as unwatched" : "Marks the whole show as watched")
                .accessibilityIdentifier(ControlID.watched)
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
