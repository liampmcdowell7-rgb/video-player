import AVFoundation
import MediaPlayer
import AppLogic

/// Writes the Now Playing entry and turns the remote commands on or off. All decisions are made in AppLogic
/// (`NowPlayingMapper`, `RemoteCommandPlanner`); this class only maps each field and command to its system key.
final class NowPlayingCenterPublisher: NowPlayingPublishing, @unchecked Sendable {
    private weak var player: AVPlayer?

    init(player: AVPlayer) {
        self.player = player
    }

    func publish(_ snapshot: NowPlayingSnapshot) {
        var info: [String: Any] = [:]
        for (field, value) in snapshot.fields {
            let key = Self.key(for: field)
            switch value {
            case .string(let text): info[key] = text
            case .number(let number): info[key] = number
            case .mediaTypeVideo: info[key] = MPNowPlayingInfoMediaType.video.rawValue
            case .artworkKey: break
            }
        }
        DispatchQueue.main.async { MPNowPlayingInfoCenter.default().nowPlayingInfo = info }
    }

    func clear() {
        DispatchQueue.main.async { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }

    func apply(_ commands: RemoteCommandState) {
        DispatchQueue.main.async { [weak self] in self?.configure(commands) }
    }

    private static func key(for field: NowPlayingField) -> String {
        switch field {
        case .title: return MPMediaItemPropertyTitle
        case .artist: return MPMediaItemPropertyArtist
        case .albumTitle: return MPMediaItemPropertyAlbumTitle
        case .albumTrackNumber: return MPMediaItemPropertyAlbumTrackNumber
        case .playbackDuration: return MPMediaItemPropertyPlaybackDuration
        case .elapsedPlaybackTime: return MPNowPlayingInfoPropertyElapsedPlaybackTime
        case .playbackRate: return MPNowPlayingInfoPropertyPlaybackRate
        case .defaultPlaybackRate: return MPNowPlayingInfoPropertyDefaultPlaybackRate
        case .mediaType: return MPNowPlayingInfoPropertyMediaType
        case .externalContentIdentifier: return MPNowPlayingInfoPropertyExternalContentIdentifier
        case .artwork: return MPMediaItemPropertyArtwork
        }
    }

    private func configure(_ state: RemoteCommandState) {
        let center = MPRemoteCommandCenter.shared()
        set(center.playCommand, enabled: state.play) { $0.player?.play() }
        set(center.pauseCommand, enabled: state.pause) { $0.player?.pause() }
        set(center.togglePlayPauseCommand, enabled: state.togglePlayPause) { me in
            guard let player = me.player else { return }
            if player.rate == 0 { player.play() } else { player.pause() }
        }
        if let interval = state.skipForwardInterval {
            center.skipForwardCommand.preferredIntervals = [NSNumber(value: interval)]
        }
        if let interval = state.skipBackwardInterval {
            center.skipBackwardCommand.preferredIntervals = [NSNumber(value: interval)]
        }
        set(center.skipForwardCommand, enabled: state.skipForwardInterval != nil) { $0.jump(by: $0.forwardInterval(state)) }
        set(center.skipBackwardCommand, enabled: state.skipBackwardInterval != nil) { $0.jump(by: -$0.backwardInterval(state)) }
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.isEnabled = state.changePlaybackPosition
        if state.changePlaybackPosition {
            center.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                self?.player?.seek(to: CMTime(seconds: event.positionTime, preferredTimescale: 600))
                return .success
            }
        }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    private func set(_ command: MPRemoteCommand, enabled: Bool, action: @escaping (NowPlayingCenterPublisher) -> Void) {
        command.removeTarget(nil)
        command.isEnabled = enabled
        guard enabled else { return }
        command.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            action(self)
            return .success
        }
    }

    private func forwardInterval(_ state: RemoteCommandState) -> TimeInterval { state.skipForwardInterval ?? 10 }
    private func backwardInterval(_ state: RemoteCommandState) -> TimeInterval { state.skipBackwardInterval ?? 10 }

    private func jump(by seconds: TimeInterval) {
        guard let player else { return }
        let target = player.currentTime().seconds + seconds
        player.seek(to: CMTime(seconds: max(0, target), preferredTimescale: 600))
    }
}
