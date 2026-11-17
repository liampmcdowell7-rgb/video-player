import XCTest
import VideoPlayerCore
@testable import MetadataOnline

/// Queue behaviour with a fake clock and a mock transport. Nothing waits and nothing touches the network.
final class RequestQueueTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/x")
    private var request: HTTPRequest { HTTPRequest(url: URL(string: "https://example.invalid/x") ?? url, method: "GET") }

    private func sequence(_ responses: [HTTPResponse]) -> MockTransport {
        let box = Box(responses)
        return MockTransport { _ in box.next() }
    }

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [HTTPResponse]
        init(_ items: [HTTPResponse]) { self.items = items }
        func next() -> HTTPResponse {
            lock.lock(); defer { lock.unlock() }
            return items.count > 1 ? items.removeFirst() : (items.first ?? HTTPResponse(statusCode: 500))
        }
    }

    func testSuccessPassesThroughWithoutSleeping() async throws {
        let clock = FakeClock()
        let transport = sequence([response(200, "ok")])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(), clock: clock)
        let r = try await queue.send(request)
        XCTAssertEqual(r.statusCode, 200)
        XCTAssertEqual(transport.count, 1)
        XCTAssertEqual(clock.sleeps, [])
    }

    func testClientErrorsOtherThan429AreReturnedNotRetried() async throws {
        let transport = sequence([response(404)])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(), clock: FakeClock())
        let r = try await queue.send(request)
        XCTAssertEqual(r.statusCode, 404)
        XCTAssertEqual(transport.count, 1)
    }

    func testRequestsAreSpacedByTheMinimumInterval() async throws {
        let clock = FakeClock()
        let queue = ProviderQueue(transport: sequence([response(200)]), configuration: plainQueue(minInterval: 0.5), clock: clock)
        for _ in 0..<3 { _ = try await queue.send(request) }
        XCTAssertEqual(clock.sleeps, [0.5, 0.5])
    }

    func testRetryAfterSecondsIsHonouredExactly() async throws {
        let clock = FakeClock()
        let transport = sequence([response(429, headers: ["Retry-After": "7"]), response(200, "ok")])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(), clock: clock)
        let r = try await queue.send(request)
        XCTAssertEqual(r.statusCode, 200)
        XCTAssertEqual(transport.count, 2)
        XCTAssertEqual(clock.totalSlept, 7, accuracy: 0.001)
    }

    func testRetryAfterHTTPDate() async throws {
        let clock = FakeClock(start: Date(timeIntervalSince1970: 784_111_777)) // Sun, 06 Nov 1994 08:49:37 GMT
        let transport = sequence([response(429, headers: ["Retry-After": "Sun, 06 Nov 1994 08:49:47 GMT"]), response(200)])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(), clock: clock)
        _ = try await queue.send(request)
        XCTAssertEqual(clock.totalSlept, 10, accuracy: 0.001)
    }

    func testRateLimitWithoutHeaderUsesBackoff() async throws {
        let clock = FakeClock()
        let transport = sequence([response(429), response(429), response(200)])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(base: 2), clock: clock)
        _ = try await queue.send(request)
        XCTAssertEqual(clock.sleeps, [2, 4])
    }

    func testRateLimitGivesUpAfterMaxRetriesAndReportsRetryAfter() async {
        let clock = FakeClock()
        let transport = sequence([response(429, headers: ["Retry-After": "3"])])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(retries: 2), clock: clock)
        do {
            _ = try await queue.send(request)
            XCTFail("expected rateLimited")
        } catch {
            XCTAssertEqual(error as? MetadataError, .rateLimited(retryAfter: 3))
        }
        XCTAssertEqual(transport.count, 3) // first try plus two retries
    }

    func testServerErrorsBackOffExponentiallyThenSucceed() async throws {
        let clock = FakeClock()
        let transport = sequence([response(503), response(500), response(502), response(200)])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(retries: 4, base: 1), clock: clock)
        let r = try await queue.send(request)
        XCTAssertEqual(r.statusCode, 200)
        XCTAssertEqual(clock.sleeps, [1, 2, 4])
    }

    func testBackoffIsCapped() async {
        let clock = FakeClock()
        let transport = sequence([response(500)])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(retries: 5, base: 1, max: 4), clock: clock)
        _ = try? await queue.send(request)
        XCTAssertEqual(clock.sleeps, [1, 2, 4, 4, 4])
    }

    func testServerErrorExhaustionThrowsServerStatus() async {
        let queue = ProviderQueue(transport: sequence([response(504)]), configuration: plainQueue(retries: 1), clock: FakeClock())
        do {
            _ = try await queue.send(request)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MetadataError, .server(504))
        }
    }

    func testJitterShortensDelaysByTheRandomFraction() async throws {
        let clock = FakeClock()
        let transport = sequence([response(500), response(200)])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(base: 10, jitter: 0.5), clock: clock, random: { 0.5 })
        _ = try await queue.send(request)
        XCTAssertEqual(clock.sleeps.count, 1)
        XCTAssertEqual(clock.sleeps[0], 7.5, accuracy: 0.0001) // 10 * (1 - 0.5 * 0.5)
    }

    func testNetworkErrorsAreRetriedThenReported() async throws {
        struct Down: Error {}
        let clock = FakeClock()
        let attempts = AttemptCounter()
        let transport = MockTransport { _ in
            let n = attempts.increment()
            if n < 3 { throw Down() }
            return HTTPResponse(statusCode: 200)
        }
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(), clock: clock)
        let r = try await queue.send(request)
        XCTAssertEqual(r.statusCode, 200)
        XCTAssertEqual(clock.sleeps, [1, 2])

        let dead = MockTransport { _ in throw Down() }
        let queue2 = ProviderQueue(transport: dead, configuration: plainQueue(retries: 2), clock: FakeClock())
        do {
            _ = try await queue2.send(request)
            XCTFail("expected an error")
        } catch let error as MetadataError {
            guard case .network = error else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual(dead.count, 3)
        }
    }

    final class AttemptCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func increment() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    }

    func testCancellationBeforeSendingStopsWithoutCallingTheTransport() async {
        let transport = sequence([response(200)])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(), clock: FakeClock())
        let req = request
        let task = Task { () async throws -> HTTPResponse in
            while !Task.isCancelled { await Task.yield() }
            return try await queue.send(req)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(transport.count, 0)
    }

    func testCancellationThrownByTheTransportIsNotRetried() async {
        let transport = MockTransport { _ in throw CancellationError() }
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(), clock: FakeClock())
        do {
            _ = try await queue.send(request)
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(transport.count, 1)
    }

    func testDailyQuotaStopsRequestsWithoutSendingAndResetsNextDay() async throws {
        let clock = FakeClock(start: Date(timeIntervalSince1970: 86_400 * 100 + 100))
        let transport = sequence([response(200)])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(daily: 2), clock: clock)
        _ = try await queue.send(request)
        _ = try await queue.send(request)
        do {
            _ = try await queue.send(request)
            XCTFail("expected quotaExhausted")
        } catch {
            XCTAssertEqual(error as? MetadataError, .quotaExhausted)
        }
        XCTAssertEqual(transport.count, 2)
        clock.advance(86_400)
        _ = try await queue.send(request)
        XCTAssertEqual(transport.count, 3)
    }

    func testRequestsSentCountsEveryAttempt() async throws {
        let transport = sequence([response(500), response(200)])
        let queue = ProviderQueue(transport: transport, configuration: plainQueue(), clock: FakeClock())
        _ = try await queue.send(request)
        let sent = await queue.requestsSent
        XCTAssertEqual(sent, 2)
    }

    func testPresetsMatchTheDocumentedLimits() {
        XCTAssertEqual(QueueConfiguration.omdb.dailyLimit, 1000)
        XCTAssertNil(QueueConfiguration.tmdb.dailyLimit)
        XCTAssertLessThan(QueueConfiguration.tmdb.minInterval, 0.1)
    }
}
