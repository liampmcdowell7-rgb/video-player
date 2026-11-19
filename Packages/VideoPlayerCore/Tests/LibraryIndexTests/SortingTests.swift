import XCTest
import VideoPlayerCore
import UserData
@testable import LibraryIndex

/// Per-file sorting into Movies, Shows and Needs Review (docs/SORTING.md). Synthetic names only.
final class SortingTests: XCTestCase {

    // MARK: The flat, mixed folder (40 files, every pattern)

    /// name -> expected outcome. All files sit in one folder, the source root.
    static let flat: [(String, SortOutcome)] = [
        // a. clear episode patterns, with release-tag noise
        ("Sample.Show.S01E01.2160p.WEB-DL.DDP5.1.HDR.x265-GRP.mkv", .episode),
        ("Sample Show - S01E02 - Second.mkv", .episode),
        ("sample_show_s01e03_720p.mkv", .episode),
        ("Sample Show S1E4.mp4", .episode),
        ("Sample Show 1x05.mkv", .episode),
        ("Sample Show Season 2 Episode 1.mkv", .episode),
        ("Sample Show S02E02-E03.mkv", .episode),
        ("Sample Show S02E04E05.mkv", .episode),
        ("Sample Show 2024-03-05.mkv", .episode),
        ("Sample Show 2024.03.06.mkv", .episode),
        ("Sample Show S02E06.720p.HDTV.x264-GRP.mkv", .episode),
        ("Sample Show S03E01 - Third Season.mkv", .episode),
        ("Sample Show SP01.mkv", .episode),
        // a second show with a similar name
        ("Sample Show Two S01E01.mkv", .episode),
        ("Sample.Show.Two.S01E02.1080p.mkv", .episode),
        ("Sample Show Two 1x03.mkv", .episode),
        ("Sample Show Two - 1x04 - Late.mkv", .episode),
        ("Sample Show Two S02E01.mkv", .episode),
        // absolute numbering, with other files of the same show
        ("Sample Anime - 001.mkv", .episode),
        ("Sample Anime - 002.mkv", .episode),
        ("[Group] Sample Anime - 003 [1080p].mkv", .episode),
        // weak markers, with other files of the same show (folder hint)
        ("Sample Cartoon E01.mkv", .episode),
        ("Sample Cartoon E02.mkv", .episode),
        // b. clear movie patterns
        ("Sample Movie (2019).mkv", .movie),
        ("Sample Movie Three 2019.mkv", .movie),
        ("Sample.Movie.Four.2021.2160p.UHD.BluRay.x265-GRP.mkv", .movie),
        ("Sample Movie 2049 (2017).mkv", .movie),
        ("Sample Movie Five (1999) 1080p.mkv", .movie),
        ("Sample_Movie_Six_2005_720p.mp4", .movie),
        ("Sample Movie Seven Ep 2 (2012).mkv", .movie),
        ("Sample Movie - 12 (2010).mkv", .movie),
        ("Sample Movie Eight (2001).avi", .movie),
        ("Sample Movie Nine 1987.mkv", .movie),
        ("Sample Movie Ten (2015) {edition-Director's Cut}.mkv", .movie),
        // e. ambiguous: Needs Review
        ("Sample Clip.mkv", .needsReview),
        ("holiday video.mp4", .needsReview),
        ("Sample Extra E05.mkv", .needsReview),
        ("Sample Lone Show - 007.mkv", .needsReview),
        ("Sample Pack S03.mkv", .needsReview),
        ("2024-01-02.mkv", .needsReview),
    ]

    func testTheFlatFolderHasFortyFiles() {
        XCTAssertEqual(Self.flat.count, 40)
        XCTAssertEqual(Set(Self.flat.map(\.0)).count, 40)
    }

    func testEveryFileInAFlatMixedFolderIsSortedOnItsOwn() {
        let siblings = SiblingIndex(names: Self.flat.map(\.0))
        for (name, expected) in Self.flat {
            let d = MediaSorter.decide(fileName: name, context: SortContext(folders: [], siblings: siblings))
            XCTAssertEqual(d.outcome, expected, "\(name): \(d.signal.rawValue), \(d.note)")
            XCTAssertFalse(d.note.isEmpty, name)
            if expected == .needsReview { XCTAssertEqual(d.signal, .undecided, name) } else { XCTAssertNotEqual(d.signal, .undecided, name) }
        }
    }

