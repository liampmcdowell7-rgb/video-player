import XCTest
@testable import AppLogic

/// R386: the failure report names the system player's error (domain, code, underlying errors) and the last event with its
/// time, and the start's 30-second limit never ends a video that is already playing.
final class PlaybackDiagnosticsTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    // MARK: The start counts as playing

    func testTheStartCountsAsPlayingWhenThePlayerSaysSoOrThePlayheadMoved() {
        XCTAssertTrue(PlaybackStartProgress.hasStarted(isPlaying: true, positionAtPlay: nil, position: nil),
                      "already playing when play was asked for: no change of state follows, and none is needed")
        XCTAssertTrue(PlaybackStartProgress.hasStarted(isPlaying: false, positionAtPlay: 120, position: 121))
        XCTAssertFalse(PlaybackStartProgress.hasStarted(isPlaying: false, positionAtPlay: 120, position: 120.2))
        XCTAssertFalse(PlaybackStartProgress.hasStarted(isPlaying: false, positionAtPlay: nil, position: 30))
        XCTAssertFalse(PlaybackStartProgress.hasStarted(isPlaying: false, positionAtPlay: 0, position: .nan))
    }

    // MARK: The player's error

    func testTheReportFollowsTheUnderlyingErrors() {
        let inner = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        let middle = NSError(domain: "CoreMediaErrorDomain", code: -12938,
                             userInfo: [NSLocalizedDescriptionKey: "HTTP 500", NSUnderlyingErrorKey: inner])
        let outer = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                            userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed", NSUnderlyingErrorKey: middle])
        let report = PlayerErrorReport(outer)
        XCTAssertEqual(report.codeLine, "AVFoundationErrorDomain -11800")
        XCTAssertEqual(report.message, "The operation could not be completed")
        XCTAssertEqual(report.underlying, ["CoreMediaErrorDomain -12938: HTTP 500", "NSURLErrorDomain -1001: The request timed out."])
        XCTAssertEqual(PlayerErrorReport(domain: "D", code: 1, message: "m").underlyingText, PlayerErrorReport.noUnderlying)
    }

    func testAnUnderlyingLoopStopsAtTheLimit() {
        let deep = (0..<10).reduce(NSError(domain: "E", code: 0)) { inner, n in
            NSError(domain: "E", code: n + 1, userInfo: [NSUnderlyingErrorKey: inner])
        }
        XCTAssertEqual(PlayerErrorReport(deep).underlying.count, PlayerErrorReport.maxDepth)
    }

    // MARK: Events

    func testAnEventSaysWhatWhereAndWhen() {
        let at = Date(timeIntervalSince1970: 3600 * 21 + 4 * 60 + 5)
        let event = PlaybackEvent(name: "Stalled", position: 31.4, elapsed: 33.2, at: at)
        XCTAssertEqual(event.line(timeZone: utc), "Stalled · video at 0:31 · 33 s after the player opened · 21:04:05")
        XCTAssertEqual(PlaybackEvent(name: "Opened", position: nil, elapsed: nil, at: at).line(timeZone: utc), "Opened · 21:04:05")
        XCTAssertEqual(PlaybackEvent.clock(3723), "1:02:03")
    }

    func testTheLogKeepsTheNewestEvents() {
        let log = PlaybackEventLog(capacity: 3)
        for n in 1...5 { log.record("e\(n)", position: Double(n), elapsed: nil) }
        XCTAssertEqual(log.recent.map(\.name), ["e3", "e4", "e5"])
        XCTAssertEqual(log.last?.name, "e5")
    }

    // MARK: The stored problem and the screen

    func testTheProblemKeepsTheReportAndEventsWithTokensRemoved() {
        let tracker = PlaybackStartTracker()
        tracker.describe(secrets: ["SECRETTOKEN1"])
        tracker.enter(.playing)
        let report = PlayerErrorReport(domain: "CoreMediaErrorDomain", code: -12938, message: "GET /a?X-Plex-Token=SECRETTOKEN1 failed",
                                       underlying: ["NSURLErrorDomain -1001: token=abcdefgh"])
        let events = [PlaybackEvent(name: "Item failed (SECRETTOKEN1)", position: 31, elapsed: 33, at: Date(timeIntervalSince1970: 0))]
        let problem = tracker.problem(PlaybackFailures.playerFailure(.network),
                                      diagnostics: PlaybackDiagnostics(detail: nil, player: report, events: events))
        XCTAssertFalse(problem.player!.message.contains("SECRETTOKEN1"))
        XCTAssertFalse(problem.player!.underlying[0].contains("abcdefgh"))
        XCTAssertFalse(problem.lastEvent!.name.contains("SECRETTOKEN1"))
        let rows = Dictionary(uniqueKeysWithValues: problem.rows.map { ($0.label, $0.value) })
        XCTAssertEqual(rows["Error Code"], "CoreMediaErrorDomain -12938")
        XCTAssertEqual(problem.rows.last?.label, "Error", "the error text stays last")
        let lines = problem.screenLines(timeZone: utc)
        XCTAssertEqual(lines.first, "Error: CoreMediaErrorDomain -12938")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Underlying: NSURLErrorDomain -1001") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("Last event: ") && $0.contains("video at 0:31") && $0.hasSuffix("00:00:00") })
        XCTAssertTrue(problem.fullText(timeZone: utc).contains("Recent Events:"))
    }

    func testAProblemStoredByTheEarlierVersionStillDecodes() throws {
        // The R311 form: no player report and no events.
        let old = #"{"step":"startPlaying","sourceKind":"Plex","container":"MKV","error":"x","at":0}"#
        let problem = try XCTUnwrap(PlaybackProblem.decoded(Data(old.utf8)))
        XCTAssertNil(problem.player)
        XCTAssertNil(problem.lastEvent)
        XCTAssertEqual(problem.screenLines(timeZone: utc), ["Step: " + PlaybackStep.startPlaying.title])
        let rows = Dictionary(uniqueKeysWithValues: problem.rows.map { ($0.label, $0.value) })
        XCTAssertEqual(rows["Last Event"], PlaybackProblem.notKnown)
    }

    func testANewProblemRoundTrips() {
        let problem = PlaybackProblem(step: .playing, sourceKind: "SMB", container: "MKV", codecs: "HEVC", error: "x",
                                      at: Date(timeIntervalSince1970: 1_000),
                                      player: PlayerErrorReport(domain: "D", code: 2, message: "m", underlying: ["u"]),
                                      events: [PlaybackEvent(name: "e", position: 1, elapsed: 2, at: Date(timeIntervalSince1970: 1_000))])
        XCTAssertEqual(PlaybackProblem.decoded(problem.encoded()), problem)
    }
}
