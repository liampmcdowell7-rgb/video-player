import Foundation
import AppLogic
import LibraryIndex
import PlaybackLogic

/// Everything the player needs to start one item. R311: `@unchecked Sendable` so the start can be timed by
/// `PlaybackStartWatch` (it crosses one task boundary; `remux` is main-actor isolated and only used there).
struct ResolvedPlayback: @unchecked Sendable {
    var url: URL
    var headers: [String: String]
    var title: String
    var subtitle: String?
    var startAt: TimeInterval
    var duration: TimeInterval?
    var content: NowPlayingContent
    /// Intro, recap and credits ranges for this item (`SegmentService.segments(forItem:)`). Empty when there are none.
    var segments: [Segment] = []
    /// Set when the file is played through the converting player; `url` is then its loopback address. The player screen stops it.
    var remux: RemuxPlayback?
    /// The library file being played (R309: the Plex watch sync reports to its server, or to the Plex files of the same item).
    var file: StoredFile?
    /// R319: the details key whose content rating the Info tab shows ("series-N" for an episode, `PlayerRating.detailsKey`).
    var ratingKey: String?
    /// R380: the rating set on the item before playback starts (`PlayerRating.atStart`), nil when none was on hand.
    var startRating: PlayerRating.Choice?
}

/// Why an item cannot be played. Every case maps to plain text and a what-to-do line (`failure`); the text is the whole message.
enum PlaybackError: LocalizedError, Equatable {
    case noFile
    case sourceUnavailable
    case notReadable

    var failure: PlaybackFailure {
        switch self {
        case .noFile: return PlaybackFailures.noFile
        case .sourceUnavailable: return PlaybackFailures.sourceGone
        case .notReadable: return PlaybackFailures.readFailed(detail: "The server did not give a link the player can open.")
        }
    }

    var errorDescription: String? { failure.text }
}

/// Turns anything the playback path throws into the text the error screen shows.
enum PlaybackFailureMapper {
    static func failure(for error: Error) -> PlaybackFailure {
        if let failure = error as? PlaybackFailure { return failure }
        if let error = error as? PlaybackError { return error.failure }
        return PlaybackFailures.map(error)
    }
}

/// How a file is played: straight by the system player, through the converting player, or not at all (with the reason).
enum PlaybackRoute: Equatable {
    case direct
    case remux
    case unsupported(PlaybackFailure)

    static func route(fileName: String) -> PlaybackRoute {
        if DirectContainers.isDirect(fileName: fileName) { return .direct }
        if PlaybackFailures.canRemux(fileName: fileName) { return .remux }
        return .unsupported(PlaybackFailures.unsupportedContainer(fileExtension: (fileName as NSString).pathExtension))
    }
}

/// Containers the system player opens without the converting engine.
enum DirectContainers {
    static let extensions: Set<String> = ["mp4", "m4v", "mov", "m3u8"]
    static func isDirect(fileName: String) -> Bool {
        extensions.contains((fileName as NSString).pathExtension.lowercased())
    }
}
