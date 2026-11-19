import XCTest
import VideoPlayerCore
@testable import MetadataOnline

final class FixMatchTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func stored(_ scope: MatchScope, _ path: String, tmdb: Int = 1, kind: TitleKind = .series) -> StoredMatch {
        StoredMatch(scope: scope, path: path, tmdbID: tmdb, kind: kind, title: "T\(tmdb)", year: 2000, createdAt: t0)
    }

    private func service(_ catalog: FakeCatalog? = nil, store: (any MatchStore)? = nil) -> (FixMatchService, FakeCatalog, any MatchStore) {
        let c = catalog ?? MatchEngineTests.catalog()
        let s: any MatchStore = store ?? InMemoryMatchStore()
        let t = t0
        return (FixMatchService(engine: MatchEngine(provider: c), store: s, now: { t }), c, s)
    }

    // MARK: File identity and lookup rules

    func testFileIdentityNormalisesPaths() {
        XCTAssertEqual(FileIdentity(path: "C:\\Media\\Show\\S01E01.mkv").path, "C:/Media/Show/S01E01.mkv")
        XCTAssertEqual(FileIdentity(path: "/media/show/").path, "/media/show")
        XCTAssertEqual(FileIdentity(path: "/media/show/a.mkv").folderPath, "/media/show")
        XCTAssertEqual(FileIdentity(path: "/a.mkv").folderPath, "/")
        XCTAssertEqual(FileIdentity(path: "a.mkv").folderPath, "")
        XCTAssertEqual(FileIdentity(path: "/", size: 5).path, "/")
    }

    func testLookupPrefersFileThenSeasonThenDeepestFolder() {
        let file = FileIdentity(path: "/tv/Show/Season 1/e01.mkv")
        let all = [
            stored(.folder, "/tv", tmdb: 1),
            stored(.folder, "/tv/Show", tmdb: 2),
            stored(.season(1), "/tv/Show/Season 1", tmdb: 3),
            stored(.file, "/tv/Show/Season 1/e01.mkv", tmdb: 4)
        ]
        XCTAssertEqual(StoredMatch.best(for: file, season: 1, in: all)?.tmdbID, 4)
        XCTAssertEqual(StoredMatch.best(for: file, season: 1, in: Array(all.prefix(3)))?.tmdbID, 3)
        XCTAssertEqual(StoredMatch.best(for: file, season: 1, in: Array(all.prefix(2)))?.tmdbID, 2)
        XCTAssertEqual(StoredMatch.best(for: file, season: 1, in: Array(all.prefix(1)))?.tmdbID, 1)
        XCTAssertNil(StoredMatch.best(for: file, season: 1, in: []))
    }

    func testSeasonChoiceNeedsTheSameFolderAndSeason() {
        let m = [stored(.season(2), "/tv/Show")]
        XCTAssertNotNil(StoredMatch.best(for: FileIdentity(path: "/tv/Show/e01.mkv"), season: 2, in: m))
        XCTAssertNil(StoredMatch.best(for: FileIdentity(path: "/tv/Show/e01.mkv"), season: 1, in: m))
        XCTAssertNil(StoredMatch.best(for: FileIdentity(path: "/tv/Show/e01.mkv"), season: nil, in: m))
        XCTAssertNil(StoredMatch.best(for: FileIdentity(path: "/tv/Other/e01.mkv"), season: 2, in: m))
        XCTAssertNil(StoredMatch.best(for: FileIdentity(path: "/tv/Show/Sub/e01.mkv"), season: 2, in: m), "a season choice is for that folder only")
    }

    func testFolderChoiceReachesSubfoldersButNotSiblingsWithTheSamePrefix() {
        let m = [stored(.folder, "/tv/Show")]
        XCTAssertNotNil(StoredMatch.best(for: FileIdentity(path: "/tv/Show/e01.mkv"), season: nil, in: m))
        XCTAssertNotNil(StoredMatch.best(for: FileIdentity(path: "/tv/Show/Season 1/e01.mkv"), season: 1, in: m))
        XCTAssertNil(StoredMatch.best(for: FileIdentity(path: "/tv/Show 2/e01.mkv"), season: nil, in: m))
        XCTAssertNil(StoredMatch.best(for: FileIdentity(path: "/tv/Northlight.mkv"), season: nil, in: m))
    }

    func testFileChoiceIsKeyedByPathNotBySize() {
        var m = stored(.file, "/m/a.mkv")
        m.fileSize = 100
        XCTAssertNotNil(StoredMatch.best(for: FileIdentity(path: "/m/a.mkv", size: 999), season: nil, in: [m]))
        XCTAssertNil(StoredMatch.best(for: FileIdentity(path: "/m/b.mkv", size: 100), season: nil, in: [m]))
    }

    // MARK: Stores

    func testStoresReplaceSameScopeAndPath() async throws {
        let stores: [any MatchStore] = [InMemoryMatchStore(), JSONFileMatchStore(url: tempDirectory("ms").appendingPathComponent("m.json"))]
        for store in stores {
            let first = stored(.file, "/m/a.mkv", tmdb: 1, kind: .movie)
            let second = stored(.file, "/m/a.mkv", tmdb: 2, kind: .movie)
            let none = try await store.save(first)
            XCTAssertNil(none)
            let replaced = try await store.save(second)
            XCTAssertEqual(replaced?.tmdbID, 1)
            let all = await store.all()
            XCTAssertEqual(all.map(\.tmdbID), [2])
            let removed = try await store.remove(id: second.id)
            XCTAssertEqual(removed?.tmdbID, 2)
            let again = try await store.remove(id: second.id)
            XCTAssertNil(again)
            let empty = await store.all()
            XCTAssertTrue(empty.isEmpty)
        }
    }

    func testDifferentScopesOnTheSamePathAreKeptSeparately() async throws {
        let store = InMemoryMatchStore()
        await store.save(stored(.folder, "/tv/Show", tmdb: 1))
        await store.save(stored(.season(1), "/tv/Show", tmdb: 2))
        await store.save(stored(.season(2), "/tv/Show", tmdb: 3))
        let all = await store.all()
        XCTAssertEqual(all.count, 3)
    }

    func testJSONStoreSurvivesRestartAndWritesAtomically() async throws {
        let dir = tempDirectory("ms-persist")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sub/matches.json")
        let a = JSONFileMatchStore(url: url)
        let m = StoredMatch(scope: .season(2), path: "/tv/Show", fileSize: nil, tmdbID: 1396, kind: .series, title: "Crossing Brine", year: 2008, createdAt: t0)
        try await a.save(m)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let b = JSONFileMatchStore(url: url)
        let loaded = await b.all()
        XCTAssertEqual(loaded, [m])
        let found = await b.lookup(file: FileIdentity(path: "/tv/Show/x.mkv"), season: 2)
        XCTAssertEqual(found?.tmdbID, 1396)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, ["matches.json"], "no temporary files left behind")
    }

    func testCorruptJSONIsSetAsideAndTheStoreStartsEmpty() async throws {
        let dir = tempDirectory("ms-corrupt")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("matches.json")
        try Data("{ not json".utf8).write(to: url)
        let store = JSONFileMatchStore(url: url)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("matches.json.corrupt"), encoding: .utf8), "{ not json")
        try await store.save(stored(.file, "/m/a.mkv", tmdb: 7, kind: .movie))
        let again = await JSONFileMatchStore(url: url).all()
        XCTAssertEqual(again.map(\.tmdbID), [7])
    }

    func testSaveFailureIsReportedNotSwallowed() async throws {
        let dir = tempDirectory("ms-fail")
        defer { try? FileManager.default.removeItem(at: dir) }
        let blocker = dir.appendingPathComponent("file")
        try Data("x".utf8).write(to: blocker)
        let store = JSONFileMatchStore(url: blocker.appendingPathComponent("matches.json"))
        do {
            try await store.save(stored(.file, "/m/a.mkv", kind: .movie))
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is MatchStoreError)
        }
    }

    // MARK: Service

    func testStoredChoiceBeatsAutomaticMatchingAndNeedsNoSearch() async throws {
        let (svc, catalog, _) = service()
        let file = FileIdentity(path: "/movies/The Marrowgate (1999).mkv")
        let input = MatchInput(parsed: P.movie("The Marrowgate", year: 1999))
        // Without a choice the file matches The Marrowgate automatically.
        let before = try await svc.resolve(file: file, input: input)
        guard case .matched(let auto) = before else { return XCTFail("got \(before)") }
        XCTAssertEqual(auto.tmdbID, 603)
        // The user says it is the 1984 Dunerra.
        let dunerra = SearchHit.movie(841, "Dunerra", year: 1984)
        let change = try await svc.choose(dunerra, for: file, input: input, scope: .file)
        XCTAssertEqual(change.result.source, .userChosen)
        let calls = catalog.calls.count
        let after = try await svc.resolve(file: file, input: input)
        guard case .matched(let chosen) = after else { return XCTFail("got \(after)") }
        XCTAssertEqual(chosen.tmdbID, 841)
        XCTAssertEqual(chosen.source, .stored)
        XCTAssertEqual(chosen.confidence, 1)
        XCTAssertEqual(chosen.title, "Dunerra")
        XCTAssertEqual(catalog.calls.count, calls, "a saved movie choice is used with no provider call at all")
    }

    func testStoredChoiceAlsoBeatsASidecarID() async throws {
        let (svc, _, _) = service()
        let file = FileIdentity(path: "/movies/a.mkv")
        let input = MatchInput(parsed: P.movie("The Marrowgate"), sidecarIDs: ProviderIDs(tmdb: 603))
        _ = try await svc.choose(.movie(841, "Dunerra", year: 1984), for: file, input: input, scope: .file)
        let outcome = try await svc.resolve(file: file, input: input)
        guard case .matched(let r) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(r.tmdbID, 841)
        XCTAssertEqual(r.source, .stored)
    }

    func testFixingAMismatchedTitleEndToEnd() async throws {
        let (svc, _, store) = service()
        let file = FileIdentity(path: "/movies/sequel.two.mkv")
        let input = MatchInput(parsed: P.movie("Sequel Two", year: 2003))
        let first = try await svc.resolve(file: file, input: input)
        XCTAssertFalse(first.isAutomaticMatch)
        // Fix Match: the user searches by title and year and picks a candidate.
        let candidates = try await svc.search(query: "The Marrowgate Reloaded", year: 2003, kind: .movie, input: input)
        let pick = try XCTUnwrap(candidates.first)
        XCTAssertEqual(pick.hit.tmdbID, 604)
        _ = try await svc.choose(pick.hit, for: file, input: input, scope: .file)
        let saved = await store.all()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].path, "/movies/sequel.two.mkv")
        XCTAssertEqual(saved[0].createdAt, t0)
        let second = try await svc.resolve(file: file, input: input)
        guard case .matched(let r) = second else { return XCTFail("got \(second)") }
        XCTAssertEqual(r.tmdbID, 604)
    }

    func testFolderChoiceAppliesToEveryEpisodeBelowAndNotElsewhere() async throws {
        let (svc, _, _) = service()
        let base = FileIdentity(path: "/tv/Some Show/Season 1/e01.mkv")
        let input = MatchInput(parsed: P.episode("Some Show", season: 1, episodes: [1]))
        _ = try await svc.choose(.show(1396, "Crossing Brine", year: 2008), for: base, input: input, scope: .folder)
        // The choice was saved for the file's own folder: /tv/Some Show/Season 1
        let sibling = try await svc.resolve(file: FileIdentity(path: "/tv/Some Show/Season 1/e02.mkv"), input: MatchInput(parsed: P.episode("Some Show", season: 1, episodes: [2])))
        guard case .matched(let r) = sibling else { return XCTFail("got \(sibling)") }
        XCTAssertEqual(r.tmdbID, 1396)
        XCTAssertEqual(r.source, .stored)
        XCTAssertEqual(r.episodes?.titles, ["Cat's in the Box..."], "episodes of the chosen series are still resolved")
        let elsewhere = try await svc.resolve(file: FileIdentity(path: "/tv/Other/Season 1/e01.mkv"), input: MatchInput(parsed: P.episode("Some Show", season: 1, episodes: [1])))
        XCTAssertFalse(elsewhere.isStored)
    }

    func testSeasonChoiceAppliesOnlyToThatSeason() async throws {
        let (svc, _, _) = service()
        let input1 = MatchInput(parsed: P.episode("Show", season: 1, episodes: [1]))
        _ = try await svc.choose(.show(1396, "Crossing Brine", year: 2008), for: FileIdentity(path: "/tv/Show/e01.mkv"), input: input1, scope: .season(1))
        let same = try await svc.resolve(file: FileIdentity(path: "/tv/Show/e02.mkv"), input: MatchInput(parsed: P.episode("Show", season: 1, episodes: [2])))
        XCTAssertTrue(same.isStored)
        let other = try await svc.resolve(file: FileIdentity(path: "/tv/Show/e03.mkv"), input: MatchInput(parsed: P.episode("Show", season: 2, episodes: [3])))
        XCTAssertFalse(other.isStored)
    }

    func testSpecialsUseSeasonZeroForSeasonChoices() async throws {
        let (svc, _, _) = service()
        let input = MatchInput(parsed: P.episode("Show", episodes: [1], special: true))
        _ = try await svc.choose(.show(1396, "Crossing Brine", year: 2008), for: FileIdentity(path: "/tv/Show/Specials/sp1.mkv"), input: input, scope: .season(0))
        let again = try await svc.resolve(file: FileIdentity(path: "/tv/Show/Specials/sp2.mkv"), input: MatchInput(parsed: P.episode("Show", episodes: [2], special: true)))
        XCTAssertTrue(again.isStored)
    }

    func testSeasonAndFolderChoicesAreOnlyAllowedForSeries() async throws {
        let (svc, _, store) = service()
        let file = FileIdentity(path: "/movies/a.mkv")
        let input = MatchInput(parsed: P.movie("Dunerra"))
        for scope in [MatchScope.folder, .season(1)] {
            do {
                _ = try await svc.choose(.movie(841, "Dunerra", year: 1984), for: file, input: input, scope: scope)
                XCTFail("expected scopeNotAllowed for \(scope)")
            } catch {
                guard case .scopeNotAllowed = error as? MetadataError else { return XCTFail("wrong error \(error)") }
            }
        }
        let all = await store.all()
        XCTAssertTrue(all.isEmpty, "nothing was saved")
    }

    func testUndoRemovesTheChoice() async throws {
        let (svc, _, store) = service()
        let file = FileIdentity(path: "/movies/a.mkv")
        let input = MatchInput(parsed: P.movie("The Marrowgate", year: 1999))
        let change = try await svc.choose(.movie(841, "Dunerra", year: 1984), for: file, input: input, scope: .file)
        XCTAssertNil(change.replaced)
        try await svc.undo(change)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
        let outcome = try await svc.resolve(file: file, input: input)
        guard case .matched(let r) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(r.source, .automatic)
        XCTAssertEqual(r.tmdbID, 603)
    }

    func testUndoRestoresTheChoiceItReplaced() async throws {
        let (svc, _, store) = service()
        let file = FileIdentity(path: "/movies/a.mkv")
        let input = MatchInput(parsed: P.movie("Dunerra"))
        let first = try await svc.choose(.movie(841, "Dunerra", year: 1984), for: file, input: input, scope: .file)
        let second = try await svc.choose(.movie(438631, "Dunerra", year: 2021), for: file, input: input, scope: .file)
        XCTAssertEqual(second.replaced?.tmdbID, 841)
        let afterSecond = await store.all()
        XCTAssertEqual(afterSecond.map(\.tmdbID), [438631])
        try await svc.undo(second)
        let restored = await store.all()
        XCTAssertEqual(restored.map(\.tmdbID), [841])
        XCTAssertEqual(restored.first?.id, first.added.id)
    }

    func testChoicesPersistAcrossServicesUsingTheFileStore() async throws {
        let dir = tempDirectory("ms-svc")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("matches.json")
        let file = FileIdentity(path: "/movies/a.mkv", size: 1234)
        let input = MatchInput(parsed: P.movie("Dunerra"))
        let (one, _, _) = service(store: JSONFileMatchStore(url: url))
        _ = try await one.choose(.movie(841, "Dunerra", year: 1984), for: file, input: input, scope: .file)
        let (two, _, _) = service(store: JSONFileMatchStore(url: url))
        let outcome = try await two.resolve(file: file, input: input)
        guard case .matched(let r) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(r.tmdbID, 841)
        let saved = await JSONFileMatchStore(url: url).all()
        XCTAssertEqual(saved.first?.fileSize, 1234)
    }

    func testStoredSeriesChoiceStillWorksWhenTheEpisodeLookupFails() async throws {
        let c = FakeCatalog() // knows nothing: season lookups throw notFound
        let (svc, _, _) = service(c)
        let file = FileIdentity(path: "/tv/Show/e01.mkv")
        let input = MatchInput(parsed: P.episode("Show", season: 1, episodes: [1]))
        _ = try await svc.choose(.show(1, "Unknown Show", year: 2000), for: file, input: input, scope: .file)
        let outcome = try await svc.resolve(file: file, input: input)
        guard case .matched(let r) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(r.tmdbID, 1)
        XCTAssertNil(r.episodes)
    }
}

extension MatchOutcome {
    var isStored: Bool {
        if case .matched(let r) = self { return r.source == .stored }
        return false
    }
}
