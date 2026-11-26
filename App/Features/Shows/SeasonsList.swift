import SwiftUI
import AppLogic
import VideoPlayerCore
import LibraryIndex
import UserData
import MetadataOnline

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
    /// R471 (31): the season the page opens on (an episode's Go to Season) until the person picks another tab.
    var startSeason: Int? = nil
    @Environment(AppServices.self) private var services
    /// #22 B (OPEN_QUESTIONS R193): the show's synopsis and cast, from the same details lookup as the movie page. Nil (no
    /// key, no match, or both empty) draws nothing: no empty band (rule L6).
    @State private var details: TitleDetails?
    /// R471 (25): the library's other shows that share a genre with this one (`RelatedShows`).
    @State private var relatedShows: [SeriesSummary] = []
    /// R471 (40): the genre each Related show shares with this one, for its focus caption.
    @State private var relatedGenres: [Int64: String] = [:]
    /// R471 (39): the show's own extras (its folder and its season folders), found again when the library changes.
    @State private var showExtras: [ShowExtras.Found] = []
    /// R452: where the title begins, for the cover behind it.
    @State private var textTop: CGFloat?
    /// R471 item 1: the page is scrolled below its hero (the backdrop is the blurred copy).
    @State private var belowHero = false
    @FocusState private var playFocused: Bool
    /// R339: the season the person chose with the tabs; nil until they choose (then `SeasonTabs.shown` picks).
    @State private var chosenSeason: Int?
    /// R350: the height of the page's scroll view, so the hero area fills the first screen (`ProductPageLayout`).
    @State private var pageHeight: CGFloat = 0
    /// R471 item 6: the episodes' own details asked for so far (the shown season's cards and the next-up episode).
    @AppStorage(AppPreference.hideSpoilers.rawValue) private var hideSpoilers = false
    @State private var episodeDetails: [Int64: TitleDetails] = [:]
    /// R471 item 6: the layer the show's rating came from (the age guidance card says where it came from).
    @State private var ratingLayer: DetailsLayer?
    /// R471 (22): the shown season's own title and synopsis, and whether a poster of that season was found.
    @State private var seasonHeader: SeasonHeader?
    @State private var seasonHasPoster = false
    /// R471 item 6: the next-up episode's source (the kind line) and tracks (Languages, Accessibility).
    @State private var nextSource: (kind: SourceKind?, name: String?)?
    @State private var nextTracks: FileTrackDetails?
    /// R471 Part 3: Mark All as Watched or Unwatched waiting for its confirmation.
    @State private var pendingMarkAll: ProductAction?
    /// R471 (23): a season's Mark as Watched or Unwatched from its long press, waiting for its confirmation.
    @State private var pendingMarkSeason: (season: SeasonSection, watched: Bool)?
    /// R471 (14): Unmatch for the whole show is asked about (system confirmation dialog).
    @State private var askUnmatch = false
    /// R471 (15): the show or season asked about for Delete from Library; the page closes after the whole show is removed.
    @State private var pendingDelete: LibraryRemover.Target?
    /// R471 (16): the show's own rating (the user layer).
    @State private var showStars: Int?
    /// R471 (61): the matched show is on the watchlist (the details button says Add or Remove).
    @State private var onWatchlist = false
    /// R471 (17): the show's key for the user's lists, and the name page of a new list.
    @State private var showRef: UDTitleRef?
    @State private var naming: ListNameRequest?
    /// R471 (18): the result of Refresh Details for the show.
    @State private var refreshOutcome: TitleRefresh.Outcome?
    @Environment(\.dismiss) private var dismiss
    /// R471 (11): the show's online id (from one of its episodes), the open edit screen, and a count bumped when it closes so
    /// the page reads the edits again.
    @State private var showTMDB: Int?
    @State private var editRequest: ShowEditRequest?
    @State private var editRevision = 0
    /// R471 (12): Fix Match for the whole show, opened through this episode.
    @State private var fixMatchEpisode: FixMatchRequest?

    /// R471 item 6: the description of the hero: the next-up episode's synopsis after its code and title, else the show's.
    private var heroDescription: (prefix: String?, text: String)? {
        let next: EpisodeRow? = content.resumeEpisode
        let nextOverview: String? = next.flatMap { e in
            SpoilerRules.synopsis(episodeDetails[e.id]?.overview, watched: e.isWatched, hideSpoilers: hideSpoilers)
        }
        return ShowHeroText.description(showOverview: details?.overview, nextCode: next?.code, nextTitle: next?.title,
                                        nextOverview: nextOverview)
    }

    /// R471 item 6: each card's text of the shown season.
    private var cardTexts: [Int64: EpisodeCardText] {
        var out: [Int64: EpisodeCardText] = [:]
        for e in shownSeason?.episodes ?? [] {
            out[e.id] = EpisodeCardText.make(number: e.number, title: e.title, details: episodeDetails[e.id], watched: e.isWatched,
                                             hideSpoilers: hideSpoilers)
        }
        return out
    }

    private var information: [InfoEntry] {
        ProductInfo.information(released: details?.releaseDate, year: nil, durationSeconds: nil, rating: details?.contentRating,
                                advisories: details?.contentDescriptors ?? [], regions: ProductInfo.regionNames(details?.regions ?? []),
                                yearOnly: true)
    }

    private var shownSeason: SeasonSection? {
        SeasonTabs.shown(content.seasons, chosen: chosenSeason ?? startSeason, resumeEpisodeID: content.resumeEpisodeID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // R350 (item D): the hero area fills the first screen, its content at the bottom over the clear artwork.
                VStack(alignment: .leading) {
                    TitleHeader(title: content.seriesTitle, artworkKey: "series-\(seriesID)")
                    // R471 item 6 (frames show t08s, home photo): "TV Show · genres [rating]".
                    HeroKindLineView(segments: HeroLines.kindLine(kind: .show, source: nextSource?.kind, genres: details?.genres ?? [],
                                                                  rating: details?.contentRating))
                    // R471 (83): no content advice line on the hero (frames show t08s, t10s: the description follows the kind
                    // line); the advice is the Information column's "Content Advisories" row, as on the movie and episode pages.
                    // R471 item 6: replaces R453's focus-driven info block: the next-up episode's synopsis after "S4, E4 · Title:",
                    // else the show's; the whole text one press away (rule L5).
                    if let description = heroDescription {
                        HeroDescription(prefix: description.prefix, text: description.text, title: content.seriesTitle,
                                        artworkKey: "series-\(seriesID)")
                    }
                    if details?.overview == nil, !services.online.hasCatalogueKey {
                        // #26 item 4: one short line saying the synopsis needs the key and where to add it. R471 (87): in the
                        // description's place, before the facts line, as on the movie page.
                        StatusText(OnlineLookupText.detailsNeedKey)
                    }
                    // R471 (84): the next-up episode's air year (else the show's first) and length, then its glyph badges.
                    HeroFactsLineView(texts: HeroLines.showFactsText(nextEpisodeDate: content.resumeEpisode.flatMap { episodeDetails[$0.id]?.releaseDate },
                                                                     nextEpisodeSeconds: content.resumeEpisode?.durationSeconds,
                                                                     showDate: details?.releaseDate),
                                      badges: HeroBadges.make(format: content.resumeEpisode?.badges ?? [], access: AccessFeature.detect(nextTracks)))
                    actions
                        // #33 I (OPEN_QUESTIONS R239, PROVISIONAL): room between the button row and the first season heading.
                        .padding(.bottom, DetailPageLayout.belowActions)
                }
                // R470: the whole text column reports its top for the cover behind it (not the title alone).
                .reportsArtTextTop()
                .productHero(pageHeight: pageHeight, fraction: CGFloat(InfoBlockLayout.showHeroFraction))
                // R471 item 6 (owner's Part 1 correction): "Starring" and "Director" at the lower right, as on the movie page.
                .overlay(alignment: .bottomTrailing) {
                    let starring: String? = ProductPage.starring((details?.cast ?? []).map(\.name))
                    let director = ProductInfo.directorLine(details?.directors ?? [])
                    if starring != nil || director != nil {
                        StarringBlock(names: starring, director: director)
                            .padding(.bottom, DetailPageLayout.belowActions)
                    }
                }
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
                // R471 (22): the season's own poster, title and synopsis, only when they say more than the picker.
                if let season = shownSeason, let seasonHeader,
                   seasonHeader.isWorthShowing(libraryTitle: season.title, hasPoster: seasonHasPoster) {
                    SeasonHeaderRow(header: seasonHeader, artworkKey: ArtworkKey.seasonKey(seriesID: seriesID, number: season.season),
                                    showsPoster: seasonHasPoster)
                        // R471 (23): the season's actions on a long press of its card.
                        .contextMenu { seasonMenu(season) }
                }
                if let season = shownSeason {
                    // R453: no "N of M watched" line under the strip (PROVISIONAL: the watched checks are on the stills).
                    // R387: the shelf is shared with the episode page (EpisodeCards.swift).
                    // R471 item 6: each card with its number, title, description, date and rating.
                    EpisodeShelfRow(episodes: season.episodes, model: model, texts: cardTexts)
                    // R339: another season starts at its first episode.
                    .id(season.season)
                    // R424: Up from any cast entry reaches the episodes.
                    .productPageRow()
                }
                // R471 (39), PROVISIONAL (frames show t06s, t16s): the show's own Trailers, then Bonus Content, under the
                // episodes: the whole show's extras and those of the season on screen.
                let extraShelves = ExtraShelves.split(ShowExtras.rows(showExtras, season: shownSeason?.season))
                if !extraShelves.trailers.isEmpty {
                    ExtrasShelf(heading: ExtraShelves.trailersHeading, extras: extraShelves.trailers, itemID: 0, seriesID: seriesID)
                }
                if !extraShelves.bonus.isEmpty {
                    ExtrasShelf(heading: ExtraShelves.bonusHeading, extras: extraShelves.bonus, itemID: 0, seriesID: seriesID)
                }
                // R471 (25): Related, from the library's own shows. R471 (26), PROVISIONAL (frame show t16s): before the
                // cast, as on the reference page.
                if !relatedShows.isEmpty {
                    RelatedShowsShelf(shows: relatedShows, genres: relatedGenres)
                }
                if let cast = details?.cast, !cast.isEmpty {
                    CastShelf(cast: cast)
                }
                // R471 item 6 (frames show t16s to t20s): About, then the columns; each only with data. How to Watch and its
                // "Seasons" line were removed by the owner (R471 (21)).
                let guidance: AgeGuidance? = AgeGuidance.make(rating: details?.contentRating, layer: ratingLayer,
                                                              descriptors: details?.contentDescriptors ?? [])
                if details?.overview != nil || guidance != nil {
                    AboutSection(title: content.seriesTitle, summary: details?.overview, artworkKey: "series-\(seriesID)", guidance: guidance,
                                 genres: details?.genres ?? [])
                }
                let languages: [InfoEntry] = ProductInfo.languages(tracks: nextTracks, originalLanguage: details?.originalLanguage)
                let access: [InfoEntry] = ProductInfo.accessibility(AccessFeature.detect(nextTracks))
                if !information.isEmpty || !languages.isEmpty || !access.isEmpty {
                    ProductInfoColumns(information: information, languages: languages, accessibility: access)
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
        .listNameCover($naming)
        .alert(refreshOutcome.map { TitleRefresh.result($0).title } ?? "", isPresented: Binding(get: { refreshOutcome != nil }, set: { if !$0 { refreshOutcome = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let refreshOutcome { Text(TitleRefresh.result(refreshOutcome).message) }
        }
        // #15 5.2: the show's fan art (or its matched online backdrop) behind the page, as on the movie page.
        .artTextTop($textTop)
        .background { BackdropView(artworkKey: "series-\(seriesID)", style: .hero, textTop: textTop, belowHero: belowHero) }
        .task(id: "series-\(seriesID)|\(services.online.keyRevision)|\(editRevision)") {
            let layered = await services.online.layeredDetails(key: "series-\(seriesID)")
            // R471 (11): the show's own edits on top of the layers (R449), keyed by its online id once an episode gives it.
            if showTMDB == nil, let id = content.resumeEpisodeID ?? content.seasons.first?.episodes.first?.id,
               let item = try? await services.store.item(id: id) {
                showTMDB = item.tmdbID
            }
            details = EditTarget.apply(services.ledger.edits(for: EditTarget.showKeys(tmdbID: showTMDB, title: content.seriesTitle)),
                                       to: layered.details)
            ratingLayer = layered.ratingLayer
            showStars = services.ledger.rating(for: EditTarget.showKeys(tmdbID: showTMDB, title: content.seriesTitle))
            showRef = await services.titleRef(seriesID: seriesID)
            refreshWatchlist()
        }
        // R471 (25): the show's genres go to its episodes in the library (so other pages can match it), then Related is
        // found from the library only (no online lookup), again when the genres or the library change.
        .task(id: "\((details?.genres ?? []).joined(separator: "|"))|\(services.libraryRevision)") {
            let genres = details?.genres ?? []
            await services.genreRecorder.record(genres, itemIDs: content.seasons.flatMap { $0.episodes.map(\.id) }, store: services.store)
            relatedShows = (try? await RelatedShows.find(seriesID: seriesID, genres: genres, store: services.store)) ?? []
            relatedGenres = (try? await RelatedCaption.sharedGenres(kind: .show, genres: genres, store: services.store)) ?? [:]
        }
        .task(id: "extras-\(seriesID)|\(services.libraryRevision)") {
            showExtras = (try? await ShowExtras.load(seriesID: seriesID, store: services.store)) ?? []
        }
        .taskCover(item: Binding(get: { editRequest }, set: { new in
            if new == nil, editRequest != nil { editRevision += 1 }
            editRequest = new
        })) { request in
            MetadataEditView(title: request.title, keys: request.keys, artworkKey: request.artworkKey, level: request.level,
                             startGroup: request.startGroup)
        }
        // R471 (14): Unmatch the show; the confirmation says what changes and what stays (`Unmatcher.confirmation`).
        .confirmationDialog(unmatchText.title, isPresented: $askUnmatch, titleVisibility: .visible) {
            Button(unmatchText.button, role: .destructive) {
                Task {
                    await services.unmatch(.show(seriesID: seriesID, title: content.seriesTitle))
                    showTMDB = nil
                    editRevision += 1
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(unmatchText.message)
        }
        .confirmationDialog(deleteText.title, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            if let target = pendingDelete {
                Button(deleteText.button, role: .destructive) {
                    Task {
                        await services.removeFromLibrary(target)
                        if case .show = target { dismiss() }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteText.message)
        }
        // R471 (23): a season's Mark as Watched or Unwatched from its long press asks first, as Mark All does.
        .confirmationDialog(pendingMarkSeason.map { $0.watched ? "Mark \($0.season.title) as Watched" : "Mark \($0.season.title) as Unwatched" } ?? "",
                            isPresented: Binding(get: { pendingMarkSeason != nil }, set: { if !$0 { pendingMarkSeason = nil } }),
                            titleVisibility: .visible) {
            if let pending = pendingMarkSeason {
                Button(pending.watched ? "Mark as Watched" : "Mark as Unwatched") {
                    Task { await model.run { await $0.markSeason(pending.season.season, watched: pending.watched) } }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(pendingMarkSeason.map { "Every episode of " + $0.season.title + " will be marked as " + ($0.watched ? "watched." : "unwatched.") } ?? "")
        }
        .taskCover(item: Binding(get: { fixMatchEpisode }, set: { new in
            if new == nil, fixMatchEpisode != nil { showTMDB = nil; editRevision += 1 }
            fixMatchEpisode = new
        })) { request in
            FixMatchView(itemID: request.id, kind: .episode, currentTitle: content.seriesTitle, initialScope: .wholeShow)
        }
        // R471 item 6: the episodes' own details (synopsis, date, rating) for the shown season's cards and the next-up
        // episode, the source's layer and the user's edits (as R453 did for the focused card).
        .task(id: "\(shownSeason?.season ?? -1)|\(content.resumeEpisodeID ?? 0)|\(services.online.keyRevision)") {
            var ids: [(Int64, String)] = (shownSeason?.episodes ?? []).map { ($0.id, $0.artworkKey) }
            if let next = content.resumeEpisode { ids.insert((next.id, next.artworkKey), at: 0) }
            for (id, key) in ids where episodeDetails[id] == nil {
                if Task.isCancelled { return }
                var own = await services.online.details(key: key)
                if let item = try? await services.store.item(id: id) {
                    let files = (try? await services.store.versions(of: id)) ?? []
                    own = EditTarget.apply(services.ledger.edits(for: EditTarget.keys(for: item, files: files)), to: own)
                }
                if let own { episodeDetails[id] = own }
            }
        }
        // R471 (22): the shown season's own text (online, with the user's season edits on top) and whether it has a poster.
        // Asked again when another season is chosen, the online key changes, an edit screen closes or the show's id arrives.
        .task(id: "\(shownSeason?.season ?? -1)|\(services.online.keyRevision)|\(editRevision)|\(showTMDB ?? 0)") {
            guard let season = shownSeason else { seasonHeader = nil; seasonHasPoster = false; return }
            let key: String = ArtworkKey.seasonKey(seriesID: seriesID, number: season.season)
            let online = await services.online.season(key: key)
            let edits = services.ledger.edits(for: EditTarget.seasonKeys(tmdbID: showTMDB, title: content.seriesTitle, season: season.season))
            let poster: ArtworkResult = await services.online.resolveArtwork(key: key)
            if Task.isCancelled { return }
            seasonHeader = SeasonHeader.make(libraryTitle: season.title, online: online, edits: edits)
            seasonHasPoster = poster != .none
        }
        // R471 item 6: the next-up episode's source (the kind line) and its file's cached tracks (Languages, Accessibility);
        // only what the index already holds, nothing read from the file here.
        .task(id: content.resumeEpisodeID) {
            guard let id = content.resumeEpisodeID, let item = try? await services.store.item(id: id) else { nextSource = nil; nextTracks = nil; return }
            let files = (try? await services.store.versions(of: id)) ?? []
            let file = PlayVersion.pick(files, explicit: item.preferredFileID, mode: .auto) ?? files.first
            let source = (try? await services.store.sources())?.first { $0.id == file?.sourceID }
            nextSource = (source?.kind, source?.name)
            if let file { nextTracks = (try? await services.store.trackDetails(fileID: file.id)) ?? nil } else { nextTracks = nil }
        }
        .pushedScreen(content.seriesTitle)
    }

    /// R471 (23): the long-press menu of one season: the season's own actions list kept to what a long press can run
    /// (`ProductActions.cardList`), each acting on THIS season (not necessarily the one on screen).
    @ViewBuilder private func seasonMenu(_ season: SeasonSection) -> some View {
        let keys: [UDEditKey] = EditTarget.seasonKeys(tmdbID: showTMDB, title: content.seriesTitle, season: season.season)
        ForEach(ProductActions.cardList(seasonContext(season)), id: \.self) { action in
            switch action {
            case .rate:
                RateMenu(current: services.ledger.rating(for: keys), title: "Rate \(season.title)") { chosen in
                    Task { await services.rate(keys: keys, itemIDs: [], stars: chosen); editRevision += 1 }
                }
            case .markAllWatched, .markAllUnwatched:
                let watched: Bool = action == .markAllWatched
                Button(watched ? "Mark \(season.title) as Watched" : "Mark \(season.title) as Unwatched", systemImage: action.symbol) {
                    pendingMarkSeason = (season, watched)
                }
            case .changeArtwork, .editMetadata:
                Button(action == .changeArtwork ? "Change \(season.title) Artwork" : "Edit \(season.title) Details", systemImage: action.symbol) {
                    editRequest = ShowEditRequest(id: "season-\(season.season)" + (action == .changeArtwork ? "-artwork" : ""),
                                                  title: "\(content.seriesTitle), \(season.title)", keys: keys,
                                                  artworkKey: ArtworkKey.seasonKey(seriesID: seriesID, number: season.season),
                                                  level: .season, startGroup: action == .changeArtwork ? .artwork : nil)
                }
            case .delete:
                Button("Delete \(season.title) from Library", systemImage: action.symbol, role: .destructive) {
                    pendingDelete = .season(seriesID: seriesID, season: season.season)
                }
            default:
                EmptyView()
            }
        }
    }

    /// R471 (23): one season's facts for its long press. Delete is for one season of several (the whole show is the page's
    /// own Delete) and is off while Restrictions are on.
    private func seasonContext(_ season: SeasonSection) -> ProductActionContext {
        var c = season.actionContext
        c.deleteAllowed = !services.restrictionsOn && content.seasons.count > 1
        return c
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
                            // R471 (23): a long press on a season's button: that season's actions.
                            .contextMenu { seasonMenu(season) }
                    } else {
                        Button { choice.wrappedValue = season.season } label: { FittingText(season.title).padding(.horizontal) }
                            .buttonStyle(.plain)
                            .contextMenu { seasonMenu(season) }
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
        // R471 item 3 (frames: show t08s and t10s): the capsule Play with the next-up episode's progress and time left, the
        // round watched check, the round details button.
        ActionRow {
            if let resume = content.resumeEpisodeID {
                let episode: EpisodeRow? = content.resumeEpisode
                PlayCapsuleButton(capsule: PlayCapsule.make(progress: episode?.progress, durationSeconds: episode?.durationSeconds)) {
                    onPlay(resume)
                }
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
            if !showMenuActions.isEmpty {
                Menu {
                    // R471 Part 3 (PROVISIONAL): the show's actions list (`ProductActions`); only actions the app has are
                    // listed (R471 (8)). Mark All asks first (system confirmation dialog).
                    ForEach(showMenuActions, id: \.self) { action in
                        switch action {
                        case .addToWatchlist, .removeFromWatchlist:
                            // R471 (61): the owner's list for a matched show (R471 (8)); the same watchlist as the movie page's "+".
                            if let id = showTMDB {
                                Button(action.title, systemImage: action.symbol) { toggleWatchlist(id) }
                            }
                        case .rate:
                            // R471 (16): the show's rating, and the season on screen's (the app only: not sent to a server).
                            RateMenu(current: showStars) { chosen in
                                showStars = chosen
                                Task { await services.rate(keys: EditTarget.showKeys(tmdbID: showTMDB, title: content.seriesTitle), itemIDs: [], stars: chosen) }
                            }
                            if let season = shownSeason {
                                let keys = EditTarget.seasonKeys(tmdbID: showTMDB, title: content.seriesTitle, season: season.season)
                                RateMenu(current: services.ledger.rating(for: keys), title: "Rate \(season.title)") { chosen in
                                    Task { await services.rate(keys: keys, itemIDs: [], stars: chosen); editRevision += 1 }
                                }
                            }
                        case .addToList, .addToPlaylistOrCollection:
                            // R471 (17): the user's lists of the action's kinds, checked where the show is in one.
                            if let ref = showRef {
                                AddToListMenu(action: action, ref: ref) { list in
                                    services.toggleList(list, ref: ref, title: content.seriesTitle)
                                } onNew: { kind in
                                    naming = ListNameRequest(kind: kind, title: content.seriesTitle, ref: { ref })
                                }
                            }
                        case .markAllWatched, .markAllUnwatched:
                            Button(action.title, systemImage: action.symbol) { pendingMarkAll = action }
                        case .manage:
                            // R471 (11): Edit Details for the show, and for the season on screen (the season's own edits).
                            Menu(action.title, systemImage: action.symbol) {
                                // R471 (13): Change Artwork for the show (the edit screen opened on Artwork).
                                let artwork = ProductAction.changeArtwork
                                Button(artwork.title, systemImage: artwork.symbol) {
                                    editRequest = ShowEditRequest(id: "show-artwork", title: content.seriesTitle,
                                                                  keys: EditTarget.showKeys(tmdbID: showTMDB, title: content.seriesTitle),
                                                                  artworkKey: "series-\(seriesID)", level: .show, startGroup: .artwork)
                                }
                                let edit = ProductAction.editMetadata
                                Button(edit.title, systemImage: edit.symbol) {
                                    editRequest = ShowEditRequest(id: "show", title: content.seriesTitle,
                                                                  keys: EditTarget.showKeys(tmdbID: showTMDB, title: content.seriesTitle),
                                                                  artworkKey: "series-\(seriesID)", level: .show)
                                }
                                if let season = shownSeason {
                                    Button("Edit \(season.title) Details", systemImage: edit.symbol) {
                                        editRequest = ShowEditRequest(id: "season-\(season.season)", title: "\(content.seriesTitle), \(season.title)",
                                                                      keys: EditTarget.seasonKeys(tmdbID: showTMDB, title: content.seriesTitle,
                                                                                                  season: season.season),
                                                                      // R471 (22): the season's poster key, so its gallery lists the season's own picture.
                                                                      artworkKey: ArtworkKey.seasonKey(seriesID: seriesID, number: season.season),
                                                                      level: .season)
                                    }
                                }
                                // R471 (18): Refresh Details for the show (its seasons and episodes with it): a real refetch.
                                if ProductActions.manageList(showActions).contains(.refreshMetadata) {
                                    let refresh = ProductAction.refreshMetadata
                                    Button(refresh.title, systemImage: refresh.symbol) {
                                        Task { refreshOutcome = await services.online.refreshTitle(.show(seriesID: seriesID)); editRevision += 1 }
                                    }
                                }
                                // R471 (12): Fix Match for the whole show, on the existing screen opened at The Whole Show
                                // through one of its episodes; off while Restrictions are on (R460).
                                if ProductActions.manageList(showActions).contains(.fixMatch), let episodeID = anyEpisodeID {
                                    let fix = ProductAction.fixMatch
                                    Button(fix.title, systemImage: fix.symbol) { fixMatchEpisode = FixMatchRequest(id: episodeID) }
                                }
                                // R471 (14): Unmatch the whole show (its seasons and episodes follow), after the confirmation.
                                if ProductActions.manageList(showActions).contains(.unmatch) {
                                    let unmatch = ProductAction.unmatch
                                    Button(unmatch.title, systemImage: unmatch.symbol, role: .destructive) { askUnmatch = true }
                                }
                                // R471 (15): Delete from Library, the whole show or the season on screen (asks first; the
                                // files stay on the source); off while Restrictions are on.
                                if ProductActions.manageList(showActions).contains(.delete) {
                                    let delete = ProductAction.delete
                                    Button(delete.title, systemImage: delete.symbol, role: .destructive) {
                                        pendingDelete = .show(seriesID: seriesID)
                                    }
                                    if let season = shownSeason, content.seasons.count > 1 {
                                        Button("Delete \(season.title) from Library", systemImage: delete.symbol, role: .destructive) {
                                            pendingDelete = .season(seriesID: seriesID, season: season.season)
                                        }
                                    }
                                }
                            }
                        default:
                            EmptyView()
                        }
                    }
                } label: {
                    // R471 item 3: the frames' round details button (a page glyph), still named "More".
                    ActionLabel("More", systemImage: "doc.text", iconOnly: true)
                }
                // R396 (audit SF2): a round icon button beside Play, as on the TV app's show page (picture A4).
                .roundAction()
                .accessibilityLabel("More")
                .accessibilityIdentifier(ControlID.more)
                .confirmationDialog(pendingMarkAll?.title ?? "", isPresented: Binding(get: { pendingMarkAll != nil },
                                                                                       set: { if !$0 { pendingMarkAll = nil } })) {
                    if let action = pendingMarkAll {
                        Button(action.title) {
                            Task { await model.run { await $0.markSeries(watched: action == .markAllWatched) } }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(pendingMarkAll == .markAllWatched ? "Every episode of this show will be marked as watched."
                                                           : "Every episode of this show will be marked as unwatched.")
                }
            }
        }
    }

    /// R471 Part 3: the facts the show's actions list depends on. The page is the show (a season page is this page on that
    /// season, so the show's list applies).
    private var showActions: ProductActionContext {
        var c = ProductActionContext(kind: .show)
        c.someUnwatched = content.canMarkWatched
        c.someWatched = content.canMarkUnwatched
        c.matched = showTMDB != nil
        c.onWatchlist = onWatchlist
        // R460: Fix Match lists catalogue titles that are not in the library, so it is off while Restrictions are on.
        c.fixMatchAllowed = OnlineTitleSurface.fixMatchCandidates.isAvailable(restricted: services.restrictionsOn)
        // R471 (15): Delete from Library is off while Restrictions are on.
        c.deleteAllowed = !services.restrictionsOn
        return c
    }

    /// R471 (14): the Unmatch confirmation for this show.
    /// R471 (15): the Delete from Library confirmation for the show or the season asked about.
    private var deleteText: (title: String, message: String, button: String) {
        guard case .season(_, let number)? = pendingDelete, let season = content.seasons.first(where: { $0.season == number }) else {
            return LibraryRemover.confirmation(.show(seriesID: seriesID), title: content.seriesTitle,
                                               episodeCount: content.seasons.reduce(0) { $0 + $1.episodes.count })
        }
        return LibraryRemover.confirmation(.season(seriesID: seriesID, season: number), title: "\(content.seriesTitle), \(season.title)",
                                           episodeCount: season.episodes.count)
    }

    private var unmatchText: (title: String, message: String, button: String) {
        Unmatcher.confirmation(.show(seriesID: seriesID, title: content.seriesTitle), title: content.seriesTitle,
                               episodeCount: content.seasons.reduce(0) { $0 + $1.episodes.count })
    }

    /// One of the show's episodes: the next-up one, else the first. Fix Match for the whole show goes through it.
    private var anyEpisodeID: Int64? { content.resumeEpisodeID ?? content.seasons.first?.episodes.first?.id }

    /// The entries of the show's list this page can act on today (R471 (61): the watchlist of a matched show, then Mark All,
    /// and Manage with Edit Details, R471 (11)); the rest of the list is not built for a show.
    private var showMenuActions: [ProductAction] {
        ProductActions.list(showActions).filter { [.addToWatchlist, .removeFromWatchlist,
                                                   .addToList, .addToPlaylistOrCollection, .rate, .markAllWatched, .markAllUnwatched, .manage].contains($0) }
    }

    /// R471 (61): whether the show is on the watchlist (the user layer, R456 sync), under the show's kind.
    private func refreshWatchlist() {
        onWatchlist = WatchlistMembership.contains(services.ledger.watchlist(), kind: .series, tmdbID: showTMDB)
    }

    /// R471 (61): adds or removes the show, as the movie page's "+" does for a movie.
    private func toggleWatchlist(_ tmdbID: Int) {
        if onWatchlist {
            services.ledger.removeFromWatchlist(kind: TitleKind.series.rawValue, tmdbID: tmdbID)
        } else {
            services.ledger.addToWatchlist(UDWatchlistEntry(kind: TitleKind.series.rawValue, tmdbID: tmdbID,
                                                            title: content.seriesTitle, addedAt: Date()))
        }
        refreshWatchlist()
    }
}

/// R471 (11): one edit screen opened from the show page (the show itself, or the season on screen).
struct ShowEditRequest: Identifiable {
    let id: String
    let title: String
    let keys: [UDEditKey]
    /// The artwork galleries' key ("series-N", or a season's "season-N-S" since R471 (22)); nil: no gallery.
    let artworkKey: String?
    let level: ArtworkGalleryKind.Level
    /// R471 (13): the group the screen opens on (Artwork for Change Artwork); nil: the list of groups.
    var startGroup: UDEditField.Group? = nil
}

/// R471 (12): the episode Fix Match for the whole show is opened through.
struct FixMatchRequest: Identifiable {
    let id: Int64
}
