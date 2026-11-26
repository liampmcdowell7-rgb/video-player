import XCTest
@testable import ScreenChecks

/// R471 (27) onwards, PROVISIONAL: differences the frame-by-frame audit of the product pages found, one check per fix.
/// Structure only, from the source: nothing is compiled or run on tvOS here, and nothing here proves the look.
extension ScreenChecksTests {
    /// R471 (27): the Information, Languages and Accessibility headings are a large bold system style.
    func testTheInfoColumnHeadingsAreLargeAndBold() throws {
        guard let sections = try appSource("App/Shared/ProductSectionsView.swift") else { return }
        XCTAssertTrue(sections.contains("Text(heading)\n                .font(.title3.weight(.bold))"), "the column heading style")
    }

    /// R471 (29): an episode's list entry is named "Show: Episode", interpolated, not the literal text.
    func testAnEpisodesListNameIsInterpolated() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        XCTAssertTrue(detail.contains(#"return "\(content.title): \(episode)""#))
        XCTAssertFalse(detail.contains(#"return "(content.title): (episode)""#))
    }

    /// R471 (30): both product pages give the About card their genres; the card shows the line under the title.
    func testTheAboutCardHasTheGenreLine() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let seasons = try appSource("App/Features/Shows/SeasonsList.swift"),
              let sections = try appSource("App/Shared/ProductSectionsView.swift") else { return }
        XCTAssertTrue(detail.contains("guidance: nil,\n                                 genres: details?.genres ?? [])"))
        XCTAssertTrue(seasons.contains("guidance: guidance,\n                                 genres: details?.genres ?? [])"))
        let title = try XCTUnwrap(sections.range(of: "FittingText(title, style: .headline)"))
        let genre = try XCTUnwrap(sections.range(of: "AboutGenres.line(genres)"))
        let summary = try XCTUnwrap(sections.range(of: "Text(summary)"))
        XCTAssertTrue(title.lowerBound < genre.lowerBound && genre.lowerBound < summary.lowerBound, "title, genres, synopsis")
    }

    /// R471 (31): Go to Season opens the show page on the episode's season (its own route), not the Go to Show route.
    func testGoToSeasonOpensTheEpisodesSeason() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let routes = try appSource("App/Shell/RouteDestinations.swift"),
              let series = try appSource("App/Features/Shows/SeriesView.swift"),
              let seasons = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        XCTAssertTrue(detail.contains("Route.seriesSeason(seriesID, season: $0)"))
        XCTAssertTrue(detail.contains("ProductAction.goToSeasonTitle(content.season)"))
        XCTAssertTrue(routes.contains("SeriesView(seriesID: id, startSeason: season)"))
        XCTAssertTrue(series.contains("startSeason: startSeason)"))
        XCTAssertTrue(seasons.contains("chosen: chosenSeason ?? startSeason"), "the person's own tab choice still wins")
    }

    /// R471 (38): the actions menu's Audio and Subtitles rows list the file's tracks, and the player applies a title's own pick.
    func testAudioAndSubtitlesInTheMenuReachThePlayer() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let menu = try appSource("App/Features/Detail/TrackChoiceMenu.swift"),
              let start = try appSource("App/Features/Player/StartTrackChoice.swift"),
              let player = try appSource("App/Features/Player/PlayerCoordinator.swift") else { return }
        XCTAssertTrue(detail.contains("case .audio, .subtitles:"))
        XCTAssertTrue(detail.contains("TrackChoiceMenu(kind:"))
        XCTAssertTrue(detail.contains("c.hasTracks ="))
        XCTAssertTrue(menu.contains(".pickerStyle(.menu)"), "a system menu picker, not custom rows")
        XCTAssertTrue(menu.contains("StartTrackChoice.keep(choice, itemID: itemID)"))
        XCTAssertTrue(start.contains("ItemTrackMenu.startChoice(item: itemChoice(itemID"), "a title's own pick wins at the start")
        XCTAssertTrue(player.contains("StartTrackChoice.apply(to: item, seriesTitle: resolved.content.seriesTitle, itemID: itemID)"))
        XCTAssertTrue(player.contains("StartTrackChoice.remember(from: item, seriesTitle: resolved.content.seriesTitle, itemID: itemID)"))
    }

