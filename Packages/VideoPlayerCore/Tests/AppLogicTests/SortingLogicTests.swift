import XCTest
import VideoPlayerCore
import LibraryIndex
import UserData
import MetadataOnline
@testable import AppLogic

/// The app side of per-file sorting (docs/SORTING.md): the source setting, the Move sheet, Move and undo through the ledger
/// and a real scan, the Needs Review list, and the online check. Synthetic names only.
final class SortingLogicTests: XCTestCase {

    // MARK: Source setting

    func testSortByFilenameSettingIsKeptInTheOptionsForMediaServersOnly() {
        let jf = UDSourceDefinition(id: "a", kind: SourceKind.jellyfin.rawValue, name: "Server", options: "x=1")
        XCTAssertFalse(SortSourceOption.preferFilename(jf))
        let on = SortSourceOption.setting(true, on: jf)
        XCTAssertTrue(SortSourceOption.preferFilename(on))
        XCTAssertEqual(SourceOptions.parse(on.options), ["x": "1", "sortByFilename": "1"])
        let off = SortSourceOption.setting(false, on: on)
        XCTAssertFalse(SortSourceOption.preferFilename(off))
        XCTAssertEqual(off.options, "x=1")
        XCTAssertTrue(SortSourceOption.applies(toKind: SourceKind.emby.rawValue))
        XCTAssertFalse(SortSourceOption.applies(toKind: SourceKind.webdav.rawValue))
        let dav = UDSourceDefinition(id: "b", kind: SourceKind.webdav.rawValue, name: "Disk", options: "sortByFilename=1")
        XCTAssertFalse(SortSourceOption.preferFilename(dav), "the setting means nothing without server library types")
    }

    // MARK: Move sheet

    func testMoveSheetIsFilledFromTheFileName() {
        let show = SortMoveDraft(kind: .episode, fileName: "Sample Show - 12.mkv", folders: ["Mixed"])
        XCTAssertEqual(show.title, "Sample Show")
        XCTAssertEqual(show.season, "1")
        XCTAssertEqual(show.episode, "12")
        XCTAssertEqual(show.sheetTitle, "Move to Shows")
        let movie = SortMoveDraft(kind: .movie, fileName: "Sample Movie Seven Ep 2.mkv", folders: [])
        XCTAssertEqual(movie.title, "Sample Movie Seven Ep 2", "as a movie, the weak marker is part of the title")
        XCTAssertEqual(movie.season, "")
        XCTAssertEqual(movie.sheetTitle, "Move to Movies")
    }

    func testMoveSheetChecksEveryField() throws {
        func error(_ d: SortMoveDraft) -> SortMoveError? {
            do { _ = try d.value(sourceID: "s", path: "/p.mkv"); return nil } catch { return error as? SortMoveError }
        }
        XCTAssertEqual(error(SortMoveDraft(kind: .movie, title: "  ")), .emptyTitle)
        XCTAssertEqual(error(SortMoveDraft(kind: .movie, title: "Sample Movie", year: "19")), .badYear)
        XCTAssertNil(error(SortMoveDraft(kind: .movie, title: "Sample Movie")))
        XCTAssertEqual(error(SortMoveDraft(kind: .episode, title: "Sample Show", season: "", episode: "1")), .badSeason)
        XCTAssertEqual(error(SortMoveDraft(kind: .episode, title: "Sample Show", season: "1", episode: "0")), .badEpisode)
        XCTAssertEqual(error(SortMoveDraft(kind: .episode, title: "Sample Show", season: "1", episode: "4", episodeEnd: "3")), .badEpisodeEnd)
        let v = try SortMoveDraft(kind: .episode, title: " Sample Show ", year: "2019", season: "0", episode: "4", episodeEnd: "5").value(sourceID: "s", path: "/p.mkv")
        XCTAssertEqual(v, UDSortOverrideValue(sourceID: "s", path: "/p.mkv", kind: .episode, title: "Sample Show", year: 2019, season: 0, episode: 4, episodeEnd: 5))
        let single = try SortMoveDraft(kind: .episode, title: "Sample Show", season: "2", episode: "4", episodeEnd: "4").value(sourceID: "s", path: "/p.mkv")
        XCTAssertNil(single.episodeEnd)
        let movie = try SortMoveDraft(kind: .movie, title: "Sample Movie", year: "2001", season: "3", episode: "9").value(sourceID: "s", path: "/p.mkv")
        XCTAssertNil(movie.season, "a movie keeps no episode numbers")
        XCTAssertEqual(SortMoveError.badYear.errorDescription, "Enter a year from 1888 to 2100, or leave it empty.")
    }

