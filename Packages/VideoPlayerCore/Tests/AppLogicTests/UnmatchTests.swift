import XCTest
import LibraryIndex
import UserData
import MetadataOnline
@testable import AppLogic

// FIXTURE: invented titles and ids; the match store is in memory.

private final class RecordingForgetter: MatchChoiceForgetting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var forgotten: [Int64] = []
    func forget(itemIDs: [Int64]) async throws { lock.withLock { forgotten += itemIDs } }
}

/// R471 (14), Part 4: Unmatch clears the match of a movie or a whole show, keeps the files, the title and the edits, holds the
/// files unmatched and removes saved Fix Match choices; the confirmation says what changes and what stays.
final class UnmatchTests: XCTestCase {
    private func ledger() -> UserDataLedger { UserDataLedger(deviceID: "A", clock: { Date(timeIntervalSince1970: 1_700_000_000) }) }

    func testAMovieLosesItsIDButKeepsItsTitleEditsAndFile() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        try await rig.store.setMetadata(itemID: id, ItemMetadata(tmdbID: 949))
        let l = ledger()
        l.setEdit(.movie(tmdbID: 949), .overview, .text("In my words"), at: Date(timeIntervalSince1970: 1_600_000_000))
        let forgetter = RecordingForgetter()
        let changed = try await Unmatcher(store: rig.store, ledger: l, forgetter: forgetter).run(.movie(itemID: id))
        XCTAssertEqual(changed, 1)
        let loaded = try await rig.store.item(id: id)
        let item = try XCTUnwrap(loaded)
        XCTAssertNil(item.tmdbID)
        XCTAssertEqual(item.title, "Hexfall", "the title stays")
        let files = try await rig.store.versions(of: id)
        XCTAssertEqual(files.count, 1, "the file stays")
        XCTAssertEqual(l.edits(for: EditTarget.keys(for: item, files: files))[.overview]?.text, "In my words",
                       "the edit moved from the online id to the file")
        XCTAssertTrue(l.isHeldUnmatched(.file(sourceID: files[0].sourceID, path: files[0].path)))
        XCTAssertEqual(forgetter.forgotten, [id])
    }

    func testAShowUnmatchesEveryEpisodeAndKeepsShowSeasonAndEpisodeEdits() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await rig.episodes(ofSeriesTitle: "Show One")
        for e in eps { try await rig.store.setMetadata(itemID: e.id, ItemMetadata(tmdbID: 1396)) }
        let seriesID = try XCTUnwrap(eps.first?.seriesID)
        let l = ledger()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        l.setEdit(.show(tmdbID: 1396), .overview, .text("Show, mine"), at: old)
        l.setEdit(UDEditKey.show(tmdbID: 1396).season(1), .overview, .text("Season one, mine"), at: old)
        l.setEdit(UDEditKey.show(tmdbID: 1396).episode(season: 1, episode: 2), .overview, .text("Episode, mine"), at: old)
        let changed = try await Unmatcher(store: rig.store, ledger: l).run(.show(seriesID: seriesID, title: "Show One"))
        XCTAssertEqual(changed, eps.count)
        for e in eps { let now = try await rig.store.item(id: e.id); XCTAssertNil(now?.tmdbID) }
        XCTAssertEqual(l.edits(for: EditTarget.showKeys(tmdbID: nil, title: "Show One"))[.overview]?.text, "Show, mine")
        XCTAssertEqual(l.edits(for: EditTarget.seasonKeys(tmdbID: nil, title: "Show One", season: 1))[.overview]?.text, "Season one, mine")
        let e2ID = try XCTUnwrap(eps.first { $0.season == 1 && $0.episode == 2 }).id
        let e2Loaded = try await rig.store.item(id: e2ID)
        let e2 = try XCTUnwrap(e2Loaded)
        let files = try await rig.store.versions(of: e2.id)
        XCTAssertEqual(l.edits(for: EditTarget.keys(for: e2, files: files))[.overview]?.text, "Episode, mine")
        for e in eps {
            for f in try await rig.store.versions(of: e.id) { XCTAssertTrue(l.isHeldUnmatched(.file(sourceID: f.sourceID, path: f.path))) }
        }
        let other = try await rig.episodes(ofSeriesTitle: "Show Two")
        for f in try await rig.store.versions(of: try XCTUnwrap(other.first).id) {
            XCTAssertFalse(l.isHeldUnmatched(.file(sourceID: f.sourceID, path: f.path)), "another show is untouched")
        }
    }

    func testSavedChoicesForTheFilesAreRemoved() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let versions = try await rig.store.versions(of: id)
        let file = try XCTUnwrap(versions.first)
        let identity = TMDBArtworkProvider.identity(of: file)
        let matches = InMemoryMatchStore()
        let date = Date(timeIntervalSince1970: 0)
        await matches.save(StoredMatch(scope: .file, path: identity.path, tmdbID: 949, kind: .movie, title: "Hexfall", year: 1995, createdAt: date))
        await matches.save(StoredMatch(scope: .file, path: "src1/elsewhere.mkv", tmdbID: 1, kind: .movie, title: "Other", year: nil, createdAt: date))
        try await StoredMatchForgetter(matches: matches, store: rig.store).forget(itemIDs: [id])
        let left = await matches.all()
        XCTAssertEqual(left.map(\.title), ["Other"], "only the unmatched file's choice goes")
    }

    func testAHoldIsReleasedByADeletionStamp() {
        let l = ledger()
        let key = UDEditKey.file(sourceID: "src1", path: "/Movies/a.mkv")
        XCTAssertFalse(l.isHeldUnmatched(key))
        l.holdUnmatched(key, at: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(l.isHeldUnmatched(key))
        l.releaseUnmatched(key, at: Date(timeIntervalSince1970: 2))
        XCTAssertFalse(l.isHeldUnmatched(key))
    }

    func testTheConfirmationSaysWhatChangesAndWhatStays() {
        let movie = Unmatcher.confirmation(.movie(itemID: 1), title: "Hexfall")
        XCTAssertEqual(movie.title, "Unmatch “Hexfall”?")
        XCTAssertTrue(movie.message.contains("The file, your progress and your edits stay."))
        XCTAssertTrue(movie.message.contains("not matched again automatically"))
        let show = Unmatcher.confirmation(.show(seriesID: 1, title: "Show One"), title: "Show One", episodeCount: 5)
        XCTAssertTrue(show.message.contains("its 5 episodes"))
        XCTAssertTrue(Unmatcher.confirmation(.show(seriesID: 1, title: "S"), title: "S", episodeCount: 1).message.contains("its 1 episode,"))
    }

    func testUnmatchIsOfferedOnlyForAMatchedMovieOrShowAndOnTheLongPress() {
        var movie = ProductActionContext(kind: .movie)
        movie.matched = true
        XCTAssertTrue(ProductActions.manageList(movie).contains(.unmatch))
        movie.matched = false
        XCTAssertFalse(ProductActions.manageList(movie).contains(.unmatch))
        var show = ProductActionContext(kind: .show)
        show.matched = true
        XCTAssertTrue(ProductActions.manageList(show).contains(.unmatch))
        var episode = ProductActionContext(kind: .episode)
        episode.matched = true
        XCTAssertFalse(ProductActions.manageList(episode).contains(.unmatch), "an episode follows its show")
        var card = ItemCard(id: 7, kind: .movie, title: "Hexfall", subtitle: nil, progress: nil, isWatched: false, isFavorite: false,
                            badges: [], artworkKey: "item-7")
        XCTAssertFalse(ProductActions.cardList(card.actionContext).contains(.unmatch))
        card.isMatched = true
        XCTAssertEqual(ProductActions.cardList(card.actionContext).last, .unmatch)
    }
}
