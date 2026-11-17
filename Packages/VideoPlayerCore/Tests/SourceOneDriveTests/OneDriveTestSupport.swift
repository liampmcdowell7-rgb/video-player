import Foundation
import XCTest
import VideoPlayerCore
@testable import SourceOneDrive

// Test helpers. Responses come from OneDriveFixtures, which are hand-written from Microsoft's
// documentation and NOT recorded from the real service.

final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    private let handler: @Sendable (HTTPRequest, Int) -> HTTPResponse

    /// The handler gets the request and its zero-based position in the conversation.
    init(_ handler: @escaping @Sendable (HTTPRequest, Int) -> HTTPResponse) { self.handler = handler }

    var requests: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return recorded }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock(); let index = recorded.count; recorded.append(request); lock.unlock()
        return handler(request, index)
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock() }
    var clock: OneDriveClock { { [self] in self.now } }
}

final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []
    private let clock: TestClock?
    init(advancing clock: TestClock? = nil) { self.clock = clock }
    var values: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return recorded }
    var sleeper: OneDriveSleeper {
        { [self] seconds in
            self.lock.lock(); self.recorded.append(seconds); self.lock.unlock()
            self.clock?.advance(seconds)
        }
    }
}

enum Support {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    static let clientID = "test-client-id-not-a-real-registration"

    static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: headers, body: Data(body.utf8))
    }

    static func bodyText(_ request: HTTPRequest) -> String {
        String(decoding: request.body ?? Data(), as: UTF8.self)
    }

    static func goodTokens(expiresIn: TimeInterval = 3600) -> OneDriveTokens {
        OneDriveTokens(accessToken: "ACCESS-0", refreshToken: "REFRESH-0", expiresAt: t0.addingTimeInterval(expiresIn))
    }

    static func make(
        clientID: String? = Support.clientID,
        tokens: OneDriveTokens? = Support.goodTokens(),
        transport: ScriptedTransport,
        sleeps: SleepLog = SleepLog(),
        clock: TestClock = TestClock(Support.t0),
        maxRetries: Int = 3
    ) -> (source: OneDriveSource, store: InMemoryTokenStore) {
        let store = InMemoryTokenStore(tokens)
        let configuration = OneDriveConfiguration(clientID: clientID, maxRetries: maxRetries)
        let source = OneDriveSource(
            configuration: configuration, tokenStore: store, transport: transport,
            sleep: sleeps.sleeper, now: clock.clock)
        return (source, store)
    }
}