    // MARK: Move, rescan, undo

    private struct Rig {
        let store: SQLiteLibraryStore
        let source: TreeSource
        let ledger: UserDataLedger
        func scan() async throws {
            let syncer = LibrarySyncer(store: store, source: source, sourceID: LibraryRig.sourceID,
                                       clock: { epoch.addingTimeInterval(100 * 86_400) }, overrides: LedgerSortOverrides(ledger: ledger))
            _ = try await syncer.sync()
        }
        func items(_ kind: ItemKind) async throws -> [LibraryItem] {
            var f = ItemFilter()
            f.kinds = [kind]
            return try await store.page(ItemQuery(filter: f, sort: ItemSort(key: .title, ascending: true)), limit: 100, after: nil).items
        }
    }

    private func rig() async throws -> Rig {
        let r = Rig(store: try SQLiteLibraryStore(path: ":memory:"), source: TreeSource(), ledger: UserDataLedger(deviceID: "dev-a"))
        try await r.store.upsertSource(LibrarySourceRecord(id: LibraryRig.sourceID, kind: .webdav, name: "Test", addedAt: epoch))
        r.source.put("/Mixed/Sample Clip.mkv")
        r.source.put("/Mixed/Sample Movie (2019).mkv")
        try await r.scan()
        return r
    }

    func testMoveFromNeedsReviewSurvivesARescanAndCanBeTakenBack() async throws {
        let r = try await rig()
        var list = NeedsReviewViewModel(store: r.store)
        await list.load()
        let entry = try XCTUnwrap(list.state.content?.first)
        XCTAssertEqual(entry.fileName, "Sample Clip.mkv")
        let mover = SortMover(store: r.store, writer: r.ledger)
        var draft = mover.draft(for: entry, to: .movie)
        XCTAssertEqual(draft.title, "Sample Clip")
        draft.year = "2011"
        try mover.move(entry, draft)
        list.remove(entry)
        XCTAssertEqual(list.state, .empty(EmptyState(reason: .noMatches, title: "Nothing to Review", message: "Every video file is in Movies or Shows.")))

        try await r.scan()
        let reviewCount = try await r.store.needsReviewCount()
        XCTAssertEqual(reviewCount, 0)
        let movies = try await r.items(.movie)
        XCTAssertEqual(Set(movies.map(\.title)), ["Sample Clip", "Sample Movie"])
        let clip = try XCTUnwrap(movies.first { $0.title == "Sample Clip" })
        XCTAssertEqual(clip.year, 2011)
        let info = try await r.store.sortInfo(itemID: clip.id)
        XCTAssertEqual(info?.record.signal, .manual)
        XCTAssertEqual(info.map { SortTexts.line($0.record) }, "Moved by Hand. Moved by hand.")

        // A second rescan changes nothing.
        try await r.scan()
        let again = try await r.items(.movie)
        XCTAssertEqual(again.map(\.title), movies.map(\.title))

        // Move the movie to Shows (every version), then take the choice back.
        let maybeDraft = try await mover.draft(itemID: clip.id, to: .episode)
        var toShow = try XCTUnwrap(maybeDraft)
        XCTAssertEqual(toShow.title, "Sample Clip")
        toShow.season = "1"; toShow.episode = "3"
        let moved = try await mover.move(itemID: clip.id, toShow)
        XCTAssertEqual(moved, 1)
        try await r.scan()
        let episodes = try await r.items(.episode)
        XCTAssertEqual(episodes.map(\.seriesTitle), ["Sample Clip"])
        XCTAssertEqual(episodes.first?.episode, 3)

        let episodeID = try XCTUnwrap(episodes.first?.id)
        try await mover.sortAutomatically(itemID: episodeID)
        try await r.scan()
        let back = try await r.store.needsReview(limit: 10)
        XCTAssertEqual(back.map(\.fileName), ["Sample Clip.mkv"], "with the choice taken back, the rules decide again")
        XCTAssertTrue(r.ledger.sortOverrides().isEmpty)
    }