    func testSignalsAreRecordedInTheRightOrder() {
        let siblings = SiblingIndex(names: Self.flat.map(\.0))
        func signal(_ name: String) -> SortSignal { MediaSorter.decide(fileName: name, context: SortContext(siblings: siblings)).signal }
        XCTAssertEqual(signal("Sample Show S1E4.mp4"), .episodePattern)
        XCTAssertEqual(signal("Sample Show 2024.03.06.mkv"), .episodePattern)
        XCTAssertEqual(signal("Sample Anime - 002.mkv"), .episodePattern, "absolute numbering counts when other files of the show are here")
        XCTAssertEqual(signal("Sample Cartoon E02.mkv"), .folderHint, "a weak marker needs a tie-breaker")
        XCTAssertEqual(signal("Sample Movie (2019).mkv"), .moviePattern)
        XCTAssertEqual(signal("Sample Clip.mkv"), .undecided)
    }

    func testAbsoluteNumberingAloneIsNotAnEpisode() {
        let alone = MediaSorter.decide(fileName: "Sample Anime - 001.mkv", context: SortContext())
        XCTAssertEqual(alone.outcome, .needsReview, alone.note)
        let pair = SiblingIndex(names: ["Sample Anime - 001.mkv", "Sample Anime - 002.mkv"])
        XCTAssertEqual(MediaSorter.decide(fileName: "Sample Anime - 001.mkv", context: SortContext(siblings: pair)).outcome, .episode)
        let unrelated = SiblingIndex(names: ["Sample Anime - 001.mkv", "Other Sample - 002.mkv"])
        XCTAssertEqual(MediaSorter.decide(fileName: "Sample Anime - 001.mkv", context: SortContext(siblings: unrelated)).outcome, .needsReview)
    }

    func testAYearInTheTitleAndAYearInParenthesesGiveTheRightMovie() {
        let d = MediaSorter.decide(fileName: "Sample Movie 2049 (2017).mkv", context: SortContext())
        XCTAssertEqual(d.outcome, .movie)
        XCTAssertEqual(d.parsed.title, "Sample Movie 2049")
        XCTAssertEqual(d.parsed.year, 2017)
    }

    func testAWeakMarkerWithAYearIsAMovieAndKeepsTheNumberInItsTitle() {
        let d = MediaSorter.decide(fileName: "Sample Movie - 12 (2010).mkv", context: SortContext())
        XCTAssertEqual(d.outcome, .movie)
        XCTAssertEqual(d.parsed.year, 2010)
        XCTAssertTrue(d.parsed.title.contains("12"), d.parsed.title)
    }

    func testFolderHintsOnlyBreakTies() {
        // A season folder makes a weak marker an episode; it never overrides a clear movie pattern.
        let inSeason = MediaSorter.decide(fileName: "Sample Extra E05.mkv", context: SortContext(folders: ["Season 2", "Sample Extra"]))
        XCTAssertEqual(inSeason.outcome, .episode)
        XCTAssertEqual(inSeason.signal, .folderHint)
        XCTAssertEqual(inSeason.parsed.season, 2)
        let movie = MediaSorter.decide(fileName: "Sample Movie (2019).mkv", context: SortContext(folders: ["Season 2", "Sample Show"]))
        XCTAssertEqual(movie.outcome, .movie)
        // A folder named like a movie, with a year, files a year-less name as that movie.
        let titled = MediaSorter.decide(fileName: "movie.mkv", context: SortContext(folders: ["Sample Movie (2019)"]))
        XCTAssertEqual(titled.outcome, .movie)
        XCTAssertEqual(titled.signal, .folderHint)
    }

    // MARK: Server item types

    func testTheServerTypeIsUsedWhenTheFileNameIsNotClear() {
        let d = MediaSorter.decide(fileName: "Sample Clip.mkv", context: SortContext(serverType: .movie))
        XCTAssertEqual(d.outcome, .movie)
        XCTAssertEqual(d.signal, .serverType)
        let ep = MediaSorter.decide(fileName: "Sample Extra E05.mkv", context: SortContext(serverType: .episode))
        XCTAssertEqual(ep.outcome, .episode)
        XCTAssertEqual(ep.signal, .serverType)
        let noNumber = MediaSorter.decide(fileName: "Sample Clip.mkv", context: SortContext(serverType: .episode))
        XCTAssertEqual(noNumber.outcome, .needsReview, "an episode needs a number to be filed")
    }

