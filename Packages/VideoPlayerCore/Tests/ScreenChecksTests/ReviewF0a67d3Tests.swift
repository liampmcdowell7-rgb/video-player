import XCTest
@testable import ScreenChecks

/// R400 to R408 (owner's review of the screenshot run on f0a67d3): each fix checked from the app's source (structure only:
/// nothing is compiled or run on tvOS here). The look itself waits for the next run.
extension ScreenChecksTests {
    /// The body of `struct <name>` (or of the first `func <name>`) in `source`.
    private func reviewBody(of declaration: String, in source: String) throws -> String {
        let start: String.Index = try XCTUnwrap(source.range(of: declaration)?.lowerBound, "no \(declaration)")
        return String(try XCTUnwrap(Self.braceBody(of: source, after: start), "the body of \(declaration)"))
    }

    /// R400 (item 1): the dark grey of a task cover is drawn by the page INSIDE the cover's navigation stack; every page a
    /// cover can show takes it. R412: without `scrollContentBackground`, whose Apple page lists no tvOS.
    func testTaskCoverPagesDrawTheGreyInsideTheirNavigationStack() throws {
        guard let pane = try appSource("App/Shared/SettingsPane.swift"),
              let entry = try appSource("App/Shared/TextEntryPage.swift"),
              let long = try appSource("App/Shared/LongTextPage.swift") else { return }
        let background: String = try reviewBody(of: "struct TaskCoverPageBackground: ViewModifier {", in: pane)
        XCTAssertTrue(background.contains("@Environment(\\.isInTaskCover)"), "the grey is not limited to task covers")
        XCTAssertFalse(background.contains(".scrollContentBackground("), "scrollContentBackground is not available on tvOS (R412)")
        // R414: the layers moved into `TaskCoverFill`, shared with the cover's root (TaskCoverChrome).
        XCTAssertTrue(background.contains(".modifier(TaskCoverFill())"), "the page does not draw the cover's layers")
        let fill: String = try reviewBody(of: "struct TaskCoverFill: ViewModifier {", in: pane)
        XCTAssertTrue(fill.contains(".background(.regularMaterial, ignoresSafeAreaEdges: .all)"), "no material behind the page")
        XCTAssertTrue(fill.contains(".background(BackgroundStyle(), ignoresSafeAreaEdges: .all)"), "the page is not opaque under the material")
        if let material = fill.range(of: ".regularMaterial"), let opaque = fill.range(of: "BackgroundStyle(), ignoresSafeAreaEdges") {
            XCTAssertLessThan(material.lowerBound, opaque.lowerBound, "the opaque background is drawn above the material")
        }
        XCTAssertTrue(try reviewBody(of: "struct TaskPage<Content: View>: View {", in: pane).contains(".taskCoverPageBackground()"), "TaskPage draws no cover grey")
        XCTAssertTrue(try reviewBody(of: "struct SettingsPane<Content: View>: View {", in: pane).contains(".taskCoverPageBackground()"), "SettingsPane draws no cover grey")
        XCTAssertTrue(entry.contains(".taskCoverPageBackground()"), "the entry page draws no cover grey")
        XCTAssertTrue(long.contains(".taskCoverPageBackground()"), "the long text page draws no cover grey")
    }

    /// R401 (item 2): no row of a source form has a symbol (every row or none, as Add a Source, R391).
    func testSourceFormRowsHaveNoSymbols() throws {
        guard let form = try appSource("App/Features/Sources/SourceFormView.swift") else { return }
        XCTAssertFalse(form.contains("systemImage:"), "a row of a source form still has a symbol")
        XCTAssertTrue(form.contains("FittingText(\"Search Your Network\")"), "Search Your Network is not a plain title")
        XCTAssertTrue(form.contains("FittingText(SourceAboutText.title(info))"), "About is not a plain title")
    }

