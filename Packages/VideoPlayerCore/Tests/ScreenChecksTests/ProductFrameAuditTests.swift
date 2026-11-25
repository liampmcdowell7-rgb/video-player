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
        XCTAssertTrue(home.contains("HeroKindLineView(segments: featured.kindLine(genres: genres, rating: rating))"))
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

    /// R471 (45): a cast name is headline size (as the About title), its role caption and secondary (as the genre line).
    func testCastNamesMatchTheAboutTitle() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        XCTAssertTrue(detail.contains("CastCaption(text: person.name, style: .headline)"))
        XCTAssertTrue(detail.contains("CastCaption(text: role, style: .caption)\n                                    .foregroundStyle(.secondary)"))
    }
}