    func testNeedsReviewFailureIsCalm() async throws {
        let r = try await rig()
        let flaky = FlakyStore(r.store)
        flaky.failing = true
        var list = NeedsReviewViewModel(store: flaky)
        await list.load()
        guard case .failed(let e) = list.state else { return XCTFail("\(list.state)") }
        XCTAssertEqual(e.title, "Couldn’t load Needs Review")
    }

    // MARK: Online check

    private struct FakeLookup: SortLookup {
        /// Normalised title + kind -> confidence.
        var answers: [String: Double]
        func lookUp(_ input: MatchInput) async throws -> MatchOutcome {
            let kind: TitleKind = input.kind
            guard let c = answers[input.parsed.title + "|" + (kind == .movie ? "movie" : "series")] else { return .unmatched }
            let result = MatchResult(tmdbID: 1, kind: kind, title: input.parsed.title, year: 2005, confidence: c, source: .automatic)
            return c >= 0.8 ? .matched(result) : .needsReview(.lowConfidence, [])
        }
    }

    private func entry(_ name: String) -> ReviewEntry {
        ReviewEntry(id: 1, fileID: 1, sourceID: "s", path: "/Mixed/" + name, fileName: name, title: "", year: nil, note: "", addedAt: epoch)
    }

    func testOnlineCheckMovesOnlyWhenExactlyOneSideIsConfirmed() async throws {
        let ledger = UserDataLedger(deviceID: "dev-a")
        let resolver = OnlineSortResolver(lookup: FakeLookup(answers: [
            "Sample Clip|movie": 0.92,
            "Sample Show|series": 0.9,
            "Sample Pair|movie": 0.9, "Sample Pair|series": 0.95,
            "Sample Faint|movie": 0.6,
        ]), writer: ledger)

        let movie = await resolver.decide(entry("Sample Clip.mkv"))
        XCTAssertEqual(movie, UDSortOverrideValue(sourceID: "s", path: "/Mixed/Sample Clip.mkv", kind: .movie, title: "Sample Clip", year: 2005, signal: "onlineLookup"))

        let show = await resolver.decide(entry("Sample Show - 12.mkv"))
        XCTAssertEqual(show?.kind, .episode)
        XCTAssertEqual(show?.title, "Sample Show")
        XCTAssertEqual(show?.season, 1)
        XCTAssertEqual(show?.episode, 12)

        let both = await resolver.decide(entry("Sample Pair - 3.mkv"))
        XCTAssertNil(both, "movie and show both confirmed: still ambiguous")
        let faint = await resolver.decide(entry("Sample Faint.mkv"))
        XCTAssertNil(faint, "below 0.8")
        let noNumbers = await resolver.decide(entry("Sample Show.mkv"))
        XCTAssertNil(noNumbers, "a show is only confirmed when the name has episode numbers")

        let saved = await resolver.run([entry("Sample Clip.mkv"), entry("Sample Faint.mkv"), entry("Sample Show - 12.mkv")],
                                       skipping: [OnlineSortResolver.key(entry("Sample Show - 12.mkv"))])
        XCTAssertEqual(saved.map(\.title), ["Sample Clip"])
        XCTAssertEqual(ledger.sortOverrides().map(\.signal), ["onlineLookup"])
    }