    func testAWrongServerTypeIsCorrectedByTheFileNameAndSaysSo() {
        let d = MediaSorter.decide(fileName: "Sample Show S01E02.mkv", context: SortContext(serverType: .movie))
        XCTAssertEqual(d.outcome, .episode)
        XCTAssertEqual(d.signal, .filenameOverServer)
        XCTAssertTrue(d.note.hasPrefix("Sorted by filename, not by the server."), d.note)
        let m = MediaSorter.decide(fileName: "Sample Movie (2019).mkv", context: SortContext(serverType: .episode))
        XCTAssertEqual(m.outcome, .movie)
        XCTAssertEqual(m.signal, .filenameOverServer)
    }

    func testTheSourceSettingIgnoresServerTypes() {
        let d = MediaSorter.decide(fileName: "Sample Clip.mkv", context: SortContext(serverType: .movie, preferFilename: true))
        XCTAssertEqual(d.outcome, .needsReview)
    }

    // MARK: Through the index

    func put(_ h: Harness, _ names: [String], folder: String = "") {
        for (i, n) in names.enumerated() { h.source.put(folder + "/" + n, size: Int64(1_000 + i), modified: day(Double(i % 20))) }
    }

    func items(_ h: Harness, _ kind: ItemKind) async throws -> [LibraryItem] {
        var f = ItemFilter()
        f.kinds = [kind]
        return try await h.store.page(ItemQuery(filter: f), limit: 1_000, offset: 0)
    }

    func testAFlatFolderSortsIntoMoviesShowsAndNeedsReview() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        put(h, Self.flat.map(\.0))
        try await h.syncer.sync()

        let movies = try await items(h, .movie)
        let episodes = try await items(h, .episode)
        let review = try await h.store.needsReview(limit: 100)
        XCTAssertEqual(movies.count, Self.flat.filter { $0.1 == .movie }.count)
        XCTAssertEqual(Set(review.map(\.fileName)), Set(Self.flat.filter { $0.1 == .needsReview }.map(\.0)))
        try await expectEqual(try await h.store.needsReviewCount(), 6)
        // Multi-episode files are one item each: 23 episode files.
        XCTAssertEqual(episodes.count, 23)

        // Shows grouped by normalised name across the flat folder.
        let byShow = Dictionary(grouping: episodes, by: { $0.seriesID ?? -1 })
        XCTAssertEqual(byShow.count, 4)
        XCTAssertEqual(Set(episodes.compactMap(\.seriesTitle).map(LibraryText.normalize)), ["sample show", "sample show two", "sample anime", "sample cartoon"])
        let show = byShow.values.first { LibraryText.normalize($0[0].seriesTitle ?? "") == "sample show" }!
        XCTAssertEqual(Set(show.compactMap(\.season)), [0, 1, 2, 3])
        XCTAssertEqual(show.filter { $0.season == 1 }.compactMap(\.episode).sorted(), [1, 2, 3, 4, 5])
        XCTAssertEqual(show.first { $0.season == 2 && $0.episode == 2 }?.episodeEnd, 3)

