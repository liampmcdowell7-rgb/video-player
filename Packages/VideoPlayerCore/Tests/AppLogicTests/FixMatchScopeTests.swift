import XCTest
import LibraryIndex
@testable import AppLogic

// FIXTURE: invented candidates; the recorder is a fake that stores nothing outside memory.

private struct OneCandidate: MatchSearching {
    func search(title: String, year: Int?, kind: ItemKind) async throws -> [MatchCandidate] { [MatchCandidate(id: 1396, title: "Fixture Show", year: 2008)] }
}

private final class MemoryRecorder: MatchChoiceRecording, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var records: [(Int64, Int, FixMatchScope)] = []
    func record(itemID: Int64, candidate: MatchCandidate, scope: FixMatchScope) async throws { lock.withLock { records.append((itemID, candidate.id, scope)) } }
}

final class FixMatchScopeTests: XCTestCase {
    func testMoviesOnlyHaveTheFileScopeAndEpisodesHaveThree() {
        XCTAssertEqual(FixMatchScope.choices(for: .movie), [.thisFile])
        XCTAssertEqual(FixMatchScope.choices(for: .episode), [.thisFile, .thisSeason, .wholeShow])
    }

    /// R471 (12): the show page opens Fix Match on The Whole Show; a movie given that scope still opens on This File Only.
    func testTheScreenCanOpenOnTheWholeShowForAnEpisodeOnly() throws {
        let store = try LibraryRig.make().store
        let episode = FixMatchViewModel(store: store, searcher: OneCandidate(), itemID: 1, kind: .episode, currentTitle: "x", scope: .wholeShow)
        XCTAssertEqual(episode.scope, .wholeShow)
        let movie = FixMatchViewModel(store: store, searcher: OneCandidate(), itemID: 1, kind: .movie, currentTitle: "x", scope: .wholeShow)
        XCTAssertEqual(movie.scope, .thisFile)
        XCTAssertEqual(FixMatchViewModel(store: store, searcher: OneCandidate(), itemID: 1, kind: .episode, currentTitle: "x").scope, .thisFile,
                       "the episode page still opens on This File Only")
    }

    func testTheShowsManageOffersFixMatchUnlessRestricted() {
        var c = ProductActionContext(kind: .show)
        XCTAssertEqual(ProductActions.manageList(c), [.changeArtwork, .editMetadata, .refreshMetadata, .fixMatch, .delete])
        c.fixMatchAllowed = false
        XCTAssertEqual(ProductActions.manageList(c), [.changeArtwork, .editMetadata, .refreshMetadata, .delete])
    }

    func testAMovieCannotBeGivenASeasonScope() throws {
        var vm = FixMatchViewModel(store: try LibraryRig.make().store, searcher: OneCandidate(), itemID: 1, kind: .movie, currentTitle: "x")
        vm.setScope(.wholeShow)
        XCTAssertEqual(vm.scope, .thisFile)
    }

    private func run(_ scope: FixMatchScope) async throws -> (LibraryRig, [LibraryItem], FixMatchViewModel, MemoryRecorder) {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await rig.episodes(ofSeriesTitle: "Show One")
        let target = try XCTUnwrap(eps.first { $0.season == 1 && $0.episode == 2 })
        let recorder = MemoryRecorder()
        var vm = FixMatchViewModel(store: rig.store, searcher: OneCandidate(), itemID: target.id, kind: .episode, currentTitle: "Show One", recorder: recorder)
        vm.setScope(scope)
        await vm.choose(MatchCandidate(id: 1396, title: "Fixture Show", year: 2008))
        return (rig, eps, vm, recorder)
    }

    private func ids(_ rig: LibraryRig, _ eps: [LibraryItem]) async throws -> [String: Int?] {
        var out: [String: Int?] = [:]
        for e in eps { out["S\(e.season ?? -1)E\(e.episode ?? -1)"] = try await rig.store.item(id: e.id)?.tmdbID }
        return out
    }

    func testThisFileChangesOneEpisodeAndKeepsItsOwnTitle() async throws {
        let (rig, eps, vm, recorder) = try await run(.thisFile)
        XCTAssertTrue(vm.applied)
        XCTAssertEqual(vm.appliedCount, 1)
        let tags = try await ids(rig, eps)
        XCTAssertEqual(tags["S1E2"], 1396)
        XCTAssertNil(tags["S1E1"] ?? nil)
        let item = try await rig.store.item(id: try XCTUnwrap(eps.first { $0.episode == 2 && $0.season == 1 }).id)
        XCTAssertNotEqual(item?.title, "Fixture Show", "an episode keeps its own title; only the show id is stored")
        XCTAssertEqual(recorder.records.map(\.2), [.thisFile])
    }

    func testThisSeasonChangesEveryEpisodeOfThatSeasonOnly() async throws {
        let (rig, eps, vm, recorder) = try await run(.thisSeason)
        XCTAssertEqual(vm.appliedCount, 3)
        let tags = try await ids(rig, eps)
        XCTAssertEqual(tags["S1E1"], 1396); XCTAssertEqual(tags["S1E3"], 1396)
        XCTAssertNil(tags["S2E1"] ?? nil, "another season is untouched")
        XCTAssertEqual(recorder.records.map(\.2), [.thisSeason])
    }

    func testTheWholeShowChangesEveryEpisodeIncludingSpecials() async throws {
        let (rig, eps, vm, _) = try await run(.wholeShow)
        XCTAssertEqual(vm.appliedCount, eps.count)
        let tags = try await ids(rig, eps)
        XCTAssertTrue(tags.values.allSatisfy { $0 == 1396 })
    }

    func testAMovieChoiceStoresTitleYearAndIDAndIsRecorded() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let recorder = MemoryRecorder()
        var vm = FixMatchViewModel(store: rig.store, searcher: OneCandidate(), itemID: id, kind: .movie, currentTitle: "Hexfall", recorder: recorder)
        await vm.choose(MatchCandidate(id: 949, title: "Hexfall", year: 1995))
        let item = try await rig.store.item(id: id)
        XCTAssertEqual(item?.tmdbID, 949)
        XCTAssertEqual(recorder.records.count, 1)
    }

    func testARecorderFailureIsShownAndNothingIsClaimedApplied() async throws {
        struct Failing: MatchChoiceRecording { func record(itemID: Int64, candidate: MatchCandidate, scope: FixMatchScope) async throws { throw Boom() } }
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        var vm = FixMatchViewModel(store: rig.store, searcher: OneCandidate(), itemID: id, kind: .movie, currentTitle: "Hexfall", recorder: Failing())
        await vm.choose(MatchCandidate(id: 949, title: "Hexfall", year: 1995))
        XCTAssertFalse(vm.applied)
        guard case .failed = vm.state else { return XCTFail("\(vm.state)") }
    }

    func testTheNeedsKeyTextIsExact() {
        XCTAssertEqual(OnlineLookupText.fixMatchNeedsKey, "Fix Match needs your TMDB key. Add it in Settings > Online Lookup.")
    }
}
