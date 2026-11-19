import Foundation
import VideoPlayerCore

/// Time source and sleeper. The app uses `SystemMetadataClock`; tests use a fake that never really waits.
public protocol MetadataClock: Sendable {
    func now() -> Date
    func sleep(seconds: Double) async throws
}

public struct SystemMetadataClock: MetadataClock {
    public init() {}
    public func now() -> Date { Date() }
    public func sleep(seconds: Double) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

public struct QueueConfiguration: Sendable, Equatable {
    /// Minimum seconds between the start of two requests.
    public var minInterval: Double
    /// Retries after the first attempt (so up to `maxRetries + 1` attempts).
    public var maxRetries: Int
    public var baseBackoff: Double
    public var maxBackoff: Double
    /// 0 means exact delays; 0.5 means a delay is randomly shortened by up to 50 percent.
    public var jitter: Double
    /// Requests allowed per UTC day, nil for no daily limit.
    public var dailyLimit: Int?

    public init(minInterval: Double = 0, maxRetries: Int = 4, baseBackoff: Double = 1, maxBackoff: Double = 30, jitter: Double = 0.25, dailyLimit: Int? = nil) {
        self.minInterval = max(0, minInterval)
        self.maxRetries = max(0, maxRetries)
        self.baseBackoff = max(0, baseBackoff)
        self.maxBackoff = max(baseBackoff, maxBackoff)
        self.jitter = min(1, max(0, jitter))
        self.dailyLimit = dailyLimit
    }

    /// TMDB asks for fewer than about 50 requests per second; we stay far below that.
    public static let tmdb = QueueConfiguration(minInterval: 0.05, maxRetries: 4, baseBackoff: 1, maxBackoff: 30)
}

/// Sends requests for one provider one slot at a time, with spacing, retries and back-off.
/// Responses with other 4xx statuses are returned unchanged for the client to interpret.
public actor ProviderQueue {
    private let transport: any HTTPTransport
    private let configuration: QueueConfiguration
    private let clock: any MetadataClock
    private let random: @Sendable () -> Double
    private var nextSlot: Date
    private var dayNumber: Int
    private var sentToday = 0
    public private(set) var requestsSent = 0

    public init(
        transport: any HTTPTransport,
        configuration: QueueConfiguration,
        clock: any MetadataClock = SystemMetadataClock(),
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.transport = transport
        self.configuration = configuration
        self.clock = clock
        self.random = random
        let now = clock.now()
        self.nextSlot = now
        self.dayNumber = ProviderQueue.day(of: now)
    }

    private static func day(of date: Date) -> Int { Int((date.timeIntervalSince1970 / 86_400).rounded(.down)) }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            try checkQuota()
            try await waitForSlot()
            requestsSent += 1
            sentToday += 1

            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt >= configuration.maxRetries { throw MetadataError.network(String(describing: error)) }
                try await clock.sleep(seconds: backoff(attempt))
                attempt += 1
                continue
            }

            switch response.statusCode {
            case 429:
                let wait = Self.retryAfter(response, now: clock.now())
                if attempt >= configuration.maxRetries { throw MetadataError.rateLimited(retryAfter: wait) }
                let delay = wait ?? backoff(attempt)
                // Everyone waiting behind this request also waits.
                nextSlot = max(nextSlot, clock.now().addingTimeInterval(delay))
                attempt += 1
            case 500...599:
                if attempt >= configuration.maxRetries { throw MetadataError.server(response.statusCode) }
                try await clock.sleep(seconds: backoff(attempt))
                attempt += 1
            default:
                return response
            }
        }
    }

    private func checkQuota() throws {
        guard let limit = configuration.dailyLimit else { return }
        let today = Self.day(of: clock.now())
        if today != dayNumber { dayNumber = today; sentToday = 0 }
        if sentToday >= limit { throw MetadataError.quotaExhausted }
    }

    private func waitForSlot() async throws {
        let now = clock.now()
        let start = max(now, nextSlot)
        nextSlot = start.addingTimeInterval(configuration.minInterval)
        let wait = start.timeIntervalSince(now)
        if wait > 0 { try await clock.sleep(seconds: wait) }
    }

    func backoff(_ attempt: Int) -> Double {
        let raw = min(configuration.maxBackoff, configuration.baseBackoff * pow(2, Double(attempt)))
        return raw * (1 - configuration.jitter * random())
    }

    /// `Retry-After` as seconds or as an HTTP date.
    static func retryAfter(_ response: HTTPResponse, now: Date) -> Double? {
        guard let value = response.header("retry-after")?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Double(value), seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) { return max(0, date.timeIntervalSince(now)) }
        return nil
    }
}
