import XCTest
import VideoPlayerCore
import LibraryIndex
import PlaybackLogic
import UserData
@testable import AppLogic

/// The library feeding segments (`SegmentProvider`) and the next episode (`NextEpisodeFeed`) into the player's skip and Up Next state.
/// Uses the real in-memory SQLite index filled by the real syncer (`LibraryRig`), and fixture bytes for the files themselves.
final class SegmentFeedTests: XCTestCase {
    private func ledger() -> UserDataLedger { UserDataLedger(deviceID: "T", clock: { Date(timeIntervalSince1970: 1_700_000_000) }) }

    // MARK: Provider

    func testFD1_aMovieGetsItsChaptersFromTheFileTheLibraryPointsAt() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Heat")
        let files = try await rig.store.versions(of: id)
        let file = try XCTUnwrap(files.first)
        try await rig.store.setTechnicalInfo(fileID: file.id, FileTechnicalInfo(duration: 2500))
        let src = SegmentFixtureSource()
        src.put(file.path, FixtureMKV.episode())
        let provider = SegmentProvider(store: rig.store, ledger: ledger(), itemKey: { try? await rig.store.userDataKey(forItem: $0) },
                                       openSource: { sourceID in sourceID == file.sourceID ? src : nil })
        let segments = await provider.segments(forItem: id)
        XCTAssertEqual(segments.map(\.type), [.intro, .credits])
        XCTAssertTrue(segments.allSatisfy { $0.file.path == file.path && $0.file.duration == 2500 })
    }

    func testFD2_aMarkSavedUnderTheItemKeyIsFoundAgainAfterTheLibraryIsRebuiltWithNewIds() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Heat")
        let files = try await rig.store.versions(of: id)
        let file = try XCTUnwrap(files.first)
        try await rig.store.setTechnicalInfo(fileID: file.id, FileTechnicalInfo(duration: 2500))
        let storedKey = try await rig.store.userDataKey(forItem: id)
        let key = try XCTUnwrap(storedKey)
        let l = ledger()
        SegmentMarkSession(itemKey: key, ledger: l).press(.recap, at: 5, duration: 2500, date: Date(timeIntervalSince1970: 1_700_000_001))
        let session = SegmentMarkSession(itemKey: key, ledger: l)
        session.press(.recap, at: 5, duration: 2500, date: Date(timeIntervalSince1970: 1_700_000_001))
        session.press(.recap, at: 50, duration: 2500, date: Date(timeIntervalSince1970: 1_700_000_002))
        // A second library built from the same files: same keys, so the same mark applies even if the ids differ.
        let rig2 = try LibraryRig.make()
        try await rig2.fill()
        let id2 = try await rig2.movieID("Heat")
        let files2 = try await rig2.store.versions(of: id2)
        let file2 = try XCTUnwrap(files2.first)
        try await rig2.store.setTechnicalInfo(fileID: file2.id, FileTechnicalInfo(duration: 2500))
        let provider = SegmentProvider(store: rig2.store, ledger: l, itemKey: { try? await rig2.store.userDataKey(forItem: $0) }, openSource: { _ in nil })
        let segments = await provider.segments(forItem: id2)
        XCTAssertEqual(segments.map(\.type), [.recap])
        XCTAssertEqual(segments.first?.source, .userMarked)
        XCTAssertEqual(segments.first?.end, 50)
    }

    func testFD3_anUnknownItemOrAnUnopenableSourceGivesNoSegmentsNotAnError() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let provider = SegmentProvider(store: rig.store, ledger: ledger(), itemKey: { _ in nil }, openSource: { _ in nil })
        let none = await provider.segments(forItem: 999_999)
        XCTAssertTrue(none.isEmpty)
        let id = try await rig.movieID("Heat")
        let noSource = await provider.segments(forItem: id)
        XCTAssertTrue(noSource.isEmpty, "no length, no source, no marks: nothing to show, nothing thrown")
    }

    func testFD4_aSourceThatFailsEveryReadStillReturnsTheUsersMarks() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Heat")
        let files = try await rig.store.versions(of: id)
        let file = try XCTUnwrap(files.first)
        try await rig.store.setTechnicalInfo(fileID: file.id, FileTechnicalInfo(duration: 2500))
        let storedKey = try await rig.store.userDataKey(forItem: id)
        let key = try XCTUnwrap(storedKey)
        let l = ledger()
        let marker = SegmentMarkSession(itemKey: key, ledger: l)
        marker.press(.intro, at: 20, duration: 2500, date: Date(timeIntervalSince1970: 1_700_000_001))
        marker.press(.intro, at: 80, duration: 2500, date: Date(timeIntervalSince1970: 1_700_000_002))
        let broken = SegmentFixtureSource()
        broken.put(file.path, FixtureMKV.episode())
        broken.readError = SourceError.transport("reset")
        broken.listError = SourceError.transport("reset")
        let provider = SegmentProvider(store: rig.store, ledger: l, itemKey: { try? await rig.store.userDataKey(forItem: $0) }, openSource: { _ in broken })
        let segments = await provider.segments(forItem: id)
        XCTAssertEqual(segments.map(\.type), [.intro])
        XCTAssertEqual(segments.first?.source, .userMarked)
    }

    // MARK: Next episode feed

    private func series(_ rig: LibraryRig, _ title: String) async throws -> [LibraryItem] {
        try await rig.episodes(ofSeriesTitle: title).sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
    }

    func testFD5_nextEpisodeSameSeasonThenNextSeasonThenStopAndSpecialsNeverAdvance() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await series(rig, "Show One")        // S00E01, S01E01, S01E02, S01E03, S02E01
        XCTAssertEqual(eps.count, 5)
        let special = eps[0], s1e1 = eps[1], s1e2 = eps[2], s1e3 = eps[3], s2e1 = eps[4]

        let a = await NextEpisodeFeed.resolve(itemID: s1e1.id, store: rig.store)
        guard case .next(let toTwo) = a.decision else { return XCTFail("\(a.decision)") }
        XCTAssertEqual(NextEpisodeFeed.libraryItemID(for: toTwo), s1e2.id)
        XCTAssertEqual(toTwo.season, 1)
        XCTAssertEqual(toTwo.episode, 2)
        XCTAssertEqual(a.current?.seriesID, s1e1.seriesID.map { String($0) })
        XCTAssertEqual(a.nextItem?.itemID, s1e2.id)
        XCTAssertEqual(a.nextItem?.artworkKey, "item-\(s1e2.id)")

        let b = await NextEpisodeFeed.resolve(itemID: s1e3.id, store: rig.store)
        guard case .next(let rollover) = b.decision else { return XCTFail("\(b.decision)") }
        XCTAssertEqual(NextEpisodeFeed.libraryItemID(for: rollover), s2e1.id, "the last episode of a season goes to the first of the next")

        let c = await NextEpisodeFeed.resolve(itemID: s2e1.id, store: rig.store)
        XCTAssertEqual(c.decision, .none(.endOfSeries))
        XCTAssertNil(c.nextItem)

        let d = await NextEpisodeFeed.resolve(itemID: special.id, store: rig.store)
        XCTAssertEqual(d.decision, .none(.special), "Season 0 never auto-advances")
    }

    func testFD6_aFilmAnUnknownItemAndAnotherSeriesNeverGetANextEpisode() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let film = await NextEpisodeFeed.resolve(itemID: try await rig.movieID("Heat"), store: rig.store)
        XCTAssertEqual(film.decision, .none(.notAnEpisode))
        XCTAssertNil(film.current)
        let missing = await NextEpisodeFeed.resolve(itemID: 424_242, store: rig.store)
        XCTAssertEqual(missing.decision, .none(.notAnEpisode))
        let two = try await series(rig, "Show Two")
        let lone = await NextEpisodeFeed.resolve(itemID: two[0].id, store: rig.store)
        XCTAssertEqual(lone.decision, .none(.endOfSeries), "the episodes of Show One are not offered after Show Two's only episode")
    }

    func testFD7_aLibraryThatCannotBeReadGivesNoProposalInsteadOfAnError() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await series(rig, "Show One")
        let flaky = FlakyStore(rig.store)
        flaky.failing = true
        let out = await NextEpisodeFeed.resolve(itemID: eps[1].id, store: flaky)
        XCTAssertEqual(out.decision, .none(.endOfSeries), "episodes() throws, so there is nothing to offer")
        XCTAssertNotNil(out.current)
    }

    // MARK: Into the overlay controller

    func testFD8_creditsStartShowsUpNextWithTheNextEpisodesTitleAndMarksWatched() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await series(rig, "Show One")
        let feed = await NextEpisodeFeed.resolve(itemID: eps[1].id, store: rig.store)
        let file = FileIdentity(path: "/a.mkv", size: 1, duration: 1500)
        let credits = SkipSegment(type: .credits, start: 1380, end: 1500, source: .embeddedChapters, confidence: 0.9, file: file)
        let up = FakeUpNextPresenter(), skip = FakeSkipPresenter()
        let clock = ManualClock()
        let effects = SegmentFeedTests.Box()
        let controller = PlayerSessionFactory.controller(
            segments: [credits], duration: 1500, skip: PlayerSessionFactory.skipSettings(showSkipButtons: true),
            nextEpisode: PlayerSessionFactory.nextEpisodeSettings(autoPlay: true), feed: feed, clock: clock,
            upNextPresenter: up, skipPresenter: skip, sink: { effects.append($0) })
        XCTAssertTrue(controller.playhead(100, kind: .started).isEmpty)
        let hit = controller.playhead(1385, kind: .natural)
        XCTAssertTrue(hit.contains(.markWatched))
        XCTAssertEqual(up.presented.count, 1)
        XCTAssertEqual(up.presented.first?.episodeTitle, eps[2].title.isEmpty ? "Episode 2" : eps[2].title)
        XCTAssertEqual(up.presented.first?.previewKey, "item-\(eps[2].id)")
        XCTAssertEqual(skip.shown, ["Skip Credits"], "the skip button shows while the playhead is in the credits")
        clock.advance(by: 10)
        let advance = controller.tick()
        XCTAssertEqual(advance.compactMap { e -> Int64? in if case .advance(let ref) = e { return NextEpisodeFeed.libraryItemID(for: ref) } else { return nil } }, [eps[2].id])
    }

    func testFD9_theShowSkipButtonsSwitchTurnsTheButtonOffButUpNextStays() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await series(rig, "Show One")
        let feed = await NextEpisodeFeed.resolve(itemID: eps[1].id, store: rig.store)
        let file = FileIdentity(path: "/a.mkv", size: 1, duration: 1500)
        let intro = SkipSegment(type: .intro, start: 60, end: 120, source: .embeddedChapters, confidence: 0.9, file: file)
        let credits = SkipSegment(type: .credits, start: 1380, end: 1500, source: .embeddedChapters, confidence: 0.9, file: file)
        let up = FakeUpNextPresenter(), skip = FakeSkipPresenter()
        let controller = PlayerSessionFactory.controller(
            segments: [intro, credits], duration: 1500, skip: PlayerSessionFactory.skipSettings(showSkipButtons: false),
            nextEpisode: NextEpisodeSettings(), feed: feed, clock: ManualClock(), upNextPresenter: up, skipPresenter: skip, sink: { _ in })
        controller.playhead(90, kind: .natural)
        XCTAssertTrue(skip.shown.isEmpty, "Show Skip Buttons off: no Skip Intro")
        controller.playhead(1385, kind: .natural)
        XCTAssertEqual(up.presented.count, 1, "Up Next is its own setting")
    }

    func testFD10_withNoNextEpisodeThereIsNoProposalAndTheFileEndIsReported() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await series(rig, "Show One")
        let feed = await NextEpisodeFeed.resolve(itemID: eps[4].id, store: rig.store)     // the last one
        let file = FileIdentity(path: "/a.mkv", size: 1, duration: 1500)
        let credits = SkipSegment(type: .credits, start: 1380, end: 1500, source: .embeddedChapters, confidence: 0.9, file: file)
        let up = FakeUpNextPresenter()
        let controller = PlayerSessionFactory.controller(
            segments: [credits], duration: 1500, skip: SkipSettings(), nextEpisode: NextEpisodeSettings(), feed: feed, clock: ManualClock(),
            upNextPresenter: up, skipPresenter: nil, sink: { _ in })
        controller.playhead(1390, kind: .natural)
        XCTAssertTrue(up.presented.isEmpty)
        XCTAssertTrue(controller.ended().contains(.playbackEnded))
    }

    func testFD11_theSettingMappingsAreWhatTheDocsSay() {
        XCTAssertEqual(PlayerSessionFactory.skipSettings(showSkipButtons: true), SkipSettings())
        XCTAssertEqual(PlayerSessionFactory.skipSettings(showSkipButtons: false).setting(for: .intro), .off)
        XCTAssertEqual(PlayerSessionFactory.nextEpisodeSettings(autoPlay: true).mode, .whenCreditsBegin)
        XCTAssertEqual(PlayerSessionFactory.nextEpisodeSettings(autoPlay: false).mode, .ask)
        XCTAssertEqual(PlayerSessionFactory.nextEpisodeSettings(autoPlay: true, countdownSeconds: 99).countdownSeconds, 30)
    }

    func testFD12_mergedCreditsNearAPostCreditsChapterAreNotStretchedBySessionBuilding() {
        let file = FileIdentity(path: "/a.mkv", size: 1, duration: 1500)
        let credits = SkipSegment(type: .credits, start: 1380, end: 1470, source: .embeddedChapters, confidence: 0.9, file: file)
        let session = PlayerSessionFactory.session(segments: [credits], duration: 1500, skip: SkipSettings(), nextEpisode: NextEpisodeSettings(),
                                                   next: .none(.endOfSeries), clock: ManualClock())
        XCTAssertEqual(session.resolved.segment(of: .credits)?.end, 1470, "skipping credits must not jump over the scene that follows them")
    }

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [[PlayerOverlayEffect]] = []
        func append(_ e: [PlayerOverlayEffect]) { lock.withLock { all.append(e) } }
        var value: [[PlayerOverlayEffect]] { lock.withLock { all } }
    }
}
