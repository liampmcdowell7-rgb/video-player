import XCTest
import VideoPlayerCore
@testable import SourcePlex

/// Stage 2 (docs/PLEX_SOURCE.md section 1; R302): the short-code sign-in against the fake plex.tv. No network, no waiting:
/// the one-second pause and the clock are injected.
final class PlexSignInTests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")

    /// A clock the test moves by hand; `sleep` advances it instead of waiting.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = Date(timeIntervalSince1970: 1_000_000)
        private(set) var sleeps: [TimeInterval] = []
        var now: Date { lock.lock(); defer { lock.unlock() }; return current }
        func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; sleeps.append(seconds); lock.unlock() }
    }

    private func signIn(_ server: FakePlexServer, clock: Clock, fallback: TimeInterval = 600) -> PlexPinSignIn {
        PlexPinSignIn(identity: identity, transport: server, plexTV: URL(string: "https://plex.tv")!, fallbackLifetime: fallback,
                      sleep: { clock.advance($0) }, now: { clock.now })
    }

    func testANewCodeIsAskedForWithoutTheStrongFlagAndWithoutAToken() async throws {
        let server = try FakePlexServer()
        let code = try await signIn(server, clock: Clock()).start()
        XCTAssertEqual(code.code, "WX1Z")
        XCTAssertEqual(code.linkText, "plex.tv/link")
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/v2/pins")
        XCTAssertFalse(request.url.absoluteString.contains("strong"), "a short code is asked for (the TV cannot show a long one)")
        XCTAssertNil(request.headers["X-Plex-Token"])
        XCTAssertEqual(request.headers["X-Plex-Client-Identifier"], "install-1234")
    }

    func testTheCodeLastsAsLongAsTheAnswerSaysOrTheFallback() async throws {
        let server = try FakePlexServer()
        let clock = Clock()
        server.pinExpiresIn = 900
        let given = try await signIn(server, clock: clock).start()
        XCTAssertEqual(given.expiresAt.timeIntervalSince(clock.now), 900, accuracy: 0.001)
        server.pinExpiresIn = nil
        let fallback = try await signIn(server, clock: clock, fallback: 600).start()
        XCTAssertEqual(fallback.expiresAt.timeIntervalSince(clock.now), 600, accuracy: 0.001)
    }

    func testPollingOncePerSecondReturnsTheAccountTokenWhenTheCodeIsEntered() async throws {
        let server = try FakePlexServer()
        server.claimAfterPolls = 3
        let clock = Clock()
        let flow = signIn(server, clock: clock)
        let code = try await flow.start()
        let token = try await flow.waitForToken(code)
        XCTAssertEqual(token, "account-token-placeholder")
        XCTAssertEqual(clock.sleeps, [1, 1], "one pause of one second between polls")
        let polls = server.requests.filter { $0.method == "GET" }
        XCTAssertEqual(polls.count, 3)
        XCTAssertTrue(polls.allSatisfy { $0.url.path == "/api/v2/pins/\(code.id)" && $0.headers["X-Plex-Token"] == nil })
    }

    func testTheCodeExpiresByTheClock() async throws {
        let server = try FakePlexServer()
        server.claimAfterPolls = nil
        server.pinExpiresIn = 5
        let clock = Clock()
        let flow = signIn(server, clock: clock)
        let code = try await flow.start()
        do {
            _ = try await flow.waitForToken(code)
            XCTFail("expected the code to expire")
        } catch PlexError.codeExpired {
            XCTAssertEqual(server.requests.filter { $0.method == "GET" }.count, 5, "no poll after the code ran out")
        }
    }

    func testAGonePinIsAnExpiredCode() async throws {
        let server = try FakePlexServer()
        server.claimAfterPolls = nil
        server.expireAfterPolls = 2
        let flow = signIn(server, clock: Clock())
        let code = try await flow.start()
        do {
            _ = try await flow.waitForToken(code)
            XCTFail("expected the code to expire")
        } catch PlexError.codeExpired {}
    }

    func testGetANewCodeGivesADifferentCode() async throws {
        let server = try FakePlexServer()
        let flow = signIn(server, clock: Clock())
        let first = try await flow.start()
        let second = try await flow.start()
        XCTAssertNotEqual(first.code, second.code)
        XCTAssertEqual(server.pinsCreated, 2)
    }

    func testTheExpiredMessageNamesTheAction() {
        XCTAssertEqual(PlexError.codeExpired.errorDescription, "The code expired. Choose Get a New Code.")
    }

    func testCancellingStopsThePolling() async throws {
        let server = try FakePlexServer()
        server.claimAfterPolls = nil
        let flow = signIn(server, clock: Clock())
        let code = try await flow.start()
        let task = Task { try await flow.waitForToken(code) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
    }

    /// Every check carries the PIN's code as the query parameter `code` (owner's instruction, 21 Nov 2026; the guide read the
    /// same day shows the check without it, so it is harmless extra), and never a token.
    func testEveryCheckSendsTheCodeAsAQueryParameter() async throws {
        let server = try FakePlexServer()
        server.claimAfterPolls = 2
        let flow = signIn(server, clock: Clock())
        let code = try await flow.start()
        _ = try await flow.waitForToken(code)
        let checks = server.requests.filter { $0.method == "GET" && $0.url.path == "/api/v2/pins/\(code.id)" }
        XCTAssertEqual(checks.count, 2)
        for check in checks {
            let items = URLComponents(url: check.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(items, [URLQueryItem(name: "code", value: code.code)])
            XCTAssertEqual(check.headers["X-Plex-Client-Identifier"], "install-1234")
            XCTAssertNil(check.headers["X-Plex-Token"])
        }
    }
}
