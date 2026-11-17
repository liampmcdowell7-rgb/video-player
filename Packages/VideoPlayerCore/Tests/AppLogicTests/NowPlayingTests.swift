import XCTest
import PlaybackLogic
@testable import AppLogic

final class FakeNowPlayingPublisher: NowPlayingPublishing, @unchecked Sendable {
    private let lock = NSLock()
    private var _snapshots: [NowPlayingSnapshot] = []
    private var _commands: [RemoteCommandState] = []
    private var _clears = 0
    var snapshots: [NowPlayingSnapshot] { lock.withLock { _snapshots } }
    var commands: [RemoteCommandState] { lock.withLock { _commands } }
    var clears: Int { lock.withLock { _clears } }
    func publish(_ snapshot: NowPlayingSnapshot) { lock.withLock { _snapshots.append(snapshot) } }
    func apply(_ commands: RemoteCommandState) { lock.withLock { _commands.append(commands) } }
    func clear() { lock.withLock { _clears += 1 } }
}

final class NowPlayingTests: XCTestCase {
    private let movie = NowPlayingContent(kind: .movie, title: "Heat", year: 1995, artworkKey: "item-1", externalID: "1")
    private let episode = NowPlayingContent(kind: .episode, title: "The Return", seriesTitle: "Show One", season: 2, episode: 1,
                                            artworkKey: "item-9", externalID: "9")

    func testMovieSnapshot() {
        let s = NowPlayingMapper.snapshot(movie, duration: 6_000, position: 120, rate: 1)
        XCTAssertEqual(s[.title], .string("Heat"))
        XCTAssertNil(s[.artist])
        XCTAssertEqual(s[.mediaType], .mediaTypeVideo)
        XCTAssertEqual(s[.playbackDuration], .number(6_000))
        XCTAssertEqual(s[.elapsedPlaybackTime], .number(120))
        XCTAssertEqual(s[.playbackRate], .number(1))
        XCTAssertEqual(s[.defaultPlaybackRate], .number(1))
        XCTAssertEqual(s[.artwork], .artworkKey("item-1"))
        XCTAssertEqual(s[.externalContentIdentifier], .string("1"))
    }

    func testEpisodeSnapshotNamesTheSeriesAndSeason() {
        let s = NowPlayingMapper.snapshot(episode, duration: 2_400, position: 0, rate: 0)
        XCTAssertEqual(s[.title], .string("The Return"))
        XCTAssertEqual(s[.artist], .string("Show One"))
        XCTAssertEqual(s[.albumTitle], .string("Season 2"))
        XCTAssertEqual(s[.albumTrackNumber], .number(1))
        XCTAssertEqual(s[.playbackRate], .number(0))
    }

    func testSpecialsAreLabeledAndMissingTitlesNeverShowEmpty() {
        let special = NowPlayingContent(kind: .episode, title: "  ", seriesTitle: "Show One", season: 0, episode: 3)
        let s = NowPlayingMapper.snapshot(special, duration: nil, position: 5, rate: 1)
        XCTAssertEqual(s[.albumTitle], .string("Specials"))
        XCTAssertEqual(s[.title], .string("Episode 3"))
        XCTAssertNil(s[.playbackDuration], "unknown duration is left out, not zero")
        let blank = NowPlayingContent(kind: .movie, title: nil)
        XCTAssertEqual(NowPlayingMapper.snapshot(blank, duration: 1, position: 0, rate: 0)[.title], .string("Untitled"))
    }

    func testElapsedTimeIsClampedIntoTheDuration() {
        XCTAssertEqual(NowPlayingMapper.snapshot(movie, duration: 100, position: 250, rate: 1)[.elapsedPlaybackTime], .number(100))
        XCTAssertEqual(NowPlayingMapper.snapshot(movie, duration: 100, position: -4, rate: 1)[.elapsedPlaybackTime], .number(0))
    }

    func testRemoteCommandPlan() {
        let playing = RemoteCommandPlanner.state(isPlaying: true, hasContent: true, duration: 600, hasNextEpisode: true)
        XCTAssertTrue(playing.pause)
        XCTAssertFalse(playing.play)
        XCTAssertTrue(playing.togglePlayPause)
        XCTAssertEqual(playing.skipForwardInterval, 10)
        XCTAssertEqual(playing.skipBackwardInterval, 10)
        XCTAssertTrue(playing.changePlaybackPosition)
        XCTAssertTrue(playing.nextTrack)
        XCTAssertFalse(playing.previousTrack)
        let paused = RemoteCommandPlanner.state(isPlaying: false, hasContent: true, duration: nil, hasNextEpisode: false)
        XCTAssertTrue(paused.play)
        XCTAssertFalse(paused.pause)
        XCTAssertNil(paused.skipForwardInterval, "no duration, no skipping or scrubbing")
        XCTAssertFalse(paused.changePlaybackPosition)
        XCTAssertFalse(paused.nextTrack)
        let none = RemoteCommandPlanner.state(isPlaying: false, hasContent: false, duration: 600, hasNextEpisode: true)
        XCTAssertFalse(none.play || none.pause || none.togglePlayPause || none.nextTrack || none.changePlaybackPosition)
        XCTAssertNil(none.skipForwardInterval)
    }

