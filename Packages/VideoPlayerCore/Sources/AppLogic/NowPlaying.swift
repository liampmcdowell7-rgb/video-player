import Foundation
import PlaybackLogic

// Now Playing: what the Apple TV's system UI (Control Center, the Siri Remote, the TV app's "now playing" tile) shows,
// and which remote commands are on. This file is the pure mapping. The Apple wrapper (Apple/NowPlayingCenterPublisher.swift,
// never compiled) turns a `NowPlayingSnapshot` into MPNowPlayingInfoCenter keys and a `RemoteCommandState` into
// MPRemoteCommandCenter commands, one switch each, no logic.

// MARK: Snapshot

/// One entry of the Now Playing dictionary. `symbolName` is the MediaPlayer constant the Apple wrapper maps it to; it is a
/// documentation string only (the raw values of those constants are not documented, so nothing here relies on them).
public enum NowPlayingField: String, CaseIterable, Sendable {
    case title, artist, albumTitle, albumTrackNumber, playbackDuration, elapsedPlaybackTime
    case playbackRate, defaultPlaybackRate, mediaType, externalContentIdentifier, artwork

    public var symbolName: String {
        switch self {
        case .title: return "MPMediaItemPropertyTitle"
        case .artist: return "MPMediaItemPropertyArtist"
        case .albumTitle: return "MPMediaItemPropertyAlbumTitle"
        case .albumTrackNumber: return "MPMediaItemPropertyAlbumTrackNumber"
        case .playbackDuration: return "MPMediaItemPropertyPlaybackDuration"
        case .elapsedPlaybackTime: return "MPNowPlayingInfoPropertyElapsedPlaybackTime"
        case .playbackRate: return "MPNowPlayingInfoPropertyPlaybackRate"
        case .defaultPlaybackRate: return "MPNowPlayingInfoPropertyDefaultPlaybackRate"
        case .mediaType: return "MPNowPlayingInfoPropertyMediaType"
        case .externalContentIdentifier: return "MPNowPlayingInfoPropertyExternalContentIdentifier"
        case .artwork: return "MPMediaItemPropertyArtwork"
        }
    }
}

public enum NowPlayingValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    /// The value is "this is video" (the wrapper maps it to MPNowPlayingInfoMediaType.video).
    case mediaTypeVideo
    /// An opaque key the app resolves to an image (the wrapper builds the MPMediaItemArtwork from it).
    case artworkKey(String)
}

public struct NowPlayingSnapshot: Equatable, Sendable {
    public var fields: [NowPlayingField: NowPlayingValue]

    public init(fields: [NowPlayingField: NowPlayingValue]) { self.fields = fields }

    public subscript(field: NowPlayingField) -> NowPlayingValue? { fields[field] }
}

/// What is playing, in the library's own words (no Apple types).
public struct NowPlayingContent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case movie, episode }
    public var kind: Kind
    /// Movie title, or episode title (may be empty or nil for an episode that has none).
    public var title: String?
    public var seriesTitle: String?
    public var season: Int?
    public var episode: Int?
    public var year: Int?
    /// Key of the poster or episode still the app can load ("item-42"); nil = no artwork.
    public var artworkKey: String?
    /// A stable id (the library item id) so the system can tell titles apart.
    public var externalID: String?

    public init(kind: Kind, title: String?, seriesTitle: String? = nil, season: Int? = nil, episode: Int? = nil,
                year: Int? = nil, artworkKey: String? = nil, externalID: String? = nil) {
        self.kind = kind
        self.title = title
        self.seriesTitle = seriesTitle
        self.season = season
        self.episode = episode
        self.year = year
        self.artworkKey = artworkKey
        self.externalID = externalID
    }
}