    /// Counts every request a TMDB client would send.
    private final class CountingTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        var count: Int { lock.withLock { _count } }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            lock.withLock { _count += 1 }
            return HTTPResponse(statusCode: 404)
        }
    }

    /// Addendum #18 E: with no TMDB key (none, empty or blank) the online check builds no lookup and sends not one request,
    /// although a file waits in Needs Review. The same pass with a key does send, so the count can see requests.
    func testWithoutAKeyTheOnlineCheckSendsNothing() async throws {
        let r = try await rig()
        let transport = CountingTransport()
        let make: (String) -> any SortLookup = { key in
            MatchEngine(provider: TMDBClient(credentials: OnlineKeyStore.tmdbCredentials(key), transport: transport))
        }
        let waiting = try await r.store.needsReview(limit: 10)
        XCTAssertEqual(waiting.map(\.fileName), ["Sample Clip.mkv"])
        for missing in [nil, "", "  \n"] as [String?] {
            let lookup = OnlineSortPass.lookup(tmdbKey: missing, make: make)
            XCTAssertNil(lookup)
            let result = await OnlineSortPass.run(store: r.store, lookup: lookup, writer: r.ledger, tried: [])
            XCTAssertTrue(result.saved.isEmpty)
            XCTAssertTrue(result.checked.isEmpty)
        }
        XCTAssertEqual(transport.count, 0, "no key: zero requests")
        XCTAssertTrue(r.ledger.sortOverrides().isEmpty)

        let withKey = OnlineSortPass.lookup(tmdbKey: "fixture-key", make: make)
        let sent = await OnlineSortPass.run(store: r.store, lookup: withKey, writer: r.ledger, tried: [])
        XCTAssertEqual(sent.checked.count, 1)
        XCTAssertGreaterThan(transport.count, 0, "with a key the same pass does send")
        // Checked files are not sent again in the same launch.
        let before = transport.count
        let again = await OnlineSortPass.run(store: r.store, lookup: withKey, writer: r.ledger, tried: sent.checked)
        XCTAssertTrue(again.checked.isEmpty)
        XCTAssertEqual(transport.count, before)
    }

    func testWhatIsSentNamesTheNeedsReviewCheckPlainly() {
        let text = OnlineLookupText.whatIsSent
        XCTAssertTrue(text.hasPrefix("Nothing is sent to any online service until you enter a key"))
        for needle in ["the title and year it read from the file and folder names", "at most 40 such files each time the app opens",
                       "Needs Review"] {
            XCTAssertTrue(text.contains(needle), needle)
        }
        XCTAssertEqual(OnlineSortResolver.perRun, 40, "the text says 40")
    }

    // MARK: Texts

    func testEverySignalHasAName() {
        for s in SortSignal.allCases { XCTAssertFalse(SortTexts.title(s).isEmpty) }
        let r = FileSortRecord(signal: .filenameOverServer, note: MediaSorter.filenameOverServerNote, revision: 1, inputs: "", needsReview: false)
        XCTAssertEqual(SortTexts.line(r), "File Name, Not the Server. Sorted by filename, not by the server.")
        XCTAssertEqual(SortTexts.logLine(path: "/a.mkv", outcome: .movie, signal: .moviePattern, note: "n"), "sorted movie by moviePattern: /a.mkv (n)")
    }

    /// Addendum #18 B and C: the screen texts are short plain sentences (S1), the button carries its count, and nothing
    /// claims more than the code does.
    func testTheSortingScreenTextsAreShortAndPlain() {
        XCTAssertEqual(SortTexts.reviewButton(8), "Needs Review (8)")
        XCTAssertEqual(SortTexts.moveTitle(.movie), "Move to Movies")
        XCTAssertEqual(SortTexts.moveTitle(.episode), "Move to Shows")
        XCTAssertEqual(SortTexts.scanningDetail(foldersDone: 3, total: 40), "3 of 40 folders")
        for text in SortTexts.screenTexts {
            XCTAssertFalse(text.isEmpty)
            XCTAssertLessThanOrEqual(text.count, 120, text)
            XCTAssertFalse(text.contains("!"), text)
            XCTAssertFalse(text.contains("  "), text)
        }
        XCTAssertFalse(SortTexts.scanningDetail(foldersDone: 1, total: 2).contains("left"), "no time-left claim")
    }

    /// #25 B9: the same reason on every row is said once; different reasons stay on their rows.
    func testASharedReviewReasonIsSaidOnce() {
        XCTAssertEqual(SortTexts.sharedReason(["No episode pattern", "No episode pattern"]), "No episode pattern")
        XCTAssertNil(SortTexts.sharedReason(["No episode pattern", "Two shows match"]))
        XCTAssertNil(SortTexts.sharedReason(["Only one file"]), "one row keeps its own reason")
        XCTAssertNil(SortTexts.sharedReason([]))
        XCTAssertEqual(SortTexts.reviewFooter(sharedReason: "No episode pattern"), "No episode pattern. " + SortTexts.reviewFooter)
        XCTAssertEqual(SortTexts.reviewFooter(sharedReason: ""), SortTexts.reviewFooter)
        XCTAssertEqual(SortTexts.reviewFooter(sharedReason: nil), SortTexts.reviewFooter)
    }
}
