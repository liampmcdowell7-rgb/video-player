#if os(tvOS) && canImport(MediaPlayer) && canImport(UIKit)
import Foundation
import MediaPlayer
import UIKit

// NEVER COMPILED. Written from Apple's documentation (MPNowPlayingInfoCenter, MPRemoteCommandCenter) without a Mac.
// It contains no decisions: `NowPlayingMapper` and `RemoteCommandPlanner` (tested in WSL) decide every value, this file
// copies them into the system objects, one switch each. First compile happens on Codemagic; see docs/DEVICE_TEST_CHECKLIST.md.
//
// When the player is an AVPlayerViewController, set `updatesNowPlayingInfoCenter = false` on it, or the system and this
// publisher overwrite each other's entry.

/// A remote command that came from the system UI.
public enum SystemRemoteCommand: Equatable, Sendable {
    case play, pause, togglePlayPause, nextTrack
    case skip(by: TimeInterval)
    case seek(to: TimeInterval)
}

public final class NowPlayingCenterPublisher: NowPlayingPublishing, @unchecked Sendable {
    private let lock = NSLock()
    private let artwork: @Sendable (String) -> UIImage?
    private var tokens: [(MPRemoteCommand, Any)] = []
    private var onCommand: (@Sendable (SystemRemoteCommand) -> Void)?

    /// `artwork` resolves an `artworkKey` to an image (nil = none). `onCommand` receives what the user did in the system UI.
    public init(artwork: @escaping @Sendable (String) -> UIImage?, onCommand: @escaping @Sendable (SystemRemoteCommand) -> Void) {
        self.artwork = artwork
        self.onCommand = onCommand
        installHandlers()
    }

    deinit {
        for (command, token) in tokens { command.removeTarget(token) }
    }

    // MARK: NowPlayingPublishing

    public func publish(_ snapshot: NowPlayingSnapshot) {
        var info: [String: Any] = [:]
        for (field, value) in snapshot.fields {
            switch (field, value) {
            case (.title, .string(let s)): info[MPMediaItemPropertyTitle] = s
            case (.artist, .string(let s)): info[MPMediaItemPropertyArtist] = s
            case (.albumTitle, .string(let s)): info[MPMediaItemPropertyAlbumTitle] = s
            case (.albumTrackNumber, .number(let n)): info[MPMediaItemPropertyAlbumTrackNumber] = n
            case (.playbackDuration, .number(let n)): info[MPMediaItemPropertyPlaybackDuration] = n
            case (.elapsedPlaybackTime, .number(let n)): info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = n
            case (.playbackRate, .number(let n)): info[MPNowPlayingInfoPropertyPlaybackRate] = n
            case (.defaultPlaybackRate, .number(let n)): info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = n
            case (.mediaType, .mediaTypeVideo): info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
            case (.externalContentIdentifier, .string(let s)): info[MPNowPlayingInfoPropertyExternalContentIdentifier] = s
            case (.artwork, .artworkKey(let key)):
                if let image = artwork(key) {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
            default: break
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    public func apply(_ commands: RemoteCommandState) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = commands.play
        center.pauseCommand.isEnabled = commands.pause
        center.togglePlayPauseCommand.isEnabled = commands.togglePlayPause
        if let forward = commands.skipForwardInterval {
            center.skipForwardCommand.preferredIntervals = [NSNumber(value: forward)]
            center.skipForwardCommand.isEnabled = true
        } else {
            center.skipForwardCommand.isEnabled = false
        }
        if let backward = commands.skipBackwardInterval {
            center.skipBackwardCommand.preferredIntervals = [NSNumber(value: backward)]
            center.skipBackwardCommand.isEnabled = true
        } else {
            center.skipBackwardCommand.isEnabled = false
        }
        center.changePlaybackPositionCommand.isEnabled = commands.changePlaybackPosition
        center.nextTrackCommand.isEnabled = commands.nextTrack
        center.previousTrackCommand.isEnabled = commands.previousTrack
    }

    public func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Handlers (installed once; they only forward)

    private func installHandlers() {
        let center = MPRemoteCommandCenter.shared()
        func add(_ command: MPRemoteCommand, _ map: @escaping @Sendable (MPRemoteCommandEvent) -> SystemRemoteCommand?) {
            let token = command.addTarget { [weak self] event in
                guard let self, let send = self.lock.withLock({ self.onCommand }), let mapped = map(event) else { return .commandFailed }
                send(mapped)
                return .success
            }
            tokens.append((command, token))
        }
        add(center.playCommand) { _ in .play }
        add(center.pauseCommand) { _ in .pause }
        add(center.togglePlayPauseCommand) { _ in .togglePlayPause }
        add(center.nextTrackCommand) { _ in .nextTrack }
        add(center.skipForwardCommand) { e in (e as? MPSkipIntervalCommandEvent).map { .skip(by: $0.interval) } }
        add(center.skipBackwardCommand) { e in (e as? MPSkipIntervalCommandEvent).map { .skip(by: -$0.interval) } }
        add(center.changePlaybackPositionCommand) { e in (e as? MPChangePlaybackPositionCommandEvent).map { .seek(to: $0.positionTime) } }
    }
}
#endif
