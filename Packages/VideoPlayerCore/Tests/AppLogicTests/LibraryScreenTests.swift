import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

final class LibraryScreenTests: XCTestCase {
    private let now = epoch.addingTimeInterval(100 * 86_400)

    // MARK: Home

    func testHomeWithNoSourcesSaysSo() async throws {
        let rig = try LibraryRig.make()
        var home = HomeViewModel(store: rig.store)
        await home.load(now: now)
        guard case .empty(let e) = home.state else { return XCTFail("\(home.state)") }
        XCTAssertEqual(e.reason, .noSources)
        XCTAssertEqual(e.actionTitle, "Add a Source")
    }

    func testHomeWithASourceButNothingIndexed() async throws {
        let rig = try LibraryRig.make()
        try await rig.store.upsertSource(LibrarySourceRecord(id: "s", kind: .webdav, name: "S", addedAt: epoch))
        var home = HomeViewModel(store: rig.store)
        await home.load(now: now)
        guard case .empty(let e) = home.state else { return XCTFail("\(home.state)") }
        XCTAssertEqual(e.reason, .nothingIndexed)
    }

    func testHomeShowsOnlyTheThreeLibraryRowsAndSkipsEmptyOnes() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var home = HomeViewModel(store: rig.store)
        await home.load(now: now)
        let rows = try XCTUnwrap(home.state.content)
        // Nothing watched yet: no Continue Watching, no Next Up; only Recently Added.
        XCTAssertEqual(rows.map(\.id), [.recentlyAdded])
        XCTAssertEqual(rows[0].title, "Recently Added")
        XCTAssertEqual(rows[0].cards.count, 9)
        XCTAssertTrue(Set(HomeRowID.allCases).isSuperset(of: Set(rows.map(\.id))))
        XCTAssertEqual(HomeRowID.allCases.count, 3)
    }

    func testHomeContinueWatchingShowsTimeLeftAndNextUpShowsTheEpisode() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let hexfall = try await rig.movieID("Hexfall")
        try await rig.store.updateProgress(itemID: hexfall, position: 1_800, duration: 6_000, at: now.addingTimeInterval(-3_600))
        let show = try await rig.episodes(ofSeriesTitle: "Show One")
        let first = try XCTUnwrap(show.first { $0.season == 1 && $0.episode == 1 })
        try await rig.store.markWatched(itemIDs: [first.id], watched: true, at: now.addingTimeInterval(-7_200))
        var home = HomeViewModel(store: rig.store)
        await home.load(now: now)
        let rows = try XCTUnwrap(home.state.content)
        XCTAssertEqual(rows.map(\.id), [.continueWatching, .nextUp, .recentlyAdded])
        let cont = rows[0].cards[0]
        XCTAssertEqual(cont.title, "Hexfall")
        XCTAssertEqual(cont.subtitle, "1 h 10 min left")
        XCTAssertEqual(try XCTUnwrap(cont.progress), 0.3, accuracy: 0.001)
        let next = rows[1].cards[0]
        XCTAssertEqual(next.kind, .episode)
        // Screenshot review item 3b: an episode card is titled with its show, the second line names the episode.
        XCTAssertEqual(next.title, "Show One")
        XCTAssertTrue(next.subtitle?.hasPrefix("S1 E2") == true, next.subtitle ?? "nil")
        XCTAssertFalse(next.subtitle?.contains("Show One") == true, "the show name is not repeated")
        XCTAssertNil(next.progress)
    }

    func testHomeFailureGivesACalmErrorAndRecovers() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let flaky = FlakyStore(rig.store)
        flaky.failing = true
        var home = HomeViewModel(store: flaky)
        await home.load(now: now)
        guard case .failed(let e) = home.state else { return XCTFail("\(home.state)") }
        XCTAssertEqual(e.title, "Couldn’t load your library")
        XCTAssertEqual(e.message, "The library could not be read.")
        XCTAssertEqual(e.retryTitle, "Try Again")
        flaky.failing = false
        await home.load(now: now)
        XCTAssertNotNil(home.state.content)
    }

    // MARK: Cards

    func testCardBadgesFollowTheBestVersionAndComeInAFixedOrder() {
        // Built through the real index in testGridFilters below; here only the text helpers.
        XCTAssertEqual(DisplayText.remaining(0), "Finished")
        XCTAssertEqual(DisplayText.remaining(30), "Less than a minute left")
        XCTAssertEqual(DisplayText.remaining(60 * 41), "41 min left")
        XCTAssertEqual(DisplayText.remaining(3_900), "1 h 5 min left")
        XCTAssertEqual(DisplayText.remaining(7_200), "2 h left")
        XCTAssertEqual(DisplayText.runtime(6_720), "1 h 52 min")
        XCTAssertEqual(DisplayText.runtime(10), "1 min")
        XCTAssertEqual(DisplayText.episodeCode(season: 2, episode: 5), "S2 E5")
        XCTAssertEqual(DisplayText.episodeCode(season: 1, episode: 1, episodeEnd: 2), "S1 E1-E2")
        XCTAssertNil(DisplayText.episodeCode(season: nil, episode: 1))
        XCTAssertEqual(DisplayText.fileSize(999), "999 bytes")
        XCTAssertEqual(DisplayText.fileSize(12_400_000), "12.4 MB")
        XCTAssertEqual(DisplayText.fileSize(3_100_000_000), "3.1 GB")
        XCTAssertEqual(DisplayText.seconds(1), "1 second")
        XCTAssertEqual(DisplayText.seconds(7), "7 seconds")
    }

    // MARK: Movies grid

    func testMoviesGridListsOnlyMoviesSortedByTitleWithCountAndLetters() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var grid = ItemGridViewModel.movies(store: rig.store)
        await grid.load()
        let c = try XCTUnwrap(grid.state.content)
        XCTAssertEqual(c.cards.map(\.title), ["Aftlander", "Hexfall", "Zornwick"])
        XCTAssertEqual(c.cards.map(\.subtitle), ["1979", "1995", "2007"])
        XCTAssertEqual(c.total, 3)
        XCTAssertFalse(c.hasMore)
        XCTAssertEqual(grid.countText, "3 movies")
        XCTAssertFalse(grid.isFiltered)
        XCTAssertTrue(grid.chips.isEmpty)
        XCTAssertFalse(c.alphabet.isEmpty)
    }

    func testGridPagesWithCursorsWithoutRepeatsOrGaps() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var f = ItemFilter()
        f.kinds = [.movie, .episode]
        var grid = ItemGridViewModel(store: rig.store, base: f, pageSize: 3, noun: "items")
        await grid.load()
        var c = try XCTUnwrap(grid.state.content)
        XCTAssertEqual(c.cards.count, 3)
        XCTAssertTrue(c.hasMore)
        XCTAssertEqual(c.total, 9)
        // Scrolling near the end of the loaded cards loads the next page; the far start does not.
        await grid.loadMoreIfNeeded(visible: c.cards[0].id)
        XCTAssertEqual(try XCTUnwrap(grid.state.content).cards.count, 3 + 3)
        c = try XCTUnwrap(grid.state.content)
        await grid.loadMoreIfNeeded(visible: c.cards.last!.id)
        c = try XCTUnwrap(grid.state.content)
        XCTAssertEqual(c.cards.count, 9)
        XCTAssertFalse(c.hasMore)
        XCTAssertEqual(Set(c.cards.map(\.id)).count, 9)
        let before = c.cards.count
        await grid.loadMore()
        XCTAssertEqual(try XCTUnwrap(grid.state.content).cards.count, before)
    }

    func testGridFiltersShowChipsAndClearGoesBackToTheBase() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let hexfall = try await rig.movieID("Hexfall")
        try await rig.store.markWatched(itemIDs: [hexfall], watched: true, at: now)
        var grid = ItemGridViewModel.movies(store: rig.store)
        await grid.toggle(.watch(.unwatched))
        var c = try XCTUnwrap(grid.state.content)
        XCTAssertEqual(c.cards.map(\.title), ["Aftlander", "Zornwick"])
        XCTAssertEqual(grid.chips.map(\.title), ["Unwatched"])
        XCTAssertTrue(grid.isFiltered)
        await grid.toggle(.watch(.watched))          // a watch filter is one choice: the second pick replaces it
        c = try XCTUnwrap(grid.state.content)
        XCTAssertEqual(c.cards.map(\.title), ["Hexfall"])
        XCTAssertTrue(c.cards[0].isWatched)
        let chip = try XCTUnwrap(grid.chips.first)
        await grid.removeChip(chip)
        XCTAssertFalse(grid.isFiltered)
        XCTAssertEqual(try XCTUnwrap(grid.state.content).cards.count, 3)
        await grid.toggle(.favorites)
        guard case .empty(let e) = grid.state else { return XCTFail("\(grid.state)") }
        XCTAssertEqual(e.reason, .noMatches)
        XCTAssertEqual(e.actionTitle, "Clear Filters")
        await grid.clearFilters()
        XCTAssertEqual(try XCTUnwrap(grid.state.content).cards.count, 3)
    }

    func testGridSortChoiceFlipsDirectionOnRepeatAndStartsNewKeysAtTheirDefault() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var grid = ItemGridViewModel.movies(store: rig.store)
        await grid.load()
        await grid.chooseSort(.title)                // same key: flips
        XCTAssertEqual(try XCTUnwrap(grid.state.content).cards.map(\.title), ["Zornwick", "Hexfall", "Aftlander"])
        XCTAssertEqual(grid.sortTitle, "Title, descending")
        await grid.chooseSort(.year)                 // new key: newest first
        XCTAssertEqual(try XCTUnwrap(grid.state.content).cards.map(\.title), ["Zornwick", "Hexfall", "Aftlander"])
        XCTAssertEqual(grid.sortTitle, "Year, descending")
        await grid.chooseSort(.year)
        XCTAssertEqual(try XCTUnwrap(grid.state.content).cards.map(\.title), ["Aftlander", "Hexfall", "Zornwick"])
        XCTAssertEqual(try XCTUnwrap(grid.state.content).alphabet.count, 0, "letters only for title sorts")
    }

    /// #32 B: each key names its two directions in its own words; every key on Movies and Shows has two different words.
    func testSortDirectionWordsFollowTheKey() {
        XCTAssertEqual(SortChoice.directionTitle(for: .title, ascending: true), "A to Z")
        XCTAssertEqual(SortChoice.directionTitle(for: .title, ascending: false), "Z to A")
        XCTAssertEqual(SortChoice.directionTitle(for: .added, ascending: false), "Newest First")
        XCTAssertEqual(SortChoice.directionTitle(for: .year, ascending: true), "Oldest First")
        XCTAssertEqual(SortChoice.directionTitle(for: .runtime, ascending: false), "Longest First")
        XCTAssertEqual(SortChoice.directionTitle(for: .rating, ascending: false), "Highest First")
        for choice in SortChoice.all + SortChoice.shows {
            let words = SortChoice.directionTitles(for: choice.key)
            XCTAssertNotEqual(words.ascending, words.descending, choice.title)
            XCTAssertFalse(words.ascending.contains("Largest") || words.descending.contains("Largest"), choice.title)
        }
    }

    func testSavedViewsRoundTripThroughTheIndex() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var grid = ItemGridViewModel.movies(store: rig.store)
        await grid.toggle(.watch(.unwatched))
        await grid.chooseSort(.year)
        let saved = try await grid.saveCurrentView(name: "  Next to watch  ")
        XCTAssertEqual(saved.name, "Next to watch")
        XCTAssertEqual(grid.savedViews.map(\.name), ["Next to watch"])
        await grid.clearFilters()
        await grid.setSort(ItemSort(key: .title, ascending: true))
        XCTAssertEqual(try XCTUnwrap(grid.state.content).cards.count, 3)
        await grid.apply(try XCTUnwrap(grid.savedViews.first))
        XCTAssertEqual(grid.chips.map(\.title), ["Unwatched"])
        XCTAssertEqual(grid.sortTitle, "Year, descending")
        await grid.deleteView(id: saved.id)
        XCTAssertTrue(grid.savedViews.isEmpty)
        let blank = try await grid.saveCurrentView(name: "   ")
        XCTAssertEqual(blank.name, "Saved View")
    }

    func testWatchedAndFavoriteActionsRefreshTheCardInPlace() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var grid = ItemGridViewModel.movies(store: rig.store)
        await grid.load()
        let aftlander = try XCTUnwrap(grid.state.content?.cards.first { $0.title == "Aftlander" })
        XCTAssertFalse(aftlander.isWatched)
        await grid.toggleWatched(itemID: aftlander.id)
        XCTAssertTrue(try XCTUnwrap(grid.state.content?.cards.first { $0.id == aftlander.id }).isWatched)
        await grid.toggleWatched(itemID: aftlander.id)
        XCTAssertFalse(try XCTUnwrap(grid.state.content?.cards.first { $0.id == aftlander.id }).isWatched)
        await grid.toggleFavorite(itemID: aftlander.id)
        XCTAssertTrue(try XCTUnwrap(grid.state.content?.cards.first { $0.id == aftlander.id }).isFavorite)
        XCTAssertEqual(grid.state.content?.cards.map(\.title), ["Aftlander", "Hexfall", "Zornwick"], "order is kept")
    }

    func testGridFailureKeepsTheScreenCalmAndRetryWorks() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let flaky = FlakyStore(rig.store)
        var grid = ItemGridViewModel.movies(store: flaky)
        await grid.load()
        XCTAssertNotNil(grid.state.content)
        flaky.failing = true
        await grid.load()
        guard case .failed(let e) = grid.state else { return XCTFail("\(grid.state)") }
        XCTAssertEqual(e.title, "Couldn’t load movies")
        flaky.failing = false
        await grid.load()
        XCTAssertEqual(grid.state.content?.cards.count, 3)
    }

    func testAFailingNextPageKeepsWhatIsOnScreen() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let flaky = FlakyStore(rig.store)
        var f = ItemFilter()
        f.kinds = [.movie, .episode]
        var grid = ItemGridViewModel(store: flaky, base: f, pageSize: 3)
        await grid.load()
        flaky.failing = true
        await grid.loadMore()
        XCTAssertEqual(grid.state.content?.cards.count, 3)
        flaky.failing = false
        await grid.loadMore()
        XCTAssertEqual(grid.state.content?.cards.count, 6)
    }

    func testFilterOptionsToggleAndDescribeEveryGroup() {
        var f = ItemFilter()
        FilterOption.resolution(.uhd4k).toggle(in: &f)
        FilterOption.hdr(.dolbyVision).toggle(in: &f)
        FilterOption.atmos.toggle(in: &f)
        FilterOption.minChannels(6).toggle(in: &f)
        FilterOption.genre("Drama").toggle(in: &f)
        FilterOption.favorites.toggle(in: &f)
        XCTAssertEqual(FilterDescriber.chips(for: f).map(\.title), ["4K", "Dolby Vision", "Dolby Atmos", "5.1 or more", "Drama", "Favorites"])
        for chip in FilterDescriber.chips(for: f) { FilterDescriber.remove(chip, from: &f) }
        XCTAssertEqual(f, ItemFilter())
        FilterOption.atmos.toggle(in: &f)
        FilterOption.atmos.toggle(in: &f)
        XCTAssertEqual(f, ItemFilter())
    }

    // MARK: Shows

    func testShowsListsSeriesWithCountsAndTheSpecialsDoNotCountAsASeason() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var shows = ShowsViewModel(store: rig.store)
        await shows.load()
        let list = try XCTUnwrap(shows.state.content)
        XCTAssertEqual(list.map(\.title), ["Show One", "Show Two"])
        XCTAssertEqual(list[0].episodeCount, 5)
        XCTAssertEqual(list[0].seasonCount, 2)
        XCTAssertEqual(list[0].seasonsText, "2 seasons")
        XCTAssertEqual(list[1].seasonsText, "1 season")
        XCTAssertEqual(list[0].unwatchedCount, 5)
        // #15 4.5: the count, in the same place as the Movies count.
        XCTAssertEqual(shows.countText, "2 shows")
    }

    func testShowsEmptyLibrary() async throws {
        let rig = try LibraryRig.make()
        var shows = ShowsViewModel(store: rig.store)
        await shows.load()
        guard case .empty(let e) = shows.state else { return XCTFail("\(shows.state)") }
        XCTAssertEqual(e.reason, .noSources)
        XCTAssertNil(shows.countText, "no count without shows")
    }

    func testSeasonsAreOrderedWithSpecialsLastAndPlayPicksTheRightEpisode() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await rig.episodes(ofSeriesTitle: "Show One")
        let seriesID = try XCTUnwrap(eps.first?.seriesID)
        var vm = SeasonsViewModel(store: rig.store, seriesID: seriesID)
        await vm.load()
        var c = try XCTUnwrap(vm.state.content)
        XCTAssertEqual(c.seriesTitle, "Show One")
        XCTAssertEqual(c.seasons.map(\.title), ["Season 1", "Season 2", "Specials"])
        XCTAssertEqual(c.seasons[0].episodes.map(\.code), ["S1 E1", "S1 E2", "S1 E3"])
        XCTAssertEqual(c.playTitle, "Play")
        let first = try XCTUnwrap(c.seasons[0].episodes.first)
        XCTAssertEqual(c.resumeEpisodeID, first.id)
        XCTAssertEqual(c.seasons[0].summary, "0 of 3 watched")
        XCTAssertTrue(c.canMarkWatched)
        XCTAssertFalse(c.canMarkUnwatched, "#15 5.1: nothing watched, so no Mark Show as Unwatched")

        // First two episodes watched: Play becomes Resume and points at episode 3.
        await vm.setWatched(true, episodeID: c.seasons[0].episodes[0].id)
        await vm.setWatched(true, episodeID: c.seasons[0].episodes[1].id)
        c = try XCTUnwrap(vm.state.content)
        XCTAssertEqual(c.playTitle, "Resume")
        XCTAssertEqual(c.resumeEpisodeID, c.seasons[0].episodes[2].id)
        XCTAssertEqual(c.seasons[0].summary, "2 of 3 watched")
        XCTAssertTrue(c.canMarkWatched && c.canMarkUnwatched, "partly watched: both apply")

        // A whole season at once, then the whole series.
        await vm.markSeason(1, watched: true)
        XCTAssertEqual(vm.state.content?.seasons[0].watchedCount, 3)
        XCTAssertEqual(vm.state.content?.resumeEpisodeID, vm.state.content?.seasons[1].episodes[0].id, "Season 2 is next; specials are never resumed into")
        await vm.markSeries(watched: true)
        XCTAssertEqual(vm.state.content?.playTitle, "Play Again")
        XCTAssertEqual(vm.state.content?.canMarkWatched, false, "all watched: only Mark Show as Unwatched")
        XCTAssertEqual(vm.state.content?.canMarkUnwatched, true)
        await vm.markSeries(watched: false)
        XCTAssertEqual(vm.state.content?.playTitle, "Play")
    }

    func testSeasonsOfAnUnknownSeriesIsEmptyNotAnError() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var vm = SeasonsViewModel(store: rig.store, seriesID: 987_654)
        await vm.load()
        guard case .empty = vm.state else { return XCTFail("\(vm.state)") }
    }

    func testSeasonsFailure() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let flaky = FlakyStore(rig.store)
        flaky.failing = true
        var vm = SeasonsViewModel(store: flaky, seriesID: 1)
        await vm.load()
        guard case .failed(let e) = vm.state else { return XCTFail("\(vm.state)") }
        XCTAssertEqual(e.title, "Couldn’t load this show")
    }

    // MARK: Files

    func testFilesBrowserWalksDownAndUpAndLeavesAtTheRoot() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var files = FilesBrowserViewModel(store: rig.store, sourceID: LibraryRig.sourceID, sourceName: "Test")
        XCTAssertTrue(files.isAtRoot)
        await files.load()
        var c = try XCTUnwrap(files.state.content)
        XCTAssertEqual(Set(c.rows.map(\.name)), ["Movies", "TV", "Docs"])
        XCTAssertEqual(c.breadcrumb, ["Test"])
        let movies = try XCTUnwrap(c.rows.first { $0.name == "Movies" })
        XCTAssertTrue(movies.isDirectory)
        XCTAssertNil(movies.sizeText)
        XCTAssertEqual(movies.detail, "3 items", "#15 7.3: a folder's second line is its item count")
        await files.enter(movies)
        XCTAssertFalse(files.isAtRoot)
        c = try XCTUnwrap(files.state.content)
        XCTAssertEqual(c.breadcrumb, ["Test", "Movies"])
        XCTAssertEqual(Set(c.rows.map(\.name)), ["Hexfall (1995)", "Aftlander (1979)", "Zornwick (2007)"])
        await files.enter(try XCTUnwrap(c.rows.first { $0.name == "Hexfall (1995)" }))
        c = try XCTUnwrap(files.state.content)
        let file = try XCTUnwrap(c.rows.first { !$0.isDirectory })
        XCTAssertEqual(file.name, "Hexfall (1995).mkv")
        XCTAssertEqual(file.sizeText, "10.0 KB")
        XCTAssertEqual(file.detail, "10.0 KB · MKV", "#15 7.3: a file's second line is its size and format")
        let before = files.folder
        await files.enter(file)                         // entering a file does nothing
        XCTAssertEqual(files.folder, before)
        let up1 = await files.up()
        XCTAssertTrue(up1)
        XCTAssertEqual(files.folder, "/Movies")
        let up2 = await files.up()
        XCTAssertTrue(up2)
        XCTAssertTrue(files.isAtRoot)
        let up3 = await files.up()
        XCTAssertFalse(up3, "Menu at the root leaves the screen")
    }

    /// #15 7.3: the second-line texts of the Files tab.
    func testFilesSecondLines() {
        XCTAssertEqual(FilesText.itemCount(0), "Empty")
        XCTAssertEqual(FilesText.itemCount(1), "1 item")
        XCTAssertEqual(FilesText.itemCount(12), "12 items")
        XCTAssertEqual(FilesText.itemCount(1000), "999+ items")
        XCTAssertEqual(FilesText.fileDetail(name: "a.en.srt", kind: .subtitle, size: 2048), "2.0 KB · Subtitles")
        XCTAssertNil(FilesText.fileDetail(name: "notes", kind: .other, size: nil))
        XCTAssertEqual(FilesText.sourceDetail(.smb), SourceCatalog.info(for: .smb).title)
        XCTAssertEqual(FilesText.sourceDetail(.webdav), "WebDAV")
    }

    func testFilesBrowserPagesAndShowsAnEmptyFolderAndAFailure() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var files = FilesBrowserViewModel(store: rig.store, sourceID: LibraryRig.sourceID, sourceName: "Test", pageSize: 2)
        await files.load()
        XCTAssertEqual(files.state.content?.rows.count, 2)
        XCTAssertEqual(files.state.content?.hasMore, true)
        await files.loadMore()
        XCTAssertEqual(files.state.content?.rows.count, 3)
        XCTAssertEqual(files.state.content?.hasMore, false)

        var empty = FilesBrowserViewModel(store: rig.store, sourceID: LibraryRig.sourceID, sourceName: "Test", folder: "/Nothing")
        await empty.load()
        guard case .empty(let e) = empty.state else { return XCTFail("\(empty.state)") }
        XCTAssertEqual(e.reason, .emptyFolder)

        let flaky = FlakyStore(rig.store)
        flaky.failing = true
        var broken = FilesBrowserViewModel(store: flaky, sourceID: LibraryRig.sourceID, sourceName: "Test")
        await broken.load()
        guard case .failed(let f) = broken.state else { return XCTFail("\(broken.state)") }
        XCTAssertEqual(f.title, "Couldn’t open this folder")
    }

    // MARK: Search

    func testSearchIsLibraryOnlyAndHasThreeNonResultStates() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var search = SearchViewModel(store: rig.store)
        guard case .empty(let prompt) = search.state else { return XCTFail() }
        XCTAssertEqual(prompt.reason, .noQuery)
        await search.search("hex")
        XCTAssertEqual(search.state.content?.map(\.title), ["Hexfall"])
        await search.search("  show  ")
        XCTAssertEqual(search.text, "show")
        let shows = try XCTUnwrap(search.state.content)
        XCTAssertTrue(shows.allSatisfy { $0.kind == .episode })
        XCTAssertGreaterThan(shows.count, 0)
        await search.search("zzzzqq")
        guard case .empty(let none) = search.state else { return XCTFail("\(search.state)") }
        XCTAssertEqual(none.reason, .noMatches)
        XCTAssertEqual(none.title, "No Results for “zzzzqq”")
        await search.search("   ")
        guard case .empty(let again) = search.state else { return XCTFail() }
        XCTAssertEqual(again.reason, .noQuery)
    }

    func testSearchFailure() async throws {
        let rig = try LibraryRig.make()
        let flaky = FlakyStore(rig.store)
        flaky.failing = true
        var search = SearchViewModel(store: flaky)
        await search.search("anything")
        guard case .failed(let e) = search.state else { return XCTFail("\(search.state)") }
        XCTAssertEqual(e.title, "Couldn’t search")
    }

    // MARK: Library-only rule

    func testEveryCardComesFromAnIndexedItem() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var f = ItemFilter()
        f.kinds = [.movie, .episode]
        let page = try await rig.store.page(ItemQuery(filter: f, sort: ItemSort()), limit: 100, after: nil)
        var home = HomeViewModel(store: rig.store)
        await home.load(now: now)
        let known = Set(page.items.map(\.id))
        for row in home.state.content ?? [] { for card in row.cards { XCTAssertTrue(known.contains(card.id)) } }
    }
}