    func testSessionPublishesOnStartAndOnlyWhenSomethingChanges() {
        let clock = ManualClock()
        let pub = FakeNowPlayingPublisher()
        let session = NowPlayingSession(publisher: pub, clock: clock)
        session.update(position: 5, rate: 1)
        XCTAssertTrue(pub.snapshots.isEmpty, "nothing before start")

        session.start(episode, duration: 2_400, hasNextEpisode: true, position: 0, rate: 1)
        XCTAssertEqual(pub.snapshots.count, 1)
        XCTAssertEqual(pub.commands.count, 1)
        XCTAssertTrue(pub.commands[0].nextTrack)

        // Normal playback: the system extrapolates, so nothing is sent.
        for second in 1...10 {
            clock.advance(by: 1)
            session.update(position: Double(second), rate: 1)
        }
        XCTAssertEqual(pub.snapshots.count, 1)

        // Pause: rate change.
        session.update(position: 10, rate: 0)
        XCTAssertEqual(pub.snapshots.count, 2)
        XCTAssertEqual(pub.snapshots[1][.playbackRate], .number(0))
        XCTAssertEqual(pub.commands.count, 2)
        XCTAssertTrue(pub.commands[1].play)

        // Resume and then a jump of 300 s.
        session.update(position: 10, rate: 1)
        XCTAssertEqual(pub.snapshots.count, 3)
        clock.advance(by: 1)
        session.update(position: 311, rate: 1)
        XCTAssertEqual(pub.snapshots.count, 4)
        XCTAssertEqual(pub.snapshots[3][.elapsedPlaybackTime], .number(311))

        // A small wobble below the tolerance is ignored.
        clock.advance(by: 1)
        session.update(position: 312.8, rate: 1)
        XCTAssertEqual(pub.snapshots.count, 4)
    }

    func testSessionRefreshesAPlayingEntryEveryThirtySeconds() {
        let clock = ManualClock()
        let pub = FakeNowPlayingPublisher()
        let session = NowPlayingSession(publisher: pub, clock: clock)
        session.start(movie, duration: 6_000, hasNextEpisode: false, position: 0, rate: 1)
        clock.advance(by: 29)
        session.update(position: 29, rate: 1)
        XCTAssertEqual(pub.snapshots.count, 1)
        clock.advance(by: 1)
        session.update(position: 30, rate: 1)
        XCTAssertEqual(pub.snapshots.count, 2)
    }

    func testNextEpisodeKnowledgeChangesOnlyTheCommands() {
        let pub = FakeNowPlayingPublisher()
        let session = NowPlayingSession(publisher: pub, clock: ManualClock())
        session.start(episode, duration: 2_400, hasNextEpisode: false, rate: 1)
        XCTAssertFalse(pub.commands.last!.nextTrack)
        session.nextEpisodeChanged(true)
        XCTAssertTrue(pub.commands.last!.nextTrack)
        let count = pub.commands.count
        session.nextEpisodeChanged(true)
        XCTAssertEqual(pub.commands.count, count, "no repeat")
        XCTAssertEqual(pub.snapshots.count, 1)
    }

    func testStopClearsTheEntryAndTurnsEveryCommandOff() {
        let pub = FakeNowPlayingPublisher()
        let session = NowPlayingSession(publisher: pub, clock: ManualClock())
        session.stop()
        XCTAssertEqual(pub.clears, 0, "stop before start does nothing")
        session.start(movie, duration: 100, hasNextEpisode: false, rate: 1)
        session.stop()
        XCTAssertEqual(pub.clears, 1)
        let last = pub.commands.last!
        XCTAssertFalse(last.play || last.pause || last.togglePlayPause || last.nextTrack)
        session.update(position: 5, rate: 1)
        XCTAssertEqual(pub.snapshots.count, 1, "nothing after stop")
        session.stop()
        XCTAssertEqual(pub.clears, 1)
    }

    func testEveryFieldNamesAnAppleConstant() {
        for field in NowPlayingField.allCases { XCTAssertTrue(field.symbolName.hasPrefix("MP"), field.symbolName) }
        XCTAssertEqual(Set(NowPlayingField.allCases.map(\.symbolName)).count, NowPlayingField.allCases.count)
    }
}