public enum NowPlayingMapper {
    /// Builds the dictionary. `duration` and `position` are seconds; `rate` is 1 playing, 0 paused (other rates pass through).
    ///
    /// Interpretation (PROVISIONAL, no spec text): an episode shows its own title, the series name as the second line (artist
    /// slot) and "Season N" (or "Specials") as the album line; a movie shows only its title. A file with no title at all falls
    /// back to "Untitled" so the system never shows an empty row.
    public static func snapshot(_ content: NowPlayingContent, duration: TimeInterval?, position: TimeInterval, rate: Double) -> NowPlayingSnapshot {
        var f: [NowPlayingField: NowPlayingValue] = [:]
        f[.mediaType] = .mediaTypeVideo
        switch content.kind {
        case .movie:
            f[.title] = .string(nonEmpty(content.title) ?? "Untitled")
        case .episode:
            let episodeTitle = nonEmpty(content.title)
                ?? content.episode.map { "Episode \($0)" } ?? "Untitled"
            f[.title] = .string(episodeTitle)
            if let series = nonEmpty(content.seriesTitle) { f[.artist] = .string(series) }
            if let season = content.season { f[.albumTitle] = .string(season == 0 ? "Specials" : "Season \(season)") }
            if let ep = content.episode { f[.albumTrackNumber] = .number(Double(ep)) }
        }
        if let duration, duration > 0 { f[.playbackDuration] = .number(duration) }
        f[.elapsedPlaybackTime] = .number(max(0, min(position, duration ?? position)))
        f[.playbackRate] = .number(rate)
        f[.defaultPlaybackRate] = .number(1)
        if let id = content.externalID { f[.externalContentIdentifier] = .string(id) }
        if let key = content.artworkKey { f[.artwork] = .artworkKey(key) }
        return NowPlayingSnapshot(fields: f)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

// MARK: Remote commands

public struct RemoteCommandState: Equatable, Sendable {
    public var play: Bool
    public var pause: Bool
    public var togglePlayPause: Bool
    /// Seconds for the skip-forward / skip-back commands; nil = command off.
    public var skipForwardInterval: TimeInterval?
    public var skipBackwardInterval: TimeInterval?
    /// Scrubbing from the system UI.
    public var changePlaybackPosition: Bool
    public var nextTrack: Bool
    public var previousTrack: Bool
}

public enum RemoteCommandPlanner {
    /// Interpretation (PROVISIONAL): 10-second skips, Next only when a next episode exists, Previous off (the player has no
    /// "previous episode"), scrubbing only when the duration is known. Everything is off when nothing is playing.
    public static func state(isPlaying: Bool, hasContent: Bool, duration: TimeInterval?, hasNextEpisode: Bool) -> RemoteCommandState {
        guard hasContent else {
            return RemoteCommandState(play: false, pause: false, togglePlayPause: false, skipForwardInterval: nil,
                                      skipBackwardInterval: nil, changePlaybackPosition: false, nextTrack: false, previousTrack: false)
        }
        let known = (duration ?? 0) > 0
        return RemoteCommandState(
            play: !isPlaying, pause: isPlaying, togglePlayPause: true,
            skipForwardInterval: known ? 10 : nil, skipBackwardInterval: known ? 10 : nil,
            changePlaybackPosition: known, nextTrack: hasNextEpisode, previousTrack: false)
    }
}

// MARK: Publishing

public protocol NowPlayingPublishing: AnyObject, Sendable {
    func publish(_ snapshot: NowPlayingSnapshot)
    func apply(_ commands: RemoteCommandState)
    /// Removes the Now Playing entry (playback stopped).
    func clear()
}

/// Keeps the system entry current without flooding it: the system extrapolates the elapsed time from the last
/// snapshot's time and rate, so a new snapshot is only sent when the rate changes, the user jumps, or the entry has
/// not been refreshed for a while.
public final class NowPlayingSession: @unchecked Sendable {
    private let publisher: any NowPlayingPublishing
    private let clock: any PlaybackClock
    private let lock = NSLock()
    private var content: NowPlayingContent?
    private var duration: TimeInterval?
    private var hasNext = false
    private var lastPosition = 0.0
    private var lastRate = 0.0
    private var lastSentAt = 0.0
    private var started = false

    /// A position that differs from what the system would extrapolate by more than this many seconds is a jump.
    public static let jumpTolerance: TimeInterval = 1.5
    /// Refresh at least this often while playing (keeps the entry honest if the system drifted).
    public static let refreshInterval: TimeInterval = 30

    public init(publisher: any NowPlayingPublishing, clock: any PlaybackClock) {
        self.publisher = publisher
        self.clock = clock
    }

    public func start(_ content: NowPlayingContent, duration: TimeInterval?, hasNextEpisode: Bool, position: TimeInterval = 0, rate: Double = 0) {
        lock.lock(); defer { lock.unlock() }
        self.content = content
        self.duration = duration
        self.hasNext = hasNextEpisode
        started = true
        send(position: position, rate: rate)
        publisher.apply(RemoteCommandPlanner.state(isPlaying: rate > 0, hasContent: true, duration: duration, hasNextEpisode: hasNextEpisode))
    }

    /// Call on every playhead update, rate change and seek.
    public func update(position: TimeInterval, rate: Double) {
        lock.lock(); defer { lock.unlock() }
        guard started else { return }
        let elapsed = clock.now - lastSentAt
        let expected = lastPosition + elapsed * lastRate
        let rateChanged = rate != lastRate
        let jumped = abs(position - expected) > Self.jumpTolerance
        let stale = rate > 0 && elapsed >= Self.refreshInterval
        guard rateChanged || jumped || stale else { return }
        send(position: position, rate: rate)
        if rateChanged {
            publisher.apply(RemoteCommandPlanner.state(isPlaying: rate > 0, hasContent: true, duration: duration, hasNextEpisode: hasNext))
        }
    }

    /// The next episode became known or unknown (changes the Next command).
    public func nextEpisodeChanged(_ hasNext: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard started, hasNext != self.hasNext else { return }
        self.hasNext = hasNext
        publisher.apply(RemoteCommandPlanner.state(isPlaying: lastRate > 0, hasContent: true, duration: duration, hasNextEpisode: hasNext))
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard started else { return }
        started = false
        content = nil
        publisher.clear()
        publisher.apply(RemoteCommandPlanner.state(isPlaying: false, hasContent: false, duration: nil, hasNextEpisode: false))
    }

    private func send(position: TimeInterval, rate: Double) {
        guard let content else { return }
        lastPosition = position
        lastRate = rate
        lastSentAt = clock.now
        publisher.publish(NowPlayingMapper.snapshot(content, duration: duration, position: position, rate: rate))
    }
}