    /// R471 (39): the show page has its own Trailers and Bonus Content between the episodes and Related, and a card plays
    /// the show's extra (found again by the show, not by a title).
    func testTheShowPageHasItsOwnExtrasUnderTheEpisodes() throws {
        guard let page = try appSource("App/Features/Shows/SeasonsList.swift"),
              let shelf = try appSource("App/Shared/ProductSectionsView.swift"),
              let resolve = try appSource("App/Support/ExtraPlayback.swift") else { return }
        let names = ["EpisodeShelfRow(episodes:", "ExtrasShelf(heading: ExtraShelves.trailersHeading", "ExtrasShelf(heading: ExtraShelves.bonusHeading",
                     "RelatedShowsShelf(shows: relatedShows", "CastShelf(cast: cast)"]
        let offsets: [Int] = try names.map { (name: String) -> Int in
            let range: Range<String.Index> = try XCTUnwrap(page.range(of: name), "no \(name)")
            return page.distance(from: page.startIndex, to: range.lowerBound)
        }
        XCTAssertEqual(offsets, offsets.sorted(), "episodes, Trailers, Bonus Content, Related, cast")
        XCTAssertTrue(page.contains("ShowExtras.rows(showExtras, season: shownSeason?.season)"), "the whole show's and the season on screen")
        XCTAssertTrue(page.contains(#".task(id: "extras-\(seriesID)|\(services.libraryRevision)")"#), "found again when the library changes")
        XCTAssertTrue(shelf.contains("ExtraPlayRequest(itemID: itemID, extraID: extra.id, seriesID: seriesID)"))
        XCTAssertTrue(resolve.contains("ShowExtras.find(seriesID: seriesID, extraID: extraID, store: store)"))
    }
    /// R471 (40): a Related card shows one line, the kind and the shared genre, only while it has focus; other shelves keep
    /// their titles.
    func testRelatedCardsCaptionOnlyOnFocus() throws {
        guard let caption = try appSource("App/Shared/FocusOnlyCaption.swift"),
              let poster = try appSource("App/Shared/PosterCard.swift"),
              let series = try appSource("App/Features/Shows/SeriesCard.swift"),
              let movieShelf = try appSource("App/Shared/ProductSectionsView.swift"),
              let showShelf = try appSource("App/Features/Shows/RelatedShowsShelf.swift"),
              let grid = try appSource("App/Shared/PosterGrid.swift") else { return }
        XCTAssertTrue(caption.contains(#"@Environment(\.isFocused)"#))
        XCTAssertTrue(caption.contains(".opacity(isFocused ? 1 : 0)"), "hidden by opacity, so the row keeps its height")
        XCTAssertTrue(poster.contains("if let focusCaption {") && series.contains("if let focusCaption {"))
        XCTAssertTrue(movieShelf.contains("PosterCard(card: card, focusCaption: RelatedCaption.text(kind: .movie"))
        XCTAssertTrue(showShelf.contains("SeriesCard(series: show, focusCaption: RelatedCaption.text(kind: .show"))
        XCTAssertFalse(grid.contains("focusCaption"), "a library grid keeps its titles")
    }

    /// R471 (42): the age card's source line is primary semibold, its descriptors run to four lines, and the About row's
    /// two cards are one height.
    func testTheAgeCardTextAndTheCardsHeight() throws {
        guard let sections = try appSource("App/Shared/ProductSectionsView.swift") else { return }
        XCTAssertTrue(sections.contains("FittingText(source, style: .callout)\n                                    .fontWeight(.semibold)"))
        XCTAssertFalse(sections.contains("FittingText(source, style: .caption)"), "no longer a secondary caption")
        XCTAssertTrue(sections.contains(".font(.callout)\n                                    .lineLimit(4, reservesSpace: false)"))
        let about = try XCTUnwrap(sections.range(of: "struct AboutSection"))
        let rest = String(sections[about.lowerBound...])
        XCTAssertTrue(rest.contains(".fixedSize(horizontal: false, vertical: true)"), "the row takes its natural height")
        XCTAssertEqual(rest.components(separatedBy: "maxHeight: .infinity").count - 1, 2, "each card fills it")
    }

    /// R471 (46): Home's featured area: the page's kind line, three lines of synopsis, the Play capsule, the info button.
    func testHomeFeaturedFollowsTheHomePhoto() throws {
        guard let home = try appSource("App/Features/Home/HomeFeaturedView.swift") else { return }
        // R471 (86): with the source's glyph, found from the card's file.
        XCTAssertTrue(home.contains("HeroKindLineView(segments: featured.kindLine(source: sourceKind, genres: genres, rating: rating))"))
        XCTAssertTrue(home.contains("sourceKind = (try? await services.store.sources())?.first { $0.id == file?.sourceID }?.kind"))
        XCTAssertTrue(home.contains(".lineLimit(HomeFeatured.synopsisLines)"))
        XCTAssertTrue(home.contains("PlayCapsuleButton(capsule: PlayCapsule.make(progress: featured.card.progress"))
        XCTAssertFalse(home.contains(".buttonStyle(.borderedProminent)"), "no prominent button left on Home")
        XCTAssertTrue(home.contains(#"ActionLabel("More", systemImage: "info", iconOnly: true)"#))
        XCTAssertFalse(home.contains("BadgeRow("), "the format badges stay on the page")
    }

    /// R471 (47): a product page's hero description shows up to four lines; other synopsis links keep three.
    func testTheHeroDescriptionShowsFourLines() throws {
        guard let hero = try appSource("App/Shared/HeroLinesView.swift"),
              let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let lines = try appSource("Packages/VideoPlayerCore/Sources/AppLogic/HeroLines.swift") else { return }
        XCTAssertTrue(hero.contains("lines: HeroLines.descriptionLines)"))
        XCTAssertTrue(lines.contains("public static let descriptionLines = 4"))
        XCTAssertTrue(detail.contains(".lineLimit(lines, reservesSpace: reservesSpace)"))
        XCTAssertTrue(detail.contains("var lines: Int = 3"), "the show page's info block keeps three")
    }

    /// R471 (48): cards, backdrops and cast photos are decoded at their display size, not whole (no AsyncImage left there).
    func testPicturesAreDecodedAtTheirDisplaySize() throws {
        guard let fitted = try appSource("App/Shared/FittedImage.swift"),
              let artwork = try appSource("App/Shared/ArtworkView.swift"),
              let backdrop = try appSource("App/Shared/BackdropView.swift"),
              let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        XCTAssertTrue(fitted.contains("CGImageSourceCreateThumbnailAtIndex(source, 0, options)"))
        XCTAssertTrue(fitted.contains("kCGImageSourceShouldCacheImmediately: true"), "decoded off the main thread, before it is drawn")
        XCTAssertTrue(fitted.contains("ImageSizing.maxPixelSize("))
        XCTAssertTrue(fitted.contains("if new != size { size = new }"), "the size is written only when it changes")
        for (name, text) in [("ArtworkView", artwork), ("BackdropView", backdrop), ("ItemDetailContentView", detail)] {
            XCTAssertTrue(text.contains("FittedImage(url: url, session: services.online.imageSession)"), name)
            XCTAssertFalse(text.contains("AsyncImage("), "\(name) still decodes whole files")
        }
    }

    /// R471 (49): no library grid card is hidden by its scroll visibility (R443's whole-row rule showed one row at a time,
    /// and one Down passed over the hidden rows).
    func testNoGridCardIsHiddenWhileScrolling() throws {
        guard let layout = try appSource("App/Shared/PosterGridLayout.swift"),
              let poster = try appSource("App/Shared/PosterCard.swift"),
              let series = try appSource("App/Features/Shows/SeriesCard.swift") else { return }
        for (name, text) in [("PosterGridLayout", layout), ("PosterCard", poster), ("SeriesCard", series)] {
            XCTAssertFalse(text.contains(".wholeRowOnly()"), name)
            XCTAssertFalse(text.contains("onScrollVisibilityChange(threshold: 0.98)"), name)
            XCTAssertFalse(text.contains(".opacity(whole ? 1 : 0)"), name)
        }
        XCTAssertTrue(layout.contains("LazyVGrid(columns:"), "the grid stays lazy: built rows keep their focus order")
        XCTAssertTrue(layout.contains(".focusSection()"), "R361's focus section is kept")
        XCTAssertTrue(layout.contains("if let header { header }"), "R443 item 1: the controls stay the grid's header")
    }

    /// R471 (50): the below-hero material is in the tree only while it shows, and measures are written only on a change of
    /// half a point or more.
    func testScrollingWritesAndLayersAreKeptDown() throws {
        guard let backdrop = try appSource("App/Shared/BackdropView.swift"),
              let fitting = try appSource("App/Shared/FittingLine.swift") else { return }
        XCTAssertTrue(backdrop.contains("if belowHero {"), "the second material only while it shows")
        XCTAssertFalse(backdrop.contains(".opacity(belowHero ? 1 : 0)"), "no invisible material kept in the tree")
        XCTAssertTrue(backdrop.contains("if abs(frame.height - height) >= 0.5"))
        XCTAssertTrue(backdrop.contains("if abs(frame.minY - top) >= 0.5"))
        XCTAssertTrue(fitting.contains("if abs(width - available) >= 0.5 { available = width }"))
        XCTAssertTrue(fitting.contains("if abs(width - natural) >= 0.5 { natural = width }"))
        XCTAssertTrue(fitting.contains("if abs(width - (widths[candidate] ?? -1)) >= 0.5 { widths[candidate] = width }"))
        XCTAssertFalse(fitting.contains("action: { available = $0 }"))
    }

    /// R471 (51): the grids and Home's shelves record each focus move and slow frames, in memory, with no titles; Settings >
    /// Playback shows them.
    func testScrollDiagnosticsAreWiredAndShown() throws {
        guard let recorder = try appSource("App/Shared/ScrollDiagnosticsRecorder.swift"),
              let layout = try appSource("App/Shared/PosterGridLayout.swift"),
              let grid = try appSource("App/Shared/PosterGrid.swift"),
              let shows = try appSource("App/Features/Shows/ShowsView.swift"),
              let person = try appSource("App/Features/Detail/PersonView.swift"),
              let home = try appSource("App/Features/Home/HomeRows.swift"),
              let shelf = try appSource("App/Shared/CardRow.swift"),
              let settings = try appSource("App/Features/Settings/PlaybackSettingsView.swift") else { return }
        XCTAssertTrue(layout.contains(".scrollDiagnostics(screen: screen, columns: listView ? 1 : 5)"))
        XCTAssertTrue(home.contains(#".scrollDiagnostics(screen: "Home", columns: nil)"#))
        XCTAssertTrue(home.contains(".environment(\\.focusShelf, index + 1)"))
        for (name, text) in [("PosterGrid", grid), ("ShowsView", shows), ("PersonView", person), ("CardRow", shelf)] {
            XCTAssertTrue(text.contains(".focusCell(index:"), name)
        }
        XCTAssertTrue(recorder.contains("if now.isScrolling, !screen.isEmpty { timer.start(screen: screen) } else { timer.stop() }"),
                      "the display link runs only while a page scrolls")
        XCTAssertTrue(recorder.contains("ScrollDiagnosticsStore.shared.add(scroll)"), "frames reach the store once a scroll ends")
        XCTAssertFalse(recorder.contains("UserDefaults"), "memory only")
        XCTAssertFalse(recorder.contains("AppStorage"), "memory only")
        XCTAssertFalse(recorder.contains(".title"), "no titles in the log")
        XCTAssertTrue(settings.contains("diagnostics.trail.rows") && settings.contains("diagnostics.frames.rows"))
        XCTAssertEqual(settings.components(separatedBy: "SettingsRowID.last").count - 1, 2,
                       "the page's last row is now in Scrolling Speed (empty or not)")
    }

    /// R471 (52): on the other pages that stack rows, no Down press can pass over a row: the product pages are a plain
    /// (built) stack whose every row is its own focus section, Home's shelves are lazy but none is screen tall and none is
    /// hidden, and no page scrolls by itself (no paging, scroll position or visibility hiding).
    func testNoOtherPageCanPassOverARow() throws {
        guard let movie = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let show = try appSource("App/Features/Shows/SeasonsList.swift"),
              let sections = try appSource("App/Shared/ProductSectionsView.swift"),
              let related = try appSource("App/Features/Shows/RelatedShowsShelf.swift"),
              let season = try appSource("App/Features/Shows/SeasonHeaderRow.swift"),
              let home = try appSource("App/Features/Home/HomeRows.swift"),
              let shelf = try appSource("App/Shared/CardRow.swift"),
              let search = try appSource("App/Features/Search/SearchView.swift") else { return }
        XCTAssertTrue(movie.contains("ScrollView {\n            VStack(alignment: .leading) {\n                hero"), "movie and episode pages: every row built")
        XCTAssertTrue(show.contains("ScrollView {\n            VStack(alignment: .leading) {"), "show page: every row built")
        XCTAssertEqual(sections.components(separatedBy: ".productPageRow()").count - 1, 4, "Extras, Related, About, the columns")
        XCTAssertTrue(related.contains(".productPageRow()") && season.contains(".productPageRow()"))
        XCTAssertTrue(movie.contains("struct CastShelf") && movie.contains(".productPageRow()"))
        XCTAssertEqual(show.components(separatedBy: ".productPageRow()").count - 1, 2, "season tabs and the episodes")
        XCTAssertTrue(home.contains("LazyVStack(alignment: .leading)"))
        XCTAssertFalse(shelf.contains("containerRelativeFrame(.vertical"), "no shelf is sized to the screen's height")
        XCTAssertTrue(search.contains(#"PosterGrid(cards: cards, screen: "Search")"#), "Search is a library grid (R471 (49))")
        for (name, text) in [("movie", movie), ("show", show), ("home", home), ("shelf", shelf), ("search", search)] {
            XCTAssertFalse(text.contains("scrollTargetBehavior"), name)
            XCTAssertFalse(text.contains("scrollPosition("), name)
            XCTAssertFalse(text.contains("onScrollVisibilityChange(threshold:"), name)
        }
    }

    /// R471 (45): a cast name is headline size (as the About title), its role caption and secondary (as the genre line).
    func testCastNamesMatchTheAboutTitle() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        XCTAssertTrue(detail.contains("CastCaption(text: person.name, style: .headline)"))
        XCTAssertTrue(detail.contains("CastCaption(text: role, style: .caption)\n                                    .foregroundStyle(.secondary)"))
    }

    /// R471 (56): the platter behind a focused episode card's text has round corners (frame show t06s), scaled with the text.
    func testTheFocusedEpisodeCardsPlatterIsRounded() throws {
        guard let cards = try appSource("App/Features/Shows/EpisodeCards.swift") else { return }
        XCTAssertTrue(cards.contains("in: RoundedRectangle(cornerRadius: platterCorner, style: .continuous))"))
        XCTAssertTrue(cards.contains("@ScaledMetric(relativeTo: .caption) private var platterCorner: CGFloat = 12"))
    }
}