    /// R402 (items 3 and 4): Home's and Discover's shelves leave the shared room for the lifted card above and below, and
    /// are as tall as their tallest caption; a Discover title follows rule S1 (`CardCaption`).
    func testShelvesLeaveRoomForTheLiftedCardAndTheirTallestCaption() throws {
        guard let row = try appSource("App/Shared/CardRow.swift"),
              let discover = try appSource("App/Features/Discover/DiscoverView.swift") else { return }
        let card: String = try reviewBody(of: "struct CardRow: View {", in: row)
        XCTAssertEqual(card.components(separatedBy: ".padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))").count - 1, 2, "Home's shelf has no room under its header and under its cards")
        XCTAssertTrue(card.contains(".fixedSize(horizontal: false, vertical: true)"), "Home's shelf does not take its cards' own height")
        XCTAssertTrue(discover.contains(".padding(.top, CGFloat(RowSpacing.shelfFocusRoom))"), "Discover's shelf has no room above its cards")
        XCTAssertTrue(discover.contains(".padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))"), "Discover's shelf has no room under its cards")
        XCTAssertTrue(discover.contains("CardCaption(text: title.title)"), "a Discover title is not the S1 caption")
        XCTAssertFalse(discover.contains("Text(title.title)"), "a Discover title still wraps in Caption")
    }

    /// R403 (item 5): Recent Searches and its Clear button at the top leading edge, the button the plain bordered style.
    func testRecentSearchesSitAtTheTopLeadingEdgeInThePlainStyle() throws {
        guard let search = try appSource("App/Features/Search/SearchView.swift") else { return }
        XCTAssertFalse(search.contains("role: .destructive"), "Clear Recent Searches is still drawn as destructive")
        XCTAssertTrue(search.contains(".buttonStyle(.bordered)"), "Clear Recent Searches is not the plain bordered button")
        XCTAssertTrue(search.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"), "the search page is still centred as large as its content")
    }

    /// R404 (item 6 b): without content advice nothing is put into the hero's stack.
    func testEmptyContentAdviceIsNotPutIntoThePage() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let seasons = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        for (name, text) in [("movie page", detail), ("show page", seasons)] {
            XCTAssertFalse(text.contains("ContentAdviceLine(descriptors: details?.contentDescriptors ?? [])"), "the \(name) still puts an empty advice line into its stack")
        }
        // R471 (83): the show page's hero has no advice line either (frames show t08s, t10s); its Information column has the row.
        XCTAssertFalse(seasons.contains("ContentAdviceLine("), "the show page still has the advice line on the hero")
        XCTAssertTrue(seasons.contains("advisories: details?.contentDescriptors ?? []"), "the show page's Information does not take the advice")
        // R471 item 4: the movie and episode pages show the advice as the Information column's row ("Content Advisories"),
        // which `ProductInfo.information` leaves out when there is none (ProductSectionsTests).
        XCTAssertFalse(detail.contains("ContentAdviceLine("), "the movie page still has the advice line on the hero")
        // R471 (85): the advice is the title's own, else (an episode) its show's.
        XCTAssertTrue(detail.contains("rating: rating, advisories: advisories,"), "the movie page's Information does not take the advice")
        XCTAssertTrue(detail.contains("EpisodePage.borrowed(details?.contentDescriptors, series: seriesDetails?.contentDescriptors)"),
                      "an episode does not borrow its show's content advice")
    }

