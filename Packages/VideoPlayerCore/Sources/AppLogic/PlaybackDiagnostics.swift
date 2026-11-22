import Foundation

// R386 (owner's device test, 22 Nov 2026: playback starts, then fails about 30 seconds in, and the message could not be
// read). The pure part, tested on Linux:
//  - `PlayerErrorReport`: the system player's error as domain, code, message and the chain of underlying errors, in plain
//    text the owner can read off the TV and photograph;
//  - `PlaybackEvent` and `PlaybackEventLog`: what the player did last, with the playhead, the seconds since the player got
//    the file and the clock time;
//  - `PlaybackStartProgress`: when the start counts as playing (the start's 30-second limit must never fire on a video that
//    is already moving).

/// The system player's error, as the failure screen and Settings > Playback show it (R386).
public struct PlayerErrorReport: Codable, Equatable, Sendable {
    public var domain: String
    public var code: Int
    public var message: String
    /// The underlying errors, outermost first, each "Domain code: message".
    public var underlying: [String]

    public init(domain: String, code: Int, message: String, underlying: [String] = []) {
        self.domain = domain
        self.code = code
        self.message = message
        self.underlying = underlying
    }

    /// The deepest number of underlying errors followed (a chain is short; a loop must not hang the report).
    public static let maxDepth = 4

    /// From an error, following `NSUnderlyingErrorKey`.
    public init(_ error: NSError) {
        var chain: [String] = []
        var next = error.userInfo[NSUnderlyingErrorKey] as? NSError
        while let inner = next, chain.count < Self.maxDepth {
            chain.append(Self.line(domain: inner.domain, code: inner.code, message: inner.localizedDescription))
            next = inner.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        self.init(domain: error.domain, code: error.code, message: error.localizedDescription, underlying: chain)
    }

    /// "Domain code: message", the message left out when empty.
    public static func line(domain: String, code: Int, message: String) -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "\(domain) \(code)" : "\(domain) \(code): \(text)"
    }

    /// "Domain code", for the Error Code row.
    public var codeLine: String { "\(domain) \(code)" }
    /// The underlying errors on one line each, or "None" when the error had none.
    public var underlyingText: String { underlying.isEmpty ? Self.noUnderlying : underlying.joined(separator: "\n") }
    public static let noUnderlying = "None"

    /// The same with every string passed through `transform` (token removal).
    public func mapped(_ transform: (String) -> String) -> PlayerErrorReport {
        PlayerErrorReport(domain: domain, code: code, message: transform(message), underlying: underlying.map(transform))
    }
}

/// One thing the player did (R386).
public struct PlaybackEvent: Codable, Equatable, Sendable {
    /// What happened ("Stalled: the media did not arrive in time", "Play state: waiting (to minimize stalls)").
    public var name: String
    /// The playhead in seconds, nil when not known.
    public var position: Double?
    /// Seconds since the player got the file, nil when not known.
    public var elapsed: Double?
    public var at: Date

    public init(name: String, position: Double?, elapsed: Double?, at: Date) {
        self.name = name
        self.position = position
        self.elapsed = elapsed
        self.at = at
    }

    /// "Stalled · video at 0:31 · 33 s after the player opened · 21:04:05", what is not known left out.
    public func line(timeZone: TimeZone = .current) -> String {
        var parts = [name]
        if let position, position.isFinite, position >= 0 { parts.append("video at " + Self.clock(position)) }
        if let elapsed, elapsed.isFinite, elapsed >= 0 { parts.append("\(Int(elapsed.rounded())) s after the player opened") }
        parts.append(Self.time(at, timeZone: timeZone))
        return parts.joined(separator: " · ")
    }

    /// "0:31", "1:02:03".
    public static func clock(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// The clock time "21:04:05" (24-hour, so it reads the same in every region).
    public static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

/// The player's recent events, newest last (R386). The player screen owns one per playback.
public final class PlaybackEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [PlaybackEvent] = []
    public let capacity: Int

    public init(capacity: Int = 12) { self.capacity = max(1, capacity) }

    public func record(_ name: String, position: Double?, elapsed: Double?, at date: Date = Date()) {
        let event = PlaybackEvent(name: name, position: position, elapsed: elapsed, at: date)
        lock.withLock {
            kept.append(event)
            if kept.count > capacity { kept.removeFirst(kept.count - capacity) }
        }
    }

    public var last: PlaybackEvent? { lock.withLock { kept.last } }
    public var recent: [PlaybackEvent] { lock.withLock { kept } }
}

/// What a failed playback hands to the screen and to Settings (R386).
public struct PlaybackDiagnostics: Sendable {
    /// The system player's own words (item error, error log, item status, play state), as before (R311).
    public var detail: String?
    public var player: PlayerErrorReport?
    public var events: [PlaybackEvent]

    public init(detail: String? = nil, player: PlayerErrorReport? = nil, events: [PlaybackEvent] = []) {
        self.detail = detail
        self.player = player
        self.events = events
    }
}

/// When the start of playback counts as playing (R386). Before, only a CHANGE of the player's play state seen after `play()`
/// ended the start: a player that was already playing by then (Play pressed on the remote during the move to the saved
/// position) sent no change, the start stayed at "Starting playback", and its 30-second limit ended a playing video.
public enum PlaybackStartProgress {
    /// The playhead must move this far past where play was asked for to count as moving pictures.
    public static let movedSeconds: Double = 0.5

    /// True when the player says it is playing, or the playhead has moved on since play was asked for.
    public static func hasStarted(isPlaying: Bool, positionAtPlay: Double?, position: Double?) -> Bool {
        if isPlaying { return true }
        guard let start = positionAtPlay, let now = position, start.isFinite, now.isFinite else { return false }
        return now - start >= movedSeconds
    }
}
