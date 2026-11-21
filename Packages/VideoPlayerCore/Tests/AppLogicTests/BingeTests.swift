import XCTest
import LibraryIndex
import PlaybackLogic
@testable import AppLogic

/// R314: the binge chain as the player runs it (the system Up Next, R340): at the credits start (or the end, with no credits
/// marker) the card is presented with its countdown, accepting plays the next episode, and that episode's intro is skipped
/// by itself when Skip Intros Automatically is on. Play Next Episode Automatically stays the master switch.
final class BingeTests: XCTestCase {
    private let file = FileIdentity(path: "/tv/Show One/S01E02.mkv", size: 1, duration: 1500)

    private func episodes(_ rig: LibraryRig) async throws -> [LibraryItem] {
        try await rig.episodes(ofSeriesTitle: "Show One").sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
    }

    private func controller(_ segments: [SkipSegment], feed: NextEpisodeFeed.Outcome, skip: SkipSettings, up: FakeUpNextPresenter,
                            skipPresenter: FakeSkipPresenter = FakeSkipPresenter(), effects: SegmentFeedTests.Box) -> PlayerOverlayController {
        PlayerSessionFactory.controller(segments: segments, duration: 1500, skip: skip, nextEpisode: PlayerSessionFactory.systemUpNextSettings(),
                                        feed: feed, clock: ManualClock(), upNextPresenter: up, skipPresenter: skipPresenter,
                                        sink: { effects.append($0) })
    }

    private func advanced(_ effects: SegmentFeedTests.Box) -> [Int64] {
        effects.value.flatMap { $0 }.compactMap { e -> Int64? in
            if case .advance(let ref) = e { return NextEpisodeFeed.libraryItemID(for: ref) }
            return nil
        }
    }

    func testTheCardAppearsAtTheCreditsStartAndAcceptingPlaysTheNextEpisode() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await episodes(rig)
        let feed = await NextEpisodeFeed.resolve(itemID: eps[1].id, store: rig.store)
        let credits = SkipSegment(type: .credits, start: 1380, end: 1500, source: .serverMarkers, confidence: 1, file: file)
        let up = FakeUpNextPresenter(), effects = SegmentFeedTests.Box()
        let c = controller([credits], feed: feed, skip: PlayerSessionFactory.skipSettings(showSkipButtons: true, skipIntros: true, skipCredits: false),
                           up: up, effects: effects)
        c.playhead(1379, kind: .natural)
        XCTAssertTrue(up.presented.isEmpty)
        c.playhead(1380, kind: .natural)
        XCTAssertEqual(up.presented.count, 1, "at the credits start")
        // The system counts down (Auto-Play on: 10 s after the card, counted from the end of the file) and accepts.
        XCTAssertEqual(UpNextCard.acceptanceInterval(autoPlay: true, position: 1380, duration: 1500), -110)
        XCTAssertTrue(UpNextCard.acceptanceInterval(autoPlay: false, position: 1380, duration: 1500).isNaN, "the master switch off: it waits")
        c.proposalAccepted()
        XCTAssertEqual(advanced(effects), [eps[2].id])
    }

    func testWithNoCreditsMarkerTheCardAppearsAtTheEnd() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await episodes(rig)
        let feed = await NextEpisodeFeed.resolve(itemID: eps[1].id, store: rig.store)
        let up = FakeUpNextPresenter(), effects = SegmentFeedTests.Box()
        let c = controller([], feed: feed, skip: SkipSettings(), up: up, effects: effects)
        c.playhead(1400, kind: .natural)
        XCTAssertTrue(up.presented.isEmpty)
        c.playhead(1499.5, kind: .natural)
        XCTAssertEqual(up.presented.count, 1, "at the end of the file")
    }

    func testTheNextEpisodeSkipsItsIntroByItselfAndOffersTheWayBack() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await episodes(rig)
        let feed = await NextEpisodeFeed.resolve(itemID: eps[2].id, store: rig.store)
        let next = FileIdentity(path: "/tv/Show One/S01E03.mkv", size: 1, duration: 1500)
        let intro = SkipSegment(type: .intro, start: 0, end: 52, source: .serverMarkers, confidence: 1, file: next)
        let up = FakeUpNextPresenter(), skip = FakeSkipPresenter(), effects = SegmentFeedTests.Box()
        let c = controller([intro], feed: feed, skip: PlayerSessionFactory.skipSettings(showSkipButtons: true, skipIntros: true, skipCredits: false),
                           up: up, skipPresenter: skip, effects: effects)
        c.playhead(0, kind: .natural)
        XCTAssertEqual(effects.value.flatMap { $0 }.first, .seek(to: 52), "from its first second")
        c.playhead(52, kind: .seek)
        XCTAssertEqual(skip.shown.last, "Watch Intro")
        skip.press()
        XCTAssertEqual(effects.value.flatMap { $0 }.last, .seek(to: 0))
    }

    func testWithSkipIntrosOffTheButtonShowsAsBefore() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await episodes(rig)
        let feed = await NextEpisodeFeed.resolve(itemID: eps[2].id, store: rig.store)
        let intro = SkipSegment(type: .intro, start: 0, end: 52, source: .serverMarkers, confidence: 1, file: file)
        let skip = FakeSkipPresenter(), effects = SegmentFeedTests.Box()
        let c = controller([intro], feed: feed, skip: PlayerSessionFactory.skipSettings(showSkipButtons: true, skipIntros: false, skipCredits: false),
                           up: FakeUpNextPresenter(), skipPresenter: skip, effects: effects)
        c.playhead(1, kind: .natural)
        XCTAssertEqual(skip.shown, ["Skip Intro"])
        XCTAssertTrue(effects.value.isEmpty, "no jump")
    }

    func testSkipCreditsAutomaticallyJumpsToTheEndAndTheCardAppearsAtOnce() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await episodes(rig)
        let feed = await NextEpisodeFeed.resolve(itemID: eps[1].id, store: rig.store)
        let credits = SkipSegment(type: .credits, start: 1380, end: 1500, source: .serverMarkers, confidence: 1, file: file)
        let up = FakeUpNextPresenter(), effects = SegmentFeedTests.Box()
        let c = controller([credits], feed: feed, skip: PlayerSessionFactory.skipSettings(showSkipButtons: true, skipIntros: true, skipCredits: true),
                           up: up, effects: effects)
        c.playhead(1380, kind: .natural)
        XCTAssertEqual(up.presented.count, 1, "the card, counting down")
        XCTAssertTrue(advanced(effects).isEmpty, "the system's countdown decides, not the logic")
        c.proposalAccepted()
        XCTAssertEqual(advanced(effects), [eps[2].id])
    }

    func testTheSettingsMapping() {
        let both = PlayerSessionFactory.skipSettings(showSkipButtons: true, skipIntros: true, skipCredits: true)
        XCTAssertEqual(both, SkipSettings(recap: .automatic, intro: .automatic, credits: .automatic, untrustedFallback: .ask))
        let introOnly = PlayerSessionFactory.skipSettings(showSkipButtons: true, skipIntros: true, skipCredits: false)
        XCTAssertEqual(introOnly.credits, .ask)
        let noButtons = PlayerSessionFactory.skipSettings(showSkipButtons: false, skipIntros: true, skipCredits: false)
        XCTAssertEqual(noButtons, SkipSettings(recap: .automatic, intro: .automatic, credits: .off, untrustedFallback: .off))
        XCTAssertTrue(SettingsKey.skipIntrosAutomatically.defaultBool, "on by default (owner)")
        XCTAssertFalse(SettingsKey.skipCreditsAutomatically.defaultBool)
    }
}