    /// R471 (85): an episode's kind line and Information borrow the show's genres and regions when its own have none
    /// (frames episode t00s, t02s).
    func testAnEpisodeBorrowsItsShowsGenresAndRegions() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        XCTAssertTrue(detail.contains("EpisodePage.borrowed(details?.genres, series: seriesDetails?.genres)"), "no borrowed genres")
        XCTAssertTrue(detail.contains("source: content.sourceKind, genres: genres,"), "the kind line does not use the borrowed genres")
        XCTAssertTrue(detail.contains("EpisodePage.borrowed(details?.regions, series: seriesDetails?.regions)"), "no borrowed regions")
        XCTAssertTrue(detail.contains("EpisodePage.needsSeriesDetails("), "the show's details are not asked for")
    }

    /// R471 (84): the show hero's facts line takes the next-up episode's year and length (frames show t08s, t10s).
    func testTheShowHeroFactsLineSpeaksForTheNextUpEpisode() throws {
        guard let seasons = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        XCTAssertTrue(seasons.contains("HeroLines.showFactsText(nextEpisodeDate:"), "the show hero's facts line is not the next-up episode's")
        XCTAssertTrue(seasons.contains("nextEpisodeSeconds: content.resumeEpisode?.durationSeconds"), "the show hero gives no length")
    }

    /// R471 (87): the "needs the key" line stands in the description's place, before the facts line, on the show page as on
    /// the movie page.
    func testTheNeedsTheKeyLineComesBeforeTheFactsLineOnBothPages() throws {
        guard let seasons = try appSource("App/Features/Shows/SeasonsList.swift"),
              let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        for (name, text) in [("show page", seasons), ("movie page", detail)] {
            let key = try XCTUnwrap(text.range(of: "StatusText(OnlineLookupText.detailsNeedKey)"), "no key line on the \(name)")
            let facts = try XCTUnwrap(text.range(of: "HeroFactsLineView("), "no facts line on the \(name)")
            XCTAssertLessThan(key.lowerBound, facts.lowerBound, "the \(name)'s key line follows its facts line")
        }
    }

    /// R471 (92): the movie and show pages ask for the year only in Information; the episode page keeps the full date.
    func testReleasedIsTheYearOnTheMovieAndShowPages() throws {
        guard let seasons = try appSource("App/Features/Shows/SeasonsList.swift"),
              let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        XCTAssertTrue(seasons.contains("yearOnly: true)"), "the show page's Released row is not the year")
        XCTAssertTrue(detail.contains("yearOnly: content.kind == .movie)"), "the movie page's Released row is not the year")
    }

    /// R471 (97): the show hero's key line stands only where no description is shown (the hero's own description, not the
    /// show's overview alone, decides).
    func testTheShowHerosKeyLineOnlyWithoutADescription() throws {
        guard let seasons = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        XCTAssertTrue(seasons.contains("if heroDescription == nil, !services.online.hasCatalogueKey {"),
                      "the key line does not follow the hero's description")
        XCTAssertFalse(seasons.contains("if details?.overview == nil, !services.online.hasCatalogueKey {"),
                       "the key line can still sit under a next-up episode's description")
    }

    /// R471 (102): Home's Play capsule is given the featured title's length (read with the item the source glyph needs).
    func testHomePlayIsGivenTheTitlesLength() throws {
        guard let home = try appSource("App/Features/Home/HomeFeaturedView.swift") else { return }
        XCTAssertTrue(home.contains("PlayCapsule.make(progress: featured.card.progress, durationSeconds: playSeconds)"),
                      "Home's Play has no length, so no time left")
        XCTAssertTrue(home.contains("playSeconds = HomeFeatured.playSeconds(of: item)"))
        XCTAssertFalse(home.contains("durationSeconds: nil)"), "Home's Play still passes no length")
    }

    /// R471 (98): the show's Manage menu offers Change Artwork for the season on screen, next to its Edit Details, opening the
    /// season's edit screen on Artwork as the season heading's menu does.
    func testTheShowsManageMenuChangesTheSeasonsArtwork() throws {
        guard let seasons = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        let manage = try XCTUnwrap(seasons.range(of: "case .manage:"), "no Manage menu on the show page")
        let rest = seasons[manage.lowerBound...]
        let change = try XCTUnwrap(rest.range(of: "Button(\"Change \\(season.title) Artwork\", systemImage: artwork.symbol)"),
                                   "no Change Season Artwork in the Manage menu")
        let edit = try XCTUnwrap(rest.range(of: "Button(\"Edit \\(season.title) Details\", systemImage: edit.symbol)"))
        XCTAssertLessThan(change.lowerBound, edit.lowerBound, "Change Artwork comes before Edit Details, as for the show")
        let request = rest[change.lowerBound..<edit.lowerBound]
        XCTAssertTrue(request.contains("id: \"season-\\(season.season)-artwork\""))
        XCTAssertTrue(request.contains("level: .season, startGroup: .artwork)"))
    }

    /// R471 (96): the show page's episode cards are given the show's rating to fall back on.
    func testShowPageEpisodeCardsBorrowTheShowsRating() throws {
        guard let seasons = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        XCTAssertTrue(seasons.contains("hideSpoilers: hideSpoilers, seriesRating: details?.contentRating)"),
                      "the episode cards do not fall back on the show's rating")
    }

    /// R407 (item 10, A11Y1): the UI-test text-size override is applied on every pushed page too, not only around each
    /// tab's navigation stack.
    func testPushedPagesTakeTheUITestOverrides() throws {
        guard let routes = try appSource("App/Shell/RouteDestinations.swift"),
              let root = try appSource("App/Shell/RootView.swift") else { return }
        XCTAssertTrue(try reviewBody(of: "struct RouteDestinations: ViewModifier {", in: routes).contains(".uiTestAccessibilityOverrides()"), "a Route destination does not take the overrides")
        XCTAssertTrue(try reviewBody(of: "func pushedScreen(_ title: String) -> some View {", in: root).contains(".uiTestAccessibilityOverrides()"), "pushedScreen does not apply the overrides")
    }
}