        // Needs Review never shows in Movies, Shows, Home rows or the counts.
        let all = try await h.store.page(ItemQuery(), limit: 1_000, offset: 0)
        XCTAssertEqual(all.count, movies.count + episodes.count)
        let recent = try await h.store.recentlyAdded(limit: 100, kind: nil)
        XCTAssertFalse(recent.contains { r in review.contains { $0.id == r.id } })
        try await expectEqual(try await h.store.counts().items, movies.count + episodes.count)
    }

    func testReleaseTagNoiseJoinsOneShow() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        put(h, ["Sample.Show.S01E02.2160p.WEB-DL.DDP5.1.HDR.x265-GRP.mkv", "Sample Show - S01E03.mkv", "sample_show_S01E04_720p_HDTV.mkv"])
        try await h.syncer.sync()
        let eps = try await items(h, .episode)
        XCTAssertEqual(eps.count, 3)
        XCTAssertEqual(Set(eps.compactMap(\.seriesID)).count, 1, "one show")
        XCTAssertEqual(eps.compactMap(\.episode).sorted(), [2, 3, 4])
    }

    func testTwoShowsWithSimilarNamesStayApart() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        put(h, ["Sample Show S01E01.mkv", "Sample Show Two S01E01.mkv", "Sample Shows S01E01.mkv"])
        try await h.syncer.sync()
        let eps = try await items(h, .episode)
        XCTAssertEqual(Set(eps.compactMap(\.seriesID)).count, 3)
    }

    func testTheSignalIsShownInTheItemInfo() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        put(h, ["Sample Movie (2019).mkv", "Sample Show S01E01.mkv"])
        try await h.syncer.sync()
        let movies = try await items(h, .movie)
        let movie = try XCTUnwrap(movies.first)
        let info = try await h.store.sortInfo(itemID: movie.id)
        XCTAssertEqual(info?.record.signal, .moviePattern)
        XCTAssertEqual(info?.fileName, "Sample Movie (2019).mkv")
        XCTAssertFalse(info?.record.note.isEmpty ?? true)
    }

    func testEverySortedFileIsLogged() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        put(h, ["Sample Movie (2019).mkv", "Sample Clip.mkv"])
        let lines = Locked<[String]>([])
        let syncer = LibrarySyncer(store: h.store, source: h.source, sourceID: Harness.sourceID, sortLog: { path, outcome, signal, _ in
            lines.with { $0.append("\(path) \(outcome.rawValue) \(signal.rawValue)") }
        })
        try await syncer.sync()
        XCTAssertEqual(Set(lines.get), ["/Sample Movie (2019).mkv movie moviePattern", "/Sample Clip.mkv needsReview undecided"])
    }

    func testARescanChangesNothing() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        put(h, Self.flat.map(\.0))
        try await h.syncer.sync()
        let before = try await h.store.snapshot()
        let again = try await h.syncer.sync()
        XCTAssertEqual(again.progress.added, 0)
        XCTAssertEqual(again.progress.changed, 0, "Needs Review files that are still undecided are not rewritten")
        XCTAssertEqual(again.progress.unchanged, 40)
        let after = try await h.store.snapshot()
        XCTAssertEqual(after, before)
    }

    func testANeedsReviewFileIsSortedWhenTheFolderLaterSaysMore() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/Sample Anime - 001.mkv", size: 1, modified: day(1))
        try await h.syncer.sync()
        try await expectEqual(try await h.store.needsReviewCount(), 1)
        h.source.put("/Sample Anime - 002.mkv", size: 2, modified: day(2))
        try await h.syncer.sync()
        try await expectEqual(try await h.store.needsReviewCount(), 0)
        let eps = try await items(h, .episode)
        XCTAssertEqual(eps.compactMap(\.episode).sorted(), [1, 2])
    }

    // MARK: Overrides

    func testAnOverrideMovesAFileAndSurvivesRescansAndARebuiltIndex() async throws {
        let ledger = UserDataLedger(deviceID: "A")
        let overrides = LedgerSortOverrides(ledger: ledger)
        let h = try Harness.make(overrides: overrides)
        defer { h.cleanup() }
        put(h, ["Sample Clip.mkv", "Sample Movie (2019).mkv"])
        try await h.syncer.sync()
        try await expectEqual(try await h.store.needsReviewCount(), 1)

        // Move to Shows, with the episode details asked for.
        ledger.setSortOverride(UDSortOverrideValue(sourceID: Harness.sourceID, path: "/Sample Clip.mkv", kind: .episode, title: "Sample Show", season: 2, episode: 7))
        // Move a clear movie to Shows too: the override wins over the file name.
        ledger.setSortOverride(UDSortOverrideValue(sourceID: Harness.sourceID, path: "/Sample Movie (2019).mkv", kind: .episode, title: "Sample Show", season: 1, episode: 1))
        let moved = try await h.syncer.sync()
        XCTAssertEqual(moved.progress.changed, 2, "the files did not change, the overrides did")
        try await expectEqual(try await h.store.needsReviewCount(), 0)
        try await expectEqual(try await items(h, .movie).count, 0)
        let eps = try await items(h, .episode)
        XCTAssertEqual(eps.map { "\($0.season ?? -1)x\($0.episode ?? -1)" }.sorted(), ["1x1", "2x7"])
        let info = try await h.store.sortInfo(itemID: eps[0].id)
        XCTAssertEqual(info?.record.signal, .manual)

        // A rescan keeps it; nothing is rewritten.
        let again = try await h.syncer.sync()
        XCTAssertEqual(again.progress.changed, 0)

        // The override syncs: a second device (an empty index) gets the same result.
        let other = UserDataLedger(deviceID: "B")
        for r in ledger.allRecords() { other.apply(r) }
        let h2 = try Harness.make(overrides: LedgerSortOverrides(ledger: other))
        defer { h2.cleanup() }
        put(h2, ["Sample Clip.mkv", "Sample Movie (2019).mkv"])
        try await h2.syncer.sync()
        let eps2 = try await items(h2, .episode)
        XCTAssertEqual(eps2.map { "\($0.season ?? -1)x\($0.episode ?? -1)" }.sorted(), ["1x1", "2x7"])

        // Removing the override sorts the file by its name again.
        ledger.removeSortOverride(sourceID: Harness.sourceID, path: "/Sample Clip.mkv")
        try await h.syncer.sync()
        try await expectEqual(try await h.store.needsReviewCount(), 1)
    }

    func testOverrideRecordsRoundTripAndMergeAsOneGroup() {
        let v = UDSortOverrideValue(sourceID: "s1", path: "/a/b c.mkv", kind: .episode, title: "Sample Show", year: 2019, season: 1, episode: 2, episodeEnd: 3)
        let r = UDSortOverride.patch(v, at: UDStamp(time: 10, device: "A"))
        XCTAssertEqual(UDSortOverride.value(of: r), v)
        let later = UDSortOverride.patch(UDSortOverrideValue(sourceID: "s1", path: "/a/b c.mkv", kind: .movie, title: "Sample Movie"), at: UDStamp(time: 20, device: "B"))
        let merged = UDSchema.merge(r, later)
        let value = UDSortOverride.value(of: merged)
        XCTAssertEqual(value?.kind, .movie)
        XCTAssertNil(value?.season, "the later group wins as a whole; no episode number is left over")
        XCTAssertEqual(UDSchema.merge(later, r), merged)
    }

    func testServerTypesAndTheSourceSettingThroughTheIndex() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/Sample Clip.mkv", serverType: .movie)
        h.source.put("/Sample Show S01E01.mkv", serverType: .movie)
        try await h.syncer.sync()
        let movies = try await items(h, .movie), episodes = try await items(h, .episode)
        let movie = try XCTUnwrap(movies.first)
        try await expectEqual(try await h.store.sortInfo(itemID: movie.id)?.record.signal, .serverType)
        let ep = try XCTUnwrap(episodes.first)
        let info = try await h.store.sortInfo(itemID: ep.id)
        XCTAssertEqual(info?.record.signal, .filenameOverServer)
        XCTAssertTrue(info?.record.note.contains(MediaSorter.filenameOverServerNote) ?? false)

        // Turning the source setting on sorts the unchanged files again, by name only.
        let byName = LibrarySyncer(store: h.store, source: h.source, sourceID: Harness.sourceID, preferFilename: true)
        try await byName.sync()
        try await expectEqual(try await h.store.needsReviewCount(), 1)
    }

    // MARK: Upgrade

    func testFilesIndexedByTheOldRulesAreSortedAgainOnce() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        put(h, ["Sample Clip.mkv", "Sample Movie (2019).mkv"])
        try await h.syncer.sync()
        // What a version 2 database looks like after the migration: no sort record.
        try await h.store.forgetSortRecords()
        let upgraded = try await h.syncer.sync()
        XCTAssertEqual(upgraded.progress.changed, 2)
        try await expectEqual(try await h.store.needsReviewCount(), 1)
        let again = try await h.syncer.sync()
        XCTAssertEqual(again.progress.changed, 0)
    }
}

extension SQLiteLibraryStore {
    func forgetSortRecords() throws {
        try db.exec("UPDATE files SET sort_signal = NULL, sort_note = NULL, sort_rev = 0, sort_inputs = '', review = 0")
    }
}
