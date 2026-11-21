import Foundation

// Two-way watch state with a media server (OPEN_QUESTIONS R306 b, decided by the owner 21 Nov 2026; R308). Only Plex
// implements it (`PlexWatchWriter` in SourcePlex); the app's logic (AppLogic) talks to this protocol, so it never needs
// to know a server's paths or headers.

/// What the player is doing, in the words the server's timeline uses.
public enum ServerPlaybackState: String, Equatable, Sendable {
    case playing, paused, buffering, stopped
}

/// One report of playback progress for one item on the server.
public struct ServerTimelineReport: Equatable, Sendable {
    /// The server's own id of the item (Plex: `ratingKey`).
    public var itemKey: String
    public var state: ServerPlaybackState
    /// Seconds from the start.
    public var position: Double
    /// Seconds, when known.
    public var duration: Double?
    /// With `.stopped` only: whether another item plays next.
    public var continuing: Bool?
    /// One value per playback session.
    public var sessionIdentifier: String?
    /// Set when the report is sent later than it happened (the server could not be reached at the time): when the state
    /// was last updated. Nil for a live report.
    public var offlineUpdated: Date?

    public init(itemKey: String, state: ServerPlaybackState, position: Double, duration: Double? = nil, continuing: Bool? = nil,
                sessionIdentifier: String? = nil, offlineUpdated: Date? = nil) {
        self.itemKey = itemKey
        self.state = state
        self.position = position
        self.duration = duration
        self.continuing = continuing
        self.sessionIdentifier = sessionIdentifier
        self.offlineUpdated = offlineUpdated
    }
}

/// Writes watch state to a media server. Every call is one request; a thrown error means it did not arrive (or the server
/// refused it).
public protocol ServerWatchWriting: Sendable {
    func report(_ report: ServerTimelineReport) async throws
    func markPlayed(itemKey: String) async throws
    func markUnplayed(itemKey: String) async throws
}

/// When a playback report is due (R308). Plex, read 21 Nov 2026 in the PMS reference's OpenAPI file: the timeline "must
/// be hit whenever the play state changes, or in the absence of a play state change, in a regular fashion (generally this
/// means every 10 seconds on a LAN/WAN, and every 20 seconds over cellular)". An Apple TV is never on cellular: 10 seconds.
public struct ServerTimelineRhythm: Equatable, Sendable {
    public static let interval: TimeInterval = 10

    public let interval: TimeInterval
    public private(set) var lastState: ServerPlaybackState?
    public private(set) var lastSent: Date?

    public init(interval: TimeInterval = ServerTimelineRhythm.interval) {
        self.interval = interval
    }

    /// True (and remembered as sent) when the state changed since the last report, or the interval has passed.
    public mutating func isDue(_ state: ServerPlaybackState, at now: Date) -> Bool {
        let due: Bool
        if let lastSent, let lastState, lastState == state {
            due = now.timeIntervalSince(lastSent) >= interval
        } else {
            due = true
        }
        if due {
            lastState = state
            lastSent = now
        }
        return due
    }
}

/// A source whose server keeps its own watch state and accepts writes to it (Plex; R309). The app's sync asks it for the
/// writer and for the server's id of a file; it never needs to know which server kind it is.
public protocol ServerWatchSource: Sendable {
    /// The writer for this server (one per server address and token).
    var watchWriter: any ServerWatchWriting { get }
    /// The server's own id of the item a file belongs to (Plex: `ratingKey`), nil when the server does not list the file.
    func serverItemKey(at path: String) async throws -> String?
    /// What the server knows about one file (R310), nil when it does not list the file.
    func serverWatchState(at path: String) async throws -> ServerWatchState?
    /// What the server knows about every file it lists, by path (R310: the merge after a scan).
    func serverWatchStates() async throws -> [String: ServerWatchState]
}

/// The server's own watch state of one file (R310).
public struct ServerWatchState: Equatable, Sendable {
    /// The server's id of the item (Plex: `ratingKey`).
    public var itemKey: String
    /// Played at least once (Plex: `viewCount` > 0).
    public var played: Bool
    /// The resume point in seconds (Plex: `viewOffset`), nil when none.
    public var position: Double?
    /// When it was last watched (Plex: `lastViewedAt`).
    public var lastViewedAt: Date?
    public var duration: Double?

    public init(itemKey: String, played: Bool, position: Double? = nil, lastViewedAt: Date? = nil, duration: Double? = nil) {
        self.itemKey = itemKey
        self.played = played
        self.position = position
        self.lastViewedAt = lastViewedAt
        self.duration = duration
    }
}
